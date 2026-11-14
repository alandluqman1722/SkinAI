import json
import logging
import math
import os
import threading
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from uuid import uuid4

import httpx
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

from .firebase_auth import require_firebase_user
from .firebase_app import PROJECT_ROOT

load_dotenv(PROJECT_ROOT / ".env", override=False)

_SCANSKIN_URL = "https://scanskinai.aihealthpred.com/api/detect/"
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_MAX_IMAGE_PIXELS = 40_000_000
_MAX_IMAGE_SIDE = 2000
_MAX_RESPONSE_BYTES = 2 * 1024 * 1024
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

router = APIRouter(tags=["ScanSkinAI"])


def _mock_enabled() -> bool:
    return os.getenv("MOCK_API", "").strip() == "1"


def _create_http_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0))


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
    configured_path = os.getenv("SCANSKIN_HISTORY_PATH", "").strip()
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
            "Could not persist ScanSkinAI history (%s).",
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
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=502,
            detail="The screening provider returned an invalid response.",
        )

    result = payload.get("result")
    confidence = payload.get("confidence")
    summary = payload.get("summary")
    if (
        not isinstance(result, str)
        or not result.strip()
        or isinstance(confidence, bool)
        or not isinstance(confidence, (int, float))
        or not math.isfinite(confidence)
        or confidence < 0
        or confidence > 100
        or not isinstance(summary, str)
    ):
        raise HTTPException(
            status_code=502,
            detail="The screening provider returned an invalid response.",
        )
    return {
        "result": result,
        "confidence": float(confidence),
        "summary": summary,
    }


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
        payload: object = {
            "result": "Mock screening result",
            "confidence": 0.84,
            "summary": (
                "## Mock analysis\n\n"
                "This is a **mock response** for testing the app without using "
                "a ScanSkinAI call.\n\n- No diagnosis was made."
            ),
        }
    else:
        api_key = os.getenv("SCANSKIN_API_KEY", "").strip()
        if not api_key:
            raise HTTPException(
                status_code=503,
                detail="ScanSkinAI is not configured on the server.",
            )

        fields = {
            "skin_illness_location": skin_illness_location,
            "symptoms_duration": symptoms_duration,
            "symptoms_details": symptoms_details,
            "symptoms_change_over_time": symptoms_change_over_time,
        }
        data = {
            name: value.strip()
            for name, value in fields.items()
            if value is not None and value.strip()
        }
        try:
            async with _create_http_client() as client:
                response = await client.post(
                    _SCANSKIN_URL,
                    headers={
                        "X-API-KEY": api_key,
                        "Accept": "application/json",
                    },
                    files={
                        "input_image": (
                            "scan.jpg",
                            jpeg_bytes,
                            "image/jpeg",
                        )
                    },
                    data=data,
                )
        except httpx.TimeoutException as error:
            _logger.warning("ScanSkinAI request timed out.")
            raise HTTPException(
                status_code=504,
                detail="The screening provider timed out. Please try again later.",
            ) from error
        except httpx.HTTPError as error:
            _logger.warning(
                "ScanSkinAI request failed (%s).",
                type(error).__name__,
            )
            raise HTTPException(
                status_code=502,
                detail="The screening provider could not be reached.",
            ) from error

        if response.status_code in {401, 403}:
            raise HTTPException(
                status_code=response.status_code,
                detail="The screening provider rejected its server credentials.",
            )
        if response.status_code == 400:
            raise HTTPException(
                status_code=400,
                detail="The screening provider could not process this image.",
            )
        if not 200 <= response.status_code < 300:
            _logger.warning(
                "ScanSkinAI returned HTTP %d.",
                response.status_code,
            )
            raise HTTPException(
                status_code=502,
                detail="The screening provider could not complete the request.",
            )
        if len(response.content) > _MAX_RESPONSE_BYTES:
            raise HTTPException(
                status_code=502,
                detail="The screening provider returned an oversized response.",
            )
        try:
            payload = response.json()
        except ValueError as error:
            raise HTTPException(
                status_code=502,
                detail="The screening provider returned invalid JSON.",
            ) from error

    analysis = _validate_provider_result(payload)
    scan_id = str(uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()
    response_data = {
        **analysis,
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
