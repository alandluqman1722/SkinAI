from __future__ import annotations

import logging
import os
from collections import defaultdict
from datetime import date, datetime, time as datetime_time, timedelta, timezone
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from google.api_core.exceptions import GoogleAPIError
from pydantic import BaseModel, ConfigDict, Field

from .firebase_app import get_firebase_app
from .firebase_auth import require_admin

_logger = logging.getLogger(__name__)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TrendPoint(StrictModel):
    date: date
    value: int = Field(ge=0)


class SystemHealth(StrictModel):
    status: Literal["ok"] = "ok"
    mock_mode: bool
    skinchat_enabled: bool


class DashboardSummary(StrictModel):
    generated_at: datetime
    period_days: Literal[7, 30]
    users_total: int = Field(ge=0)
    new_users_by_day: list[TrendPoint]
    scans_by_day: list[TrendPoint]
    scans_total: int = Field(ge=0)
    skinchat_messages_by_day: list[TrendPoint]
    skinchat_messages_total: int = Field(ge=0)
    appointments_by_status: dict[str, int]
    doctors_published: int = Field(ge=0)
    doctors_pending: int = Field(ge=0)
    reports_waiting: int = Field(ge=0)
    system_health: SystemHealth


def _database():
    try:
        from firebase_admin import firestore

        return firestore.client(app=get_firebase_app())
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "Admin dashboard database is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard data is temporarily unavailable.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin dashboard database request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard data is temporarily unavailable.",
        ) from error


router = APIRouter(prefix="/api/admin", tags=["Admin"])


def _iter_auth_users(firebase_app: Any):
    from firebase_admin import auth

    page_token = None
    while True:
        page = auth.list_users(
            max_results=1000,
            page_token=page_token,
            app=firebase_app,
        )
        yield from page.users
        page_token = page.next_page_token
        if not page_token:
            break


def _timestamp_date(value: object) -> date | None:
    try:
        if isinstance(value, datetime):
            timestamp = value
        elif isinstance(value, str):
            timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            timestamp = datetime.fromtimestamp(value / 1000, tz=timezone.utc)
        else:
            return None
    except (OverflowError, OSError, ValueError):
        return None

    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    return timestamp.astimezone(timezone.utc).date()


def _trend_dates(days: int, today: date) -> list[date]:
    first_day = today - timedelta(days=days - 1)
    return [first_day + timedelta(days=offset) for offset in range(days)]


def _trend_points(
    dates: list[date],
    counts: dict[date, int],
) -> list[TrendPoint]:
    return [
        TrendPoint(date=day, value=counts.get(day, 0))
        for day in dates
    ]


def _count_trends(
    snapshots: Any,
    *,
    dates: list[date],
    value_key: str,
    amount_key: str | None = None,
) -> dict[date, int]:
    first_day = dates[0]
    last_day = dates[-1]
    counts: defaultdict[date, int] = defaultdict(int)
    for snapshot in snapshots:
        record = snapshot.to_dict() or {}
        record_date = _timestamp_date(record.get(value_key))
        if record_date is None:
            _logger.error("Dashboard trend data contains an invalid date.")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Admin dashboard data is temporarily unavailable.",
            )
        if record_date < first_day or record_date > last_day:
            continue
        amount = 1 if amount_key is None else record.get(amount_key)
        if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
            _logger.error("Dashboard usage data contains an invalid counter.")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Admin dashboard data is temporarily unavailable.",
            )
        counts[record_date] += amount
    return dict(counts)


def _new_user_counts(
    firebase_app: Any,
    *,
    dates: list[date],
) -> tuple[int, dict[date, int]]:
    first_day = dates[0]
    last_day = dates[-1]
    total = 0
    counts: defaultdict[date, int] = defaultdict(int)
    for user in _iter_auth_users(firebase_app):
        total += 1
        metadata = getattr(user, "user_metadata", None)
        created_at = _timestamp_date(
            getattr(metadata, "creation_timestamp", None),
        )
        if created_at is None:
            _logger.error("Firebase Auth returned a user without a valid creation date.")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Admin dashboard data is temporarily unavailable.",
            )
        if first_day <= created_at <= last_day:
            counts[created_at] += 1
    return total, dict(counts)


