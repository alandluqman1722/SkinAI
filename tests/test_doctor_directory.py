import asyncio
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from io import BytesIO
from unittest.mock import patch

import httpx
from fastapi import HTTPException
from PIL import Image

import app as skinai_api
import backend.doctor_directory as directory
import backend.firebase_auth as firebase_auth
from backend.firebase_auth import require_firebase_user


class _Snapshot:
    def __init__(self, path, data):
        self.path = path
        self.id = path[-1]
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return dict(self._data or {})


class _Document:
    def __init__(self, database, path):
        self.database = database
        self.path = path
        self.id = path[-1]

    def collection(self, name):
        return _Collection(self.database, self.path + (name,))

    def get(self, transaction=None):
        return _Snapshot(self.path, self.database.documents.get(self.path))

    def set(self, data, merge=False):
        if merge:
            self.database.documents.setdefault(self.path, {}).update(data)
        else:
            self.database.documents[self.path] = dict(data)

    def create(self, data):
        if self.path in self.database.documents:
            raise RuntimeError("Document already exists.")
        self.database.documents[self.path] = dict(data)

    def update(self, data):
        if self.path not in self.database.documents:
            raise RuntimeError("Document does not exist.")
        self.database.documents[self.path].update(data)

    def delete(self):
        self.database.documents.pop(self.path, None)


class _Collection:
    def __init__(self, database, path):
        self.database = database
        self.path = path
        self.filters = []
        self.maximum = None

    def document(self, document_id=None):
        return _Document(
            self.database,
            self.path + (document_id or f"generated-{len(self.database.documents)}",),
        )

    def where(self, field, operator, value):
        assert operator == "=="
        result = _Collection(self.database, self.path)
        result.filters = self.filters + [(field, value)]
        result.maximum = self.maximum
        return result

    def limit(self, maximum):
        result = _Collection(self.database, self.path)
        result.filters = list(self.filters)
        result.maximum = maximum
        return result

    def stream(self):
        records = []
        for path, data in self.database.documents.items():
            if len(path) != len(self.path) + 1 or path[: len(self.path)] != self.path:
                continue
            if any(data.get(key) != value for key, value in self.filters):
                continue
            records.append(_Snapshot(path, data))
        return records[: self.maximum] if self.maximum is not None else records


class _Transaction:
    def set(self, reference, data, merge=False):
        reference.set(data, merge=merge)

    def create(self, reference, data):
        reference.create(data)

    def update(self, reference, data):
        reference.update(data)


class _Database:
    def __init__(self):
        self.documents = {}

    def collection(self, name):
        return _Collection(self, (name,))

    def transaction(self, max_attempts=5):
        return _Transaction()


def _direct_transactional(function):
    def wrapped(transaction):
        return function(transaction)

    return wrapped


def _png_image():
    buffer = BytesIO()
    Image.new("RGB", (4, 4), color=(30, 120, 180)).save(buffer, format="PNG")
    return buffer.getvalue()


