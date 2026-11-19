import asyncio
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import httpx
from firebase_admin import auth

import app as skinai_api
import backend.admin_api as admin_api
import backend.firebase_auth as firebase_auth
from backend.firebase_auth import require_firebase_user


class _Snapshot:
    def __init__(self, path, data):
        self.path = path
        self.id = path[-1]
        self._data = data

    def to_dict(self):
        return dict(self._data or {})


class _Query:
    def __init__(self, database, path=None, group=None, filters=(), selected=None):
        self.database = database
        self.path = path
        self.group = group
        self.filters = list(filters)
        self.selected = selected

    def where(self, field, operator, value):
        return _Query(
            self.database,
            path=self.path,
            group=self.group,
            filters=self.filters + [(field, operator, value)],
            selected=self.selected,
        )

    def select(self, fields):
        return _Query(
            self.database,
            path=self.path,
            group=self.group,
            filters=self.filters,
            selected=list(fields),
        )

    def _matches_path(self, path):
        if self.group is not None:
            return len(path) >= 2 and path[-2] == self.group
        return path[:-1] == self.path

    def _matches_filters(self, record):
        for field, operator, expected in self.filters:
            actual = record.get(field)
            if operator == "==" and actual != expected:
                return False
            if operator == ">=" and (actual is None or actual < expected):
                return False
            if operator == "<" and (actual is None or actual >= expected):
                return False
        return True

    def stream(self):
        snapshots = []
        for path, data in self.database.documents.items():
            if not self._matches_path(path) or not self._matches_filters(data):
                continue
            selected_data = (
                data
                if self.selected is None
                else {key: data[key] for key in self.selected if key in data}
            )
            snapshots.append(_Snapshot(path, selected_data))
        return snapshots


class _Database:
    def __init__(self, documents):
        self.documents = documents

    def collection(self, name):
        return _Query(self, path=(name,))

    def collection_group(self, name):
        return _Query(self, group=name)


class _Metadata:
    def __init__(self, creation_timestamp):
        self.creation_timestamp = creation_timestamp


class _User:
    def __init__(self, creation_timestamp):
        self.user_metadata = _Metadata(creation_timestamp)


class AdminApiTests(unittest.TestCase):
    def setUp(self):
        firebase_auth._admin_rate_requests.clear()
        now = datetime.now(timezone.utc)
        today = now.date()
        yesterday = today - timedelta(days=1)
        self.database = _Database(
            {
                ("users", "user-a", "medical_records", "scan-today"): {
                    "type": "scans",
                    "created_at": now.isoformat(),
                    "result": "private scan detail",
                    "image_file_path": "private/image/path",
                },
                ("users", "user-a", "medical_records", "scan-yesterday"): {
                    "type": "scans",
                    "created_at": datetime.combine(
                        yesterday,
                        datetime.min.time(),
                        tzinfo=timezone.utc,
                    ).isoformat(),
                    "result": "private scan detail",
                },
                ("users", "user-a", "skinchat_usage", today.isoformat()): {
                    "date": today.isoformat(),
                    "count": 3,
                },
                ("users", "user-a", "skinchat_conversations", "conversation-a",
                 "messages", "message-a"): {
                    "content": "private conversation",
                },
                ("doctor_appointments", "appointment-a"): {"status": "pending"},
                ("doctor_appointments", "appointment-b"): {"status": "confirmed"},
                ("doctors", "doctor-a"): {"publication_status": "published"},
                ("doctors", "doctor-b"): {
                    "publication_status": "draft",
                    "verification_status": "pending",
                },
                ("doctor_review_reports", "report-a"): {"status": "pending"},
                ("doctor_review_reports", "report-b"): {"status": "dismissed"},
            }
        )
        self.claims = {"uid": "admin-dashboard-test", "admin": True}
        self.database_patch = patch.object(
            admin_api,
            "_database",
            return_value=self.database,
        )
        self.database_patch.start()
        self.firebase_app_patch = patch.object(
            admin_api,
            "get_firebase_app",
            return_value=object(),
        )
        self.firebase_app_patch.start()
        self.users_patch = patch.object(
            admin_api,
            "_iter_auth_users",
            return_value=iter(
                [
                    _User(int(now.timestamp() * 1000)),
                    _User(int((now - timedelta(days=1)).timestamp() * 1000)),
                ]
            ),
        )
        self.users_patch.start()
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: self.claims
        )

    def tearDown(self):
        skinai_api.app.dependency_overrides.clear()
        self.users_patch.stop()
        self.firebase_app_patch.stop()
        self.database_patch.stop()

    def _request(self, method, path, *, headers=None, admin=None, params=None):
        async def send():
            if admin is not None:
                self.claims = {"uid": "admin-dashboard-test", "admin": admin}
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.request(
                    method,
                    path,
                    headers=headers,
                    params=params,
                )

        return asyncio.run(send())

    def test_missing_and_invalid_id_tokens_are_rejected(self):
        skinai_api.app.dependency_overrides.clear()
        missing = self._request("GET", "/api/admin/status")
        self.assertEqual(missing.status_code, 401)

        with (
            patch(
                "backend.firebase_auth.get_firebase_app",
                return_value=object(),
            ),
            patch(
                "firebase_admin.auth.verify_id_token",
                side_effect=auth.InvalidIdTokenError("invalid"),
            ),
        ):
            invalid = self._request(
                "GET",
                "/api/admin/status",
                headers={"Authorization": "Bearer invalid-token"},
            )
        self.assertEqual(invalid.status_code, 401)

    def test_status_requires_admin_claim(self):
        response = self._request(
            "GET",
            "/api/admin/status",
            admin=False,
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_status_and_dashboard_return_metadata_only(self):
        status_response = self._request("GET", "/api/admin/status")
        response = self._request(
            "GET",
            "/api/admin/dashboard",
            params={"days": 7},
        )

        self.assertEqual(status_response.status_code, 200)
        self.assertEqual(status_response.json(), {"admin": True})
        self.assertEqual(response.status_code, 200, response.text)
        dashboard = response.json()
        self.assertEqual(dashboard["users_total"], 2)
        self.assertEqual(dashboard["scans_total"], 2)
        self.assertEqual(dashboard["skinchat_messages_total"], 3)
        self.assertEqual(dashboard["appointments_by_status"]["pending"], 1)
        self.assertEqual(dashboard["doctors_published"], 1)
        self.assertEqual(dashboard["doctors_pending"], 1)
        self.assertEqual(dashboard["reports_waiting"], 1)
        self.assertEqual(dashboard["system_health"]["status"], "ok")
        serialized = response.text
        self.assertNotIn("private scan detail", serialized)
        self.assertNotIn("private/image/path", serialized)
        self.assertNotIn("private conversation", serialized)

    def test_dashboard_rejects_unsupported_period(self):
        response = self._request(
            "GET",
            "/api/admin/dashboard",
            params={"days": 8},
        )
        self.assertEqual(response.status_code, 422)

    def test_admin_endpoints_are_rate_limited(self):
        uid = "rate-limit-test-admin"
        self.claims = {"uid": uid, "admin": True}
        firebase_auth._admin_rate_requests.pop(uid, None)
        with patch.object(firebase_auth, "_ADMIN_RATE_REQUEST_LIMIT", 1):
            first = self._request("GET", "/api/admin/status")
            second = self._request("GET", "/api/admin/status")

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 429)


if __name__ == "__main__":
    unittest.main()
