import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/admin/admin_api_service.dart';
import 'package:skin_ai/doctors/doctor_api_service.dart';
import 'package:skin_ai/doctors/doctor_models.dart';
import 'package:skin_ai/doctors/doctor_screens.dart';
import 'package:skin_ai/localization/app_localizations.dart';

http.Response _json(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json'});

Map<String, dynamic> _adminDashboardJson() {
  final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final points = [
    for (var index = 0; index < 7; index++) {'date': day, 'value': 0},
  ];
  return {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'period_days': 7,
    'users_total': 0,
    'new_users_by_day': points,
    'scans_by_day': points,
    'scans_total': 0,
    'skinchat_messages_by_day': points,
    'skinchat_messages_total': 0,
    'appointments_by_status': <String, int>{},
    'doctors_published': 0,
    'doctors_pending': 0,
    'reports_waiting': 0,
    'system_health': {
      'status': 'ok',
      'mock_mode': false,
      'skinchat_enabled': false,
    },
  };
}

void main() {
  testWidgets('empty discovery shows a real-data empty state', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/doctors') return _json([]);
      if (request.url.path == '/api/doctors/favorites/mine') return _json([]);
      if (request.url.path == '/api/admin/status') {
        return http.Response(
          jsonEncode({'detail': 'Administrator access is required.'}),
          403,
        );
      }
      fail('Unexpected doctor directory request: ${request.url}');
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );
    final adminApi = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: DoctorDirectoryScreen(
          baseUrl: 'http://localhost:8000',
          idTokenProvider: () async => 'test-token',
          api: api,
          adminApi: adminApi,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No doctors to show yet'), findsOneWidget);
    expect(
        find.textContaining('No sample profiles or ratings'), findsOneWidget);
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('admin entry appears after the server confirms access',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return _json({'admin': true});
      }
      if (request.url.path == '/api/admin/dashboard') {
        return _json(_adminDashboardJson());
      }
      if (request.url.path == '/api/doctors') return _json([]);
      if (request.url.path == '/api/doctors/favorites/mine') return _json([]);
      fail('Unexpected request: ${request.url}');
    });
    Future<String?> tokenProvider() async => 'test-token';
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: tokenProvider,
      client: client,
    );
    final adminApi = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: tokenProvider,
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: DoctorDirectoryScreen(
          baseUrl: 'http://localhost:8000',
          idTokenProvider: tokenProvider,
          api: api,
          adminApi: adminApi,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.admin_panel_settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Total users'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('verified doctor profile shows clinic and booking details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = MockClient((request) async {
      expect(request.url.path, '/api/doctors/doctor-1/reviews');
      return _json([]);
    });
    final api = DoctorApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );
    const doctor = DoctorProfile(
      id: 'doctor-1',
      fullName: 'Real profile name',
      specializations: ['Dermatology'],
      qualifications: ['Verified medical qualification'],
      experienceYears: 8,
      clinics: [
        DoctorClinic(
          id: 'clinic-1',
          name: 'Verified clinic',
          city: 'Erbil',
          address: 'Verified clinic address',
          weeklySchedule: [
            DoctorAvailabilityRule(weekday: 0, times: ['09:00']),
          ],
        ),
      ],
      verified: true,
      publicationStatus: 'published',
      averageRating: 4.5,
      reviewCount: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: DoctorProfileScreen(
          api: api,
          doctor: doctor,
          isFavorite: false,
          onFavoriteChanged: () async => true,
          onBook: () {},
          onNotice: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Real profile name'), findsOneWidget);
    expect(find.text('Verified doctor'), findsOneWidget);
    expect(find.text('Verified medical qualification'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('Verified clinic address'),
      find.byType(ListView).last,
      const Offset(0, -500),
    );
    expect(find.textContaining('Verified clinic address'), findsOneWidget);
    expect(find.text('Book appointment'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });
}
