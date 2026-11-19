import 'dart:typed_data';

import 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Saves downloaded bytes on the current platform:
/// - Linux/desktop: writes to the Downloads folder (never overwrites).
/// - Android: opens the system "save as" dialog.
/// - Web: triggers a browser download.
///
/// Returns a short description of where the file went, or null if the user
/// cancelled.
Future<String?> saveDownloadedFile(
  String fileName,
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) =>
    impl.saveFile(fileName, bytes, mimeType);
