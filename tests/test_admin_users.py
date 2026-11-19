import asyncio
import os
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import uuid4

import httpx
from firebase_admin import auth

import app as skinai_api
import backend.admin_users as admin_users
from backend.email_block import email_document_id
from backend.firebase_auth import require_firebase_user


class _Snapshot:
    def __init__(self, path, data):
        self.path = path
        self.id = path[-1]
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return dict(self._data or {})


class _Reference:
    def __init__(self, database, path):
        self.database = database
        self.path = path
        self.id = path[-1]

    def get(self, transaction=None):
        return _Snapshot(self.path, self.database.documents.get(self.path))

    def create(self, data):
        if self.path in self.database.documents:
            raise AssertionError("Document already exists.")
        self.database.documents[self.path] = dict(data)

    def set(self, data):
        self.database.documents[self.path] = dict(data)

    def delete(self):
        self.database.documents.pop(self.path, None)

    def collection(self, name):
        return _Collection(self.database, self.path + (name,))


class _Query:
    def __init__(self, database, path, filters=(), selected=None):
        self.database = database
        self.path = path
        self.filters = list(filters)
        self.selected = selected

    def where(self, field, operator, value):
        return _Query(
            self.database,
            self.path,
            self.filters + [(field, operator, value)],
            self.selected,
        )

    def select(self, fields):
        return _Query(self.database, self.path, self.filters, list(fields))

    def stream(self):
        results = []
        for path, data in self.database.documents.items():
            if path[:-1] != self.path:
                continue
            matches = all(
                (operator != "==" or data.get(field) == value)
                for field, operator, value in self.filters
            )
            if not matches:
                continue
            record = (
                data
                if self.selected is None
                else {key: data[key] for key in self.selected if key in data}
            )
            results.append(_Snapshot(path, record))
        return results


class _Collection(_Query):
    def document(self, identifier=None):
        identifier = identifier or str(uuid4())
        return _Reference(self.database, self.path + (identifier,))


class _Transaction:
    def set(self, reference, data):
        reference.set(data)

    def create(self, reference, data):
        reference.create(data)

    def delete(self, reference):
        reference.delete()


class _Database:
    def __init__(self):
        self.documents = {}

    def collection(self, name):
        return _Collection(self, (name,))

    def transaction(self, **_):
        return _Transaction()


class _Metadata:
    def __init__(self, created_at, last_sign_in=None):
        self.creation_timestamp = created_at
        self.last_sign_in_timestamp = last_sign_in


class _User:
    def __init__(
        self,
        uid,
        email,
        *,
        created_at=None,
        display_name=None,
        disabled=False,
        custom_claims=None,
    ):
        created_at = created_at or int(datetime.now(timezone.utc).timestamp() * 1000)
        self.uid = uid
        self.email = email
        self.display_name = display_name
        self.user_metadata = _Metadata(created_at)
        self.email_verified = True
        self.disabled = disabled
        self.custom_claims = custom_claims or {}


class _UserPage:
    def __init__(self, users, next_page_token=None):
        self.users = users
        self.next_page_token = next_page_token


