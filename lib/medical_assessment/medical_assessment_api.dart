import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:skin_ai/multipart_upload.dart';

typedef AssessmentTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});

class MedicalAssessmentApiException implements Exception {
  const MedicalAssessmentApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MedicalAssessmentUpload {
  const MedicalAssessmentUpload({
    required this.patientData,
    required this.skinImage,
    required this.skinFilename,
    this.medicationImage,
    this.medicationFilename,
    this.reports = const [],
  });

  final Map<String, Object?> patientData;
  final Uint8List skinImage;
  final String skinFilename;
  final Uint8List? medicationImage;
  final String? medicationFilename;
  final List<AssessmentFileUpload> reports;
}

class AssessmentFileUpload {
  const AssessmentFileUpload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class PatientInformation {
  const PatientInformation({
    required this.age,
    required this.sex,
    required this.symptomsDuration,
    required this.symptomsDetails,
    required this.bodyLocation,
    required this.allergies,
    required this.medicalHistory,
    required this.pregnancyOrBreastfeeding,
  });

  final int age;
  final String sex;
  final String symptomsDuration;
  final String symptomsDetails;
  final String bodyLocation;
  final String allergies;
  final String medicalHistory;
  final String pregnancyOrBreastfeeding;

  factory PatientInformation.fromJson(Map<String, dynamic> json) {
    final age = json['age'];
    if (age is! int) {
      throw const MedicalAssessmentApiException(
        'The assessment service returned invalid patient details.',
      );
    }
    return PatientInformation(
      age: age,
      sex: _requiredString(json, 'sex'),
      symptomsDuration: _requiredString(json, 'symptoms_duration'),
      symptomsDetails: _stringOrEmpty(json['symptoms_details']),
      bodyLocation: _stringOrEmpty(json['body_location']),
      allergies: _stringOrEmpty(json['allergies']),
      medicalHistory: _stringOrEmpty(json['medical_history']),
      pregnancyOrBreastfeeding:
          _requiredString(json, 'pregnancy_or_breastfeeding'),
    );
  }
}

class MedicationAssessment {
  const MedicationAssessment({
    required this.name,
    required this.ingredients,
    required this.strength,
    required this.form,
    required this.manufacturer,
    required this.expirationDate,
    required this.visibleInstructions,
    required this.confidence,
    required this.uncertainty,
    required this.category,
    required this.intendedUses,
    required this.howItWorks,
    required this.commonSideEffects,
    required this.seriousWarningSigns,
    required this.contraindications,
    required this.interactions,
    required this.precautions,
    required this.storageInstructions,
    required this.verified,
    required this.source,
    required this.sourceDate,
    required this.verificationNote,
  });

  final String? name;
  final List<String> ingredients;
  final String? strength;
  final String? form;
  final String? manufacturer;
  final String? expirationDate;
  final String? visibleInstructions;
  final double confidence;
  final List<String> uncertainty;
  final String? category;
  final List<String> intendedUses;
  final String? howItWorks;
  final List<String> commonSideEffects;
  final List<String> seriousWarningSigns;
  final List<String> contraindications;
  final List<String> interactions;
  final List<String> precautions;
  final List<String> storageInstructions;
  final bool verified;
  final String? source;
  final String? sourceDate;
  final String verificationNote;

  factory MedicationAssessment.fromJson(Map<String, dynamic> json) {
    final confidence = json['confidence'];
    if (confidence is! num || !confidence.isFinite) {
      throw const MedicalAssessmentApiException(
        'The assessment service returned invalid medication details.',
      );
    }
    return MedicationAssessment(
      name: _optionalString(json['medicine_name']),
      ingredients: _stringList(json['active_ingredients']),
      strength: _optionalString(json['strength']),
      form: _optionalString(json['form']),
      manufacturer: _optionalString(json['manufacturer']),
      expirationDate: _optionalString(json['expiration_date']),
      visibleInstructions: _optionalString(json['visible_instructions']),
      confidence: confidence.toDouble(),
      uncertainty: _stringList(json['uncertainty']),
      category: _optionalString(json['category']),
      intendedUses: _stringList(json['intended_uses']),
      howItWorks: _optionalString(json['how_it_works']),
      commonSideEffects: _stringList(json['common_side_effects']),
      seriousWarningSigns: _stringList(json['serious_warning_signs']),
      contraindications: _stringList(json['contraindications']),
      interactions: _stringList(json['interactions']),
      precautions: _stringList(json['precautions']),
      storageInstructions: _stringList(json['storage_instructions']),
      verified: json['verified'] == true,
      source: _optionalString(json['source']),
      sourceDate: _optionalString(json['source_date']),
      verificationNote: _stringOrEmpty(json['verification_note']),
    );
  }
}

class MedicalTestFinding {
  const MedicalTestFinding({
    required this.testName,
    required this.date,
    required this.result,
    required this.referenceRange,
    required this.explicitlyFlaggedAbnormal,
  });

