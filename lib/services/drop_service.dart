import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import '../models/drop.dart';
import '../util/codes.dart';
import 'auth_service.dart';
import 'firebase_exception.dart';
import 'firestore_client.dart';
import 'storage_client.dart';

/// Limits shared with `firestore.rules` / `storage.rules`. Keep them in sync.
class DropLimits {
  const DropLimits._();

  static const maxFileBytes = 100 * 1024 * 1024; // 100 MB per file
  static const maxFiles = 20;
  static const maxTextChars = 100000;
  static const maxTtl = Duration(days: 7);

  static const ttlOptions = [
    Duration(minutes: 10),
    Duration(hours: 1),
    Duration(hours: 24),
    Duration(days: 7),
  ];
  static const defaultTtl = Duration(hours: 1);
}

/// What the user wants to send.
class DropRequest {
  const DropRequest({
    this.text = '',
    this.files = const [],
    this.ttl = DropLimits.defaultTtl,
    this.burnAfterRead = false,
    this.isPublic = false,
  });

  final String text;
  final List<XFile> files;
  final Duration ttl;
  final bool burnAfterRead;

  /// Opened from a link without signing in. Always burns on first open.
  final bool isPublic;

  bool get isEmpty => text.trim().isEmpty && files.isEmpty;
}

/// Thrown for input that the rules would reject anyway.
class DropValidationException implements Exception {
  const DropValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All drop operations: create, look up, receive, download, delete, and the
/// usage counters in `users/{uid}`.
///
/// There is no backend: every call goes straight to Firestore/Storage with
/// the user's ID token and is authorised by the security rules.
class DropService {
  DropService({
    required this._auth,
    required this._firestore,
    required this._storage,
    required this._publicFirestore,
    required this._publicStorage,
  });

  final AuthService _auth;
  final FirestoreClient _firestore;
  final StorageClient _storage;

  /// Token-less clients for public links (receiver not signed in).
  final FirestoreClient _publicFirestore;
  final StorageClient _publicStorage;

  /// How long files of a burned public drop stay downloadable, so the
  /// receiver can finish downloading after opening. Mirrors storage.rules.
  static const publicDownloadWindow = Duration(minutes: 15);

  String get _uid {
    final user = _auth.user;
    if (user == null) {
      throw const FirebaseRestException('NOT_SIGNED_IN', 'You are not signed in.');
    }
    return user.uid;
  }

  String _dropDoc(String code) => _firestore.documentName('drops/$code');
  String _userDoc(String uid) => _firestore.documentName('users/$uid');

