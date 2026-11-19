from __future__ import annotations

import logging
import os
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Any, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from google.api_core.exceptions import GoogleAPIError
from pydantic import BaseModel, ConfigDict, Field

from .admin_api import _database, _iter_auth_users
from .admin_audit import create_audit_entry
from .email_block import email_document_id
from .firebase_app import get_firebase_app
from .firebase_auth import require_admin

_logger = logging.getLogger(__name__)
_USER_UID_PATTERN = r"^[A-Za-z0-9_-]{1,128}$"
_CURSOR_TTL = timedelta(minutes=15)
_MAX_SEARCH_PAGES = 10

router = APIRouter(prefix="/api/admin/users", tags=["Admin users"])


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AdminUser(StrictModel):
    uid: str
    email: str | None
    display_name: str | None
    created_at: datetime
    last_sign_in: datetime | None
    email_verified: bool
    disabled: bool
    blocked: bool
    plan: Literal["free", "paid"]


class AdminUsersPage(StrictModel):
    users: list[AdminUser]
    next_cursor: str | None


class AdminUserUsage(StrictModel):
    date: str
    daily_skinchat_usage: int = Field(ge=0)
    scans_total: int = Field(ge=0)


class BlockStateRequest(StrictModel):
    blocked: bool


class DisabledStateRequest(StrictModel):
    disabled: bool


class DeletionRequest(StrictModel):
    confirmation: Literal[True]


def _auth_context():
    try:
        from firebase_admin import auth
        from firebase_admin.exceptions import FirebaseError
        from google.auth.exceptions import DefaultCredentialsError
    except ImportError as error:
        _logger.error(
            "Admin user authentication dependencies are unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user service is temporarily unavailable.",
        ) from error
    try:
        return auth, get_firebase_app(), FirebaseError, DefaultCredentialsError
    except (DefaultCredentialsError, FirebaseError, RuntimeError) as error:
        _logger.error(
            "Admin user authentication is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user service is temporarily unavailable.",
        ) from error


def _email_block_key() -> str:
    key = os.getenv("EMAIL_BLOCK_HMAC_KEY")
    if not key:
        _logger.error("Required email blocklist configuration is unavailable.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user service is temporarily unavailable.",
        )
    return key


def _blocked_email(database: Any, email: str | None, key: str) -> bool:
    if email is None:
        return False
    return (
        database.collection("blocked_emails")
        .document(email_document_id(email, key))
        .get()
        .exists
    )


def _auth_datetime(value: object, *, required: bool) -> datetime | None:
    if value is None and not required:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user data is temporarily unavailable.",
        )
    try:
        return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
    except (OverflowError, OSError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user data is temporarily unavailable.",
        ) from error


def _user_summary(user: Any, *, blocked: bool) -> AdminUser:
    metadata = getattr(user, "user_metadata", None)
    claims = getattr(user, "custom_claims", None) or {}
    is_paid = (
        claims.get("skinchat_plan") == "paid"
        and claims.get("skinchat_subscription_status") == "active"
    )
    return AdminUser(
        uid=user.uid,
        email=user.email,
        display_name=user.display_name,
        created_at=_auth_datetime(
            getattr(metadata, "creation_timestamp", None),
            required=True,
        ),
        last_sign_in=_auth_datetime(
            getattr(metadata, "last_sign_in_timestamp", None),
            required=False,
        ),
        email_verified=bool(user.email_verified),
        disabled=bool(user.disabled),
        blocked=blocked,
        plan="paid" if is_paid else "free",
    )


def _search_matches(user: Any, search: str) -> bool:
    if not search:
        return True
    normalized = search.casefold()
    return any(
        normalized in value.casefold()
        for value in (user.email, user.display_name)
        if isinstance(value, str)
    )


def _get_user(auth: Any, firebase_app: Any, uid: str) -> Any:
    try:
        return auth.get_user(uid, app=firebase_app)
    except auth.UserNotFoundError as error:
        raise HTTPException(status_code=404, detail="User not found.") from error


def _lookup_user_page(
    auth: Any,
    firebase_app: Any,
    database: Any,
    *,
    page_token: str | None,
    page_size: int,
    search: str,
    blocked_filter: bool | None,
    disabled_filter: bool | None,
    hmac_key: str,
) -> tuple[list[AdminUser], str | None]:
    users: list[AdminUser] = []
    current_token = page_token
    max_pages = (
        _MAX_SEARCH_PAGES
        if search or blocked_filter is not None or disabled_filter is not None
        else 1
    )
    for _ in range(max_pages):
        page = auth.list_users(
            max_results=page_size,
            page_token=current_token,
            app=firebase_app,
        )
        for user in page.users:
            if not _search_matches(user, search):
                continue
            blocked = _blocked_email(database, user.email, hmac_key)
            if blocked_filter is not None and blocked != blocked_filter:
                continue
            if disabled_filter is not None and bool(user.disabled) != disabled_filter:
                continue
            users.append(_user_summary(user, blocked=blocked))
        next_token = page.next_page_token
        if users or not next_token:
            return users, next_token
        current_token = next_token
    return users, current_token


