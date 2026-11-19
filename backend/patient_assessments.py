from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from cryptography.exceptions import InvalidTag
from google.api_core.exceptions import GoogleAPIError
from pydantic import ValidationError

from . import ai_service
from .firebase_auth import require_firebase_user
from .medical_ai.encrypted_storage import (
    decrypt,
    delete_file,
    read_file,
)
from .medical_ai.patient_assessment_service import PatientAssessmentService
from .medical_ai.schemas import AssessmentResponse, PatientInput
from .medical_records import _database

router = APIRouter(prefix="/medical/assessments", tags=["Medical assessments"])
_logger = logging.getLogger(__name__)
_MAX_REPORT_BYTES = 8 * 1024 * 1024
_MAX_TOTAL_BYTES = 30 * 1024 * 1024
_MAX_REPORT_COUNT = 3
_SUPPORTED_REPORT_IMAGES = {"image/jpeg", "image/png", "image/webp"}
_service = PatientAssessmentService()


async def _read_limited(upload: UploadFile, limit: int) -> bytes:
    chunks: list[bytes] = []
    size = 0
    try:
        while chunk := await upload.read(64 * 1024):
            size += len(chunk)
            if size > limit:
                raise HTTPException(
                    status_code=413,
                    detail="A medical attachment exceeds the upload limit.",
                )
            chunks.append(chunk)
    finally:
        await upload.close()
    content = b"".join(chunks)
    if not content:
        raise HTTPException(
            status_code=400,
            detail="An uploaded medical attachment is empty.",
        )
    return content


async def _read_report(upload: UploadFile) -> tuple[bytes, str, str]:
    mime_type = upload.content_type or ""
    filename = (upload.filename or "medical-report").replace("\x00", "")[:200]
    if mime_type == "application/pdf":
        content = await _read_limited(upload, _MAX_REPORT_BYTES)
        if not content.startswith(b"%PDF-"):
            raise HTTPException(
                status_code=415,
                detail="The report does not contain a valid PDF file.",
            )
        return content, mime_type, filename
    if mime_type not in _SUPPORTED_REPORT_IMAGES:
        await upload.close()
        raise HTTPException(
            status_code=415,
            detail="Reports must be PDF, JPEG, PNG, or WebP files.",
        )
    original, _, detected_mime = await ai_service._read_original_and_convert_image(
        upload
    )
    if detected_mime != mime_type or len(original) > _MAX_REPORT_BYTES:
        raise HTTPException(
            status_code=415,
            detail="The report image format is invalid or too large.",
        )
    return original, mime_type, filename


def _record_reference(uid: str, assessment_id: str):
    try:
        normalized_id = str(UUID(assessment_id))
    except (ValueError, AttributeError) as error:
        raise HTTPException(
            status_code=404,
            detail="Medical assessment not found.",
        ) from error
    return (
        _database()
        .collection("users")
        .document(uid)
        .collection("medical_assessments")
        .document(normalized_id)
    )


def _decrypt_record(
    uid: str,
    assessment_id: str,
    encrypted_payload: bytes,
) -> dict[str, Any]:
    try:
        decoded = decrypt(
            encrypted_payload,
            associated_data=f"{uid}:{assessment_id}:record".encode(),
        )
        result = json.loads(decoded)
    except (
        InvalidTag,
        RuntimeError,
        ValueError,
        TypeError,
        json.JSONDecodeError,
    ) as error:
        _logger.error("Encrypted assessment record could not be decoded.")
        raise HTTPException(
            status_code=503,
            detail="Medical assessment storage is temporarily unavailable.",
        ) from error
    if not isinstance(result, dict):
        raise HTTPException(
            status_code=503,
            detail="Medical assessment storage is temporarily unavailable.",
        )
    return result


