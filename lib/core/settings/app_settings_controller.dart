import 'package:flutter/material.dart';

enum LyricsProvider {
  lrclib(
    name: 'LRCLIB',
    baseUrl: 'https://lrclib.net',
    description: 'Open-source crowdsourced synced & plain lyrics database.',
  ),
  lrcRed(
    name: 'LRC.red',
    baseUrl: 'https://lrc.red',
    description: 'Free community provider for time-synced LRC files.',
  );

  final String name;
  final String baseUrl;
  final String description;

  const LyricsProvider({
    required this.name,
    required this.baseUrl,
    required this.description,
  });
}

class AppSettingsController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  Color _seedColor = const Color(0xFF6750A4);

  LyricsProvider _primaryProvider = LyricsProvider.lrclib;
  bool _useFallbackProvider = true;
  bool _preferLocalLrcFirst = true;

  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  Color get seedColor => _seedColor;

  LyricsProvider get primaryProvider => _primaryProvider;
  bool get useFallbackProvider => _useFallbackProvider;
  bool get preferLocalLrcFirst => _preferLocalLrcFirst;

  static const List<Color> availableSeedColors = [
    Color(0xFF6750A4), // Deep Purple
    Color(0xFF0061A4), // Ocean Blue
    Color(0xFF006D3B), // Emerald Green
    Color(0xFFB3261E), // Crimson Red
    Color(0xFF8E4585), // Plum
    Color(0xFFE65100), // Amber Orange
  ];

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setUseDynamicColor(bool value) {
    _useDynamicColor = value;
    notifyListeners();
  }

  void setAmoledDark(bool value) {
    _amoledDark = value;
    notifyListeners();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
  }

  void setPrimaryProvider(LyricsProvider provider) {
    _primaryProvider = provider;
    notifyListeners();
  }

  void setUseFallbackProvider(bool value) {
    _useFallbackProvider = value;
    notifyListeners();
  }

  void setPreferLocalLrcFirst(bool value) {
    _preferLocalLrcFirst = value;
    notifyListeners();
  }
}
