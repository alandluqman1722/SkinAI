import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_ai/admin/admin_api_service.dart';
import 'package:skin_ai/admin/admin_dashboard_screen.dart';
import 'package:skin_ai/design/app_design_system.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/localization/locale_helper.dart';

Map<String, dynamic> _dashboardResponse() {
  final today = DateTime.now().toUtc();
  final points = [
    for (var index = 6; index >= 0; index--)
      {
        'date':
            today.subtract(Duration(days: index)).toIso8601String().substring(
                  0,
                  10,
                ),
        'value': index == 0 ? 2 : 0,
      },
  ];
  return {
    'generated_at': today.toIso8601String(),
    'period_days': 7,
    'users_total': 12,
    'new_users_by_day': points,
    'scans_by_day': points,
    'scans_total': 2,
    'skinchat_messages_by_day': points,
    'skinchat_messages_total': 2,
    'appointments_by_status': {
      'pending': 1,
      'confirmed': 0,
      'completed': 0,
      'rejected': 0,
      'cancelled': 0,
    },
    'doctors_published': 1,
    'doctors_pending': 0,
    'reports_waiting': 0,
    'system_health': {
      'status': 'ok',
      'mock_mode': false,
      'skinchat_enabled': true,
    },
  };
}

void main() {
  testWidgets('dashboard refuses direct navigation without server approval',
      (tester) async {
    var dashboardRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response(
          jsonEncode({'detail': 'Administrator access is required.'}),
          403,
        );
      }
      if (request.url.path == '/api/admin/dashboard') {
        dashboardRequests++;
        return http.Response('{}', 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(_localizedApp(
      AdminDashboardScreen(
        api: api,
        doctorManagementBuilder: (_) => const Scaffold(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Administrator access could not be verified.'),
        findsOneWidget);
    expect(dashboardRequests, 0);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('token refresh immediately rechecks server admin status',
      (tester) async {
    final tokenChanges = StreamController<void>();
    var hasAdminClaim = true;
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return hasAdminClaim
            ? http.Response('{"admin":true}', 200)
            : http.Response(
                jsonEncode({'detail': 'Administrator access is required.'}),
                403,
              );
      }
      if (request.url.path == '/api/admin/dashboard') {
        return http.Response(jsonEncode(_dashboardResponse()), 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(_localizedApp(
      AdminDashboardScreen(
        api: api,
        tokenChanges: tokenChanges.stream,
        doctorManagementBuilder: (_) => const Scaffold(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Total users'), findsOneWidget);
    expect(find.text('12'), findsWidgets);

    hasAdminClaim = false;
    tokenChanges.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Administrator access could not be verified.'),
        findsOneWidget);
    expect(find.text('Total users'), findsNothing);
    expect(tester.takeException(), isNull);
    await tokenChanges.close();
    client.close();
  });

  testWidgets('dashboard switches between supported trend periods',
      (tester) async {
    final requestedPeriods = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response('{"admin":true}', 200);
      }
      if (request.url.path == '/api/admin/dashboard') {
        requestedPeriods.add(request.url.queryParameters['days']);
        return http.Response(jsonEncode(_dashboardResponse()), 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    await tester.pumpWidget(_localizedApp(
      AdminDashboardScreen(
        api: api,
        doctorManagementBuilder: (_) => const Scaffold(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(requestedPeriods, ['7']);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    expect(requestedPeriods, ['7', '30']);
    expect(find.text('New users (last 30 days)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets(
      'dashboard has no layout overflows at supported widths and scales',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/admin/status') {
        return http.Response('{"admin":true}', 200);
      }
      if (request.url.path == '/api/admin/dashboard') {
        return http.Response(jsonEncode(_dashboardResponse()), 200);
      }
      fail('Unexpected admin request: ${request.url}');
    });
    final api = AdminApiService(
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => 'test-token',
      client: client,
    );

    for (final width in [320.0, 360.0, 390.0, 600.0, 1024.0, 1440.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _localizedApp(
            AdminDashboardScreen(
              api: api,
              doctorManagementBuilder: (_) => const Scaffold(),
            ),
            locale: const Locale('ar'),
            textScale: scale,
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width textScale=$scale',
        );
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
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleHelper.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.build(brightness, locale: locale),
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
