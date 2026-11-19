import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/admin/admin_api_service.dart';
import 'package:skin_ai/admin/admin_appointments_screen.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/localization/locale_helper.dart';

Map<String, dynamic> _appointmentsResponse() => {
      'appointments': [
        {
          'id': 'appointment-1',
          'doctor_id': 'doctor-1',
          'doctor_name': 'Doctor One',
          'clinic_id': 'clinic-1',
          'clinic_name': 'Clinic One',
          'city': 'Erbil',
          'appointment_date': '2026-10-01',
          'appointment_time': '09:00',
          'status': 'pending',
        },
      ],
      'next_cursor': null,
    };

void main() {
  testWidgets('appointment screen refuses direct navigation for non-admin',
      (tester) async {
    var listRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response(
          jsonEncode({'detail': 'Administrator access is required.'}),
          403,
        );
      }
      if (request.url.path == '/api/admin/appointments') {
        listRequests++;
        return http.Response('{}', 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(_localizedApp(AdminAppointmentsScreen(api: api)));
    await tester.pumpAndSettle();

    expect(
      find.text('Administrator access could not be verified.'),
      findsOneWidget,
    );
    expect(listRequests, 0);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('appointment moderation requires a reason and sends it',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    Map<String, dynamic>? moderationBody;
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response('{"admin":true}', 200);
      }
      if (request.url.path == '/api/admin/appointments' &&
          request.method == 'GET') {
        return http.Response(jsonEncode(_appointmentsResponse()), 200);
      }
      if (request.url.path == '/api/admin/appointments/appointment-1' &&
          request.method == 'PATCH') {
        moderationBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            ..._appointmentsResponse()['appointments'][0]
                as Map<String, dynamic>,
            'status': 'confirmed',
          }),
          200,
        );
      }
      fail('Unexpected admin request: ${request.method} ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(
      _localizedApp(AdminAppointmentsScreen(api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Patient'), findsNothing);

    await tester.tap(find.byTooltip('Appointment actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmed'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Appointment for Doctor One'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
        find.text('Enter a reason of at least 3 characters.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField),
      'Confirmed after availability check.',
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(moderationBody, {
      'status': 'confirmed',
      'reason': 'Confirmed after availability check.',
    });
    expect(find.text('Appointment updated.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    client.close();
  });

  testWidgets('appointments fit supported RTL widths and text scales',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response('{"admin":true}', 200);
      }
      if (request.url.path == '/api/admin/appointments') {
        return http.Response(jsonEncode(_appointmentsResponse()), 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    for (final locale in LocaleHelper.supportedLocales) {
      for (final width in [320.0, 360.0, 390.0, 600.0, 1024.0, 1440.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            _localizedApp(
              AdminAppointmentsScreen(
                key: ValueKey('$locale-$width-$scale'),
                api: api,
              ),
              locale: locale,
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'locale=$locale width=$width textScale=$scale',
          );
        }
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    client.close();
  });
}

Widget _localizedApp(
  Widget home, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleHelper.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        _KurdishMaterialLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        _KurdishCupertinoLocalizationsDelegate(),
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.build(Brightness.light, locale: locale),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: LocaleHelper.directionFor(locale),
            child: home,
          ),
        ),
      ),
    );

bool _isKurdish(Locale locale) =>
    locale.languageCode == 'ku' || locale.languageCode == 'bad';

class _KurdishMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _KurdishMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isKurdish(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_KurdishMaterialLocalizationsDelegate old) => false;
}

class _KurdishCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _KurdishCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isKurdish(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_KurdishCupertinoLocalizationsDelegate old) => false;
}
