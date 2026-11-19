import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/firebase_config.dart';
import 'firebase_exception.dart';

/// The signed-in Firebase user.
class AuthUser {
  const AuthUser({required this.uid, required this.email});

  final String uid;
  final String email;
}

/// Firebase Authentication (email + password) over the Identity Toolkit REST
/// API, so the same code runs on Linux, web and Android.
///
/// The refresh token is persisted with shared_preferences; the short-lived ID
/// token is kept in memory and refreshed on demand by [idToken].
class AuthService extends ChangeNotifier {
  AuthService(this._config, {http.Client? client})
      : _http = client ?? http.Client();

  static const _prefsKey = 'burner.auth.session';
  static const _identityBase = 'https://identitytoolkit.googleapis.com/v1';
  static const _tokenBase = 'https://securetoken.googleapis.com/v1';

  final FirebaseConfig _config;
  final http.Client _http;

  AuthUser? _user;
  String? _idToken;
  String? _refreshToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _refreshing;
  bool _restoring = true;

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;

  /// True until the persisted session (if any) has been restored.
  bool get isRestoring => _restoring;

  /// Restores a session saved by a previous run.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _refreshToken = data['refreshToken'] as String?;
      _user = AuthUser(
        uid: data['uid'] as String,
        email: data['email'] as String? ?? '',
      );
      // Validate the refresh token now so a revoked session signs out early.
      await idToken();
    } on FirebaseRestException catch (e) {
      if (e.isAuthError) {
        await signOut();
      }
      // Network errors keep the cached session; the next call will retry.
    } catch (_) {
      await signOut();
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) =>
      _passwordAuth('accounts:signInWithPassword', email, password);

  Future<void> signUp(String email, String password) =>
      _passwordAuth('accounts:signUp', email, password);

  Future<void> sendPasswordReset(String email) async {
    await _postJson(
      Uri.parse('$_identityBase/accounts:sendOobCode?key=${_config.apiKey}'),
      {'requestType': 'PASSWORD_RESET', 'email': email.trim()},
    );
  }

  Future<void> signOut() async {
    _user = null;
    _idToken = null;
    _refreshToken = null;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  /// Returns a valid ID token, refreshing it when it is about to expire.
  Future<String> idToken() {
    final token = _idToken;
    if (token != null &&
        DateTime.now().isBefore(_expiresAt.subtract(const Duration(minutes: 1)))) {
      return Future.value(token);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      throw const FirebaseRestException('NOT_SIGNED_IN', 'You are not signed in.');
    }
    final response = await _http.post(
      Uri.parse('$_tokenBase/token?key=${_config.apiKey}'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    final data = FirebaseRestException.check(response);
    _idToken = data['id_token'] as String;
    _refreshToken = data['refresh_token'] as String;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: int.parse(data['expires_in'] as String)));
    await _persist();
    return _idToken!;
  }

  Future<void> _passwordAuth(String endpoint, String email, String password) async {
    final data = await _postJson(
      Uri.parse('$_identityBase/$endpoint?key=${_config.apiKey}'),
      {
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    _user = AuthUser(
      uid: data['localId'] as String,
      email: data['email'] as String? ?? email.trim(),
    );
    _idToken = data['idToken'] as String;
    _refreshToken = data['refreshToken'] as String;
    _expiresAt = DateTime.now()
        .add(Duration(seconds: int.parse(data['expiresIn'] as String)));
    await _persist();
    notifyListeners();
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, Object?> body) async {
    final response = await _http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return FirebaseRestException.check(response);
  }

  Future<void> _persist() async {
    final user = _user;
    if (user == null || _refreshToken == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'uid': user.uid,
        'email': user.email,
        'refreshToken': _refreshToken,
      }),
    );
  }
}
