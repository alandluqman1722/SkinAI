import os
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import firebase_admin

from backend import firebase_app


class FirebaseAppInitializationTests(unittest.TestCase):
    def test_missing_service_account_fails_with_one_actionable_message(self):
        with (
            patch.dict(
                os.environ,
                {
                    "GOOGLE_APPLICATION_CREDENTIALS": "",
                    "FIREBASE_SERVICE_ACCOUNT_PATH": "",
                    "FIREBASE_PROJECT_ID": "skinai-b0465",
                },
                clear=True,
            ),
            patch.object(firebase_app, "load_dotenv"),
        ):
            with self.assertRaisesRegex(
                RuntimeError,
                "set GOOGLE_APPLICATION_CREDENTIALS",
            ) as raised:
                firebase_app.initialize_firebase_app()

        self.assertIn("FIREBASE_SERVICE_ACCOUNT_PATH", str(raised.exception))

    def test_missing_service_account_file_fails_before_initialization(self):
        with tempfile.TemporaryDirectory() as directory:
            missing_path = Path(directory) / "missing.json"
            with (
                patch.dict(
                    os.environ,
                    {
                        "GOOGLE_APPLICATION_CREDENTIALS": str(missing_path),
                        "FIREBASE_PROJECT_ID": "skinai-b0465",
                    },
                    clear=True,
                ),
                patch.object(firebase_app, "load_dotenv"),
                patch.object(firebase_admin, "initialize_app") as initialize,
            ):
                with self.assertRaisesRegex(RuntimeError, "was not found"):
                    firebase_app.initialize_firebase_app()

        initialize.assert_not_called()

    def test_service_account_project_must_match_frontend_project(self):
        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory) / "credential.json"
            key_path.touch()
            with (
                patch.dict(
                    os.environ,
                    {
                        "GOOGLE_APPLICATION_CREDENTIALS": str(key_path),
                        "FIREBASE_PROJECT_ID": "skinai-b0465",
                    },
                    clear=True,
                ),
                patch.object(firebase_app, "load_dotenv"),
                patch(
                    "firebase_admin.credentials.Certificate",
                    return_value=SimpleNamespace(project_id="other-project"),
                ),
                patch.object(firebase_admin, "initialize_app") as initialize,
            ):
                with self.assertRaisesRegex(
                    RuntimeError,
                    "service-account project does not match",
                ):
                    firebase_app.initialize_firebase_app()

        initialize.assert_not_called()

    def test_service_account_initializes_firebase_only_once(self):
        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory) / "credential.json"
            key_path.touch()
            app = SimpleNamespace(project_id="skinai-b0465")
            with (
                patch.dict(
                    os.environ,
                    {
                        "GOOGLE_APPLICATION_CREDENTIALS": str(key_path),
                        "FIREBASE_PROJECT_ID": "skinai-b0465",
                    },
                    clear=True,
                ),
                patch.object(firebase_app, "load_dotenv") as load_dotenv,
                patch(
                    "firebase_admin.credentials.Certificate",
                    return_value=SimpleNamespace(project_id="skinai-b0465"),
                ) as certificate,
                patch.object(
                    firebase_admin,
                    "get_app",
                    side_effect=[ValueError("not initialized"), app],
                ),
                patch.object(
                    firebase_admin,
                    "initialize_app",
                    return_value=app,
                ) as initialize,
            ):
                first = firebase_app.initialize_firebase_app()
                second = firebase_app.initialize_firebase_app()

        self.assertIs(first, app)
        self.assertIs(second, app)
        self.assertEqual(initialize.call_count, 1)
        self.assertEqual(certificate.call_count, 2)
        self.assertEqual(load_dotenv.call_count, 2)
        self.assertEqual(
            initialize.call_args.kwargs["options"],
            {"projectId": "skinai-b0465"},
        )


if __name__ == "__main__":
    unittest.main()
