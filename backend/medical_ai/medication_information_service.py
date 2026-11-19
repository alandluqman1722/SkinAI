from __future__ import annotations

from typing import Any

from .schemas import MedicationRecognition

_UNAVAILABLE = {
    "en": (
        "Medication package recognition is unavailable. Only the name entered "
        "by the patient can be used; other package fields were not extracted."
    ),
    "ku": (
        "ناسینەوەی پێچانی دەرمان بەردەست نییە. تەنها ناوی نووسراوی نەخۆش "
        "بەکاردێت؛ زانیارییەکانی تری پێچان دەرهێنراون."
    ),
    "bad": (
        "ناسینا پێچانا دەرمانی بەردەست نینە. تەنێ ناڤێ هاتیە نڤیسین دهێتە "
        "بکارئینان؛ زانیاریێن دی یێن پێچانێ نەهاتنە دەرهێنان."
    ),
    "ar": (
        "التعرف على عبوة الدواء غير متاح. يمكن استخدام الاسم الذي أدخله "
        "المريض فقط؛ ولم تُستخرج بقية بيانات العبوة."
    ),
}


class MedicationInformationService:
    def from_patient_input(
        self,
        *,
        medicine_name: str | None,
        language: str,
    ) -> MedicationRecognition:
        name = medicine_name.strip() if medicine_name else None
        return MedicationRecognition(
            medicine_name=name or None,
            active_ingredients=[],
            strength=None,
            form=None,
            manufacturer=None,
            expiration_date=None,
            visible_instructions=None,
            confidence=0.0,
            uncertainty=[_UNAVAILABLE[language]],
            verified=False,
            verification_note=_UNAVAILABLE[language],
        )

    @staticmethod
    def with_verified_information(
        extraction: MedicationRecognition,
        data: dict[str, Any] | None,
    ) -> MedicationRecognition:
        if data is None:
            return extraction
        allowed = {
            "active_ingredients",
            "category",
            "intended_uses",
            "how_it_works",
            "common_side_effects",
            "serious_warning_signs",
            "contraindications",
            "interactions",
            "precautions",
            "storage_instructions",
            "source",
            "source_date",
        }
        fields = {key: value for key, value in data.items() if key in allowed}
        return MedicationRecognition.model_validate({
            **extraction.model_dump(),
            **fields,
            "verified": bool(data.get("source")),
            "verification_note": (
                "Reference information is from the cited medication label."
                if data.get("source")
                else extraction.verification_note
            ),
        })
