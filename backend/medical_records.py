from __future__ import annotations

import logging
import os
from datetime import date, datetime, timezone
from enum import Enum
from io import BytesIO
from typing import Annotated, Any, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from google.api_core.exceptions import GoogleAPIError
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, model_validator

from .firebase_app import get_firebase_app
from .firebase_auth import require_firebase_user
from .private_image_storage import (
    delete_image,
    image_exists,
    read_image,
    store_image,
)

router = APIRouter(prefix="/medical", tags=["Medical records"])
_logger = logging.getLogger(__name__)
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_MAX_IMAGE_PIXELS = 40_000_000
_SUPPORTED_FORMATS = {
    "JPEG": "image/jpeg",
    "PNG": "image/png",
    "WEBP": "image/webp",
    "GIF": "image/gif",
    "BMP": "image/bmp",
    "TIFF": "image/tiff",
}


class MedicationStatus(str, Enum):
    CURRENT = "currently_using"
    COMPLETED = "completed"
    PAUSED = "paused_by_doctor"
    DISCONTINUED = "discontinued_by_doctor"


class CompletionStatus(str, Enum):
    COMPLETED = "completed"
    SKIPPED = "skipped"
    POSTPONED = "postponed"


class StrictRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")


class MedicationRecord(StrictRecord):
    name: str = Field(min_length=1, max_length=200)
    active_ingredient: str | None = Field(default=None, max_length=300)
    purpose: str | None = Field(default=None, max_length=2000)
    prescribing_doctor: str | None = Field(default=None, max_length=200)
    start_date: date | None = None
    end_date: date | None = None
    instructions: str | None = Field(default=None, max_length=4000)
    notes: str | None = Field(default=None, max_length=4000)
    status: MedicationStatus = MedicationStatus.CURRENT
    reminder_enabled: bool = False


class MedicationRecognitionResult(StrictRecord):
    medicine_name: str | None = None
    brand_name: str | None = None
    generic_name: str | None = None
    active_ingredient: str | None = None
    category: str | None = None
    concentration: str | None = None
    form: str | None = None
    manufacturer: str | None = None
    confidence: float = Field(ge=0, le=1)
    verified: bool
    source: str | None = None
    information_date: date | None = None
    uncertainty: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def verified_information_requires_provenance(
        self,
    ) -> MedicationRecognitionResult:
        if self.verified and (
            self.source is None or self.information_date is None
        ):
            raise ValueError(
                "Verified medicine information requires a source and date."
            )
        return self


class MedicationHistoryRecord(StrictRecord):
    medication_id: str = Field(min_length=1, max_length=100)
    status: MedicationStatus
    changed_at: datetime
    notes: str | None = Field(default=None, max_length=4000)


class TreatmentPlanRecord(StrictRecord):
    title: str = Field(min_length=1, max_length=200)
    concern: str | None = Field(default=None, max_length=500)
    medication_ids: list[str] = Field(default_factory=list, max_length=50)
    start_date: date | None = None
    end_date: date | None = None
    instructions: str | None = Field(default=None, max_length=4000)
    notes: str | None = Field(default=None, max_length=4000)


class SkinScanRecord(StrictRecord):
    analysis_id: str = Field(min_length=1, max_length=100)
    created_at: datetime
    result: str = Field(min_length=1, max_length=500)
    confidence: float = Field(ge=0, le=100)
    explanation: str = Field(default="", max_length=10000)
    body_location: str | None = Field(default=None, max_length=200)
    user_notes: str | None = Field(default=None, max_length=4000)
    medication_ids: list[str] = Field(default_factory=list, max_length=50)
    treatment_plan_id: str | None = Field(default=None, max_length=100)
    doctor_review_id: str | None = Field(default=None, max_length=100)


class ScanMetadataUpdate(StrictRecord):
    body_location: str | None = Field(default=None, max_length=200)
    user_notes: str | None = Field(default=None, max_length=4000)


class ScanComparisonRecord(StrictRecord):
    earlier_scan_id: str = Field(min_length=1, max_length=100)
    later_scan_id: str = Field(min_length=1, max_length=100)
    observations: str = Field(min_length=1, max_length=10000)
    reliability_notes: str = Field(min_length=1, max_length=4000)


class SkinRoutineRecord(StrictRecord):
    name: str = Field(min_length=1, max_length=200)
    period: str = Field(pattern=r"^(morning|afternoon|evening|bedtime)$")
    tasks: list[str] = Field(min_length=1, max_length=100)
    reminder_enabled: bool = False


