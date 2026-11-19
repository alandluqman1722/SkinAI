import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/medical_assessment/medical_assessment_api.dart';
import 'package:skin_ai/medical_assessment/medical_assessment_screen.dart';

void main() {
  testWidgets('assessment screen renders without missing English app keys',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MedicalAssessmentScreen(
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
          baseUrl: 'https://api.example.test',
          tokenProvider: ({required forceRefresh}) async => 'account-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Personalized skin-health assessment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assessment questions are split into navigable steps',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MedicalAssessmentScreen(
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
          baseUrl: 'https://api.example.test',
          tokenProvider: ({required forceRefresh}) async => 'account-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(
      find.text('Are you using medication or cream for this condition?'),
      findsNothing,
    );

    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), '34');
    await tester.enterText(inputs.at(3), 'two weeks');
    final sexDropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(sexDropdown);
    await tester.tap(sexDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer not to say').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(
      find.text('Are you using medication or cream for this condition?'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'assessment details start collapsed and medicine warning stays visible',
      (tester) async {
    final result = MedicalAssessmentResult.fromJson({
      'id': 'assessment-visual-test',
      'created_at': '2026-11-19T00:00:00Z',
      'patient_information': {
        'age': 34,
        'sex': 'prefer_not_to_say',
        'symptoms_duration': 'two weeks',
        'symptoms_details': 'itching',
        'body_location': 'Face',
        'allergies': '',
        'medical_history': '',
        'pregnancy_or_breastfeeding': 'not_applicable',
      },
      'skin_analysis': {
        'result': 'Possible irritation pattern',
        'confidence': 0.62,
        'summary':
            'A short screening summary followed by a long detail that should remain collapsed.',
      },
      'medication': {
        'medicine_name': 'Example cream',
        'confidence': 0.9,
        'intended_uses': [
          '${List.filled(15, 'detailed medicine information').join(' ')} END_MARKER',
        ],
      },
      'medication_history': null,
      'examinations': [],
      'guidance': {
        'patient_summary': 'Educational summary',
        'skin_analysis_context': 'Screening estimate',
        'medication_explanation': 'Educational medicine explanation.',
        'examination_explanation': 'No report provided',
        'reassuring_observations': [],
        'concerning_observations': [],
        'missing_information': [],
        'recommendations': ['Discuss persistent symptoms with a clinician'],
        'clinician_follow_up': 'Clinician evaluation is appropriate',
        'urgent_care_guidance': 'Seek urgent care for breathing difficulty',
        'disclaimer': 'Educational information only',
      },
      'safety': {
        'concern_level': 'low',
        'referral_required': false,
        'medication_recommendations_allowed': false,
        'medication_block_reasons': [],
      },
      'original_reports_available': false,
      'sources': [],
      'original_files': [],
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MedicalAssessmentScreen(
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
          baseUrl: 'https://api.example.test',
          tokenProvider: ({required forceRefresh}) async => 'account-token',
          initialResult: result,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('62%'), findsOneWidget);

    final medicationDetails = find.byKey(
      const ValueKey('assessment-medication-details'),
    );
    await tester.scrollUntilVisible(
      medicationDetails,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        "Do not start, change, or stop any medication without your doctor's approval.",
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('END_MARKER'),
      findsNothing,
    );
    await tester.ensureVisible(medicationDetails);
    await tester.pumpAndSettle();
    await tester.tap(medicationDetails);
    await tester.pumpAndSettle();

    expect(find.textContaining('END_MARKER'), findsOneWidget);
    expect(
      find.text(
        "Do not start, change, or stop any medication without your doctor's approval.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('assessment API sends consent, bearer token, and all attachments',
      () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer account-token');
      expect(request.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(request.bodyBytes, isNotEmpty);
      expect(request.body, contains('external_processing_consent'));
      expect(request.body, contains('name="skin_image"'));
      expect(request.body, contains('name="medication_image"'));
      expect(request.body, contains('name="medical_reports"'));
      expect(request.body, contains('structured_examinations'));
      return http.Response(
        jsonEncode({
          'id': 'assessment-1',
          'created_at': '2026-11-19T00:00:00Z',
          'patient_information': {
            'age': 34,
            'sex': 'prefer_not_to_say',
            'symptoms_duration': 'two weeks',
            'symptoms_details': 'itching',
            'body_location': 'Face',
            'allergies': '',
            'medical_history': '',
            'pregnancy_or_breastfeeding': 'not_applicable',
          },
          'skin_analysis': {
            'result': 'Screening label',
            'confidence': 62,
            'summary': 'Screening summary',
          },
          'medication': null,
          'medication_history': null,
          'examinations': [],
          'guidance': {
            'patient_summary': 'Educational summary',
            'skin_analysis_context': 'Screening estimate',
            'medication_explanation': 'No medication reported',
            'examination_explanation': 'No report provided',
            'reassuring_observations': [],
            'concerning_observations': [],
            'missing_information': [],
            'recommendations': ['Discuss persistent symptoms with a clinician'],
            'clinician_follow_up': 'Clinician evaluation is appropriate',
            'urgent_care_guidance': 'Seek urgent care for breathing difficulty',
            'disclaimer': 'Educational information only',
          },
          'original_reports_available': true,
          'sources': ['Ivy AI skin-condition screening'],
          'original_files': [],
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = MedicalAssessmentApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: ({required forceRefresh}) async => 'account-token',
      client: client,
    );
    final result = await api.createAssessment(
      MedicalAssessmentUpload(
        patientData: {
          'age': 34,
          'sex': 'prefer_not_to_say',
          'taking_medication': true,
          'had_examinations': true,
          'external_processing_consent': true,
          'storage_consent': true,
          'symptoms_duration': 'two weeks',
          'medication_duration': 'one week',
          'medication_prescribed': 'no',
          'medication_effect': 'no_change',
          'structured_examinations': [
            {
              'examination_date': '2025-01-03',
              'doctor_findings': ['Patient-entered finding'],
              'documented_diagnosis': [],
            },
          ],
        },
        skinImage: Uint8List.fromList([1, 2, 3]),
        skinFilename: 'skin.png',
        medicationImage: Uint8List.fromList([4, 5, 6]),
        medicationFilename: 'medication.png',
        reports: [
          AssessmentFileUpload(
            bytes: Uint8List.fromList([7, 8, 9]),
            filename: 'report.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );
    expect(result.id, 'assessment-1');
    expect(result.patient.age, 34);
    expect(result.guidance.recommendations, isNotEmpty);
    client.close();
  });

  test('assessment API surfaces authentication and validation errors',
      () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"detail":"invalid"}',
        422,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = MedicalAssessmentApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: ({required forceRefresh}) async => 'account-token',
      client: client,
    );
    await expectLater(
      api.createAssessment(
        MedicalAssessmentUpload(
          patientData: {
            'taking_medication': false,
            'had_examinations': false,
            'external_processing_consent': true,
          },
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
        ),
      ),
      throwsA(
        isA<MedicalAssessmentApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          422,
        ),
      ),
    );
    client.close();
  });

  test('assessment API preserves safe provider-specific timeout details',
      () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"detail":"The medical AI provider timed out."}',
        504,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = MedicalAssessmentApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: ({required forceRefresh}) async => 'account-token',
      client: client,
    );
    await expectLater(
      api.createAssessment(
        MedicalAssessmentUpload(
          patientData: const {},
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
        ),
      ),
      throwsA(
        isA<MedicalAssessmentApiException>().having(
          (error) => error.message,
          'message',
          'The medical AI provider timed out.',
        ),
      ),
    );
    client.close();
  });

  test('assessment API surfaces provider errors instead of a generic message',
      () async {
    var requestCount = 0;
    final client = MockClient(
      (_) async {
        requestCount++;
        return http.Response(
          '{"detail":"The medical AI provider could not complete the request."}',
          502,
          headers: {'content-type': 'application/json'},
        );
      },
    );
    final api = MedicalAssessmentApi(
      baseUrl: 'https://api.example.test',
      tokenProvider: ({required forceRefresh}) async => 'account-token',
      client: client,
    );
    await expectLater(
      api.createAssessment(
        MedicalAssessmentUpload(
          patientData: const {},
          skinImage: Uint8List.fromList([1, 2, 3]),
          skinFilename: 'skin.png',
        ),
      ),
      throwsA(
        isA<MedicalAssessmentApiException>().having(
          (error) => error.message,
          'message',
          'The medical AI provider could not complete the request.',
        ),
      ),
    );
    expect(requestCount, 1);
    client.close();
  });
}
