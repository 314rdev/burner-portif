import 'package:burner/models/drop.dart';
import 'package:burner/services/firebase_exception.dart';
import 'package:burner/services/firestore_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('codec round-trips nested values', () {
    final data = <String, Object?>{
      'n': null,
      'b': true,
      'i': 42,
      'd': 1.5,
      's': 'hi',
      't': DateTime.utc(2026, 11, 18, 10, 30),
      'l': [1, 'two'],
      'm': {'k': 'v'},
    };
    final decoded = FirestoreCodec.decodeFields(FirestoreCodec.encodeFields(data));
    expect(decoded, data);
  });

  test('integers are encoded as strings', () {
    expect(FirestoreCodec.encodeValue(7), {'integerValue': '7'});
  });

  test('Drop survives a Firestore round-trip', () {
    final drop = Drop(
      code: 'ABC234',
      ownerUid: 'u1',
      text: 'hello',
      files: const [
        DropFile(name: 'a.txt', size: 3, contentType: 'text/plain', path: 'drops/u1/x/0_a.txt'),
      ],
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 1, 2),
      burnAfterRead: true,
    );
    final stored = FirestoreCodec.decodeFields(
      FirestoreCodec.encodeFields({...drop.toCreateMap(), 'createdAt': drop.createdAt}),
    );
    final back = Drop.fromMap('ABC234', stored);
    expect(back.text, 'hello');
    expect(back.files.single.path, 'drops/u1/x/0_a.txt');
    expect(back.burnAfterRead, isTrue);
    expect(back.burned, isFalse);
    expect(back.expiresAt, drop.expiresAt);
    expect(back.totalBytes, 3);
  });

  group('FirebaseRestException.fromResponse', () {
    test('auth errors take the code from message', () {
      final e = FirebaseRestException.fromResponse(
          400, '{"error":{"code":400,"message":"WEAK_PASSWORD : Password should be at least 6 characters"}}');
      expect(e.code, 'WEAK_PASSWORD');
      expect(e.friendly, contains('6 characters'));
    });

    test('firestore errors take the code from status', () {
      final e = FirebaseRestException.fromResponse(403,
          '{"error":{"code":403,"message":"Missing or insufficient permissions.","status":"PERMISSION_DENIED"}}');
      expect(e.code, 'PERMISSION_DENIED');
      expect(e.isPermissionDenied, isTrue);
    });

    test('non-JSON bodies fall back to HTTP status', () {
      final e = FirebaseRestException.fromResponse(502, 'Bad gateway');
      expect(e.code, 'HTTP_502');
    });
  });
}
