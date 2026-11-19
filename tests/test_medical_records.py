import asyncio
import os
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import httpx
from PIL import Image
from pydantic import ValidationError

import app as skinai_api
import backend.medical_records as medical_records
import backend.private_image_storage as private_image_storage
from backend.firebase_auth import require_firebase_user


class _Snapshot:
    def __init__(self, record_id, data):
        self.id = record_id
        self._data = data
        self.exists = data is not None

    def get(self, key):
        return self._data.get(key) if self._data else None

    def to_dict(self):
        return dict(self._data or {})


class _Document:
    def __init__(self, database, uid, collection, document_id):
        self.database = database
        self.uid = uid
        self.collection_name = collection
        self.id = document_id

    def collection(self, name):
        return _Collection(self.database, self.uid, name)

    def get(self):
        key = (self.uid, self.collection_name, self.id)
        return _Snapshot(self.id, self.database.documents.get(key))


class _Collection:
    def __init__(self, database, uid, name):
        self.database = database
        self.uid = uid
        self.name = name

    def document(self, document_id=None):
        if self.name == "users":
            return _Document(self.database, document_id, "users", document_id)
        if document_id is None:
            document_id = f"audit-{len(self.database.documents)}"
        return _Document(self.database, self.uid, self.name, document_id)

    def where(self, field, operator, value):
        assert field == "type"
        assert operator == "=="
        self._filter = (field, value)
        return self

    def stream(self):
        _, record_type = self._filter
        return [
            _Snapshot(document_id, data)
            for (uid, collection, document_id), data in self.database.documents.items()
            if uid == self.uid
            and collection == self.name
            and data.get("type") == record_type
        ]


class _Batch:
    def __init__(self, database):
        self.database = database
        self.operations = []

    def set(self, reference, data):
        self.operations.append(("set", reference, data))

    def delete(self, reference):
        self.operations.append(("delete", reference, None))

    def update(self, reference, data):
        self.operations.append(("update", reference, data))

    def commit(self):
        for operation, reference, data in self.operations:
            key = (reference.uid, reference.collection_name, reference.id)
            if operation == "set":
                self.database.documents[key] = dict(data)
            elif operation == "update":
                self.database.documents[key].update(data)
            else:
                self.database.documents.pop(key, None)


class _Database:
    def __init__(self):
        self.documents = {}

    def collection(self, name):
        return _Collection(self, None, name)

    def batch(self):
        return _Batch(self)


