import 'package:flutter/material.dart';

import 'config/firebase_config.dart';
import 'services/auth_service.dart';
import 'services/drop_service.dart';
import 'ui/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/public_receive_screen.dart';
import 'ui/services_scope.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

class BurnerApp extends StatefulWidget {
  const BurnerApp({
    super.key,
    required this.config,
    required this.auth,
    required this.drops,
    this.initialCode,
    this.publicToken,
  });

  final FirebaseConfig config;
  final AuthService auth;
  final DropService drops;
  final String? initialCode;

  /// Token from a public link (`?p=`). Shows the no-sign-in receive screen
  /// instead of the normal app until the visitor leaves it.
  final String? publicToken;

  @override
  State<BurnerApp> createState() => _BurnerAppState();
}

class _BurnerAppState extends State<BurnerApp> {
  late String? _publicToken = widget.publicToken;

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return ServicesScope(
      config: widget.config,
      auth: auth,
      drops: widget.drops,
      child: MaterialApp(
        title: 'Burner',
        debugShowCheckedModeBanner: false,
        theme: BurnerTheme.light(),
        darkTheme: BurnerTheme.dark(),
        home: _publicToken != null
            ? PublicReceiveScreen(
                token: _publicToken!,
                onLeave: () => setState(() => _publicToken = null),
              )
            : ListenableBuilder(
                listenable: auth,
                builder: (context, _) {
                  if (auth.isRestoring) return const SplashScreen();
                  if (!auth.isSignedIn) return const AuthScreen();
                  // Keyed by uid so switching accounts resets all page state.
                  return HomeScreen(
                    key: ValueKey(auth.user!.uid),
                    initialCode: widget.initialCode,
                  );
                },
              ),
      ),
    );
  }
}

/// Shown when the app was built without Firebase settings.
class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burner',
      debugShowCheckedModeBanner: false,
      theme: BurnerTheme.light(),
      darkTheme: BurnerTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_suggest_outlined, size: 48),
                  SizedBox(height: 16),
                  Text('Firebase is not configured',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12),
                  Text(
                    'Copy config/firebase.env.example.json to config/firebase.env.json, '
                    'fill in your project values, and run:\n\n'
                    'flutter run --dart-define-from-file=config/firebase.env.json',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
