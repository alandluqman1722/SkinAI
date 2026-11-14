import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:crypto/crypto.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/auth/social_auth_service.dart';
import 'package:skin_ai/multipart_upload.dart';
import 'package:skin_ai/scan_report.dart';
import 'package:skin_ai/medical_scan_api.dart';
import 'package:skin_ai/skin_scan/body_region_selector.dart';
import 'package:skin_ai/local_reminder_service.dart';
import 'package:skin_ai/routines/home_widget_bridge.dart';
import 'package:skin_ai/routines/routine_controller.dart';
import 'package:skin_ai/routines/routine_models.dart';
import 'package:skin_ai/routines/routine_screens.dart';
import 'package:skin_ai/notifications/notification_screens.dart';
import 'package:skin_ai/skinchat/screens/skinchat_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/localization/locale_helper.dart';

export 'localization/language_controller.dart'
    show AppLang, AppLangLocale, langNames;

// SkinAI Flutter client with Kurdish, English, and Arabic UI support.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkinAIStartup());
}

class SkinAIStartup extends StatefulWidget {
  const SkinAIStartup({super.key});

  @override
  State<SkinAIStartup> createState() => _SkinAIStartupState();
}

class _SkinAIStartupState extends State<SkinAIStartup> {
  AppController? _controller;
  Object? _startupError;
  bool _initializing = false;
  Timer? _startupTimeout;
  int _initializationAttempt = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    final attempt = ++_initializationAttempt;
    if (mounted) {
      setState(() {
        _controller = null;
        _startupError = null;
      });
    }
    _startupTimeout?.cancel();
    _startupTimeout = Timer(const Duration(seconds: 30), () {
      if (!mounted || attempt != _initializationAttempt) return;
      _initializing = false;
      _initializationAttempt++;
      setState(
        () => _startupError = TimeoutException(
          'App initialization exceeded 30 seconds.',
        ),
      );
    });

    FirebaseAuth? firebaseAuth;
    String? firebaseSetupError;
    if (FirebaseClientConfig.isConfigured) {
      try {
        await Firebase.initializeApp(options: FirebaseClientConfig.options)
            .timeout(const Duration(seconds: 20));
        firebaseAuth = FirebaseAuth.instance;
      } on FirebaseException catch (error) {
        firebaseSetupError = error.code;
        debugPrint('Firebase initialization failed: ${error.code}');
      } on Object catch (error, stackTrace) {
        firebaseSetupError = error.runtimeType.toString();
        debugPrint('Firebase initialization failed: $error\n$stackTrace');
      }
    } else {
      firebaseSetupError = FirebaseClientConfig.configurationError;
    }

    try {
      final controller = AppController(
        auth: firebaseAuth,
        authSetupError: firebaseSetupError,
        widgetBridge: HomeWidgetBridge(),
      );
      await controller.init();
      if (mounted && attempt == _initializationAttempt) {
        setState(() => _controller = controller);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('SkinAI startup failed: $error\n$stackTrace');
      if (mounted && attempt == _initializationAttempt) {
        setState(() => _startupError = error);
      }
    } finally {
      if (attempt == _initializationAttempt) {
        _initializing = false;
        _startupTimeout?.cancel();
      }
    }
  }

  @override
  void dispose() {
    _startupTimeout?.cancel();
    _initializationAttempt++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return AppScope(
        controller: controller,
        child: const SkinAIApp(),
      );
    }
    return _StartupScreen(
      error: _startupError,
      onRetry: _initialize,
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({required this.error, required this.onRetry});

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final localizations = AppLocalizations.forLanguageCode('en');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SkinAI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050714),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066FF),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF050714),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/logo.png',
                    width: 104,
                    height: 104,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.face_retouching_natural,
                      size: 88,
                      color: Color(0xFF00D4FF),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'SkinAI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (hasError) ...[
                    Text(
                      localizations.text('startupErrorBody'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFCBD5E1)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(localizations.text('tryAgain')),
                    ),
                  ] else
                    const CircularProgressIndicator(
                      color: Color(0xFF00D4FF),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FirebaseClientConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const androidApiKey =
      String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const googleSignInWebClientId =
      String.fromEnvironment('GOOGLE_SIGN_IN_WEB_CLIENT_ID');
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

  static String? get configurationError {
    if (projectId.isEmpty) {
      return 'Firebase options were not passed to this run. Stop the app and launch “SkinAI (Firebase configured)” from VS Code Run and Debug, or run: flutter run --dart-define-from-file=firebase.config.json';
    }
    if (projectId != 'skinai-b0465') {
      return 'The configured Firebase project does not match SkinAI (skinai-b0465). Check FIREBASE_PROJECT_ID in firebase.config.json.';
    }
    if (messagingSenderId.isEmpty) {
      return 'Firebase messaging sender ID is missing.';
    }
    if (kIsWeb) {
      if (apiKey.isEmpty || appId.isEmpty || authDomain.isEmpty) {
        return 'Firebase Web app options are incomplete.';
      }
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (androidApiKey.isEmpty || androidAppId.isEmpty) {
        return 'Register the Android app in Firebase and pass FIREBASE_ANDROID_API_KEY and FIREBASE_ANDROID_APP_ID.';
      }
      return null;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (iosApiKey.isEmpty || iosAppId.isEmpty || iosBundleId.isEmpty) {
        return 'Register the iOS app in Firebase and pass FIREBASE_IOS_API_KEY, FIREBASE_IOS_APP_ID, and FIREBASE_IOS_BUNDLE_ID.';
      }
      return null;
    }
    return 'Firebase options are not configured for this platform.';
  }

  static bool get isConfigured => configurationError == null;

  static FirebaseOptions get options {
    final error = configurationError;
    if (error != null) throw StateError(error);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return FirebaseOptions(
      apiKey: isAndroid ? androidApiKey : (isIos ? iosApiKey : apiKey),
      appId: isAndroid ? androidAppId : (isIos ? iosAppId : appId),
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: kIsWeb && authDomain.isNotEmpty ? authDomain : null,
      iosBundleId: isIos ? iosBundleId : null,
    );
  }
}

// -------------------- Brand colors --------------------

const Color cyan = Color(0xFF00E5FF);
const Color blue = Color(0xFF087CFF);
const Color purple = Color(0xFF963BFF);
const List<Color> brandGradient = [Color(0xFF00B8D9), blue, purple];

// -------------------- Theme palette (dark + light) --------------------

class Pal {
  final Color bg, panel, input, text, sub, hint, border, accent, nav, snack;
  final List<Color> bgGradient;
  final List<Color> hero;
  final double orb;

  const Pal({
    required this.bg,
    required this.panel,
    required this.input,
    required this.text,
    required this.sub,
    required this.hint,
    required this.border,
    required this.accent,
    required this.nav,
    required this.snack,
    required this.bgGradient,
    required this.hero,
    required this.orb,
  });

  Pal withAccent(Color value) => Pal(
        bg: bg,
        panel: panel,
        input: input,
        text: text,
        sub: sub,
        hint: hint,
        border: border,
        accent: value,
        nav: nav,
        snack: snack,
        bgGradient: bgGradient,
        hero: hero,
        orb: orb,
      );

  static const dark = Pal(
    bg: Color(0xFF050714),
    panel: Color(0xFF10172A),
    input: Color(0xFF080E1D),
    text: Colors.white,
    sub: Color(0xFFB5C4DE),
    hint: Color(0xFF7F8CA8),
    border: Color(0x24FFFFFF),
    accent: cyan,
    nav: Color(0xFF0B1021),
    snack: Color(0xFF17243B),
    bgGradient: [
      Color(0xFF030611),
      Color(0xFF0A1025),
      Color(0xFF100824),
      Color(0xFF030611),
    ],
    hero: [Color(0xFF103D70), Color(0xFF282060), Color(0xFF11162B)],
    orb: 0.19,
  );

  static const light = Pal(
    bg: Color(0xFFF3F6FF),
    panel: Colors.white,
    input: Color(0xFFF0F4FC),
    text: Color(0xFF0B1226),
    sub: Color(0xFF5A6784),
    hint: Color(0xFF8A94AD),
    border: Color(0x1F0B1226),
    accent: Color(0xFF0A7BD8),
    nav: Colors.white,
    snack: Colors.white,
    bgGradient: [
      Color(0xFFF7F9FF),
      Color(0xFFE8F0FF),
      Color(0xFFF1E9FF),
      Color(0xFFF7F9FF),
    ],
    hero: [Color(0xFF1C7BEA), Color(0xFF5B47D6), Color(0xFF8A3FE0)],
    orb: 0.28,
  );

  static Pal of(BuildContext context) {
    final palette =
        Theme.of(context).brightness == Brightness.dark ? dark : light;
    return palette.withAccent(AppScope.of(context).accentColor);
  }

  static Pal settingsOf(BuildContext context) {
    final base = of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pal(
      bg: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF5F7FB),
      panel: isDark ? const Color(0xFF151C2C) : const Color(0xFFFFFFFF),
      input: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      text: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
      sub: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      hint: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      border: isDark ? const Color(0xFF263147) : const Color(0xFFE2E8F0),
      accent: base.accent,
      nav: base.nav,
      snack: isDark ? const Color(0xFF151C2C) : const Color(0xFFFFFFFF),
      bgGradient: [isDark ? const Color(0xFF0B0F19) : const Color(0xFFF5F7FB)],
      hero: base.hero,
      orb: base.orb,
    );
  }
}

ThemeData buildTheme(Brightness b, {Color? accentColor}) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final accent = accentColor ?? p.accent;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.snack,
      contentTextStyle: TextStyle(color: p.text),
    ),
  );
}

// -------------------- App state: language + theme --------------------

// -------------------- Database models --------------------

class UserRecord {
  final String uid, name, email;
  final List<int> answers; // option index per question, -1 = not answered
  final int createdAt;

  const UserRecord({
    this.uid = '',
    required this.name,
    required this.email,
    required this.answers,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'email': email,
        'answers': answers,
        'createdAt': createdAt,
      };

  factory UserRecord.fromJson(Map<String, dynamic> j) => UserRecord(
        uid: (j['uid'] as String?) ?? '',
        name: j['name'] as String,
        email: j['email'] as String,
        answers:
            ((j['answers'] as List?) ?? const []).map((e) => e as int).toList(),
        createdAt: (j['createdAt'] as int?) ?? 0,
      );
}

enum AuthError {
  none,
  noAccount,
  wrongPassword,
  accountDisabled,
  emailPasswordDisabled,
  exists,
  serviceUnavailable,
  emailNotVerified,
  verificationRequired,
  verificationResent,
  alreadyVerified,
  verificationNetworkError,
  verificationTooManyRequests,
  verificationFailed,
  profileUpdateFailed,
  weakPassword,
  invalidEmail,
  tooManyRequests,
  networkError,
  signOutFailed,
  authCancelled,
  accountLinkRequired,
  accountConflict,
  providerUnavailable,
  authFailed,
}

class AuthUserInfo {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final DateTime? creationTime;
  final bool emailVerified;

  const AuthUserInfo({
    this.uid = '',
    required this.email,
    required this.displayName,
    required this.emailVerified,
    this.photoUrl,
    this.creationTime,
  });
}

abstract interface class EmailPasswordAuthGateway {
  AuthUserInfo? get currentUser;
  Future<String?> getIdToken({bool forceRefresh = false});
  Future<AuthUserInfo?> createAccount({
    required String email,
    required String password,
  });
  Future<void> updateDisplayName(String name);
  Future<AuthUserInfo?> signIn({
    required String email,
    required String password,
  });
  Future<void> reloadCurrentUser();
  Future<void> setLanguageCode(String? languageCode);
  Future<void> sendEmailVerification();
  Future<void> sendPasswordResetEmail(String email);
  Future<void> signOut();
}

class FirebaseEmailPasswordAuthGateway implements EmailPasswordAuthGateway {
  final FirebaseAuth _auth;

  FirebaseEmailPasswordAuthGateway(this._auth);

  AuthUserInfo? _userInfo(User? user) => user == null
      ? null
      : AuthUserInfo(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          emailVerified: user.emailVerified,
          photoUrl: user.photoURL,
          creationTime: user.metadata.creationTime,
        );

  @override
  AuthUserInfo? get currentUser => _userInfo(_auth.currentUser);

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);

  @override
  Future<AuthUserInfo?> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _userInfo(credential.user);
  }

  @override
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.updateDisplayName(name);
  }

  @override
  Future<AuthUserInfo?> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _userInfo(credential.user);
  }

  @override
  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  @override
  Future<void> setLanguageCode(String? languageCode) =>
      _auth.setLanguageCode(languageCode);

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.sendEmailVerification();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

String _authErrorText(AppController controller, AuthError error) {
  return switch (error) {
    AuthError.noAccount => controller.t('errNoAccount'),
    AuthError.wrongPassword => controller.t('errWrongPass'),
    AuthError.accountDisabled => controller.t('accountDisabled'),
    AuthError.emailPasswordDisabled => controller.t('emailPasswordDisabled'),
    AuthError.exists => controller.t('errExists'),
    AuthError.emailNotVerified => controller.t('emailNotVerified'),
    AuthError.verificationFailed => controller.t('verificationFailed'),
    AuthError.profileUpdateFailed => controller.t('profileUpdateFailed'),
    AuthError.weakPassword => controller.t('errPass'),
    AuthError.invalidEmail => controller.t('errEmail'),
    AuthError.tooManyRequests => controller.t('authTooManyRequests'),
    AuthError.networkError => controller.t('authNetworkError'),
    AuthError.serviceUnavailable => controller.authSetupMessage,
    AuthError.authCancelled => controller.t('authCancelled'),
    AuthError.accountLinkRequired => controller.t('accountLinkRequired'),
    AuthError.accountConflict => controller.t('accountConflict'),
    AuthError.providerUnavailable => controller.t('providerUnavailable'),
    AuthError.authFailed => controller.t('authFailed'),
    AuthError.verificationRequired => controller.t('verificationSent'),
    AuthError.verificationResent => controller.t('verificationResent'),
    AuthError.alreadyVerified => controller.t('alreadyVerified'),
    AuthError.verificationNetworkError =>
      controller.t('verificationNetworkError'),
    AuthError.verificationTooManyRequests =>
      controller.t('verificationTooManyRequests'),
    AuthError.signOutFailed => controller.t('verificationSignOutFailed'),
    AuthError.none => '',
  };
}

// -------------------- AI server (FastAPI) --------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
}

class ScanResult {
  final String cls;
  final double confidence;
  final String summary;
  final String scanId;
  final DateTime timestamp;

  const ScanResult({
    required this.cls,
    required this.confidence,
    required this.summary,
    required this.scanId,
    required this.timestamp,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    final result = json['result'];
    final confidenceValue = json['confidence'];
    final summaryValue = json['summary'];
    final idValue = json['id'];
    final timestampValue = json['timestamp'];
    final parsedTimestamp =
        timestampValue is String ? DateTime.tryParse(timestampValue) : null;

    if (result is! String ||
        result.trim().isEmpty ||
        confidenceValue is! num ||
        !confidenceValue.isFinite ||
        confidenceValue < 0 ||
        confidenceValue > 100 ||
        summaryValue is! String ||
        idValue is! String ||
        idValue.isEmpty ||
        parsedTimestamp == null) {
      throw ApiException(
        'The AI server returned an invalid analysis.',
        statusCode: 502,
      );
    }

    final confidencePercent =
        confidenceValue <= 1 ? confidenceValue * 100 : confidenceValue;
    return ScanResult(
      cls: result,
      confidence: confidencePercent.toDouble(),
      summary: summaryValue,
      scanId: idValue,
      timestamp: parsedTimestamp,
    );
  }
}

class ScanRecord {
  final String cls;
  final double conf;
  final bool mel;
  final int ts;
  final String? bodyPart;
  final String? bodySubregion;
  final String? bodySide;
  final String? concernType;
  final String? userId;
  final String? analysisId;
  final String? summary;
  final String? bodyLocation;
  final String? notes;
  final bool accountRecord;
  final bool hasOriginalImage;
  const ScanRecord({
    required this.cls,
    required this.conf,
    required this.mel,
    required this.ts,
    this.bodyPart,
    this.bodySubregion,
    this.bodySide,
    this.concernType,
    this.userId,
    this.analysisId,
    this.summary,
    this.bodyLocation,
    this.notes,
    this.accountRecord = false,
    this.hasOriginalImage = false,
  });

  Map<String, dynamic> toJson() => {
        'cls': cls,
        'conf': conf,
        'mel': mel,
        'ts': ts,
        'bodyPart': bodyPart,
        'bodySubregion': bodySubregion,
        'bodySide': bodySide,
        'concernType': concernType,
        'userId': userId,
        'analysisId': analysisId,
        'summary': summary,
        'bodyLocation': bodyLocation,
        'notes': notes,
        'accountRecord': accountRecord,
        'hasOriginalImage': hasOriginalImage,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
        cls: j['cls'] as String,
        conf: (j['conf'] as num).toDouble(),
        mel: j['mel'] == true,
        ts: (j['ts'] as num).toInt(),
        bodyPart: j['bodyPart'] as String?,
        bodySubregion: j['bodySubregion'] as String?,
        bodySide: j['bodySide'] as String?,
        concernType: j['concernType'] as String?,
        userId: j['userId'] as String?,
        analysisId: j['analysisId'] as String?,
        summary: j['summary'] as String?,
        bodyLocation: j['bodyLocation'] as String?,
        notes: j['notes'] as String?,
        accountRecord: j['accountRecord'] == true,
        hasOriginalImage: j['hasOriginalImage'] == true,
      );

  factory ScanRecord.fromMedicalRecord(MedicalScanRecord record) => ScanRecord(
        cls: record.result,
        conf: record.confidence,
        mel: false,
        ts: record.createdAt.millisecondsSinceEpoch,
        analysisId: record.id,
        summary: record.explanation,
        bodyLocation: record.bodyLocation,
        notes: record.notes,
        accountRecord: true,
        hasOriginalImage: record.hasOriginalImage,
      );
}

class SkinApi {
  static Future<void> testConnection(
    String baseUrl, {
    required String languageCode,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/health');
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw ApiException('Configure a valid HTTP or HTTPS AI API URL.');
    }

    try {
      final response = await http.get(
        uri,
        headers: {'Accept-Language': languageCode},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'AI server health check failed.',
          statusCode: response.statusCode,
        );
      }
    } on ApiException {
      rethrow;
    } on Exception {
      throw ApiException('Could not connect to the AI server.');
    }
  }

