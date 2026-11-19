from __future__ import annotations

import re
from typing import Literal

from .schemas import (
    MedicalReportExtraction,
    MedicationRecognition,
    PatientInput,
    SafetyAssessment,
)

ConcernLevel = Literal[
    "low",
    "moderate",
    "high",
    "prompt_in_person",
    "insufficient",
]

_HIGH_RISK_PATTERNS = (
    re.compile(r"\bmelanoma\b|\bmel\b"),
    re.compile(r"\bbasal\s+cell\s+carcinoma\b|\bbcc\b"),
    re.compile(r"\bsquamous\s+cell\s+carcinoma\b|\bscc\b"),
    re.compile(r"\bactinic\s+keratosis\b|\bakiec\b"),
    re.compile(r"\bmalignan\w*\b|\bpre[- ]?malignan\w*\b"),
    re.compile(r"\bcarcinoma\b|\bcancer\b"),
)
_HIGH_CONCERN_PATTERNS = (
    re.compile(r"\bhigh[- ]concern\b|\bhigh[- ]risk\b"),
    re.compile(r"\burgent\b|\bprompt\s+(?:in[- ]person|dermatolog)"),
)
_INSUFFICIENT_PATTERNS = (
    re.compile(r"\bblurr(?:y|ed)\b|\bunusable\b|\binsufficient\b"),
    re.compile(r"\binadequate\b|\bpoor\s+quality\b|\bnot\s+(?:a\s+)?skin\s+image\b"),
    re.compile(r"\bunable\s+to\s+(?:assess|analy[sz]e)\b|\bcannot\s+assess\b"),
)
_BENIGN_PATTERNS = (
    re.compile(r"\bbenign\b|\bnevus\b|\bnaevus\b"),
    re.compile(r"\bbkl\b|\bdf\b|\bvasc\b"),
)


def classify_skin_analysis(
    skin_analysis: dict[str, object],
) -> tuple[ConcernLevel, bool]:
    result_text = str(skin_analysis.get("result", "")).casefold()
    summary_text = str(skin_analysis.get("summary", "")).casefold()
    insufficient = any(
        pattern.search(result_text) or pattern.search(summary_text)
        for pattern in _INSUFFICIENT_PATTERNS
    )
    high_risk = any(pattern.search(result_text) for pattern in _HIGH_RISK_PATTERNS)
    high_concern = any(
        pattern.search(result_text) or pattern.search(summary_text)
        for pattern in _HIGH_CONCERN_PATTERNS
    )
    benign = any(pattern.search(result_text) for pattern in _BENIGN_PATTERNS)

    if insufficient:
        concern_level: ConcernLevel = "insufficient"
    elif high_risk:
        concern_level = "prompt_in_person"
    elif high_concern:
        concern_level = "high"
    elif benign:
        concern_level = "low"
    else:
        concern_level = "moderate"
    return concern_level, concern_level in {"high", "prompt_in_person"}


def assess_safety(
    *,
    patient: PatientInput,
    skin_analysis: dict[str, object],
    medication: MedicationRecognition | None,
    examinations: list[MedicalReportExtraction],
) -> SafetyAssessment:
    concern_level, referral_required = classify_skin_analysis(skin_analysis)

    block_reasons: list[str] = []
    if patient.age < 12:
        block_reasons.append("under_12")
    if patient.pregnancy_or_breastfeeding in {
        "pregnant",
        "breastfeeding",
        "unsure",
    }:
        block_reasons.append("pregnancy_or_breastfeeding")
    if patient.allergies.strip():
        block_reasons.append("reported_allergy")
    else:
        block_reasons.append("allergy_information_missing")
    if concern_level in {"high", "prompt_in_person"}:
        block_reasons.append("high_concern_screening")
    if concern_level == "insufficient":
        block_reasons.append("image_or_assessment_insufficient")
    if medication is not None and not medication.verified:
        block_reasons.append("medication_unverified")
    if medication is not None and (
        medication.interactions or medication.contraindications
    ):
        block_reasons.append("medication_warnings_present")
    if any(
        finding.explicitly_flagged_abnormal is True
        for report in examinations
        for finding in report.tests
    ):
        block_reasons.append("abnormal_report_finding")

    return SafetyAssessment(
        concern_level=concern_level,
        referral_required=referral_required,
        medication_recommendations_allowed=not block_reasons,
        medication_block_reasons=block_reasons,
    )