class DoctorDirectoryTests(unittest.TestCase):
    def setUp(self):
        firebase_auth._admin_rate_requests.clear()
        self.database = _Database()
        self.claims = {"uid": "patient-a"}
        self.storage = tempfile.TemporaryDirectory()
        self.storage_patch = patch.dict(
            os.environ,
            {"SKINAI_DOCTOR_STORAGE_DIR": self.storage.name},
        )
        self.storage_patch.start()
        self.database_patch = patch.object(
            directory,
            "_database",
            return_value=self.database,
        )
        self.database_patch.start()
        self.transaction_patch = patch(
            "google.cloud.firestore_v1.transactional",
            _direct_transactional,
        )
        self.transaction_patch.start()
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: self.claims
        )

    def tearDown(self):
        skinai_api.app.dependency_overrides.clear()
        self.transaction_patch.stop()
        self.database_patch.stop()
        self.storage_patch.stop()
        self.storage.cleanup()

    def _request(self, method, path, *, user_id="patient-a", admin=False, json=None, **kwargs):
        async def send():
            self.claims = {"uid": user_id, **({"admin": True} if admin else {})}
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.request(method, path, json=json, **kwargs)

        return asyncio.run(send())

    def _create_doctor(self, *, published=True):
        doctor_data = {
            "full_name": "Verified test profile",
            "qualifications": ["Medical qualification supplied by admin"],
            "specializations": ["Dermatology"],
            "experience_years": 12,
            "languages": ["English"],
            "clinics": [
                {
                    "name": "Clinic entered by admin",
                    "city": "Erbil",
                    "address": "Address entered by admin",
                    "weekly_schedule": [
                        {"weekday": weekday, "times": ["09:00", "10:00"]}
                        for weekday in range(7)
                    ],
                }
            ],
            "publication_status": "draft",
        }
        created = self._request(
            "POST",
            "/api/doctors/admin/doctors",
            admin=True,
            json=doctor_data,
        )
        self.assertEqual(created.status_code, 201, created.text)
        doctor_id = created.json()["id"]
        photo = self._request(
            "POST",
            f"/api/doctors/admin/doctors/{doctor_id}/photo",
            admin=True,
            files={"file": ("profile.png", _png_image(), "image/png")},
        )
        self.assertEqual(photo.status_code, 200, photo.text)
        if published:
            doctor_data["publication_status"] = "published"
            doctor_data["clinics"][0]["clinic_id"] = created.json()["clinics"][0][
                "clinic_id"
            ]
            updated = self._request(
                "PUT",
                f"/api/doctors/admin/doctors/{doctor_id}",
                admin=True,
                json=doctor_data,
            )
            self.assertEqual(updated.status_code, 200, updated.text)
        return doctor_id

    def _clinic_id(self, doctor_id):
        return self.database.collection("doctors").document(doctor_id).get().to_dict()[
            "clinics"
        ][0]["clinic_id"]

    def _future_date(self):
        return (datetime.now(timezone(timedelta(hours=3))).date() + timedelta(days=2))

    def test_public_directory_only_returns_published_profiles_and_filters_verified_first(self):
        draft_id = self._create_doctor(published=False)
        doctor_id = self._create_doctor()
        list_response = self._request(
            "GET",
            "/api/doctors",
            params={"city": "Erbil", "specialization": "Dermatology"},
        )
        profile = self._request("GET", f"/api/doctors/{doctor_id}")
        draft = self._request("GET", f"/api/doctors/{draft_id}")

        self.assertEqual(list_response.status_code, 200)
        self.assertEqual([item["id"] for item in list_response.json()], [doctor_id])
        self.assertFalse(list_response.json()[0]["verified"])
        self.assertEqual(profile.json()["clinics"][0]["address"], "Address entered by admin")
        self.assertEqual(draft.status_code, 404)

    def test_unverified_experience_does_not_affect_experience_sorting(self):
        doctor_ids = [
            self._create_doctor(),
            self._create_doctor(),
        ]
        for doctor_id, name, experience in [
            (doctor_ids[0], "Alpha unverified", 40),
            (doctor_ids[1], "Zed unverified", 2),
        ]:
            reference = self.database.collection("doctors").document(doctor_id)
            data = reference.get().to_dict()
            data["full_name"] = name
            data["experience_years"] = experience
            reference.set(data)
        response = self._request("GET", "/api/doctors", params={"sort": "experience"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [doctor["full_name"] for doctor in response.json()],
            ["Zed unverified", "Alpha unverified"],
        )
        self.assertNotIn("experience_years", response.json()[0])

    def test_admin_requires_server_verified_custom_claim(self):
        response = self._request(
            "GET",
            "/api/doctors/admin/doctors",
            user_id="patient-a",
            admin=False,
        )
        self.assertEqual(response.status_code, 403)

    def test_favorites_are_private_to_each_authenticated_user(self):
        doctor_id = self._create_doctor()
        saved = self._request("PUT", f"/api/doctors/{doctor_id}/favorite")
        owner_list = self._request("GET", "/api/doctors/favorites/mine")
        other_list = self._request(
            "GET",
            "/api/doctors/favorites/mine",
            user_id="patient-b",
        )
        removed = self._request(
            "DELETE",
            f"/api/doctors/{doctor_id}/favorite",
        )

        self.assertEqual(saved.json(), {"is_favorite": True})
        self.assertEqual([item["id"] for item in owner_list.json()], [doctor_id])
        self.assertEqual(other_list.json(), [])
        self.assertEqual(removed.json(), {"is_favorite": False})

    def test_appointment_slot_is_available_once_and_cancellation_releases_it(self):
        doctor_id = self._create_doctor()
        clinic_id = self._clinic_id(doctor_id)
        target_date = self._future_date()
        available = self._request(
            "GET",
            f"/api/doctors/{doctor_id}/availability",
            params={"clinic_id": clinic_id, "date": target_date.isoformat()},
        )
        booking = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": clinic_id,
                "appointment_date": target_date.isoformat(),
                "appointment_time": "09:00",
            },
        )
        duplicate = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": clinic_id,
                "appointment_date": target_date.isoformat(),
                "appointment_time": "09:00",
            },
        )
        cancelled = self._request(
            "POST",
            f"/api/doctors/appointments/{booking.json()['id']}/cancel",
        )
        rebooked = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": clinic_id,
                "appointment_date": target_date.isoformat(),
                "appointment_time": "09:00",
            },
        )

        self.assertEqual(available.status_code, 200)
        self.assertIn("09:00", available.json()["times"])
        self.assertEqual(booking.status_code, 201, booking.text)
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(cancelled.json()["status"], "cancelled")
        self.assertEqual(rebooked.status_code, 201)

    def test_same_doctor_cannot_be_booked_at_two_clinics_for_the_same_slot(self):
        doctor_id = self._create_doctor()
        doctor_reference = self.database.collection("doctors").document(doctor_id)
        doctor = doctor_reference.get().to_dict()
        doctor["clinics"].append(
            {
                **doctor["clinics"][0],
                "clinic_id": "second-clinic",
                "name": "Second verified clinic",
                "city": "Duhok",
            }
        )
        doctor_reference.set(doctor)
        target_date = self._future_date()
        first = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": self._clinic_id(doctor_id),
                "appointment_date": target_date.isoformat(),
                "appointment_time": "09:00",
            },
        )
        second = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": "second-clinic",
                "appointment_date": target_date.isoformat(),
                "appointment_time": "09:00",
            },
        )

        self.assertEqual(first.status_code, 201, first.text)
        self.assertEqual(second.status_code, 409)

    def test_only_completed_owned_appointments_can_be_reviewed_once(self):
        doctor_id = self._create_doctor()
        clinic_id = self._clinic_id(doctor_id)
        target_date = self._future_date()
        booking = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": clinic_id,
                "appointment_date": target_date.isoformat(),
                "appointment_time": "10:00",
            },
        )
        appointment_id = booking.json()["id"]
        early_review = self._request(
            "POST",
            f"/api/doctors/appointments/{appointment_id}/review",
            json={
                "appointment_id": appointment_id,
                "rating": 5,
                "comment": "Review text from the appointment owner.",
            },
        )
        self._request(
            "PATCH",
            f"/api/doctors/admin/appointments/{appointment_id}",
            admin=True,
            json={"status": "confirmed"},
        )
        self._request(
            "PATCH",
            f"/api/doctors/admin/appointments/{appointment_id}",
            admin=True,
            json={"status": "completed"},
        )
        review = self._request(
            "POST",
            f"/api/doctors/appointments/{appointment_id}/review",
            json={
                "appointment_id": appointment_id,
                "rating": 5,
                "comment": "Review text from the appointment owner.",
            },
        )
        duplicate = self._request(
            "POST",
            f"/api/doctors/appointments/{appointment_id}/review",
            json={
                "appointment_id": appointment_id,
                "rating": 4,
                "comment": "A second review is not allowed.",
            },
        )
        other_user = self._request(
            "POST",
            f"/api/doctors/appointments/{appointment_id}/review",
            user_id="patient-b",
            json={
                "appointment_id": appointment_id,
                "rating": 4,
                "comment": "A different user cannot review this appointment.",
            },
        )

        self.assertEqual(early_review.status_code, 409)
        self.assertEqual(review.status_code, 201, review.text)
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(other_user.status_code, 404)

    def test_verification_documents_are_admin_only_and_moderation_controls_badge(self):
        doctor_id = self._create_doctor()
        upload = self._request(
            "POST",
            f"/api/doctors/admin/doctors/{doctor_id}/verification-documents",
            admin=True,
            files={"file": ("license.pdf", b"%PDF-1.7\nprivate test document", "application/pdf")},
        )
        admin_list = self._request(
            "GET",
            "/api/doctors/admin/doctors",
            admin=True,
        )
        document_id = upload.json()["id"]
        private_document = self._request(
            "GET",
            f"/api/doctors/admin/doctors/{doctor_id}/verification-documents/{document_id}",
            admin=True,
        )
        forbidden_document = self._request(
            "GET",
            f"/api/doctors/admin/doctors/{doctor_id}/verification-documents/{document_id}",
            admin=False,
        )
        approval = self._request(
            "PUT",
            f"/api/doctors/admin/doctors/{doctor_id}/verification",
            admin=True,
            json={"status": "approved"},
        )
        profile = self._request("GET", f"/api/doctors/{doctor_id}")
        removal = self._request(
            "PUT",
            f"/api/doctors/admin/doctors/{doctor_id}/verification",
            admin=True,
            json={
                "status": "unverified",
                "notes": "Private review note must not be copied to the audit log.",
            },
        )
        profile_after_removal = self._request("GET", f"/api/doctors/{doctor_id}")

        self.assertEqual(upload.status_code, 201, upload.text)
        self.assertEqual(private_document.content, b"%PDF-1.7\nprivate test document")
        self.assertEqual(forbidden_document.status_code, 403)
        self.assertEqual(approval.json()["verified"], True)
        self.assertTrue(profile.json()["verified"])
        self.assertEqual(removal.status_code, 200, removal.text)
        self.assertFalse(profile_after_removal.json()["verified"])
        self.assertNotIn(
            "file_id",
            admin_list.json()[0]["verification_documents"][0],
        )
        audit_entries = [
            value
            for path, value in self.database.documents.items()
            if path[0] == "admin_audit_logs"
        ]
        self.assertEqual(
            [entry["action"] for entry in audit_entries],
            [
                "doctor.created",
                "doctor.photo_uploaded",
                "doctor.updated",
                "doctor.verification_document_uploaded",
                "doctor.verification_changed",
                "doctor.verification_changed",
            ],
        )
        self.assertNotIn("license.pdf", str(audit_entries))
        self.assertNotIn("private test document", str(audit_entries))
        self.assertNotIn("Private review note", str(audit_entries))

    def test_review_reports_are_deduplicated_and_admin_moderated(self):
        doctor_id = self._create_doctor()
        clinic_id = self._clinic_id(doctor_id)
        target_date = self._future_date()
        booking = self._request(
            "POST",
            "/api/doctors/appointments",
            json={
                "doctor_id": doctor_id,
                "clinic_id": clinic_id,
                "appointment_date": target_date.isoformat(),
                "appointment_time": "10:00",
            },
        )
        appointment_id = booking.json()["id"]
        self._request(
            "PATCH",
            f"/api/doctors/admin/appointments/{appointment_id}",
            admin=True,
            json={"status": "confirmed"},
        )
        self._request(
            "PATCH",
            f"/api/doctors/admin/appointments/{appointment_id}",
            admin=True,
            json={"status": "completed"},
        )
        review = self._request(
            "POST",
            f"/api/doctors/appointments/{appointment_id}/review",
            json={
                "appointment_id": appointment_id,
                "rating": 4,
                "comment": "Review text from the appointment owner.",
            },
        )
        review_id = review.json()["id"]
        approval = self._request(
            "PATCH",
            f"/api/doctors/admin/reviews/{review_id}",
            admin=True,
            json={"status": "approved"},
        )
        first_report = self._request(
            "POST",
            f"/api/doctors/{doctor_id}/reviews/{review_id}/report",
            json={"reason": "Please review this content."},
        )
        duplicate_report = self._request(
            "POST",
            f"/api/doctors/{doctor_id}/reviews/{review_id}/report",
            json={"reason": "Duplicate report."},
        )
        reports = self._request(
            "GET",
            "/api/doctors/admin/reports",
            admin=True,
        )
        report_id = first_report.json()["id"]
        moderated = self._request(
            "PATCH",
            f"/api/doctors/admin/reports/{report_id}",
            admin=True,
            json={"status": "reviewed"},
        )

        self.assertEqual(first_report.status_code, 201)
        self.assertEqual(approval.json()["status"], "approved")
        self.assertEqual(duplicate_report.status_code, 409)
        self.assertEqual(reports.json()[0]["reason"], "Please review this content.")
        self.assertEqual(moderated.json()["status"], "reviewed")

    def test_invalid_schedule_and_review_rating_are_rejected(self):
        invalid_schedule = self._request(
            "POST",
            "/api/doctors/admin/doctors",
            admin=True,
            json={
                "full_name": "Doctor",
                "specializations": ["Dermatology"],
                "clinics": [
                    {
                        "name": "Clinic",
                        "city": "Duhok",
                        "address": "Verified address",
                        "latitude": 36,
                        "weekly_schedule": [],
                    }
                ],
            },
        )
        self.assertEqual(invalid_schedule.status_code, 422)

    def test_publishing_without_a_real_profile_photo_is_rejected(self):
        doctor_id = self._create_doctor(published=False)
        doctor = self.database.collection("doctors").document(doctor_id).get().to_dict()
        doctor["profile_photo_id"] = None
        doctor["profile_photo_extension"] = None
        self.database.collection("doctors").document(doctor_id).set(doctor)
        clinic = doctor["clinics"][0]
        response = self._request(
            "PUT",
            f"/api/doctors/admin/doctors/{doctor_id}",
            admin=True,
            json={
                "full_name": doctor["full_name"],
                "qualifications": doctor["qualifications"],
                "specializations": doctor["specializations"],
                "experience_years": doctor["experience_years"],
                "languages": doctor["languages"],
                "clinics": [clinic],
                "publication_status": "published",
            },
        )
        self.assertEqual(response.status_code, 409)


if __name__ == "__main__":
    unittest.main()