  static Future<ScanResult> analyze(
    String baseUrl,
    Uint8List bytes,
    String filename, {
    required String idToken,
    bool saveHistory = false,
    String? location,
    String? duration,
    String? details,
    String? changeOverTime,
    void Function(int sentBytes, int totalBytes)? onUploadProgress,
    http.Client? client,
  }) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    if (bytes.isEmpty) {
      throw ApiException('The selected image is empty.', statusCode: 400);
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw ApiException(
        'The image exceeds the 10 MB upload limit.',
        statusCode: 413,
      );
    }
    if (idToken.trim().isEmpty) {
      throw ApiException(
        'A signed-in account is required to analyze images.',
        statusCode: 401,
      );
    }

    final apiUri = Uri.tryParse('$base/analyze');
    if (apiUri == null ||
        !apiUri.hasAuthority ||
        !{'http', 'https'}.contains(apiUri.scheme) ||
        apiUri.host.isEmpty) {
      throw ApiException(
        'Configure a valid HTTP or HTTPS AI API URL.',
        statusCode: 400,
      );
    }

    final name = filename.isEmpty ? 'scan.jpg' : filename;
    final lowerName = name.toLowerCase();
    final extension = lowerName.contains('.')
        ? lowerName.substring(lowerName.lastIndexOf('.') + 1)
        : '';
    final mimeType = switch (extension) {
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'gif' => MediaType('image', 'gif'),
      'bmp' => MediaType('image', 'bmp'),
      'tif' || 'tiff' => MediaType('image', 'tiff'),
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      _ => MediaType('application', 'octet-stream'),
    };

    final request = http.MultipartRequest('POST', apiUri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $idToken',
      });

    request.headers['Authorization'] = 'Bearer $idToken';

    final optionalFields = {
      if (saveHistory) 'save_history': 'true',
      'skin_illness_location': location,
      'symptoms_duration': duration,
      'symptoms_details': details,
      'symptoms_change_over_time': changeOverTime,
    };
    request.fields.addAll({
      for (final entry in optionalFields.entries)
        if (entry.value != null && entry.value!.trim().isNotEmpty)
          entry.key: entry.value!.trim(),
    });

    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: name,
        contentType: mimeType,
      ),
    );

    final uploadClient = client ?? http.Client();
    try {
      final streamed = await sendMultipartWithProgress(
        uploadClient,
        request,
        onProgress: onUploadProgress,
      ).timeout(const Duration(seconds: 125));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 125));

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Expected an object.');
        }
        data = decoded;
      } on FormatException {
        throw ApiException(
          'The AI server returned an unexpected response.',
          statusCode: response.statusCode,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'The AI request could not be completed.',
          statusCode: response.statusCode,
        );
      }

      return ScanResult.fromJson(data);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'The screening request timed out.',
        statusCode: 504,
      );
    } on http.ClientException {
      throw ApiException('Could not connect to the AI server.');
    } on Exception {
      throw ApiException('Could not connect to the AI server.');
    } finally {
      if (client == null) uploadClient.close();
    }
  }
}

/// First item = question, the rest = options. Same order in every language.
class Question {
  final IconData icon;
  final List<String> en, ku, ar;
  const Question(this.icon, this.en, this.ku, this.ar);

  List<String> of(String code) => code == 'ku' ? ku : (code == 'ar' ? ar : en);
}

const List<Question> quiz = [
  Question(
    Icons.cake_outlined,
    [
      'What is your age group?',
      'Under 18',
      '18 – 25',
      '26 – 35',
      '36 – 50',
      'Over 50'
    ],
    [
      'تەمەنت لە چ پۆلێکدایە؟',
      'کەمتر لە 18',
      '18 – 25',
      '26 – 35',
      '36 – 50',
      'سەروو 50'
    ],
    [
      'ما هي فئتك العمرية؟',
      'أقل من 18',
      '18 – 25',
      '26 – 35',
      '36 – 50',
      'أكثر من 50'
    ],
  ),
  Question(
    Icons.wc_rounded,
    ['What is your gender?', 'Male', 'Female', 'Prefer not to say'],
    ['ڕەگەزت چییە؟', 'نێر', 'مێ', 'نامەوێت بیڵێم'],
    ['ما هو جنسك؟', 'ذكر', 'أنثى', 'أفضل عدم الذكر'],
  ),
  Question(
    Icons.face_retouching_natural,
    [
      'What is your skin type?',
      'Oily',
      'Dry',
      'Combination',
      'Normal',
      'Not sure'
    ],
    ['جۆری پێستت چییە؟', 'چەوری', 'وشک', 'تێکەڵ', 'ئاسایی', 'دڵنیا نیم'],
    ['ما نوع بشرتك؟', 'دهنية', 'جافة', 'مختلطة', 'عادية', 'لست متأكدًا'],
  ),
  Question(
    Icons.wb_sunny_outlined,
    [
      'How does your skin react to the sun?',
      'Burns easily',
      'Burns, then tans',
      'Tans easily',
      'Rarely burns'
    ],
    [
      'پێستت چۆن کاردانەوە دەکات بەرامبەر بە خۆر؟',
      'بە ئاسانی دەسووتێت',
      'دەسووتێت پاشان قاوەیی دەبێت',
      'بە ئاسانی قاوەیی دەبێت',
      'بە دەگمەن دەسووتێت'
    ],
    [
      'كيف تتفاعل بشرتك مع الشمس؟',
      'تحترق بسهولة',
      'تحترق ثم تتسمر',
      'تتسمر بسهولة',
      'نادرًا ما تحترق'
    ],
  ),
  Question(
    Icons.flag_outlined,
    [
      'What is your main goal?',
      'Check a mole or spot',
      'Track skin changes',
      'Learn about skin health',
      'Use it as a doctor'
    ],
    [
      'ئامانجی سەرەکیت چییە؟',
      'پشکنینی خاڵ یان لەکە',
      'بەدواداچوونی گۆڕانکارییەکانی پێست',
      'فێربوون دەربارەی تەندروستی پێست',
      'بەکارهێنان وەک دکتۆر'
    ],
    [
      'ما هدفك الرئيسي؟',
      'فحص شامة أو بقعة',
      'تتبع تغيّرات البشرة',
      'التعرف على صحة البشرة',
      'استخدامه كطبيب'
    ],
  ),
  Question(
    Icons.healing_outlined,
    [
      'Do you have a skin concern right now?',
      'A mole or dark spot',
      'Acne',
      'Rash or itching',
      'Dryness',
      'None'
    ],
    [
      'ئێستا کێشەیەکی پێستت هەیە؟',
      'خاڵ یان لەکەی تاریک',
      'ئەکنی',
      'دانە یان خورانی پێست',
      'وشکی',
      'هیچ'
    ],
    [
      'هل لديك مشكلة جلدية حاليًا؟',
      'شامة أو بقعة داكنة',
      'حب الشباب',
      'طفح أو حكة',
      'جفاف',
      'لا شيء'
    ],
  ),
  Question(
    Icons.family_restroom_rounded,
    ['Any family history of skin cancer?', 'Yes', 'No', 'Not sure'],
    ['مێژووی خێزانی شێرپەنجەی پێستت هەیە؟', 'بەڵێ', 'نەخێر', 'دڵنیا نیم'],
    ['هل لديك تاريخ عائلي لسرطان الجلد؟', 'نعم', 'لا', 'لست متأكدًا'],
  ),
  Question(
    Icons.shield_outlined,
    [
      'How often do you use sunscreen?',
      'Every day',
      'Sometimes',
      'Rarely',
      'Never'
    ],
    [
      'چەند جار سەنسکرین بەکاردەهێنیت؟',
      'هەموو ڕۆژێک',
      'هەندێک جار',
      'بە دەگمەن',
      'هەرگیز'
    ],
    ['كم مرة تستخدم واقي الشمس؟', 'كل يوم', 'أحيانًا', 'نادرًا', 'أبدًا'],
  ),
  Question(
    Icons.schedule_rounded,
    [
      'How long are you in the sun daily?',
      'Less than 1 hour',
      '1 – 3 hours',
      'More than 3 hours'
    ],
    [
      'ڕۆژانە چەند کات لە ژێر خۆر دەبیت؟',
      'کەمتر لە کاتژمێرێک',
      '1 – 3 کاتژمێر',
      'زیاتر لە 3 کاتژمێر'
    ],
    [
      'كم تقضي من الوقت تحت الشمس يوميًا؟',
      'أقل من ساعة',
      '1 – 3 ساعات',
      'أكثر من 3 ساعات'
    ],
  ),
  Question(
    Icons.campaign_outlined,
    [
      'How did you hear about Skin AI?',
      'A friend',
      'Social media',
      'A doctor',
      'Other'
    ],
    [
      'چۆن لە Skin AI ئاگادار بویت؟',
      'هاوڕێیەک',
      'تۆڕە کۆمەڵایەتییەکان',
      'دکتۆرێک',
      'شتێکی تر'
    ],
    ['كيف سمعت عن Skin AI؟', 'صديق', 'وسائل التواصل الاجتماعي', 'طبيب', 'أخرى'],
  ),
];

class AppController extends ChangeNotifier {
  AppController({
    FirebaseAuth? auth,
    EmailPasswordAuthGateway? authGateway,
    ReminderService? reminderService,
    RoutineWidgetBridge? widgetBridge,
    RoutineScheduler? routineScheduler,
    SocialAuthService? socialAuthService,
    this.authSetupError,
  })  : _socialAuth = socialAuthService ??
        (auth == null
            ? null
            : SocialAuthService(
                auth,
                webClientId: FirebaseClientConfig.googleSignInWebClientId,
              )),
        _auth = authGateway ??
            (auth == null ? null : FirebaseEmailPasswordAuthGateway(auth)),
        _reminderService = reminderService ?? LocalReminderService(),
        routineController = RoutineController(
          scheduler: routineScheduler,
          widgetBridge: widgetBridge,
        ) {
    languageController.addListener(notifyListeners);
  }

  final LanguageController languageController = LanguageController();
  AppLang get lang => languageController.language;
  ThemeMode themeMode = ThemeMode.dark;
  String skincareGoal = 'hydration';
  int reminderHour = 8;
  int reminderMinute = 0;
  String skinType = 'combination';
  bool notificationsEnabled = false;
  Color accentColor = const Color(0xFF0066FF);

  // ----- database (stored on the device with shared_preferences) -----
  SharedPreferences? _prefs;
  UserRecord? currentUser;
  List<int> pendingAnswers = List<int>.filled(quiz.length, -1);
  final List<ScanRecord> _localScans = [];
  List<ScanRecord> _remoteScans = [];
  List<ScanRecord> get scans {
    final remoteIds =
        _remoteScans.map((scan) => scan.analysisId).whereType<String>().toSet();
    final combined = [
      ..._remoteScans,
      ..._localScans.where(
        (scan) =>
            !scan.accountRecord ||
            scan.analysisId == null ||
            !remoteIds.contains(scan.analysisId),
      ),
    ]..sort((first, second) => second.ts.compareTo(first.ts));
    return combined;
  }

  String serverUrl = '';
  bool onboardingCompleted = false;
  bool retainHistory = false;
  final SocialAuthService? _socialAuth;
  final EmailPasswordAuthGateway? _auth;
  final ReminderService _reminderService;
  final RoutineController routineController;
  final String? authSetupError;
  DateTime? _verificationCooldownUntil;
  bool _verificationRequestInFlight = false;

  String get defaultServer {
    const configuredUrl = String.fromEnvironment('AI_API_URL');
    if (configuredUrl.trim().isNotEmpty) {
      return configuredUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return kIsWeb
        ? 'http://127.0.0.1:8000'
        : (defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:8000'
            : 'http://127.0.0.1:8000');
  }

  String get authSetupMessage {
    if (_auth == null && authSetupError != null && authSetupError!.isNotEmpty) {
      return '${t('firebaseInitFailed')}\n$authSetupError';
    }
    if (_auth == null) return t('firebaseNotConfigured');
    return t('authServiceUnavailable');
  }

  int get verificationCooldownSeconds {
    final remaining = _verificationCooldownUntil?.difference(DateTime.now());
    if (remaining == null || remaining.isNegative) return 0;
    return remaining.inSeconds + (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
  }

  String get userName => currentUser?.name ?? '';
  String get userEmail => currentUser?.email ?? '';
  bool get hasPendingEmailVerification {
    final user = _auth?.currentUser;
    return user != null && !user.emailVerified;
  }

  Future<String?> getFirebaseIdToken({bool forceRefresh = false}) async =>
      _auth?.getIdToken(forceRefresh: forceRefresh);

  String? get profilePhotoUrl {
    final photoUrl = _auth?.currentUser?.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) return photoUrl;
    final email = userEmail.trim().toLowerCase();
    if (email.isEmpty) return null;
    return 'https://www.gravatar.com/avatar/'
        '${md5.convert(utf8.encode(email))}?d=identicon&s=160';
  }

  DateTime? get memberSince => _auth?.currentUser?.creationTime;
  bool get notificationsSupported => _reminderService.isSupported;
  String get initial {
    final n = userName.trim();
    return n.isEmpty ? '?' : String.fromCharCode(n.runes.first).toUpperCase();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    await routineController.init(preferences: prefs);
    routineController.addListener(notifyListeners);

    await languageController.restore(prefs);
    await routineController.setWidgetLanguage(lang.name);
    final savedTheme = prefs.getString('theme');
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.dark,
    );
    skincareGoal = prefs.getString('settings_skincare_goal') ?? 'hydration';
    final savedReminderMinutes =
        prefs.getInt('settings_reminder_minutes') ?? 480;
    reminderHour = savedReminderMinutes ~/ 60;
    reminderMinute = savedReminderMinutes % 60;
    skinType = prefs.getString('settings_skin_type') ?? 'combination';
    notificationsEnabled =
        prefs.getBool('settings_notifications_enabled') ?? false;
    if (routineController.notificationSettings.masterEnabled !=
        notificationsEnabled) {
      await routineController.updateNotificationSettings(
        routineController.notificationSettings.copyWith(
          masterEnabled: notificationsEnabled,
        ),
      );
    }
    accentColor = Color(
      prefs.getInt('settings_accent_color') ??
          const Color(0xFF0066FF).toARGB32(),
    );

    // Older releases stored local-only accounts and treated them as real auth.
    // Remove those credentials and sessions rather than trusting them.
    await prefs.remove('users');
    await prefs.remove('session');
    final firebaseUser = _auth?.currentUser;
    if (firebaseUser != null && firebaseUser.emailVerified) {
      await _setCurrentUser(
        AuthUserInfo(
          uid: firebaseUser.uid,
          email: firebaseUser.email,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoUrl,
          creationTime: firebaseUser.creationTime,
          emailVerified: firebaseUser.emailVerified,
        ),
      );
    }
    onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    retainHistory = prefs.getBool('retain_analysis_history') ?? false;

    serverUrl = prefs.getString('server') ?? defaultServer;
    _loadScans();
    if (notificationsEnabled) {
      if (notificationsSupported) {
        await _syncDailyReminder(routineController.notificationSettings);
      } else {
        notificationsEnabled = false;
        await prefs.setBool('settings_notifications_enabled', false);
        await routineController.updateNotificationSettings(
          routineController.notificationSettings.copyWith(
            masterEnabled: false,
          ),
        );
        await _reminderService.cancel();
      }
    }
  }

  void _loadScans() {
    _localScans.clear();
    _remoteScans = [];
    final e = currentUser?.email;
    if (e == null) return;
    final raw = _prefs?.getString('scans_$e');
    if (raw == null) return;
    try {
      _localScans.addAll((jsonDecode(raw) as List)
          .map((x) => ScanRecord.fromJson(x as Map<String, dynamic>))
          .toList());
    } catch (_) {
      _localScans.clear();
    }
  }

  Future<void> _saveScans([List<ScanRecord>? records]) async {
    final e = currentUser?.email;
    if (e == null) return;
    await _prefs?.setString(
      'scans_$e',
      jsonEncode((records ?? _localScans).map((x) => x.toJson()).toList()),
    );
  }

  Future<void> addScan(ScanRecord r) async {
    final updated = [r, ..._localScans].take(100).toList();
    await _saveScans(updated);
    _localScans
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  Future<bool> addAccountScan(ScanRecord record) async {
    _remoteScans = [
      record,
      ..._remoteScans.where((scan) => scan.analysisId != record.analysisId),
    ];
    if (retainHistory) {
      final updated = [
        record,
        ..._localScans.where((scan) => scan.analysisId != record.analysisId),
      ].take(100).toList();
      try {
        await _saveScans(updated);
      } on Exception {
        notifyListeners();
        return false;
      }
      _localScans
        ..clear()
        ..addAll(updated);
    }
    notifyListeners();
    return true;
  }

  Future<T> _withMedicalScanApi<T>(
    Future<T> Function(MedicalScanApi api) action,
  ) async {
    Future<T> send({required bool forceRefresh}) async {
      final idToken = await getFirebaseIdToken(forceRefresh: forceRefresh);
      if (idToken == null || idToken.isEmpty) {
        throw const MedicalScanApiException(
          'A signed-in account is required to access scan history.',
          statusCode: 401,
        );
      }
      final client = http.Client();
      try {
        return await action(
          MedicalScanApi(
            baseUrl: serverUrl,
            idToken: idToken,
            client: client,
          ),
        );
      } finally {
        client.close();
      }
    }

    try {
      return await send(forceRefresh: false);
    } on MedicalScanApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      try {
        return await send(forceRefresh: true);
      } on FirebaseException {
        throw const MedicalScanApiException(
          'Your session expired. Sign in again to access scan history.',
          statusCode: 401,
        );
      }
    }
  }

  Future<bool> originalImageStorageConfigured() =>
      _withMedicalScanApi((api) => api.originalImageStorageConfigured());

