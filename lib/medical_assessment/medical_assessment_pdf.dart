import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:skin_ai/medical_assessment/medical_assessment_api.dart';

Future<Uint8List> buildMedicalAssessmentPdf({
  required MedicalAssessmentResult assessment,
  required String Function(String key) localize,
  required bool isRtl,
}) async {
  final document = pw.Document();
  final generatedAt = DateTime.now().toLocal().toIso8601String();

  pw.Widget text(String value, {double size = 10, bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      lineSpacing: 3,
    );
    final content = pw.Text(value, style: style, textAlign: pw.TextAlign.left);
    return isRtl
        ? pw.Directionality(textDirection: pw.TextDirection.rtl, child: content)
        : content;
  }

  List<pw.Widget> section(String title, List<String> values) => [
        pw.SizedBox(height: 16),
        text(title, size: 15, bold: true),
        pw.Divider(),
        for (final value in values.where((value) => value.trim().isNotEmpty))
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: text(value),
          ),
      ];

  final patient = assessment.patient;
  final skinResult =
      assessment.skinAnalysis['result']?.toString() ?? localize('notProvided');
  final skinSummary =
      assessment.skinAnalysis['summary']?.toString() ?? localize('notProvided');
  final rawConfidence = assessment.skinAnalysis['confidence'];
  final confidence = rawConfidence is num
      ? rawConfidence <= 1
          ? rawConfidence * 100
          : rawConfidence
      : null;
  final medication = assessment.medication;
  final concernLabelKey = switch (assessment.safety.concernLevel) {
    'low' => 'concernLow',
    'moderate' => 'concernModerate',
    'high' => 'concernHigh',
    'prompt_in_person' => 'concernPrompt',
    'insufficient' => 'concernInsufficient',
    _ => 'concernModerate',
  };
  final medicationLines = medication == null
      ? [localize('noMedicationReported')]
      : [
          localize('medicationSafetyWarning'),
          localize('medicationSuitabilityNotice'),
          '${localize('medicationName')}: ${medication.name ?? localize('notProvided')}',
          '${localize('activeIngredients')}: ${medication.ingredients.isEmpty ? localize('notProvided') : medication.ingredients.join(', ')}',
          '${localize('medicationStrength')}: ${medication.strength ?? localize('notProvided')}',
          '${localize('medicationForm')}: ${medication.form ?? localize('notProvided')}',
          '${localize('manufacturer')}: ${medication.manufacturer ?? localize('notProvided')}',
          '${localize('expirationDate')}: ${medication.expirationDate ?? localize('notProvided')}',
          '${localize('potentialBenefits')}: ${medication.intendedUses.isEmpty ? localize('notProvided') : medication.intendedUses.join(', ')}',
          '${localize('howItWorks')}: ${medication.howItWorks ?? localize('notProvided')}',
          '${localize('verificationStatus')}: ${medication.verified ? localize('verified') : localize('unverified')}',
          medication.verified
              ? medication.verificationNote
              : localize('medicationNotVerified'),
          if (medication.source != null)
            '${localize('referenceSource')}: ${medication.source}',
          ...medication.contraindications.map(
            (value) => '${localize('contraindications')}: $value',
          ),
          ...medication.commonSideEffects.map(
            (value) => '${localize('commonSideEffects')}: $value',
          ),
          ...medication.seriousWarningSigns.map(
            (value) => '${localize('seriousWarnings')}: $value',
          ),
          ...medication.interactions.map(
            (value) => '${localize('possibleInteractions')}: $value',
          ),
          ...medication.precautions.map(
            (value) => '${localize('precautions')}: $value',
          ),
          ...medication.uncertainty,
        ];
  final medicationHistory = assessment.medicationHistory;
  final medicationHistoryLines = medicationHistory == null
      ? <String>[]
      : [
          '${localize('medicationDuration')}: ${medicationHistory['duration'] ?? localize('notProvided')}',
          '${localize('prescribedQuestion')}: ${medicationHistory['prescribed_by_doctor'] ?? localize('notProvided')}',
          '${localize('effectQuestion')}: ${medicationHistory['reported_effect'] ?? localize('notProvided')}',
        ];
  final reportLines = <String>[
    if (assessment.examinations.isEmpty) localize('noReportsProvided'),
    for (var index = 0; index < assessment.examinations.length; index++) ...[
      '${localize('reportNumber')} ${index + 1}',
      '${localize('recordSource')}: ${localize(assessment.examinations[index].source == 'patient_reported' ? 'sourcePatientReported' : 'sourceUnavailable')}',
      if (assessment.examinations[index].examinationDate != null)
        '${localize('examinationDate')}: ${assessment.examinations[index].examinationDate}',
      ...assessment.examinations[index].doctorFindings.map(
        (value) => '${localize('doctorFindings')}: $value',
      ),
      ...assessment.examinations[index].documentedDiagnosis.map(
        (value) => '${localize('documentedDiagnosis')}: $value',
      ),
      ...assessment.examinations[index].tests.map(
        (test) => '${test.testName}: ${test.result}'
            '${test.date == null ? '' : ' (${test.date})'}'
            '${test.referenceRange == null ? '' : ' — ${localize('referenceRange')}: ${test.referenceRange}'}'
            '${test.explicitlyFlaggedAbnormal == true ? ' — ${localize('markedAbnormal')}' : ''}',
      ),
      ...assessment.examinations[index].conclusions,
      ...assessment.examinations[index].recommendedTreatments.map(
        (value) => '${localize('recommendedTreatments')}: $value',
      ),
      ...assessment.examinations[index].medicationNames.map(
        (value) => '${localize('medicationNames')}: $value',
      ),
      ...assessment.examinations[index].followUpInstructions.map(
        (value) => '${localize('followUpInstructions')}: $value',
      ),
      ...assessment.examinations[index].otherReportText,
      ...assessment.examinations[index].uncertainty,
      ...assessment.examinations[index].missingOrUnreadable,
    ],
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        text(localize('assessmentReportTitle'), size: 22, bold: true),
        pw.SizedBox(height: 8),
        text('${localize('reportDate')}: $generatedAt'),
        ...section(localize('patientInformation'), [
          '${localize('patientAge')}: ${patient.age}',
          '${localize('patientSex')}: ${patient.sex}',
          '${localize('pregnancy')}: ${patient.pregnancyOrBreastfeeding}',
          '${localize('symptomsDuration')}: ${patient.symptomsDuration}',
          '${localize('symptomsDetails')}: ${patient.symptomsDetails}',
          '${localize('bodyLocation')}: ${patient.bodyLocation}',
          '${localize('allergies')}: ${patient.allergies}',
          '${localize('medicalHistory')}: ${patient.medicalHistory}',
        ]),
        ...section(localize('skinImageAnalysis'), [
          '${localize('possiblePattern')}: $skinResult',
          if (confidence != null)
            '${localize('modelConfidence')}: ${confidence.toStringAsFixed(confidence == confidence.roundToDouble() ? 0 : 1)}%',
          '${localize('concernLevel')}: ${localize(concernLabelKey)}',
          skinSummary,
          localize('screeningLimitations'),
        ]),
        ...section(localize('medicationAnalysis'), medicationLines),
        ...section(localize('medicationHistory'), medicationHistoryLines),
        ...section(localize('medicationInformationNote'), [
          assessment.guidance.medicationExplanation,
        ]),
        ...section(localize('examinationRecordDetails'), reportLines),
        ...section(localize('assessmentSummary'), [
          assessment.guidance.examinationExplanation,
        ]),
        ...section(localize('reassuringFindings'), [
          ...assessment.guidance.reassuringObservations,
          if (assessment.guidance.reassuringObservations.isEmpty)
            localize('notProvided'),
        ]),
        ...section(localize('concerningFindings'), [
          ...assessment.guidance.concerningObservations,
          if (assessment.guidance.concerningObservations.isEmpty)
            localize('notProvided'),
        ]),
        ...section(localize('missingInformation'), [
          ...assessment.guidance.missingInformation,
          if (assessment.guidance.missingInformation.isEmpty)
            localize('noneReported'),
        ]),
        ...section(localize('personalizedRecommendations'), [
          ...assessment.guidance.recommendations,
          assessment.guidance.clinicianFollowUp,
          assessment.guidance.urgentCareGuidance,
          if (assessment.safety.referralRequired)
            localize('urgentDermatologistReferral'),
        ]),
        ...section(localize('medicalDisclaimer'), [
          assessment.guidance.disclaimer,
        ]),
        ...section(localize('reportSources'), assessment.sources),
      ],
    ),
  );
  return document.save();
}

Future<void> shareMedicalAssessmentPdf(
  Uint8List bytes,
  String filename,
) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
