import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/admin/admin_api_service.dart';
import 'package:skin_ai/admin/admin_users_screen.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/localization/locale_helper.dart';

Map<String, dynamic> _usersResponse() => {
      'users': [
        {
          'uid': 'test-user',
          'email': 'person@example.test',
          'display_name': 'Test Person',
          'created_at': '2024-01-01T00:00:00Z',
          'last_sign_in': null,
          'email_verified': true,
          'disabled': false,
          'blocked': false,
          'plan': 'free',
        },
      ],
      'next_cursor': null,
    };

void main() {
  testWidgets('user screen refuses access without server approval',
      (tester) async {
    var userRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response(
          jsonEncode({'detail': 'Administrator access is required.'}),
          403,
        );
      }
      if (request.url.path == '/api/admin/users') {
        userRequests++;
        return http.Response('{}', 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(_localizedApp(AdminUsersScreen(api: api)));
    await tester.pumpAndSettle();

    expect(
      find.text('Administrator access could not be verified.'),
      findsOneWidget,
    );
    expect(userRequests, 0);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('user list stays responsive across widths and text scales',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response('{"admin":true}', 200);
      }
      if (request.url.path == '/api/admin/users') {
        return http.Response(jsonEncode(_usersResponse()), 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    for (final locale in [
      const Locale('en'),
      const Locale('ku'),
      const Locale('bad'),
      const Locale('ar'),
    ]) {
      for (final width in [320.0, 360.0, 390.0, 600.0, 1024.0, 1440.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            _localizedApp(
              AdminUsersScreen(
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
