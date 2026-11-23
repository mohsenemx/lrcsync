import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppFont {
  system(label: 'System Default', fontFamily: null),
  ubuntu(label: 'Ubuntu', fontFamily: 'Ubuntu'),
  vazirmatn(label: 'Vazirmatn', fontFamily: 'Vazirmatn'),
  jetBrainsMono(label: 'JetBrains Mono', fontFamily: 'JetBrainsMono');

  final String label;
  final String? fontFamily;

  const AppFont({required this.label, required this.fontFamily});
}

enum OverlayShape {
  rounded(label: 'Rounded', borderRadius: 24.0),
  pill(label: 'Pill', borderRadius: 36.0),
  softSquare(label: 'Soft', borderRadius: 12.0),
  sharp(label: 'Sharp', borderRadius: 4.0);

  final String label;
  final double borderRadius;

  const OverlayShape({required this.label, required this.borderRadius});
}

enum OverlayBackgroundStyle {
  themeSurface(label: 'Theme'),
  amoledBlack(label: 'Pure Black'),
  frostedDark(label: 'Dark Glass'),
  frostedLight(label: 'Light Glass'),
  transparent(label: 'Transparent'),
  customColor(label: 'Custom');

  final String label;

  const OverlayBackgroundStyle({required this.label});
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

  AppFont _appFont = AppFont.system;
  double _lyricsFontSize = 24.0;
  bool _blurInactiveLyrics = true;

  // Floating Overlay Customization
  OverlayShape _overlayShape = OverlayShape.rounded;
  OverlayBackgroundStyle _overlayBackgroundStyle =
      OverlayBackgroundStyle.themeSurface;
  Color _overlayCustomColor = const Color(0xFF1A1B26);
  double _overlayOpacity = 0.92;
  bool _overlayShowBorder = true;
  bool _overlayFullWidth = true;
  double _overlayWidthDp = 320.0;
  double _overlayHeightDp = 240.0;
  int _overlaySizeRevision = 0;

  // Updates
  String? _skippedUpdateVersion;

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
  bool get blurInactiveLyrics => _blurInactiveLyrics;

  OverlayShape get overlayShape => _overlayShape;
  OverlayBackgroundStyle get overlayBackgroundStyle => _overlayBackgroundStyle;
  Color get overlayCustomColor => _overlayCustomColor;
  double get overlayOpacity => _overlayOpacity;
  bool get overlayShowBorder => _overlayShowBorder;
  bool get overlayFullWidth => _overlayFullWidth;
  double get overlayWidthDp => _overlayWidthDp;
  double get overlayHeightDp => _overlayHeightDp;
  int get overlaySizeRevision => _overlaySizeRevision;

  String? get skippedUpdateVersion => _skippedUpdateVersion;

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

  static const List<Color> availableOverlayColors = [
    Color(0xFF1A1B26), // Midnight Navy
    Color(0xFF1E1A2E), // Deep Violet
    Color(0xFF102A24), // Deep Emerald
    Color(0xFF2B161B), // Burgundy Dark
    Color(0xFF1F2428), // Slate Charcoal
    Color(0xFFF5F3FF), // Soft Lavender Light
  ];

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
      if (seedInt != null) _seedColor = Color(seedInt);

      final fontName = map['appFont'] as String?;
      if (fontName != null) {
        _appFont = AppFont.values.firstWhere(
          (e) => e.name == fontName,
          orElse: () => AppFont.system,
        );
      }

      final fontSize = (map['lyricsFontSize'] as num?)?.toDouble();
      if (fontSize != null) _lyricsFontSize = fontSize.clamp(16.0, 36.0);

      _blurInactiveLyrics =
          (map['blurInactiveLyrics'] as bool?) ?? _blurInactiveLyrics;

      // Floating Overlay settings
      final shapeName = map['overlayShape'] as String?;
      if (shapeName != null) {
        _overlayShape = OverlayShape.values.firstWhere(
          (e) => e.name == shapeName,
          orElse: () => OverlayShape.rounded,
        );
      }

