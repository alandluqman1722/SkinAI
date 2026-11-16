from __future__ import annotations

import argparse
from typing import Any


def set_doctor_admin(auth_api: Any, firebase_app: Any, uid: str, enabled: bool) -> None:
    user = auth_api.get_user(uid, app=firebase_app)
    claims = dict(user.custom_claims or {})
    if enabled:
        claims["admin"] = True
    else:
        claims.pop("admin", None)
    auth_api.set_custom_user_claims(uid, claims or None, app=firebase_app)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Grant or revoke the SkinAI doctor-directory administrator claim."
    )
    parser.add_argument("uid", help="Firebase user ID to update.")
    parser.add_argument(
        "--revoke",
        action="store_true",
        help="Remove the doctor-directory admin claim instead of granting it.",
    )
    args = parser.parse_args()

    import firebase_admin.auth as auth

    from .firebase_app import initialize_firebase_app

    firebase_app = initialize_firebase_app()
    set_doctor_admin(auth, firebase_app, args.uid, enabled=not args.revoke)
    action = "revoked" if args.revoke else "granted"
    print(f"Doctor-directory administrator access {action} for UID {args.uid}.")


if __name__ == "__main__":
    main()
