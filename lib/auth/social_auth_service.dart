import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SocialAuthService {
  SocialAuthService(this._auth, {this.webClientId});

  final FirebaseAuth _auth;
  final String? webClientId;
  GoogleSignIn? _googleSignIn;
  OAuthCredential? _pendingCredential;

  GoogleSignIn get _googleSignInInstance {
    if (kIsWeb && (webClientId == null || webClientId!.isEmpty)) {
      throw UnsupportedError(
        'Configure GOOGLE_SIGN_IN_WEB_CLIENT_ID to enable Google sign-in on web.',
      );
    }
    return _googleSignIn ??= GoogleSignIn(
      scopes: const ['email'],
      clientId: kIsWeb ? webClientId : null,
    );
  }

  User? get currentUser => _auth.currentUser;

  bool get hasPendingCredential => _pendingCredential != null;

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignInInstance.signIn();
    if (googleUser == null) return null;

    try {
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null && accessToken == null) {
        throw FirebaseAuthException(
          code: 'invalid-credential',
          message: 'Google did not return an authentication token.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      return await _signInWithCredential(credential);
    } on Object {
      await _googleSignInInstance.signOut();
      rethrow;
    }
  }

  Future<UserCredential?> signInWithApple() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('Apple sign-in is configured for iOS only.');
    }
    if (!await SignInWithApple.isAvailable()) {
      throw UnsupportedError(
          'Sign in with Apple is unavailable on this device.');
    }

    final rawNonce = _secureNonce();
    final hashedNonce = sha256.convert(rawNonce.codeUnits).toString();
    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
    final idToken = appleCredential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Apple did not return an identity token.',
      );
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );
    final userCredential = await _signInWithCredential(oauthCredential);
    final user = userCredential.user;
    final displayName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');

    if (user != null &&
        (user.displayName == null || user.displayName!.trim().isEmpty) &&
        displayName.isNotEmpty) {
      await user.updateDisplayName(displayName);
    }
    return userCredential;
  }

  Future<UserCredential> _signInWithCredential(
    OAuthCredential credential,
  ) async {
    try {
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'account-exists-with-different-credential') {
        final pending = error.credential;
        if (pending is OAuthCredential) {
          _pendingCredential = pending;
        }
      }
      rethrow;
    }
  }

  Future<UserCredential> linkPendingCredential() async {
    final user = _auth.currentUser;
    final credential = _pendingCredential;
    if (user == null || credential == null) {
      throw FirebaseAuthException(code: 'no-pending-credential');
    }

    final linked = await user.linkWithCredential(credential);
    _pendingCredential = null;
    return linked;
  }

  void discardPendingCredential() {
    _pendingCredential = null;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _pendingCredential = null;
    final googleSignIn = _googleSignIn;
    if (googleSignIn != null) await googleSignIn.signOut();
  }

  String _secureNonce([int length = 32]) {
    const characters =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }
}
