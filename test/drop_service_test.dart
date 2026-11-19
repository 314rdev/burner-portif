import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:burner/config/firebase_config.dart';
import 'package:burner/models/drop.dart';
import 'package:burner/services/auth_service.dart';
import 'package:burner/services/drop_service.dart';
import 'package:burner/services/firestore_client.dart';
import 'package:burner/services/storage_client.dart';
import 'package:burner/util/codes.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = FirebaseConfig(
  apiKey: 'key',
  projectId: 'proj',
  storageBucket: 'bucket',
);

void main() {
  late List<http.Request> requests;
  late MockClient client;
  late AuthService auth;
  late DropService drops;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    client = MockClient((request) async {
      requests.add(request);
      final url = request.url.toString();
      if (url.contains('accounts:signInWithPassword')) {
        return http.Response(
          jsonEncode({
            'localId': 'uid1',
            'email': 'a@b.c',
            'idToken': 'tok',
            'refreshToken': 'ref',
            'expiresIn': '3600',
          }),
          200,
        );
      }
      if (url.contains(':commit') || url.contains('firebasestorage')) {
        return http.Response('{}', 200);
      }
      return http.Response('{"error":{"code":404,"status":"NOT_FOUND"}}', 404);
    });
    auth = AuthService(config, client: client);
    drops = DropService(
      auth: auth,
      firestore: FirestoreClient(config, auth.idToken, client: client),
      storage: StorageClient(config, auth.idToken, client: client),
      publicFirestore: FirestoreClient.anonymous(config, client: client),
      publicStorage: StorageClient.anonymous(config, client: client),
    );
    await auth.signIn('a@b.c', 'secret1');
  });

  test('create uploads files and commits drop + usage atomically', () async {
    final dir = await Directory.systemTemp.createTemp('burner_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/my file.txt')
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    final drop = await drops.create(DropRequest(
      text: '  hi  ',
      files: [XFile(file.path)],
      burnAfterRead: true,
    ));

    expect(drop.text, 'hi');
    expect(drop.files.single.size, 3);
    expect(drop.files.single.path,
        matches(RegExp(r'^drops/uid1/[A-Za-z0-9]{20}/0_my_file\.txt$')));

    final upload = requests.firstWhere((r) => r.url.host == 'firebasestorage.googleapis.com');
    expect(upload.method, 'POST');
    expect(upload.headers['Authorization'], 'Firebase tok');
    expect(upload.url.queryParameters['name'], drop.files.single.path);
    expect(upload.bodyBytes, [1, 2, 3]);

    final commit = requests.firstWhere((r) => r.url.path.endsWith(':commit'));
    expect(commit.headers['Authorization'], 'Bearer tok');
    final writes = (jsonDecode(commit.body) as Map)['writes'] as List;
    expect(writes, hasLength(2));
    final create = writes[0] as Map;
    expect(create['currentDocument'], {'exists': false});
    expect((create['update'] as Map)['name'],
        'projects/proj/databases/(default)/documents/drops/${drop.code}');
    expect(create['updateTransforms'],
        [{'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'}]);
    final usage = writes[1] as Map;
    expect((usage['update'] as Map)['name'], endsWith('/users/uid1'));
  });

  test('public drops use a long token, always burn, and share the folder', () async {
    final drop = await drops.create(const DropRequest(text: 'hi', isPublic: true));
    expect(drop.isPublic, isTrue);
    expect(drop.burnAfterRead, isTrue);
    expect(DropCodes.publicTokenPattern.hasMatch(drop.code), isTrue);

    final commit = requests.firstWhere((r) => r.url.path.endsWith(':commit'));
    final create = ((jsonDecode(commit.body) as Map)['writes'] as List)[0] as Map;
    final fields = (create['update'] as Map)['fields'] as Map;
    expect(fields['public'], {'booleanValue': true});
    expect(fields['burnAfterRead'], {'booleanValue': true});
  });

  test('public lookups and opens send no auth token', () async {
    requests.clear();
    final token = DropCodes.publicToken();
    expect(await drops.findPublic(token), isNull);
    final drop = Drop(
      code: token,
      ownerUid: 'someone',
      text: 'x',
      files: const [],
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      burnAfterRead: true,
      isPublic: true,
    );
    await drops.openPublic(drop);

    for (final r in requests) {
      expect(r.headers.containsKey('Authorization'), isFalse, reason: '${r.url}');
      expect(r.url.queryParameters['key'], 'key');
    }
    final writes = (jsonDecode(requests.last.body) as Map)['writes'] as List;
    final open = writes.single as Map;
    expect((open['update'] as Map)['fields'], {'burned': {'booleanValue': true}});
    expect(open['updateMask'], {'fieldPaths': ['burned']});
    expect(open['updateTransforms'], [
      {'fieldPath': 'downloads', 'increment': {'integerValue': '1'}},
      {'fieldPath': 'burnedAt', 'setToServerValue': 'REQUEST_TIME'},
    ]);
    expect(open['currentDocument'], {'exists': true});
  });

  test('create rejects empty drops', () async {
    expect(() => drops.create(const DropRequest(text: '   ')),
        throwsA(isA<DropValidationException>()));
  });

  test('find returns null for unknown codes', () async {
    expect(await drops.find('ABC234'), isNull);
  });
}
