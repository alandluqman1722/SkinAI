import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:skin_ai/main.dart';

void main() {
  testWidgets('startup immediately shows branded loading instead of blank',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SkinAIStartup());
    expect(find.text('SkinAI'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('scan history keeps optional body metadata and reads legacy records',
      () {
    const scan = ScanRecord(
      cls: 'unknown',
      conf: 42,
      mel: false,
      ts: 123,
      bodyPart: 'Hands',
      bodySubregion: 'Left hand',
      bodySide: 'left',
      concernType: 'Redness',
      userId: 'firebase-user-1',
    );
    final restored = ScanRecord.fromJson(scan.toJson());
    expect(restored.bodyPart, 'Hands');
    expect(restored.bodySubregion, 'Left hand');
    expect(restored.bodySide, 'left');
    expect(restored.concernType, 'Redness');
    expect(restored.userId, 'firebase-user-1');

    final legacy = ScanRecord.fromJson({
      'cls': 'unknown',
      'conf': 42,
      'mel': false,
      'ts': 123,
    });
    expect(legacy.bodyPart, isNull);
  });

  test(
      'remote history stays separate and clearing does not migrate or erase it',
      () async {
    SharedPreferences.setMockInitialValues({
      'scans_person@example.com': jsonEncode([
        {
          'cls': 'legacy-local-result',
          'conf': 51,
          'mel': false,
          'ts': 123,
        }
      ]),
    });
    final gateway = FakeEmailPasswordAuthGateway()
      .._user = const AuthUserInfo(
        uid: 'firebase-user-1',
        email: 'person@example.com',
        displayName: 'Person',
        emailVerified: true,
      );
    final controller = AppController(authGateway: gateway);
    await controller.init();
    expect(controller.scans.single.cls, 'legacy-local-result');

    await controller.addAccountScan(
      const ScanRecord(
        cls: 'account-result',
        conf: 72,
        mel: false,
        ts: 456,
        analysisId: 'scan-owned',
        accountRecord: true,
      ),
    );
    expect(controller.scans.map((scan) => scan.cls), [
      'account-result',
      'legacy-local-result',
    ]);

    await controller.clearScans();
    expect(controller.scans.map((scan) => scan.cls), ['account-result']);
    final preferences = await SharedPreferences.getInstance();
    final storedLocal = jsonDecode(
      preferences.getString('scans_person@example.com')!,
    ) as List;
    expect(storedLocal, isEmpty);
  });

  test('unconfigured Firebase auth never creates a local session', () async {
    SharedPreferences.setMockInitialValues({
      'users': '{}',
      'session': 'legacy@example.com',
    });
    final controller = AppController();
    await controller.init();
    final preferences = await SharedPreferences.getInstance();

    expect(
      await controller.login(email: 'person@example.com', password: 'password'),
      AuthError.serviceUnavailable,
    );
    expect(
      await controller.register(
        name: 'Person',
        email: 'person@example.com',
        password: 'password',
      ),
      AuthError.serviceUnavailable,
    );
    expect(controller.currentUser, isNull);
    expect(
      controller.authSetupMessage,
      contains(
        'flutter run --dart-define-from-file=firebase.config.json',
      ),
    );
    expect(preferences.getString('users'), isNull);
    expect(preferences.getString('session'), isNull);
  });

  testWidgets('sign-in explains that Firebase setup is missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: AuthScreen(startLogin: true),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('Sign In'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining(
        'SkinAI (Firebase configured)',
      ),
      findsOneWidget,
    );
    expect(FirebaseClientConfig.isConfigured, isFalse);
  });

  testWidgets('auth form fits a narrow RTL screen with large text and keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    await controller.setLang(AppLang.ku);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 180),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: AuthScreen(startLogin: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('registration sends verification and keeps its pending session',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.register(
        name: 'Person',
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.verificationRequired,
    );
    expect(gateway.createCalls, 1);
    expect(gateway.verificationCalls, 1);
    expect(gateway.signOutCalls, 0);
    expect(gateway.currentUser?.emailVerified, isFalse);
  });

  test('signed-in profile uses its Firebase UID', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway()..emailVerified = true;
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.login(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.none,
    );
    expect(controller.currentUser?.uid, 'firebase-user-1');
    expect(await controller.getFirebaseIdToken(), 'test-firebase-id-token');
  });

  test('verification request failure is reported and signs out the new user',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway()
      ..verificationError = FirebaseAuthException(
        code: 'network-request-failed',
      );
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.register(
        name: 'Person',
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.verificationNetworkError,
    );
    expect(gateway.accountCreated, isTrue);
    expect(gateway.createCalls, 1);
    expect(gateway.signOutCalls, 1);
    expect(gateway.currentUser, isNull);
  });

  test('resend authenticates the existing account and enforces cooldown',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.resendVerificationEmail(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.verificationResent,
    );
    expect(gateway.createCalls, 0);
    expect(gateway.signInCalls, 1);
    expect(gateway.verificationCalls, 1);
    expect(gateway.signOutCalls, 0);
    expect(gateway.currentUser, isNotNull);
    expect(
      await controller.resendVerificationEmail(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.tooManyRequests,
    );
    expect(gateway.signInCalls, 1);
  });

  test('resend surfaces invalid credentials without sending email', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.resendVerificationEmail(
        email: 'person@example.com',
        password: 'wrong-password',
      ),
      AuthError.wrongPassword,
    );
    expect(gateway.verificationCalls, 0);
    expect(gateway.signOutCalls, 0);
  });

  test('resend notices when the account became verified', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway()..verifyOnReload = true;
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.resendVerificationEmail(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.none,
    );
    expect(gateway.verificationCalls, 0);
    expect(gateway.signOutCalls, 0);
    expect(controller.currentUser?.email, 'person@example.com');
  });

  test('verification refresh activates only after Firebase reload confirms it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();
    await controller.register(
      name: 'Person',
      email: 'person@example.com',
      password: 'password123',
    );

    expect(await controller.refreshEmailVerification(),
        AuthError.emailNotVerified);
    expect(controller.currentUser, isNull);

    gateway.verifyOnReload = true;
    expect(await controller.refreshEmailVerification(), AuthError.none);
    expect(controller.currentUser?.email, 'person@example.com');
  });

  testWidgets('auth screen rechecks Firebase verification when returning', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();
    await controller.register(
      name: 'Person',
      email: 'person@example.com',
      password: 'password123',
    );

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: AuthScreen(startLogin: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('I verified my email'), findsOneWidget);

    gateway.verifyOnReload = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(controller.currentUser?.email, 'person@example.com');
  });

  test('unverified sign-in is blocked and signs out', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway();
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.login(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.emailNotVerified,
    );
    expect(controller.currentUser, isNull);
    expect(gateway.signOutCalls, 1);
  });

  test('logout clears the authenticated user and notifies app listeners',
      () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway()..emailVerified = true;
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.login(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.none,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.logout();

    expect(gateway.currentUser, isNull);
    expect(controller.currentUser, isNull);
    expect(controller.scans, isEmpty);
    expect(gateway.signOutCalls, 1);
    expect(notifications, 1);
    expect(gateway.currentUser, isNull);
  });

  test('verified sign-in succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeEmailPasswordAuthGateway()..emailVerified = true;
    final controller = AppController(authGateway: gateway);
    await controller.init();

    expect(
      await controller.login(
        email: 'person@example.com',
        password: 'password123',
      ),
      AuthError.none,
    );
    expect(controller.currentUser?.email, 'person@example.com');
    expect(gateway.currentUser?.emailVerified, isTrue);
  });

  test('provider response parser preserves generic result fields', () {
    final result = ScanResult.fromJson({
      'result': 'A future provider label',
      'confidence': 72.5,
      'summary': 'A **provider** summary.',
      'id': 'scan-456',
      'timestamp': '2026-10-29T12:00:00+00:00',
      'discordant': true,
    });
    expect(result.cls, 'A future provider label');
    expect(result.confidence, 72.5);
    expect(result.summary, 'A **provider** summary.');
    expect(result.scanId, 'scan-456');
  });

  test('provider response parser rejects invalid confidence values', () {
    expect(
      () => ScanResult.fromJson({
        'result': 'A future provider label',
        'confidence': 101,
        'summary': 'Invalid',
        'id': 'scan-789',
        'timestamp': '2026-10-29T12:00:00+00:00',
      }),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('splash falls back to sign-in when video playback is unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const SkinAIApp(),
      ),
    );
    await tester.pump();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}

class FakeEmailPasswordAuthGateway implements EmailPasswordAuthGateway {
  AuthUserInfo? _user;
  bool accountCreated = false;
  bool emailVerified = false;
  bool verifyOnReload = false;
  int createCalls = 0;
  int signInCalls = 0;
  int verificationCalls = 0;
  int signOutCalls = 0;
  String? languageCode;
  FirebaseAuthException? verificationError;

  @override
  AuthUserInfo? get currentUser => _user;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      'test-firebase-id-token';

  @override
  Future<AuthUserInfo?> createAccount({
    required String email,
    required String password,
  }) async {
    createCalls++;
    accountCreated = true;
    _user = AuthUserInfo(
      uid: 'firebase-user-1',
      email: email,
      displayName: null,
      emailVerified: emailVerified,
    );
    return _user;
  }

  @override
  Future<void> updateDisplayName(String name) async {
    final user = _user!;
    _user = AuthUserInfo(
      email: user.email,
      displayName: name,
      emailVerified: user.emailVerified,
    );
  }

  @override
  Future<AuthUserInfo?> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    if (email != 'person@example.com' || password != 'password123') {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    _user = AuthUserInfo(
      uid: 'firebase-user-1',
      email: email,
      displayName: null,
      emailVerified: emailVerified,
    );
    return _user;
  }

  @override
  Future<void> reloadCurrentUser() async {
    if (verifyOnReload && _user != null) {
      emailVerified = true;
      _user = AuthUserInfo(
        email: _user!.email,
        displayName: _user!.displayName,
        emailVerified: true,
      );
    }
  }

  @override
  Future<void> setLanguageCode(String? languageCode) async {
    this.languageCode = languageCode;
  }

  @override
  Future<void> sendEmailVerification() async {
    verificationCalls++;
    final error = verificationError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
  }
}