      final bgStyleName = map['overlayBackgroundStyle'] as String?;
      if (bgStyleName != null) {
        _overlayBackgroundStyle = OverlayBackgroundStyle.values.firstWhere(
          (e) => e.name == bgStyleName,
          orElse: () => OverlayBackgroundStyle.themeSurface,
        );
      }

      final overlayColorInt = map['overlayCustomColor'] as int?;
      if (overlayColorInt != null) _overlayCustomColor = Color(overlayColorInt);

      final opacity = (map['overlayOpacity'] as num?)?.toDouble();
      if (opacity != null) _overlayOpacity = opacity.clamp(0.15, 1.0);

      _overlayShowBorder =
          (map['overlayShowBorder'] as bool?) ?? _overlayShowBorder;
      _overlayFullWidth =
          (map['overlayFullWidth'] as bool?) ?? _overlayFullWidth;

      final widthDp = (map['overlayWidthDp'] as num?)?.toDouble();
      if (widthDp != null) _overlayWidthDp = widthDp.clamp(220.0, 420.0);

      final heightDp = (map['overlayHeightDp'] as num?)?.toDouble();
      if (heightDp != null) _overlayHeightDp = heightDp.clamp(120.0, 400.0);

      _skippedUpdateVersion = map['skippedUpdateVersion'] as String?;

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
        'blurInactiveLyrics': _blurInactiveLyrics,
        'overlayShape': _overlayShape.name,
        'overlayBackgroundStyle': _overlayBackgroundStyle.name,
        'overlayCustomColor': _overlayCustomColor.toARGB32(),
        'overlayOpacity': _overlayOpacity,
        'overlayShowBorder': _overlayShowBorder,
        'overlayFullWidth': _overlayFullWidth,
        'overlayWidthDp': _overlayWidthDp,
        'overlayHeightDp': _overlayHeightDp,
        'skippedUpdateVersion': _skippedUpdateVersion,
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

  void setBlurInactiveLyrics(bool value) {
    _blurInactiveLyrics = value;
    notifyListeners();
    _saveSettings();
  }

  // --- Floating Overlay Setters ---

  void setOverlayShape(OverlayShape shape) {
    _overlayShape = shape;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayBackgroundStyle(OverlayBackgroundStyle style) {
    _overlayBackgroundStyle = style;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayCustomColor(Color color) {
    _overlayCustomColor = color;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayOpacity(double value) {
    _overlayOpacity = value.clamp(0.15, 1.0);
    notifyListeners();
    _saveSettings();
  }

  void setOverlayShowBorder(bool value) {
    _overlayShowBorder = value;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayFullWidth(bool value) {
    _overlayFullWidth = value;
    _overlaySizeRevision++;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayWidthDp(double value) {
    _overlayWidthDp = value.clamp(220.0, 420.0);
    _overlaySizeRevision++;
    notifyListeners();
    _saveSettings();
  }

  void setOverlayHeightDp(double value) {
    _overlayHeightDp = value.clamp(120.0, 400.0);
    _overlaySizeRevision++;
    notifyListeners();
    _saveSettings();
  }

  /// Called when the user resizes the overlay directly on screen so the
  /// settings persist without bouncing a duplicate resize command back.
  void persistOverlaySizeFromWindow({
    required bool fullWidth,
    required double widthDp,
    required double heightDp,
  }) {
    _overlayFullWidth = fullWidth;
    _overlayWidthDp = widthDp.clamp(220.0, 420.0);
    _overlayHeightDp = heightDp.clamp(120.0, 400.0);
    notifyListeners();
    _saveSettings();
  }

  void resetOverlayDefaults() {
    _overlayShape = OverlayShape.rounded;
    _overlayBackgroundStyle = OverlayBackgroundStyle.themeSurface;
    _overlayCustomColor = const Color(0xFF1A1B26);
    _overlayOpacity = 0.92;
    _overlayShowBorder = true;
    _overlayFullWidth = true;
    _overlayWidthDp = 320.0;
    _overlayHeightDp = 240.0;
    _overlaySizeRevision++;
    notifyListeners();
    _saveSettings();
  }

  // --- Update Preference ---

  void setSkippedUpdateVersion(String? version) {
    _skippedUpdateVersion = version;
    notifyListeners();
    _saveSettings();
  }

  // --- Provider & Theme Setters ---

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
