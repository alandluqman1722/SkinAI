from __future__ import annotations

import logging
import re
import threading
import time
from datetime import datetime, timezone
from io import BytesIO
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import Response
from google.api_core.exceptions import GoogleAPIError
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .firebase_app import get_firebase_app
from .firebase_auth import require_firebase_user
from .private_image_storage import (
    delete_image,
    image_exists,
    read_image,
    store_image,
)
from .skinchat_ai import (
    classify_question,
    daily_message_limit,
    generate_response,
    gemini_enabled,
    policy_response,
    selected_language,
)

router = APIRouter(
    prefix="/api/skinchat/conversations",
    tags=["SkinChat AI"],
)
_logger = logging.getLogger(__name__)
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_MAX_IMAGE_PIXELS = 40_000_000
_SUPPORTED_FORMATS = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
}
_RATE_LIMIT_WINDOW = 60.0
_RATE_LIMIT_REQUESTS = 30
_rate_lock = threading.Lock()
_rate_requests: dict[str, list[float]] = {}
_client_message_id_pattern = re.compile(r"^[A-Za-z0-9_-]{1,80}$")
_IMAGE_CONTEXT_TRANSLATIONS = {
    "ku": "ئەم وێنەیە بە پارێزراوی هەڵگیراوە، بەڵام بۆ Gemini نانێردرێت و "
    "شیکردنەوەی وێنەیی ئەنجام نادرێت.",
    "bad": "ئەڤ وێنە ب پاراستی هاتیە هەڵگرتن، لێ بۆ Gemini ناهێتە فرێکرن و "
    "شیکرنا وێنەیی ناهێتە ئەنجامدان.",
    "ar": "تم حفظ الصورة بأمان، لكنها لا تُرسل إلى Gemini ولا تُحلل بصريًا.",
    "en": "This image is stored securely but is never sent to Gemini or visually analyzed.",
}
_SUPPORTED_LANGUAGES = {"en", "ar", "ku", "bad"}


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ScanContext(StrictModel):
    scan_id: str = Field(min_length=1, max_length=100)
    detected_condition: str = Field(min_length=1, max_length=500)
    confidence: float = Field(ge=0, le=100)
    scan_date: datetime
    summary: str | None = Field(default=None, max_length=10000)
    body_location: str | None = Field(default=None, max_length=200)
    has_original_image: bool = False


class NewConversation(StrictModel):
    scan_context: ScanContext | None = None


class NewMessage(StrictModel):
    content: str = Field(min_length=1, max_length=4000)
    client_message_id: str | None = Field(default=None, max_length=80)
    language: str | None = Field(default=None, pattern=r"^(en|ar|ku|bad)$")

    @field_validator("content")
    @classmethod
    def content_must_not_be_blank(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Message content cannot be blank.")
        return normalized


def _database():
    try:
        from firebase_admin import firestore

        return firestore.client(app=get_firebase_app())
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "SkinChat database is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="SkinChat storage is not configured.",
        ) from error
    except GoogleAPIError as error:
        _logger.error("SkinChat database request failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="SkinChat storage is temporarily unavailable.",
        ) from error


def _user_conversations(uid: str):
    return (
        _database()
        .collection("users")
        .document(uid)
        .collection("skinchat_conversations")
    )


def _conversation(uid: str, conversation_id: str):
    reference = _user_conversations(uid).document(conversation_id)
    try:
        snapshot = reference.get()
    except GoogleAPIError as error:
        _logger.error("SkinChat conversation read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load the conversation.",
        ) from error
    if not snapshot.exists:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    return reference, snapshot.to_dict() or {}


def _check_rate_limit(uid: str) -> None:
    now = time.monotonic()
    with _rate_lock:
        recent = [
            stamp
            for stamp in _rate_requests.get(uid, [])
            if now - stamp < _RATE_LIMIT_WINDOW
        ]
        if len(recent) >= _RATE_LIMIT_REQUESTS:
            raise HTTPException(
                status_code=429,
                detail="Too many SkinChat requests. Please wait before retrying.",
                headers={"Retry-After": "60"},
            )
        recent.append(now)
        _rate_requests[uid] = recent


