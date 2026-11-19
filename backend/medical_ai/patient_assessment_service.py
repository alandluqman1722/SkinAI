from __future__ import annotations

import json
import logging
import threading
import time
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from fastapi import HTTPException
from google.api_core.exceptions import GoogleAPIError

from ..medical_records import _database
from .assessment_report_service import AssessmentReportService
from .encrypted_storage import _key, delete_file, encrypt, store_file
from .medical_knowledge_service import MedicalKnowledgeService
from .medical_report_service import MedicalReportService
from .medication_information_service import MedicationInformationService
from .schemas import (
    AssessmentResponse,
    MedicalReportExtraction,
    MedicationRecognition,
    PatientInput,
    PatientInformation,
    StoredAssessmentFile,
)
from .safety_policy import assess_safety
from .skin_analysis_service import SkinAnalysisService

_logger = logging.getLogger(__name__)
_RATE_LIMIT_WINDOW = 60.0
_RATE_LIMIT = 5
_rate_lock = threading.Lock()
_rate_requests: dict[str, list[float]] = {}


def enforce_assessment_rate_limit(uid: str) -> None:
    now = time.monotonic()
    with _rate_lock:
        recent = [
            timestamp
            for timestamp in _rate_requests.get(uid, [])
            if now - timestamp < _RATE_LIMIT_WINDOW
        ]
        if len(recent) >= _RATE_LIMIT:
            raise HTTPException(
                status_code=429,
                detail="Too many assessment requests. Please try again later.",
            )
        recent.append(now)
        _rate_requests[uid] = recent