def _cursor_reference(database: Any, cursor: str):
    return database.collection("admin_user_cursors").document(cursor)


def _cursor_page_token(
    database: Any,
    *,
    cursor: str | None,
    admin_uid: str,
    search: str,
    page_size: int,
    blocked_filter: bool | None,
    disabled_filter: bool | None,
) -> str | None:
    if cursor is None:
        return None
    reference = _cursor_reference(database, cursor)
    snapshot = reference.get()
    cursor_data = snapshot.to_dict() or {}
    expected_filters = {
        "search": search,
        "page_size": page_size,
        "blocked": blocked_filter,
        "disabled": disabled_filter,
    }
    if (
        not snapshot.exists
        or cursor_data.get("owner_uid") != admin_uid
        or any(cursor_data.get(key) != value for key, value in expected_filters.items())
        or not isinstance(cursor_data.get("page_token"), str)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This user-list cursor is invalid. Refresh the list.",
        )
    expires_at = cursor_data.get("expires_at")
    if not isinstance(expires_at, datetime):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This user-list cursor is invalid. Refresh the list.",
        )
    expiration = expires_at
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    if expiration <= datetime.now(timezone.utc):
        reference.delete()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This user-list cursor expired. Refresh the list.",
        )
    return cursor_data["page_token"]


def _save_next_cursor(
    database: Any,
    *,
    page_token: str | None,
    admin_uid: str,
    search: str,
    page_size: int,
    blocked_filter: bool | None,
    disabled_filter: bool | None,
) -> str | None:
    if page_token is None:
        return None
    cursor = str(uuid4())
    _cursor_reference(database, cursor).create(
        {
            "owner_uid": admin_uid,
            "page_token": page_token,
            "search": search,
            "page_size": page_size,
            "blocked": blocked_filter,
            "disabled": disabled_filter,
            "expires_at": datetime.now(timezone.utc) + _CURSOR_TTL,
        }
    )
    return cursor


@router.get("", response_model=AdminUsersPage)
def list_admin_users(
    search: str = Query(default="", max_length=100),
    page_size: int = Query(default=50, ge=1, le=100),
    cursor: str | None = Query(
        default=None,
        min_length=36,
        max_length=36,
        pattern=r"^[a-f0-9-]{36}$",
    ),
    blocked: bool | None = Query(default=None),
    disabled: bool | None = Query(default=None),
    admin: dict[str, Any] = Depends(require_admin),
) -> AdminUsersPage:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    database = _database()
    normalized_search = search.strip()
    hmac_key = _email_block_key()
    try:
        page_token = _cursor_page_token(
            database,
            cursor=cursor,
            admin_uid=admin["uid"],
            search=normalized_search,
            page_size=page_size,
            blocked_filter=blocked,
            disabled_filter=disabled,
        )
        users, next_page_token = _lookup_user_page(
            auth,
            firebase_app,
            database,
            page_token=page_token,
            page_size=page_size,
            search=normalized_search,
            blocked_filter=blocked,
            disabled_filter=disabled,
            hmac_key=hmac_key,
        )
        next_cursor = _save_next_cursor(
            database,
            page_token=next_page_token,
            admin_uid=admin["uid"],
            search=normalized_search,
            page_size=page_size,
            blocked_filter=blocked,
            disabled_filter=disabled,
        )
        return AdminUsersPage(users=users, next_cursor=next_cursor)
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin user list request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user data is temporarily unavailable.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin user list storage request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user data is temporarily unavailable.",
        ) from error