def _reserve_daily_message(
    uid: str,
    claims: dict[str, Any],
    client_message_id: str,
) -> None:
    try:
        from google.cloud.firestore_v1 import transactional

        db = _database()
        today = datetime.now(timezone.utc).date().isoformat()
        daily_limit = daily_message_limit(claims)
        usage_reference = (
            db.collection("users")
            .document(uid)
            .collection("skinchat_usage")
            .document(today)
        )
        request_reference = usage_reference.collection("requests").document(
            client_message_id
        )
        transaction = db.transaction(max_attempts=5)

        @transactional
        def reserve(transaction: Any) -> None:
            request_snapshot = request_reference.get(transaction=transaction)
            if request_snapshot.exists:
                return
            usage_snapshot = usage_reference.get(transaction=transaction)
            usage = usage_snapshot.to_dict() or {}
            count = usage.get("count", 0)
            if isinstance(count, bool) or not isinstance(count, int) or count < 0:
                raise HTTPException(
                    status_code=503,
                    detail="SkinChat usage data is unavailable.",
                )
            if count >= daily_limit:
                raise HTTPException(
                    status_code=429,
                    detail="Your daily SkinChat message limit has been reached.",
                )
            transaction.set(
                usage_reference,
                {"count": count + 1, "date": today},
                merge=True,
            )
            transaction.set(
                request_reference,
                {"reserved_at": _iso_now()},
            )

        reserve(transaction)
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "SkinChat daily usage reservation failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not verify the SkinChat daily message allowance.",
        ) from error
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "SkinChat usage storage is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not verify the SkinChat daily message allowance.",
        ) from error


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _serialize_conversation(snapshot: Any) -> dict[str, Any]:
    data = snapshot.to_dict() or {}
    data["conversation_id"] = snapshot.id
    data.pop("user_id", None)
    file_path = data.get("image_file_path")
    data["image_available"] = (
        isinstance(file_path, str) and image_exists(file_path)
    )
    for field in (
        "image_object",
        "image_owner_uid",
        "image_file_path",
        "image_file_size",
        "image_content_type",
    ):
        data.pop(field, None)
    return data