class RoutineCompletionRecord(StrictRecord):
    routine_id: str = Field(min_length=1, max_length=100)
    task_id: str = Field(min_length=1, max_length=100)
    completed_on: date
    status: CompletionStatus
    notes: str | None = Field(default=None, max_length=2000)


class AppointmentRecord(StrictRecord):
    provider_id: str = Field(min_length=1, max_length=100)
    requested_at: datetime
    status: str = Field(pattern=r"^(requested|confirmed|cancelled|completed)$")
    notes: str | None = Field(default=None, max_length=2000)


class DoctorReviewRecord(StrictRecord):
    provider_id: str = Field(min_length=1, max_length=100)
    scan_id: str | None = Field(default=None, max_length=100)
    reviewed_at: datetime
    comments: str = Field(min_length=1, max_length=10000)


class DoctorProfileRecord(StrictRecord):
    provider_id: str = Field(min_length=1, max_length=200)
    full_name: str = Field(min_length=1, max_length=300)
    profile_image_url: str | None = Field(default=None, max_length=2000)
    credentials: list[str] = Field(min_length=1, max_length=30)
    specialty: str = Field(min_length=1, max_length=300)
    experience_years: int | None = Field(default=None, ge=0, le=100)
    clinic_name: str = Field(min_length=1, max_length=300)
    address: str = Field(min_length=1, max_length=1000)
    city: str = Field(min_length=1, max_length=100)
    phone: str | None = Field(default=None, max_length=100)
    working_hours: list[str] = Field(default_factory=list, max_length=100)
    appointment_options: list[str] = Field(default_factory=list, max_length=100)
    languages: list[str] = Field(default_factory=list, max_length=30)
    verified: Literal[True]
    verified_by: str = Field(min_length=1, max_length=300)
    verified_at: datetime
    source: str = Field(min_length=1, max_length=1000)


class HealthReportRecord(StrictRecord):
    created_at: datetime
    scan_ids: list[str] = Field(default_factory=list, max_length=100)
    medication_ids: list[str] = Field(default_factory=list, max_length=100)
    content_object: str | None = None


class MedicalNotificationRecord(StrictRecord):
    created_at: datetime
    category: str = Field(min_length=1, max_length=100)
    message: str = Field(min_length=1, max_length=2000)
    acknowledged: bool = False


_RECORD_TYPES: dict[str, type[StrictRecord]] = {
    "medications": MedicationRecord,
    "medication_history": MedicationHistoryRecord,
    "treatment_plans": TreatmentPlanRecord,
    "scans": SkinScanRecord,
    "comparisons": ScanComparisonRecord,
    "routines": SkinRoutineRecord,
    "routine_completions": RoutineCompletionRecord,
    "appointments": AppointmentRecord,
    "doctor_reviews": DoctorReviewRecord,
    "health_reports": HealthReportRecord,
    "medical_notifications": MedicalNotificationRecord,
}
_USER_WRITABLE_TYPES = {
    "medications",
    "medication_history",
    "treatment_plans",
    "routines",
    "routine_completions",
    "health_reports",
}


def _database():
    try:
        from firebase_admin import firestore

        return firestore.client(app=get_firebase_app())
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "Medical record database is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Medical record storage is not configured.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Medical record database request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Medical record storage is temporarily unavailable.",
        ) from error


def _records(uid: str, record_type: str):
    if record_type not in _RECORD_TYPES:
        raise HTTPException(status_code=404, detail="Medical record type not found.")
    return (
        _database()
        .collection("users")
        .document(uid)
        .collection("medical_records")
    )


def _validated_record(record_type: str, payload: dict[str, Any]) -> dict[str, Any]:
    model = _RECORD_TYPES.get(record_type)
    if model is None:
        raise HTTPException(status_code=404, detail="Medical record type not found.")
    try:
        return model.model_validate(payload).model_dump(mode="json")
    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail="Invalid medical record.",
        ) from error


def _validate_owned_references(
    uid: str,
    record_type: str,
    data: dict[str, Any],
) -> None:
    references: list[tuple[str, str]] = []
    if record_type == "medication_history":
        references.append(("medications", data["medication_id"]))
    elif record_type == "treatment_plans":
        references.extend(
            ("medications", medication_id)
            for medication_id in data["medication_ids"]
        )
    elif record_type == "routine_completions":
        references.append(("routines", data["routine_id"]))
    elif record_type == "health_reports":
        references.extend(("scans", scan_id) for scan_id in data["scan_ids"])
        references.extend(
            ("medications", medication_id)
            for medication_id in data["medication_ids"]
        )

    for reference_type, reference_id in references:
        snapshot = _records(uid, reference_type).document(reference_id).get()
        if not snapshot.exists or snapshot.get("type") != reference_type:
            raise HTTPException(
                status_code=422,
                detail="A referenced medical record was not found.",
            )


