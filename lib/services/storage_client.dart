import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/firebase_config.dart';
import 'firebase_exception.dart';
import 'firestore_client.dart' show TokenProvider;

/// Reports bytes transferred so far out of [total].
typedef ProgressCallback = void Function(int sent, int total);

/// Minimal Cloud Storage for Firebase client over the v0 REST API (the same
/// endpoint the official SDKs use), so `storage.rules` apply.
/// [StorageClient.anonymous] sends no token; it is used for public links.
class StorageClient {
  StorageClient(this._config, TokenProvider token, {http.Client? client})
      : _token = token,
        _http = client ?? http.Client();

  StorageClient.anonymous(this._config, {http.Client? client})
      : _token = null,
        _http = client ?? http.Client();

  final FirebaseConfig _config;
  final TokenProvider? _token;
  final http.Client _http;

  Future<Map<String, String>> _auth() async {
    final token = _token;
    return token == null ? {} : {'Authorization': 'Firebase ${await token()}'};
  }

  String get _base =>
      'https://firebasestorage.googleapis.com/v0/b/${_config.storageBucket}/o';

  Uri _objectUri(String path, [Map<String, String>? query]) => Uri.parse(
          '$_base/${Uri.encodeComponent(path)}')
      .replace(queryParameters: query);

  /// Uploads [data] (of [length] bytes) to [path].
  ///
  /// On web, the browser client buffers the body before sending, so progress
  /// reaches 100% before the network transfer finishes.
  Future<void> upload(
    String path,
    Stream<List<int>> data, {
    required int length,
    required String contentType,
    ProgressCallback? onProgress,
  }) async {
    final request = http.StreamedRequest(
      'POST',
      Uri.parse(_base).replace(queryParameters: {'name': path}),
    )
      ..headers.addAll(await _auth())
      ..headers['Content-Type'] = contentType
      ..contentLength = length;

    var sent = 0;
    final pump = data.listen(
      (chunk) {
        sent += chunk.length;
        request.sink.add(chunk);
        onProgress?.call(sent, length);
      },
      onError: request.sink.addError,
      onDone: request.sink.close,
      cancelOnError: true,
    );

    try {
      final response = await http.Response.fromStream(await _http.send(request));
      FirebaseRestException.check(response);
    } finally {
      await pump.cancel();
    }
  }

  /// Downloads the object at [path] into memory.
  Future<Uint8List> download(
    String path, {
    int? expectedLength,
    ProgressCallback? onProgress,
  }) async {
    final request = http.Request('GET', _objectUri(path, {'alt': 'media'}))
      ..headers.addAll(await _auth());
    final response = await _http.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw FirebaseRestException.fromResponse(response.statusCode, body);
    }
    final total = response.contentLength ?? expectedLength ?? 0;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      onProgress?.call(builder.length, total);
    }
    return builder.takeBytes();
  }

  /// Deletes the object at [path]. Missing objects are ignored.
  Future<void> delete(String path) async {
    final response = await _http.delete(
      _objectUri(path),
      headers: await _auth(),
    );
    if (response.statusCode == 404) return;
    FirebaseRestException.check(response);
  }
}