@router.post("", response_model=AssessmentResponse, status_code=201)
async def create_assessment(
    patient_data: Annotated[str, Form()],
    skin_image: Annotated[UploadFile, File()],
    medication_image: Annotated[UploadFile | None, File()] = None,
    medical_reports: Annotated[list[UploadFile] | None, File()] = None,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> AssessmentResponse:
    if os.getenv("MEDICAL_ASSESSMENT_ENABLED", "").strip().lower() != "true":
        raise HTTPException(
            status_code=503,
            detail="Medical assessment is not enabled on the server.",
        )
    try:
        patient = PatientInput.model_validate_json(patient_data)
    except (ValidationError, ValueError) as error:
        raise HTTPException(
            status_code=422,
            detail="The patient assessment details are invalid.",
        ) from error
    reports_uploads = medical_reports or []
    if len(reports_uploads) > _MAX_REPORT_COUNT:
        raise HTTPException(
            status_code=413,
            detail=f"No more than {_MAX_REPORT_COUNT} medical reports are allowed.",
        )
    original_skin, jpeg_skin, skin_mime = (
        await ai_service._read_original_and_convert_image(skin_image)
    )
    medication: tuple[bytes, str] | None = None
    medication_size = 0
    if medication_image is not None:
        raw, _, medication_mime = await ai_service._read_original_and_convert_image(
            medication_image
        )
        if medication_mime not in _SUPPORTED_REPORT_IMAGES:
            raise HTTPException(
                status_code=415,
                detail="Medication images must be JPEG, PNG, or WebP.",
            )
        medication = (raw, medication_mime)
        medication_size = len(raw)
    reports: list[tuple[bytes, str, str]] = []
    for upload in reports_uploads:
        reports.append(await _read_report(upload))
    total_bytes = (
        len(original_skin)
        + medication_size
        + sum(len(content) for content, _, _ in reports)
    )
    if total_bytes > _MAX_TOTAL_BYTES:
        raise HTTPException(
            status_code=413,
            detail="The total medical upload exceeds the processing limit.",
        )
    return await _service.assess(
        uid=user["uid"],
        patient=patient,
        skin_image=(original_skin, jpeg_skin, skin_mime),
        medication_image=medication,
        reports=reports,
    )


@router.get("", response_model=list[AssessmentResponse])
def list_assessments(
    user: dict[str, Any] = Depends(require_firebase_user),
) -> list[AssessmentResponse]:
    try:
        snapshots = (
            _database()
            .collection("users")
            .document(user["uid"])
            .collection("medical_assessments")
            .order_by("created_at", direction="DESCENDING")
            .limit(30)
            .stream()
        )
        result: list[AssessmentResponse] = []
        for snapshot in snapshots:
            data = snapshot.to_dict() or {}
            record = _decrypt_record(
                user["uid"],
                snapshot.id,
                data.get("encrypted_payload", b""),
            )
            result.append(AssessmentResponse.model_validate(record["assessment"]))
        return result
    except GoogleAPIError as error:
        _logger.error("Medical assessment list failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Medical assessments are temporarily unavailable.",
        ) from error


@router.get("/{assessment_id}", response_model=AssessmentResponse)
def get_assessment(
    assessment_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> AssessmentResponse:
    try:
        reference = _record_reference(user["uid"], assessment_id)
        snapshot = reference.get()
    except GoogleAPIError as error:
        _logger.error("Medical assessment lookup failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Medical assessment is temporarily unavailable.",
        ) from error
    if not snapshot.exists:
        raise HTTPException(status_code=404, detail="Medical assessment not found.")
    record = _decrypt_record(
        user["uid"],
        reference.id,
        snapshot.get("encrypted_payload"),
    )
    return AssessmentResponse.model_validate(record["assessment"])


@router.get("/{assessment_id}/files/{file_id}")
def get_assessment_file(
    assessment_id: str,
    file_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    try:
        reference = _record_reference(user["uid"], assessment_id)
        snapshot = reference.get()
    except GoogleAPIError as error:
        _logger.error("Medical attachment lookup failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Medical attachment is temporarily unavailable.",
        ) from error
    if not snapshot.exists:
        raise HTTPException(status_code=404, detail="Medical assessment not found.")
    record = _decrypt_record(
        user["uid"],
        reference.id,
        snapshot.get("encrypted_payload"),
    )
    file_record = next(
        (
            item
            for item in record.get("file_refs", [])
            if item.get("id") == file_id
        ),
        None,
    )
    if file_record is None or file_record.get("kind") == "skin_image":
        raise HTTPException(status_code=404, detail="Medical attachment not found.")
    try:
        content = read_file(
            file_record["storage_id"],
            uid=user["uid"],
            assessment_id=reference.id,
            file_id=file_id,
        )
    except (OSError, ValueError) as error:
        _logger.error("Encrypted medical attachment read failed.")
        raise HTTPException(
            status_code=503,
            detail="Medical attachment is temporarily unavailable.",
        ) from error
    mime_type = file_record.get("mime_type")
    if mime_type not in {"application/pdf", *_SUPPORTED_REPORT_IMAGES}:
        raise HTTPException(
            status_code=503,
            detail="Medical attachment metadata is invalid.",
        )
    filename = "medical-report.pdf" if mime_type == "application/pdf" else "medical-report"
    return Response(
        content=content,
        media_type=mime_type,
        headers={
            "Cache-Control": "no-store",
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.delete("/{assessment_id}", status_code=204)
def delete_assessment(
    assessment_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> Response:
    reference = _record_reference(user["uid"], assessment_id)
    db = _database()
    try:
        snapshot = reference.get()
        if not snapshot.exists:
            raise HTTPException(
                status_code=404,
                detail="Medical assessment not found.",
            )
        record = _decrypt_record(
            user["uid"],
            reference.id,
            snapshot.get("encrypted_payload"),
        )
        audit_reference = (
            db.collection("users")
            .document(user["uid"])
            .collection("medical_audit")
            .document()
        )
        batch = db.batch()
        batch.delete(reference)
        batch.set(audit_reference, {
            "action": "delete_ai_assessment",
            "target_type": "medical_assessment",
            "target_id": assessment_id,
            "created_at": datetime.now(timezone.utc).isoformat(),
        })
        batch.commit()
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Medical assessment deletion failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Medical assessment could not be deleted.",
        ) from error
    for file_record in record.get("file_refs", []):
        try:
            delete_file(file_record["storage_id"])
        except (OSError, ValueError) as error:
            _logger.error("Encrypted medical attachment cleanup failed.")
            raise HTTPException(
                status_code=503,
                detail=(
                    "The assessment was deleted, but private file cleanup "
                    "needs administrator attention."
                ),
            ) from error
    return Response(status_code=204)
