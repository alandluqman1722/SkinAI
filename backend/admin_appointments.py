from __future__ import annotations

import logging
import re
from datetime import date, datetime, timedelta, timezone
from typing import Any, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from google.api_core.exceptions import GoogleAPIError
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .doctor_directory import _change_appointment_status, _database
from .firebase_auth import require_admin

_logger = logging.getLogger(__name__)
_APPOINTMENT_ID_PATTERN = r"^[A-Za-z0-9_-]{1,128}$"
_CURSOR_PATTERN = r"^[a-f0-9-]{36}$"
_CURSOR_TTL = timedelta(minutes=15)
_STATUSES = ("pending", "confirmed", "completed", "rejected", "cancelled")

router = APIRouter(prefix="/api/admin/appointments", tags=["Admin appointments"])


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AdminAppointment(StrictModel):
    id: str
    doctor_id: str
    doctor_name: str
    clinic_id: str
    clinic_name: str
    city: str
    appointment_date: date
    appointment_time: str
    status: Literal[
        "pending",
        "confirmed",
        "completed",
        "rejected",
        "cancelled",
        "unknown",
    ]


class AdminAppointmentsPage(StrictModel):
    appointments: list[AdminAppointment]
    next_cursor: str | None


class AppointmentStatusChange(StrictModel):
    status: Literal["confirmed", "rejected", "completed", "cancelled"]
    reason: str = Field(min_length=3, max_length=500)

    @field_validator("reason")
    @classmethod
    def normalize_reason(cls, value: str) -> str:
        normalized = value.strip()
        if len(normalized) < 3:
            raise ValueError("A reason of at least three characters is required.")
        return normalized


def _cursor_reference(database: Any, cursor: str):
    return database.collection("admin_appointment_cursors").document(cursor)


def _cursor_snapshot(
    database: Any,
    *,
    cursor: str | None,
    admin_uid: str,
    status_filter: str | None,
    doctor_id: str | None,
    date_from: date | None,
    date_to: date | None,
    page_size: int,
):
    if cursor is None:
        return None

    reference = _cursor_reference(database, cursor)
    snapshot = reference.get()
    cursor_data = snapshot.to_dict() or {}
    expected = {
        "admin_uid": admin_uid,
        "status": status_filter,
        "doctor_id": doctor_id,
        "date_from": date_from.isoformat() if date_from else None,
        "date_to": date_to.isoformat() if date_to else None,
        "page_size": page_size,
    }
    if (
        not snapshot.exists
        or any(cursor_data.get(key) != value for key, value in expected.items())
        or not isinstance(cursor_data.get("last_appointment_id"), str)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This appointment cursor is invalid. Refresh the list.",
        )

    expires_at = cursor_data.get("expires_at")
    if not isinstance(expires_at, datetime):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This appointment cursor is invalid. Refresh the list.",
        )
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= datetime.now(timezone.utc):
        reference.delete()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This appointment cursor expired. Refresh the list.",
        )

    last_snapshot = (
        database.collection("doctor_appointments")
        .document(cursor_data["last_appointment_id"])
        .get()
    )
    if not last_snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This appointment cursor is invalid. Refresh the list.",
        )
    return last_snapshot


def _save_cursor(
    database: Any,
    *,
    last_appointment_id: str,
    admin_uid: str,
    status_filter: str | None,
    doctor_id: str | None,
    date_from: date | None,
    date_to: date | None,
    page_size: int,
) -> str:
    cursor = str(uuid4())
    _cursor_reference(database, cursor).create(
        {
            "admin_uid": admin_uid,
            "status": status_filter,
            "doctor_id": doctor_id,
            "date_from": date_from.isoformat() if date_from else None,
            "date_to": date_to.isoformat() if date_to else None,
            "page_size": page_size,
            "last_appointment_id": last_appointment_id,
            "expires_at": datetime.now(timezone.utc) + _CURSOR_TTL,
        }
    )
    return cursor


def _appointment_summary(snapshot: Any) -> AdminAppointment:
    return _appointment_summary_record(snapshot.id, snapshot.to_dict() or {})


