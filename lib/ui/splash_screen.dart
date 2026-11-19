import 'package:flutter/material.dart';

import 'theme.dart';

/// Branded screen shown while the saved session is restored.
///
/// It matches the native splash (Android launch theme, web `index.html`), so
/// the hand-off to Flutter is seamless. On Linux, where GTK has no native
/// splash, this is the splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BurnerTheme.splashBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BurnerFlame(size: 96),
            SizedBox(height: 16),
            Text(
              'Burner',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 32),
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BurnerTheme.flameBottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's flame mark with the ember gradient used by the launcher icons.
class BurnerFlame extends StatelessWidget {
  const BurnerFlame({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BurnerTheme.seed, BurnerTheme.flameBottom],
      ).createShader(bounds),
      child: Icon(Icons.local_fire_department, size: size),
    );
  }
}
