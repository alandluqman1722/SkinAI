from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PatientReportedExamination(StrictModel):
    examination_date: str | None = Field(default=None, max_length=100)
    doctor_findings: list[str] = Field(default_factory=list, max_length=30)
    documented_diagnosis: list[str] = Field(default_factory=list, max_length=30)


class PatientInput(StrictModel):
    age: int = Field(ge=1, le=120)
    sex: Literal["female", "male", "intersex", "prefer_not_to_say"]
    language: Literal["en", "ku", "bad", "ar"] = "en"
    allergies: str = Field(default="", max_length=2000)
    medical_history: str = Field(default="", max_length=3000)
    pregnancy_or_breastfeeding: Literal[
        "not_applicable", "pregnant", "breastfeeding", "neither", "unsure"
    ] = "not_applicable"
    symptoms_duration: str = Field(min_length=1, max_length=200)
    symptoms_details: str = Field(default="", max_length=3000)
    body_location: str = Field(default="", max_length=200)
    taking_medication: bool
    medication_status: Literal["yes", "no", "unsure"] | None = None
    medication_name: str | None = Field(default=None, max_length=200)
    medication_duration: str | None = Field(default=None, max_length=200)
    medication_prescribed: Literal["yes", "no", "unsure"] | None = None
    medication_effect: Literal[
        "improved", "worsened", "no_change", "unsure"
    ] | None = None
    had_examinations: bool
    examination_status: Literal["yes", "no", "unsure"] | None = None
    structured_examinations: list[PatientReportedExamination] = Field(
        default_factory=list,
        max_length=3,
    )
    external_processing_consent: bool
    storage_consent: bool = False

    @model_validator(mode="after")
    def require_consent_and_consistent_answers(self) -> PatientInput:
        if not self.external_processing_consent:
            raise ValueError("External processing consent is required.")
        if not self.taking_medication and any(
            value is not None
            for value in (
                self.medication_name,
                self.medication_duration,
                self.medication_prescribed,
                self.medication_effect,
            )
        ):
            raise ValueError("Medication details require a current medication.")
        if not self.had_examinations and self.structured_examinations:
            raise ValueError(
                "Structured examination details require a previous examination."
            )
        return self


class MedicationRecognition(StrictModel):
    medicine_name: str | None = Field(default=None, max_length=200)
    active_ingredients: list[str] = Field(default_factory=list, max_length=20)
    strength: str | None = Field(default=None, max_length=200)
    form: str | None = Field(default=None, max_length=200)
    manufacturer: str | None = Field(default=None, max_length=200)
    expiration_date: str | None = Field(default=None, max_length=100)
    visible_instructions: str | None = Field(default=None, max_length=1000)
    confidence: float = Field(ge=0, le=1)
    uncertainty: list[str] = Field(default_factory=list, max_length=20)
    category: str | None = Field(default=None, max_length=200)
    intended_uses: list[str] = Field(default_factory=list, max_length=20)
    how_it_works: str | None = Field(default=None, max_length=2000)
    common_side_effects: list[str] = Field(default_factory=list, max_length=30)
    serious_warning_signs: list[str] = Field(default_factory=list, max_length=30)
    contraindications: list[str] = Field(default_factory=list, max_length=30)
    interactions: list[str] = Field(default_factory=list, max_length=30)
    precautions: list[str] = Field(default_factory=list, max_length=30)
    storage_instructions: list[str] = Field(default_factory=list, max_length=20)
    verified: bool = False
    source: str | None = Field(default=None, max_length=500)
    source_date: date | None = None
    verification_note: str = Field(default="", max_length=1000)

    @model_validator(mode="after")
    def verified_details_have_provenance(self) -> MedicationRecognition:
        if self.verified and not self.source:
            raise ValueError("Verified medication information needs a source.")
        return self


class ReportTestResult(StrictModel):
    test_name: str = Field(min_length=1, max_length=200)
    date: str | None = Field(default=None, max_length=50)
    result: str = Field(min_length=1, max_length=1000)
    reference_range: str | None = Field(default=None, max_length=500)
    explicitly_flagged_abnormal: bool | None = None


class MedicalReportExtraction(StrictModel):
    source: Literal["patient_reported", "unavailable"] | None = None
    examination_date: str | None = Field(default=None, max_length=100)
    doctor_findings: list[str] = Field(default_factory=list, max_length=30)
    documented_diagnosis: list[str] = Field(default_factory=list, max_length=30)
    tests: list[ReportTestResult] = Field(default_factory=list, max_length=100)
    conclusions: list[str] = Field(default_factory=list, max_length=30)
    recommended_treatments: list[str] = Field(default_factory=list, max_length=30)
    medication_names: list[str] = Field(default_factory=list, max_length=30)
    follow_up_instructions: list[str] = Field(default_factory=list, max_length=30)
    other_report_text: list[str] = Field(default_factory=list, max_length=50)
    missing_or_unreadable: list[str] = Field(default_factory=list, max_length=30)
    uncertainty: list[str] = Field(default_factory=list, max_length=30)


class AssessmentGuidance(StrictModel):
    patient_summary: str = Field(min_length=1, max_length=3000)
    skin_analysis_context: str = Field(min_length=1, max_length=3000)
    medication_explanation: str = Field(min_length=1, max_length=5000)
    examination_explanation: str = Field(min_length=1, max_length=5000)
    reassuring_observations: list[str] = Field(default_factory=list, max_length=20)
    concerning_observations: list[str] = Field(default_factory=list, max_length=20)
    missing_information: list[str] = Field(default_factory=list, max_length=20)
    recommendations: list[str] = Field(default_factory=list, max_length=20)
    clinician_follow_up: str = Field(min_length=1, max_length=2000)
    urgent_care_guidance: str = Field(min_length=1, max_length=1500)
    disclaimer: str = Field(min_length=1, max_length=1000)


class PatientInformation(StrictModel):
    age: int
    sex: Literal["female", "male", "intersex", "prefer_not_to_say"]
    symptoms_duration: str
    symptoms_details: str
    body_location: str
    allergies: str
    medical_history: str
    pregnancy_or_breastfeeding: str


class StoredAssessmentFile(StrictModel):
    id: str
    kind: Literal["medication_image", "medical_report_0", "medical_report_1",
                  "medical_report_2"]
    mime_type: Literal[
        "application/pdf", "image/jpeg", "image/png", "image/webp"
    ]


class SafetyAssessment(StrictModel):
    concern_level: Literal[
        "low",
        "moderate",
        "high",
        "prompt_in_person",
        "insufficient",
    ] = "moderate"
    referral_required: bool = False
    medication_recommendations_allowed: bool = False
    medication_block_reasons: list[str] = Field(default_factory=list, max_length=20)


class AssessmentResponse(StrictModel):
    id: str
    created_at: str
    patient_information: PatientInformation
    skin_analysis: dict[str, object]
    medication: MedicationRecognition | None
    medication_history: dict[str, object] | None
    examinations: list[MedicalReportExtraction]
    guidance: AssessmentGuidance
    safety: SafetyAssessment = Field(default_factory=SafetyAssessment)
    original_reports_available: bool
    sources: list[str]
    original_files: list[StoredAssessmentFile] = Field(default_factory=list)
