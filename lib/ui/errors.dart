import 'package:http/http.dart' as http;

import '../services/drop_service.dart';
import '../services/firebase_exception.dart';

/// Turns any error thrown by the services into a user-facing sentence.
String describeError(Object error) {
  if (error is FirebaseRestException) return error.friendly;
  if (error is DropValidationException) return error.message;
  if (error is http.ClientException) {
    return 'Network error. Check your connection and try again.';
  }
  final text = '$error';
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'Network error. Check your connection and try again.';
  }
  return text;
}
