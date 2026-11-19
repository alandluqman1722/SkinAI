from __future__ import annotations

import logging
import re
from datetime import date, datetime, time, timedelta, timezone
from io import BytesIO
from typing import Any, Callable, Literal
from urllib.parse import quote
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.responses import Response
from google.api_core.exceptions import GoogleAPIError
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, model_validator

from .admin_audit import create_audit_entry
from .doctor_storage import delete_file, file_exists, read_file, store_file
from .firebase_app import get_firebase_app
from .firebase_auth import require_admin, require_firebase_user

router = APIRouter(prefix="/api/doctors", tags=["Doctor directory"])
_logger = logging.getLogger(__name__)
_IRAQ_TZ = timezone(timedelta(hours=3))
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_TIME_PATTERN = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")
_HELD_APPOINTMENT_STATUSES = {"pending", "confirmed"}
_RELEASED_APPOINTMENT_STATUSES = {"rejected", "cancelled"}


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class WeeklyAvailability(StrictModel):
    weekday: int = Field(ge=0, le=6)
    times: list[str] = Field(min_length=1, max_length=48)

    @model_validator(mode="after")
    def validate_times(self) -> WeeklyAvailability:
        if any(not _TIME_PATTERN.fullmatch(value) for value in self.times):
            raise ValueError("Availability times must use HH:MM format.")
        if len(set(self.times)) != len(self.times):
            raise ValueError("Availability times cannot be duplicated.")
        return self


class ClinicInput(StrictModel):
    clinic_id: str | None = Field(default=None, max_length=100)
    name: str = Field(min_length=1, max_length=200)
    city: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1, max_length=1000)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    phone: str | None = Field(default=None, max_length=100)
    website: str | None = Field(default=None, max_length=500)
    weekly_schedule: list[WeeklyAvailability] = Field(default_factory=list, max_length=7)

    @model_validator(mode="after")
    def coordinates_are_a_pair(self) -> ClinicInput:
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Clinic coordinates must include both latitude and longitude.")
        if len({item.weekday for item in self.weekly_schedule}) != len(
            self.weekly_schedule
        ):
            raise ValueError("A clinic can have only one schedule per weekday.")
        return self


class DoctorWrite(StrictModel):
    full_name: str = Field(min_length=2, max_length=200)
    qualifications: list[str] = Field(default_factory=list, max_length=30)
    specializations: list[str] = Field(min_length=1, max_length=20)
    experience_years: int | None = Field(default=None, ge=0, le=80)
    biography: str = Field(default="", max_length=4000)
    languages: list[str] = Field(default_factory=list, max_length=20)
    clinics: list[ClinicInput] = Field(min_length=1, max_length=20)
    publication_status: Literal["draft", "published"] = "draft"

    @model_validator(mode="after")
    def validate_clinics(self) -> DoctorWrite:
        clinic_ids = [
            clinic.clinic_id for clinic in self.clinics if clinic.clinic_id is not None
        ]
        if len(clinic_ids) != len(set(clinic_ids)):
            raise ValueError("Clinic identifiers must be unique.")
        return self


class VerificationDecision(StrictModel):
    status: Literal["approved", "rejected", "unverified"]
    notes: str | None = Field(default=None, max_length=2000)


