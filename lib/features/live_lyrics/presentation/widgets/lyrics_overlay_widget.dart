import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../../core/utils/rtl_helper.dart';
import '../../../now_playing/data/models/parsed_lyrics.dart';
import '../../data/services/lyrics_overlay_bridge.dart';

class LyricsOverlayApp extends StatefulWidget {
  const LyricsOverlayApp({super.key});

  @override
  State<LyricsOverlayApp> createState() => _LyricsOverlayAppState();
}

class _LyricsOverlayAppState extends State<LyricsOverlayApp>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  StreamSubscription<dynamic>? _sub;
  ReceivePort? _stateReceivePort;
  StreamSubscription<dynamic>? _statePortSub;

  // Synced Theme & Lyrics Settings
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  Color _seedColor = const Color(0xFF6750A4);
  AppFont _appFont = AppFont.system;
  double _lyricsFontSize = 24.0;
  bool _blurInactiveLyrics = true;

  // Synced Overlay Customization
  OverlayShape _overlayShape = OverlayShape.rounded;
  OverlayBackgroundStyle _overlayBackgroundStyle =
      OverlayBackgroundStyle.themeSurface;
  Color _overlayCustomColor = const Color(0xFF1A1B26);
  double _overlayOpacity = 0.92;
  bool _overlayShowBorder = true;
  bool _overlayFullWidth = true;
  double _overlayWidthDp = 320.0;
  double _overlayHeightDp = 240.0;
  int _lastSizeRevision = -1;

  // Resize Mode State
  bool _isResizeMode = false;
  DateTime _lastResizeCall = DateTime.fromMillisecondsSinceEpoch(0);

  // Synced Track & Lyrics State
  bool _isFetching = false;
  String? _title;
  String? _artist;
  int _durationMs = 0;
  int _positionMs = 0;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  int _timestampEpochMs = 0;

  String? _lastRawLrc;
  ParsedLyrics? _parsedLyrics;

  Duration _livePosition = Duration.zero;
  int _activeLineIndex = -1;
  int _slideDirection = 1;

  // Auto-close liveness check when current song ends
  DateTime? _lastMainReplyAt;
  DateTime? _endPingSentAt;
  bool _isAutoClosing = false;

  void _sendCommandToMain(String action, [Map<String, dynamic>? extra]) {
    final payload = jsonEncode({
      'type': 'cmd',
      'action': action,
      'reqId': DateTime.now().microsecondsSinceEpoch,
      ...?extra,
    });
    final sendPort = ui.IsolateNameServer.lookupPortByName(
      kLrcSyncOverlayCmdPort,
    );
    sendPort?.send(payload);
    FlutterOverlayWindow.shareData(payload);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayStatePort);
    _stateReceivePort = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _stateReceivePort!.sendPort,
      kLrcSyncOverlayStatePort,
    );
    _statePortSub = _stateReceivePort!.listen(_onMessageReceived);
    _sub = FlutterOverlayWindow.overlayListener.listen(_onMessageReceived);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendCommandToMain('ready');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _title == null) {
          _sendCommandToMain('ready');
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _statePortSub?.cancel();
    _stateReceivePort?.close();
    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayStatePort);
    super.dispose();
  }

  Future<void> _applyWindowResize({required bool enableDrag}) async {
    final targetW = _overlayFullWidth
        ? WindowSize.matchParent
        : _overlayWidthDp.round();
    final targetH = _overlayHeightDp.round();
    try {
      await FlutterOverlayWindow.resizeOverlay(targetW, targetH, enableDrag);
    } catch (_) {}
  }

  Future<void> _toggleResizeMode() async {
    final entering = !_isResizeMode;
    setState(() => _isResizeMode = entering);

    // Disable native window dragging while resizing so corner drags don't move the window
    await _applyWindowResize(enableDrag: !entering);

    if (!entering) {
      _sendCommandToMain('save_overlay_size', {
        'fullWidth': _overlayFullWidth,
        'widthDp': _overlayWidthDp,
        'heightDp': _overlayHeightDp,
      });
    }
  }

  void _handleCornerDrag(DragUpdateDetails details, double currentWidthDp) {
    final nextWidth =
        ((_overlayFullWidth ? currentWidthDp : _overlayWidthDp) +
                details.delta.dx)
            .clamp(220.0, 420.0);
    final nextHeight = (_overlayHeightDp + details.delta.dy).clamp(
      120.0,
      400.0,
    );

    setState(() {
      if (details.delta.dx.abs() > 1.2) {
        _overlayFullWidth = false;
      }
      _overlayWidthDp = nextWidth;
      _overlayHeightDp = nextHeight;
    });

    final now = DateTime.now();
    if (now.difference(_lastResizeCall).inMilliseconds >= 50) {
      _lastResizeCall = now;
      _applyWindowResize(enableDrag: false);
    }
  }

  void _nudgeHeight(double deltaDp) {
    setState(() {
      _overlayHeightDp = (_overlayHeightDp + deltaDp).clamp(120.0, 400.0);
    });
    _applyWindowResize(enableDrag: !_isResizeMode);
  }

  void _toggleFullWidthInOverlay() {
    setState(() => _overlayFullWidth = !_overlayFullWidth);
    _applyWindowResize(enableDrag: !_isResizeMode);
  }

  void _onMessageReceived(dynamic event) {
    if (event is! String || !mounted) return;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['type'] == 'pong') {
        _lastMainReplyAt = DateTime.now();
        return;
      }

      if (decoded['type'] != 'state') return;

      _lastMainReplyAt = DateTime.now();
      _endPingSentAt = null;

      final settingsMap = decoded['settings'] as Map<String, dynamic>?;
      final trackMap = decoded['track'] as Map<String, dynamic>?;
      final rawLrc = decoded['rawLrc'] as String?;

      bool shouldResizeFromSettings = false;

      setState(() {
        _isFetching = (decoded['isFetching'] as bool?) ?? false;

        if (settingsMap != null) {
          final themeName = settingsMap['themeMode'] as String?;
          if (themeName != null) {
            _themeMode = ThemeMode.values.firstWhere(
              (e) => e.name == themeName,
              orElse: () => ThemeMode.system,
            );
          }
          _useDynamicColor =
              (settingsMap['useDynamicColor'] as bool?) ?? _useDynamicColor;
          _amoledDark = (settingsMap['amoledDark'] as bool?) ?? _amoledDark;

          final seedInt = settingsMap['seedColor'] as int?;
          if (seedInt != null) _seedColor = Color(seedInt);

          final fontName = settingsMap['appFont'] as String?;
          if (fontName != null) {
            _appFont = AppFont.values.firstWhere(
              (e) => e.name == fontName,
              orElse: () => AppFont.system,
            );
          }
          _lyricsFontSize =
              (settingsMap['lyricsFontSize'] as num?)?.toDouble() ??
              _lyricsFontSize;
          _blurInactiveLyrics =
              (settingsMap['blurInactiveLyrics'] as bool?) ??
              _blurInactiveLyrics;

          final shapeName = settingsMap['overlayShape'] as String?;
          if (shapeName != null) {
            _overlayShape = OverlayShape.values.firstWhere(
              (e) => e.name == shapeName,
              orElse: () => OverlayShape.rounded,
            );
          }

          final bgStyleName = settingsMap['overlayBackgroundStyle'] as String?;
          if (bgStyleName != null) {
            _overlayBackgroundStyle = OverlayBackgroundStyle.values.firstWhere(
              (e) => e.name == bgStyleName,
              orElse: () => OverlayBackgroundStyle.themeSurface,
            );
          }

          final customColorInt = settingsMap['overlayCustomColor'] as int?;
          if (customColorInt != null) {
            _overlayCustomColor = Color(customColorInt);
          }

          final opacity = (settingsMap['overlayOpacity'] as num?)?.toDouble();
          if (opacity != null) _overlayOpacity = opacity.clamp(0.15, 1.0);

          _overlayShowBorder =
              (settingsMap['overlayShowBorder'] as bool?) ?? _overlayShowBorder;

          final sizeRevision =
              (settingsMap['overlaySizeRevision'] as num?)?.toInt() ?? 0;
          if (!_isResizeMode) {
            _overlayFullWidth =
                (settingsMap['overlayFullWidth'] as bool?) ?? _overlayFullWidth;
            _overlayWidthDp =
                (settingsMap['overlayWidthDp'] as num?)?.toDouble() ??
                _overlayWidthDp;
            _overlayHeightDp =
                (settingsMap['overlayHeightDp'] as num?)?.toDouble() ??
                _overlayHeightDp;

            if (_lastSizeRevision != -1 && sizeRevision != _lastSizeRevision) {
              shouldResizeFromSettings = true;
            }
            _lastSizeRevision = sizeRevision;
          }
        }

        if (trackMap != null) {
          _title = trackMap['title'] as String?;
          _artist = trackMap['artist'] as String?;
          _durationMs = (trackMap['durationMs'] as num?)?.toInt() ?? 0;
          _positionMs = (trackMap['positionMs'] as num?)?.toInt() ?? 0;
          _isPlaying = (trackMap['isPlaying'] as bool?) ?? false;
          _playbackSpeed =
              (trackMap['playbackSpeed'] as num?)?.toDouble() ?? 1.0;
          _timestampEpochMs =
              (trackMap['timestampEpochMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
        } else {
          _title = null;
          _artist = null;
          _isPlaying = false;
        }

        if (rawLrc != _lastRawLrc) {
          _lastRawLrc = rawLrc;
          _parsedLyrics = (rawLrc != null && rawLrc.trim().isNotEmpty)
              ? ParsedLyrics.parse(rawLrc)
              : null;
          _activeLineIndex = -1;
          _slideDirection = 1;
        }

        final updatedPos = _estimateLivePosition();
        _livePosition = updatedPos;
        final parsed = _parsedLyrics;
        if (parsed != null && parsed.syncType != LyricsSyncType.plain) {
          int idx = -1;
          for (var i = 0; i < parsed.lines.length; i++) {
            if (updatedPos >= parsed.lines[i].startTime) {
              idx = i;
            } else {
              break;
            }
          }
          if (idx != _activeLineIndex && _activeLineIndex != -1) {
            _slideDirection = idx > _activeLineIndex ? 1 : -1;
          }
          _activeLineIndex = idx;
        }
      });

      if (shouldResizeFromSettings) {
        _applyWindowResize(enableDrag: !_isResizeMode);
      }
    } catch (_) {}
  }

  Duration _estimateLivePosition() {
    final maxMs = _durationMs > 0 ? _durationMs : 86400000;
    if (!_isPlaying || _timestampEpochMs <= 0) {
      return Duration(milliseconds: _positionMs.clamp(0, maxMs));
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - _timestampEpochMs;
    final extrapolated = _positionMs + (elapsed * _playbackSpeed).round();
    return Duration(milliseconds: extrapolated.clamp(0, maxMs));
  }

  void _onTick(Duration _) {
    if (!mounted || _title == null) return;

    if (_isPlaying &&
        _durationMs > 0 &&
        _timestampEpochMs > 0 &&
        !_isAutoClosing) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _timestampEpochMs;
      final unclampedMs = _positionMs + (elapsed * _playbackSpeed).round();

      if (unclampedMs >= _durationMs) {
        if (_endPingSentAt == null) {
          _endPingSentAt = DateTime.now();
          _sendCommandToMain('ping');
        } else if (DateTime.now().difference(_endPingSentAt!).inMilliseconds >=
            1500) {
          final mainReplied =
              _lastMainReplyAt != null &&
              _lastMainReplyAt!.isAfter(_endPingSentAt!);
          if (!mainReplied) {
            _isAutoClosing = true;
            FlutterOverlayWindow.closeOverlay();
            return;
          }
        }
      } else {
        _endPingSentAt = null;
      }
    }

    final newPos = _estimateLivePosition();
    int newActiveIndex = -1;
    final parsed = _parsedLyrics;

    if (parsed != null && parsed.syncType != LyricsSyncType.plain) {
      for (var i = 0; i < parsed.lines.length; i++) {
        if (newPos >= parsed.lines[i].startTime) {
          newActiveIndex = i;
        } else {
          break;
        }
      }
    }

    setState(() {
      if (newActiveIndex != _activeLineIndex && _activeLineIndex != -1) {
        _slideDirection = newActiveIndex > _activeLineIndex ? 1 : -1;
      }
      _livePosition = newPos;
      _activeLineIndex = newActiveIndex;
    });
  }

  void _handlePlayPauseTap() {
    _sendCommandToMain('toggle_play_pause');
  }

  ThemeData _buildOverlayTheme(
    ColorScheme? dynamicScheme,
    Brightness brightness,
  ) {
    ColorScheme scheme = (_useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(seedColor: _seedColor, brightness: brightness);

    if (brightness == Brightness.dark && _amoledDark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerHigh: const Color(0xFF0A0A0A),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _appFont.fontFamily,
      fontFamilyFallback: const ['Vazirmatn'],
    );
  }

  Color _resolveCardBackground(ColorScheme scheme, bool isDark) {
    switch (_overlayBackgroundStyle) {
      case OverlayBackgroundStyle.themeSurface:
        final base = (isDark && _amoledDark)
            ? Colors.black
            : scheme.surfaceContainerHigh;
        return base.withValues(alpha: _overlayOpacity);
      case OverlayBackgroundStyle.amoledBlack:
        return Colors.black.withValues(alpha: _overlayOpacity);
      case OverlayBackgroundStyle.frostedDark:
        return const Color(0xFF14151A).withValues(alpha: _overlayOpacity);
      case OverlayBackgroundStyle.frostedLight:
        return const Color(0xFFF6F7FB).withValues(alpha: _overlayOpacity);
      case OverlayBackgroundStyle.transparent:
        return Colors.transparent;
      case OverlayBackgroundStyle.customColor:
        return _overlayCustomColor.withValues(alpha: _overlayOpacity);
    }
  }

  Color _resolveSecondaryTextColor(ColorScheme scheme, bool isDark) {
    switch (_overlayBackgroundStyle) {
      case OverlayBackgroundStyle.amoledBlack:
      case OverlayBackgroundStyle.frostedDark:
        return Colors.white;
      case OverlayBackgroundStyle.frostedLight:
        return const Color(0xFF1A1C1E);
      case OverlayBackgroundStyle.customColor:
        return ThemeData.estimateBrightnessForColor(_overlayCustomColor) ==
                Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1C1E);
      case OverlayBackgroundStyle.transparent:
        return Colors.white;
      case OverlayBackgroundStyle.themeSurface:
        return scheme.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: _buildOverlayTheme(lightDynamic, Brightness.light),
          darkTheme: _buildOverlayTheme(darkDynamic, Brightness.dark),
          home: Builder(builder: (context) => _buildOverlayCard(context)),
        );
      },
    );
  }

  Widget _buildOverlayCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTransparent =
        _overlayBackgroundStyle == OverlayBackgroundStyle.transparent;

    final cardBg = _resolveCardBackground(scheme, isDark);
    final fgBase = _resolveSecondaryTextColor(scheme, isDark);
    final radius = _overlayShape.borderRadius;

    final double progress = _durationMs > 0
        ? (_livePosition.inMilliseconds / _durationMs).clamp(0.0, 1.0)
        : 0.0;

    final double scaledFontSize = (_lyricsFontSize * 0.78).clamp(13.0, 26.0);

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showThreeLines = constraints.maxHeight >= 150;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                decoration: BoxDecoration(
                  color: _isResizeMode && isTransparent
                      ? Colors.black.withValues(alpha: 0.45)
                      : cardBg,
                  borderRadius: BorderRadius.circular(radius),
                  border: _isResizeMode
                      ? Border.all(color: scheme.primary, width: 2.0)
                      : (_overlayShowBorder && !isTransparent
                            ? Border.all(color: fgBase.withValues(alpha: 0.16))
                            : null),
                  boxShadow: isTransparent
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.28 * _overlayOpacity,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Top Mini Controls Bar
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 5, 6, 2),
                          decoration: isTransparent
                              ? BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.32),
                                )
                              : null,
                          child: Row(
                            children: [
                              Icon(
                                _isResizeMode
                                    ? Icons.aspect_ratio_rounded
                                    : Icons.drag_indicator_rounded,
                                size: 15,
                                color: _isResizeMode
                                    ? scheme.primary
                                    : fgBase.withValues(alpha: 0.65),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isResizeMode
                                      ? 'Drag corner to resize'
                                      : (_title != null
                                            ? '$_title • ${_artist ?? ''}'
                                            : 'LRCSync Overlay'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: fgBase.withValues(alpha: 0.78),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                icon: Icon(
                                  _isResizeMode
                                      ? Icons.check_rounded
                                      : Icons.open_in_full_rounded,
                                  size: 17,
                                  color: _isResizeMode
                                      ? scheme.primary
                                      : fgBase.withValues(alpha: 0.78),
                                ),
                                onPressed: _toggleResizeMode,
                              ),
                              if (!_isResizeMode)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  onPressed: _handlePlayPauseTap,
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: fgBase.withValues(alpha: 0.78),
                                ),
                                onPressed: () {
                                  _sendCommandToMain('close');
                                  FlutterOverlayWindow.closeOverlay();
                                },
                              ),
                            ],
                          ),
                        ),

                        // Animated Lyrics Area
                        Expanded(
                          child: ClipRect(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Center(
                                child: _buildLyricsContent(
                                  context,
                                  scheme,
                                  textTheme,
                                  fgBase,
                                  isTransparent,
                                  scaledFontSize,
                                  progress,
                                  showThreeLines,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Quick Resize Controls Bar (shown only in Resize Mode)
                        if (_isResizeMode)
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 2, 42, 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _MiniResizeChip(
                                  label: _overlayFullWidth
                                      ? 'Full W'
                                      : 'Custom W',
                                  active: _overlayFullWidth,
                                  onTap: _toggleFullWidthInOverlay,
                                ),
                                const SizedBox(width: 6),
                                _MiniResizeChip(
                                  label: 'H −',
                                  onTap: () => _nudgeHeight(-24),
                                ),
                                const SizedBox(width: 6),
                                _MiniResizeChip(
                                  label: 'H +',
                                  onTap: () => _nudgeHeight(24),
                                ),
                              ],
                            ),
                          ),

                        // Bottom Live Progress Bar
                        if (!isTransparent || _isResizeMode)
                          LinearProgressIndicator(
                            minHeight: 3,
                            value: progress,
                            backgroundColor: fgBase.withValues(alpha: 0.12),
                          ),
                      ],
                    ),

                    // Bottom-Right Corner Drag Handle (active in Resize Mode)
                    if (_isResizeMode)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) =>
                              _handleCornerDrag(details, constraints.maxWidth),
                          onPanEnd: (_) =>
                              _applyWindowResize(enableDrag: false),
                          child: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.bottomRight,
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.south_east_rounded,
                                size: 14,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecondaryLine(
    String text,
    TextTheme textTheme,
    Color fgBase,
    bool isTransparent,
    double fontSize,
    double opacity,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return SizedBox(height: fontSize * 1.0);
    }

    final isRtl = RtlHelper.isRtl(trimmed);
    Widget lineWidget = Text(
      trimmed,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodyMedium?.copyWith(
        fontFamily: isRtl ? 'Vazirmatn' : null,
        fontSize: (fontSize * 0.68).clamp(11.0, 17.0),
        fontWeight: FontWeight.w600,
        color: fgBase.withValues(alpha: opacity),
        height: 1.25,
        shadows: isTransparent
            ? const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 8,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
    );

    if (_blurInactiveLyrics) {
      lineWidget = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
        child: lineWidget,
      );
    }

    return lineWidget;
  }

  Widget _buildLyricsContent(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
    Color fgBase,
    bool isTransparent,
    double fontSize,
    double progress,
    bool showThreeLines,
  ) {
    if (_title == null) {
      return Text(
        'Waiting for music...',
        style: textTheme.bodyMedium?.copyWith(
          color: fgBase.withValues(alpha: 0.7),
        ),
      );
    }

    if (_isFetching) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    final parsed = _parsedLyrics;
    if (parsed == null || parsed.lines.isEmpty) {
      return Text(
        'No synced lyrics for this track',
        textAlign: TextAlign.center,
        style: textTheme.bodySmall?.copyWith(
          color: fgBase.withValues(alpha: 0.7),
        ),
      );
    }

    final lines = parsed.lines;
    int displayIndex = _activeLineIndex;
    if (parsed.syncType == LyricsSyncType.plain) {
      displayIndex = (progress * (lines.length - 1)).round().clamp(
        0,
        lines.length - 1,
      );
    } else if (displayIndex < 0) {
      displayIndex = 0;
    }

    final isBeforeStart =
        parsed.syncType != LyricsSyncType.plain && _activeLineIndex < 0;

    final prevLine = (!isBeforeStart && displayIndex > 0)
        ? lines[displayIndex - 1]
        : null;
    final currentLine = lines[displayIndex];
    final nextLine = (displayIndex + 1 < lines.length)
        ? lines[displayIndex + 1]
        : null;

    final isRtl = RtlHelper.isRtl(currentLine.text);

    Widget activeWidget;
    if (isBeforeStart) {
      activeWidget = Text(
        '♪ •••',
        textAlign: TextAlign.center,
        style: textTheme.titleLarge?.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: scheme.primary.withValues(alpha: 0.8),
        ),
      );
    } else if (currentLine.hasWords) {
      activeWidget = _OverlayWordByWordLine(
        line: currentLine,
        livePosition: _livePosition,
        fontSize: fontSize,
        isRtl: isRtl,
        inactiveColor: fgBase.withValues(alpha: 0.4),
        isTransparent: isTransparent,
      );
    } else {
      activeWidget = Text(
        currentLine.text.isEmpty ? '♪ •••' : currentLine.text,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.titleLarge?.copyWith(
          fontFamily: isRtl ? 'Vazirmatn' : null,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: scheme.primary,
          height: 1.25,
          shadows: [
            Shadow(
              color: isTransparent
                  ? Colors.black87
                  : scheme.primary.withValues(alpha: 0.35),
              blurRadius: isTransparent ? 10 : 12,
              offset: isTransparent ? const Offset(0, 1.5) : Offset.zero,
            ),
          ],
        ),
      );
    }

    final activeKey = ValueKey(
      'overlay_3line_${isBeforeStart ? -1 : displayIndex}',
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == activeKey;
        final offsetTween = isIncoming
            ? Tween<Offset>(
                begin: Offset(0, 0.32 * _slideDirection),
                end: Offset.zero,
              )
            : Tween<Offset>(
                begin: Offset(0, -0.32 * _slideDirection),
                end: Offset.zero,
              );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetTween.animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: activeKey,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showThreeLines) ...[
                _buildSecondaryLine(
                  prevLine?.text ?? '',
                  textTheme,
                  fgBase,
                  isTransparent,
                  fontSize,
                  0.36,
                ),
                const SizedBox(height: 6),
              ],
              activeWidget,
              if (showThreeLines) ...[
                const SizedBox(height: 6),
                _buildSecondaryLine(
                  (isBeforeStart ? currentLine.text : nextLine?.text) ?? '',
                  textTheme,
                  fgBase,
                  isTransparent,
                  fontSize,
                  0.52,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniResizeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MiniResizeChip({
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _OverlayWordByWordLine extends StatelessWidget {
  final LyricLine line;
  final Duration livePosition;
  final double fontSize;
  final bool isRtl;
  final Color inactiveColor;
  final bool isTransparent;

  const _OverlayWordByWordLine({
    required this.line,
    required this.livePosition,
    required this.fontSize,
    required this.isRtl,
    required this.inactiveColor,
    required this.isTransparent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontFamily: isRtl ? 'Vazirmatn' : null,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    final textShadows = [
      Shadow(
        color: isTransparent
            ? Colors.black87
            : scheme.primary.withValues(alpha: 0.45),
        blurRadius: isTransparent ? 10 : 12,
        offset: isTransparent ? const Offset(0, 1.5) : Offset.zero,
      ),
    ];

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 0,
        runSpacing: 4,
        children: line.words.map((word) {
          final totalMs = (word.endTime - word.startTime).inMilliseconds.clamp(
            1,
            60000,
          );
          final elapsedMs = (livePosition - word.startTime).inMilliseconds;
          final progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
          final isCurrentlySinging = progress > 0.0 && progress < 1.0;

          final label = word.text.endsWith(' ') ? word.text : '${word.text} ';

          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            transform: Matrix4.translationValues(
              0,
              isCurrentlySinging ? -2.5 : 0.0,
              0,
            ),
            child: progress <= 0.0
                ? Text(
                    label,
                    style: baseStyle?.copyWith(
                      color: inactiveColor,
                      shadows: isTransparent
                          ? const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  )
                : progress >= 1.0
                ? Text(
                    label,
                    style: baseStyle?.copyWith(
                      color: scheme.primary,
                      shadows: textShadows,
                    ),
                  )
                : ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: isRtl
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        end: isRtl
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        stops: [
                          (progress - 0.03).clamp(0.0, 1.0),
                          (progress + 0.03).clamp(0.0, 1.0),
                        ],
                        colors: [scheme.primary, inactiveColor],
                      ).createShader(bounds);
                    },
                    child: Text(
                      label,
                      style: baseStyle?.copyWith(
                        color: Colors.white,
                        shadows: textShadows,
                      ),
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }
}