  /// Uploads the files and registers the drop. Returns the created drop.
  ///
  /// [onProgress] receives overall bytes uploaded across all files.
  Future<Drop> create(
    DropRequest request, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final uid = _uid;
    final text = request.text.trim();
    if (request.isEmpty) {
      throw const DropValidationException('Add some text or at least one file.');
    }
    if (text.length > DropLimits.maxTextChars) {
      throw const DropValidationException(
          'Text is too long (max ${DropLimits.maxTextChars} characters).');
    }
    if (request.files.length > DropLimits.maxFiles) {
      throw const DropValidationException(
          'Too many files (max ${DropLimits.maxFiles} per drop).');
    }
    if (request.ttl > DropLimits.maxTtl) {
      throw const DropValidationException('Expiry can be at most 7 days.');
    }

    final sizes = <int>[];
    for (final file in request.files) {
      final size = await file.length();
      if (size > DropLimits.maxFileBytes) {
        throw DropValidationException(
            '"${file.name}" is larger than ${DropLimits.maxFileBytes ~/ (1024 * 1024)} MB.');
      }
      sizes.add(size);
    }
    final total = sizes.fold(0, (a, b) => a + b);

    // Public drops use their token as both document id and Storage folder,
    // so storage.rules can look the drop up for token-less downloads.
    final publicToken = request.isPublic ? DropCodes.publicToken() : null;
    final folder = 'drops/$uid/${publicToken ?? DropCodes.storageId()}';
    final uploaded = <DropFile>[];
    var done = 0;
    try {
      for (var i = 0; i < request.files.length; i++) {
        final file = request.files[i];
        final contentType = file.mimeType ?? guessContentType(file.name);
        final path = '$folder/${i}_${safeObjectName(file.name)}';
        await _storage.upload(
          path,
          file.openRead(),
          length: sizes[i],
          contentType: contentType,
          onProgress: (sent, _) => onProgress?.call(done + sent, total),
        );
        done += sizes[i];
        uploaded.add(DropFile(
          name: file.name,
          size: sizes[i],
          contentType: contentType,
          path: path,
        ));
      }

      final now = DateTime.now();
      for (var attempt = 0;; attempt++) {
        final drop = Drop(
          code: publicToken ?? DropCodes.generate(),
          ownerUid: uid,
          text: text,
          files: uploaded,
          createdAt: now,
          expiresAt: now.add(request.ttl),
          burnAfterRead: request.isPublic || request.burnAfterRead,
          isPublic: request.isPublic,
        );
        try {
          await _firestore.commit([
            FirestoreWrite.create(
              _dropDoc(drop.code),
              drop.toCreateMap(),
              serverTimestamps: const ['createdAt'],
            ),
            FirestoreWrite.merge(
              _userDoc(uid),
              increments: {'dropsCreated': 1, 'bytesUploaded': total},
              serverTimestamps: const ['lastActiveAt'],
            ),
          ]);
          return drop;
        } on FirebaseRestException catch (e) {
          // A code collision surfaces as ALREADY_EXISTS, or as
          // PERMISSION_DENIED because the rules treat it as an update.
          final collision = e.alreadyExists || e.isPermissionDenied;
          if (!collision || attempt >= 2) rethrow;
        }
      }
    } catch (_) {
      // Don't leave orphaned objects behind if registration failed.
      for (final f in uploaded) {
        try {
          await _storage.delete(f.path);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Looks a drop up by code. Returns null when it does not exist, has
  /// expired or was burned (the rules hide those from non-owners).
  Future<Drop?> find(String code) async {
    try {
      final doc = await _firestore.get('drops/$code');
      if (doc == null) return null;
      final drop = Drop.fromMap(doc.id, doc.data);
      if (drop.ownerUid != _uid && !drop.isActive()) return null;
      return drop;
    } on FirebaseRestException catch (e) {
      if (e.isPermissionDenied || e.isNotFound) return null;
      rethrow;
    }
  }

  /// Records that the current user opened [drop]: bumps its download counter
  /// and burns it if it is burn-after-read. No-op for the owner.
  Future<void> markReceived(Drop drop) async {
    final uid = _uid;
    if (drop.ownerUid == uid) return;
    await _firestore.commit([
      FirestoreWrite.merge(
        _dropDoc(drop.code),
        data: {if (drop.burnAfterRead) 'burned': true},
        increments: const {'downloads': 1},
        serverTimestamps: [if (drop.burnAfterRead) 'burnedAt'],
        mustExist: true,
      ),
      FirestoreWrite.merge(
        _userDoc(uid),
        increments: const {'dropsReceived': 1},
        serverTimestamps: const ['lastActiveAt'],
      ),
    ]);
  }

  /// Looks up a public drop by its link token, without signing in. Returns
  /// null if it does not exist, expired or was already opened.
  Future<Drop?> findPublic(String token) async {
    try {
      final doc = await _publicFirestore.get('drops/$token');
      if (doc == null) return null;
      final drop = Drop.fromMap(doc.id, doc.data);
      return drop.isPublic && drop.isActive() ? drop : null;
    } on FirebaseRestException catch (e) {
      if (e.isPermissionDenied || e.isNotFound) return null;
      rethrow;
    }
  }

  /// Opens (burns) a public drop. After this nobody can open the link again;
  /// its files stay downloadable for [publicDownloadWindow].
  Future<void> openPublic(Drop drop) async {
    await _publicFirestore.commit([
      FirestoreWrite.merge(
        _publicFirestore.documentName('drops/${drop.code}'),
        data: const {'burned': true},
        increments: const {'downloads': 1},
        serverTimestamps: const ['burnedAt'],
        mustExist: true,
      ),
    ]);
  }

  /// Downloads a file of a public drop without signing in.
  Future<Uint8List> downloadPublic(
    DropFile file, {
    void Function(int received, int total)? onProgress,
  }) =>
      _publicStorage.download(
        file.path,
        expectedLength: file.size,
        onProgress: onProgress,
      );

  /// Downloads one file of a drop into memory.
  Future<Uint8List> download(
    DropFile file, {
    void Function(int received, int total)? onProgress,
  }) async {
    final bytes = await _storage.download(
      file.path,
      expectedLength: file.size,
      onProgress: onProgress,
    );
    try {
      await _firestore.commit([
        FirestoreWrite.merge(
          _userDoc(_uid),
          increments: {'bytesDownloaded': bytes.length},
          serverTimestamps: const ['lastActiveAt'],
        ),
      ]);
    } catch (_) {
      // Usage tracking is best-effort; never fail a download over it.
    }
    return bytes;
  }

  /// The current user's drops, newest first.
  Future<List<Drop>> myDrops() async {
    final docs = await _firestore.whereEqual('drops', 'ownerUid', _uid);
    final drops = [for (final d in docs) Drop.fromMap(d.id, d.data)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return drops;
  }

  /// Deletes a drop the current user owns, files first.
  Future<void> delete(Drop drop) async {
    for (final f in drop.files) {
      await _storage.delete(f.path);
    }
    await _firestore.delete('drops/${drop.code}');
  }

  /// Deletes the current user's expired or burned drops. Best-effort; returns
  /// how many were removed. Storage lifecycle rules and Firestore TTL (see
  /// README) are the backstop for drops whose owner never comes back.
  Future<int> cleanup() async {
    var removed = 0;
    for (final drop in await myDrops()) {
      if (drop.isActive()) continue;
      try {
        await delete(drop);
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  Future<UsageStats> usage() async {
    final doc = await _firestore.get('users/$_uid');
    return doc == null ? const UsageStats() : UsageStats.fromMap(doc.data);
  }
}

/// Makes a file name safe to use as the last segment of a Storage path.
String safeObjectName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final trimmed = cleaned.length > 100 ? cleaned.substring(cleaned.length - 100) : cleaned;
  return trimmed.isEmpty ? 'file' : trimmed;
}

/// Best-effort MIME type from a file extension.
String guessContentType(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  const types = {
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'html': 'text/html',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'apk': 'application/vnd.android.package-archive',
    'deb': 'application/vnd.debian.binary-package',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return types[ext] ?? 'application/octet-stream';
}