class PatientAssessmentService:
    def __init__(
        self,
        *,
        skin: SkinAnalysisService | None = None,
        medical_knowledge: MedicalKnowledgeService | None = None,
        medical_reports: MedicalReportService | None = None,
        report_generation: AssessmentReportService | None = None,
    ) -> None:
        self._skin = skin or SkinAnalysisService()
        self._medication_information = MedicationInformationService()
        self._medical_knowledge = medical_knowledge or MedicalKnowledgeService()
        self._medical_reports = medical_reports or MedicalReportService()
        self._report_generation = (
            report_generation or AssessmentReportService()
        )

    async def assess(
        self,
        *,
        uid: str,
        patient: PatientInput,
        skin_image: tuple[bytes, bytes, str],
        medication_image: tuple[bytes, str] | None,
        reports: list[tuple[bytes, str, str]],
    ) -> AssessmentResponse:
        if not patient.external_processing_consent:
            raise HTTPException(
                status_code=403,
                detail="Explicit external processing consent is required.",
            )
        has_manual_medication = bool(
            patient.medication_name and patient.medication_name.strip()
        )
        has_medication_details = medication_image is not None or has_manual_medication
        if patient.medication_status == "yes" and not has_medication_details:
            raise HTTPException(
                status_code=422,
                detail="A medication photo or medication name is required.",
            )
        if (
            patient.medication_status in (None, "no")
            and patient.taking_medication != has_medication_details
        ):
            raise HTTPException(
                status_code=422,
                detail="Medication answers and uploaded image do not match.",
            )
        if patient.medication_status == "unsure" and patient.taking_medication:
            raise HTTPException(
                status_code=422,
                detail="Unsure medication answers cannot include medication details.",
            )
        has_examination_details = bool(
            reports or patient.structured_examinations
        )
        if patient.examination_status == "yes" and not has_examination_details:
            raise HTTPException(
                status_code=422,
                detail=(
                    "Enter examination details or attach a medical report."
                ),
            )
        if (
            patient.examination_status in (None, "no")
            and patient.had_examinations != has_examination_details
        ):
            raise HTTPException(
                status_code=422,
                detail="Examination answers and details do not match.",
            )
        if patient.storage_consent:
            try:
                _key()
            except RuntimeError as error:
                raise HTTPException(
                    status_code=503,
                    detail="Encrypted medical storage is not configured.",
                ) from error

        enforce_assessment_rate_limit(uid)
        _, jpeg_skin, _ = skin_image
        skin_analysis = await self._skin.analyze(
            jpeg_skin,
            body_location=patient.body_location,
            symptoms_duration=patient.symptoms_duration,
            symptoms_details=patient.symptoms_details,
        )
        medication = None
        if patient.taking_medication:
            medication = self._medication_information.from_patient_input(
                medicine_name=patient.medication_name,
                language=patient.language,
            )
            if medication.medicine_name:
                verified_info = await self._medical_knowledge.lookup_medication(
                    medication.medicine_name,
                    [],
                )
                medication = (
                    self._medication_information.with_verified_information(
                        medication,
                        verified_info,
                    )
                )
        examinations = [
            MedicalReportExtraction(
                source="patient_reported",
                examination_date=entry.examination_date,
                doctor_findings=entry.doctor_findings,
                documented_diagnosis=entry.documented_diagnosis,
            )
            for entry in patient.structured_examinations
        ]
        examinations.extend(
            [
                await self._medical_reports.extract(
                    content,
                    mime_type,
                    language=patient.language,
                )
                for content, mime_type, _ in reports
            ]
        )
        medication_history = (
            {
                "duration": patient.medication_duration,
                "prescribed_by_doctor": patient.medication_prescribed,
                "reported_effect": patient.medication_effect,
                "source": "patient_reported",
            }
            if patient.taking_medication
            else None
        )
        guidance = await self._report_generation.generate(
            patient=patient,
            skin_analysis=skin_analysis,
            medication=medication,
            examinations=examinations,
        )
        safety = assess_safety(
            patient=patient,
            skin_analysis=skin_analysis,
            medication=medication,
            examinations=examinations,
        )
        guidance = self._apply_safety_guidance(
            guidance,
            safety,
            patient.language,
            medication,
        )

        assessment_id = str(uuid4())
        created_at = datetime.now(timezone.utc).isoformat()
        response = AssessmentResponse(
            id=assessment_id,
            created_at=created_at,
            patient_information=PatientInformation(
                age=patient.age,
                sex=patient.sex,
                symptoms_duration=patient.symptoms_duration,
                symptoms_details=patient.symptoms_details,
                body_location=patient.body_location,
                allergies=patient.allergies,
                medical_history=patient.medical_history,
                pregnancy_or_breastfeeding=patient.pregnancy_or_breastfeeding,
            ),
            skin_analysis=skin_analysis,
            medication=medication,
            medication_history=medication_history,
            examinations=examinations,
            guidance=guidance,
            safety=safety,
            original_reports_available=patient.storage_consent and bool(reports),
            sources=self._sources(medication),
        )
        if patient.storage_consent:
            response = self._persist(
                uid=uid,
                response=response,
                patient=patient,
                skin_image=skin_image,
                medication_image=medication_image,
                reports=reports,
            )
        return response

    @staticmethod
    def _apply_safety_guidance(
        guidance: Any,
        safety: Any,
        language: str,
        medication: MedicationRecognition | None,
    ) -> Any:
        localized = {
            "en": {
                "safe": "Do not start, change, or stop any medication without your doctor's approval.",
                "high": "Arrange prompt in-person assessment with a dermatologist. This screening result is not a diagnosis.",
                "insufficient": "The image or information was not sufficient for a reliable screening. Consider a clear new image or an in-person assessment.",
                "follow_up": "Discuss persistent, changing, or concerning skin symptoms with a qualified dermatologist.",
                "medication_verified": "The information above summarizes the cited medication label only. It does not determine whether the medicine is suitable for your skin condition.",
                "medication_unverified": "Medication information could not be fully verified. Please confirm it with a pharmacist or doctor.",
                "no_medication": "No current medication was reported.",
            },
            "ku": {
                "safe": "بێ ڕەزامەندی پزیشک هیچ دەرمانێک دەست پێ مەکە، مەگۆڕە و مەوەستێنە.",
                "high": "بە زووترین کات پشکنینی ڕووبەڕووی لەلایەن پزیشکی پێستەوە وەربگرە. ئەم ئەنجامە تشخیص نییە.",
                "insufficient": "وێنە یان زانیارییەکان بۆ پشکنینێکی باوەڕپێکراو بەس نەبوون. وێنەیەکی ڕوونتر یان پشکنینی ڕووبەڕوو لەبەرچاو بگرە.",
                "follow_up": "نیشانەی بەردەوام، گۆڕاو یان نیگەرانکەر لەگەڵ پزیشکی پسپۆڕی پێست باس بکە.",
                "medication_verified": "زانیارییەکانی سەرەوە تەنها پوختەی لیبێڵی دەرمانی سەرچاوەدراون. ئەمە دیاری ناکات کە دەرمانەکە بۆ کێشەی پێستی تۆ گونجاوە.",
                "medication_unverified": "زانیاریی دەرمان بە تەواوی پشتڕاست نەکرایەوە. تکایە لەگەڵ دەرمانساز یان پزیشک دڵنیایی بکەرەوە.",
                "no_medication": "هیچ دەرمانێکی ئێستا ڕاپۆرت نەکراوە.",
            },
            "bad": {
                "safe": "بێ ڕەزامەندیا دکتۆری چ دەرمانەکێ دەست پێ مەکە، مەگوهۆڕە و مەوەستینە.",
                "high": "ب زووترین دەم پشکنینەکا ڕووبەڕوو ژ لایێ دکتۆرێ پێستی وەرگرە. ئەڤ ئەنجامە تشخیص نینە.",
                "insufficient": "وێنە یان زانیاری بۆ پشکنینەکا باوەڕپێکری بەس نەبوون. وێنەیەکا ڕوونتر یان پشکنینەکا ڕووبەڕوو لەبەرچاو بگرە.",
                "follow_up": "نیشانێن بەردەوام، گوهۆڕی یان نیگەرانکەر دگەل دکتۆرێ پسپۆڕێ پێستی باس بکە.",
                "medication_verified": "زانیاریێن سەرەوە تەنێ پوختەیا لیبێلا دەرمانا سەرچاوەدری. ئەڤە دیار ناکەت کو دەرمان بۆ کێشەیا پێستێ تە گونجایە.",
                "medication_unverified": "زانیاریێن دەرمان ب تەماماهی نەهاتنە پشتڕاستکرن. ژێدڤە دگەل دەرمانساز یان دکتۆری دڵنیا ببە.",
                "no_medication": "چ دەرمانێن نوکە نەهاتیە ڕاپۆرتکرن.",
            },
            "ar": {
                "safe": "لا تبدأ أي دواء أو تغيّره أو توقفه دون موافقة طبيبك.",
                "high": "رتّب تقييمًا حضوريًا قريبًا لدى طبيب جلدية. نتيجة الفحص هذه ليست تشخيصًا.",
                "insufficient": "الصورة أو المعلومات غير كافية لفحص موثوق. فكّر في صورة أوضح أو تقييم حضوري.",
                "follow_up": "ناقش الأعراض الجلدية المستمرة أو المتغيرة أو المقلقة مع طبيب جلدية مؤهل.",
                "medication_verified": "المعلومات أعلاه تلخص النشرة الدوائية المشار إليها فقط. ولا تحدد ما إذا كان الدواء مناسبًا لحالة بشرتك.",
                "medication_unverified": "تعذر التحقق الكامل من معلومات الدواء. يرجى تأكيدها مع صيدلي أو طبيب.",
                "no_medication": "لم يُذكر استخدام دواء حالي.",
            },
        }[language]
        if medication is None:
            medication_explanation = localized["no_medication"]
        elif medication.verified:
            medication_explanation = localized["medication_verified"]
        else:
            medication_explanation = localized["medication_unverified"]
        if safety.concern_level in {"high", "prompt_in_person"}:
            recommendations = [localized["high"], localized["safe"]]
            follow_up = localized["high"]
            urgent = localized["high"]
            patient_summary = localized["high"]
            skin_analysis_context = localized["high"]
            concerning_observations = [localized["high"]]
        elif safety.concern_level == "insufficient":
            recommendations = [localized["insufficient"], localized["safe"]]
            follow_up = localized["insufficient"]
            urgent = guidance.urgent_care_guidance
            patient_summary = guidance.patient_summary
            skin_analysis_context = guidance.skin_analysis_context
            concerning_observations = guidance.concerning_observations
        else:
            recommendations = [localized["follow_up"], localized["safe"]]
            follow_up = localized["follow_up"]
            urgent = guidance.urgent_care_guidance
            patient_summary = guidance.patient_summary
            skin_analysis_context = guidance.skin_analysis_context
            concerning_observations = guidance.concerning_observations
        disclaimer = {
            "en": "SkinAI provides automated screening and educational information. It does not replace a qualified dermatologist, medical examination, or professional diagnosis.",
            "ku": "SkinAI پشکنینی خۆکار و زانیاریی فێرکاری پێشکەش دەکات. جێگرەوەی پزیشکی پێستی پسپۆڕ، پشکنینی پزیشکی یان تشخیصی پیشەیی نییە.",
            "bad": "SkinAI پشکنینا خۆکار و زانیاریێن فێرکاری پێشکێش دکەت. نە جهگرتی دکتۆرێ پێستی پسپۆڕ، پشکنینا پزیشکی و نە تشخیصا پیشەییە.",
            "ar": "يقدم SkinAI فحصًا آليًا ومعلومات تثقيفية. ولا يحل محل طبيب جلدية مؤهل أو الفحص الطبي أو التشخيص المهني.",
        }[language]
        return guidance.model_copy(update={
            "patient_summary": patient_summary,
            "skin_analysis_context": skin_analysis_context,
            "concerning_observations": concerning_observations,
            "medication_explanation": medication_explanation,
            "recommendations": recommendations,
            "clinician_follow_up": follow_up,
            "urgent_care_guidance": urgent,
            "disclaimer": disclaimer,
        })

    @staticmethod
    def _sources(medication: Any) -> list[str]:
        sources = ["Ivy AI skin-condition screening"]
        if medication is not None:
            sources.append("Patient-entered medication details")
            if medication.source:
                sources.append(medication.source)
        sources.append("Deterministic assessment summary")
        return sources

    def _persist(
        self,
        *,
        uid: str,
        response: AssessmentResponse,
        patient: PatientInput,
        skin_image: tuple[bytes, bytes, str],
        medication_image: tuple[bytes, str] | None,
        reports: list[tuple[bytes, str, str]],
    ) -> AssessmentResponse:
        from .encrypted_storage import _key

        _key()
        stored_ids: list[str] = []
        file_refs: list[dict[str, str]] = []
        uploads: list[tuple[bytes, str, str]] = [
            (skin_image[0], skin_image[2], "skin_image")
        ]
        if medication_image is not None:
            uploads.append(
                (medication_image[0], medication_image[1], "medication_image")
            )
        uploads.extend(
            (content, mime_type, f"medical_report_{index}")
            for index, (content, mime_type, _) in enumerate(reports)
        )
        try:
            for content, mime_type, kind in uploads:
                file_id = str(uuid4())
                storage_id = store_file(
                    content,
                    uid=uid,
                    assessment_id=response.id,
                    file_id=file_id,
                )
                stored_ids.append(storage_id)
                file_refs.append({
                    "id": file_id,
                    "storage_id": storage_id,
                    "mime_type": mime_type,
                    "kind": kind,
                })
            full_record = {
                "patient": patient.model_dump(mode="json"),
                "assessment": response.model_copy(update={
                    "original_files": [
                        {
                            "id": item["id"],
                            "mime_type": item["mime_type"],
                            "kind": item["kind"],
                        }
                        for item in file_refs
                        if item["kind"] != "skin_image"
                    ]
                }).model_dump(mode="json"),
                "file_refs": file_refs,
                "report_names": [name for _, _, name in reports],
            }
            encrypted_payload = encrypt(
                json.dumps(
                    full_record,
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode(),
                associated_data=f"{uid}:{response.id}:record".encode(),
            )
            if len(encrypted_payload) > 900_000:
                raise ValueError("Medical assessment exceeds the record limit.")
            db = _database()
            reference = (
                db.collection("users")
                .document(uid)
                .collection("medical_assessments")
                .document(response.id)
            )
            audit_reference = (
                db.collection("users")
                .document(uid)
                .collection("medical_audit")
                .document()
            )
            batch = db.batch()
            batch.set(reference, {
                "created_at": response.created_at,
                "encrypted_payload": encrypted_payload,
                "external_processing_consent": True,
                "storage_consent": True,
                "schema_version": 1,
            })
            batch.set(audit_reference, {
                "action": "create_ai_assessment",
                "target_type": "medical_assessment",
                "target_id": response.id,
                "created_at": response.created_at,
                "external_processing_consent": True,
                "storage_consent": True,
                "file_count": len(file_refs),
            })
            batch.commit()
            return response.model_copy(update={
                "original_files": [
                    StoredAssessmentFile.model_validate({
                        "id": item["id"],
                        "mime_type": item["mime_type"],
                        "kind": item["kind"],
                    })
                    for item in file_refs
                    if item["kind"] != "skin_image"
                ]
            })
        except HTTPException:
            self._cleanup_files(stored_ids)
            raise
        except (GoogleAPIError, OSError, RuntimeError, ValueError) as error:
            self._cleanup_files(stored_ids)
            _logger.error(
                "Medical assessment persistence failed (%s).",
                type(error).__name__,
            )
            raise HTTPException(
                status_code=503,
                detail="The encrypted medical assessment could not be saved.",
            ) from error

    @staticmethod
    def _cleanup_files(storage_ids: list[str]) -> None:
        for storage_id in storage_ids:
            try:
                delete_file(storage_id)
            except (OSError, ValueError) as error:
                _logger.error(
                    "Medical assessment file cleanup failed (%s).",
                    type(error).__name__,
                )