class AppointmentRequest(StrictModel):
    doctor_id: str = Field(min_length=1, max_length=100)
    clinic_id: str = Field(min_length=1, max_length=100)
    appointment_date: date
    appointment_time: str = Field(pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")


class ReviewRequest(StrictModel):
    appointment_id: str = Field(min_length=1, max_length=100)
    rating: int = Field(ge=1, le=5)
    comment: str = Field(min_length=1, max_length=2000)


class ReviewModeration(StrictModel):
    status: Literal["approved", "rejected"]


class AppointmentModeration(StrictModel):
    status: Literal["confirmed", "rejected", "cancelled", "completed"]


class ReviewReport(StrictModel):
    reason: str = Field(min_length=1, max_length=1000)


class ReportModeration(StrictModel):
    status: Literal["reviewed", "dismissed"]


def _database():
    try:
        from firebase_admin import firestore

        return firestore.client(app=get_firebase_app())
    except (ImportError, RuntimeError) as error:
        _logger.error(
            "Doctor directory database is unavailable (%s).",
            type(error).__name__,
        )
        _validate_publishable(data)
        raise HTTPException(
            status_code=503,
            detail="Doctor directory storage is not configured.",
        ) from error
    except GoogleAPIError as error:
        _logger.error(
            "Doctor directory database request failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Doctor directory storage is temporarily unavailable.",
        ) from error


def require_doctor_admin(
    claims: dict[str, Any] = Depends(require_admin),
) -> dict[str, Any]:
    return claims


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _timestamp() -> str:
    return _now().isoformat()


def _commit_admin_change(
    db: Any,
    *,
    admin_uid: str,
    action: str,
    target_type: str,
    target_id: str,
    before: dict[str, bool | int | str] | None,
    after: dict[str, bool | int | str] | None,
    write: Callable[[Any], None],
) -> None:
    from google.cloud.firestore_v1 import transactional

    transaction = db.transaction(max_attempts=5)

    @transactional
    def commit(transaction: Any) -> None:
        write(transaction)
        create_audit_entry(
            db,
            admin_uid=admin_uid,
            action=action,
            target_type=target_type,
            target_id=target_id,
            before=before,
            after=after,
            transaction=transaction,
        )

    commit(transaction)


def _doctor_reference(db: Any, doctor_id: str):
    return db.collection("doctors").document(doctor_id)


def _read_doctor(db: Any, doctor_id: str, *, public_only: bool = False) -> dict[str, Any]:
    try:
        snapshot = _doctor_reference(db, doctor_id).get()
    except GoogleAPIError as error:
        _logger.error("Doctor profile read failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load this doctor.") from error
    if not snapshot.exists:
        raise HTTPException(status_code=404, detail="Doctor not found.")
    data = snapshot.to_dict() or {}
    if public_only and (
        data.get("publication_status") != "published"
        or not file_exists(
            "profiles",
            data.get("profile_photo_id", ""),
            data.get("profile_photo_extension", ""),
        )
    ):
        raise HTTPException(status_code=404, detail="Doctor not found.")
    return {"id": snapshot.id, **data}


def _public_doctor(data: dict[str, Any]) -> dict[str, Any]:
    result = {
        key: value
        for key, value in data.items()
        if key not in {
            "verification_status",
            "verification_notes",
            "verification_updated_by",
            "verification_updated_at",
            "created_by",
            "updated_by",
            "profile_photo_id",
            "profile_photo_extension",
        }
    }
    result["verified"] = data.get("verification_status") == "approved"
    if not result["verified"]:
        result.pop("qualifications", None)
        result.pop("experience_years", None)
    result["photo_url"] = (
        f"/api/doctors/{quote(str(data['id']), safe='')}/photo"
        if data.get("profile_photo_id")
        else None
    )
    return result


def _validate_publishable(data: dict[str, Any]) -> None:
    if data.get("publication_status") != "published":
        return
    if not file_exists(
        "profiles",
        data.get("profile_photo_id", ""),
        data.get("profile_photo_extension", ""),
    ):
        raise HTTPException(
            status_code=409,
            detail="Upload a real profile photo before publishing this doctor.",
        )


def _clinics_for_write(payload: DoctorWrite, old_data: dict[str, Any] | None = None):
    old_ids = {
        clinic.get("clinic_id")
        for clinic in (old_data or {}).get("clinics", [])
        if isinstance(clinic, dict)
    }
    clinics = []
    for clinic in payload.clinics:
        item = clinic.model_dump(mode="json")
        clinic_id = item.get("clinic_id")
        if clinic_id is None:
            item["clinic_id"] = str(uuid4())
        elif old_data is not None and clinic_id not in old_ids:
            raise HTTPException(status_code=422, detail="Unknown clinic identifier.")
        clinics.append(item)
    return clinics


def _active_appointments_for_doctor(db: Any, doctor_id: str) -> list[dict[str, Any]]:
    try:
        return [
            {"id": snapshot.id, **(snapshot.to_dict() or {})}
            for snapshot in db.collection("doctor_appointments")
            .where("doctor_id", "==", doctor_id)
            .stream()
            if (snapshot.to_dict() or {}).get("status") in _HELD_APPOINTMENT_STATUSES
        ]
    except GoogleAPIError as error:
        _logger.error("Doctor availability read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load appointment availability.",
        ) from error


def _clinic(data: dict[str, Any], clinic_id: str) -> dict[str, Any]:
    for item in data.get("clinics", []):
        if item.get("clinic_id") == clinic_id:
            return item
    raise HTTPException(status_code=404, detail="Clinic not found.")


def _times_for_date(
    db: Any,
    doctor: dict[str, Any],
    clinic_id: str,
    target_date: date,
    appointments: list[dict[str, Any]] | None = None,
) -> list[str]:
    clinic = _clinic(doctor, clinic_id)
    schedule = next(
        (
            item
            for item in clinic.get("weekly_schedule", [])
            if item.get("weekday") == target_date.weekday()
        ),
        {},
    )
    times = set(schedule.get("times", []))
    if not times:
        return []
    held = appointments if appointments is not None else _active_appointments_for_doctor(
        db, doctor["id"]
    )
    booked = {
        item.get("appointment_time")
        for item in held
        if item.get("appointment_date") == target_date.isoformat()
        and item.get("doctor_id") == doctor["id"]
    }
    now_local = datetime.now(_IRAQ_TZ)
    if target_date == now_local.date():
        times = {
            slot
            for slot in times
            if datetime.strptime(slot, "%H:%M").time() > now_local.time().replace(
                tzinfo=None, second=0, microsecond=0
            )
        }
    return sorted(times - booked)


def _next_available(
    db: Any, doctor: dict[str, Any], *, within_days: int = 30
) -> str | None:
    today = datetime.now(_IRAQ_TZ).date()
    appointments = _active_appointments_for_doctor(db, doctor["id"])
    for offset in range(within_days + 1):
        target = today + timedelta(days=offset)
        for clinic in doctor.get("clinics", []):
            if _times_for_date(
                db,
                doctor,
                clinic.get("clinic_id", ""),
                target,
                appointments,
            ):
                return target.isoformat()
    return None


def _review_stats(db: Any, doctor_id: str) -> tuple[float | None, int]:
    try:
        ratings = [
            item.to_dict().get("rating")
            for item in db.collection("doctor_reviews")
            .where("doctor_id", "==", doctor_id)
            .stream()
            if (item.to_dict() or {}).get("status") == "approved"
            and isinstance((item.to_dict() or {}).get("rating"), int)
        ]
    except GoogleAPIError as error:
        _logger.error("Doctor review summary failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load doctor reviews.") from error
    if not ratings:
        return None, 0
    return round(sum(ratings) / len(ratings), 2), len(ratings)


@router.get("")
def list_doctors(
    search: str | None = Query(default=None, max_length=200),
    city: str | None = Query(default=None, max_length=100),
    specialization: str | None = Query(default=None, max_length=100),
    clinic: str | None = Query(default=None, max_length=200),
    available_within_days: int | None = Query(default=None, ge=0, le=30),
    sort: Literal["rating", "experience"] = "rating",
    limit: int = Query(default=100, ge=1, le=200),
) -> list[dict[str, Any]]:
    db = _database()
    try:
        snapshots = db.collection("doctors").limit(500).stream()
        doctors = []
        for snapshot in snapshots:
            data = snapshot.to_dict() or {}
            if data.get("publication_status") != "published" or not file_exists(
                "profiles",
                data.get("profile_photo_id", ""),
                data.get("profile_photo_extension", ""),
            ):
                continue
            item = {"id": snapshot.id, **data}
            if search and search.casefold() not in item.get("full_name", "").casefold():
                continue
            if city and city.casefold() not in {
                (record.get("city") or "").casefold()
                for record in item.get("clinics", [])
            }:
                continue
            if specialization and specialization.casefold() not in {
                value.casefold() for value in item.get("specializations", [])
            }:
                continue
            if clinic and not any(
                clinic.casefold() in record.get("name", "").casefold()
                for record in item.get("clinics", [])
            ):
                continue
            if available_within_days is not None:
                next_date = _next_available(
                    db,
                    item,
                    within_days=available_within_days,
                )
                if next_date is None:
                    continue
                item["next_available_date"] = next_date
            rating = item.get("average_rating")
            experience = (
                item.get("experience_years")
                if item.get("verification_status") == "approved"
                else None
            )
            item["_sort_value"] = (
                rating if sort == "rating" and isinstance(rating, (int, float))
                else experience if sort == "experience" and isinstance(experience, int)
                else -1
            )
            doctors.append(item)
    except GoogleAPIError as error:
        _logger.error("Doctor directory list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load doctors.") from error

    doctors.sort(
        key=lambda item: (
            item.get("verification_status") == "approved",
            item.pop("_sort_value", -1),
            item.get("full_name", "").casefold(),
        ),
        reverse=True,
    )
    return [_public_doctor(item) for item in doctors[:limit]]


@router.get("/{doctor_id}")
def get_doctor(doctor_id: str) -> dict[str, Any]:
    db = _database()
    doctor = _read_doctor(db, doctor_id, public_only=True)
    if not file_exists(
        "profiles",
        doctor.get("profile_photo_id", ""),
        doctor.get("profile_photo_extension", ""),
    ):
        raise HTTPException(status_code=404, detail="Doctor not found.")
    average_rating, review_count = _review_stats(db, doctor_id)
    doctor["average_rating"] = average_rating
    doctor["review_count"] = review_count
    return _public_doctor(doctor)


@router.get("/{doctor_id}/photo")
def get_doctor_photo(doctor_id: str) -> Response:
    doctor = _read_doctor(_database(), doctor_id, public_only=True)
    file_id = doctor.get("profile_photo_id")
    extension = doctor.get("profile_photo_extension")
    media_types = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
    if not isinstance(file_id, str) or extension not in media_types:
        raise HTTPException(status_code=404, detail="Doctor photo not found.")
    try:
        content = read_file("profiles", file_id, extension)
    except (FileNotFoundError, ValueError):
        raise HTTPException(status_code=404, detail="Doctor photo not found.") from None
    except OSError as error:
        _logger.error("Doctor photo read failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load doctor photo.") from error
    return Response(
        content=content,
        media_type=media_types[extension],
        headers={"Cache-Control": "public, max-age=300", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/{doctor_id}/availability")
def doctor_availability(
    doctor_id: str,
    clinic_id: str,
    target_date: date = Query(alias="date"),
) -> dict[str, Any]:
    today = datetime.now(_IRAQ_TZ).date()
    if target_date < today or target_date > today + timedelta(days=365):
        raise HTTPException(status_code=422, detail="Choose a date within the next year.")
    db = _database()
    doctor = _read_doctor(db, doctor_id, public_only=True)
    try:
        available = _times_for_date(db, doctor, clinic_id, target_date)
    except HTTPException:
        raise
    return {
        "doctor_id": doctor_id,
        "clinic_id": clinic_id,
        "date": target_date.isoformat(),
        "times": available,
        "timezone": "Asia/Baghdad",
    }


@router.get("/{doctor_id}/reviews")
def doctor_reviews(
    doctor_id: str,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[dict[str, Any]]:
    doctor = _read_doctor(_database(), doctor_id, public_only=True)
    del doctor
    try:
        reviews = [
            {"id": snapshot.id, **(snapshot.to_dict() or {})}
            for snapshot in _database()
            .collection("doctor_reviews")
            .where("doctor_id", "==", doctor_id)
            .stream()
            if (snapshot.to_dict() or {}).get("status") == "approved"
        ]
    except GoogleAPIError as error:
        _logger.error("Doctor reviews read failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load doctor reviews.") from error
    reviews.sort(key=lambda item: item.get("created_at", ""), reverse=True)
    return reviews[:limit]


@router.get("/{doctor_id}/favorite")
def get_favorite(
    doctor_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, bool]:
    _read_doctor(_database(), doctor_id, public_only=True)
    try:
        favorite = (
            _database()
            .collection("users")
            .document(user["uid"])
            .collection("doctor_favorites")
            .document(doctor_id)
            .get()
            .exists
        )
    except GoogleAPIError as error:
        _logger.error("Doctor favorite read failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load favorites.") from error
    return {"is_favorite": favorite}


@router.put("/{doctor_id}/favorite")
def add_favorite(
    doctor_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, bool]:
    db = _database()
    _read_doctor(db, doctor_id, public_only=True)
    try:
        db.collection("users").document(user["uid"]).collection(
            "doctor_favorites"
        ).document(doctor_id).set({"created_at": _timestamp(), "doctor_id": doctor_id})
    except GoogleAPIError as error:
        _logger.error("Doctor favorite write failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not save this favorite.") from error
    return {"is_favorite": True}


@router.delete("/{doctor_id}/favorite")
def remove_favorite(
    doctor_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, bool]:
    try:
        (
            _database()
            .collection("users")
            .document(user["uid"])
            .collection("doctor_favorites")
            .document(doctor_id)
            .delete()
        )
    except GoogleAPIError as error:
        _logger.error("Doctor favorite delete failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not remove this favorite.") from error
    return {"is_favorite": False}


@router.get("/favorites/mine")
def list_favorites(
    user: dict[str, Any] = Depends(require_firebase_user),
) -> list[dict[str, Any]]:
    db = _database()
    try:
        references = db.collection("users").document(user["uid"]).collection(
            "doctor_favorites"
        ).stream()
        doctors = []
        for favorite in references:
            snapshot = _doctor_reference(db, favorite.id).get()
            if snapshot.exists:
                doctor = {"id": snapshot.id, **(snapshot.to_dict() or {})}
                if doctor.get("publication_status") == "published" and file_exists(
                    "profiles",
                    doctor.get("profile_photo_id", ""),
                    doctor.get("profile_photo_extension", ""),
                ):
                    doctors.append(_public_doctor(doctor))
        return doctors
    except GoogleAPIError as error:
        _logger.error("Doctor favorites list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load favorites.") from error


@router.post("/admin/doctors", status_code=201)
def create_doctor(
    payload: DoctorWrite,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    db = _database()
    doctor_id = str(uuid4())
    data = payload.model_dump(mode="json")
    data["clinics"] = _clinics_for_write(payload)
    data.update(
        {
            "verification_status": "unverified",
            "verification_notes": None,
            "profile_photo_id": None,
            "profile_photo_extension": None,
            "average_rating": None,
            "review_count": 0,
            "created_at": _timestamp(),
            "updated_at": _timestamp(),
            "created_by": admin["uid"],
            "updated_by": admin["uid"],
        }
    )
    try:
        _commit_admin_change(
            db,
            admin_uid=admin["uid"],
            action="doctor.created",
            target_type="doctor",
            target_id=doctor_id,
            before=None,
            after={
                "publication_status": data["publication_status"],
                "verification_status": "unverified",
            },
            write=lambda transaction: transaction.create(
                _doctor_reference(db, doctor_id),
                data,
            ),
        )
    except GoogleAPIError as error:
        _logger.error("Doctor profile create failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not create doctor profile.") from error
    return {"id": doctor_id, **_admin_doctor(data)}


def _admin_doctor(data: dict[str, Any]) -> dict[str, Any]:
    result = dict(data)
    result.pop("created_by", None)
    result.pop("updated_by", None)
    return result


def _verification_document_list(db: Any, doctor_id: str) -> list[dict[str, Any]]:
    try:
        return [
            {"id": snapshot.id, **{
                key: value
                for key, value in (snapshot.to_dict() or {}).items()
                if key not in {"file_id", "uploaded_by"}
            }}
            for snapshot in (
                db.collection("doctor_private")
                .document(doctor_id)
                .collection("verification_documents")
                .stream()
            )
        ]
    except GoogleAPIError as error:
        _logger.error(
            "Verification document list failed (%s).",
            type(error).__name__,
        )
        raise HTTPException(
            status_code=503,
            detail="Could not load verification documents.",
        ) from error


@router.get("/admin/doctors")
def list_admin_doctors(
    _: dict[str, Any] = Depends(require_doctor_admin),
) -> list[dict[str, Any]]:
    try:
        db = _database()
        doctors = []
        for snapshot in db.collection("doctors").limit(500).stream():
            doctor = {"id": snapshot.id, **_admin_doctor(snapshot.to_dict() or {})}
            doctor["verification_documents"] = _verification_document_list(
                db,
                snapshot.id,
            )
            doctors.append(doctor)
        return doctors
    except GoogleAPIError as error:
        _logger.error("Admin doctor list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load doctor profiles.") from error


@router.put("/admin/doctors/{doctor_id}")
def update_doctor(
    doctor_id: str,
    payload: DoctorWrite,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    db = _database()
    old_data = _read_doctor(db, doctor_id)
    data = payload.model_dump(mode="json")
    data["clinics"] = _clinics_for_write(payload, old_data)
    data.update({"updated_at": _timestamp(), "updated_by": admin["uid"]})
    _validate_publishable({**old_data, **data})
    try:
        _commit_admin_change(
            db,
            admin_uid=admin["uid"],
            action="doctor.updated",
            target_type="doctor",
            target_id=doctor_id,
            before={
                "publication_status": str(old_data.get("publication_status", "draft")),
                "verification_status": str(old_data.get("verification_status", "unverified")),
            },
            after={
                "publication_status": data["publication_status"],
                "verification_status": str(
                    data.get(
                        "verification_status",
                        old_data.get("verification_status", "unverified"),
                    )
                ),
            },
            write=lambda transaction: transaction.update(
                _doctor_reference(db, doctor_id),
                data,
            ),
        )
    except GoogleAPIError as error:
        _logger.error("Doctor profile update failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not update doctor profile.") from error
    return {"id": doctor_id, **_admin_doctor({**old_data, **data})}


@router.post("/admin/doctors/{doctor_id}/photo")
async def upload_doctor_photo(
    doctor_id: str,
    file: UploadFile = File(...),
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, str]:
    db = _database()
    doctor = _read_doctor(db, doctor_id)
    raw = await file.read(_MAX_UPLOAD_BYTES + 1)
    if len(raw) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="The profile image is too large.")
    try:
        image = Image.open(BytesIO(raw))
        image.verify()
        extension = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}.get(
            image.format or ""
        )
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError):
        extension = None
    if extension is None:
        raise HTTPException(status_code=400, detail="Choose a valid JPG, PNG, or WebP image.")
    file_id = store_file("profiles", extension, raw)
    previous_id = doctor.get("profile_photo_id")
    previous_extension = doctor.get("profile_photo_extension")
    try:
        _commit_admin_change(
            db,
            admin_uid=admin["uid"],
            action="doctor.photo_uploaded",
            target_type="doctor",
            target_id=doctor_id,
            before={"profile_photo": bool(previous_id)},
            after={"profile_photo": True},
            write=lambda transaction: transaction.update(
                _doctor_reference(db, doctor_id),
                {
                    "profile_photo_id": file_id,
                    "profile_photo_extension": extension,
                    "updated_at": _timestamp(),
                    "updated_by": admin["uid"],
                },
            ),
        )
    except GoogleAPIError as error:
        delete_file("profiles", file_id, extension)
        _logger.error("Doctor photo metadata update failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not save doctor photo.") from error
    if previous_id and previous_extension:
        delete_file("profiles", previous_id, previous_extension)
    return {"photo_url": f"/api/doctors/{quote(doctor_id, safe='')}/photo"}


@router.post("/admin/doctors/{doctor_id}/verification-documents", status_code=201)
async def upload_verification_document(
    doctor_id: str,
    file: UploadFile = File(...),
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    db = _database()
    doctor = _read_doctor(db, doctor_id)
    raw = await file.read(_MAX_UPLOAD_BYTES + 1)
    if len(raw) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="The verification document is too large.")
    if raw.startswith(b"%PDF-"):
        extension, content_type = "pdf", "application/pdf"
    else:
        try:
            image = Image.open(BytesIO(raw))
            image.verify()
            extension, content_type = {
                "JPEG": ("jpg", "image/jpeg"),
                "PNG": ("png", "image/png"),
                "WEBP": ("webp", "image/webp"),
            }.get(image.format or "", (None, None))
        except (
            Image.DecompressionBombError,
            UnidentifiedImageError,
            OSError,
            ValueError,
        ):
            extension, content_type = None, None
    if extension is None or content_type is None:
        raise HTTPException(
            status_code=400,
            detail="Choose a valid PDF, JPG, PNG, or WebP verification document.",
        )
    document_id = str(uuid4())
    file_id = store_file("verification", extension, raw)
    document = {
        "file_id": file_id,
        "extension": extension,
        "content_type": content_type,
        "filename": (file.filename or "verification-document")[:200],
        "uploaded_by": admin["uid"],
        "uploaded_at": _timestamp(),
    }
    reference = (
        db.collection("doctor_private")
        .document(doctor_id)
        .collection("verification_documents")
        .document(document_id)
    )

    def write_verification_document(transaction: Any) -> None:
        transaction.set(reference, document)
        transaction.update(
            _doctor_reference(db, doctor_id),
            {
                "verification_status": "pending",
                "updated_at": _timestamp(),
                "updated_by": admin["uid"],
            },
        )

    try:
        _commit_admin_change(
            db,
            admin_uid=admin["uid"],
            action="doctor.verification_document_uploaded",
            target_type="doctor",
            target_id=doctor_id,
            before={
                "verification_status": str(
                    doctor.get("verification_status", "unverified")
                ),
            },
            after={
                "verification_status": "pending",
                "document_uploaded": True,
            },
            write=write_verification_document,
        )
    except GoogleAPIError as error:
        delete_file("verification", file_id, extension)
        _logger.error("Verification document save failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not save verification document.",
        ) from error
    return {"id": document_id, "uploaded_at": document["uploaded_at"]}


@router.get("/admin/doctors/{doctor_id}/verification-documents/{document_id}")
def read_verification_document(
    doctor_id: str,
    document_id: str,
    _: dict[str, Any] = Depends(require_doctor_admin),
) -> Response:
    try:
        snapshot = (
            _database()
            .collection("doctor_private")
            .document(doctor_id)
            .collection("verification_documents")
            .document(document_id)
            .get()
        )
    except GoogleAPIError as error:
        _logger.error("Verification document read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load verification document.",
        ) from error
    if not snapshot.exists:
        raise HTTPException(status_code=404, detail="Verification document not found.")
    data = snapshot.to_dict() or {}
    try:
        content = read_file("verification", data["file_id"], data["extension"])
    except (FileNotFoundError, ValueError, KeyError):
        raise HTTPException(status_code=404, detail="Verification document not found.") from None
    except OSError as error:
        _logger.error("Verification document file read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load verification document.",
        ) from error
    filename = quote(str(data.get("filename") or "verification-document"))
    return Response(
        content=content,
        media_type=data.get("content_type", "application/octet-stream"),
        headers={
            "Cache-Control": "no-store",
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.put("/admin/doctors/{doctor_id}/verification")
def decide_verification(
    doctor_id: str,
    payload: VerificationDecision,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    db = _database()
    doctor = _read_doctor(db, doctor_id)
    if payload.status == "approved":
        documents = (
            db.collection("doctor_private")
            .document(doctor_id)
            .collection("verification_documents")
            .limit(1)
            .stream()
        )
        if not any(True for _ in documents):
            raise HTTPException(
                status_code=409,
                detail="Upload and review at least one verification document first.",
            )
    update = {
        "verification_status": payload.status,
        "verification_notes": payload.notes,
        "verification_updated_by": admin["uid"],
        "verification_updated_at": _timestamp(),
        "updated_at": _timestamp(),
        "updated_by": admin["uid"],
    }
    try:
        _commit_admin_change(
            db,
            admin_uid=admin["uid"],
            action="doctor.verification_changed",
            target_type="doctor",
            target_id=doctor_id,
            before={
                "verification_status": str(
                    doctor.get("verification_status", "unverified")
                ),
            },
            after={"verification_status": payload.status},
            write=lambda transaction: transaction.update(
                _doctor_reference(db, doctor_id),
                update,
            ),
        )
    except GoogleAPIError as error:
        _logger.error("Doctor verification update failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not update verification.") from error
    return {
        "id": doctor_id,
        "verification_status": payload.status,
        "verified": payload.status == "approved",
    }


def _slot_id(doctor_id: str, target_date: str, target_time: str) -> str:
    import hashlib

    raw = f"{doctor_id}|{target_date}|{target_time}".encode()
    return hashlib.sha256(raw).hexdigest()


def _scheduled_for(
    doctor: dict[str, Any],
    clinic_id: str,
    target_date: date,
    target_time: str,
) -> bool:
    clinic = _clinic(doctor, clinic_id)
    if not _TIME_PATTERN.fullmatch(target_time):
        return False
    schedule = next(
        (
            item
            for item in clinic.get("weekly_schedule", [])
            if item.get("weekday") == target_date.weekday()
        ),
        {},
    )
    if target_time not in schedule.get("times", []):
        return False
    now_local = datetime.now(_IRAQ_TZ)
    if target_date < now_local.date():
        return False
    if target_date == now_local.date() and time.fromisoformat(target_time) <= now_local.time().replace(
        tzinfo=None, second=0, microsecond=0
    ):
        return False
    return True


def _appointment_public(data: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in data.items()
        if key not in {"patient_uid", "patient_name"}
    }


@router.get("/appointments")
def list_my_appointments(
    user: dict[str, Any] = Depends(require_firebase_user),
) -> list[dict[str, Any]]:
    try:
        appointments = [
            {"id": snapshot.id, **_appointment_public(snapshot.to_dict() or {})}
            for snapshot in _database()
            .collection("doctor_appointments")
            .where("patient_uid", "==", user["uid"])
            .stream()
        ]
    except GoogleAPIError as error:
        _logger.error("Appointment history read failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not load appointment history.",
        ) from error
    appointments.sort(
        key=lambda item: (
            item.get("appointment_date", ""),
            item.get("appointment_time", ""),
        ),
        reverse=True,
    )
    return appointments


@router.post("/appointments", status_code=201)
def request_appointment(
    payload: AppointmentRequest,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    db = _database()
    doctor_id = payload.doctor_id
    doctor_reference = _doctor_reference(db, doctor_id)
    doctor = _read_doctor(db, doctor_id, public_only=True)
    clinic = _clinic(doctor, payload.clinic_id)
    today = datetime.now(_IRAQ_TZ).date()
    if payload.appointment_date < today or payload.appointment_date > today + timedelta(
        days=365
    ):
        raise HTTPException(status_code=422, detail="Choose a date within the next year.")
    if not _scheduled_for(
        doctor,
        payload.clinic_id,
        payload.appointment_date,
        payload.appointment_time,
    ):
        raise HTTPException(status_code=409, detail="That time is not available.")

    appointment_id = str(uuid4())
    appointment_reference = db.collection("doctor_appointments").document(
        appointment_id
    )
    slot_reference = db.collection("doctor_appointment_slots").document(
        _slot_id(
            doctor_id,
            payload.appointment_date.isoformat(),
            payload.appointment_time,
        )
    )
    record = {
        "doctor_id": doctor_id,
        "doctor_name": doctor.get("full_name", ""),
        "clinic_id": payload.clinic_id,
        "clinic_name": clinic.get("name", ""),
        "city": clinic.get("city", ""),
        "appointment_date": payload.appointment_date.isoformat(),
        "appointment_time": payload.appointment_time,
        "timezone": "Asia/Baghdad",
        "status": "pending",
        "patient_uid": user["uid"],
        "patient_name": user.get("name") if isinstance(user.get("name"), str) else None,
        "created_at": _timestamp(),
        "updated_at": _timestamp(),
    }
    try:
        from google.cloud.firestore_v1 import transactional

        transaction = db.transaction(max_attempts=5)

        @transactional
        def reserve_slot(tx: Any) -> None:
            doctor_snapshot = doctor_reference.get(transaction=tx)
            current_doctor = doctor_snapshot.to_dict() or {}
            if (
                not doctor_snapshot.exists
                or current_doctor.get("publication_status") != "published"
            ):
                raise HTTPException(status_code=404, detail="Doctor not found.")
            if not _scheduled_for(
                {"id": doctor_id, **current_doctor},
                payload.clinic_id,
                payload.appointment_date,
                payload.appointment_time,
            ):
                raise HTTPException(status_code=409, detail="That time is not available.")
            slot_snapshot = slot_reference.get(transaction=tx)
            if (
                slot_snapshot.exists
                and (slot_snapshot.to_dict() or {}).get("status")
                in _HELD_APPOINTMENT_STATUSES
            ):
                raise HTTPException(status_code=409, detail="That time was just booked.")
            tx.set(
                slot_reference,
                {
                    "appointment_id": appointment_id,
                    "status": "pending",
                    "doctor_id": doctor_id,
                    "clinic_id": payload.clinic_id,
                    "appointment_date": payload.appointment_date.isoformat(),
                    "appointment_time": payload.appointment_time,
                },
            )
            tx.create(appointment_reference, record)

        reserve_slot(transaction)
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Appointment booking failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not request this appointment.",
        ) from error
    except (ImportError, RuntimeError) as error:
        _logger.error("Appointment transaction unavailable (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Appointment booking is temporarily unavailable.",
        ) from error
    return {"id": appointment_id, **_appointment_public(record)}


def _change_appointment_status(
    db: Any,
    appointment_id: str,
    target_status: str,
    *,
    patient_uid: str | None = None,
    admin_uid: str | None = None,
    reason: str | None = None,
) -> dict[str, Any]:
    appointment_reference = db.collection("doctor_appointments").document(
        appointment_id
    )
    try:
        from google.cloud.firestore_v1 import transactional

        transaction = db.transaction(max_attempts=5)
        updated_record: dict[str, Any] = {}

        @transactional
        def update_status(tx: Any) -> None:
            nonlocal updated_record
            snapshot = appointment_reference.get(transaction=tx)
            if not snapshot.exists:
                raise HTTPException(status_code=404, detail="Appointment not found.")
            current = snapshot.to_dict() or {}
            if patient_uid is not None and current.get("patient_uid") != patient_uid:
                raise HTTPException(status_code=404, detail="Appointment not found.")
            current_status = current.get("status")
            if target_status == "cancelled":
                allowed = current_status in _HELD_APPOINTMENT_STATUSES
            elif target_status == "confirmed":
                allowed = current_status == "pending"
            elif target_status == "rejected":
                allowed = current_status in _HELD_APPOINTMENT_STATUSES
            else:
                allowed = current_status == "confirmed"
            if not allowed:
                raise HTTPException(
                    status_code=409,
                    detail="This appointment can no longer change to that status.",
                )
            updated_record = {
                **current,
                "status": target_status,
                "updated_at": _timestamp(),
            }
            update = {
                "status": target_status,
                "updated_at": updated_record["updated_at"],
            }
            if admin_uid is not None:
                updated_record["moderated_by"] = admin_uid
                update["moderated_by"] = admin_uid
                if reason is not None:
                    normalized_reason = reason.strip()
                    updated_record["moderation_reason"] = normalized_reason
                    update["moderation_reason"] = normalized_reason
            slot_reference = db.collection("doctor_appointment_slots").document(
                _slot_id(
                    current["doctor_id"],
                    current["appointment_date"],
                    current["appointment_time"],
                )
            )
            tx.update(appointment_reference, update)
            tx.set(
                slot_reference,
                {
                    "appointment_id": appointment_id,
                    "status": target_status,
                },
                merge=True,
            )
            if admin_uid is not None:
                create_audit_entry(
                    db,
                    admin_uid=admin_uid,
                    action="appointment.status_changed",
                    target_type="appointment",
                    target_id=appointment_id,
                    before={"status": str(current_status)},
                    after={
                        "status": target_status,
                        "reason_provided": reason is not None,
                    },
                    transaction=tx,
                )

        update_status(transaction)
        return {"id": appointment_id, **_appointment_public(updated_record)}
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Appointment status update failed (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Could not update appointment status.",
        ) from error
    except (ImportError, RuntimeError) as error:
        _logger.error("Appointment transaction unavailable (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Appointment updates are temporarily unavailable.",
        ) from error


@router.post("/appointments/{appointment_id}/cancel")
def cancel_appointment(
    appointment_id: str,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    return _change_appointment_status(
        _database(),
        appointment_id,
        "cancelled",
        patient_uid=user["uid"],
    )


@router.post("/appointments/{appointment_id}/review", status_code=201)
def create_appointment_review(
    appointment_id: str,
    payload: ReviewRequest,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, Any]:
    if payload.appointment_id != appointment_id:
        raise HTTPException(status_code=422, detail="Appointment identifiers do not match.")
    db = _database()
    appointment_reference = db.collection("doctor_appointments").document(
        appointment_id
    )
    review_reference = db.collection("doctor_reviews").document(appointment_id)
    record: dict[str, Any] = {}
    try:
        from google.cloud.firestore_v1 import transactional

        transaction = db.transaction(max_attempts=5)

        @transactional
        def create_review(tx: Any) -> None:
            nonlocal record
            appointment_snapshot = appointment_reference.get(transaction=tx)
            if not appointment_snapshot.exists:
                raise HTTPException(status_code=404, detail="Appointment not found.")
            appointment = appointment_snapshot.to_dict() or {}
            if appointment.get("patient_uid") != user["uid"]:
                raise HTTPException(status_code=404, detail="Appointment not found.")
            if appointment.get("status") != "completed":
                raise HTTPException(
                    status_code=409,
                    detail="Reviews are available after a completed appointment.",
                )
            if review_reference.get(transaction=tx).exists:
                raise HTTPException(
                    status_code=409,
                    detail="A review has already been submitted for this appointment.",
                )
            record = {
                "doctor_id": appointment["doctor_id"],
                "appointment_id": appointment_id,
                "patient_uid": user["uid"],
                "rating": payload.rating,
                "comment": payload.comment.strip(),
                "status": "pending",
                "created_at": _timestamp(),
            }
            tx.create(review_reference, record)

        create_review(transaction)
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Doctor review submit failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not submit review.") from error
    except (ImportError, RuntimeError) as error:
        _logger.error("Review transaction unavailable (%s).", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Review submission is temporarily unavailable.",
        ) from error
    return {"id": appointment_id, **_public_review(record)}


def _public_review(data: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in data.items()
        if key not in {"patient_uid", "appointment_id", "status"}
    }


@router.post("/{doctor_id}/reviews/{review_id}/report", status_code=201)
def report_doctor_review(
    doctor_id: str,
    review_id: str,
    payload: ReviewReport,
    user: dict[str, Any] = Depends(require_firebase_user),
) -> dict[str, str]:
    db = _database()
    review_reference = db.collection("doctor_reviews").document(review_id)
    try:
        review_snapshot = review_reference.get()
        review = review_snapshot.to_dict() or {}
        if (
            not review_snapshot.exists
            or review.get("doctor_id") != doctor_id
            or review.get("status") != "approved"
        ):
            raise HTTPException(status_code=404, detail="Review not found.")
        reporter_reference = review_reference.collection("reporters").document(
            user["uid"]
        )
        if reporter_reference.get().exists:
            raise HTTPException(status_code=409, detail="You have already reported this review.")
        report_id = str(uuid4())
        report = {
            "doctor_id": doctor_id,
            "review_id": review_id,
            "reporter_uid": user["uid"],
            "reason": payload.reason.strip(),
            "status": "pending",
            "created_at": _timestamp(),
        }
        db.collection("doctor_review_reports").document(report_id).set(report)
        reporter_reference.set({"report_id": report_id, "created_at": report["created_at"]})
        return {"id": report_id, "status": "pending"}
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Doctor review report failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not report this review.") from error


@router.get("/admin/appointments")
def list_admin_appointments(
    status_filter: str | None = Query(default=None, alias="status"),
    _: dict[str, Any] = Depends(require_doctor_admin),
) -> list[dict[str, Any]]:
    try:
        records = [
            {"id": snapshot.id, **(snapshot.to_dict() or {})}
            for snapshot in _database().collection("doctor_appointments").stream()
        ]
    except GoogleAPIError as error:
        _logger.error("Admin appointment list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load appointments.") from error
    if status_filter is not None:
        records = [item for item in records if item.get("status") == status_filter]
    return sorted(
        records,
        key=lambda item: (
            item.get("appointment_date", ""),
            item.get("appointment_time", ""),
        ),
    )


@router.patch("/admin/appointments/{appointment_id}")
def moderate_appointment(
    appointment_id: str,
    payload: AppointmentModeration,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    return _change_appointment_status(
        _database(),
        appointment_id,
        payload.status,
        admin_uid=admin["uid"],
    )


@router.get("/admin/reviews")
def list_admin_reviews(
    status_filter: str = Query(default="pending", alias="status"),
    _: dict[str, Any] = Depends(require_doctor_admin),
) -> list[dict[str, Any]]:
    try:
        reviews = [
            {"id": snapshot.id, **(snapshot.to_dict() or {})}
            for snapshot in _database().collection("doctor_reviews").stream()
            if (snapshot.to_dict() or {}).get("status") == status_filter
        ]
        reports = list(_database().collection("doctor_review_reports").stream())
        report_counts: dict[str, int] = {}
        for report in reports:
            report_data = report.to_dict() or {}
            review_id = report_data.get("review_id")
            if isinstance(review_id, str):
                report_counts[review_id] = report_counts.get(review_id, 0) + 1
        for review in reviews:
            review["report_count"] = report_counts.get(review["id"], 0)
        return reviews
    except GoogleAPIError as error:
        _logger.error("Admin review list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load reviews.") from error


@router.patch("/admin/reviews/{review_id}")
def moderate_review(
    review_id: str,
    payload: ReviewModeration,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, Any]:
    db = _database()
    reference = db.collection("doctor_reviews").document(review_id)
    try:
        snapshot = reference.get()
        if not snapshot.exists:
            raise HTTPException(status_code=404, detail="Review not found.")
        review = snapshot.to_dict() or {}
        reference.update(
            {
                "status": payload.status,
                "moderated_by": admin["uid"],
                "moderated_at": _timestamp(),
            }
        )
        average_rating, review_count = _review_stats(db, review["doctor_id"])
        _doctor_reference(db, review["doctor_id"]).update(
            {
                "average_rating": average_rating,
                "review_count": review_count,
                "updated_at": _timestamp(),
            }
        )
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Review moderation failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not moderate review.") from error
    return {"id": review_id, "status": payload.status}


@router.get("/admin/reports")
def list_admin_reports(
    _: dict[str, Any] = Depends(require_doctor_admin),
) -> list[dict[str, Any]]:
    try:
        reports = [
            {"id": snapshot.id, **(snapshot.to_dict() or {})}
            for snapshot in _database().collection("doctor_review_reports").stream()
        ]
    except GoogleAPIError as error:
        _logger.error("Review report list failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not load review reports.") from error
    return sorted(reports, key=lambda item: item.get("created_at", ""), reverse=True)


@router.patch("/admin/reports/{report_id}")
def moderate_report(
    report_id: str,
    payload: ReportModeration,
    admin: dict[str, Any] = Depends(require_doctor_admin),
) -> dict[str, str]:
    try:
        reference = _database().collection("doctor_review_reports").document(report_id)
        snapshot = reference.get()
        if not snapshot.exists:
            raise HTTPException(status_code=404, detail="Review report not found.")
        reference.update(
            {
                "status": payload.status,
                "moderated_by": admin["uid"],
                "moderated_at": _timestamp(),
            }
        )
    except HTTPException:
        raise
    except GoogleAPIError as error:
        _logger.error("Review report moderation failed (%s).", type(error).__name__)
        raise HTTPException(status_code=503, detail="Could not moderate report.") from error
    return {"id": report_id, "status": payload.status}