@router.get("/{uid}/usage", response_model=AdminUserUsage)
def get_admin_user_usage(
    uid: str = Path(pattern=_USER_UID_PATTERN),
    _: dict[str, Any] = Depends(require_admin),
) -> AdminUserUsage:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    try:
        _get_user(auth, firebase_app, uid)
        database = _database()
        today = datetime.now(timezone.utc).date().isoformat()
        user_reference = database.collection("users").document(uid)
        usage_snapshot = (
            user_reference.collection("skinchat_usage").document(today).get()
        )
        usage_count = (usage_snapshot.to_dict() or {}).get("count", 0)
        if (
            isinstance(usage_count, bool)
            or not isinstance(usage_count, int)
            or usage_count < 0
        ):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Admin user usage data is temporarily unavailable.",
            )
        scans_total = sum(
            1
            for _ in (
                user_reference.collection("medical_records")
                .where("type", "==", "scans")
                .select(["type"])
                .stream()
            )
        )
        return AdminUserUsage(
            date=today,
            daily_skinchat_usage=usage_count,
            scans_total=scans_total,
        )
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin user usage request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user usage data is temporarily unavailable.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin user usage storage request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin user usage data is temporarily unavailable.",
        ) from error


def _ensure_another_admin_remains(
    auth: Any,
    firebase_app: Any,
    database: Any,
    *,
    target_uid: str,
    hmac_key: str,
) -> None:
    for user in _iter_auth_users(firebase_app):
        if user.uid == target_uid or user.disabled:
            continue
        claims = getattr(user, "custom_claims", None) or {}
        if claims.get("admin") is not True:
            continue
        if _blocked_email(database, user.email, hmac_key):
            continue
        return
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="The last active administrator cannot be blocked or disabled.",
    )


def _acquire_mutation_lease(database: Any, admin_uid: str) -> tuple[Any, str]:
    from google.cloud.firestore_v1 import transactional

    reference = database.collection("admin_security_locks").document(
        "user_account_mutation",
    )
    owner = str(uuid4())
    transaction = database.transaction(max_attempts=5)

    @transactional
    def acquire(transaction: Any) -> None:
        snapshot = reference.get(transaction=transaction)
        current = snapshot.to_dict() or {}
        expires_at = current.get("expires_at")
        if isinstance(expires_at, str):
            try:
                expiration = datetime.fromisoformat(expires_at)
            except ValueError:
                expiration = datetime.min.replace(tzinfo=timezone.utc)
            if expiration > datetime.now(timezone.utc):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Another account-security action is in progress.",
                )
        transaction.set(
            reference,
            {
                "owner": owner,
                "admin_uid": admin_uid,
                "expires_at": (
                    datetime.now(timezone.utc) + timedelta(minutes=5)
                ).isoformat(),
            },
        )

    acquire(transaction)
    return reference, owner


def _release_mutation_lease(database: Any, reference: Any, owner: str) -> None:
    from google.cloud.firestore_v1 import transactional

    transaction = database.transaction(max_attempts=5)

    @transactional
    def release(transaction: Any) -> None:
        snapshot = reference.get(transaction=transaction)
        if (snapshot.to_dict() or {}).get("owner") == owner:
            transaction.delete(reference)

    release(transaction)


@contextmanager
def _admin_user_mutation_lease(database: Any, admin_uid: str):
    reference, owner = _acquire_mutation_lease(database, admin_uid)
    try:
        yield
    finally:
        try:
            _release_mutation_lease(database, reference, owner)
        except GoogleAPIError as error:
            _logger.error(
                "Admin account-security lock could not be released (%s).",
                type(error).__name__,
            )


def _change_block_state(
    database: Any,
    *,
    uid: str,
    email: str,
    hmac_key: str,
    blocked: bool,
    admin_uid: str,
) -> bool:
    from google.cloud.firestore_v1 import transactional

    block_reference = database.collection("blocked_emails").document(
        email_document_id(email, hmac_key),
    )
    transaction = database.transaction(max_attempts=5)

    @transactional
    def update(transaction: Any) -> bool:
        snapshot = block_reference.get(transaction=transaction)
        before_blocked = snapshot.exists
        if before_blocked == blocked:
            return False
        if blocked:
            transaction.set(
                block_reference,
                {
                    "created_at": datetime.now(timezone.utc).isoformat(),
                    "created_by": admin_uid,
                },
            )
        else:
            transaction.delete(block_reference)
        create_audit_entry(
            database,
            admin_uid=admin_uid,
            action="user.blocked" if blocked else "user.unblocked",
            target_type="user",
            target_id=uid,
            before={"blocked": before_blocked},
            after={"blocked": blocked},
            transaction=transaction,
        )
        return True

    return update(transaction)


