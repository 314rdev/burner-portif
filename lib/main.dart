import 'package:flutter/material.dart';

import 'app.dart';
import 'config/firebase_config.dart';
import 'services/auth_service.dart';
import 'services/drop_service.dart';
import 'services/firestore_client.dart';
import 'services/storage_client.dart';
import 'util/codes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = FirebaseConfig.fromEnvironment;
  if (!config.isConfigured) {
    runApp(const SetupRequiredApp());
    return;
  }

  final auth = AuthService(config);
  final drops = DropService(
    auth: auth,
    firestore: FirestoreClient(config, auth.idToken),
    storage: StorageClient(config, auth.idToken),
    publicFirestore: FirestoreClient.anonymous(config),
    publicStorage: StorageClient.anonymous(config),
  );

  // Web links look like https://host/?code=ABC234. On native builds
  // Uri.base is a file URI without a query, so this is null.
  final initialCode = DropCodes.parse(Uri.base.queryParameters['code'] ?? '');
  // Public links look like https://host/?p=<24-char token>; no sign-in.
  final publicToken =
      DropCodes.parsePublicToken(Uri.base.queryParameters['p'] ?? '');

  runApp(BurnerApp(
    config: config,
    auth: auth,
    drops: drops,
    initialCode: initialCode,
    publicToken: publicToken,
  ));
  await auth.restore();
}