def create_analysis_scan(
    uid: str,
    analysis: dict[str, Any],
    *,
    original_image: bytes | None,
    original_content_type: str,
    body_location: str | None,
    user_notes: str | None,
) -> None:
    record_id = str(analysis["id"])
    image_id = None
    file_path = None
    try:
        db = _database()
        if original_image is not None:
            image_id, file_path = store_image(original_image)
        record = {
            "type": "scans",
            "analysis_id": record_id,
            "created_at": analysis["timestamp"],
            "result": analysis["result"],
            "confidence": (
                float(analysis["confidence"]) * 100
                if float(analysis["confidence"]) <= 1
                else float(analysis["confidence"])
            ),
            "explanation": analysis["summary"],
            "body_location": body_location,
            "user_notes": user_notes,
            "medication_ids": [],
            "treatment_plan_id": None,
            "doctor_review_id": None,
            "image_id": image_id,
            "image_owner_uid": uid if image_id else None,
            "image_file_path": file_path,
            "image_uploaded_at": (
                datetime.now(timezone.utc).isoformat() if image_id else None
            ),
            "image_file_size": len(original_image) if original_image else None,
            "image_content_type": (
                original_content_type if image_id else None
            ),
            "image_storage_consent": original_image is not None,
            "source": "ScanSkinAI",
        }
        reference = (
            db.collection("users")
            .document(uid)
            .collection("medical_records")
            .document(record_id)
        )
        batch = db.batch()
        batch.set(reference, record)
        _add_audit_to_batch(
            batch, db, uid, "create", "scans", record_id
        )
        batch.commit()
    except GoogleAPIError as error:
        _cleanup_local_image(file_path)
        _logger.error(
            "Analysis record save failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Analysis completed, but its medical record could not be saved.",
        ) from error
    except OSError as error:
        _cleanup_local_image(file_path)
        _logger.error(
            "Analysis image or record could not be persisted (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Analysis completed, but its medical record could not be saved.",
        ) from error


async def _validated_image(upload: UploadFile) -> tuple[bytes, str]:
    chunks: list[bytes] = []
    size = 0
    try:
        while chunk := await upload.read(64 * 1024):
            size += len(chunk)
            if size > _MAX_UPLOAD_BYTES:
                raise HTTPException(
                    status_code=413,
                    detail="Image exceeds the 10 MB limit.",
                )
            chunks.append(chunk)
    finally:
        await upload.close()
    raw = b"".join(chunks)
    if not raw:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")
    if upload.content_type not in _SUPPORTED_FORMATS.values():
        raise HTTPException(
            status_code=415,
            detail="Upload a supported image with a matching MIME type.",
        )
    try:
        with Image.open(BytesIO(raw)) as image:
            expected_type = _SUPPORTED_FORMATS.get(image.format or "")
            if expected_type is None or expected_type != upload.content_type:
                raise HTTPException(
                    status_code=415,
                    detail="The image format does not match its content type.",
                )
            if image.width * image.height > _MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=400,
                    detail="Image dimensions are too large.",
                )
            image.verify()
            return raw, expected_type
    except HTTPException:
        raise
    except (
        Image.DecompressionBombError,
        UnidentifiedImageError,
        OSError,
        ValueError,
    ) as error:
        raise HTTPException(
            status_code=400,
            detail="Invalid image file.",
        ) from error


