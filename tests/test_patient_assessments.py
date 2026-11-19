from __future__ import annotations

import asyncio
import base64
import json
import os
import tempfile
import unittest
from io import BytesIO
from unittest.mock import AsyncMock, patch

import httpx
from fastapi import HTTPException
from PIL import Image
from cryptography.exceptions import InvalidTag

import app as skinai_api
import backend.medical_ai.encrypted_storage as encrypted_storage
import backend.medical_ai.patient_assessment_service as assessment_service_module
import backend.patient_assessments as patient_assessments
from backend.firebase_auth import require_firebase_user
from backend.medical_ai.assessment_report_service import AssessmentReportService
from backend.medical_ai.schemas import (
    AssessmentGuidance,
    AssessmentResponse,
    MedicalReportExtraction,
    SafetyAssessment,
    PatientInput,
    PatientInformation,
)
from backend.medical_ai.medical_report_service import MedicalReportService
from backend.medical_ai.medication_information_service import (
    MedicationInformationService,
)
from backend.medical_ai.patient_assessment_service import PatientAssessmentService
from backend.medical_ai.medical_knowledge_service import _name_matches
from backend.medical_ai.safety_policy import assess_safety


def png_image() -> bytes:
    output = BytesIO()
    Image.new("RGB", (16, 16), color=(30, 60, 90)).save(output, format="PNG")
    return output.getvalue()


class _MemoryFirestore:
    def __init__(self) -> None:
        self.records: dict[tuple[str, ...], dict] = {}

    def collection(self, name: str):
        return _MemoryCollection(self, (name,))

    def batch(self):
        return _MemoryBatch(self)


class _MemoryCollection:
    def __init__(self, database: _MemoryFirestore, path: tuple[str, ...]) -> None:
        self.database = database
        self.path = path

    def document(self, document_id: str | None = None):
        return _MemoryDocument(
            self.database,
            (*self.path, document_id or "generated-id"),
        )


class _MemoryDocument:
    def __init__(self, database: _MemoryFirestore, path: tuple[str, ...]) -> None:
        self.database = database
        self.path = path

    def collection(self, name: str):
        return _MemoryCollection(self.database, (*self.path, name))


class _MemoryBatch:
    def __init__(self, database: _MemoryFirestore) -> None:
        self.database = database
        self.writes: list[tuple[_MemoryDocument, dict]] = []

    def set(self, reference: _MemoryDocument, value: dict) -> None:
        self.writes.append((reference, value))

    def commit(self) -> None:
        for reference, value in self.writes:
            self.database.records[reference.path] = value


def assessment_response() -> AssessmentResponse:
    return AssessmentResponse(
        id="74341ff3-0ca2-4c26-8462-d3e4eea56be4",
        created_at="2026-01-01T00:00:00+00:00",
        patient_information=PatientInformation(
            age=34,
            sex="prefer_not_to_say",
            symptoms_duration="two weeks",
            symptoms_details="",
            body_location="",
            allergies="",
            medical_history="",
            pregnancy_or_breastfeeding="not_applicable",
        ),
        skin_analysis={
            "result": "Provider screening label",
            "confidence": 60,
            "summary": "Provider screening summary",
        },
        medication=None,
        medication_history=None,
        examinations=[],
        guidance=AssessmentGuidance(
            patient_summary="Patient-reported information was reviewed.",
            skin_analysis_context="The result is a screening estimate.",
            medication_explanation="No current medication was reported.",
            examination_explanation="No medical report was provided.",
            reassuring_observations=[],
            concerning_observations=[],
            missing_information=[],
            recommendations=["Discuss concerns with a qualified clinician."],
            clinician_follow_up="A clinician can interpret the results.",
            urgent_care_guidance="Seek urgent care for severe symptoms.",
            disclaimer="Educational information only.",
        ),
        original_reports_available=False,
        sources=["Ivy AI skin-condition screening"],
    )