  final String testName;
  final String? date;
  final String result;
  final String? referenceRange;
  final bool? explicitlyFlaggedAbnormal;

  factory MedicalTestFinding.fromJson(Map<String, dynamic> json) =>
      MedicalTestFinding(
        testName: _requiredString(json, 'test_name'),
        date: _optionalString(json['date']),
        result: _requiredString(json, 'result'),
        referenceRange: _optionalString(json['reference_range']),
        explicitlyFlaggedAbnormal: json['explicitly_flagged_abnormal'] as bool?,
      );
}

class MedicalReportInterpretation {
  const MedicalReportInterpretation({
    required this.source,
    required this.examinationDate,
    required this.doctorFindings,
    required this.documentedDiagnosis,
    required this.tests,
    required this.conclusions,
    required this.recommendedTreatments,
    required this.medicationNames,
    required this.followUpInstructions,
    required this.otherReportText,
    required this.missingOrUnreadable,
    required this.uncertainty,
  });

  final String source;
  final String? examinationDate;
  final List<String> doctorFindings;
  final List<String> documentedDiagnosis;
  final List<MedicalTestFinding> tests;
  final List<String> conclusions;
  final List<String> recommendedTreatments;
  final List<String> medicationNames;
  final List<String> followUpInstructions;
  final List<String> otherReportText;
  final List<String> missingOrUnreadable;
  final List<String> uncertainty;

  factory MedicalReportInterpretation.fromJson(Map<String, dynamic> json) =>
      MedicalReportInterpretation(
        source: _stringOrEmpty(json['source']),
        examinationDate: _optionalString(json['examination_date']),
        doctorFindings: _stringList(json['doctor_findings']),
        documentedDiagnosis: _stringList(json['documented_diagnosis']),
        tests: _objectList(json['tests'])
            .map(MedicalTestFinding.fromJson)
            .toList(),
        conclusions: _stringList(json['conclusions']),
        recommendedTreatments: _stringList(json['recommended_treatments']),
        medicationNames: _stringList(json['medication_names']),
        followUpInstructions: _stringList(json['follow_up_instructions']),
        otherReportText: _stringList(json['other_report_text']),
        missingOrUnreadable: _stringList(json['missing_or_unreadable']),
        uncertainty: _stringList(json['uncertainty']),
      );
}

class AssessmentGuidance {
  const AssessmentGuidance({
    required this.patientSummary,
    required this.skinAnalysisContext,
    required this.medicationExplanation,
    required this.examinationExplanation,
    required this.reassuringObservations,
    required this.concerningObservations,
    required this.missingInformation,
    required this.recommendations,
    required this.clinicianFollowUp,
    required this.urgentCareGuidance,
    required this.disclaimer,
  });

  final String patientSummary;
  final String skinAnalysisContext;
  final String medicationExplanation;
  final String examinationExplanation;
  final List<String> reassuringObservations;
  final List<String> concerningObservations;
  final List<String> missingInformation;
  final List<String> recommendations;
  final String clinicianFollowUp;
  final String urgentCareGuidance;
  final String disclaimer;

  factory AssessmentGuidance.fromJson(Map<String, dynamic> json) =>
      AssessmentGuidance(
        patientSummary: _requiredString(json, 'patient_summary'),
        skinAnalysisContext: _requiredString(json, 'skin_analysis_context'),
        medicationExplanation: _requiredString(json, 'medication_explanation'),
        examinationExplanation:
            _requiredString(json, 'examination_explanation'),
        reassuringObservations: _stringList(json['reassuring_observations']),
        concerningObservations: _stringList(json['concerning_observations']),
        missingInformation: _stringList(json['missing_information']),
        recommendations: _stringList(json['recommendations']),
        clinicianFollowUp: _requiredString(json, 'clinician_follow_up'),
        urgentCareGuidance: _requiredString(json, 'urgent_care_guidance'),
        disclaimer: _requiredString(json, 'disclaimer'),
      );
}

class AssessmentSafety {
  const AssessmentSafety({
    required this.concernLevel,
    required this.referralRequired,
    required this.medicationRecommendationsAllowed,
    required this.medicationBlockReasons,
  });

