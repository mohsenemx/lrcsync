import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:isolate';

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
  // Synced Settings
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  Color _seedColor = const Color(0xFF6750A4);
  AppFont _appFont = AppFont.system;
  double _lyricsFontSize = 24.0;
  bool _blurInactiveLyrics = true;

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
  int _slideDirection =
      1; // 1 = moving forward (slide up), -1 = rewinding (slide down)

  void _sendCommandToMain(String action) {
    final payload = jsonEncode({
      'type': 'cmd',
      'action': action,
      'reqId': DateTime.now().microsecondsSinceEpoch,
    });
    final sendPort = ui.IsolateNameServer.lookupPortByName(
      kLrcSyncOverlayCmdPort,
    );
    sendPort?.send(payload);
    FlutterOverlayWindow.shareData(payload);
  }

  void _handlePlayPauseTap() {
    _sendCommandToMain('toggle_play_pause');
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    // Register direct state port for Main -> Overlay updates
    ui.IsolateNameServer.removePortNameMapping(kLrcSyncOverlayStatePort);
    _stateReceivePort = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _stateReceivePort!.sendPort,
      kLrcSyncOverlayStatePort,
    );
    _statePortSub = _stateReceivePort!.listen(_onMessageReceived);

    // Keep plugin listener as fallback
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

  void _onMessageReceived(dynamic event) {
    if (event is! String || !mounted) return;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'state') {
        return;
      }

      final settingsMap = decoded['settings'] as Map<String, dynamic>?;
      final trackMap = decoded['track'] as Map<String, dynamic>?;
      final rawLrc = decoded['rawLrc'] as String?;

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

    final double progress = _durationMs > 0
        ? (_livePosition.inMilliseconds / _durationMs).clamp(0.0, 1.0)
        : 0.0;

    final double scaledFontSize = (_lyricsFontSize * 0.78).clamp(13.0, 26.0);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color:
                  (isDark && _amoledDark
                          ? Colors.black
                          : scheme.surfaceContainerHigh)
                      .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top Mini Controls Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.drag_indicator_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _title != null
                              ? '$_title • ${_artist ?? ''}'
                              : 'LRCSync Overlay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
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
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _sendCommandToMain('close');
                          FlutterOverlayWindow.closeOverlay();
                        },
                      ),
                    ],
                  ),
                ),

                // 3-Line Animated Lyrics Display Area
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
                          scaledFontSize,
                          progress,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Live Progress Bar
                LinearProgressIndicator(
                  minHeight: 3,
                  value: progress,
                  backgroundColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryLine(
    String text,
    ColorScheme scheme,
    TextTheme textTheme,
    double fontSize,
    double opacity,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return SizedBox(height: fontSize * 1.1);
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
        color: scheme.onSurface.withValues(alpha: opacity),
        height: 1.25,
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
    double fontSize,
    double progress,
  ) {
    if (_title == null) {
      return Text(
        'Waiting for music...',
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
          color: scheme.primary.withValues(alpha: 0.75),
        ),
      );
    } else if (currentLine.hasWords) {
      activeWidget = _OverlayWordByWordLine(
        line: currentLine,
        livePosition: _livePosition,
        fontSize: fontSize,
        isRtl: isRtl,
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
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
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
              // Line 1: Previous Line
              _buildSecondaryLine(
                prevLine?.text ?? '',
                scheme,
                textTheme,
                fontSize,
                0.34,
              ),
              const SizedBox(height: 6),
              // Line 2: Active Synced Line
              activeWidget,
              const SizedBox(height: 6),
              // Line 3: Next Line
              _buildSecondaryLine(
                (isBeforeStart ? currentLine.text : nextLine?.text) ?? '',
                scheme,
                textTheme,
                fontSize,
                0.50,
              ),
            ],
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

  const _OverlayWordByWordLine({
    required this.line,
    required this.livePosition,
    required this.fontSize,
    required this.isRtl,
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
                      color: scheme.onSurface.withValues(alpha: 0.35),
                    ),
                  )
                : progress >= 1.0
                ? Text(
                    label,
                    style: baseStyle?.copyWith(
                      color: scheme.primary,
                      shadows: [
                        Shadow(
                          color: scheme.primary.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ],
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
                        colors: [
                          scheme.primary,
                          scheme.onSurface.withValues(alpha: 0.35),
                        ],
                      ).createShader(bounds);
                    },
                    child: Text(
                      label,
                      style: baseStyle?.copyWith(color: Colors.white),
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }
}
