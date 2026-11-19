import 'package:flutter/material.dart';

/// Burner's look: warm "ember" seed colour, Material 3, light + dark.
class BurnerTheme {
  const BurnerTheme._();

  static const seed = Color(0xFFE8590C);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Monospace style for drop codes.
  static TextStyle codeStyle(BuildContext context, {double size = 40}) =>
      TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Ubuntu Mono', 'DejaVu Sans Mono', 'Courier'],
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.12,
        color: Theme.of(context).colorScheme.primary,
      );
}

/// Breakpoints shared by all screens.
class Breakpoints {
  const Breakpoints._();

  /// At or above this width the app uses a side navigation rail.
  static const wide = 840.0;

  /// Content never grows wider than this.
  static const maxContent = 760.0;
}

/// Shows a floating message.
void showMessage(BuildContext context, String text, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? scheme.error : null,
    ));
}

/// Centers [child] and caps its width, with padding that suits phones.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? Breakpoints.maxContent),
        child: child,
      ),
    );
  }
}