@router.post("/records/{record_type}", status_code=201)
def create_record(
    record_type: str,
    payload: dict[str, Any],
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    if record_type not in _USER_WRITABLE_TYPES:
        raise HTTPException(
            status_code=409,
            detail="This record type is managed by a verified service.",
        )
    data = _validated_record(record_type, payload)
    uid = user["uid"]
    record_id = str(uuid4())
    try:
        _validate_owned_references(uid, record_type, data)
        db = _database()
        reference = (
            db.collection("users")
            .document(uid)
            .collection("medical_records")
            .document(record_id)
        )
        batch = db.batch()
        batch.set(reference, {"type": record_type, **data})
        _add_audit_to_batch(
            batch, db, uid, "create", record_type, record_id
        )
        batch.commit()
        return {"id": record_id, **data}
    except GoogleAPIError as error:
        _logger.error("Medical record create failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not save medical record.",
        ) from error


@router.get("/records/{record_type}")
def list_records(
    record_type: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> list[dict[str, Any]]:
    collection = _records(user["uid"], record_type)
    try:
        return [
            _public_record(document.id, document.to_dict())
            for document in collection.where("type", "==", record_type).stream()
        ]
    except GoogleAPIError as error:
        _logger.error(
            "Medical record list failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not load medical records.",
        ) from error


def _get_record_data(uid: str, record_type: str, record_id: str) -> dict[str, Any]:
    try:
        snapshot = _records(uid, record_type).document(record_id).get()
    except GoogleAPIError as error:
        _logger.error(
            "Medical record read failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not load medical record.",
        ) from error
    if not snapshot.exists or snapshot.get("type") != record_type:
        raise HTTPException(status_code=404, detail="Medical record not found.")
    return snapshot.to_dict()


def _public_record(record_id: str, data: dict[str, Any]) -> dict[str, Any]:
    result = dict(data)
    if result.get("type") == "scans":
        for field in (
            "image_object",
            "image_id",
            "image_owner_uid",
            "image_file_path",
            "image_uploaded_at",
            "image_file_size",
            "image_content_type",
        ):
            result.pop(field, None)
        file_path = data.get("image_file_path")
        result["has_original_image"] = bool(
            isinstance(file_path, str) and image_exists(file_path)
        )
    return {"id": record_id, **result}


@router.get("/records/{record_type}/{record_id}")
def get_record(
    record_type: str,
    record_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    data = _get_record_data(user["uid"], record_type, record_id)
    return _public_record(record_id, data)


@router.patch("/scans/{scan_id}")
def update_scan_metadata(
    scan_id: str,
    payload: ScanMetadataUpdate,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    updates = payload.model_dump(mode="json", exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=422, detail="No scan metadata was provided.")
    uid = user["uid"]
    collection = _records(uid, "scans")
    try:
        reference = collection.document(scan_id)
        snapshot = reference.get()
        if not snapshot.exists or snapshot.get("type") != "scans":
            raise HTTPException(status_code=404, detail="Medical record not found.")
        db = _database()
        batch = db.batch()
        batch.update(reference, updates)
        _add_audit_to_batch(batch, db, uid, "update", "scans", scan_id)
        batch.commit()
        return _public_record(
            scan_id,
            {**snapshot.to_dict(), **updates},
        )
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "Scan metadata update failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not update scan metadata.",
        ) from error


@router.put("/records/{record_type}/{record_id}")
def replace_record(
    record_type: str,
    record_id: str,
    payload: dict[str, Any],
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    if record_type not in _USER_WRITABLE_TYPES:
        raise HTTPException(
            status_code=409,
            detail="This record type is managed by a verified service.",
        )
    data = _validated_record(record_type, payload)
    collection = _records(user["uid"], record_type)
    try:
        _validate_owned_references(user["uid"], record_type, data)
        reference = collection.document(record_id)
        snapshot = reference.get()
        if not snapshot.exists or snapshot.get("type") != record_type:
            raise HTTPException(status_code=404, detail="Medical record not found.")
        db = _database()
        batch = db.batch()
        batch.set(reference, {"type": record_type, **data})
        _add_audit_to_batch(
            batch, db, user["uid"], "update", record_type, record_id
        )
        batch.commit()
        return {"id": record_id, **data}
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "Medical record update failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not update medical record.",
        ) from error


@router.delete(
    "/records/{record_type}/{record_id}",
    status_code=204,
    response_class=Response,
    response_model=None,
)
def delete_record(
    record_type: str,
    record_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    collection = _records(user["uid"], record_type)
    try:
        reference = collection.document(record_id)
        snapshot = reference.get()
        if not snapshot.exists or snapshot.get("type") != record_type:
            raise HTTPException(status_code=404, detail="Medical record not found.")
        image_file_path = snapshot.get("image_file_path")
        if image_file_path:
            _delete_owned_image(
                user["uid"],
                snapshot.get("image_owner_uid"),
                snapshot.get("image_id"),
                image_file_path,
            )
        db = _database()
        batch = db.batch()
        batch.delete(reference)
        _add_audit_to_batch(
            batch, db, user["uid"], "delete", record_type, record_id
        )
        batch.commit()
        return Response(status_code=204)
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "Medical record delete failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not delete medical record.",
        ) from error


def _add_audit_to_batch(
    batch: Any,
    db: Any,
    uid: str,
    event: str,
    record_type: str,
    record_id: str,
) -> None:
    event_data = {
        "event": event,
        "record_type": record_type,
        "record_id": record_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    audit_reference = (
        db.collection("users")
        .document(uid)
        .collection("medical_audit")
        .document()
    )
    batch.set(audit_reference, event_data)


def _cleanup_local_image(file_path: str | None) -> None:
    if not file_path:
        return
    try:
        delete_image(file_path)
    except OSError as error:
        _logger.error(
            "Private image cleanup failed (%s).",
            type(error).__name__,
        )


def _delete_owned_image(
    uid: str,
    image_owner_uid: str | None,
    image_id: str | None,
    file_path: str,
) -> None:
    if image_owner_uid != uid or image_id != file_path:
        raise HTTPException(status_code=403, detail="Image ownership check failed.")
    try:
        delete_image(file_path)
    except ValueError as error:
        raise HTTPException(
            status_code=403,
            detail="Image ownership check failed.",
        ) from error
    except OSError as error:
        _logger.error("Medical image delete failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not delete medical image.",
        ) from error


@router.post("/scans/{scan_id}/original-image", status_code=201)
async def store_original_scan_image(
    scan_id: str,
    file: Annotated[UploadFile, File()],
    storage_consent: Annotated[bool, Form()],
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, str]:
    if not storage_consent:
        raise HTTPException(
            status_code=403,
            detail="Explicit medical image storage consent is required.",
        )
    uid = user["uid"]
    db = _database()
    collection = (
        db.collection("users")
        .document(uid)
        .collection("medical_records")
    )
    try:
        reference = collection.document(scan_id)
        snapshot = reference.get()
        if not snapshot.exists or snapshot.get("type") != "scans":
            raise HTTPException(status_code=404, detail="Scan record not found.")
        if snapshot.get("image_file_path"):
            raise HTTPException(
                status_code=409,
                detail="The original scan image is already stored.",
            )
    except GoogleAPIError as error:
        _logger.error("Scan lookup failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load scan record.",
        ) from error

    raw, content_type = await _validated_image(file)
    batch = db.batch()
    try:
        image_id, file_path = store_image(raw)
    except OSError as error:
        _logger.error("Original scan image upload failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not securely store the original scan image.",
        ) from error
    uploaded_at = datetime.now(timezone.utc).isoformat()
    batch.update(
        reference,
        {
            "image_id": image_id,
            "image_owner_uid": uid,
            "image_file_path": file_path,
            "image_uploaded_at": uploaded_at,
            "image_file_size": len(raw),
            "image_content_type": content_type,
            "image_storage_consent": True,
        },
    )
    _add_audit_to_batch(
        batch, db, uid, "store_original_image", "scans", scan_id
    )
    try:
        batch.commit()
    except GoogleAPIError as error:
        _cleanup_local_image(file_path)
        _logger.error("Original scan image save failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not securely store the original scan image.",
        ) from error
    except OSError as error:
        _cleanup_local_image(file_path)
        _logger.error("Original scan image save failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not securely store the original scan image.",
        ) from error
    return {"scan_id": scan_id, "status": "stored"}


@router.get("/scans/{scan_id}/original-image")
def read_original_scan_image(
    scan_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
):
    uid = user["uid"]
    record = _get_record_data(uid, "scans", scan_id)
    file_path = record.get("image_file_path")
    image_id = record.get("image_id")
    if not file_path:
        raise HTTPException(status_code=404, detail="Original image not found.")
    if (
        record.get("image_owner_uid") != uid
        or image_id != file_path
    ):
        raise HTTPException(status_code=403, detail="Image ownership check failed.")
    try:
        content = read_image(file_path)
    except FileNotFoundError as error:
        raise HTTPException(
            status_code=404,
            detail="Original image not found.",
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=403,
            detail="Image ownership check failed.",
        ) from error
    except OSError as error:
        _logger.error("Original scan image read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load original image.",
        ) from error
    content_type = record.get("image_content_type")
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


@router.get("/integrations/status")
def integration_status(
    _: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, dict[str, bool]]:
    return {
        "medicine_recognition": {
            "configured": bool(os.getenv("MEDICINE_RECOGNITION_URL", "").strip())
        },
        "medicine_reference": {
            "configured": bool(os.getenv("MEDICINE_REFERENCE_URL", "").strip())
        },
        "doctor_directory": {
            "configured": bool(os.getenv("VERIFIED_DOCTOR_DIRECTORY_URL", "").strip())
        },
        "skin_assistant": {
            "configured": bool(os.getenv("SKIN_ASSISTANT_URL", "").strip())
        },
        "medical_image_storage": {
            "configured": True
        },
    }
