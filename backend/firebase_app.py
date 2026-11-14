import json
import os
from pathlib import Path
from threading import Lock
from typing import Any

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
_initialization_lock = Lock()

_configuration_help = (
    "Firebase Admin could not start. Put the service-account JSON outside "
    "the repository, set GOOGLE_APPLICATION_CREDENTIALS (or "
    "FIREBASE_SERVICE_ACCOUNT_PATH) to its path, set FIREBASE_PROJECT_ID "
    "to the frontend Firebase project, then restart Uvicorn."
)


def _frontend_project_id() -> str | None:
    config_path = PROJECT_ROOT / "firebase.config.json"
    if not config_path.is_file():
        return None
    try:
        with config_path.open(encoding="utf-8") as config_file:
            config: dict[str, Any] = json.load(config_file)
    except (OSError, json.JSONDecodeError):
        raise RuntimeError(
            "Firebase client configuration could not be read. Fix "
            "firebase.config.json or set FIREBASE_PROJECT_ID to the same "
            "project used by the frontend."
        ) from None
    project_id = config.get("FIREBASE_PROJECT_ID")
    return project_id if isinstance(project_id, str) and project_id else None


def initialize_firebase_app(*, project_id: str | None = None):
    load_dotenv(PROJECT_ROOT / ".env", override=False)

    frontend_project_id = _frontend_project_id()
    configured_project_id = (
        project_id
        or os.getenv("FIREBASE_PROJECT_ID")
        or frontend_project_id
    )
    if not configured_project_id:
        raise RuntimeError(
            "Firebase project ID is missing. Set FIREBASE_PROJECT_ID in "
            ".env to the project used by the frontend, then restart Uvicorn."
        )
    if (
        frontend_project_id
        and configured_project_id != frontend_project_id
    ):
        raise RuntimeError(
            "FIREBASE_PROJECT_ID does not match the project's "
            "firebase.config.json. Use the same Firebase project for the "
            "frontend and backend."
        )

    service_account_path = (
        os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        or os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    )
    if not service_account_path:
        raise RuntimeError(_configuration_help)

    path = Path(service_account_path).expanduser()
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    if not path.is_file():
        raise RuntimeError(
            f"{_configuration_help} The configured credential file was not found."
        )

    import firebase_admin
    from firebase_admin import credentials

    try:
        certificate = credentials.Certificate(str(path))
    except (OSError, ValueError):
        raise RuntimeError(
            f"{_configuration_help} The credential file could not be loaded."
        ) from None

    if certificate.project_id != configured_project_id:
        raise RuntimeError(
            "The Firebase service-account project does not match "
            "FIREBASE_PROJECT_ID and the frontend project."
        )

    with _initialization_lock:
        try:
            firebase_app = firebase_admin.get_app()
        except ValueError:
            firebase_app = firebase_admin.initialize_app(
                certificate,
                options={"projectId": configured_project_id},
            )
        if firebase_app.project_id != configured_project_id:
            raise RuntimeError(
                "The existing Firebase Admin app is configured for a "
                "different project. Restart the backend with the correct "
                "service-account file and FIREBASE_PROJECT_ID."
            )
        return firebase_app


def get_firebase_app():
    import firebase_admin

    try:
        return firebase_admin.get_app()
    except ValueError:
        raise RuntimeError(
            "Firebase Admin was not initialized during application startup."
        ) from None
