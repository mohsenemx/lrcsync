import 'package:flutter/material.dart';

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
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  Color _seedColor = const Color(0xFF6750A4);

  // Adjustable priority list (default: LRCMux -> LRCLIB -> LRC.red)
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

  ThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  Color get seedColor => _seedColor;

  List<LyricsProvider> get providerPriority =>
      List.unmodifiable(_providerPriority);

  /// Returns enabled providers in the user's exact priority order
  List<LyricsProvider> get activeProvidersInOrder {
    final active = _providerPriority.where(_enabledProviders.contains).toList();
    return active.isNotEmpty ? active : [_providerPriority.first];
  }

  LyricsProvider get primaryProvider => activeProvidersInOrder.first;
  bool get useFallbackProvider => _useFallbackProvider;
  bool get preferLocalLrcFirst => _preferLocalLrcFirst;

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

  void reorderProviders(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _providerPriority.removeAt(oldIndex);
    _providerPriority.insert(newIndex, item);
    notifyListeners();
  }

  void toggleProviderEnabled(LyricsProvider provider, bool enabled) {
    if (!enabled &&
        _enabledProviders.length <= 1 &&
        _enabledProviders.contains(provider)) {
      // Keep at least one provider active
      return;
    }
    if (enabled) {
      _enabledProviders.add(provider);
    } else {
      _enabledProviders.remove(provider);
    }
    notifyListeners();
  }

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

  void setUseFallbackProvider(bool value) {
    _useFallbackProvider = value;
    notifyListeners();
  }

  void setPreferLocalLrcFirst(bool value) {
    _preferLocalLrcFirst = value;
    notifyListeners();
  }
}
