import unittest

from backend.manage_doctor_admin import set_doctor_admin


class _User:
    custom_claims = {"skinchat_plan": "paid", "admin": False}


class _Auth:
    def __init__(self):
        self.claims = None

    def get_user(self, uid, *, app):
        self.uid = uid
        self.app = app
        return _User()

    def set_custom_user_claims(self, uid, claims, *, app):
        self.claims = claims


class DoctorAdminProvisioningTests(unittest.TestCase):
    def test_grant_preserves_existing_claims_and_adds_admin(self):
        auth = _Auth()
        firebase_app = object()

        set_doctor_admin(auth, firebase_app, "trusted-uid", enabled=True)

        self.assertEqual(auth.uid, "trusted-uid")
        self.assertIs(auth.app, firebase_app)
        self.assertEqual(auth.claims, {"skinchat_plan": "paid", "admin": True})

    def test_revoke_removes_only_admin_claim(self):
        auth = _Auth()

        set_doctor_admin(auth, object(), "trusted-uid", enabled=False)

        self.assertEqual(auth.claims, {"skinchat_plan": "paid"})


if __name__ == "__main__":
    unittest.main()