@router.post("", status_code=201)
def create_conversation(
    request: NewConversation | None = None,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    uid = user["uid"]
    _check_rate_limit(uid)
    now = _iso_now()
    conversation_id = str(uuid4())
    record = {
        "user_id": uid,
        "uploaded_image_id": None,
        "image_owner_uid": None,
        "image_file_path": None,
        "image_file_size": None,
        "image_content_type": None,
        "image_available": False,
        "image_upload_timestamp": None,
        "initial_analysis": None,
        "detected_visual_features": [],
        "detected_language": "en",
        "scan_context": (
            request.scan_context.model_dump(mode="json")
            if request is not None and request.scan_context is not None
            else None
        ),
        "created_at": now,
        "updated_at": now,
    }
    try:
        _user_conversations(uid).document(conversation_id).set(record)
    except GoogleAPIError as error:
        _logger.error("SkinChat conversation creation failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not create the conversation.",
        ) from error
    response_record = dict(record)
    response_record.pop("user_id", None)
    for field in (
        "image_owner_uid",
        "image_file_path",
        "image_file_size",
        "image_content_type",
    ):
        response_record.pop(field, None)
    return {"conversation_id": conversation_id, **response_record}


@router.get("")
def list_conversations(
    user: dict[str, Any] = Depends(require_firebase_user),
) -> list[dict[str, Any]]:
    _check_rate_limit(user["uid"])
    try:
        snapshots = list(_user_conversations(user["uid"]).stream())
    except GoogleAPIError as error:
        _logger.error("SkinChat conversation list failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load conversations.",
        ) from error
    conversations = [_serialize_conversation(item) for item in snapshots]
    return sorted(
        conversations,
        key=lambda item: item.get("updated_at", ""),
        reverse=True,
    )


@router.get("/{conversation_id}")
def get_conversation(
    conversation_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    _check_rate_limit(user["uid"])
    _, data = _conversation(user["uid"], conversation_id)
    safe_data = dict(data)
    safe_data.pop("user_id", None)
    file_path = safe_data.get("image_file_path")
    safe_data["image_available"] = (
        isinstance(file_path, str) and image_exists(file_path)
    )
    for field in (
        "image_object",
        "image_owner_uid",
        "image_file_path",
        "image_file_size",
        "image_content_type",
    ):
        safe_data.pop(field, None)
    return {"conversation_id": conversation_id, **safe_data}


async def _validated_image(file: UploadFile) -> tuple[bytes, str]:
    if (
        not isinstance(file.content_type, str)
        or file.content_type not in _SUPPORTED_FORMATS.values()
    ):
        await file.close()
        raise HTTPException(
            status_code=415,
            detail="Upload a JPEG, PNG, or WebP image.",
        )
    content_type = file.content_type
    chunks: list[bytes] = []
    total = 0
    try:
        while chunk := await file.read(64 * 1024):
            total += len(chunk)
            if total > _MAX_UPLOAD_BYTES:
                raise HTTPException(
                    status_code=413,
                    detail="The image exceeds the 10 MB upload limit.",
                )
            chunks.append(chunk)
    finally:
        await file.close()
    raw = b"".join(chunks)
    if not raw:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")
    try:
        with Image.open(BytesIO(raw)) as source:
            expected_type = _SUPPORTED_FORMATS.get(source.format or "")
            if expected_type is None or expected_type != content_type:
                raise HTTPException(
                    status_code=415,
                    detail="The uploaded image format does not match its content type.",
                )
            if source.width * source.height > _MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=400,
                    detail="The image dimensions are too large to process safely.",
                )
            source.verify()
    except HTTPException:
        raise
    except (
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        UnidentifiedImageError,
        OSError,
        ValueError,
    ) as error:
        raise HTTPException(
            status_code=400,
            detail="The uploaded file is not a valid supported image.",
        ) from error
    return raw, content_type


@router.post("/{conversation_id}/image", status_code=201)
async def upload_conversation_image(
    conversation_id: str,
    file: UploadFile = File(...),
    language: str = Form(default="en"),
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    uid = user["uid"]
    _check_rate_limit(uid)
    reference, conversation = _conversation(uid, conversation_id)
    existing_file_path = conversation.get("image_file_path")
    if (
        conversation.get("uploaded_image_id")
        and isinstance(existing_file_path, str)
        and image_exists(existing_file_path)
    ):
        if (
            conversation.get("image_owner_uid") != uid
            or conversation.get("uploaded_image_id") != existing_file_path
        ):
            raise HTTPException(status_code=403, detail="Image ownership check failed.")
        raise HTTPException(
            status_code=409,
            detail="This conversation already has an image. Start a new conversation.",
        )
    image_bytes, content_type = await _validated_image(file)
    try:
        image_id, file_path = store_image(image_bytes)
    except OSError as error:
        _logger.error("SkinChat local image upload failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not securely upload the image.",
        ) from error

    timestamp = _iso_now()
    detected_language = (
        language if language in _SUPPORTED_LANGUAGES else "en"
    )
    analysis = _IMAGE_CONTEXT_TRANSLATIONS[detected_language]
    try:
        reference.update(
            {
                "uploaded_image_id": image_id,
                "image_owner_uid": uid,
                "image_file_path": file_path,
                "image_file_size": len(image_bytes),
                "image_content_type": content_type,
                "image_upload_timestamp": timestamp,
                "initial_analysis": analysis,
                "detected_visual_features": [],
                "detected_language": detected_language,
                "updated_at": timestamp,
            }
        )
    except GoogleAPIError as error:
        try:
            delete_image(file_path)
        except OSError as cleanup_error:
            _logger.error(
                "Orphaned SkinChat image cleanup failed (%s).",
                type(cleanup_error).__name__,
            )
        _logger.error("SkinChat image metadata save failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not save uploaded image metadata.",
        ) from error
    return {
        "conversation_id": conversation_id,
        "uploaded_image_id": image_id,
        "image_file_size": len(image_bytes),
        "image_upload_timestamp": timestamp,
        "initial_analysis": analysis,
        "detected_visual_features": [],
        "detected_language": detected_language,
    }


@router.get("/{conversation_id}/image")
def read_conversation_image(
    conversation_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    uid = user["uid"]
    _check_rate_limit(uid)
    _, conversation = _conversation(uid, conversation_id)
    file_path = conversation.get("image_file_path")
    image_id = conversation.get("uploaded_image_id")
    if (
        not file_path
        or conversation.get("image_owner_uid") != uid
        or image_id != file_path
    ):
        raise HTTPException(status_code=404, detail="Conversation image not found.")
    try:
        content = read_image(file_path)
    except FileNotFoundError as error:
        raise HTTPException(
            status_code=404,
            detail="Conversation image not found.",
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=404,
            detail="Conversation image not found.",
        ) from error
    except OSError as error:
        _logger.error("SkinChat image read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load the conversation image.",
        ) from error
    content_type = conversation.get("image_content_type")
    if content_type not in _SUPPORTED_FORMATS.values():
        raise HTTPException(status_code=500, detail="Stored image metadata is invalid.")
    return Response(
        content=content,
        media_type=content_type,
        headers={
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.post("/{conversation_id}/messages")
async def send_message(
    conversation_id: str,
    request: NewMessage,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    uid = user["uid"]
    _check_rate_limit(uid)
    reference, conversation = _conversation(uid, conversation_id)
    language = selected_language(request.content, request.language)
    messages = reference.collection("messages")
    client_id = request.client_message_id or str(uuid4())
    if not _client_message_id_pattern.fullmatch(client_id):
        raise HTTPException(status_code=422, detail="Invalid client message id.")
    user_message_id = f"user-{client_id}"
    user_reference = messages.document(user_message_id)
    timestamp = _iso_now()
    try:
        existing = user_reference.get()
        existing_data = existing.to_dict() or {}
        if not existing.exists:
            user_reference.set(
                {
                    "role": "user",
                    "content": request.content.strip(),
                    "language": language,
                    "client_message_id": client_id,
                    "created_at": timestamp,
                }
            )
        else:
            if existing_data.get("content") != request.content.strip():
                raise HTTPException(
                    status_code=409,
                    detail="This client message id has already been used.",
                )
            timestamp = existing_data.get("created_at", timestamp)
        history_snapshots = messages.order_by(
            "created_at",
            direction="DESCENDING",
        ).limit(20).stream()
        history_snapshots = list(history_snapshots)
        history_snapshots.reverse()
        history = []
        for history_snapshot in history_snapshots:
            if history_snapshot.id == user_message_id:
                continue
            history_data = history_snapshot.to_dict() or {}
            if (
                history_data.get("role") in {"user", "assistant"}
                and isinstance(history_data.get("content"), str)
            ):
                history.append(
                    {
                        "role": history_data["role"],
                        "content": history_data["content"],
                    }
                )
        existing_reply = messages.document(f"assistant-{client_id}").get()
        if existing_reply.exists:
            return {
                "message": {
                    "message_id": user_message_id,
                    **(existing.to_dict() or {}),
                },
                "reply": {
                    "message_id": f"assistant-{client_id}",
                    **(existing_reply.to_dict() or {}),
                },
            }
    except GoogleAPIError as error:
        _logger.error("SkinChat message history read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not save or load conversation messages.",
        ) from error

    _reserve_daily_message(uid, user, client_id)
    recent_user_messages = [
        message["content"]
        for message in history
        if message["role"] == "user"
    ]
    scan_context = conversation.get("scan_context")
    category = classify_question(
        request.content,
        recent_user_messages,
        has_scan_context=isinstance(scan_context, dict),
    )
    if category != "skincare":
        answer = policy_response(category, language)
    else:
        if not gemini_enabled():
            raise HTTPException(
                status_code=503,
                detail="SkinChat AI is not enabled on the server.",
            )
        response_options: dict[str, Any] = {
            "question": request.content.strip(),
            "history": history,
            "language": language,
        }
        if isinstance(scan_context, dict):
            response_options["scan_context"] = scan_context
        answer = await generate_response(**response_options)
    assistant_id = f"assistant-{client_id}"
    assistant_record = {
        "role": "assistant",
        "content": answer,
        "language": language,
        "created_at": _iso_now(),
    }
    try:
        messages.document(assistant_id).set(assistant_record)
        reference.update(
            {"detected_language": language, "updated_at": assistant_record["created_at"]}
        )
    except GoogleAPIError as error:
        _logger.error("SkinChat reply persistence failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="The AI answered, but the reply could not be saved.",
        ) from error
    return {
        "message": {
            "message_id": user_message_id,
            "role": "user",
            "content": request.content.strip(),
            "language": language,
            "created_at": timestamp,
        },
        "reply": {"message_id": assistant_id, **assistant_record},
    }


@router.get("/{conversation_id}/messages")
def list_messages(
    conversation_id: str,
    limit: int = Query(default=50, ge=1, le=100),
    before: str | None = Query(default=None, max_length=40),
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    _check_rate_limit(user["uid"])
    reference, _ = _conversation(user["uid"], conversation_id)
    try:
        query = reference.collection("messages").order_by(
            "created_at",
            direction="DESCENDING",
        )
        if before:
            query = query.where("created_at", "<", before)
        snapshots = list(query.limit(limit + 1).stream())
    except GoogleAPIError as error:
        _logger.error("SkinChat messages read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load conversation messages.",
        ) from error
    has_more = len(snapshots) > limit
    selected = snapshots[:limit]
    selected.reverse()
    return {
        "messages": [
            {"message_id": item.id, **(item.to_dict() or {})}
            for item in selected
        ],
        "next_before": (
            (selected[0].to_dict() or {}).get("created_at")
            if has_more and selected
            else None
        ),
    }


@router.delete("/{conversation_id}/messages/{message_id}", status_code=204)
def delete_message(
    conversation_id: str,
    message_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    _check_rate_limit(user["uid"])
    reference, _ = _conversation(user["uid"], conversation_id)
    messages = reference.collection("messages")
    try:
        message_reference = messages.document(message_id)
        snapshot = message_reference.get()
        if not snapshot.exists:
            raise HTTPException(status_code=404, detail="Message not found.")
        message_reference.delete()
        content = snapshot.to_dict() or {}
        client_message_id = content.get("client_message_id")
        if (
            content.get("role") == "user"
            and isinstance(client_message_id, str)
        ):
            messages.document(f"assistant-{client_message_id}").delete()
    except GoogleAPIError as error:
        _logger.error("SkinChat message deletion failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not delete the message.",
        ) from error
    return Response(status_code=204)


@router.delete("/{conversation_id}", status_code=204)
def delete_conversation(
    conversation_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    uid = user["uid"]
    _check_rate_limit(uid)
    reference, conversation = _conversation(uid, conversation_id)
    file_path = conversation.get("image_file_path")
    if file_path:
        if (
            conversation.get("image_owner_uid") != uid
            or conversation.get("uploaded_image_id") != file_path
        ):
            raise HTTPException(status_code=403, detail="Image ownership check failed.")
        try:
            delete_image(file_path)
        except ValueError as error:
            raise HTTPException(
                status_code=403,
                detail="Image ownership check failed.",
            ) from error
        except OSError as error:
            _logger.error("SkinChat image delete failed (%s).", type(error).__name__)
            raise HTTPException(
                status_code=503,
                detail="Could not delete the conversation image.",
            ) from error
    try:
        for message in reference.collection("messages").stream():
            message.reference.delete()
        reference.delete()
    except GoogleAPIError as error:
        _logger.error("SkinChat conversation delete failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not delete the conversation.",
        ) from error
    return Response(status_code=204)
