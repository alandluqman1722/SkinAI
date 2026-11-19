import logging
import os
import threading
import time
from typing import Any

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

if __package__:
    from .email_block import email_document_id
    from .firebase_app import get_firebase_app
else:
    from email_block import email_document_id
    from firebase_app import get_firebase_app

_bearer_scheme = HTTPBearer(auto_error=False)
_logger = logging.getLogger(__name__)
_authentication_unavailable_detail = (
    "Authentication is temporarily unavailable. Please try again later."
)
_ADMIN_RATE_WINDOW_SECONDS = 60.0
_ADMIN_RATE_REQUEST_LIMIT = 60
_admin_rate_lock = threading.Lock()
_admin_rate_requests: dict[str, list[float]] = {}


def require_firebase_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> dict[str, Any]:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A Firebase ID token is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        import firebase_admin
        from firebase_admin import auth
        from firebase_admin import firestore
        from firebase_admin.exceptions import FirebaseError
        from google.auth.exceptions import DefaultCredentialsError
    except ImportError as error:
        _logger.error(
            "Firebase authentication dependencies are unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error

    try:
        firebase_app = get_firebase_app()
    except (DefaultCredentialsError, FirebaseError, RuntimeError) as error:
        _logger.error(
            "Firebase authentication is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error

    try:
        claims = auth.verify_id_token(
            credentials.credentials,
            app=firebase_app,
            check_revoked=True,
        )
    except DefaultCredentialsError as error:
        _logger.error(
            "Firebase credentials are unavailable during token verification (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error
    except auth.RevokedIdTokenError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase session has been revoked. Sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except auth.ExpiredIdTokenError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase ID token has expired. Sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except auth.UserDisabledError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase account is disabled.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except auth.UserNotFoundError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase account no longer exists.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except (auth.InvalidIdTokenError, ValueError) as error:
        _logger.info(
            "Firebase ID token verification rejected (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase ID token is invalid or expired.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except FirebaseError as error:
        _logger.error(
            "Firebase ID token verification service failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error

    if not isinstance(claims.get("uid"), str) or not claims["uid"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase ID token does not identify a user.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if claims.get("email_verified") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verify your email address before using this service.",
        )
    try:
        current_user = auth.get_user(claims["uid"], app=firebase_app)
    except auth.UserNotFoundError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="The Firebase account no longer exists.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Firebase account status lookup failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error

    if not current_user.email or not current_user.email_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Verify your current email address before using this service.",
        )

    email_block_hmac_key = os.getenv("EMAIL_BLOCK_HMAC_KEY")
    if not email_block_hmac_key:
        _logger.error(
            "Required configuration EMAIL_BLOCK_HMAC_KEY is missing; set it "
            "to the same secret used by Firebase Functions."
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        )
    try:
        blocked_email = (
            firestore.client(app=firebase_app)
            .collection("blocked_emails")
            .document(email_document_id(current_user.email, email_block_hmac_key))
            .get()
            .exists
        )
    except Exception as error:
        _logger.error(
            "Blocked-email status lookup failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=_authentication_unavailable_detail,
        ) from error
    if blocked_email:
        try:
            auth.revoke_refresh_tokens(claims["uid"], app=firebase_app)
        except (DefaultCredentialsError, FirebaseError) as error:
            _logger.error(
                "Blocked-account session revocation failed (%s).",
                type(error).__name__,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=_authentication_unavailable_detail,
            ) from error
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is not permitted to use the service.",
        )

    return claims


def require_admin(
    claims: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    if claims.get("admin") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access is required.",
        )
    now = time.monotonic()
    uid = claims["uid"]
    with _admin_rate_lock:
        recent = [
            request_time
            for request_time in _admin_rate_requests.get(uid, [])
            if now - request_time < _ADMIN_RATE_WINDOW_SECONDS
        ]
        if len(recent) >= _ADMIN_RATE_REQUEST_LIMIT:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many admin requests. Please retry shortly.",
                headers={"Retry-After": str(int(_ADMIN_RATE_WINDOW_SECONDS))},
            )
        recent.append(now)
        _admin_rate_requests[uid] = recent
    return claims