class MedicalRecordApiTests(unittest.TestCase):
    def setUp(self):
        self.database = _Database()
        self.image_directory = tempfile.TemporaryDirectory()
        self.image_directory_patch = patch.dict(
            os.environ,
            {"SKINAI_IMAGE_STORAGE_DIR": self.image_directory.name},
        )
        self.image_directory_patch.start()
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: {"uid": "user-a"}
        )
        self.database_patch = patch.object(
            medical_records,
            "_database",
            return_value=self.database,
        )
        self.database_patch.start()

    def tearDown(self):
        self.database_patch.stop()
        self.image_directory_patch.stop()
        self.image_directory.cleanup()
        skinai_api.app.dependency_overrides.clear()

    def _request(self, method, path, *, user_id="user-a", json=None, **kwargs):
        async def send():
            skinai_api.app.dependency_overrides[require_firebase_user] = (
                lambda: {"uid": user_id}
            )
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.request(method, path, json=json, **kwargs)

        return asyncio.run(send())

    def test_authenticated_medication_crud_is_scoped_to_token_owner(self):
        created = self._request(
            "POST",
            "/medical/records/medications",
            json={
                "name": "User-entered medicine",
                "status": "currently_using",
                "instructions": "Follow the label provided by my clinician.",
            },
        )
        self.assertEqual(created.status_code, 201)
        record_id = created.json()["id"]

        other_user_list = self._request(
            "GET",
            "/medical/records/medications",
            user_id="user-b",
        )
        other_user_read = self._request(
            "GET",
            f"/medical/records/medications/{record_id}",
            user_id="user-b",
        )
        owner_list = self._request("GET", "/medical/records/medications")

        self.assertEqual(other_user_list.json(), [])
        self.assertEqual(other_user_read.status_code, 404)
        self.assertEqual(len(owner_list.json()), 1)
        self.assertEqual(owner_list.json()[0]["id"], record_id)
        self.assertTrue(
            any(
                collection == "medical_audit"
                for _, collection, _ in self.database.documents
            )
        )

        updated = self._request(
            "PUT",
            f"/medical/records/medications/{record_id}",
            json={"name": "Updated medicine", "status": "completed"},
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["name"], "Updated medicine")

        deleted = self._request(
            "DELETE",
            f"/medical/records/medications/{record_id}",
        )
        self.assertEqual(deleted.status_code, 204)

    def test_server_owned_or_verified_service_records_cannot_be_fabricated(self):
        fake_scan = self._request(
            "POST",
            "/medical/records/scans",
            json={
                "analysis_id": "made-up",
                "created_at": "2026-11-13T00:00:00Z",
                "result": "made-up diagnosis",
                "confidence": 99,
            },
        )
        fake_doctor_review = self._request(
            "POST",
            "/medical/records/doctor_reviews",
            json={
                "provider_id": "unverified",
                "reviewed_at": "2026-11-13T00:00:00Z",
                "comments": "Not a real doctor review.",
            },
        )

        self.assertEqual(fake_scan.status_code, 409)
        self.assertEqual(fake_doctor_review.status_code, 409)

    def test_external_medication_information_requires_provenance_when_verified(self):
        with self.assertRaises(ValidationError):
            medical_records.MedicationRecognitionResult(
                medicine_name="Example",
                confidence=0.9,
                verified=True,
            )

        unverified = medical_records.MedicationRecognitionResult(
            medicine_name=None,
            confidence=0,
            verified=False,
            uncertainty=["No reliable identification."],
        )
        self.assertIsNone(unverified.medicine_name)

    def test_client_cannot_supply_an_owner_uid_or_unrecognized_fields(self):
        response = self._request(
            "POST",
            "/medical/records/medications",
            json={"uid": "user-b", "name": "Medicine"},
        )
        self.assertEqual(response.status_code, 422)

    def test_relationships_must_reference_records_owned_by_the_same_user(self):
        response = self._request(
            "POST",
            "/medical/records/medication_history",
            json={
                "medication_id": "another-users-medication",
                "status": "completed",
                "changed_at": "2026-11-13T10:00:00Z",
            },
        )
        self.assertEqual(response.status_code, 422)

    def test_analysis_record_is_created_only_under_authenticated_owner(self):
        medical_records.create_analysis_scan(
            "user-a",
            {
                "id": "provider-issued-uuid",
                "timestamp": "2026-11-13T10:00:00+00:00",
                "result": "Provider result",
                "confidence": 0.725,
                "summary": "Provider explanation",
            },
            original_image=None,
            original_content_type="image/png",
            body_location="left cheek",
            user_notes="User-reported concern.",
        )

        stored = self.database.documents[
            ("user-a", "medical_records", "provider-issued-uuid")
        ]
        self.assertEqual(stored["type"], "scans")
        self.assertEqual(stored["source"], "Ivy AI")
        self.assertEqual(stored["result"], "Provider result")
        self.assertEqual(stored["confidence"], 72.5)
        self.assertIsNone(stored["image_file_path"])
        self.assertIsNone(stored["image_owner_uid"])
        self.assertFalse(stored["image_storage_consent"])
        self.assertEqual(stored["body_location"], "left cheek")
        self.assertTrue(
            any(
                collection == "medical_audit"
                for _, collection, _ in self.database.documents
            )
        )

    def test_scan_responses_do_not_expose_private_storage_metadata(self):
        image_id, file_path = private_image_storage.store_image(b"private")
        response = medical_records._public_record(
            "scan-id",
            {
                "type": "scans",
                "image_id": image_id,
                "image_owner_uid": "user-a",
                "image_file_path": file_path,
                "image_file_size": 24,
                "image_content_type": "image/png",
                "image_storage_consent": True,
            },
        )
        private_image_storage.delete_image(file_path)
        self.assertTrue(response["has_original_image"])
        for field in (
            "image_id",
            "image_owner_uid",
            "image_file_path",
            "image_file_size",
            "image_content_type",
        ):
            self.assertNotIn(field, response)

    def test_private_image_storage_rejects_non_uuid_paths(self):
        with self.assertRaises(ValueError):
            private_image_storage.read_image("../outside.png")
        with self.assertRaises(ValueError):
            private_image_storage.delete_image("../outside.png")
        self.assertFalse(private_image_storage.image_exists("../outside.png"))

    def test_scan_history_lists_updates_and_deletes_only_owner_records(self):
        medical_records.create_analysis_scan(
            "user-a",
            {
                "id": "owned-scan",
                "timestamp": "2026-11-13T10:00:00+00:00",
                "result": "Provider result",
                "confidence": 0.72,
                "summary": "Provider explanation.",
            },
            original_image=None,
            original_content_type="image/jpeg",
            body_location="left cheek",
            user_notes="Initial note.",
        )

        owner_list = self._request("GET", "/medical/records/scans")
        other_list = self._request(
            "GET",
            "/medical/records/scans",
            user_id="user-b",
        )
        self.assertEqual(len(owner_list.json()), 1)
        self.assertEqual(owner_list.json()[0]["id"], "owned-scan")
        self.assertEqual(owner_list.json()[0]["confidence"], 72)
        self.assertEqual(other_list.json(), [])

        other_update = self._request(
            "PATCH",
            "/medical/scans/owned-scan",
            user_id="user-b",
            json={"user_notes": "Unauthorized edit."},
        )
        owner_update = self._request(
            "PATCH",
            "/medical/scans/owned-scan",
            json={"body_location": "right cheek", "user_notes": "Updated note."},
        )
        self.assertEqual(other_update.status_code, 404)
        self.assertEqual(owner_update.status_code, 200)
        self.assertEqual(owner_update.json()["result"], "Provider result")
        self.assertEqual(owner_update.json()["body_location"], "right cheek")
        self.assertEqual(owner_update.json()["user_notes"], "Updated note.")

        other_delete = self._request(
            "DELETE",
            "/medical/records/scans/owned-scan",
            user_id="user-b",
        )
        owner_delete = self._request(
            "DELETE",
            "/medical/records/scans/owned-scan",
        )
        self.assertEqual(other_delete.status_code, 404)
        self.assertEqual(owner_delete.status_code, 204)

    def test_owner_scan_workflow_includes_private_image_and_confirmed_deletion(self):
        image_buffer = BytesIO()
        Image.new("RGB", (4, 4), color=(20, 40, 60)).save(
            image_buffer,
            format="PNG",
        )
        original_image = image_buffer.getvalue()
        medical_records.create_analysis_scan(
            "user-a",
            {
                "id": "workflow-scan",
                "timestamp": "2026-11-13T10:00:00+00:00",
                "result": "Provider result",
                "confidence": 0.72,
                "summary": "Provider explanation.",
            },
            original_image=None,
            original_content_type="image/png",
            body_location="left cheek",
            user_notes="Initial note.",
        )

        owner_history = self._request("GET", "/medical/records/scans")
        other_read = self._request(
            "GET",
            "/medical/records/scans/workflow-scan",
            user_id="user-b",
        )
        updated = self._request(
            "PATCH",
            "/medical/scans/workflow-scan",
            json={"user_notes": "Updated note."},
        )
        upload = self._request(
            "POST",
            "/medical/scans/workflow-scan/original-image",
            data={"storage_consent": "true"},
            files={
                "file": (
                    "../../outside.png",
                    original_image,
                    "image/png",
                )
            },
        )
        owner_image = self._request(
            "GET",
            "/medical/scans/workflow-scan/original-image",
        )
        history_with_image = self._request(
            "GET",
            "/medical/records/scans",
        )
        other_image = self._request(
            "GET",
            "/medical/scans/workflow-scan/original-image",
            user_id="user-b",
        )
        other_delete = self._request(
            "DELETE",
            "/medical/records/scans/workflow-scan",
            user_id="user-b",
        )
        stored = self.database.documents[
            ("user-a", "medical_records", "workflow-scan")
        ]
        private_file = Path(self.image_directory.name) / stored["image_file_path"]
        self.assertTrue(private_file.is_file())
        self.assertEqual(stored["image_owner_uid"], "user-a")
        self.assertEqual(stored["image_file_size"], len(original_image))
        self.assertEqual(stored["image_content_type"], "image/png")
        self.assertEqual(stored["image_id"], stored["image_file_path"])
        self.assertRegex(stored["image_file_path"], r"^[0-9a-f-]{36}$")
        self.assertTrue(stored["image_uploaded_at"])
        owner_delete = self._request(
            "DELETE",
            "/medical/records/scans/workflow-scan",
        )
        history_after_delete = self._request(
            "GET",
            "/medical/records/scans",
        )

        self.assertEqual(owner_history.status_code, 200)
        self.assertEqual(owner_history.json()[0]["id"], "workflow-scan")
        self.assertEqual(owner_history.json()[0]["has_original_image"], False)
        self.assertNotIn("image_file_path", owner_history.json()[0])
        self.assertEqual(other_read.status_code, 404)
        self.assertEqual(updated.json()["user_notes"], "Updated note.")
        self.assertEqual(updated.json()["result"], "Provider result")
        self.assertEqual(upload.status_code, 201)
        self.assertTrue(history_with_image.json()[0]["has_original_image"])
        self.assertNotIn("image_file_path", history_with_image.json()[0])
        self.assertEqual(owner_image.content, original_image)
        self.assertEqual(owner_image.headers["cache-control"], "no-store")
        self.assertEqual(other_image.status_code, 404)
        self.assertEqual(other_delete.status_code, 404)
        self.assertEqual(owner_delete.status_code, 204)
        self.assertEqual(history_after_delete.json(), [])
        self.assertFalse(private_file.exists())

    def test_scan_metadata_update_rejects_empty_or_managed_fields(self):
        empty = self._request("PATCH", "/medical/scans/missing", json={})
        managed = self._request(
            "PATCH",
            "/medical/scans/missing",
            json={"result": "client-supplied result"},
        )
        self.assertEqual(empty.status_code, 422)
        self.assertEqual(managed.status_code, 422)

    def test_original_image_is_private_and_accessed_only_for_its_owner(self):
        self.database.documents[
            ("user-a", "medical_records", "scan-id")
        ] = {
            "type": "scans",
            "analysis_id": "scan-id",
            "image_file_path": None,
            "image_storage_consent": False,
        }
        image_buffer = BytesIO()
        Image.new("RGB", (4, 4), color=(20, 40, 60)).save(
            image_buffer,
            format="PNG",
        )
        original_image = image_buffer.getvalue()
        stored = self._request(
            "POST",
            "/medical/scans/scan-id/original-image",
            data={"storage_consent": "true"},
            files={
                "file": (
                    "original.png",
                    original_image,
                    "image/png",
                )
            },
        )
        self.assertEqual(stored.status_code, 201)
        metadata = self.database.documents[
            ("user-a", "medical_records", "scan-id")
        ]
        self.assertEqual(
            (Path(self.image_directory.name) / metadata["image_file_path"]).read_bytes(),
            original_image,
        )
        owner_read = self._request(
            "GET",
            "/medical/scans/scan-id/original-image",
        )
        other_read = self._request(
            "GET",
            "/medical/scans/scan-id/original-image",
            user_id="user-b",
        )

        self.assertEqual(owner_read.status_code, 200)
        self.assertEqual(owner_read.content, original_image)
        self.assertEqual(owner_read.headers["cache-control"], "no-store")
        self.assertEqual(other_read.status_code, 404)

    def test_image_storage_requires_explicit_consent(self):
        response = self._request(
            "POST",
            "/medical/scans/scan-id/original-image",
            data={"storage_consent": "false"},
            files={"file": ("scan.png", b"not inspected without consent", "image/png")},
        )
        self.assertEqual(response.status_code, 403)

    def test_image_storage_rejects_invalid_bytes_and_mismatched_mime_type(self):
        self.database.documents[
            ("user-a", "medical_records", "scan-id")
        ] = {"type": "scans", "image_file_path": None}
        invalid = self._request(
            "POST",
            "/medical/scans/scan-id/original-image",
            data={"storage_consent": "true"},
            files={"file": ("scan.png", b"not an image", "image/png")},
        )
        image_buffer = BytesIO()
        Image.new("RGB", (4, 4), color=(20, 40, 60)).save(
            image_buffer,
            format="PNG",
        )
        mismatched = self._request(
            "POST",
            "/medical/scans/scan-id/original-image",
            data={"storage_consent": "true"},
            files={
                "file": (
                    "scan.png",
                    image_buffer.getvalue(),
                    "image/jpeg",
                )
            },
        )

        self.assertEqual(invalid.status_code, 400)
        self.assertEqual(mismatched.status_code, 415)
        self.assertEqual(list(Path(self.image_directory.name).iterdir()), [])

    def test_medical_endpoints_require_firebase_authentication(self):
        async def send():
            skinai_api.app.dependency_overrides.clear()
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.get("/medical/records/medications")

        response = asyncio.run(send())
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
