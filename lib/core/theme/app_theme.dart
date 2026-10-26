import 'package:flutter/material.dart';

import '../settings/app_settings_controller.dart';

class AppTheme {
  static ThemeData buildTheme({
    required ColorScheme? dynamicScheme,
    required Brightness brightness,
    required AppSettingsController settings,
  }) {
    ColorScheme scheme = (settings.useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(
            seedColor: settings.seedColor,
            brightness: brightness,
          );

    if (brightness == Brightness.dark && settings.amoledDark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamilyFallback: const ['Vazirmatn'],
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
