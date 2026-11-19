/// Firebase settings injected at build time with
/// `--dart-define-from-file=config/firebase.env.json`.
///
/// Nothing here is secret: a Firebase Web API key only identifies the project.
/// Access control lives in `firestore.rules` and `storage.rules`.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.projectId,
    required this.storageBucket,
    this.webUrl = '',
  });

  static const FirebaseConfig fromEnvironment = FirebaseConfig(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    webUrl: String.fromEnvironment('BURNER_WEB_URL'),
  );

  final String apiKey;
  final String projectId;
  final String storageBucket;

  /// Public URL of the hosted web build, used to build shareable links.
  /// Optional: when empty, the web build falls back to its own origin and
  /// native builds only show the code.
  final String webUrl;

  bool get isConfigured =>
      apiKey.isNotEmpty && projectId.isNotEmpty && storageBucket.isNotEmpty;
}
