import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/firebase_config.dart';
import 'firebase_exception.dart';

/// Signature of a function that returns a fresh Firebase ID token.
typedef TokenProvider = Future<String> Function();

/// Converts between plain Dart values and Firestore REST `Value` JSON.
class FirestoreCodec {
  const FirestoreCodec._();

  static Map<String, dynamic> encodeFields(Map<String, Object?> data) => {
        for (final entry in data.entries) entry.key: encodeValue(entry.value),
      };

  static Map<String, dynamic> encodeValue(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is String) return {'stringValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(encodeValue).toList()},
      };
    }
    if (value is Map<String, Object?>) {
      return {
        'mapValue': {'fields': encodeFields(value)},
      };
    }
    throw ArgumentError('Unsupported Firestore value: ${value.runtimeType}');
  }

  static Map<String, dynamic> decodeFields(Map<String, dynamic>? fields) => {
        if (fields != null)
          for (final entry in fields.entries)
            entry.key: decodeValue(entry.value as Map<String, dynamic>),
      };

  static Object? decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('booleanValue')) return value['booleanValue'] as bool;
    if (value.containsKey('integerValue')) {
      return int.parse('${value['integerValue']}');
    }
    if (value.containsKey('doubleValue')) {
      return (value['doubleValue'] as num).toDouble();
    }
    if (value.containsKey('stringValue')) return value['stringValue'] as String;
    if (value.containsKey('timestampValue')) {
      return DateTime.parse(value['timestampValue'] as String);
    }
    if (value.containsKey('arrayValue')) {
      final values = (value['arrayValue'] as Map)['values'] as List? ?? const [];
      return values
          .map((v) => decodeValue(v as Map<String, dynamic>))
          .toList();
    }
    if (value.containsKey('mapValue')) {
      return decodeFields(
          (value['mapValue'] as Map)['fields'] as Map<String, dynamic>?);
    }
    if (value.containsKey('referenceValue')) {
      return value['referenceValue'] as String;
    }
    if (value.containsKey('bytesValue')) return value['bytesValue'] as String;
    return null;
  }
}

/// A document returned by [FirestoreClient].
class FirestoreDocument {
  const FirestoreDocument(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}

/// One write inside a [FirestoreClient.commit] call.
class FirestoreWrite {
  FirestoreWrite._(this._json);

  final Map<String, dynamic> _json;

  /// Creates [path] with [data]; fails with ALREADY_EXISTS if it exists.
  /// Fields listed in [serverTimestamps] are set to the request time.
  factory FirestoreWrite.create(
    String documentName,
    Map<String, Object?> data, {
    List<String> serverTimestamps = const [],
  }) =>
      FirestoreWrite._({
        'update': {
          'name': documentName,
          'fields': FirestoreCodec.encodeFields(data),
        },
        'currentDocument': {'exists': false},
        if (serverTimestamps.isNotEmpty)
          'updateTransforms': [
            for (final f in serverTimestamps)
              {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
          ],
      });

  /// Merges [data] into [path] (creating it if needed), applies numeric
  /// [increments] and sets [serverTimestamps] to the request time.
  factory FirestoreWrite.merge(
    String documentName, {
    Map<String, Object?> data = const {},
    Map<String, num> increments = const {},
    List<String> serverTimestamps = const [],
    bool mustExist = false,
  }) =>
      FirestoreWrite._({
        'update': {
          'name': documentName,
          'fields': FirestoreCodec.encodeFields(data),
        },
        'updateMask': {'fieldPaths': data.keys.toList()},
        if (mustExist) 'currentDocument': {'exists': true},
        'updateTransforms': [
          for (final entry in increments.entries)
            {
              'fieldPath': entry.key,
              'increment': FirestoreCodec.encodeValue(entry.value),
            },
          for (final f in serverTimestamps)
            {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
        ],
      });

  factory FirestoreWrite.delete(String documentName) =>
      FirestoreWrite._({'delete': documentName});

  Map<String, dynamic> toJson() => _json;
}

/// Minimal Cloud Firestore client over the v1 REST API.
///
/// Requests carry the user's Firebase ID token, so `firestore.rules` apply
/// exactly as they would with the official SDKs. A client built with
/// [FirestoreClient.anonymous] sends no token (`request.auth == null` in the
/// rules); it is used for public links.
class FirestoreClient {
  FirestoreClient(this._config, TokenProvider token, {http.Client? client})
      : _token = token,
        _http = client ?? http.Client();

  FirestoreClient.anonymous(this._config, {http.Client? client})
      : _token = null,
        _http = client ?? http.Client();

  final FirebaseConfig _config;
  final TokenProvider? _token;
  final http.Client _http;

  String get _root =>
      'projects/${_config.projectId}/databases/(default)/documents';

  String get _baseUrl => 'https://firestore.googleapis.com/v1/$_root';

  /// Builds a request URL; anonymous requests identify the project by key.
  Uri _url(String suffix) {
    final uri = Uri.parse('$_baseUrl$suffix');
    return _token == null
        ? uri.replace(queryParameters: {'key': _config.apiKey})
        : uri;
  }

  /// Full resource name for a document path such as `drops/ABC123`.
  String documentName(String path) => '$_root/$path';

  Future<Map<String, String>> _headers() async {
    final token = _token;
    return {
      if (token != null) 'Authorization': 'Bearer ${await token()}',
      'Content-Type': 'application/json',
    };
  }

  /// Reads one document, or returns null if it does not exist.
  Future<FirestoreDocument?> get(String path) async {
    final response =
        await _http.get(_url('/$path'), headers: await _headers());
    if (response.statusCode == 404) return null;
    return _toDocument(FirebaseRestException.check(response));
  }

  /// Atomically applies [writes].
  Future<void> commit(List<FirestoreWrite> writes) async {
    final response = await _http.post(
      _url(':commit'),
      headers: await _headers(),
      body: jsonEncode({'writes': writes.map((w) => w.toJson()).toList()}),
    );
    FirebaseRestException.check(response);
  }

  Future<void> delete(String path) async {
    final response =
        await _http.delete(_url('/$path'), headers: await _headers());
    if (response.statusCode == 404) return;
    FirebaseRestException.check(response);
  }

  /// Returns documents in [collection] whose [field] equals [value].
  Future<List<FirestoreDocument>> whereEqual(
    String collection,
    String field,
    Object value, {
    int limit = 100,
  }) async {
    final response = await _http.post(
      _url(':runQuery'),
      headers: await _headers(),
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collection},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': FirestoreCodec.encodeValue(value),
            },
          },
          'limit': limit,
        },
      }),
    );
    final rows = FirebaseRestException.checkRaw(response) as List;
    return [
      for (final row in rows)
        if ((row as Map)['document'] != null)
          _toDocument(row['document'] as Map<String, dynamic>),
    ];
  }

  FirestoreDocument _toDocument(Map<String, dynamic> json) {
    final name = json['name'] as String;
    return FirestoreDocument(
      name.substring(name.lastIndexOf('/') + 1),
      FirestoreCodec.decodeFields(json['fields'] as Map<String, dynamic>?),
    );
  }
}