  final String concernLevel;
  final bool referralRequired;
  final bool medicationRecommendationsAllowed;
  final List<String> medicationBlockReasons;

  factory AssessmentSafety.fromJson(Map<String, dynamic> json) =>
      AssessmentSafety(
        concernLevel: _requiredString(json, 'concern_level'),
        referralRequired: json['referral_required'] == true,
        medicationRecommendationsAllowed:
            json['medication_recommendations_allowed'] == true,
        medicationBlockReasons: _stringList(json['medication_block_reasons']),
      );
}

class StoredAssessmentFile {
  const StoredAssessmentFile({
    required this.id,
    required this.kind,
    required this.mimeType,
  });

  final String id;
  final String kind;
  final String mimeType;

  factory StoredAssessmentFile.fromJson(Map<String, dynamic> json) =>
      StoredAssessmentFile(
        id: _requiredString(json, 'id'),
        kind: _requiredString(json, 'kind'),
        mimeType: _requiredString(json, 'mime_type'),
      );
}

class MedicalAssessmentResult {
  const MedicalAssessmentResult({
    required this.id,
    required this.createdAt,
    required this.patient,
    required this.skinAnalysis,
    required this.medication,
    required this.medicationHistory,
    required this.examinations,
    required this.guidance,
    required this.safety,
    required this.originalReportsAvailable,
    required this.sources,
    required this.originalFiles,
  });

  final String id;
  final DateTime createdAt;
  final PatientInformation patient;
  final Map<String, dynamic> skinAnalysis;
  final MedicationAssessment? medication;
  final Map<String, dynamic>? medicationHistory;
  final List<MedicalReportInterpretation> examinations;
  final AssessmentGuidance guidance;
  final AssessmentSafety safety;
  final bool originalReportsAvailable;
  final List<String> sources;
  final List<StoredAssessmentFile> originalFiles;

  factory MedicalAssessmentResult.fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse(_stringOrEmpty(json['created_at']))?.toLocal();
    final skin = json['skin_analysis'];
    final medication = json['medication'];
    final medicationHistory = json['medication_history'];
    if (createdAt == null ||
        skin is! Map ||
        (medication != null && medication is! Map) ||
        (medicationHistory != null && medicationHistory is! Map)) {
      throw const MedicalAssessmentApiException(
        'The assessment service returned an invalid report.',
      );
    }
    return MedicalAssessmentResult(
      id: _requiredString(json, 'id'),
      createdAt: createdAt,
      patient:
          PatientInformation.fromJson(_object(json['patient_information'])),
      skinAnalysis: Map<String, dynamic>.from(skin),
      medication: medication == null
          ? null
          : MedicationAssessment.fromJson(
              Map<String, dynamic>.from(medication as Map),
            ),
      medicationHistory: medicationHistory == null
          ? null
          : Map<String, dynamic>.from(medicationHistory as Map),
      examinations: _objectList(json['examinations'])
          .map(MedicalReportInterpretation.fromJson)
          .toList(),
      guidance: AssessmentGuidance.fromJson(_object(json['guidance'])),
      safety: json['safety'] is Map
          ? AssessmentSafety.fromJson(_object(json['safety']))
          : const AssessmentSafety(
              concernLevel: 'moderate',
              referralRequired: false,
              medicationRecommendationsAllowed: false,
              medicationBlockReasons: ['legacy_assessment'],
            ),
      originalReportsAvailable: json['original_reports_available'] == true,
      sources: _stringList(json['sources']),
      originalFiles: _objectList(json['original_files'])
          .map(StoredAssessmentFile.fromJson)
          .toList(),
    );
  }
}

class MedicalAssessmentApi {
  MedicalAssessmentApi({
    required String baseUrl,
    required this.tokenProvider,
    http.Client? client,
  })  : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final AssessmentTokenProvider tokenProvider;
  final http.Client _client;
  final bool _ownsClient;

