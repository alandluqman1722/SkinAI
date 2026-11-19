import asyncio
import unittest
from unittest.mock import patch

import httpx

import app as skinai_api
import backend.admin_appointments as admin_appointments
import backend.firebase_auth as firebase_auth
from backend.firebase_auth import require_firebase_user


class _Snapshot:
    def __init__(self, path, data):
        self.path = path
        self.id = path[-1]
        self.exists = data is not None
        self._data = dict(data or {})

    def to_dict(self):
        return dict(self._data)


class _Document:
    def __init__(self, database, path):
        self.database = database
        self.path = path
        self.id = path[-1]

    def get(self, transaction=None):
        return _Snapshot(self.path, self.database.documents.get(self.path))

    def create(self, data):
        if self.path in self.database.documents:
            raise RuntimeError("Document already exists.")
        self.database.documents[self.path] = dict(data)

    def set(self, data, merge=False):
        if merge:
            self.database.documents.setdefault(self.path, {}).update(data)
        else:
            self.database.documents[self.path] = dict(data)

    def update(self, data):
        if self.path not in self.database.documents:
            raise RuntimeError("Document does not exist.")
        self.database.documents[self.path].update(data)

    def delete(self):
        self.database.documents.pop(self.path, None)


class _Query:
    def __init__(
        self,
        database,
        path,
        *,
        filters=(),
        order_field=None,
        maximum=None,
        start_after=None,
    ):
        self.database = database
        self.path = path
        self.filters = list(filters)
        self.order_field = order_field
        self.maximum = maximum
        self.start_after_snapshot = start_after

    def where(self, field, operator, value):
        return _Query(
            self.database,
            self.path,
            filters=self.filters + [(field, operator, value)],
            order_field=self.order_field,
            maximum=self.maximum,
            start_after=self.start_after_snapshot,
        )

    def order_by(self, field):
        return _Query(
            self.database,
            self.path,
            filters=self.filters,
            order_field=field,
            maximum=self.maximum,
            start_after=self.start_after_snapshot,
        )

    def limit(self, maximum):
        return _Query(
            self.database,
            self.path,
            filters=self.filters,
            order_field=self.order_field,
            maximum=maximum,
            start_after=self.start_after_snapshot,
        )

    def start_after(self, snapshot):
        return _Query(
            self.database,
            self.path,
            filters=self.filters,
            order_field=self.order_field,
            maximum=self.maximum,
            start_after=snapshot,
        )

    def stream(self):
        items = []
        for path, data in self.database.documents.items():
            if path[:-1] != self.path:
                continue
            matches = True
            for field, operator, expected in self.filters:
                value = data.get(field)
                if operator == "==" and value != expected:
                    matches = False
                elif operator == ">=" and (value is None or value < expected):
                    matches = False
                elif operator == "<=" and (value is None or value > expected):
                    matches = False
            if matches:
                items.append((path, data))

        if self.order_field is not None:
            items.sort(
                key=lambda item: (
                    item[1].get(self.order_field, ""),
                    item[0][-1],
                )
            )
        if self.start_after_snapshot is not None:
            cursor = self.start_after_snapshot
            cursor_data = cursor.to_dict() or {}
            cursor_key = (
                cursor_data.get(self.order_field, ""),
                cursor.id,
            )
            items = [
                item
                for item in items
                if (item[1].get(self.order_field, ""), item[0][-1]) > cursor_key
            ]
        if self.maximum is not None:
            items = items[: self.maximum]
        return [_Snapshot(path, data) for path, data in items]


class _Collection(_Query):
    def document(self, identifier=None):
        return _Document(
            self.database,
            self.path + (identifier or f"generated-{len(self.database.documents)}",),
        )


class _Transaction:
    def set(self, reference, data, merge=False):
        reference.set(data, merge=merge)

    def create(self, reference, data):
        reference.create(data)

    def update(self, reference, data):
        reference.update(data)


class _Database:
    def __init__(self):
        self.documents = {
            ("doctor_appointments", "appointment-a"): {
                "doctor_id": "doctor-a",
                "doctor_name": "Doctor A",
                "clinic_id": "clinic-a",
                "clinic_name": "Clinic A",
                "city": "Erbil",
                "appointment_date": "2026-10-01",
                "appointment_time": "09:00",
                "timezone": "Asia/Baghdad",
                "status": "pending",
                "patient_uid": "private-user-a",
                "patient_name": "Private Name",
            },
            ("doctor_appointments", "appointment-b"): {
                "doctor_id": "doctor-a",
                "doctor_name": "Doctor A",
                "clinic_id": "clinic-a",
                "clinic_name": "Clinic A",
                "city": "Erbil",
                "appointment_date": "2026-10-02",
                "appointment_time": "10:00",
                "status": "confirmed",
                "patient_uid": "private-user-b",
                "patient_name": "Other Private Name",
            },
            ("doctor_appointments", "appointment-c"): {
                "doctor_id": "doctor-b",
                "doctor_name": "Doctor B",
                "clinic_id": "clinic-b",
                "clinic_name": "Clinic B",
                "city": "Duhok",
                "appointment_date": "2026-10-03",
                "appointment_time": "11:00",
                "status": "pending",
                "patient_uid": "private-user-c",
            },
        }

    def collection(self, name):
        return _Collection(self, (name,))

    def transaction(self, **_):
        return _Transaction()


