import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppFont {
  system(label: 'System Default', fontFamily: null),
  ubuntu(label: 'Ubuntu', fontFamily: 'Ubuntu'),
  vazirmatn(label: 'Vazirmatn', fontFamily: 'Vazirmatn'),
  jetBrainsMono(label: 'JetBrains Mono', fontFamily: 'JetBrainsMono'),
  poppins(label: 'Poppins', fontFamily: 'Poppins'),
  inter(label: 'Inter', fontFamily: 'Inter');

  final String label;
  final String? fontFamily;

  const AppFont({required this.label, required this.fontFamily});
}

enum LyricsProvider {
  lrcmux(
    name: 'LRCMux',
    baseUrl: 'https://api.lrcmux.dev',
    description: 'Multi-source aggregator (Musixmatch, KuGou, YT Music, LRCLIB) with Word & Line sync.',
  ),
  lrclib(
    name: 'LRCLIB',
    baseUrl: 'https://lrclib.net',
    description: 'Open-source crowdsourced synced & plain lyrics database.',
  ),
  lrcRed(
    name: 'LRC.red',
    baseUrl: 'https://lrc.red',
    description:
        'Free community provider for ISRC-matched time-synced LRC files.',
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
  static const _methodChannel = MethodChannel('lrcsync/media_methods');
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  Color _seedColor = const Color(0xFF6750A4);

  // Font & Lyrics Typography
  AppFont _appFont = AppFont.system;
  double _lyricsFontSize = 24.0;

  // Providers & LRC Behavior
  final List<LyricsProvider> _providerPriority = [
    LyricsProvider.lrcmux,
    LyricsProvider.lrclib,
    LyricsProvider.lrcRed,
  ];
  final Set<LyricsProvider> _enabledProviders = {
    LyricsProvider.lrcmux,
    LyricsProvider.lrclib,
    LyricsProvider.lrcRed,
  };

  bool _useFallbackProvider = true;
  bool _preferLocalLrcFirst = true;
  bool _preferStandardLrcOverElrc = false;

  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  Color get seedColor => _seedColor;

  AppFont get appFont => _appFont;
  double get lyricsFontSize => _lyricsFontSize;

  List<LyricsProvider> get providerPriority =>
      List.unmodifiable(_providerPriority);

  List<LyricsProvider> get activeProvidersInOrder {
    final active = _providerPriority.where(_enabledProviders.contains).toList();
    return active.isNotEmpty ? active : [_providerPriority.first];
  }

  LyricsProvider get primaryProvider => activeProvidersInOrder.first;
  bool get useFallbackProvider => _useFallbackProvider;
  bool get preferLocalLrcFirst => _preferLocalLrcFirst;
  bool get preferStandardLrcOverElrc => _preferStandardLrcOverElrc;

  bool isProviderEnabled(LyricsProvider provider) =>
      _enabledProviders.contains(provider);

  static const List<Color> availableSeedColors = [
    Color(0xFF6750A4), // Deep Purple
    Color(0xFF0061A4), // Ocean Blue
    Color(0xFF006D3B), // Emerald Green
    Color(0xFFB3261E), // Crimson Red
    Color(0xFF8E4585), // Plum
    Color(0xFFE65100), // Amber Orange
  ];

  /// Loads persisted settings from Android SharedPreferences
  Future<void> loadSettings() async {
    try {
      final rawJson = await _methodChannel.invokeMethod<String>('loadSettings');
      if (rawJson == null || rawJson.isEmpty) return;

      final map = jsonDecode(rawJson) as Map<String, dynamic>;

      final themeName = map['themeMode'] as String?;
      if (themeName != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.name == themeName,
          orElse: () => ThemeMode.system,
        );
      }

      _useDynamicColor = (map['useDynamicColor'] as bool?) ?? _useDynamicColor;
      _amoledDark = (map['amoledDark'] as bool?) ?? _amoledDark;

      final seedInt = map['seedColor'] as int?;
      if (seedInt != null) {
        _seedColor = Color(seedInt);
      }

      final fontName = map['appFont'] as String?;
      if (fontName != null) {
        _appFont = AppFont.values.firstWhere(
          (e) => e.name == fontName,
          orElse: () => AppFont.system,
        );
      }

      final fontSize = (map['lyricsFontSize'] as num?)?.toDouble();
      if (fontSize != null) {
        _lyricsFontSize = fontSize.clamp(16.0, 36.0);
      }

      final priorityList = (map['providerPriority'] as List<dynamic>?)
          ?.whereType<String>()
          .toList();
      if (priorityList != null && priorityList.isNotEmpty) {
        final restored = <LyricsProvider>[];
        for (final name in priorityList) {
          final match = LyricsProvider.values
              .where((p) => p.name == name)
              .firstOrNull;
          if (match != null && !restored.contains(match)) {
            restored.add(match);
          }
        }
        for (final p in LyricsProvider.values) {
          if (!restored.contains(p)) restored.add(p);
        }
        _providerPriority
          ..clear()
          ..addAll(restored);
      }

      final enabledList = (map['enabledProviders'] as List<dynamic>?)
          ?.whereType<String>()
          .toList();
      if (enabledList != null && enabledList.isNotEmpty) {
        final restoredEnabled = <LyricsProvider>{};
        for (final name in enabledList) {
          final match = LyricsProvider.values
              .where((p) => p.name == name)
              .firstOrNull;
          if (match != null) restoredEnabled.add(match);
        }
        if (restoredEnabled.isNotEmpty) {
          _enabledProviders
            ..clear()
            ..addAll(restoredEnabled);
        }
      }

      _useFallbackProvider =
          (map['useFallbackProvider'] as bool?) ?? _useFallbackProvider;
      _preferLocalLrcFirst =
          (map['preferLocalLrcFirst'] as bool?) ?? _preferLocalLrcFirst;
      _preferStandardLrcOverElrc =
          (map['preferStandardLrcOverElrc'] as bool?) ??
          _preferStandardLrcOverElrc;

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final data = {
        'themeMode': _themeMode.name,
        'useDynamicColor': _useDynamicColor,
        'amoledDark': _amoledDark,
        'seedColor': _seedColor.toARGB32(),
        'appFont': _appFont.name,
        'lyricsFontSize': _lyricsFontSize,
        'providerPriority': _providerPriority.map((e) => e.name).toList(),
        'enabledProviders': _enabledProviders.map((e) => e.name).toList(),
        'useFallbackProvider': _useFallbackProvider,
        'preferLocalLrcFirst': _preferLocalLrcFirst,
        'preferStandardLrcOverElrc': _preferStandardLrcOverElrc,
      };
      await _methodChannel.invokeMethod('saveSettings', {
        'json': jsonEncode(data),
      });
    } catch (_) {}
  }