@router.patch("/{uid}/block")
def set_admin_user_blocked(
    payload: BlockStateRequest,
    uid: str = Path(pattern=_USER_UID_PATTERN),
    admin: dict[str, Any] = Depends(require_admin),
) -> dict[str, bool]:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    database = _database()
    try:
        with _admin_user_mutation_lease(database, admin["uid"]):
            target = _get_user(auth, firebase_app, uid)
            if payload.blocked and uid == admin["uid"]:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Administrators cannot block their own account.",
                )
            if target.email is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="This user has no email address to block.",
                )
            hmac_key = _email_block_key()
            if payload.blocked and (
                getattr(target, "custom_claims", None) or {}
            ).get("admin") is True:
                _ensure_another_admin_remains(
                    auth,
                    firebase_app,
                    database,
                    target_uid=uid,
                    hmac_key=hmac_key,
                )
            _change_block_state(
                database,
                uid=uid,
                email=target.email,
                hmac_key=hmac_key,
                blocked=payload.blocked,
                admin_uid=admin["uid"],
            )
        return {"blocked": payload.blocked}
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin user block action failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The user block action could not be completed.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin user block storage action failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The user block action could not be completed.",
        ) from error


@router.patch("/{uid}/disabled")
def set_admin_user_disabled(
    payload: DisabledStateRequest,
    uid: str = Path(pattern=_USER_UID_PATTERN),
    admin: dict[str, Any] = Depends(require_admin),
) -> dict[str, bool]:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    database = _database()
    try:
        with _admin_user_mutation_lease(database, admin["uid"]):
            target = _get_user(auth, firebase_app, uid)
            before_disabled = bool(target.disabled)
            if payload.disabled and uid == admin["uid"]:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Administrators cannot disable their own account.",
                )
            if before_disabled == payload.disabled:
                return {"disabled": payload.disabled}
            if payload.disabled and (
                getattr(target, "custom_claims", None) or {}
            ).get("admin") is True:
                _ensure_another_admin_remains(
                    auth,
                    firebase_app,
                    database,
                    target_uid=uid,
                    hmac_key=_email_block_key(),
                )
            create_audit_entry(
                database,
                admin_uid=admin["uid"],
                action=(
                    "user.disable_requested"
                    if payload.disabled
                    else "user.enable_requested"
                ),
                target_type="user",
                target_id=uid,
                before={"disabled": before_disabled},
                after={"disabled": payload.disabled},
            )
            auth.update_user(uid, disabled=payload.disabled, app=firebase_app)
            create_audit_entry(
                database,
                admin_uid=admin["uid"],
                action="user.disabled" if payload.disabled else "user.enabled",
                target_type="user",
                target_id=uid,
                before={"disabled": before_disabled},
                after={"disabled": payload.disabled},
            )
        return {"disabled": payload.disabled}
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin user account-state action failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The user account action could not be completed.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin user account audit failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The user account action could not be completed.",
        ) from error


@router.post("/{uid}/password-reset")
def request_admin_password_reset(
    uid: str = Path(pattern=_USER_UID_PATTERN),
    admin: dict[str, Any] = Depends(require_admin),
) -> dict[str, bool]:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    try:
        target = _get_user(auth, firebase_app, uid)
        if not target.email:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="This user has no email address.",
            )
        create_audit_entry(
            _database(),
            admin_uid=admin["uid"],
            action="user.password_reset_requested",
            target_type="user",
            target_id=uid,
            after={"requested": True},
        )
        return {"requested": True}
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin password reset request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The password reset email could not be requested.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin password reset audit failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The password reset email could not be requested.",
        ) from error


@router.post("/{uid}/deletion-requests", status_code=201)
def request_user_data_deletion(
    payload: DeletionRequest,
    uid: str = Path(pattern=_USER_UID_PATTERN),
    admin: dict[str, Any] = Depends(require_admin),
) -> dict[str, str]:
    auth, firebase_app, FirebaseError, DefaultCredentialsError = _auth_context()
    database = _database()
    try:
        _get_user(auth, firebase_app, uid)
        request_id = str(uuid4())
        request_reference = database.collection("admin_data_deletion_requests").document(
            request_id,
        )
        transaction = database.transaction(max_attempts=5)
        from google.cloud.firestore_v1 import transactional

        @transactional
        def create_request(transaction: Any) -> None:
            transaction.create(
                request_reference,
                {
                    "target_uid": uid,
                    "requested_by": admin["uid"],
                    "status": "pending",
                    "created_at": datetime.now(timezone.utc).isoformat(),
                },
            )
            create_audit_entry(
                database,
                admin_uid=admin["uid"],
                action="user.data_deletion_requested",
                target_type="user",
                target_id=uid,
                after={"request_status": "pending"},
                transaction=transaction,
            )

        create_request(transaction)
        return {"request_id": request_id}
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin user deletion-request action failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The data deletion request could not be created.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin user deletion-request storage failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The data deletion request could not be created.",
        ) from error
