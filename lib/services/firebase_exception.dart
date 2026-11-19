import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error returned by one of the Firebase REST APIs.
class FirebaseRestException implements Exception {
  const FirebaseRestException(this.code, this.message, {this.statusCode});

  /// Machine-readable code, e.g. `EMAIL_NOT_FOUND`, `PERMISSION_DENIED`,
  /// `NOT_FOUND`, `ALREADY_EXISTS`.
  final String code;
  final String message;
  final int? statusCode;

  static const _authCodes = {
    'TOKEN_EXPIRED',
    'USER_DISABLED',
    'USER_NOT_FOUND',
    'INVALID_REFRESH_TOKEN',
    'INVALID_GRANT_TYPE',
    'MISSING_REFRESH_TOKEN',
    'NOT_SIGNED_IN',
  };

  bool get isAuthError => _authCodes.contains(code);
  bool get isNotFound => code == 'NOT_FOUND' || statusCode == 404;
  bool get isPermissionDenied =>
      code == 'PERMISSION_DENIED' || statusCode == 403;
  bool get alreadyExists => code == 'ALREADY_EXISTS' || statusCode == 409;

  /// Decodes a successful JSON response body, or throws.
  static dynamic checkRaw(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const <String, dynamic>{};
      return jsonDecode(response.body);
    }
    throw fromResponse(response.statusCode, response.body);
  }

  /// Like [checkRaw] but expects a JSON object.
  static Map<String, dynamic> check(http.Response response) {
    final data = checkRaw(response);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static FirebaseRestException fromResponse(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map) {
        final message = '${error['message'] ?? 'Unknown error'}';
        final status = error['status'] as String?;
        // Identity Toolkit puts the code in `message`, sometimes followed by
        // " : details". Firestore/Storage put it in `status`.
        final authCode = message.split(' ').first;
        final isUpperSnake = RegExp(r'^[A-Z_]+$').hasMatch(authCode);
        final code = isUpperSnake ? authCode : (status ?? 'HTTP_$statusCode');
        return FirebaseRestException(code, message, statusCode: statusCode);
      }
      if (error is String) {
        return FirebaseRestException(error.toUpperCase(), error,
            statusCode: statusCode);
      }
    } catch (_) {
      // Not JSON; fall through.
    }
    return FirebaseRestException('HTTP_$statusCode',
        body.isEmpty ? 'Request failed ($statusCode)' : body,
        statusCode: statusCode);
  }

  /// A message suitable for showing to the user.
  String get friendly {
    switch (code) {
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Wrong email or password.';
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists.';
      case 'INVALID_EMAIL':
        return 'That email address is not valid.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email/password sign-in is disabled in the Firebase console.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Try again later.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'PERMISSION_DENIED':
        return 'Permission denied. Check that the Firebase rules are deployed.';
      case 'NOT_FOUND':
        return 'Not found. The code may be wrong, expired or already burned.';
      case 'NOT_SIGNED_IN':
        return 'You are not signed in.';
    }
    if (code.startsWith('WEAK_PASSWORD')) {
      return 'Password must be at least 6 characters.';
    }
    return message;
  }

  @override
  String toString() => 'FirebaseRestException($code): $message';
}