def _appointment_summary_record(
    appointment_id: str,
    record: dict[str, Any],
) -> AdminAppointment:
    try:
        appointment_date = date.fromisoformat(record["appointment_date"])
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Appointment data is temporarily unavailable.",
        ) from error

    raw_status = record.get("status")
    appointment_status = raw_status if raw_status in _STATUSES else "unknown"
    required_fields = (
        "doctor_id",
        "clinic_id",
        "appointment_time",
    )
    if any(not isinstance(record.get(key), str) for key in required_fields):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Appointment data is temporarily unavailable.",
        )

    def optional_string(key: str) -> str:
        value = record.get(key)
        return value if isinstance(value, str) else ""

    return AdminAppointment(
        id=appointment_id,
        doctor_id=record["doctor_id"],
        doctor_name=optional_string("doctor_name"),
        clinic_id=record["clinic_id"],
        clinic_name=optional_string("clinic_name"),
        city=optional_string("city"),
        appointment_date=appointment_date,
        appointment_time=record["appointment_time"],
        status=appointment_status,
    )


@router.get("", response_model=AdminAppointmentsPage)
def list_admin_appointments(
    status_filter: Literal[
        "pending",
        "confirmed",
        "completed",
        "rejected",
        "cancelled",
    ]
    | None = Query(default=None, alias="status"),
    doctor_id: str | None = Query(default=None, min_length=1, max_length=100),
    date_from: date | None = Query(default=None),
    date_to: date | None = Query(default=None),
    page_size: int = Query(default=50, ge=1, le=100),
    cursor: str | None = Query(
        default=None,
        min_length=36,
        max_length=36,
        pattern=_CURSOR_PATTERN,
    ),
    admin: dict[str, Any] = Depends(require_admin),
) -> AdminAppointmentsPage:
    if date_from is not None and date_to is not None and date_from > date_to:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The start date must be on or before the end date.",
        )
    normalized_doctor_id = doctor_id.strip() if doctor_id else None
    if doctor_id is not None and not normalized_doctor_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A doctor identifier cannot be empty.",
        )

    database = _database()
    try:
        start_after = _cursor_snapshot(
            database,
            cursor=cursor,
            admin_uid=admin["uid"],
            status_filter=status_filter,
            doctor_id=normalized_doctor_id,
            date_from=date_from,
            date_to=date_to,
            page_size=page_size,
        )
        query = database.collection("doctor_appointments")
        if status_filter is not None:
            query = query.where("status", "==", status_filter)
        if normalized_doctor_id is not None:
            query = query.where("doctor_id", "==", normalized_doctor_id)
        if date_from is not None:
            query = query.where(
                "appointment_date",
                ">=",
                date_from.isoformat(),
            )
        if date_to is not None:
            query = query.where(
                "appointment_date",
                "<=",
                date_to.isoformat(),
            )
        query = query.order_by("appointment_date").limit(page_size + 1)
        if start_after is not None:
            query = query.start_after(start_after)

        snapshots = list(query.stream())
        has_more = len(snapshots) > page_size
        page_snapshots = snapshots[:page_size]
        next_cursor = (
            _save_cursor(
                database,
                last_appointment_id=page_snapshots[-1].id,
                admin_uid=admin["uid"],
                status_filter=status_filter,
                doctor_id=normalized_doctor_id,
                date_from=date_from,
                date_to=date_to,
                page_size=page_size,
            )
            if has_more
            else None
        )
        return AdminAppointmentsPage(
            appointments=[
                _appointment_summary(snapshot) for snapshot in page_snapshots
            ],
            next_cursor=next_cursor,
        )
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "Admin appointment list failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Appointment data is temporarily unavailable.",
        ) from error


@router.patch("/{appointment_id}", response_model=AdminAppointment)
def moderate_admin_appointment(
    payload: AppointmentStatusChange,
    appointment_id: str = Path(pattern=_APPOINTMENT_ID_PATTERN),
    admin: dict[str, Any] = Depends(require_admin),
) -> AdminAppointment:
    try:
        updated = _change_appointment_status(
            _database(),
            appointment_id,
            payload.status,
            admin_uid=admin["uid"],
            reason=payload.reason,
        )
        return _appointment_summary_record(appointment_id, updated)
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error(
            "Admin appointment moderation failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The appointment could not be updated.",
        ) from error