  Uri _uri(String path) {
    final uri = Uri.tryParse('$_baseUrl$path');
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const MedicalAssessmentApiException(
        'Configure a valid HTTP or HTTPS AI API URL.',
        statusCode: 400,
      );
    }
    return uri;
  }

  Future<MedicalAssessmentResult> createAssessment(
    MedicalAssessmentUpload upload, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (upload.skinImage.isEmpty ||
        upload.skinImage.length > 10 * 1024 * 1024) {
      throw const MedicalAssessmentApiException(
        'The skin image must be between 1 byte and 10 MB.',
        statusCode: 413,
      );
    }
    final token = await _token(forceRefresh: false);
    final response = await _sendAssessment(
      upload,
      token: token,
      onProgress: onProgress,
    );
    if (response.statusCode == 401) {
      final refreshedToken = await _token(forceRefresh: true);
      final retry = await _sendAssessment(
        upload,
        token: refreshedToken,
        onProgress: onProgress,
      );
      return _parseResult(retry);
    }
    return _parseResult(response);
  }

  Future<http.Response> _sendAssessment(
    MedicalAssessmentUpload upload, {
    required String token,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/medical/assessments'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..fields['patient_data'] = jsonEncode(upload.patientData);
    request.files.add(
      http.MultipartFile.fromBytes(
        'skin_image',
        upload.skinImage,
        filename: upload.skinFilename,
        contentType: _mediaType(upload.skinFilename),
      ),
    );
    final medicationImage = upload.medicationImage;
    if (medicationImage != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'medication_image',
          medicationImage,
          filename: upload.medicationFilename ?? 'medication.jpg',
          contentType:
              _mediaType(upload.medicationFilename ?? 'medication.jpg'),
        ),
      );
    }
    for (final report in upload.reports) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'medical_reports',
          report.bytes,
          filename: report.filename,
          contentType: MediaType.parse(report.mimeType),
        ),
      );
    }
    try {
      final streamed = await sendMultipartWithProgress(
        _client,
        request,
        onProgress: onProgress,
      ).timeout(const Duration(seconds: 180));
      return await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MedicalAssessmentApiException(
        'The assessment request timed out. Try again later.',
        statusCode: 504,
      );
    } on http.ClientException {
      throw const MedicalAssessmentApiException(
        'Could not connect to the medical assessment service.',
      );
    }
  }

  Future<Uint8List> originalFile({
    required String assessmentId,
    required String fileId,
  }) async {
    final token = await _token(forceRefresh: false);
    final uri = _uri(
      '/medical/assessments/${Uri.encodeComponent(assessmentId)}/files/'
      '${Uri.encodeComponent(fileId)}',
    );
    final response = await _getFile(uri, token);
    if (response.statusCode == 401) {
      final refreshed = await _token(forceRefresh: true);
      return _readFileResponse(await _getFile(uri, refreshed));
    }
    return _readFileResponse(response);
  }

  Future<List<MedicalAssessmentResult>> listAssessments() async {
    var token = await _token(forceRefresh: false);
    var response = await _requestAssessmentList(token);
    if (response.statusCode == 401) {
      token = await _token(forceRefresh: true);
      response = await _requestAssessmentList(token);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const FormatException('Expected a list.');
      }
      return decoded
          .map((item) => MedicalAssessmentResult.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();
    } on FormatException {
      throw const MedicalAssessmentApiException(
        'The assessment history could not be parsed.',
        statusCode: 502,
      );
    }
  }

  Future<MedicalAssessmentResult> getAssessment(
    String assessmentId,
  ) async {
    var token = await _token(forceRefresh: false);
    var response = await _requestAssessment(
      assessmentId,
      token,
    );
    if (response.statusCode == 401) {
      token = await _token(forceRefresh: true);
      response = await _requestAssessment(assessmentId, token);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response.statusCode);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected an object.');
      }
      return MedicalAssessmentResult.fromJson(decoded);
    } on FormatException {
      throw const MedicalAssessmentApiException(
        'The assessment could not be parsed.',
        statusCode: 502,
      );
    }
  }

  Future<http.Response> _requestAssessmentList(String token) async {
    try {
      return await _client.get(
        _uri('/medical/assessments'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MedicalAssessmentApiException(
        'Loading assessments timed out.',
        statusCode: 504,
      );
    } on http.ClientException {
      throw const MedicalAssessmentApiException(
        'Could not load assessment history.',
      );
    }
  }

  Future<http.Response> _requestAssessment(
    String assessmentId,
    String token,
  ) async {
    try {
      return await _client.get(
        _uri(
          '/medical/assessments/${Uri.encodeComponent(assessmentId)}',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MedicalAssessmentApiException(
        'Loading the assessment timed out.',
        statusCode: 504,
      );
    } on http.ClientException {
      throw const MedicalAssessmentApiException(
        'Could not load the assessment.',
      );
    }
  }

  Future<void> deleteAssessment(String assessmentId) async {
    var token = await _token(forceRefresh: false);
    var response = await _deleteAssessment(assessmentId, token);
    if (response.statusCode == 401) {
      token = await _token(forceRefresh: true);
      response = await _deleteAssessment(assessmentId, token);
    }
    if (response.statusCode != 204) {
      _throwForResponse(response.statusCode);
    }
  }

  Future<http.Response> _deleteAssessment(
    String assessmentId,
    String token,
  ) async {
    try {
      return await _client.delete(
        _uri(
          '/medical/assessments/${Uri.encodeComponent(assessmentId)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MedicalAssessmentApiException(
        'Deleting the assessment timed out.',
      );
    } on http.ClientException {
      throw const MedicalAssessmentApiException(
        'Could not delete the assessment.',
      );
    }
  }

  Future<http.Response> _getFile(Uri uri, String token) async {
    try {
      return await _client.get(uri, headers: {
        'Accept': 'application/octet-stream',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MedicalAssessmentApiException(
        'The original medical report request timed out.',
      );
    } on http.ClientException {
      throw const MedicalAssessmentApiException(
        'Could not download the original medical report.',
      );
    }
  }

  Uint8List _readFileResponse(http.Response response) {
    if (response.statusCode != 200) _throwForResponse(response.statusCode);
    return response.bodyBytes;
  }

  MedicalAssessmentResult _parseResult(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(
        response.statusCode,
        serverDetail: _serverDetail(response),
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected an object.');
      }
      return MedicalAssessmentResult.fromJson(decoded);
    } on FormatException {
      throw const MedicalAssessmentApiException(
        'The assessment service returned an invalid report.',
        statusCode: 502,
      );
    }
  }

  Future<String> _token({required bool forceRefresh}) async {
    final token = await tokenProvider(forceRefresh: forceRefresh);
    if (token == null || token.trim().isEmpty) {
      throw const MedicalAssessmentApiException(
        'A signed-in account is required to complete an assessment.',
        statusCode: 401,
      );
    }
    return token;
  }

  MediaType _mediaType(String filename) {
    final extension = filename.toLowerCase().split('.').last;
    return switch (extension) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'pdf' => MediaType('application', 'pdf'),
      _ => MediaType('image', 'jpeg'),
    };
  }

  String? _serverDetail(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        final detail = (decoded['detail'] as String).trim();
        return detail.isEmpty ? null : detail;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Never _throwForResponse(int statusCode, {String? serverDetail}) {
    throw MedicalAssessmentApiException(
      switch (statusCode) {
        401 => 'Your session expired. Sign in again.',
        403 => 'Processing consent or access was denied.',
        413 => 'The uploaded medical files exceed the size limit.',
        415 => 'A selected medical file format is not supported.',
        422 => 'Check the assessment answers and uploaded files.',
        429 => 'Too many assessment requests. Please wait and retry.',
        503 => 'The medical assessment service is unavailable.',
        502 => serverDetail ?? 'The medical assessment provider failed.',
        504 => serverDetail ?? 'The medical assessment provider timed out.',
        500 => 'The medical assessment server failed (HTTP 500).',
        _ => 'The medical assessment could not be completed.',
      },
      statusCode: statusCode,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const MedicalAssessmentApiException(
    'The assessment service returned an invalid report.',
  );
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is! List) {
    throw const MedicalAssessmentApiException(
      'The assessment service returned an invalid report.',
    );
  }
  return value.map(_object).toList();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const MedicalAssessmentApiException(
      'The assessment service returned an invalid report.',
    );
  }
  return value;
}

String? _optionalString(Object? value) => value is String ? value : null;

String _stringOrEmpty(Object? value) => value is String ? value : '';

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}
