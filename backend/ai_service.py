import json
import logging
import os
import threading
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from uuid import uuid4

from dotenv import load_dotenv
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from .firebase_auth import require_firebase_user
from .firebase_app import PROJECT_ROOT
from .ivy_ai_provider import IvyAIProvider, validate_ivy_response
from .medical_ai.safety_policy import classify_skin_analysis

load_dotenv(PROJECT_ROOT / ".env", override=False)

_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_MAX_IMAGE_PIXELS = 40_000_000
_MAX_IMAGE_SIDE = 2000
_SUPPORTED_FORMATS = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
    "BMP": "image/bmp",
    "GIF": "image/gif",
    "TIFF": "image/tiff",
}
_HISTORY_LOCK = threading.Lock()
_logger = logging.getLogger(__name__)

router = APIRouter(tags=["Ivy AI screening"])


def _mock_enabled() -> bool:
    return os.getenv("MOCK_API", "").strip() == "1"


async def _read_and_convert_image(image: UploadFile) -> bytes:
    _, jpeg_bytes, _ = await _read_original_and_convert_image(image)
    return jpeg_bytes


async def _read_original_and_convert_image(
    image: UploadFile,
) -> tuple[bytes, bytes, str]:
    chunks = []
    total_bytes = 0
    try:
        while chunk := await image.read(64 * 1024):
            total_bytes += len(chunk)
            if total_bytes > _MAX_UPLOAD_BYTES:
                raise HTTPException(
                    status_code=413,
                    detail="The image exceeds the 10 MB upload limit.",
                )
            chunks.append(chunk)
    finally:
        await image.close()

    raw = b"".join(chunks)
    if not raw:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")

    try:
        with Image.open(BytesIO(raw)) as source:
            expected_content_type = _SUPPORTED_FORMATS.get(source.format or "")
            if expected_content_type is None:
                raise HTTPException(
                    status_code=400,
                    detail="Choose a supported image file such as JPG, PNG, or WebP.",
                )
            if image.content_type != expected_content_type:
                raise HTTPException(
                    status_code=415,
                    detail="The image format does not match its content type.",
                )
            if source.width * source.height > _MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=400,
                    detail="The image dimensions are too large to process safely.",
                )
            source.seek(0)
            content_type = expected_content_type
            converted = ImageOps.exif_transpose(source).convert("RGB")
            converted.thumbnail(
                (_MAX_IMAGE_SIDE, _MAX_IMAGE_SIDE),
                Image.Resampling.LANCZOS,
            )
            output = BytesIO()
            converted.save(output, format="JPEG", quality=90, optimize=True)
            return raw, output.getvalue(), content_type
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


def _history_path() -> Path:
    configured_path = os.getenv("SKINAI_SCAN_HISTORY_PATH", "").strip()
    return Path(configured_path) if configured_path else PROJECT_ROOT / "scan_log.jsonl"


def _append_history(record: dict[str, object]) -> None:
    path = _history_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        encoded = json.dumps(record, ensure_ascii=False, allow_nan=False)
        with _HISTORY_LOCK, path.open("a", encoding="utf-8") as history:
            history.write(encoded + "\n")
    except (OSError, TypeError, ValueError) as error:
        _logger.error(
            "Could not persist Ivy AI history (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail=(
                "The analysis completed, but local history could not be saved. "
                "Do not retry immediately."
            ),
        ) from error


def _validate_provider_result(payload: object) -> dict[str, object]:
    return validate_ivy_response(payload)


@router.post("/analyze")
async def analyze(
    image: UploadFile | None = File(default=None),
    skin_illness_location: str | None = Form(default=None),
    symptoms_duration: str | None = Form(default=None),
    symptoms_details: str | None = Form(default=None),
    symptoms_change_over_time: str | None = Form(default=None),
    save_history: bool = Form(default=False),
    image_storage_consent: bool = Form(default=False),
    user: dict = Depends(require_firebase_user),
) -> dict[str, object]:
    if image is None:
        raise HTTPException(status_code=400, detail="No input image provided.")
    if image_storage_consent and not save_history:
        raise HTTPException(
            status_code=400,
            detail="Save scan history before requesting original image storage.",
        )
    if save_history and _mock_enabled():
        raise HTTPException(
            status_code=409,
            detail="Mock screening results cannot be saved as medical records.",
        )

    original_bytes, jpeg_bytes, original_content_type = (
        await _read_original_and_convert_image(image)
    )
    if _mock_enabled():
        analysis = {
            "result": "Mock screening result",
            "confidence": 84.0,
            "summary": (
                "## Mock analysis\n\n"
                "This is a **mock response** for testing the app without using "
                "an Ivy AI call.\n\n- No diagnosis was made."
            ),
        }
    else:
        analysis = await IvyAIProvider().analyze(jpeg_bytes)
    concern_level, referral_required = classify_skin_analysis(analysis)
    scan_id = str(uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()
    response_data = {
        **analysis,
        "safety": {
            "concern_level": concern_level,
            "referral_required": referral_required,
            "medication_recommendations_allowed": False,
            "medication_block_reasons": ["image_only_workflow"],
        },
        "id": scan_id,
        "timestamp": timestamp,
    }
    if save_history:
        from .medical_records import create_analysis_scan

        create_analysis_scan(
            user["uid"],
            response_data,
            original_image=original_bytes if image_storage_consent else None,
            original_content_type=original_content_type,
            body_location=skin_illness_location,
            user_notes=symptoms_details,
        )
    _append_history(response_data)
    return response_data