def _direct_transactional(function):
    def wrapped(transaction):
        return function(transaction)

    return wrapped


class AdminAppointmentTests(unittest.TestCase):
    def setUp(self):
        firebase_auth._admin_rate_requests.clear()
        self.database = _Database()
        self.claims = {"uid": "admin-appointments-test", "admin": True}
        self.database_patch = patch.object(
            admin_appointments,
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

    def _request(
        self,
        method,
        path,
        *,
        json=None,
        params=None,
        admin=True,
    ):
        async def send():
            self.claims = {
                "uid": "admin-appointments-test",
                "admin": admin,
            }
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.request(
                    method,
                    path,
                    json=json,
                    params=params,
                )

        return asyncio.run(send())

    def test_list_filters_and_paginates_without_patient_details(self):
        first = self._request(
            "GET",
            "/api/admin/appointments",
            params={"page_size": 1},
        )
        second = self._request(
            "GET",
            "/api/admin/appointments",
            params={
                "page_size": 1,
                "cursor": first.json()["next_cursor"],
            },
        )
        third = self._request(
            "GET",
            "/api/admin/appointments",
            params={
                "page_size": 1,
                "cursor": second.json()["next_cursor"],
            },
        )
        filtered = self._request(
            "GET",
            "/api/admin/appointments",
            params={
                "status": "pending",
                "doctor_id": "doctor-a",
                "date_from": "2026-10-01",
                "date_to": "2026-10-01",
            },
        )

        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(first.json()["appointments"][0]["id"], "appointment-a")
        self.assertIsNotNone(first.json()["next_cursor"])
        self.assertEqual(second.json()["appointments"][0]["id"], "appointment-b")
        self.assertEqual(third.json()["appointments"][0]["id"], "appointment-c")
        self.assertIsNone(third.json()["next_cursor"])
        self.assertEqual(
            [item["id"] for item in filtered.json()["appointments"]],
            ["appointment-a"],
        )
        self.assertNotIn("patient_uid", first.text)
        self.assertNotIn("patient_name", first.text)
        self.assertNotIn("Private Name", first.text)

    def test_invalid_filters_and_pagination_limits_are_rejected(self):
        invalid_page_size = self._request(
            "GET",
            "/api/admin/appointments",
            params={"page_size": 101},
        )
        invalid_date_range = self._request(
            "GET",
            "/api/admin/appointments",
            params={
                "date_from": "2026-10-10",
                "date_to": "2026-10-01",
            },
        )
        invalid_reason = self._request(
            "PATCH",
            "/api/admin/appointments/appointment-a",
            json={"status": "confirmed", "reason": "  "},
        )

        self.assertEqual(invalid_page_size.status_code, 422)
        self.assertEqual(invalid_date_range.status_code, 422)
        self.assertEqual(invalid_reason.status_code, 422)

    def test_moderation_is_transactional_and_audited_without_reason_content(self):
        response = self._request(
            "PATCH",
            "/api/admin/appointments/appointment-a",
            json={
                "status": "confirmed",
                "reason": "Patient appointment confirmed.",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"], "confirmed")
        appointment = self.database.documents[
            ("doctor_appointments", "appointment-a")
        ]
        slot = next(
            value
            for path, value in self.database.documents.items()
            if path[0] == "doctor_appointment_slots"
        )
        audit = next(
            value
            for path, value in self.database.documents.items()
            if path[0] == "admin_audit_logs"
        )
        self.assertEqual(appointment["moderation_reason"], "Patient appointment confirmed.")
        self.assertEqual(slot["status"], "confirmed")
        self.assertEqual(audit["action"], "appointment.status_changed")
        self.assertEqual(audit["before"], {"status": "pending"})
        self.assertEqual(
            audit["after"],
            {"status": "confirmed", "reason_provided": True},
        )
        self.assertNotIn("Patient appointment confirmed.", str(audit))

    def test_non_admin_is_denied(self):
        response = self._request(
            "GET",
            "/api/admin/appointments",
            admin=False,
        )
        self.assertEqual(response.status_code, 403)


if __name__ == "__main__":
    unittest.main()