class AdminUsersTests(unittest.TestCase):
    def setUp(self):
        self.database = _Database()
        self.claims = {"uid": "admin-user-test", "admin": True}
        self.admin = _User("admin-user-test", "admin@example.test")
        self.target = _User(
            "target-user",
            "person@example.test",
            display_name="Test Person",
        )
        self.firebase_app = object()
        self.auth_patches = [
            patch.object(auth, "get_user", side_effect=self._get_user),
            patch.object(
                auth,
                "list_users",
                return_value=_UserPage([self.admin, self.target]),
            ),
            patch.object(auth, "update_user"),
        ]
        for auth_patch in self.auth_patches:
            auth_patch.start()
        self.database_patch = patch.object(
            admin_users,
            "_database",
            return_value=self.database,
        )
        self.database_patch.start()
        self.firebase_app_patch = patch.object(
            admin_users,
            "get_firebase_app",
            return_value=self.firebase_app,
        )
        self.firebase_app_patch.start()
        self.users_patch = patch.object(
            admin_users,
            "_iter_auth_users",
            return_value=iter([self.admin, self.target]),
        )
        self.users_patch.start()
        self.transactional_patch = patch(
            "google.cloud.firestore_v1.transactional",
            side_effect=lambda callback: callback,
        )
        self.transactional_patch.start()
        self.hmac_key_patch = patch.dict(
            os.environ,
            {"EMAIL_BLOCK_HMAC_KEY": "test-block-key"},
        )
        self.hmac_key_patch.start()
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: self.claims
        )

    def tearDown(self):
        skinai_api.app.dependency_overrides.clear()
        self.hmac_key_patch.stop()
        self.transactional_patch.stop()
        self.users_patch.stop()
        self.firebase_app_patch.stop()
        self.database_patch.stop()
        for auth_patch in reversed(self.auth_patches):
            auth_patch.stop()

    def _get_user(self, uid, app=None):
        if uid == self.admin.uid:
            return self.admin
        if uid == self.target.uid:
            return self.target
        raise auth.UserNotFoundError("missing")

    def _request(self, method, path, *, json=None, params=None, admin=True):
        async def send():
            self.claims = {"uid": "admin-user-test", "admin": admin}
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

    def test_user_listing_and_validation(self):
        response = self._request("GET", "/api/admin/users")
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual([user["uid"] for user in body["users"]], [
            "admin-user-test",
            "target-user",
        ])
        self.assertNotIn("password", response.text.lower())

        invalid_page_size = self._request(
            "GET",
            "/api/admin/users",
            params={"page_size": 101},
        )
        self.assertEqual(invalid_page_size.status_code, 422)

        invalid_body = self._request(
            "PATCH",
            "/api/admin/users/target-user/block",
            json={"blocked": True, "extra": "not allowed"},
        )
        self.assertEqual(invalid_body.status_code, 422)

    def test_block_action_uses_hmac_blocklist_and_writes_audit(self):
        response = self._request(
            "PATCH",
            "/api/admin/users/target-user/block",
            json={"blocked": True},
        )
        self.assertEqual(response.status_code, 200, response.text)
        block_id = email_document_id(
            self.target.email,
            os.environ["EMAIL_BLOCK_HMAC_KEY"],
        )
        self.assertIn(("blocked_emails", block_id), self.database.documents)
        audit_entries = [
            value
            for path, value in self.database.documents.items()
            if path[0] == "admin_audit_logs"
        ]
        self.assertEqual(len(audit_entries), 1)
        self.assertEqual(audit_entries[0]["action"], "user.blocked")
        self.assertEqual(audit_entries[0]["target_id"], self.target.uid)
        self.assertNotIn(self.target.email, str(audit_entries[0]))

    def test_admin_cannot_block_self_or_last_admin(self):
        self.admin.custom_claims = {"admin": True}
        self.target.custom_claims = {"admin": True}
        self._iter_admin_users_patch = patch.object(
            admin_users,
            "_iter_auth_users",
            return_value=iter([self.target]),
        )
        self._iter_admin_users_patch.start()
        self.addCleanup(self._iter_admin_users_patch.stop)

        self_block = self._request(
            "PATCH",
            "/api/admin/users/admin-user-test/block",
            json={"blocked": True},
        )
        last_admin = self._request(
            "PATCH",
            "/api/admin/users/target-user/block",
            json={"blocked": True},
        )
        self.assertEqual(self_block.status_code, 409)
        self.assertEqual(last_admin.status_code, 409)
        self.assertFalse(
            any(path[0] == "admin_audit_logs" for path in self.database.documents)
        )

    def test_admin_cannot_disable_self_or_last_admin(self):
        self.admin.custom_claims = {"admin": True}
        self.target.custom_claims = {"admin": True}
        self._iter_admin_users_patch = patch.object(
            admin_users,
            "_iter_auth_users",
            return_value=iter([self.target]),
        )
        self._iter_admin_users_patch.start()
        self.addCleanup(self._iter_admin_users_patch.stop)

        self_disable = self._request(
            "PATCH",
            "/api/admin/users/admin-user-test/disabled",
            json={"disabled": True},
        )
        last_admin = self._request(
            "PATCH",
            "/api/admin/users/target-user/disabled",
            json={"disabled": True},
        )

        self.assertEqual(self_disable.status_code, 409)
        self.assertEqual(last_admin.status_code, 409)
        auth.update_user.assert_not_called()
        self.assertFalse(
            any(path[0] == "admin_audit_logs" for path in self.database.documents)
        )

    def test_disable_action_audits_minimal_account_state(self):
        response = self._request(
            "PATCH",
            "/api/admin/users/target-user/disabled",
            json={"disabled": True},
        )

        self.assertEqual(response.status_code, 200, response.text)
        auth.update_user.assert_called_once_with(
            "target-user",
            disabled=True,
            app=self.firebase_app,
        )
        audit_entries = [
            value
            for path, value in self.database.documents.items()
            if path[0] == "admin_audit_logs"
        ]
        self.assertEqual(
            [entry["action"] for entry in audit_entries],
            ["user.disable_requested", "user.disabled"],
        )
        self.assertTrue(
            all(
                entry["before"] == {"disabled": False}
                and entry["after"] == {"disabled": True}
                for entry in audit_entries
            )
        )

    def test_non_admin_is_denied_and_data_deletion_is_a_request(self):
        denied = self._request(
            "GET",
            "/api/admin/users",
            admin=False,
        )
        self.assertEqual(denied.status_code, 403)

        response = self._request(
            "POST",
            "/api/admin/users/target-user/deletion-requests",
            json={"confirmation": True},
        )
        self.assertEqual(response.status_code, 201, response.text)
        self.assertTrue(
            any(
                path[0] == "admin_data_deletion_requests"
                for path in self.database.documents
            )
        )
        self.assertTrue(
            any(
                value.get("action") == "user.data_deletion_requested"
                for path, value in self.database.documents.items()
                if path[0] == "admin_audit_logs"
            )
        )


if __name__ == "__main__":
    unittest.main()
