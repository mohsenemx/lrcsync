import 'package:flutter/material.dart';

class AppTheme {
  static const _fallbackSeed = Color(0xFF6750A4);

  static ThemeData buildTheme(
    ColorScheme? dynamicScheme,
    Brightness brightness,
  ) {
    final scheme =
        dynamicScheme ??
        ColorScheme.fromSeed(seedColor: _fallbackSeed, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
