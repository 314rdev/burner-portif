import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> saveFile(String fileName, Uint8List bytes, String mimeType) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri == null ? null : 'Saved $fileName';
  }

  final dir = await getDownloadsDirectory() ??
      Directory(Platform.environment['HOME'] ?? Directory.current.path);
  await dir.create(recursive: true);
  final file = await _uniqueFile(dir, fileName);
  await file.writeAsBytes(bytes, flush: true);
  return 'Saved to ${file.path}';
}

/// `report.pdf` -> `report (1).pdf` if the name is taken.
Future<File> _uniqueFile(Directory dir, String fileName) async {
  final safe = fileName.replaceAll(RegExp(r'[/\\\x00]'), '_');
  final dot = safe.lastIndexOf('.');
  final base = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';
  var candidate = File('${dir.path}${Platform.pathSeparator}$safe');
  for (var i = 1; await candidate.exists(); i++) {
    candidate = File('${dir.path}${Platform.pathSeparator}$base ($i)$ext');
  }
  return candidate;
}