def _field_counts(database: Any, collection_name: str, field: str) -> dict[str, int]:
    counts: defaultdict[str, int] = defaultdict(int)
    for snapshot in database.collection(collection_name).select([field]).stream():
        value = (snapshot.to_dict() or {}).get(field)
        key = value if isinstance(value, str) and value else "unknown"
        counts[key] += 1
    return dict(counts)


def _doctor_dashboard_counts(database: Any) -> tuple[int, int]:
    published = 0
    pending_verification = 0
    query = database.collection("doctors").select(
        ["publication_status", "verification_status"],
    )
    for snapshot in query.stream():
        record = snapshot.to_dict() or {}
        if record.get("publication_status") == "published":
            published += 1
        if record.get("verification_status") == "pending":
            pending_verification += 1
    return published, pending_verification


def _system_health() -> SystemHealth:
    return SystemHealth(
        mock_mode=os.getenv("MOCK_API", "").strip() == "1",
        skinchat_enabled=False,
    )


@router.get("/status")
def admin_status(
    _: dict[str, Any] = Depends(require_admin),
) -> dict[str, bool]:
    return {"admin": True}


@router.get("/dashboard", response_model=DashboardSummary)
def admin_dashboard(
    days: int = Query(default=7, ge=7, le=30),
    _: dict[str, Any] = Depends(require_admin),
) -> DashboardSummary:
    if days not in {7, 30}:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The dashboard period must be 7 or 30 days.",
        )
    now = datetime.now(timezone.utc)
    today = now.date()
    dates = _trend_dates(days, today)
    first_timestamp = datetime.combine(
        dates[0],
        datetime_time.min,
        tzinfo=timezone.utc,
    ).isoformat()
    last_timestamp = datetime.combine(
        today + timedelta(days=1),
        datetime_time.min,
        tzinfo=timezone.utc,
    ).isoformat()

    try:
        from firebase_admin.exceptions import FirebaseError
        from google.auth.exceptions import DefaultCredentialsError

        firebase_app = get_firebase_app()
        users_total, new_user_counts = _new_user_counts(
            firebase_app,
            dates=dates,
        )
        database = _database()
        scans_query = (
            database.collection_group("medical_records")
            .where("type", "==", "scans")
            .where("created_at", ">=", first_timestamp)
            .where("created_at", "<", last_timestamp)
            .select(["created_at"])
        )
        chat_usage_query = (
            database.collection_group("skinchat_usage")
            .where("date", ">=", dates[0].isoformat())
            .where("date", "<", (today + timedelta(days=1)).isoformat())
            .select(["date", "count"])
        )
        scan_counts = _count_trends(
            scans_query.stream(),
            dates=dates,
            value_key="created_at",
        )
        chat_counts = _count_trends(
            chat_usage_query.stream(),
            dates=dates,
            value_key="date",
            amount_key="count",
        )
        appointment_counts = _field_counts(
            database,
            "doctor_appointments",
            "status",
        )
        doctors_published, doctors_pending = _doctor_dashboard_counts(database)
        reports_waiting = sum(
            1
            for _ in (
                database.collection("doctor_review_reports")
                .where("status", "==", "pending")
                .select(["status"])
                .stream()
            )
        )
    except HTTPException:
        raise
    except (DefaultCredentialsError, FirebaseError) as error:
        _logger.error(
            "Admin dashboard authentication data read failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard data is temporarily unavailable.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Admin dashboard Firestore read failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard data is temporarily unavailable.",
        ) from error
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "Admin dashboard service is unavailable (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard data is temporarily unavailable.",
        ) from error

    return DashboardSummary(
        generated_at=now,
        period_days=days,
        users_total=users_total,
        new_users_by_day=_trend_points(dates, new_user_counts),
        scans_by_day=_trend_points(dates, scan_counts),
        scans_total=sum(scan_counts.values()),
        skinchat_messages_by_day=_trend_points(dates, chat_counts),
        skinchat_messages_total=sum(chat_counts.values()),
        appointments_by_status=appointment_counts,
        doctors_published=doctors_published,
        doctors_pending=doctors_pending,
        reports_waiting=reports_waiting,
        system_health=_system_health(),
    )