  void setAppFont(AppFont font) {
    _appFont = font;
    notifyListeners();
    _saveSettings();
  }

  void setLyricsFontSize(double size) {
    _lyricsFontSize = size.clamp(16.0, 36.0);
    notifyListeners();
    _saveSettings();
  }

  void setPreferStandardLrcOverElrc(bool value) {
    _preferStandardLrcOverElrc = value;
    notifyListeners();
    _saveSettings();
  }

  void reorderProviders(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _providerPriority.removeAt(oldIndex);
    _providerPriority.insert(newIndex, item);
    notifyListeners();
    _saveSettings();
  }

  void toggleProviderEnabled(LyricsProvider provider, bool enabled) {
    if (!enabled &&
        _enabledProviders.length <= 1 &&
        _enabledProviders.contains(provider)) {
      return;
    }
    if (enabled) {
      _enabledProviders.add(provider);
    } else {
      _enabledProviders.remove(provider);
    }
    notifyListeners();
    _saveSettings();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _saveSettings();
  }

  void setUseDynamicColor(bool value) {
    _useDynamicColor = value;
    notifyListeners();
    _saveSettings();
  }

  void setAmoledDark(bool value) {
    _amoledDark = value;
    notifyListeners();
    _saveSettings();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setUseFallbackProvider(bool value) {
    _useFallbackProvider = value;
    notifyListeners();
    _saveSettings();
  }

  void setPreferLocalLrcFirst(bool value) {
    _preferLocalLrcFirst = value;
    notifyListeners();
    _saveSettings();
  }
}
