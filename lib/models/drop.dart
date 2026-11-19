/// A file attached to a drop, stored in Cloud Storage at [path].
class DropFile {
  const DropFile({
    required this.name,
    required this.size,
    required this.contentType,
    required this.path,
  });

  final String name;
  final int size;
  final String contentType;
  final String path;

  Map<String, Object?> toMap() => {
        'name': name,
        'size': size,
        'contentType': contentType,
        'path': path,
      };

  factory DropFile.fromMap(Map<String, dynamic> map) => DropFile(
        name: map['name'] as String? ?? 'file',
        size: (map['size'] as num?)?.toInt() ?? 0,
        contentType: map['contentType'] as String? ?? 'application/octet-stream',
        path: map['path'] as String,
      );
}

/// A drop: text and/or files shared under a short code.
///
/// Stored at `drops/{code}` in Firestore. See `firestore.rules` for the
/// allowed shape; keep [toMap] and the rules in sync.
class Drop {
  const Drop({
    required this.code,
    required this.ownerUid,
    required this.text,
    required this.files,
    required this.createdAt,
    required this.expiresAt,
    required this.burnAfterRead,
    this.burned = false,
    this.downloads = 0,
  });

  final String code;
  final String ownerUid;
  final String text;
  final List<DropFile> files;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// When true, the first recipient to open the drop burns it.
  final bool burnAfterRead;
  final bool burned;
  final int downloads;

  bool get hasText => text.isNotEmpty;
  bool get hasFiles => files.isNotEmpty;
  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  bool isExpired([DateTime? now]) =>
      !(now ?? DateTime.now()).isBefore(expiresAt);

  bool isActive([DateTime? now]) => !burned && !isExpired(now);

  /// Fields written on creation. `createdAt` is set by the server.
  Map<String, Object?> toCreateMap() => {
        'ownerUid': ownerUid,
        'text': text,
        'files': files.map((f) => f.toMap()).toList(),
        'expiresAt': expiresAt,
        'burnAfterRead': burnAfterRead,
        'burned': false,
        'downloads': 0,
      };

  factory Drop.fromMap(String code, Map<String, dynamic> map) => Drop(
        code: code,
        ownerUid: map['ownerUid'] as String? ?? '',
        text: map['text'] as String? ?? '',
        files: [
          for (final f in (map['files'] as List? ?? const []))
            DropFile.fromMap(f as Map<String, dynamic>),
        ],
        createdAt: map['createdAt'] as DateTime? ?? DateTime.now(),
        expiresAt: map['expiresAt'] as DateTime? ?? DateTime.now(),
        burnAfterRead: map['burnAfterRead'] as bool? ?? false,
        burned: map['burned'] as bool? ?? false,
        downloads: (map['downloads'] as num?)?.toInt() ?? 0,
      );
}

/// Per-user usage counters stored at `users/{uid}`.
class UsageStats {
  const UsageStats({
    this.dropsCreated = 0,
    this.bytesUploaded = 0,
    this.dropsReceived = 0,
    this.bytesDownloaded = 0,
    this.lastActiveAt,
  });

  final int dropsCreated;
  final int bytesUploaded;
  final int dropsReceived;
  final int bytesDownloaded;
  final DateTime? lastActiveAt;

  factory UsageStats.fromMap(Map<String, dynamic> map) {
    int n(String key) => (map[key] as num?)?.toInt() ?? 0;
    return UsageStats(
      dropsCreated: n('dropsCreated'),
      bytesUploaded: n('bytesUploaded'),
      dropsReceived: n('dropsReceived'),
      bytesDownloaded: n('bytesDownloaded'),
      lastActiveAt: map['lastActiveAt'] as DateTime?,
    );
  }
}
