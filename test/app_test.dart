import 'dart:convert';

import 'package:burner/app.dart';
import 'package:burner/config/firebase_config.dart';
import 'package:burner/services/auth_service.dart';
import 'package:burner/services/drop_service.dart';
import 'package:burner/services/firestore_client.dart';
import 'package:burner/services/storage_client.dart';
import 'package:burner/ui/auth_screen.dart';
import 'package:burner/ui/public_receive_screen.dart';
import 'package:burner/ui/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = FirebaseConfig(apiKey: 'k', projectId: 'p', storageBucket: 'b');

final client = MockClient((request) async {
  final url = request.url.toString();
  if (url.contains('signInWithPassword')) {
    return http.Response(
        jsonEncode({
          'localId': 'u',
          'email': 'me@example.com',
          'idToken': 't',
          'refreshToken': 'r',
          'expiresIn': '3600',
        }),
        200);
  }
  if (url.contains(':runQuery')) return http.Response('[]', 200);
  return http.Response('{"error":{"status":"NOT_FOUND"}}', 404);
});

Future<AuthService> pumpApp(WidgetTester tester, Size size, {bool signIn = true}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = AuthService(config, client: client);
  final drops = DropService(
    auth: auth,
    firestore: FirestoreClient(config, auth.idToken, client: client),
    storage: StorageClient(config, auth.idToken, client: client),
    publicFirestore: FirestoreClient.anonymous(config, client: client),
    publicStorage: StorageClient.anonymous(config, client: client),
  );
  await tester.runAsync(() async {
    await auth.restore();
    if (signIn) await auth.signIn('me@example.com', 'secret1');
  });
  await tester.pumpWidget(BurnerApp(config: config, auth: auth, drops: drops));
  await tester.pump();
  return auth;
}

void main() {
  testWidgets('signed-out users see the auth screen', (tester) async {
    await pumpApp(tester, const Size(400, 800), signIn: false);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // Sign-up is behind BURNER_SIGNUP_ENABLED, off by default.
    expect(find.text('New here? Create an account'), findsNothing);
  });

  testWidgets('a public link opens without signing in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService(config, client: client);
    final drops = DropService(
      auth: auth,
      firestore: FirestoreClient(config, auth.idToken, client: client),
      storage: StorageClient(config, auth.idToken, client: client),
      publicFirestore: FirestoreClient.anonymous(config, client: client),
      publicStorage: StorageClient.anonymous(config, client: client),
    );
    await tester.pumpWidget(BurnerApp(
      config: config,
      auth: auth,
      drops: drops,
      publicToken: 'a' * 24,
    ));
    expect(find.byType(PublicReceiveScreen), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    // The mock returns 404, so the screen reports a used/expired link.
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('phone width uses a bottom navigation bar', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Pick files to send').evaluate().isNotEmpty ||
        find.text('Drag files here').evaluate().isNotEmpty, isTrue);
  });

  testWidgets('desktop width uses a navigation rail', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('splash shows while the session is restored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService(config, client: client);
    final drops = DropService(
      auth: auth,
      firestore: FirestoreClient(config, auth.idToken, client: client),
      storage: StorageClient(config, auth.idToken, client: client),
      publicFirestore: FirestoreClient.anonymous(config, client: client),
      publicStorage: StorageClient.anonymous(config, client: client),
    );
    await tester.pumpWidget(BurnerApp(config: config, auth: auth, drops: drops));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Burner'), findsOneWidget);
    await tester.runAsync(auth.restore);
    await tester.pump();
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('setup screen explains missing config', (tester) async {
    await tester.pumpWidget(const SetupRequiredApp());
    expect(find.text('Firebase is not configured'), findsOneWidget);
  });
}