  Future<void> refreshAccountScans() async {
    final records = await _withMedicalScanApi((api) => api.listScans());
    _remoteScans = records.map(ScanRecord.fromMedicalRecord).toList();
    notifyListeners();
  }

  Future<void> updateAccountScan(
    ScanRecord record, {
    String? bodyLocation,
    String? notes,
  }) async {
    final scanId = record.analysisId;
    if (scanId == null || scanId.isEmpty) {
      throw StateError('The account scan is missing its record identifier.');
    }
    await _withMedicalScanApi(
      (api) => api.updateScan(
        scanId: scanId,
        bodyLocation: bodyLocation,
        notes: notes,
      ),
    );
    ScanRecord updated(ScanRecord scan) => scan.analysisId == scanId
        ? ScanRecord(
            cls: scan.cls,
            conf: scan.conf,
            mel: scan.mel,
            ts: scan.ts,
            bodyPart: scan.bodyPart,
            bodySubregion: scan.bodySubregion,
            bodySide: scan.bodySide,
            concernType: scan.concernType,
            userId: scan.userId,
            analysisId: scan.analysisId,
            summary: scan.summary,
            bodyLocation: bodyLocation ?? scan.bodyLocation,
            notes: notes ?? scan.notes,
            accountRecord: scan.accountRecord,
            hasOriginalImage: scan.hasOriginalImage,
          )
        : scan;
    _remoteScans = _remoteScans.map(updated).toList();
    final local = _localScans.map(updated).toList();
    await _saveScans(local);
    _localScans
      ..clear()
      ..addAll(local);
    notifyListeners();
  }

  Future<Uint8List> getAccountScanImage(ScanRecord record) {
    final scanId = record.analysisId;
    if (scanId == null || scanId.isEmpty) {
      throw StateError('The account scan is missing its record identifier.');
    }
    return _withMedicalScanApi((api) => api.originalImage(scanId));
  }

  Future<bool> storeAccountScanImage(
    ScanRecord record, {
    required Uint8List bytes,
    required String filename,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final scanId = record.analysisId;
    if (scanId == null || scanId.isEmpty) {
      throw StateError('The account scan is missing its record identifier.');
    }
    await _withMedicalScanApi(
      (api) => api.storeOriginalImage(
        scanId: scanId,
        bytes: bytes,
        filename: filename,
        onProgress: onProgress,
      ),
    );
    ScanRecord markStored(ScanRecord scan) => scan.analysisId == scanId
        ? ScanRecord(
            cls: scan.cls,
            conf: scan.conf,
            mel: scan.mel,
            ts: scan.ts,
            bodyPart: scan.bodyPart,
            bodySubregion: scan.bodySubregion,
            bodySide: scan.bodySide,
            concernType: scan.concernType,
            userId: scan.userId,
            analysisId: scan.analysisId,
            summary: scan.summary,
            bodyLocation: scan.bodyLocation,
            notes: scan.notes,
            accountRecord: true,
            hasOriginalImage: true,
          )
        : scan;
    _remoteScans = _remoteScans.map(markStored).toList();
    final local = _localScans.map(markStored).toList();
    try {
      await _saveScans(local);
    } on Exception {
      _localScans
        ..clear()
        ..addAll(local);
      notifyListeners();
      return false;
    }
    _localScans
      ..clear()
      ..addAll(local);
    notifyListeners();
    return true;
  }

  Future<void> clearScans() async {
    await _saveScans(const []);
    _localScans.clear();
    notifyListeners();
  }

  Future<void> removeScan(ScanRecord record) async {
    final scanId = record.analysisId;
    if (record.accountRecord) {
      if (scanId == null || scanId.isEmpty) {
        throw StateError('The account scan is missing its record identifier.');
      }
      await _withMedicalScanApi((api) => api.deleteScan(scanId));
      _remoteScans.removeWhere((scan) => scan.analysisId == scanId);
    }
    final updated = _localScans.where((scan) {
      if (record.accountRecord && scanId != null) {
        return scan.analysisId != scanId;
      }
      return scan.ts != record.ts || scan.analysisId != record.analysisId;
    }).toList();
    await _saveScans(updated);
    _localScans
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  Future<void> setServer(String value) async {
    await _prefs?.setString('server', value);
    serverUrl = value;
    notifyListeners();
  }

  Future<AuthError> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) return AuthError.serviceUnavailable;
    AuthUserInfo? user;
    try {
      user = await auth.createAccount(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      return _mapFirebaseAuthError(error);
    } on FirebaseException catch (error) {
      return _mapFirebaseAuthError(error);
    }

    if (user == null) {
      if (!await _signOutAfterAuth(auth)) return AuthError.signOutFailed;
      return AuthError.serviceUnavailable;
    }
    try {
      await auth.updateDisplayName(name.trim());
    } on FirebaseException {
      if (!await _signOutAfterAuth(auth)) return AuthError.signOutFailed;
      return AuthError.profileUpdateFailed;
    }

    _verificationCooldownUntil =
        DateTime.now().add(const Duration(seconds: 60));
    try {
      await auth.setLanguageCode(lang.firebaseLanguageCode);
      await auth.sendEmailVerification();
    } on FirebaseException catch (error) {
      final result = _mapVerificationError(error, registration: true);
      if (!await _signOutAfterAuth(auth)) return AuthError.signOutFailed;
      return result;
    }
    return AuthError.verificationRequired;
  }

  Future<AuthError> resendVerificationEmail({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) return AuthError.serviceUnavailable;
    if (_verificationRequestInFlight || verificationCooldownSeconds > 0) {
      return AuthError.tooManyRequests;
    }

    _verificationRequestInFlight = true;
    var sendingVerification = false;
    var result = AuthError.serviceUnavailable;
    try {
      var user = auth.currentUser;
      if (user?.email?.toLowerCase() != email.trim().toLowerCase()) {
        user = await auth.signIn(
          email: email.trim(),
          password: password,
        );
      }
      if (user == null) {
        result = AuthError.serviceUnavailable;
      } else {
        await auth.reloadCurrentUser();
        final refreshedUser = auth.currentUser;
        if (refreshedUser?.emailVerified == true) {
          await _setCurrentUser(refreshedUser!);
          result = AuthError.none;
        } else {
          _verificationCooldownUntil =
              DateTime.now().add(const Duration(seconds: 60));
          sendingVerification = true;
          await auth.setLanguageCode(lang.firebaseLanguageCode);
          await auth.sendEmailVerification();
          result = AuthError.verificationResent;
        }
      }
    } on FirebaseException catch (error) {
      result = sendingVerification
          ? _mapVerificationError(error)
          : _mapFirebaseAuthError(error);
      if (error.code == 'too-many-requests') {
        _verificationCooldownUntil =
            DateTime.now().add(const Duration(seconds: 60));
      }
    }
    _verificationRequestInFlight = false;
    return result;
  }

  Future<bool> _signOutAfterAuth(EmailPasswordAuthGateway auth) async {
    try {
      await auth.signOut();
      return true;
    } on FirebaseException {
      return false;
    }
  }

  Future<AuthError> signInWithGoogle() async {
    return _finishSocialSignIn(
      () => _socialAuth?.signInWithGoogle(),
      provider: 'Google',
    );
  }

  Future<AuthError> signInWithApple() async {
    return _finishSocialSignIn(
      () => _socialAuth?.signInWithApple(),
      provider: 'Apple',
    );
  }

  Future<AuthError> _finishSocialSignIn(
    Future<UserCredential?>? Function() authenticate, {
    required String provider,
  }) async {
    final service = _socialAuth;
    if (service == null) return AuthError.serviceUnavailable;
    try {
      final result = await authenticate();
      if (result == null) return AuthError.authCancelled;

      final user = result.user;
      if (user == null) return AuthError.serviceUnavailable;
      await user.reload();
      final refreshedUser = service.currentUser;
      if (refreshedUser == null) return AuthError.serviceUnavailable;

      await _setCurrentUser(
        AuthUserInfo(
          uid: refreshedUser.uid,
          email: refreshedUser.email,
          displayName: refreshedUser.displayName,
          photoUrl: refreshedUser.photoURL,
          creationTime: refreshedUser.metadata.creationTime,
          emailVerified: refreshedUser.emailVerified,
        ),
      );
      unawaited(_recordLoginActivity());
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed') {
        return AuthError.providerUnavailable;
      }
      if (error.code == 'invalid-credential') {
        return AuthError.authFailed;
      }
      return _mapFirebaseAuthError(error);
    } on UnsupportedError {
      return AuthError.providerUnavailable;
    } on PlatformException catch (error) {
      debugPrint('$provider sign-in failed (${error.code}).');
      return error.code.toLowerCase().contains('network')
          ? AuthError.networkError
          : AuthError.authFailed;
    } on Exception catch (error) {
      debugPrint('$provider sign-in failed (${error.runtimeType}).');
      return AuthError.authFailed;
    }
  }

  bool get hasPendingSocialCredential =>
      _socialAuth?.hasPendingCredential ?? false;

  void discardPendingSocialCredential() {
    _socialAuth?.discardPendingCredential();
  }

  Future<AuthError> linkPendingSocialCredential() async {
    final service = _socialAuth;
    if (service == null) return AuthError.serviceUnavailable;
    try {
      final credential = await service.linkPendingCredential();
      final user = credential.user;
      if (user == null) return AuthError.serviceUnavailable;
      await user.reload();
      final refreshedUser = service.currentUser;
      if (refreshedUser == null) return AuthError.serviceUnavailable;
      await _setCurrentUser(
        AuthUserInfo(
          uid: refreshedUser.uid,
          email: refreshedUser.email,
          displayName: refreshedUser.displayName,
          photoUrl: refreshedUser.photoURL,
          creationTime: refreshedUser.metadata.creationTime,
          emailVerified: refreshedUser.emailVerified,
        ),
      );
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      service.discardPendingCredential();
      return _mapFirebaseAuthError(error);
    } on Exception catch (error) {
      service.discardPendingCredential();
      debugPrint('Provider linking failed (${error.runtimeType}).');
      return AuthError.serviceUnavailable;
    }
  }

  Future<AuthError> login({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) return AuthError.serviceUnavailable;
    try {
      final user = await auth.signIn(
        email: email.trim(),
        password: password,
      );
      if (user == null) return AuthError.serviceUnavailable;
      await auth.reloadCurrentUser();
      final refreshedUser = auth.currentUser;
      if (refreshedUser == null) return AuthError.serviceUnavailable;
      if (!refreshedUser.emailVerified) {
        if (!await _signOutAfterAuth(auth)) return AuthError.signOutFailed;
        return AuthError.emailNotVerified;
      }
      await _setCurrentUser(refreshedUser);
      unawaited(_recordLoginActivity());
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      return _mapFirebaseAuthError(error);
    } on FirebaseException catch (error) {
      return _mapFirebaseAuthError(error);
    }
  }

  Future<void> _recordLoginActivity() async {
    try {
      final token = await getFirebaseIdToken(forceRefresh: true);
      if (token == null || token.isEmpty) return;
      final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.tryParse('$base/api/v1/user/activity/login');
      if (uri == null ||
          !uri.hasAuthority ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        debugPrint('Login activity was not recorded: invalid API URL.');
        return;
      }
      final response = await http.post(uri, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 204) {
        debugPrint(
          'Login activity was not recorded (HTTP ${response.statusCode}).',
        );
      }
    } on Exception catch (error) {
      debugPrint('Login activity could not be recorded: $error');
    }
  }

  Future<AuthError> refreshEmailVerification() async {
    final auth = _auth;
    if (auth == null) return AuthError.serviceUnavailable;
    if (auth.currentUser == null) return AuthError.emailNotVerified;

    try {
      await auth.reloadCurrentUser();
      final refreshedUser = auth.currentUser;
      if (refreshedUser == null) return AuthError.emailNotVerified;
      if (!refreshedUser.emailVerified) return AuthError.emailNotVerified;

      await _setCurrentUser(refreshedUser);
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      return _mapFirebaseAuthError(error);
    } on FirebaseException catch (error) {
      return _mapFirebaseAuthError(error);
    }
  }

  Future<void> _setCurrentUser(
    AuthUserInfo user,
  ) async {
    final previous = currentUser;
    final existing =
        previous?.uid == user.uid && user.uid.isNotEmpty ? previous : null;
    currentUser = UserRecord(
      uid: user.uid,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (existing?.name ?? user.email?.split('@').first ?? ''),
      email: user.email ?? existing?.email ?? '',
      answers: existing?.answers ?? const [],
      createdAt: user.creationTime?.millisecondsSinceEpoch ??
          (existing?.createdAt ?? 0),
    );
    _loadScans();
    notifyListeners();
  }

  Future<AuthError> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) return AuthError.serviceUnavailable;
    try {
      await auth.setLanguageCode(lang.firebaseLanguageCode);
      await auth.sendPasswordResetEmail(email.trim());
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      return _mapFirebaseAuthError(error);
    } on FirebaseException catch (error) {
      return _mapFirebaseAuthError(error);
    }
  }

  Future<void> logout() async {
    try {
      final socialAuth = _socialAuth;
      if (socialAuth != null) {
        await socialAuth.signOut();
      } else {
        await _auth?.signOut();
      }
      await _prefs?.remove('session');
      currentUser = null;
      _localScans.clear();
      _remoteScans = [];
      _verificationCooldownUntil = null;
      notifyListeners();
    } on FirebaseException {
      rethrow;
    }
  }

  AuthError _mapFirebaseAuthError(FirebaseException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return _socialAuth?.hasPendingCredential == true
            ? AuthError.accountLinkRequired
            : AuthError.accountConflict;
      case 'credential-already-in-use':
        return AuthError.accountConflict;
      case 'email-not-verified':
        return AuthError.emailNotVerified;
      case 'user-not-found':
        return AuthError.noAccount;
      case 'wrong-password':
      case 'invalid-login-credentials':
      case 'invalid-credential':
        return AuthError.wrongPassword;
      case 'user-disabled':
        return AuthError.accountDisabled;
      case 'operation-not-allowed':
        return AuthError.emailPasswordDisabled;
      case 'email-already-in-use':
        return AuthError.exists;
      case 'weak-password':
        return AuthError.weakPassword;
      case 'invalid-email':
        return AuthError.invalidEmail;
      case 'too-many-requests':
        return AuthError.tooManyRequests;
      case 'network-request-failed':
        return AuthError.networkError;
      case 'user-token-expired':
      case 'invalid-user-token':
        return AuthError.authFailed;
      case 'provider-already-linked':
        return AuthError.accountConflict;
      default:
        return AuthError.serviceUnavailable;
    }
  }

  AuthError _mapVerificationError(
    FirebaseException error, {
    bool registration = false,
  }) {
    switch (error.code) {
      case 'too-many-requests':
        return registration
            ? AuthError.verificationTooManyRequests
            : AuthError.tooManyRequests;
      case 'network-request-failed':
        return registration
            ? AuthError.verificationNetworkError
            : AuthError.networkError;
      case 'invalid-email':
        return AuthError.invalidEmail;
      case 'user-disabled':
        return AuthError.accountDisabled;
      case 'operation-not-allowed':
        return AuthError.emailPasswordDisabled;
      default:
        return AuthError.verificationFailed;
    }
  }

  Future<void> completeOnboarding() async {
    await _prefs?.setBool('onboarding_completed', true);
    onboardingCompleted = true;
    notifyListeners();
  }

  Future<void> setRetainHistory(bool value) async {
    await _prefs?.setBool('retain_analysis_history', value);
    retainHistory = value;
    notifyListeners();
  }

  /// Answer text (in the current language) for question [q], or null.
  String? answerText(int q) {
    final u = currentUser;
    if (u == null || q >= u.answers.length) return null;
    final i = u.answers[q];
    if (i < 0) return null;
    final opts = quiz[q].of(lang.locale.languageCode);
    return i + 1 < opts.length ? opts[i + 1] : null;
  }

  bool get isRtl => LocaleHelper.isRtl(lang.locale);

  Future<void> setLang(AppLang value) async {
    final preferences = _prefs;
    if (preferences == null) {
      throw StateError('The app controller has not been initialized.');
    }
    await languageController.setLanguage(value, preferences: preferences);
    await routineController.setWidgetLanguage(value.name);
    if (notificationsEnabled && notificationsSupported) {
      await _syncDailyReminder(routineController.notificationSettings);
    }
  }

  Future<void> setTheme(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await _prefs?.setString('theme', value.name);
  }

  Future<void> setSkincareGoal(String value) async {
    skincareGoal = value;
    await _prefs?.setString('settings_skincare_goal', value);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay value) async {
    reminderHour = value.hour;
    reminderMinute = value.minute;
    notifyListeners();
    await _prefs?.setInt(
      'settings_reminder_minutes',
      value.hour * 60 + value.minute,
    );
    if (notificationsEnabled && notificationsSupported) {
      await _syncDailyReminder(routineController.notificationSettings);
    }
  }

  Future<void> setSkinType(String value) async {
    skinType = value;
    notifyListeners();
    await _prefs?.setString('settings_skin_type', value);
  }

  Future<void> setAccentColor(Color value) async {
    accentColor = value;
    await _prefs?.setInt('settings_accent_color', value.toARGB32());
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    final routineSettings =
        routineController.notificationSettings.copyWith(masterEnabled: value);
    if (value) {
      final dailyReminderEnabled = _dailyReminderEnabled(routineSettings);
      if (dailyReminderEnabled) {
        await _reminderService.enableDaily(
          hour: reminderHour,
          minute: reminderMinute,
          title: t('reminderNotificationTitle'),
          body: t('reminderNotificationBody'),
          quietHoursEnabled: routineSettings.quietHoursEnabled,
          quietStartMinutes: routineSettings.quietStartMinutes,
          quietEndMinutes: routineSettings.quietEndMinutes,
          soundEnabled: routineSettings.soundEnabled,
          vibrationEnabled: routineSettings.vibrationEnabled,
          privatePreview: routineSettings.privatePreview,
          language: lang.locale.languageCode,
        );
      } else {
        await routineController.requestNotificationPermission();
        await _reminderService.cancel();
      }
    } else {
      await _reminderService.cancel();
    }
    await routineController.updateNotificationSettings(routineSettings);
    notificationsEnabled = value;
    await _prefs?.setBool('settings_notifications_enabled', value);
    notifyListeners();
  }

  bool _dailyReminderEnabled(RoutineNotificationSettings settings) =>
      settings.masterEnabled &&
      settings.dailyEnabled &&
      (reminderHour < 12 ? settings.morningEnabled : settings.eveningEnabled);

  Future<void> _syncDailyReminder(
    RoutineNotificationSettings settings,
  ) async {
    if (!notificationsSupported || !settings.masterEnabled) {
      await _reminderService.cancel();
      return;
    }
    if (!await routineController.notificationPermissionGranted) {
      await _reminderService.cancel();
      notificationsEnabled = false;
      await _prefs?.setBool('settings_notifications_enabled', false);
      await routineController.updateNotificationSettings(
        settings.copyWith(masterEnabled: false),
      );
      notifyListeners();
      return;
    }
    if (!_dailyReminderEnabled(settings)) {
      await _reminderService.cancel();
      return;
    }
    await _reminderService.scheduleDaily(
      hour: reminderHour,
      minute: reminderMinute,
      title: t('reminderNotificationTitle'),
      body: t('reminderNotificationBody'),
      quietHoursEnabled: settings.quietHoursEnabled,
      quietStartMinutes: settings.quietStartMinutes,
      quietEndMinutes: settings.quietEndMinutes,
      soundEnabled: settings.soundEnabled,
      vibrationEnabled: settings.vibrationEnabled,
      privatePreview: settings.privatePreview,
      language: lang.locale.languageCode,
    );
  }

  Future<void> updateNotificationSettings(
    RoutineNotificationSettings settings,
  ) async {
    await routineController.updateNotificationSettings(settings);
    notificationsEnabled = settings.masterEnabled;
    await _prefs?.setBool(
        'settings_notifications_enabled', settings.masterEnabled);
    if (notificationsSupported) await _syncDailyReminder(settings);
    notifyListeners();
  }

  Future<AuthError> updateProfileName(String value) async {
    final name = value.trim();
    if (name.length < 2) return AuthError.profileUpdateFailed;
    final auth = _auth;
    final user = currentUser;
    if (auth == null || user == null) return AuthError.serviceUnavailable;
    try {
      await auth.updateDisplayName(name);
      currentUser = UserRecord(
        uid: user.uid,
        name: name,
        email: user.email,
        answers: user.answers,
        createdAt: user.createdAt,
      );
      notifyListeners();
      return AuthError.none;
    } on FirebaseAuthException catch (error) {
      return _mapFirebaseAuthError(error);
    } on FirebaseException catch (error) {
      return _mapFirebaseAuthError(error);
    }
  }

  String t(
    String key, {
    Map<String, String> arguments = const {},
  }) {
    return AppLocalizations.forLanguageCode(lang.locale.languageCode)
        .text(key, arguments: arguments);
  }

  String settingsText(
    String key, {
    Map<String, String> arguments = const {},
  }) {
    final localization =
        AppLocalizations.forLanguageCode(lang.locale.languageCode);
    if (localization.domain('settings').containsKey(key)) {
      return localization.text(
        key,
        domain: 'settings',
        arguments: arguments,
      );
    }
    return localization.text(key, arguments: arguments);
  }

  String routineText(
    String key, {
    Map<String, String> arguments = const {},
  }) =>
      AppLocalizations.forLanguageCode(lang.locale.languageCode)
          .text(key, domain: 'routines', arguments: arguments);

  @override
  void dispose() {
    languageController
      ..removeListener(notifyListeners)
      ..dispose();
    routineController.removeListener(notifyListeners);
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Use inside build(): the widget rebuilds when language/theme changes.
  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Use inside button callbacks (no rebuild dependency).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

// -------------------- Translations --------------------

// -------------------- App root --------------------

class SkinAIApp extends StatelessWidget {
  const SkinAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Skin AI',
      themeMode: a.themeMode,
      theme: buildTheme(Brightness.light, accentColor: a.accentColor),
      darkTheme: buildTheme(Brightness.dark, accentColor: a.accentColor),
      locale: a.lang.locale,
      supportedLocales: LocaleHelper.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        _KurdishMaterialLocalizationsDelegate(),
        _KurdishCupertinoLocalizationsDelegate(),
      ],
      builder: (context, child) => Directionality(
        textDirection: LocaleHelper.directionFor(a.lang.locale),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const SplashScreen(),
    );
  }
}