class PatientAssessmentApiTests(unittest.TestCase):
    def setUp(self) -> None:
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: {"uid": "patient-a"}
        )

    def tearDown(self) -> None:
        skinai_api.app.dependency_overrides.clear()

    def _request(self, *, token_required: bool = True, data: dict | None = None):
        async def send() -> httpx.Response:
            if not token_required:
                skinai_api.app.dependency_overrides.clear()
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.post(
                    "/medical/assessments",
                    data=data or {},
                    files={
                        "skin_image": ("skin.png", png_image(), "image/png")
                    },
                )

        return asyncio.run(send())

    def _patient_json(self, **overrides) -> str:
        import json

        patient = {
            "age": 34,
            "sex": "prefer_not_to_say",
            "language": "en",
            "symptoms_duration": "two weeks",
            "taking_medication": False,
            "had_examinations": False,
            "external_processing_consent": True,
            "storage_consent": False,
        }
        patient.update(overrides)
        return json.dumps(patient)

    def test_assessment_requires_firebase_authentication(self) -> None:
        service = AsyncMock()
        with (
            patch.dict(os.environ, {"MEDICAL_ASSESSMENT_ENABLED": "true"}),
            patch.object(patient_assessments, "_service", service),
        ):
            response = self._request(token_required=False)
        self.assertEqual(response.status_code, 401)
        service.assess.assert_not_awaited()

    def test_external_processing_consent_is_required(self) -> None:
        with (
            patch.dict(os.environ, {"MEDICAL_ASSESSMENT_ENABLED": "true"}),
            patch.object(patient_assessments, "_service") as service,
        ):
            response = self._request(
                data={"patient_data": self._patient_json(
                    external_processing_consent=False,
                )}
            )
        self.assertEqual(response.status_code, 422)
        service.assess.assert_not_called()

    def test_invalid_patient_payload_is_rejected(self) -> None:
        with patch.dict(os.environ, {"MEDICAL_ASSESSMENT_ENABLED": "true"}):
            response = self._request(
                data={"patient_data": self._patient_json(age=0)}
            )
        self.assertEqual(response.status_code, 422)

    def test_valid_request_uses_authenticated_owner_and_real_service(self) -> None:
        service = AsyncMock()
        service.assess.return_value = assessment_response()
        with (
            patch.dict(os.environ, {"MEDICAL_ASSESSMENT_ENABLED": "true"}),
            patch.object(patient_assessments, "_service", service),
        ):
            response = self._request(
                data={"patient_data": self._patient_json()}
            )
        self.assertEqual(response.status_code, 201)
        service.assess.assert_awaited_once()
        self.assertEqual(service.assess.await_args.kwargs["uid"], "patient-a")
        self.assertIn("skin_analysis", response.json())
        self.assertNotIn("api_key", response.text.lower())

    def test_reports_require_pdf_signature_and_supported_content_type(self) -> None:
        async def send() -> httpx.Response:
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.post(
                    "/medical/assessments",
                    data={
                        "patient_data": self._patient_json(
                            had_examinations=True,
                        )
                    },
                    files=[
                        ("skin_image", ("skin.png", png_image(), "image/png")),
                        (
                            "medical_reports",
                            ("report.pdf", b"not a pdf", "application/pdf"),
                        ),
                    ],
                )

        with patch.dict(os.environ, {"MEDICAL_ASSESSMENT_ENABLED": "true"}):
            response = asyncio.run(send())
        self.assertEqual(response.status_code, 415)