class _KurdishMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _KurdishMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ku' || locale.languageCode == 'bad';

  @override
  Future<MaterialLocalizations> load(Locale locale) async =>
      const DefaultMaterialLocalizations();

  @override
  bool shouldReload(_KurdishMaterialLocalizationsDelegate old) => false;
}

class _KurdishCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _KurdishCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ku' || locale.languageCode == 'bad';

  @override
  Future<CupertinoLocalizations> load(Locale locale) async =>
      const DefaultCupertinoLocalizations();

  @override
  bool shouldReload(_KurdishCupertinoLocalizationsDelegate old) => false;
}

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 350),
    );

// -------------------- Animated neon background --------------------

class NeonBackground extends StatefulWidget {
  final Widget child;
  const NeonBackground({super.key, required this.child});

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

class _NeonBackgroundState extends State<NeonBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: p.bgGradient,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = animation.value * math.pi * 2;
              return Stack(
                children: [
                  _orb(
                    left: -100 + math.sin(t) * 30,
                    top: 80 + math.cos(t) * 30,
                    color: cyan,
                    alpha: p.orb,
                  ),
                  _orb(
                    right: -130 + math.cos(t) * 30,
                    top: 300 + math.sin(t) * 40,
                    color: purple,
                    alpha: p.orb,
                  ),
                  _orb(
                    left: 60 + math.sin(t) * 30,
                    bottom: -180 + math.cos(t) * 30,
                    color: blue,
                    alpha: p.orb,
                  ),
                ],
              );
            },
          ),
          SafeArea(child: widget.child),
        ],
      ),
    );
  }

  Widget _orb({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required Color color,
    required double alpha,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: 290,
          height: 290,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: alpha * 0.37),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Reusable widgets --------------------

/// Your logo (assets/icon/logo.png) in a glowing rounded square.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.26;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(colors: brandGradient),
        boxShadow: [
          BoxShadow(
            color: cyan.withValues(alpha: 0.28),
            blurRadius: size * 0.2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Image.asset(
          'assets/icon/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: const Color(0xFF10172A),
            child: Icon(
              Icons.face_retouching_natural,
              color: cyan,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Language + theme quick buttons.
class QuickSettings extends StatelessWidget {
  const QuickSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<AppLang>(
          tooltip: a.t('language'),
          color: p.panel,
          onSelected: a.setLang,
          icon: Icon(Icons.language_rounded, color: p.accent),
          itemBuilder: (_) => [
            for (final l
                in AppLang.values.where((value) => value.isReleaseReady))
              PopupMenuItem<AppLang>(
                value: l,
                child: Row(
                  children: [
                    Icon(
                      l == a.lang
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 18,
                      color: p.accent,
                    ),
                    const SizedBox(width: 10),
                    Text(langNames[l]!, style: TextStyle(color: p.text)),
                  ],
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: a.t('appearance'),
          onPressed: () =>
              a.setTheme(isDark ? ThemeMode.light : ThemeMode.dark),
          icon: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: p.accent,
          ),
        ),
      ],
    );
  }
}

class NeonButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;

  const NeonButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: brandGradient),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: blue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isLoading ? null : onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (!isLoading) ...[
                const SizedBox(width: 12),
                Icon(icon, color: Colors.white, size: 21),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration cardDecoration(Pal p, {double radius = 19}) => BoxDecoration(
      color: p.panel.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border),
    );

class PanelTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const PanelTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.panel.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: p.accent, size: 28),
          title: Text(title, style: TextStyle(color: p.text)),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: p.hint, fontSize: 12),
          ),
          trailing: Icon(
            a.isRtl ? Icons.chevron_left : Icons.chevron_right,
            color: p.hint,
          ),
        ),
      ),
    );
  }
}

void showNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// -------------------- Splash, welcome, and onboarding --------------------

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final VideoPlayerController _videoController;
  Timer? _navigationFallback;
  bool _initialized = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _navigationFallback = Timer(const Duration(seconds: 8), _goNext);
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoController =
        VideoPlayerController.asset('gemini_generated_video_a4162dd9.mp4');
    try {
      await _videoController.initialize().timeout(const Duration(seconds: 6));
      if (!mounted || _navigated) return;
      await _videoController.setVolume(1.0);
      if (!mounted || _navigated) return;
      _videoController.addListener(_checkVideoEnd);
      if (mounted) {
        setState(() => _initialized = true);
        await _videoController.play();
      }
    } catch (error) {
      debugPrint('Splash video initialization or playback failed: $error');
      _goNext();
    }
  }

  void _checkVideoEnd() {
    final value = _videoController.value;
    if (value.hasError) {
      debugPrint('Splash video playback failed: ${value.errorDescription}');
      _goNext();
      return;
    }
    if (value.isInitialized &&
        !value.isPlaying &&
        value.position >= value.duration) {
      _goNext();
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _navigationFallback?.cancel();

    final controller = AppScope.read(context);
    // ئەگەر داخڵ بووبێت دەچێتە ناو بەرنامەکە، ئەگەر نا دەچێتە پەڕەی Login / Sign Up
    final Widget destination = controller.currentUser != null
        ? const DashboardScreen()
        : const AuthScreen(startLogin: true);

    Navigator.of(context).pushReplacement(fadeRoute(destination));
  }

  @override
  void dispose() {
    _navigationFallback?.cancel();
    _videoController.removeListener(_checkVideoEnd);
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050714),
      body: Center(
        child: _initialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover, // پڕکردنەوەی تەواوی شاشەکە بە ڤیدیۆکە
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              )
            : const CircularProgressIndicator(color: cyan),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _start(BuildContext context) {
    final controller = AppScope.read(context);
    final Widget destination = controller.currentUser != null
        ? const DashboardScreen()
        : (controller.onboardingCompleted
            ? const AuthScreen(startLogin: true)
            : const OnboardingScreen());
    Navigator.push(context, fadeRoute(destination));
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    return NeonBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 34, 26, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo(size: 112)),
                const SizedBox(height: 28),
                Text(
                  a.t('welcomeHeading'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  a.t('welcomeBody'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub, height: 1.6),
                ),
                const SizedBox(height: 32),
                NeonButton(
                  text: a.t('getStarted'),
                  icon: a.isRtl
                      ? Icons.arrow_back_rounded
                      : Icons.arrow_forward_rounded,
                  onTap: () => _start(context),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    fadeRoute(const AuthScreen(startLogin: true)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(a.t('signIn')),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    fadeRoute(const AuthScreen(startLogin: false)),
                  ),
                  child: Text(a.t('createAccount')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;
  bool _saving = false;

  static const _steps = [
    (
      Icons.photo_camera_back_outlined,
      'onboardCaptureTitle',
      'onboardCaptureBody'
    ),
    (Icons.auto_awesome_outlined, 'onboardAnalyzeTitle', 'onboardAnalyzeBody'),
    (
      Icons.health_and_safety_outlined,
      'onboardUnderstandTitle',
      'onboardUnderstandBody'
    ),
  ];

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.read(context).completeOnboarding();
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      showNotice(context, AppScope.read(context).t('onboardingSaveFailed'));
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, fadeRoute(const AuthScreen()));
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    final step = _steps[_index];
    return NeonBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: a.t('back'),
                    onPressed: _back,
                    icon: Icon(
                      a.isRtl
                          ? Icons.arrow_forward_ios_rounded
                          : Icons.arrow_back_ios_new_rounded,
                      color: p.sub,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      a.t('stepLabel').replaceAll('{n}', '${_index + 1}'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.sub),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _finish,
                    child: Text(a.t('skip')),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    minHeight: 6,
                    backgroundColor: p.border,
                    valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Center(
                    key: ValueKey<int>(_index),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: p.accent.withValues(alpha: 0.14),
                              border: Border.all(
                                color: p.accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Icon(step.$1, size: 50, color: p.accent),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            a.t(step.$2),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            a.t(step.$3),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.sub,
                              height: 1.6,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              NeonButton(
                text: _index == _steps.length - 1 ? a.t('finish') : a.t('next'),
                icon: _index == _steps.length - 1
                    ? Icons.check_rounded
                    : (a.isRtl
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_forward_rounded),
                onTap: _saving
                    ? () {}
                    : () {
                        if (_index == _steps.length - 1) {
                          _finish();
                        } else {
                          setState(() => _index++);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _sendReset();
  }

  bool _sending = false;

  Future<void> _sendReset() async {
    if (_sending) return;
    setState(() => _sending = true);
    final controller = AppScope.read(context);
    final result =
        await controller.sendPasswordResetEmail(_emailController.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (result == AuthError.none) {
      showNotice(context, controller.t('resetEmailSent'));
    } else {
      showNotice(
        context,
        result == AuthError.serviceUnavailable
            ? controller.authSetupMessage
            : _authErrorText(controller, result),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    return NeonBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: IconButton(
                      tooltip: a.t('back'),
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        a.isRtl
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        color: p.sub,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(child: AppLogo(size: 84)),
                  const SizedBox(height: 24),
                  Text(
                    a.t('forgot'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    a.t('forgotMsg'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.sub, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: TextStyle(color: p.text),
                    decoration: InputDecoration(
                      labelText: a.t('email'),
                      hintText: a.t('emailHint'),
                      prefixIcon:
                          Icon(Icons.mail_outline_rounded, color: p.accent),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return a.t('errEmail');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  NeonButton(
                    text: _sending ? a.t('analyzing') : a.t('sendRecovery'),
                    icon: Icons.mail_outline_rounded,
                    isLoading: _sending,
                    onTap: _sending ? () {} : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Login and sign up --------------------

class AuthScreen extends StatefulWidget {
  final bool startLogin;
  const AuthScreen({super.key, this.startLogin = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  late bool isLogin = widget.startLogin;
  bool busy = false;
  String? _socialProvider;
  bool hidePassword = true;
  bool hideConfirm = true;
  bool acceptedTerms = false;
  bool _showVerificationResend = false;
  bool _resendingVerification = false;
  bool _checkingVerification = false;
  int _resendWaitSeconds = 0;
  AuthError? _verificationStatus;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = AppScope.read(context);
      if (controller.hasPendingEmailVerification && mounted) {
        setState(() {
          isLogin = true;
          _showVerificationResend = true;
          _verificationStatus = AuthError.emailNotVerified;
        });
      }
      unawaited(_checkEmailVerification(silent: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkEmailVerification(silent: true));
    }
  }

  void _openDashboard(AppController controller) {
    showNotice(
      context,
      controller.t('welcomeUser').replaceAll('{n}', controller.userName),
    );
    Navigator.pushAndRemoveUntil(
      context,
      fadeRoute(const DashboardScreen()),
      (route) => false,
    );
  }

  Future<void> _checkEmailVerification({bool silent = false}) async {
    if (_checkingVerification ||
        busy ||
        !AppScope.read(context).hasPendingEmailVerification) {
      return;
    }

    final controller = AppScope.read(context);
    setState(() => _checkingVerification = true);
    final result = await controller.refreshEmailVerification();
    if (!mounted) return;
    setState(() => _checkingVerification = false);

    if (result == AuthError.none) {
      _openDashboard(controller);
      return;
    }
    if (result != AuthError.emailNotVerified) {
      setState(() => _verificationStatus = result);
      if (!silent) showNotice(context, _authErrorText(controller, result));
    } else if (!silent) {
      setState(() => _verificationStatus = result);
      showNotice(context, _authErrorText(controller, result));
    }
  }

  Future<void> _submit() async {
    final a = AppScope.read(context);
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!isLogin && !acceptedTerms) {
      showNotice(context, a.t('errTerms'));
      return;
    }

    setState(() => busy = true);
    final AuthError err = isLogin
        ? await a.login(
            email: _emailController.text,
            password: _passwordController.text,
          )
        : await a.register(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
    if (!mounted) return;
    setState(() => busy = false);

    if (err == AuthError.none) {
      await _offerPendingSocialLink(a);
      if (mounted) _openDashboard(a);
    } else if (err == AuthError.verificationRequired ||
        err == AuthError.emailNotVerified ||
        err == AuthError.verificationNetworkError ||
        err == AuthError.verificationTooManyRequests ||
        err == AuthError.verificationFailed ||
        err == AuthError.profileUpdateFailed ||
        err == AuthError.signOutFailed) {
      setState(() {
        isLogin = true;
        _showVerificationResend = true;
        _verificationStatus = err;
      });
      _startVerificationCooldown(a);
      showNotice(context, _authErrorText(a, err));
    } else if (err == AuthError.noAccount) {
      // No account yet -> the person must create one first.
      setState(() => isLogin = false);
      showNotice(context, a.t('errNoAccount'));
    } else if (err == AuthError.exists) {
      setState(() => isLogin = true);
      showNotice(context, a.t('errExists'));
    } else if (err == AuthError.accountLinkRequired) {
      setState(() => isLogin = true);
      showNotice(context, a.t('accountLinkRequired'));
    } else if (err == AuthError.accountConflict) {
      showNotice(context, a.t('accountConflict'));
    } else if (err == AuthError.providerUnavailable) {
      showNotice(context, a.t('providerUnavailable'));
    } else if (err == AuthError.serviceUnavailable) {
      showNotice(context, a.authSetupMessage);
    } else if (err == AuthError.weakPassword) {
      showNotice(context, a.t('errPass'));
    } else if (err == AuthError.invalidEmail) {
      showNotice(context, a.t('errEmail'));
    } else if (err == AuthError.tooManyRequests) {
      showNotice(context, a.t('authTooManyRequests'));
    } else if (err == AuthError.networkError) {
      showNotice(context, a.t('authNetworkError'));
    } else if (err == AuthError.accountDisabled ||
        err == AuthError.emailPasswordDisabled) {
      showNotice(context, _authErrorText(a, err));
    } else {
      showNotice(context, a.t('errWrongPass'));
    }
  }

  Future<void> _socialSignIn(String provider) async {
    if (busy) return;
    final controller = AppScope.read(context);
    if (!isLogin && !acceptedTerms) {
      showNotice(context, controller.t('errTerms'));
      return;
    }
    setState(() {
      busy = true;
      _socialProvider = provider;
    });
    final result = provider == 'apple'
        ? await controller.signInWithApple()
        : await controller.signInWithGoogle();
    if (!mounted) return;
    setState(() {
      busy = false;
      _socialProvider = null;
    });

    if (result == AuthError.none) {
      await _offerPendingSocialLink(controller);
      if (mounted) _openDashboard(controller);
    } else if (result != AuthError.authCancelled) {
      showNotice(
        context,
        result == AuthError.serviceUnavailable
            ? controller.authSetupMessage
            : _authErrorText(controller, result),
      );
    }
  }

  Future<void> _offerPendingSocialLink(AppController controller) async {
    if (!controller.hasPendingSocialCredential || !mounted) return;
    final shouldLink = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.of(dialogContext).panel,
        title: Text(
          controller.t('linkAccountTitle'),
          style: TextStyle(color: Pal.of(dialogContext).text),
        ),
        content: Text(
          controller.t('linkAccountMessage'),
          style: TextStyle(color: Pal.of(dialogContext).sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(controller.t('continueWithoutLinking')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(controller.t('linkAccount')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (shouldLink != true) {
      controller.discardPendingSocialCredential();
      return;
    }

    setState(() => busy = true);
    final result = await controller.linkPendingSocialCredential();
    if (!mounted) return;
    setState(() => busy = false);
    showNotice(
      context,
      result == AuthError.none
          ? controller.t('accountLinked')
          : _authErrorText(controller, result),
    );
  }

  Future<void> _resendVerification() async {
    final a = AppScope.read(context);
    FocusScope.of(context).unfocus();
    if (busy || _resendingVerification || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      busy = true;
      _resendingVerification = true;
    });
    final result = await a.resendVerificationEmail(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (result == AuthError.none) {
      _openDashboard(a);
      return;
    }
    setState(() {
      busy = false;
      _resendingVerification = false;
      _verificationStatus = result;
    });
    _startVerificationCooldown(a);
    showNotice(context, _authErrorText(a, result));
  }

  void _startVerificationCooldown(AppController controller) {
    _cooldownTimer?.cancel();
    void updateRemaining() {
      if (!mounted) return;
      final remaining = controller.verificationCooldownSeconds;
      setState(() => _resendWaitSeconds = remaining);
      if (remaining == 0) _cooldownTimer?.cancel();
    }

    updateRemaining();
    if (_resendWaitSeconds > 0) {
      _cooldownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => updateRemaining(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);

    return NeonBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        a.isRtl
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        color: p.sub,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'SKIN AI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: p.text,
                      ),
                    ),
                    const Spacer(),
                    const QuickSettings(),
                  ],
                ),
                const SizedBox(height: 14),
                const Center(child: AppLogo(size: 84)),
                const SizedBox(height: 22),
                Text(
                  isLogin ? a.t('welcomeBack') : a.t('createAccount'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isLogin ? a.t('signinSub') : a.t('signupSub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: p.panel.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.border),
                  ),
                  child: Row(
                    children: [
                      _tab(a.t('login'), isLogin, () {
                        setState(() => isLogin = true);
                      }),
                      _tab(a.t('createAccount'), !isLogin, () {
                        setState(() => isLogin = false);
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: cardDecoration(p, radius: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isLogin) ...[
                          _label(a.t('fullName'), p),
                          const SizedBox(height: 8),
                          _input(
                            p: p,
                            controller: _nameController,
                            hint: a.t('fullNameHint'),
                            icon: Icons.person_outline_rounded,
                            validator: (value) {
                              if (value == null || value.trim().length < 2) {
                                return a.t('errName');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 17),
                        ],
                        _label(a.t('email'), p),
                        const SizedBox(height: 8),
                        _input(
                          p: p,
                          controller: _emailController,
                          hint: a.t('emailHint'),
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(email)) {
                              return a.t('errEmail');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 17),
                        _label(a.t('password'), p),
                        const SizedBox(height: 8),
                        _input(
                          p: p,
                          controller: _passwordController,
                          hint: a.t('passwordHint'),
                          icon: Icons.lock_outline_rounded,
                          obscureText: hidePassword,
                          suffix: IconButton(
                            onPressed: () {
                              setState(() => hidePassword = !hidePassword);
                            },
                            icon: Icon(
                              hidePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: p.hint,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.length < 8) {
                              return a.t('errPass');
                            }
                            return null;
                          },
                        ),
                        if (!isLogin) ...[
                          const SizedBox(height: 17),
                          _label(a.t('confirm'), p),
                          const SizedBox(height: 8),
                          _input(
                            p: p,
                            controller: _confirmController,
                            hint: a.t('confirmHint'),
                            icon: Icons.verified_user_outlined,
                            obscureText: hideConfirm,
                            suffix: IconButton(
                              onPressed: () {
                                setState(() => hideConfirm = !hideConfirm);
                              },
                              icon: Icon(
                                hideConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: p.hint,
                              ),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) {
                                return a.t('errMatch');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: acceptedTerms,
                            onChanged: (value) {
                              setState(() => acceptedTerms = value ?? false);
                            },
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: blue,
                            checkColor: Colors.white,
                            title: Text(
                              a.t('terms'),
                              style: TextStyle(fontSize: 12, color: p.sub),
                            ),
                          ),
                        ],
                        if (isLogin)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                fadeRoute(const PasswordRecoveryScreen()),
                              ),
                              child: Text(
                                a.t('forgot'),
                                style: TextStyle(color: p.accent, fontSize: 12),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        NeonButton(
                          text: isLogin ? a.t('signIn') : a.t('createAccount'),
                          icon: isLogin
                              ? Icons.login_rounded
                              : Icons.person_add_alt_1_rounded,
                          isLoading: busy,
                          onTap:
                              busy || _resendingVerification ? () {} : _submit,
                        ),
                        if (!kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform ==
                                    TargetPlatform.android)) ...[
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(child: Divider(color: p.border)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  a.t('continueWith'),
                                  style: TextStyle(
                                    color: p.hint,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: p.border)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                            _socialButton(
                              label: a.t('signInApple'),
                              loadingLabel: a.t('appleLoading'),
                              isApple: true,
                              isLoading: _socialProvider == 'apple',
                              onPressed:
                                  busy ? null : () => _socialSignIn('apple'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _socialButton(
                            label: a.t('signInGoogle'),
                            loadingLabel: a.t('googleLoading'),
                            isApple: false,
                            isLoading: _socialProvider == 'google',
                            onPressed:
                                busy ? null : () => _socialSignIn('google'),
                          ),
                        ],
                        if (_showVerificationResend && isLogin) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: p.input,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: p.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_verificationStatus != null)
                                  Text(
                                    _authErrorText(
                                      a,
                                      _verificationStatus!,
                                    ),
                                    style: TextStyle(
                                      color: p.sub,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                TextButton.icon(
                                  onPressed: busy || _checkingVerification
                                      ? null
                                      : () => _checkEmailVerification(),
                                  icon: _checkingVerification
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.mark_email_read_outlined,
                                        ),
                                  label: Text(a.t('checkVerification')),
                                ),
                                TextButton.icon(
                                  onPressed: busy ||
                                          _resendingVerification ||
                                          _resendWaitSeconds > 0
                                      ? null
                                      : _resendVerification,
                                  icon: _resendingVerification
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.mark_email_unread_outlined,
                                        ),
                                  label: Text(
                                    _resendWaitSeconds > 0
                                        ? a.t('resendCountdown').replaceAll(
                                              '{seconds}',
                                              '$_resendWaitSeconds',
                                            )
                                        : a.t('resendVerification'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: p.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        a.t('privacyNote'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: p.hint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String text, bool selected, VoidCallback onTap) {
    final p = Pal.of(context);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF087CFF), Color(0xFF4640B9)],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : p.hint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({
    required String label,
    required String loadingLabel,
    required bool isApple,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    final background = isApple ? const Color(0xFF000000) : Colors.white;
    final foreground = isApple ? Colors.white : const Color(0xFF202124);
    final text = isLoading ? loadingLabel : label;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: text,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  isApple ? null : Border.all(color: const Color(0xFFDADCE0)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        )
                      : isApple
                          ? Icon(Icons.apple, size: 25, color: foreground)
                          : const _GoogleGLogo(size: 22),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 32,
                    end: 8,
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, Pal p) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    );
  }

  Widget _input({
    required Pal p,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(color: p.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: p.hint, fontSize: 12),
        prefixIcon: Icon(icon, color: p.accent, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: p.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(p.accent, 1.4),
        errorBorder: border(Colors.redAccent),
        focusedErrorBorder: border(Colors.redAccent, 1.4),
      ),
    );
  }
}

class _GoogleGLogo extends StatelessWidget {
  const _GoogleGLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _GoogleGLogoPainter(),
      );
}

class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.36;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const colors = [
      Color(0xFFEA4335),
      Color(0xFFFBBC05),
      Color(0xFF34A853),
      Color(0xFF4285F4),
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.18
      ..strokeCap = StrokeCap.butt;

    for (var index = 0; index < colors.length; index++) {
      paint.color = colors[index];
      canvas.drawArc(
        rect,
        -math.pi / 2 + index * math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }

    paint
      ..color = colors.last
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - size.width * 0.01,
        center.dy - paint.strokeWidth * 0.34,
        size.width * 0.48,
        paint.strokeWidth * 0.68,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGLogoPainter oldDelegate) => false;
}

// -------------------- Dashboard and navigation --------------------

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 0;
  RoutineController? _observedRoutineController;
  StreamSubscription<Uri>? _widgetLinkSubscription;

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _symptomsController = TextEditingController();
  final TextEditingController _changeController = TextEditingController();
  Uint8List? picked;
  String pickedName = 'scan.jpg';
  bool analyzing = false;
  bool _uploadingImage = false;
  double _uploadProgress = 0;
  bool exportingReport = false;
  ScanResult? result;
  String? scanError;
  DateTime? scannedAt;
  String? selectedBodyRegion;
  String? selectedBodyPart;
  String? selectedBodySubregion;
  String? selectedBodySide;
  String? selectedConcern;
  bool bodySelectionConfirmed = false;
  bool _sensitivePhotoConsent = false;
  bool _accountHistoryConsent = false;
  bool _originalImageConsent = false;
  bool? _medicalImageStorageConfigured;
  bool _checkingMedicalImageStorage = false;
  bool _refreshingAccountHistory = false;
  int? _accountHistoryErrorStatus;
  bool _medicalImageStorageCheckFailed = false;

  bool get _isGeneralConcern => selectedConcern == 'general_concern';

  String _scanConcernLabel(AppController a, String? concernId) {
    if (concernId == 'general_concern') return a.t('generalSkinConcern');
    return _scanConcerns
            .where((item) => item.$1 == concernId)
            .firstOrNull
            ?.$2 ??
        'Concern not selected';
  }

  String _displayScanLabel(AppController a, String code) {
    final key = 'cls_$code';
    return AppLocalizations.keysFor(a.lang.locale.languageCode, 'app')
            .contains(key)
        ? a.t(key)
        : code;
  }

  void _selectGeneralConcern() {
    setState(() {
      selectedConcern = 'general_concern';
      bodySelectionConfirmed = true;
      _sensitivePhotoConsent = false;
      _accountHistoryConsent = false;
      _originalImageConsent = false;
      picked = null;
      result = null;
      scanError = null;
      scannedAt = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context).routineController;
    if (!identical(controller, _observedRoutineController)) {
      _widgetLinkSubscription?.cancel();
      _observedRoutineController = controller;
      _widgetLinkSubscription = controller.widgetLinks.listen(_handleDeepLink);
      final pending = controller.takePendingWidgetLink();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleDeepLink(pending);
        });
      }
    }
  }

  @override
  void dispose() {
    _widgetLinkSubscription?.cancel();
    _locationController.dispose();
    _durationController.dispose();
    _symptomsController.dispose();
    _changeController.dispose();
    super.dispose();
  }

  void _handleDeepLink(Uri uri) {
    if (!mounted) return;
    final segments = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((segment) => segment.isNotEmpty),
    ];
    if (segments.join('/') == 'notifications') {
      _openNotifications();
      return;
    }
    final tab = switch (segments.join('/')) {
      'routine/daily' || 'routine/weekly' || 'routine' => 3,
      'history' => 1,
      'settings' => 4,
      'scanner' => 2,
      _ => null,
    };
    if (tab != null) _selectTab(tab);
  }

  void _selectTab(int tab) {
    setState(() {
      if (tab == 2 && selectedIndex != 2) {
        bodySelectionConfirmed = false;
      }
      selectedIndex = tab;
    });
    if (tab == 1) unawaited(_refreshAccountHistory());
    if (tab == 2) unawaited(_checkMedicalImageStorage());
  }

  Future<void> _refreshAccountHistory() async {
    if (_refreshingAccountHistory) return;
    setState(() {
      _refreshingAccountHistory = true;
      _accountHistoryErrorStatus = null;
    });
    try {
      await AppScope.read(context).refreshAccountScans();
    } on MedicalScanApiException catch (error) {
      _accountHistoryErrorStatus = error.statusCode;
    } on Exception {
      _accountHistoryErrorStatus = 0;
    } finally {
      if (mounted) {
        setState(() => _refreshingAccountHistory = false);
      }
    }
  }

  Future<void> _checkMedicalImageStorage() async {
    if (_checkingMedicalImageStorage) return;
    setState(() {
      _checkingMedicalImageStorage = true;
      _medicalImageStorageCheckFailed = false;
      _medicalImageStorageConfigured = null;
    });
    try {
      _medicalImageStorageConfigured =
          await AppScope.read(context).originalImageStorageConfigured();
    } on Exception {
      _medicalImageStorageCheckFailed = true;
    } finally {
      if (mounted) {
        setState(() => _checkingMedicalImageStorage = false);
      }
    }
  }

  Future<void> _pick(ImageSource source) async {
    final a = AppScope.read(context);
    if (selectedBodyRegion == 'buttocks' && !_sensitivePhotoConsent) {
      final p = Pal.of(context);
      final consent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: p.panel,
          title: Text(
            a.t('sensitiveImageTitle'),
            style: TextStyle(color: p.text),
          ),
          content: Text(
            a.t('sensitiveImageBody'),
            style: TextStyle(color: p.sub, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(a.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(a.t('continue')),
            ),
          ],
        ),
      );
      if (consent != true || !mounted) return;
      setState(() => _sensitivePhotoConsent = true);
    }
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) showNotice(context, a.t('invalidImage'));
        return;
      }
      if (bytes.length > 10 * 1024 * 1024) {
        if (mounted) showNotice(context, a.t('imageTooLarge'));
        return;
      }
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        bool isReadable;
        try {
          final frame = await codec.getNextFrame();
          isReadable = frame.image.width > 0 && frame.image.height > 0;
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
        if (!isReadable) {
          if (mounted) showNotice(context, a.t('invalidImage'));
          return;
        }
      } catch (_) {
        if (mounted) showNotice(context, a.t('invalidImage'));
        return;
      }
      if (!mounted) return;
      setState(() {
        picked = bytes;
        pickedName = x.name;
        _accountHistoryConsent = false;
        _originalImageConsent = false;
        result = null;
        scanError = null;
        scannedAt = null;
      });
    } catch (_) {
      if (mounted) showNotice(context, a.t('errPick'));
    }
  }

  Future<void> _analyze() async {
    if (analyzing) return;
    final a = AppScope.read(context);
    final bytes = picked;
    if (bytes == null) {
      showNotice(context, a.t('pickFirst'));
      return;
    }
    var saveToAccount = _accountHistoryConsent;
    var saveOriginalImage = _originalImageConsent;
    if (saveToAccount) {
      final p = Pal.of(context);
      final consent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: p.panel,
          title: Text(
            a.t('accountHistoryConsentTitle'),
            style: TextStyle(color: p.text),
          ),
          content: Text(
            saveOriginalImage
                ? a.t('accountImageConsentBody')
                : a.t('accountHistoryConsentBody'),
            style: TextStyle(color: p.sub, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: Text(a.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(a.t('analyzeWithoutSaving')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(a.t('consentAndAnalyze')),
            ),
          ],
        ),
      );
      if (!mounted || consent == null) return;
      if (!consent) {
        saveToAccount = false;
        saveOriginalImage = false;
        setState(() {
          _accountHistoryConsent = false;
          _originalImageConsent = false;
        });
      }
    }
    setState(() {
      analyzing = true;
      _uploadingImage = true;
      _uploadProgress = 0;
      scanError = null;
      result = null;
    });
    try {
      final idToken = await a.getFirebaseIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw ApiException(a.t('authRequiredForAnalysis'));
      }
      final concernLabel = selectedConcern == null
          ? null
          : _scanConcernLabel(a, selectedConcern);
      final details = [
        if (concernLabel != null) '${a.t('concernLabel')}: $concernLabel',
        if (_symptomsController.text.trim().isNotEmpty)
          _symptomsController.text.trim(),
      ].join('\n');
      final r = await SkinApi.analyze(
        a.serverUrl,
        bytes,
        pickedName,
        idToken: idToken,
        saveHistory: saveToAccount,
        location: _locationController.text,
        duration: _durationController.text,
        details: details,
        changeOverTime: _changeController.text,
        onUploadProgress: (sentBytes, totalBytes) {
          if (!mounted) return;
          final progress =
              totalBytes == 0 ? 0.0 : sentBytes / totalBytes;
          final boundedProgress = progress.clamp(0, 1).toDouble();
          if ((boundedProgress * 100).round() ==
                  (_uploadProgress * 100).round() &&
              sentBytes < totalBytes) {
            return;
          }
          setState(() {
            _uploadProgress = boundedProgress;
            if (sentBytes >= totalBytes) _uploadingImage = false;
          });
        },
      );
      String? persistenceError;
      final record = ScanRecord(
        cls: r.cls,
        conf: r.confidence,
        mel: false,
        ts: r.timestamp.millisecondsSinceEpoch,
        analysisId: r.scanId,
        summary: r.summary,
        bodyPart: selectedBodyRegion == null
            ? a.t('generalSkinConcern')
            : bodyRegionOptions
                .firstWhere((region) => region.id == selectedBodyRegion)
                .group,
        bodySubregion: selectedBodyRegion == null
            ? null
            : bodyRegionOptions
                .firstWhere((region) => region.id == selectedBodyRegion)
                .label,
        bodySide: selectedBodySide,
        concernType: _scanConcernLabel(a, selectedConcern),
        userId: a.currentUser?.uid,
        bodyLocation: _locationController.text.trim().isEmpty
            ? [
                if (selectedBodySide != null) selectedBodySide!,
                if (selectedBodySubregion != null) selectedBodySubregion!,
              ].join(' ')
            : _locationController.text.trim(),
        notes: details.isEmpty ? null : details,
        accountRecord: saveToAccount,
      );
      if (saveToAccount) {
        final localHistoryStored = await a.addAccountScan(record);
        if (!localHistoryStored) {
          persistenceError = a.t('historySaveFailed');
        }
        if (saveOriginalImage) {
          bool imageUploaded;
          setState(() {
            _uploadingImage = true;
            _uploadProgress = 0;
          });
          try {
            imageUploaded = await a.storeAccountScanImage(
              record,
              bytes: bytes,
              filename: pickedName,
              onProgress: (sentBytes, totalBytes) {
                if (!mounted) return;
                final progress =
                    totalBytes == 0 ? 0.0 : sentBytes / totalBytes;
                final boundedProgress = progress.clamp(0, 1).toDouble();
                if ((boundedProgress * 100).round() ==
                    (_uploadProgress * 100).round()) {
                  return;
                }
                setState(
                  () => _uploadProgress = boundedProgress,
                );
              },
            );
          } on Exception {
            imageUploaded = false;
            final imageError = a.t('imageStorageSaveFailed');
            persistenceError = persistenceError == null
                ? imageError
                : '$persistenceError\n$imageError';
          }
          if (!imageUploaded && persistenceError == null) {
            persistenceError = a.t('historySaveFailed');
          }
        }
      } else if (a.retainHistory) {
        try {
          await a.addScan(record);
        } on Exception {
          persistenceError = a.t('historySaveFailed');
        }
      }
      if (!mounted) return;
      setState(() {
        analyzing = false;
        _uploadingImage = false;
        result = r;
        scanError = persistenceError;
        scannedAt = r.timestamp;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        analyzing = false;
        _uploadingImage = false;
        scanError = switch (e.statusCode) {
          401 => a.t('authRequiredForAnalysis'),
          400 => a.t('scanBadInput'),
          403 => a.t('scanAccessDenied'),
          409 => a.t('mockHistoryNotSupported'),
          413 => a.t('imageTooLarge'),
          503 => a.t('apiServiceUnavailable'),
          502 => a.t('scanProviderError'),
          504 => a.t('scanTimeout'),
          _ =>
            e.statusCode == null ? a.t('errConnect') : a.t('apiRequestFailed'),
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        analyzing = false;
        _uploadingImage = false;
        scanError = a.t('errConnect');
      });
    }
  }

  Future<void> _exportReport(ScanResult scan) async {
    if (exportingReport) return;
    setState(() => exportingReport = true);
    final a = AppScope.read(context);
    try {
      final bytes = await buildScanReportPdf(
        result: _displayScanLabel(a, scan.cls),
        confidencePercent: scan.confidence,
        scannedAt: scannedAt ?? DateTime.now(),
        summary: scan.summary,
        localize: a.t,
      );
      final now = DateTime.now();
      final filename =
          'skin_ai_scan_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
      await shareScanReport(bytes, filename);
    } on Exception {
      if (mounted) {
        showNotice(context, AppScope.read(context).t('reportExportFailed'));
      }
    } finally {
      if (mounted) setState(() => exportingReport = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await AppScope.read(context).logout();
    } on FirebaseException {
      if (mounted) {
        showNotice(context, AppScope.read(context).t('signOutFailed'));
      }
      return;
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      fadeRoute(const SplashScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmSignOut() async {
    final a = AppScope.read(context);
    final p = Pal.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.panel,
        title: Text(a.t('signOut'), style: TextStyle(color: p.text)),
        content: Text(
          a.t('signOutConfirm'),
          style: TextStyle(color: p.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(a.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(a.t('signOut')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _signOut();
  }

  Future<void> _openSearch() async {
    final a = AppScope.read(context);
    final items = <SearchItem>[
      SearchItem(a.t('navHome'), Icons.home_outlined, 0),
      SearchItem(a.t('navHistory'), Icons.history, 1),
      SearchItem(a.t('navScan'), Icons.center_focus_strong, 2),
      SearchItem(a.routineText('routines'), Icons.checklist_rounded, 3),
      SearchItem(a.t('notifications'), Icons.notifications_outlined, -1),
      SearchItem(a.t('settings'), Icons.settings_outlined, 4),
      SearchItem(a.t('tip1t'), Icons.wb_sunny_outlined, 0),
      SearchItem(a.t('tip2t'), Icons.water_drop_outlined, 0),
      SearchItem(a.t('tip3t'), Icons.search_rounded, 0),
      SearchItem(a.t('gallery'), Icons.photo_library_outlined, 2),
      SearchItem(a.t('camera'), Icons.camera_alt_outlined, 2),
      SearchItem(a.t('language'), Icons.language_rounded, 4),
      SearchItem(a.t('appearance'), Icons.dark_mode_outlined, 4),
      SearchItem(a.t('subscription'), Icons.workspace_premium_outlined, 4),
    ];
    final tab = await showSearch<int?>(
      context: context,
      delegate: SkinSearch(
        items: items,
        hint: a.t('searchHint'),
        empty: a.t('noResults'),
      ),
    );
    if (tab == -1 && mounted) {
      _openNotifications();
    } else if (tab != null && mounted) {
      _selectTab(tab);
    }
  }

  void _openNotifications() {
    final a = AppScope.read(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (notificationContext) => NotificationCenterScreen(
          controller: a.routineController,
          language: a.lang.name,
          onOpenDeepLink: (uri) {
            Navigator.of(notificationContext).pop();
            _handleDeepLink(uri);
          },
          onMasterChanged: a.setNotificationsEnabled,
          onSettingsChanged: a.updateNotificationSettings,
        ),
      ),
    );
  }

  void _onMenu(String v) {
    final a = AppScope.read(context);
    if (v.startsWith('lang_')) {
      a.setLang(AppLang.values.firstWhere((l) => 'lang_${l.name}' == v));
    } else if (v == 'theme') {
      final dark = Theme.of(context).brightness == Brightness.dark;
      a.setTheme(dark ? ThemeMode.light : ThemeMode.dark);
    } else if (v == 'settings') {
      _selectTab(4);
    } else if (v == 'about') {
      showAboutDialog(
        context: context,
        applicationName: 'Skin AI',
        applicationVersion: '1.0.0',
        applicationIcon: const AppLogo(size: 52),
        children: [Text(a.t('aboutText'))],
      );
    } else if (v == 'signout') {
      _confirmSignOut();
    }
  }

  Widget _topBar(AppController a, Pal p) {
    final titles = [
      'Skin AI',
      a.t('history'),
      a.t('scanner'),
      a.routineText('routines'),
      a.t('settings'),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    PopupMenuItem<String> item(String value, IconData icon, String label,
        {bool checked = false}) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: p.text))),
            if (checked) Icon(Icons.check_rounded, size: 18, color: p.accent),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: p.nav.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          const AppLogo(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              titles[selectedIndex],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: selectedIndex == 0 && !a.isRtl ? 1 : 0,
                color: p.text,
              ),
            ),
          ),
          IconButton(
            tooltip: a.t('search'),
            onPressed: _openSearch,
            icon: Icon(Icons.search_rounded, color: p.sub),
          ),
          IconButton(
            tooltip: a.t('notifications'),
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: a.routineController.unseenNotificationCount > 0,
              label: Text(
                '${a.routineController.unseenNotificationCount}',
              ),
              child: Icon(Icons.notifications_none_rounded, color: p.sub),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: a.t('settings'),
            color: p.panel,
            onSelected: _onMenu,
            itemBuilder: (_) => [
              for (final l
                  in AppLang.values.where((value) => value.isReleaseReady))
                item('lang_${l.name}', Icons.language_rounded, langNames[l]!,
                    checked: l == a.lang),
              const PopupMenuDivider(),
              item(
                'theme',
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                isDark ? a.t('light') : a.t('dark'),
              ),
              item('settings', Icons.settings_outlined, a.t('settings')),
              item('about', Icons.info_outline_rounded, a.t('about')),
              const PopupMenuDivider(),
              item('signout', Icons.logout_rounded, a.t('signOut')),
            ],
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: brandGradient),
              ),
              alignment: Alignment.center,
              child: Text(
                a.initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);

    return NeonBackground(
      child: Column(
        children: [
          _topBar(a, p),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                _home(a, p),
                _history(a, p),
                _scanner(a, p),
                RoutineDashboardScreen(
                  controller: a.routineController,
                  language: a.lang.name,
                  accentColor: p.accent,
                  onOpenWidgets: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WidgetGalleryScreen(
                          controller: a.routineController,
                          language: a.lang.name,
                        ),
                      ),
                    );
                  },
                ),
                SettingsScreen(onLogout: _confirmSignOut),
              ],
            ),
          ),
          NavigationBar(
            backgroundColor: p.nav,
            indicatorColor: p.accent.withValues(alpha: 0.18),
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              _selectTab(index);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: p.accent),
                label: a.t('navHome'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.history),
                selectedIcon: Icon(Icons.history, color: p.accent),
                label: a.t('navHistory'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.center_focus_weak),
                selectedIcon: Icon(Icons.center_focus_strong, color: p.accent),
                label: a.t('navScan'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist_rounded, color: p.accent),
                label: a.routineText('routines'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded, color: p.accent),
                label: a.t('settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Home ----------

  Widget _home(AppController a, Pal p) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 6),
        Text(
          '${a.t('hello')} ${a.userName} 👋',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: p.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(a.t('homeSub'), style: TextStyle(color: p.sub)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(23),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: LinearGradient(colors: p.hero),
            border: Border.all(color: cyan.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: blue.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.face_retouching_natural,
                  color: Colors.white, size: 42),
              const SizedBox(height: 18),
              Text(
                a.t('aiAnalysis'),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                a.t('aiAnalysisDesc'),
                style: const TextStyle(color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _selectTab(2),
                  icon: const Icon(Icons.center_focus_strong),
                  label: Text(a.t('scanSkin')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0B3D91),
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SkinChatScreen(
                  baseUrl: a.defaultServer,
                  languageCode: a.lang.locale.languageCode,
                ),
              ),
            ),
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF112B49), Color(0xFF20234D)],
                ),
                border: Border.all(color: cyan.withValues(alpha: .28)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF12C7E8),
                    child: Icon(
                      Icons.health_and_safety_outlined,
                      color: Color(0xFF06202B),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SkinChat AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.lang == AppLang.ar
                              ? 'ارفع صورة وتحدث عنها مع مساعدك'
                              : a.lang == AppLang.ku
                                  ? 'وێنە باربکە و لەبارەی گفتوگۆ بکە'
                                  : a.lang == AppLang.badini
                                      ? 'وێنە بارکە و دەر بارێ وێ گفتوگۆ بکە'
                                      : 'Upload an image and ask follow-up questions',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          a.t('quick'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: p.text,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _quickAction(p, Icons.center_focus_strong, a.t('navScan'),
                () => _selectTab(2)),
            _quickAction(p, Icons.photo_library_outlined, a.t('gallery'), () {
              _selectTab(2);
            }),
            _quickAction(p, Icons.camera_alt_outlined, a.t('camera'), () {
              _selectTab(2);
            }),
            _quickAction(p, Icons.search_rounded, a.t('search'), _openSearch),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          a.t('workspace'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: p.text,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _featureCard(
                p,
                Icons.history_rounded,
                a.t('history'),
                a.t('historyShort'),
                () => setState(() => selectedIndex = 1),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: _featureCard(
                p,
                Icons.settings_outlined,
                a.t('settings'),
                a.t('profileShort'),
                () => setState(() => selectedIndex = 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          a.t('tips'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: p.text,
          ),
        ),
        const SizedBox(height: 14),
        _tip(p, Icons.wb_sunny_outlined, a.t('tip1t'), a.t('tip1d')),
        _tip(p, Icons.water_drop_outlined, a.t('tip2t'), a.t('tip2d')),
        _tip(p, Icons.search_rounded, a.t('tip3t'), a.t('tip3d')),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(p, radius: 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  a.t('disclaimer'),
                  style: TextStyle(color: p.sub, height: 1.6, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _quickAction(Pal p, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: p.accent.withValues(alpha: 0.14),
                  border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: p.accent),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.sub),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureCard(
    Pal p,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: p.accent, size: 29),
              const SizedBox(height: 15),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: p.text),
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: p.hint, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tip(Pal p, IconData icon, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(p, radius: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: p.accent.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(color: p.sub, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _scanConcerns = <(String, String, IconData)>[
    (
      'general_concern',
      'General skin concern',
      Icons.health_and_safety_outlined
    ),
    ('acne', 'Acne / Pimples', Icons.circle_outlined),
    ('redness', 'Redness', Icons.local_fire_department_outlined),
    ('rash', 'Rash', Icons.grain_rounded),
    ('dryness', 'Dryness', Icons.water_drop_outlined),
    ('dark_spots', 'Dark spots', Icons.blur_circular_outlined),
    ('itching', 'Itching', Icons.back_hand_outlined),
    ('swelling', 'Swelling', Icons.healing_outlined),
    ('mole_lesion', 'Mole or skin lesion', Icons.circle_outlined),
    ('irritation', 'Irritation', Icons.spa_outlined),
    ('other', 'Other', Icons.more_horiz_rounded),
    ('unsure', 'Not sure', Icons.help_outline_rounded),
  ];

  Widget _generalConcernCategoryCard(AppController a, Pal p) {
    const warning = Color(0xFFF59E0B);
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warning.withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _selectGeneralConcern,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.health_and_safety_outlined,
                      color: warning,
                      size: 23,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.t('generalSkinConcern'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        a.t('screeningTool'),
                        style: const TextStyle(
                          color: warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        a.t('generalConcernSubtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.sub,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodySelectionScreen(AppController a, Pal p) {
    final selectedRegion = bodyRegionOptions
        .where((region) => region.id == selectedBodyRegion)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          a.t('bodyConcernTitle'),
          style: TextStyle(
            color: p.text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          a.t('bodyConcernPrompt'),
          style: TextStyle(color: p.sub, height: 1.5),
        ),
        const SizedBox(height: 16),
        BodyRegionSelector(
          selectedRegion: selectedBodyRegion,
          accentColor: p.accent,
          panelColor: p.panel,
          textColor: p.text,
          mutedColor: p.sub,
          borderColor: p.border,
          localize: a.t,
          onSelected: (region) {
            setState(() {
              selectedBodyRegion = region.id;
              _locationController.text = region.label;
              selectedBodyPart = region.bodyPart;
              selectedBodySubregion =
                  region.id == region.bodyPart ? null : region.id;
              selectedBodySide = region.id.startsWith('left_')
                  ? 'left'
                  : region.id.startsWith('right_')
                      ? 'right'
                      : null;
              bodySelectionConfirmed = false;
              _sensitivePhotoConsent = false;
              picked = null;
              result = null;
              scanError = null;
              scannedAt = null;
            });
          },
          featuredCategoryCard: _generalConcernCategoryCard(a, p),
          onCleared: () {
            setState(() {
              selectedBodyRegion = null;
              selectedBodyPart = null;
              selectedBodySubregion = null;
              selectedBodySide = null;
              _locationController.clear();
              bodySelectionConfirmed = false;
              _sensitivePhotoConsent = false;
              picked = null;
              result = null;
              scanError = null;
              scannedAt = null;
            });
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() {
              selectedBodyRegion = null;
              selectedBodyPart = null;
              selectedBodySubregion = null;
              selectedBodySide = null;
              selectedConcern = null;
              _locationController.clear();
              bodySelectionConfirmed = true;
            }),
            icon: const Icon(Icons.skip_next_rounded),
            label: Text(a.t('continueWithoutLocation')),
          ),
        ),
        _medicalDisclaimerCard(a, p),
        if (selectedRegion != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: p.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.t(
                      'selectedArea',
                      arguments: {'area': selectedRegion.label},
                    ),
                    style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            a.t('whatWouldYouLikeToExamine'),
            style: TextStyle(
              color: p.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 300 ? 1 : 2;
              return GridView.builder(
                itemCount: _scanConcerns.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: crossAxisCount == 1 ? 76 : 88,
                ),
                itemBuilder: (context, index) {
                  final (id, label, icon) = _scanConcerns[index];
                  final selected = selectedConcern == id;
                  final title = id == 'general_concern'
                      ? a.t('generalSkinConcern')
                      : label;
                  return Material(
                    color: p.panel,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (id == 'general_concern') {
                          _selectGeneralConcern();
                          return;
                        }
                        setState(() {
                          selectedConcern = id;
                          bodySelectionConfirmed = false;
                          picked = null;
                          result = null;
                          scanError = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? p.accent.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? p.accent : p.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: selected ? p.accent : p.sub,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? p.accent : p.text,
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.privacy_tip_outlined, color: p.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.t('beforePhotoUpload'),
                    style: TextStyle(color: p.text, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          NeonButton(
            text: a.t('continue'),
            icon: Icons.arrow_forward_rounded,
            onTap: () => setState(() => bodySelectionConfirmed = true),
          ),
        ],
      ],
    );
  }

  Widget _selectedScanTaskCard(AppController a, Pal p) {
    final region = bodyRegionOptions
        .where((item) => item.id == selectedBodyRegion)
        .firstOrNull;
    final concern =
        _scanConcerns.where((item) => item.$1 == selectedConcern).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(
            _isGeneralConcern
                ? Icons.health_and_safety_outlined
                : Icons.location_on_outlined,
            color: p.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region?.label ??
                      (_isGeneralConcern
                          ? a.t('generalSkinConcern')
                          : 'Body area not selected'),
                  style: TextStyle(
                    color: p.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _scanConcernLabel(a, concern?.$1),
                  style: TextStyle(color: p.sub, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => bodySelectionConfirmed = false),
            child: Text(a.t('change')),
          ),
        ],
      ),
    );
  }

  Widget _photoGuidanceCard(AppController a, Pal p) {
    final group = bodyRegionOptions
        .where((item) => item.id == selectedBodyRegion)
        .firstOrNull
        ?.group;
    final guidance = switch (group) {
      'Head and face' => const [
          'Use natural, even lighting and a clear frontal or angled view.',
          'Keep the area visible; avoid filters and unnecessary distance.',
        ],
      'Hands' => const [
          'Capture the affected hand, fingers, palm, or nail clearly.',
          'Keep the camera steady and avoid motion blur.',
        ],
      'Upper body — back' => const [
          'Include the selected back area with sufficient lighting.',
          'Keep the skin concern in focus and visible.',
        ],
      'Feet' => const [
          'Frame the selected sole, heel, toe, nail, or top-of-foot area.',
          'Use sufficient light and keep the camera steady.',
        ],
      _ => const [
          'Use a clear, in-focus image with even lighting.',
          'Avoid filters and include only the selected skin area.',
        ],
    };
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.t('photoGuidance'),
            style: TextStyle(
              color: p.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in guidance)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 17, color: p.accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(color: p.sub, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionalTextField(
    AppController a,
    Pal p,
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: p.text),
        decoration: InputDecoration(
          labelText: a.t(label),
          labelStyle: TextStyle(color: p.sub),
          filled: true,
          fillColor: p.panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.border),
          ),
        ),
      ),
    );
  }

  Widget _medicalDisclaimerCard(AppController a, Pal p) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined, color: p.sub, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              a.t('disclaimer'),
              style: TextStyle(color: p.sub, height: 1.5, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Scanner ----------

  Widget _scanner(AppController a, Pal p) {
    if (!bodySelectionConfirmed) return _bodySelectionScreen(a, p);

    final r = result;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 18),
        Text(
          a.t('scanner'),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: p.text,
          ),
        ),
        const SizedBox(height: 12),
        Text(a.t('scannerDesc'), style: TextStyle(color: p.sub, height: 1.6)),
        const SizedBox(height: 14),
        _selectedScanTaskCard(a, p),
        const SizedBox(height: 14),
        _photoGuidanceCard(a, p),
        _optionalTextField(
          a,
          p,
          _locationController,
          'scanLocation',
        ),
        _optionalTextField(
          a,
          p,
          _durationController,
          'symptomsDuration',
        ),
        _optionalTextField(
          a,
          p,
          _symptomsController,
          'symptomsDetails',
          maxLines: 3,
        ),
        _optionalTextField(
          a,
          p,
          _changeController,
          'symptomsChange',
          maxLines: 2,
        ),
        _medicalDisclaimerCard(a, p),
        const SizedBox(height: 24),
        Container(
          height: 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: p.accent.withValues(alpha: 0.35)),
          ),
          child: picked != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(picked!, fit: BoxFit.cover),
                    if (!analyzing)
                      Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: IconButton.filledTonal(
                          tooltip: a.t('removeImage'),
                          onPressed: () => setState(() {
                            picked = null;
                            _accountHistoryConsent = false;
                            _originalImageConsent = false;
                            result = null;
                            scanError = null;
                            scannedAt = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    if (analyzing)
                      Container(
                        color: Colors.black54,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_uploadingImage)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 48),
                                child: LinearProgressIndicator(
                                  value: _uploadProgress,
                                ),
                              )
                            else
                              const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(
                              _uploadingImage
                                  ? '${a.t('uploadingImageProgress')} ${(_uploadProgress * 100).round()}%'
                                  : a.t('analyzing'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 65, color: p.accent),
                    const SizedBox(height: 18),
                    Text(
                      a.t('pickPrompt'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        PanelTile(
          icon: Icons.photo_library_outlined,
          title: a.t('gallery'),
          subtitle: a.t('galleryS'),
          onTap: analyzing ? () {} : () => _pick(ImageSource.gallery),
        ),
        PanelTile(
          icon: Icons.camera_alt_outlined,
          title: a.t('camera'),
          subtitle: a.t('cameraS'),
          onTap: analyzing ? () {} : () => _pick(ImageSource.camera),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: a.retainHistory,
          onChanged: analyzing
              ? null
              : (value) async {
                  try {
                    await a.setRetainHistory(value);
                  } on Exception {
                    if (mounted) {
                      showNotice(context, a.t('historySaveFailed'));
                    }
                  }
                },
          title: Text(
            a.t('historyConsent'),
            style: TextStyle(color: p.text, fontSize: 13),
          ),
          subtitle: Text(
            a.t('historyConsentDetail'),
            style: TextStyle(color: p.hint, fontSize: 11),
          ),
          activeThumbColor: p.accent,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _accountHistoryConsent,
          onChanged: analyzing
              ? null
              : (value) => setState(() {
                    _accountHistoryConsent = value;
                    if (!value) _originalImageConsent = false;
                  }),
          title: Text(
            a.t('accountHistoryConsent'),
            style: TextStyle(color: p.text, fontSize: 13),
          ),
          subtitle: Text(
            a.t('accountHistoryConsentDetail'),
            style: TextStyle(color: p.hint, fontSize: 11),
          ),
          activeThumbColor: p.accent,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _originalImageConsent,
          onChanged: analyzing ||
                  !_accountHistoryConsent ||
                  _medicalImageStorageConfigured != true
              ? null
              : (value) => setState(() => _originalImageConsent = value),
          title: Text(
            a.t('originalImageConsent'),
            style: TextStyle(color: p.text, fontSize: 13),
          ),
          subtitle: Text(
            _medicalImageStorageCheckFailed
                ? a.t('secureHistoryError')
                : _medicalImageStorageConfigured == true
                    ? a.t('originalImageConsentDetail')
                    : _checkingMedicalImageStorage
                        ? a.t('imageStorageChecking')
                        : a.t('imageStorageUnavailable'),
            style: TextStyle(color: p.hint, fontSize: 11),
          ),
          activeThumbColor: p.accent,
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: (picked == null || analyzing) ? 0.5 : 1,
          child: NeonButton(
            text: analyzing ? a.t('analyzing') : a.t('analyzeImage'),
            icon: Icons.auto_awesome,
            onTap: analyzing ? () {} : _analyze,
          ),
        ),
        if (scanError != null)
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFEF4444),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    scanError!,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (r != null) _resultCard(a, p, r),
        const SizedBox(height: 18),
        Text(
          a.t('privImg'),
          style: TextStyle(color: p.hint, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  Widget _resultCard(AppController a, Pal p, ScanResult r) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.panel.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.t('result'), style: TextStyle(color: p.hint, fontSize: 12)),
          const SizedBox(height: 10),
          SelectableText(
            r.cls,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(a.t('confidence'),
                  style: TextStyle(color: p.sub, fontSize: 12)),
              const Spacer(),
              Text(
                '${r.confidence.toStringAsFixed(1)}%',
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (r.confidence / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation<Color>(p.accent),
            ),
          ),
          const SizedBox(height: 18),
          MarkdownBody(
            data: r.summary,
            selectable: true,
            imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: p.sub, height: 1.5),
              h1: TextStyle(color: p.text, fontSize: 23),
              h2: TextStyle(color: p.text, fontSize: 20),
              h3: TextStyle(color: p.text, fontSize: 17),
              strong: TextStyle(
                color: p.text,
                fontWeight: FontWeight.w700,
              ),
              listBullet: TextStyle(color: p.accent),
              code: TextStyle(color: p.text, backgroundColor: p.border),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: exportingReport ? null : () => _exportReport(r),
              icon: exportingReport
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                exportingReport ? a.t('reportGenerating') : a.t('exportReport'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- History ----------

  Widget _history(AppController a, Pal p) {
    final scans = a.scans;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                a.t('history'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: p.text,
                ),
              ),
            ),
            IconButton(
              tooltip: a.t('refreshAccountHistory'),
              onPressed:
                  _refreshingAccountHistory ? null : _refreshAccountHistory,
              icon: _refreshingAccountHistory
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(a.t('historyDesc'), style: TextStyle(color: p.sub, height: 1.6)),
        const SizedBox(height: 6),
        Text(
          a.t('historySourceDesc'),
          style: TextStyle(color: p.hint, fontSize: 12, height: 1.5),
        ),
        if (_accountHistoryErrorStatus != null) ...[
          const SizedBox(height: 10),
          Text(
            _accountHistoryErrorStatus == 401
                ? a.t('secureHistoryAuthError')
                : _accountHistoryErrorStatus == 503
                    ? a.t('secureHistoryUnavailable')
                    : a.t('secureHistoryError'),
            style: const TextStyle(color: Color(0xFFEF4444)),
          ),
        ],
        const SizedBox(height: 20),
        if (scans.isEmpty) ...[
          const SizedBox(height: 25),
          Icon(Icons.history_rounded, size: 75, color: p.accent),
          const SizedBox(height: 18),
          Text(
            a.t('noScans'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: p.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            a.t('noScansDesc2'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.hint, height: 1.6),
          ),
        ],
        if (scans.any((scan) => !scan.accountRecord)) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: p.panel,
                    title: Text(a.t('clearLocalHistory'),
                        style: TextStyle(color: p.text)),
                    content: Text(
                      a.t('clearLocalHistoryConfirm'),
                      style: TextStyle(color: p.sub),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(a.t('cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(a.t('clearLocalHistory')),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await a.clearScans();
                  } on Exception {
                    if (mounted) {
                      showNotice(context, a.t('historyDeleteFailed'));
                    }
                  }
                }
              },
              icon:
                  Icon(Icons.delete_outline_rounded, color: p.accent, size: 18),
              label: Text(a.t('clearLocalHistory'),
                  style: TextStyle(color: p.accent)),
            ),
          ),
        ],
        for (final sc in scans) _scanTile(a, p, sc),
      ],
    );
  }

  Widget _scanTile(AppController a, Pal p, ScanRecord sc) {
    final d = DateTime.fromMillisecondsSinceEpoch(sc.ts);
    String two(int n) => n.toString().padLeft(2, '0');

    return GestureDetector(
      onTap: () => _showScanDetails(a, p, sc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(p, radius: 17),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: p.accent.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.analytics_outlined, color: p.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayScanLabel(a, sc.cls),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.t(sc.accountRecord
                        ? 'accountHistoryLabel'
                        : 'localHistoryLabel'),
                    style: TextStyle(color: p.hint, fontSize: 10),
                  ),
                  if (sc.bodyLocation?.isNotEmpty == true ||
                      sc.bodySubregion != null ||
                      sc.bodyPart != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      sc.bodyLocation?.isNotEmpty == true
                          ? sc.bodyLocation!
                          : [
                              if (sc.bodySide != null) sc.bodySide!,
                              sc.bodySubregion ?? sc.bodyPart!,
                              if (sc.concernType != null) sc.concernType!,
                            ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.sub, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${sc.conf.toStringAsFixed(1)}%  ·  ${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}',
                    style: TextStyle(color: p.hint, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: a.t('deleteRecord'),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: p.panel,
                    title: Text(
                      a.t('deleteRecord'),
                      style: TextStyle(color: p.text),
                    ),
                    content: Text(
                      a.t('historyDeleteConfirm'),
                      style: TextStyle(color: p.sub),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(a.t('cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(a.t('deleteRecord')),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await a.removeScan(sc);
                } on Exception {
                  if (mounted) {
                    showNotice(context, a.t('historyDeleteFailed'));
                  }
                }
              },
              icon: Icon(Icons.delete_outline_rounded, color: p.hint),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showScanDetails(AppController a, Pal p, ScanRecord scan) async {
    final locationController = TextEditingController(
      text: scan.bodyLocation ??
          [
            if (scan.bodySide != null) scan.bodySide!,
            if (scan.bodySubregion != null) scan.bodySubregion!,
          ].join(' '),
    );
    final notesController = TextEditingController(text: scan.notes ?? '');
    final imageFuture = scan.accountRecord && scan.hasOriginalImage
        ? a.getAccountScanImage(scan)
        : null;
    var saving = false;
    var saveFailed = false;
    final d = DateTime.fromMillisecondsSinceEpoch(scan.ts);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: p.panel,
            title: Text(
              _displayScanLabel(a, scan.cls),
              style: TextStyle(color: p.text),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${a.t('scanDate')}: ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                      style: TextStyle(color: p.sub),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${a.t('scanConfidence')}: ${scan.conf.toStringAsFixed(1)}%',
                      style: TextStyle(color: p.sub),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationController,
                      readOnly: !scan.accountRecord,
                      decoration: InputDecoration(
                        labelText: a.t('bodyLocation'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesController,
                      readOnly: !scan.accountRecord,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: a.t('notes')),
                    ),
                    if (scan.summary?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Text(
                        scan.summary!,
                        style: TextStyle(color: p.sub, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (imageFuture != null)
                      FutureBuilder<Uint8List>(
                        future: imageFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(
                              a.t('originalImageLoadError'),
                              style: const TextStyle(color: Color(0xFFEF4444)),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.contain,
                            ),
                          );
                        },
                      )
                    else
                      Text(
                        a.t('originalImageNotStored'),
                        style: TextStyle(color: p.hint, fontSize: 12),
                      ),
                    if (saveFailed) ...[
                      const SizedBox(height: 8),
                      Text(
                        a.t('secureHistoryError'),
                        style: const TextStyle(color: Color(0xFFEF4444)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(a.t('close')),
              ),
              if (scan.accountRecord)
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                            saveFailed = false;
                          });
                          try {
                            await a.updateAccountScan(
                              scan,
                              bodyLocation: locationController.text.trim(),
                              notes: notesController.text.trim(),
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } on Exception {
                            setDialogState(() {
                              saving = false;
                              saveFailed = true;
                            });
                          }
                        },
                  child: Text(
                    saving ? a.t('saving') : a.t('saveDetails'),
                  ),
                ),
            ],
          ),
        ),
      );
    } finally {
      locationController.dispose();
      notesController.dispose();
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.memberLabel,
    required this.onTap,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final String memberLabel;
  final VoidCallback onTap;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    if (parts.isEmpty) return '?';
    final words = parts.toList();
    final first = String.fromCharCode(words.first.runes.first).toUpperCase();
    if (words.length == 1) return first;
    return '$first${String.fromCharCode(words.last.runes.first).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.settingsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRtl = AppScope.of(context).isRtl;
    final uri = photoUrl == null ? null : Uri.tryParse(photoUrl!);
    final hasPhoto = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final initials = _initials;
    const cardRadius = 24.0;

    Widget avatarFallback() => Center(
          child: Text(
            initials,
            style: TextStyle(
              color: p.accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: p.border),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.18)
                  : const Color(0x0C173867),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: brandGradient),
                  ),
                  child: Container(
                    width: 60,
                    height: 60,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: p.panel,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => avatarFallback(),
                            )
                          : avatarFallback(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'SkinAI Member' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.sub, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              p.accent.withValues(alpha: isDark ? 0.16 : 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                color: p.accent,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  memberLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: isRtl ? 0 : 0.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: p.hint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  const SettingsScreen({super.key, required this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _chooseGoal() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _label(a, 'primaryGoal'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final goal in const [
                'acne',
                'spots',
                'antiAging',
                'hydration',
                'soothing',
                'brightening',
                'pores',
              ])
                ListTile(
                  title: Text(
                    _label(a, 'goal_$goal'),
                    style: TextStyle(color: p.text),
                  ),
                  trailing: a.skincareGoal == goal
                      ? Icon(Icons.check_circle_rounded, color: p.accent)
                      : null,
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    await a.setSkincareGoal(goal);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editServer() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    final controller = TextEditingController(text: a.serverUrl);
    String? connectionStatus;
    bool testing = false;
    bool connectionSucceeded = false;
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: p.panel,
              title: Text(a.t('serverAddr'), style: TextStyle(color: p.text)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    style: TextStyle(color: p.text),
                    decoration: InputDecoration(
                      hintText: a.t('serverHint'),
                      hintStyle: TextStyle(color: p.hint),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _label(a, 'serverTestHint'),
                    style: TextStyle(color: p.sub, fontSize: 12),
                  ),
                  if (connectionStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      connectionStatus!,
                      style: TextStyle(
                        color: connectionSucceeded
                            ? (Theme.of(dialogContext).brightness ==
                                    Brightness.dark
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFF15803D))
                            : p.accent,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: testing
                      ? null
                      : () => Navigator.pop(dialogContext, a.defaultServer),
                  child: Text(a.t('resetDefault')),
                ),
                TextButton(
                  onPressed: testing
                      ? null
                      : () async {
                          setDialogState(() {
                            testing = true;
                            connectionStatus = null;
                            connectionSucceeded = false;
                          });
                          try {
                            await SkinApi.testConnection(
                              controller.text,
                              languageCode: a.lang.locale.languageCode,
                            );
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              connectionStatus = _label(a, 'serverConnected');
                              connectionSucceeded = true;
                            });
                          } on ApiException catch (error) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              connectionStatus = error.statusCode == 503
                                  ? a.t('apiServiceUnavailable')
                                  : a.t('apiRequestFailed');
                              connectionSucceeded = false;
                            });
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => testing = false);
                            }
                          }
                        },
                  child: testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_label(a, 'testConnection')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(a.t('cancel')),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, controller.text.trim()),
                  child: Text(a.t('save')),
                ),
              ],
            );
          },
        ),
      );
      if (value != null && value.isNotEmpty) await a.setServer(value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _chooseReminderTime() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    final theme = Theme.of(context);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: a.reminderHour, minute: a.reminderMinute),
      builder: (context, child) => Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            surface: p.panel,
            onSurface: p.text,
            primary: p.accent,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    try {
      await a.setReminderTime(time);
    } on Exception catch (error) {
      if (mounted) {
        showNotice(context, '${_label(a, 'reminderError')} $error');
      }
    }
  }

  Future<void> _chooseLanguage() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _label(a, 'language'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final language in AppLang.values)
                ListTile(
                  title: Text(
                    langNames[language]!,
                    style: TextStyle(
                      color: language.isReleaseReady
                          ? p.text
                          : p.text.withValues(alpha: 0.65),
                    ),
                  ),
                  subtitle: language.isReleaseReady
                      ? null
                      : Text(_label(a, 'badiniPending')),
                  trailing: a.lang == language
                      ? Icon(Icons.check_circle_rounded, color: p.accent)
                      : language.isReleaseReady
                          ? null
                          : Icon(
                              Icons.lock_outline_rounded,
                              color: p.sub,
                              size: 18,
                            ),
                  contentPadding: EdgeInsets.zero,
                  enabled: language.isReleaseReady,
                  onTap: () async {
                    await a.setLang(language);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTheme() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _label(a, 'theme'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  title: Text(
                    _label(
                      a,
                      switch (mode) {
                        ThemeMode.system => 'auto',
                        ThemeMode.light => 'light',
                        ThemeMode.dark => 'dark',
                      },
                    ),
                    style: TextStyle(color: p.text),
                  ),
                  trailing: a.themeMode == mode
                      ? Icon(Icons.check_circle_rounded, color: p.accent)
                      : null,
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    await a.setTheme(mode);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseAccentColor() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    const choices = [
      Color(0xFF0066FF),
      Color(0xFF00D4FF),
      Color(0xFF7B2CBF),
      Color(0xFF10B981),
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.panel,
        title: Text(_label(a, 'accentColor'), style: TextStyle(color: p.text)),
        content: Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (final color in choices)
              Tooltip(
                message: _label(
                  a,
                  color == const Color(0xFF00D4FF)
                      ? 'cyanAccent'
                      : color == const Color(0xFF7B2CBF)
                          ? 'purpleAccent'
                          : color == const Color(0xFF10B981)
                              ? 'emeraldAccent'
                              : 'electricBlue',
                ),
                child: InkWell(
                  onTap: () async {
                    await a.setAccentColor(color);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: a.accentColor == color ? p.text : p.border,
                        width: a.accentColor == color ? 3 : 1,
                      ),
                    ),
                    child: a.accentColor == color
                        ? const Icon(Icons.check_rounded, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setNotifications(bool value) async {
    final a = AppScope.read(context);
    try {
      await a.setNotificationsEnabled(value);
    } on ReminderPermissionDeniedException {
      if (mounted) {
        showNotice(context, _label(a, 'notificationPermission'));
      }
    } on Exception catch (error) {
      if (mounted) {
        showNotice(context, '${_label(a, 'notificationError')} $error');
      }
    }
  }

  Future<void> _editProfile() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    final nameController = TextEditingController(text: a.userName);
    String? name;
    try {
      name = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: p.panel,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            0,
            22,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _label(a, 'editProfile'),
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _label(a, 'displayName'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_label(a, 'email')}: ${a.userEmail}',
                  style: TextStyle(color: p.sub),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext)
                      .pop(nameController.text.trim()),
                  child: Text(_label(a, 'save')),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      nameController.dispose();
    }
    if (name == null || !mounted) return;

    final result = await a.updateProfileName(name);
    if (!mounted) return;
    showNotice(
      context,
      result == AuthError.none
          ? _label(a, 'profileUpdated')
          : _authErrorText(a, result),
    );
  }

  Future<void> _showAccountSecurity() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _label(a, 'accountSecurity'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: p.accent),
                title: Text(
                  _label(a, 'editProfile'),
                  style: TextStyle(color: p.text),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_editProfile());
                },
              ),
              ListTile(
                leading: Icon(Icons.lock_reset_rounded, color: p.accent),
                title: Text(
                  _label(a, 'changePassword'),
                  style: TextStyle(color: p.text),
                ),
                subtitle: Text(
                  _label(a, 'passwordResetInfo'),
                  style: TextStyle(color: p.sub),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_sendPasswordReset());
                },
              ),
              ListTile(
                leading: Icon(Icons.mail_outline_rounded, color: p.accent),
                title: Text(
                  _label(a, 'email'),
                  style: TextStyle(color: p.text),
                ),
                subtitle: Text(
                  a.userEmail,
                  style: TextStyle(color: p.sub),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.logout_rounded,
                  color: isDark
                      ? const Color(0xFFFF8A80)
                      : const Color(0xFFD32F2F),
                ),
                title: Text(
                  _label(a, 'signOut'),
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFFF8A80)
                        : const Color(0xFFD32F2F),
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await widget.onLogout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendPasswordReset() async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    if (a.userEmail.isEmpty) {
      showNotice(context, _label(a, 'passwordResetUnavailable'));
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.panel,
        title:
            Text(_label(a, 'changePassword'), style: TextStyle(color: p.text)),
        content: Text(
          _label(a, 'passwordResetConfirm').replaceAll('{email}', a.userEmail),
          style: TextStyle(color: p.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_label(a, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_label(a, 'sendReset')),
          ),
        ],
      ),
    );
    if (send != true) return;
    final result = await a.sendPasswordResetEmail(a.userEmail);
    if (!mounted) return;
    showNotice(
      context,
      result == AuthError.none
          ? _label(a, 'passwordResetSent')
          : _authErrorText(a, result),
    );
  }

  Future<void> _showInformation(String key, String body) async {
    final a = AppScope.read(context);
    final p = Pal.settingsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label(a, key),
                style: TextStyle(
                  color: p.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(body, style: TextStyle(color: p.sub, height: 1.55)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.settingsOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String text(String key) => a.settingsText(key);
    final ink = p.text;
    final muted = p.sub;
    final blueAccent = a.accentColor;
    const cyanAccent = Color(0xFF17B8D5);
    const violetAccent = Color(0xFF8757E8);
    final canvas = p.bg;
    final border = p.border;
    final isRtl = a.isRtl;
    final photoUrl = a.profilePhotoUrl;
    final memberSince = a.memberSince;
    final memberLine = memberSince == null
        ? text('member')
        : text('memberSince').replaceAll('{year}', '${memberSince.year}');
    final profileAnswers = [
      for (int i = 0; i < quiz.length; i++)
        if (a.answerText(i) != null) a.answerText(i)!,
    ];
    final profileSummary = [
      '${text('skinType')}: ${text(a.skinType)}',
      '${text('primaryGoal')}: ${text('goal_${a.skincareGoal}')}',
      '${text('dailyReminder')}: ${TimeOfDay(hour: a.reminderHour, minute: a.reminderMinute).format(context)}',
      ...profileAnswers,
    ];

    Widget section(String title, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 22, 4, 10),
              child: Text(
                title,
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: isRtl ? 0 : 1.05,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
                boxShadow: isDark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x080D2850),
                          blurRadius: 22,
                          offset: Offset(0, 8),
                        ),
                      ],
              ),
              child: child,
            ),
          ],
        );

    Widget skinTypeSelector() => LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 10) / 2;
            const types = [
              ('oily', Icons.water_drop_outlined),
              ('dry', Icons.wb_sunny_outlined),
              ('combination', Icons.blur_on_rounded),
              ('sensitive', Icons.favorite_border_rounded),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (type, icon) in types)
                  SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => unawaited(a.setSkinType(type)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: a.skinType == type
                              ? blueAccent.withValues(alpha: 0.18)
                              : isDark
                                  ? const Color(0xFF1E293B)
                                  : p.panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: a.skinType == type
                                ? blueAccent
                                : isDark
                                    ? const Color(0xFF334155)
                                    : border,
                            width: a.skinType == type ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: a.skinType == type
                                  ? blueAccent
                                  : isDark
                                      ? const Color(0xFFE2E8F0)
                                      : p.sub,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                text(type),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: a.skinType == type
                                      ? blueAccent
                                      : isDark
                                          ? const Color(0xFFE2E8F0)
                                          : p.sub,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (a.skinType == type)
                              Icon(
                                Icons.check_circle_rounded,
                                color: blueAccent,
                                size: 16,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );

    Widget themeSelector() => SegmentedButton<ThemeMode>(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? blueAccent : p.sub,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? blueAccent.withValues(alpha: 0.16)
                  : p.panel,
            ),
            side: WidgetStatePropertyAll(BorderSide(color: border)),
          ),
          showSelectedIcon: false,
          segments: [
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              label: Text(text('auto')),
              icon: const Icon(Icons.phone_android_rounded, size: 16),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              label: Text(text('light')),
              icon: const Icon(Icons.light_mode_rounded, size: 16),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              label: Text(text('dark')),
              icon: const Icon(Icons.dark_mode_rounded, size: 16),
            ),
          ],
          selected: {a.themeMode},
          onSelectionChanged: (selection) =>
              unawaited(a.setTheme(selection.first)),
        );

    Widget preferenceRow({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
      Color? accent,
      bool last = false,
      Widget? trailing,
    }) =>
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (accent ?? blueAccent).withValues(
                          alpha: isDark ? 0.15 : 0.09,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, size: 20, color: accent ?? blueAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    trailing ??
                        Icon(
                          isRtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 21,
                          color: const Color(0xFFAAB3C3),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget divider() => Padding(
          padding: const EdgeInsetsDirectional.only(start: 52, bottom: 14),
          child: Divider(height: 1, color: border),
        );

    Widget infoTile({
      required String title,
      required IconData icon,
      required Widget child,
    }) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              backgroundColor: p.panel,
              collapsedBackgroundColor: p.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Icon(icon, color: blueAccent, size: 21),
              title: Text(
                title,
                style: TextStyle(
                  color: ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              iconColor: blueAccent,
              collapsedIconColor: muted,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [child],
            ),
          ),
        );

    return Material(
      color: canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 380 ? 16.0 : 22.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 14, horizontalPadding, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileCard(
                        name: a.userName.isEmpty
                            ? text('skinAiMember')
                            : a.userName,
                        email: a.userEmail,
                        photoUrl: photoUrl,
                        memberLabel: memberLine,
                        onTap: _editProfile,
                      ),
                      section(
                        text('skinAiSettings'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            preferenceRow(
                              icon: Icons.spa_outlined,
                              title: text('primaryGoal'),
                              value: text('goal_${a.skincareGoal}'),
                              accent: violetAccent,
                              onTap: _chooseGoal,
                            ),
                            divider(),
                            preferenceRow(
                              icon: Icons.alarm_rounded,
                              title: text('dailyReminder'),
                              value: TimeOfDay(
                                hour: a.reminderHour,
                                minute: a.reminderMinute,
                              ).format(context),
                              accent: cyanAccent,
                              last: true,
                              onTap: _chooseReminderTime,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              text('skinType'),
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            skinTypeSelector(),
                          ],
                        ),
                      ),
                      section(
                        _label(a, 'myProfile'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final summary in profileSummary)
                              Chip(
                                label: Text(
                                  summary,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor:
                                    blueAccent.withValues(alpha: 0.1),
                                side: BorderSide(color: border),
                              ),
                          ],
                        ),
                      ),
                      section(
                        text('preferences'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            preferenceRow(
                              icon: Icons.language_rounded,
                              title: text('language'),
                              value: langNames[a.lang]!,
                              onTap: _chooseLanguage,
                            ),
                            divider(),
                            preferenceRow(
                              icon: Icons.palette_outlined,
                              title: text('theme'),
                              value: text(
                                switch (a.themeMode) {
                                  ThemeMode.system => 'auto',
                                  ThemeMode.light => 'light',
                                  ThemeMode.dark => 'dark',
                                },
                              ),
                              accent: violetAccent,
                              onTap: _chooseTheme,
                            ),
                            const SizedBox(height: 3),
                            themeSelector(),
                            const SizedBox(height: 18),
                            preferenceRow(
                              icon: Icons.dns_outlined,
                              title: _label(a, 'serverAddr'),
                              value: a.serverUrl,
                              accent: cyanAccent,
                              onTap: _editServer,
                            ),
                            const SizedBox(height: 18),
                            preferenceRow(
                              icon: Icons.color_lens_outlined,
                              title: text('accentColor'),
                              value: text(
                                a.accentColor == const Color(0xFF00D4FF)
                                    ? 'cyanAccent'
                                    : a.accentColor == const Color(0xFF7B2CBF)
                                        ? 'purpleAccent'
                                        : a.accentColor ==
                                                const Color(0xFF10B981)
                                            ? 'emeraldAccent'
                                            : 'electricBlue',
                              ),
                              accent: violetAccent,
                              onTap: _chooseAccentColor,
                            ),
                            const SizedBox(height: 18),
                            preferenceRow(
                              icon: Icons.notifications_active_outlined,
                              title: text('notifications'),
                              value: a.notificationsEnabled
                                  ? text('enabled')
                                  : text('disabled'),
                              accent: blueAccent,
                              last: true,
                              onTap: () => unawaited(
                                _setNotifications(!a.notificationsEnabled),
                              ),
                              trailing: Switch.adaptive(
                                value: a.notificationsEnabled,
                                activeThumbColor: blueAccent,
                                onChanged: (value) =>
                                    unawaited(_setNotifications(value)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      section(
                        text('aboutDataSources'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            infoTile(
                              title: text('howSkinAiWorks'),
                              icon: Icons.auto_awesome_outlined,
                              child: Text(
                                text('howSkinAiWorksBody'),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: muted,
                                  height: 1.55,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            infoTile(
                              title: text('scanProvider'),
                              icon: Icons.cloud_outlined,
                              child: Text(
                                text('scanProviderDescription'),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: muted,
                                  height: 1.55,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      section(
                        text('accountSecurity'),
                        Column(
                          children: [
                            preferenceRow(
                              icon: Icons.shield_outlined,
                              title: text('manageAccount'),
                              value: text('accountSecuritySub'),
                              accent: cyanAccent,
                              onTap: _showAccountSecurity,
                            ),
                            divider(),
                            preferenceRow(
                              icon: Icons.lock_outline_rounded,
                              title: text('privacy'),
                              value: text('privacySub'),
                              accent: violetAccent,
                              onTap: () => unawaited(
                                _showInformation(
                                  'privacy',
                                  text('privacyPolicy'),
                                ),
                              ),
                            ),
                            divider(),
                            preferenceRow(
                              icon: Icons.info_outline_rounded,
                              title: text('about'),
                              value: text('version'),
                              accent: blueAccent,
                              last: true,
                              onTap: () => unawaited(
                                _showInformation(
                                  'about',
                                  '${text('aboutDescription')}\n\n${text('version')}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Material(
                        color: isDark
                            ? const Color(0xFF3B1F2B)
                            : const Color(0xFFFFF4F3),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: widget.onLogout,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 17,
                              vertical: 15,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF63303E)
                                    : const Color(0xFFFFE2DE),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  color: isDark
                                      ? const Color(0xFFFF8A80)
                                      : const Color(0xFFE45D59),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  text('signOut'),
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFFFB4AB)
                                        : const Color(0xFFD94E4A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _label(AppController controller, String key) {
  return controller.settingsText(key);
}

// -------------------- Search --------------------

class SearchItem {
  final String label;
  final IconData icon;
  final int tab;
  const SearchItem(this.label, this.icon, this.tab);
}

class SkinSearch extends SearchDelegate<int?> {
  final List<SearchItem> items;
  final String hint;
  final String empty;

  SkinSearch({required this.items, required this.hint, required this.empty})
      : super(searchFieldLabel: hint);

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final p = Pal.of(context);
    final q = query.trim().toLowerCase();
    final found =
        items.where((e) => e.label.toLowerCase().contains(q)).toList();
    if (found.isEmpty) {
      return Center(child: Text(empty, style: TextStyle(color: p.hint)));
    }
    return ListView(
      children: [
        for (final e in found)
          ListTile(
            leading: Icon(e.icon, color: p.accent),
            title: Text(e.label),
            onTap: () => close(context, e.tab),
          ),
      ],
    );
  }
}

// -------------------- 10-question onboarding --------------------

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int index = 0;
  late List<int> answers;
  bool _answersInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_answersInitialized) return;
    answers = List<int>.of(AppScope.read(context).pendingAnswers);
    _answersInitialized = true;
  }

  void _next() {
    if (answers[index] < 0) return;
    if (index < quiz.length - 1) {
      setState(() => index++);
    } else {
      AppScope.read(context).pendingAnswers = List<int>.of(answers);
      Navigator.pushReplacement(context, fadeRoute(const AuthScreen()));
    }
  }

  void _back() {
    if (index > 0) {
      setState(() => index--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = AppScope.of(context);
    final p = Pal.of(context);
    final q = quiz[index];
    final texts = q.of(a.lang.name);
    final options = texts.sublist(1);
    final isLast = index == quiz.length - 1;
    final selected = answers[index];

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: NeonBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _back,
                        icon: Icon(
                          a.isRtl
                              ? Icons.arrow_forward_ios_rounded
                              : Icons.arrow_back_ios_new_rounded,
                          color: p.sub,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: (index + 1) / quiz.length,
                            ),
                            duration: const Duration(milliseconds: 350),
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 8,
                              backgroundColor: p.border,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(p.accent),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const QuickSettings(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 12),
                      child: Text(
                        a
                            .t('qOf')
                            .replaceAll('{n}', '${index + 1}')
                            .replaceAll('{t}', '${quiz.length}'),
                        style: TextStyle(color: p.hint, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.08, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey<int>(index),
                        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  color: p.accent.withValues(alpha: 0.14),
                                  border: Border.all(
                                    color: p.accent.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Icon(q.icon, color: p.accent, size: 36),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              texts.first,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                height: 1.3,
                                fontWeight: FontWeight.w800,
                                color: p.text,
                              ),
                            ),
                            const SizedBox(height: 24),
                            for (int i = 0; i < options.length; i++)
                              _option(p, options[i], selected == i, () {
                                setState(() => answers[index] = i);
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: selected < 0 ? 0.45 : 1,
                    child: NeonButton(
                      text: isLast ? a.t('finish') : a.t('next'),
                      icon: isLast
                          ? Icons.check_rounded
                          : (a.isRtl
                              ? Icons.arrow_back_rounded
                              : Icons.arrow_forward_rounded),
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(Pal p, String text, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? p.accent.withValues(alpha: 0.14)
                  : p.panel.withValues(alpha: 0.9),
              border: Border.all(
                color: selected ? p.accent : p.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? p.accent : p.hint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