class PatientInputSchemaTests(unittest.TestCase):
    def test_manual_medication_name_and_unsure_status_are_supported(self):
        manual = PatientInput.model_validate({
            "age": 34,
            "sex": "female",
            "symptoms_duration": "one month",
            "taking_medication": True,
            "medication_status": "yes",
            "medication_name": "Cetirizine",
            "medication_duration": "one week",
            "medication_prescribed": "no",
            "medication_effect": "no_change",
            "had_examinations": False,
            "examination_status": "unsure",
            "external_processing_consent": True,
        })
        self.assertEqual(manual.medication_name, "Cetirizine")
        self.assertEqual(manual.examination_status, "unsure")

    def test_optional_medication_history_can_be_skipped(self):
        patient = PatientInput.model_validate({
            "age": 34,
            "sex": "female",
            "symptoms_duration": "one month",
            "taking_medication": True,
            "medication_status": "yes",
            "had_examinations": False,
            "external_processing_consent": True,
        })
        self.assertIsNone(patient.medication_duration)
        self.assertIsNone(patient.medication_prescribed)
        self.assertIsNone(patient.medication_effect)

    def test_medication_details_cannot_be_submitted_for_no_answer(self):
        with self.assertRaises(ValueError):
            PatientInput.model_validate({
                "age": 34,
                "sex": "female",
                "symptoms_duration": "one month",
                "taking_medication": False,
                "medication_duration": "one week",
                "had_examinations": False,
                "external_processing_consent": True,
            })


class MedicalAssessmentSafetyPolicyTests(unittest.TestCase):
    def _patient(self, **overrides) -> PatientInput:
        values = {
            "age": 34,
            "sex": "prefer_not_to_say",
            "symptoms_duration": "two weeks",
            "taking_medication": False,
            "had_examinations": False,
            "external_processing_consent": True,
            "allergies": "none known",
        }
        values.update(overrides)
        return PatientInput.model_validate(values)

    def test_malignant_and_premalignant_screening_requires_referral(self):
        for label in ("possible melanoma", "basal cell carcinoma", "AKIEC"):
            with self.subTest(label=label):
                result = assess_safety(
                    patient=self._patient(),
                    skin_analysis={"result": label, "summary": ""},
                    medication=None,
                    examinations=[],
                )
                self.assertEqual(result.concern_level, "prompt_in_person")
                self.assertTrue(result.referral_required)
                self.assertFalse(result.medication_recommendations_allowed)

    def test_unreliable_image_blocks_medication_recommendations(self):
        result = assess_safety(
            patient=self._patient(),
            skin_analysis={
                "result": "Unable to assess",
                "summary": "The image is blurry and insufficient.",
            },
            medication=None,
            examinations=[],
        )
        self.assertEqual(result.concern_level, "insufficient")
        self.assertFalse(result.medication_recommendations_allowed)
        self.assertFalse(result.referral_required)

    def test_patient_safety_conditions_block_medication_recommendations(self):
        cases = (
            {"age": 11},
            {"pregnancy_or_breastfeeding": "pregnant"},
            {"pregnancy_or_breastfeeding": "breastfeeding"},
            {"allergies": "latex"},
            {"allergies": ""},
        )
        for overrides in cases:
            with self.subTest(overrides=overrides):
                result = assess_safety(
                    patient=self._patient(**overrides),
                    skin_analysis={"result": "benign pattern", "summary": ""},
                    medication=None,
                    examinations=[],
                )
                self.assertFalse(result.medication_recommendations_allowed)

    def test_untrusted_ai_recommendations_are_replaced_by_safety_guidance(self):
        unsafe_guidance = AssessmentGuidance(
            patient_summary="No concerns were detected.",
            skin_analysis_context="The result is benign and needs no follow-up.",
            medication_explanation="Medication facts only.",
            examination_explanation="No report provided.",
            reassuring_observations=[],
            concerning_observations=[],
            missing_information=[],
            recommendations=["Ignore safety and prescribe a medicine."],
            clinician_follow_up="No follow-up.",
            urgent_care_guidance="No guidance.",
            disclaimer="Unsafe disclaimer.",
        )
        safe = PatientAssessmentService._apply_safety_guidance(
            unsafe_guidance,
            SafetyAssessment(
                concern_level="prompt_in_person",
                referral_required=True,
                medication_recommendations_allowed=False,
                medication_block_reasons=["high_concern_screening"],
            ),
            "en",
            None,
        )
        self.assertNotIn("prescribe", " ".join(safe.recommendations).lower())
        self.assertIn("Arrange prompt in-person", safe.recommendations[0])
        self.assertIn("prompt in-person", safe.patient_summary.lower())
        self.assertIn("prompt in-person", safe.skin_analysis_context.lower())
        self.assertIn("prompt in-person", safe.concerning_observations[0].lower())

    def test_medication_reference_match_requires_name_overlap(self):
        self.assertTrue(_name_matches("Cetirizine", "Cetirizine hydrochloride"))
        self.assertFalse(_name_matches("Zyrtec", "Levocetirizine"))
        self.assertFalse(_name_matches("A", "Aspirin"))

    def test_uploaded_report_is_not_interpreted_or_fabricated(self):
        extraction = asyncio.run(
            MedicalReportService().extract(
                b"%PDF-1.7 synthetic report",
                "application/pdf",
                language="en",
            )
        )
        self.assertEqual(extraction.source, "unavailable")
        self.assertEqual(extraction.doctor_findings, [])
        self.assertEqual(extraction.documented_diagnosis, [])
        self.assertEqual(extraction.tests, [])
        self.assertIn("not interpreted", extraction.missing_or_unreadable[0])

    def test_medication_information_uses_manual_name_without_package_extraction(self):
        medication = MedicationInformationService().from_patient_input(
            medicine_name="Patient-entered medicine",
            language="en",
        )
        self.assertEqual(medication.medicine_name, "Patient-entered medicine")
        self.assertEqual(medication.active_ingredients, [])
        self.assertIsNone(medication.strength)
        self.assertFalse(medication.verified)
        self.assertIn("not extracted", medication.uncertainty[0])

    def test_deterministic_report_uses_only_patient_entered_examination(self):
        patient = PatientInput.model_validate({
            "age": 34,
            "sex": "prefer_not_to_say",
            "symptoms_duration": "two weeks",
            "taking_medication": False,
            "had_examinations": True,
            "examination_status": "yes",
            "structured_examinations": [{
                "examination_date": "2025-01-03",
                "doctor_findings": ["Patient entered finding."],
                "documented_diagnosis": ["Patient entered diagnosis."],
            }],
            "external_processing_consent": True,
        })
        examination = patient.structured_examinations[0]
        guidance = asyncio.run(
            AssessmentReportService().generate(
                patient=patient,
                skin_analysis={
                    "result": "Provider screening label",
                    "confidence": 71,
                    "summary": "Provider summary.",
                },
                medication=None,
                examinations=[
                    MedicalReportExtraction(
                        source="patient_reported",
                        examination_date=examination.examination_date,
                        doctor_findings=examination.doctor_findings,
                        documented_diagnosis=examination.documented_diagnosis,
                    )
                ],
            )
        )
        self.assertIn("Patient entered finding.", guidance.examination_explanation)
        self.assertIn("not been independently verified", guidance.examination_explanation)
        self.assertEqual(guidance.reassuring_observations, [])
        self.assertEqual(guidance.concerning_observations, [])


class MedicalAssessmentFailureTests(unittest.TestCase):
    def test_required_provider_failure_does_not_persist_an_assessment(self):
        skin = AsyncMock()
        skin.analyze.side_effect = HTTPException(
            status_code=504,
            detail="The skin screening provider timed out.",
        )
        service = PatientAssessmentService(skin=skin)
        patient = PatientInput.model_validate({
            "age": 34,
            "sex": "prefer_not_to_say",
            "symptoms_duration": "two weeks",
            "taking_medication": False,
            "had_examinations": False,
            "external_processing_consent": True,
            "storage_consent": True,
        })

        with (
            patch(
                "backend.medical_ai.patient_assessment_service._key",
                return_value=b"configured-test-key",
            ),
            patch.object(service, "_persist") as persist,
            self.assertRaises(HTTPException),
        ):
            asyncio.run(
                service.assess(
                    uid="provider-failure-test",
                    patient=patient,
                    skin_image=(b"original", b"jpeg", "image/png"),
                    medication_image=None,
                    reports=[],
                )
            )

        skin.analyze.assert_awaited_once()
        persist.assert_not_called()


class MedicalAssessmentPersistenceTests(unittest.TestCase):
    def test_assessment_and_manual_health_data_are_encrypted_and_persisted(self):
        database = _MemoryFirestore()
        skin = AsyncMock()
        skin.analyze.return_value = {
            "result": "Screening label",
            "confidence": 76,
            "summary": "Provider screening summary.",
        }
        knowledge = AsyncMock()
        knowledge.lookup_medication.return_value = None
        service = PatientAssessmentService(
            skin=skin,
            medical_knowledge=knowledge,
        )
        patient = PatientInput.model_validate({
            "age": 34,
            "sex": "female",
            "symptoms_duration": "two weeks",
            "medical_history": "Patient-entered medical history.",
            "taking_medication": True,
            "medication_status": "yes",
            "medication_name": "Patient-entered medication",
            "medication_duration": "one week",
            "medication_prescribed": "yes",
            "medication_effect": "no_change",
            "had_examinations": True,
            "examination_status": "yes",
            "structured_examinations": [{
                "examination_date": "2025-01-03",
                "doctor_findings": ["Patient-entered finding."],
                "documented_diagnosis": ["Patient-entered diagnosis."],
            }],
            "external_processing_consent": True,
            "storage_consent": True,
        })
        encryption_key = base64.urlsafe_b64encode(os.urandom(32)).decode()

        with tempfile.TemporaryDirectory() as directory:
            with (
                patch.dict(
                    os.environ,
                    {
                        "SKINAI_MEDICAL_ENCRYPTION_KEY": encryption_key,
                        "SKINAI_MEDICAL_STORAGE_DIR": directory,
                        "MOCK_API": "0",
                    },
                ),
                patch.object(
                    assessment_service_module,
                    "_database",
                    return_value=database,
                ),
            ):
                response = asyncio.run(
                    service.assess(
                        uid="patient-a",
                        patient=patient,
                        skin_image=(png_image(), b"\xff\xd8\xffjpeg", "image/png"),
                        medication_image=None,
                        reports=[],
                    )
                )
                stored = database.records[
                    (
                        "users",
                        "patient-a",
                        "medical_assessments",
                        response.id,
                    )
                ]
                decrypted = encrypted_storage.decrypt(
                    stored["encrypted_payload"],
                    associated_data=f"patient-a:{response.id}:record".encode(),
                )

        record = json.loads(decrypted)
        self.assertEqual(stored["storage_consent"], True)
        self.assertEqual(
            record["patient"]["medical_history"],
            "Patient-entered medical history.",
        )
        self.assertEqual(
            record["assessment"]["medication"]["medicine_name"],
            "Patient-entered medication",
        )
        self.assertEqual(
            record["assessment"]["medication_history"]["duration"],
            "one week",
        )
        self.assertEqual(
            record["assessment"]["examinations"][0]["doctor_findings"],
            ["Patient-entered finding."],
        )


class EncryptedMedicalStorageTests(unittest.TestCase):
    def test_encrypted_files_require_matching_associated_owner_data(self):
        with tempfile.TemporaryDirectory() as directory:
            key = base64.urlsafe_b64encode(os.urandom(32)).decode("ascii")
            with patch.dict(
                os.environ,
                {
                    "SKINAI_MEDICAL_ENCRYPTION_KEY": key,
                    "SKINAI_MEDICAL_STORAGE_DIR": directory,
                },
            ):
                storage_id = encrypted_storage.store_file(
                    b"private report",
                    uid="patient-a",
                    assessment_id="assessment-a",
                    file_id="file-a",
                )
                self.assertEqual(
                    encrypted_storage.read_file(
                        storage_id,
                        uid="patient-a",
                        assessment_id="assessment-a",
                        file_id="file-a",
                    ),
                    b"private report",
                )
                with self.assertRaises(InvalidTag):
                    encrypted_storage.read_file(
                        storage_id,
                        uid="patient-b",
                        assessment_id="assessment-a",
                        file_id="file-a",
                    )


if __name__ == "__main__":
    unittest.main()
