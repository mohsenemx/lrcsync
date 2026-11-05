import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../../core/utils/rtl_helper.dart';
import '../../../../core/widgets/album_art_view.dart';
import '../../../now_playing/data/models/parsed_lyrics.dart';
import '../../../now_playing/data/models/track_info.dart';
import '../../../now_playing/presentation/controllers/now_playing_controller.dart';
import '../widgets/lyrics_screenshot_sheet.dart';

class LiveLyricsScreen extends StatefulWidget {
  final NowPlayingController controller;
  final AppSettingsController settings;
  final bool isActive;
  const LiveLyricsScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.isActive,
  });

  @override
  State<LiveLyricsScreen> createState() => _LiveLyricsScreenState();
}

class _LiveLyricsScreenState extends State<LiveLyricsScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ScrollController _scrollController = ScrollController();

  Duration _livePosition = Duration.zero;
  Duration? _draggingPosition;
  int _activeLineIndex = -1;
  String? _lastAutoFetchedTrackKey;
  List<GlobalKey> _lineKeys = [];
  int _lastLineCount = 0;

  void _openScreenshotSheet() {
    final track = widget.controller.currentTrack;
    final parsed = widget.controller.lyricsResult?.parsed;
    if (track == null || parsed == null || parsed.lines.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LyricsScreenshotSheet(
        track: track,
        parsedLyrics: parsed,
        initialActiveIndex: _activeLineIndex,
        mediaService: widget.controller.mediaService,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _ticker = createTicker(_onTick)..start();
    _onControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final track = widget.controller.currentTrack;
    if (track == null) {
      _activeLineIndex = -1;
      return;
    }

    final trackKey = '${track.title}_${track.artist}';
    if (_lastAutoFetchedTrackKey != trackKey &&
        widget.controller.lyricsResult == null &&
        !widget.controller.isFetchingLyrics) {
      _lastAutoFetchedTrackKey = trackKey;
      widget.controller.fetchLyrics(widget.settings);
    }
  }

  void _onTick(Duration _) {
    final track = widget.controller.currentTrack;
    if (track == null || !mounted) return;

    final newPos = _draggingPosition ?? track.estimatedLivePosition;
    final parsed = widget.controller.lyricsResult?.parsed;

    int newActiveIndex = -1;
    if (parsed != null && parsed.syncType != LyricsSyncType.plain) {
      for (var i = 0; i < parsed.lines.length; i++) {
        if (newPos >= parsed.lines[i].startTime) {
          newActiveIndex = i;
        } else {
          break;
        }
      }
    }

    final lineChanged = newActiveIndex != _activeLineIndex;
    setState(() {
      _livePosition = newPos;
      _activeLineIndex = newActiveIndex;
    });

    if (lineChanged && newActiveIndex >= 0 && _draggingPosition == null) {
      _scrollToActiveLine(newActiveIndex);
    }
  }

  void _scrollToActiveLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    // Do not force focus/scroll if the user is currently browsing another tab (e.g. Library or Settings)
    if (!mounted || !widget.isActive) return;

    final ctx = _lineKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.34,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _seekToPosition(Duration target, int lineIndex) {
    widget.controller.seekTo(target);
    setState(() {
      _livePosition = target;
      _scrollToActiveLine(lineIndex);
      _activeLineIndex = lineIndex;
    });
  }

  void _seekFromProgressBar(Duration target) {
    final parsed = widget.controller.lyricsResult?.parsed;
    int targetLineIndex = -1;
    if (parsed != null && parsed.syncType != LyricsSyncType.plain) {
      for (var i = 0; i < parsed.lines.length; i++) {
        if (target >= parsed.lines[i].startTime) {
          targetLineIndex = i;
        } else {
          break;
        }
      }
    }

    widget.controller.seekTo(target);
    setState(() {
      _draggingPosition = null;
      _livePosition = target;
      _activeLineIndex = targetLineIndex;
    });

    if (targetLineIndex >= 0) {
      _scrollToActiveLine(targetLineIndex);
    }
  }

  void _ensureLineKeys(int count) {
    if (_lastLineCount != count) {
      _lastLineCount = count;
      _lineKeys = List.generate(count, (_) => GlobalKey());
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final track = widget.controller.currentTrack;
    final lyricsResult = widget.controller.lyricsResult;

    if (track == null) {
      return ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(title: const Text('Live Lyrics')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lyrics_outlined, size: 64, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text('No Active Track', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Play a song in your music player to see live synced lyrics.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final parsed = lyricsResult?.parsed;
    if (parsed != null) {
      _ensureLineKeys(parsed.lines.length);
    }

    final displayedPosition = _draggingPosition ?? _livePosition;

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Animated Moving Color Blobs Extracted from Song Cover Art
              _AnimatedCoverBlobsBackground(
                artBytes: track.artBytes,
                isPlaying: track.isPlaying,
              ),

              // 2. Full-Screen Lyrics Viewport
              Positioned.fill(child: _buildLyricsBody(context, parsed)),

              // 3. Combined Bottom Floating Island (Header + Controls + Progress)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _FloatingTrackIsland(
                      track: track,
                      controller: widget.controller,
                      livePosition: displayedPosition,
                      formattedLivePosition: _formatDuration(displayedPosition),
                      syncType: parsed?.syncType,
                      onShareCard: parsed != null && parsed.lines.isNotEmpty
                          ? _openScreenshotSheet
                          : null,
                      onScrubUpdate: (pos) {
                        setState(() => _draggingPosition = pos);
                      },
                      onSeekSelected: _seekFromProgressBar,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricsBody(BuildContext context, ParsedLyrics? parsed) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topInset = MediaQuery.of(context).padding.top;

    if (widget.controller.isFetchingLyrics) {
      return const Center(child: CircularProgressIndicator());
    }

    if (parsed == null || parsed.lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(left: 32, right: 32, bottom: 140),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note_rounded, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              Text(
                widget.controller.lyricsError ?? 'No lyrics loaded yet.',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => widget.controller.fetchLyrics(widget.settings),
                icon: const Icon(Icons.lyrics_rounded),
                label: const Text('Fetch Lyrics'),
              ),
            ],
          ),
        ),
      );
    }

    // Plain Unsynced Mode
    if (parsed.syncType == LyricsSyncType.plain) {
      return ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(28, topInset + 24, 28, 220),
        itemCount: parsed.lines.length,
        itemBuilder: (context, index) {
          final lineText = parsed.lines[index].text;
          final isRtl = RtlHelper.isRtl(lineText);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              lineText,
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
              style: textTheme.titleLarge?.copyWith(
                fontFamily: isRtl ? 'Vazirmatn' : null,
                color: scheme.onSurface.withValues(alpha: 0.88),
                fontSize: widget.settings.lyricsFontSize,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      );
    }

    // Synced Mode (Word-by-Word & Line-by-Line)
    final blurEnabled = widget.settings.blurInactiveLyrics;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        topInset + MediaQuery.of(context).size.height * 0.14,
        24,
        240,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(parsed.lines.length, (index) {
          final line = parsed.lines[index];
          final isActive = index == _activeLineIndex;
          final isPast = index < _activeLineIndex;
          final distance = (_activeLineIndex - index).abs();
          final isRtl = RtlHelper.isRtl(line.text);

          // Depth-of-field blur for unfocused lines when enabled
          final double blurSigma = (!blurEnabled || isActive)
              ? 0.0
              : (distance == 1 ? 1.8 : 3.2);

          Widget lineContent = line.hasWords && isActive
              ? _WordByWordActiveLine(
                  line: line,
                  livePosition: _livePosition,
                  isRtl: isRtl,
                  fontSize: widget.settings.lyricsFontSize,
                  onWordTap: (wordStart) => _seekToPosition(wordStart, index),
                )
              : Text(
                  line.text.isEmpty ? '•••' : line.text,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  style: textTheme.headlineSmall?.copyWith(
                    fontFamily: isRtl ? 'Vazirmatn' : null,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? scheme.primary : scheme.onSurface,
                    height: 1.35,
                    fontSize: widget.settings.lyricsFontSize,
                    shadows: isActive
                        ? [
                            Shadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 18,
                            ),
                          ]
                        : null,
                  ),
                );

          if (blurSigma > 0) {
            lineContent = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: lineContent,
            );
          }

          return GestureDetector(
            key: _lineKeys[index],
            behavior: HitTestBehavior.opaque,
            onTap: () => _seekToPosition(line.startTime, index),
            child: Container(
              width: double.infinity,
              alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: AnimatedScale(
                scale: isActive ? 1.03 : 0.94,
                alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 320),
                  opacity: isActive
                      ? 1.0
                      : (isPast ? 0.32 : (distance == 1 ? 0.58 : 0.38)),
                  child: lineContent,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ============================================================================
// ANIMATED COVER ART COLOR BLOBS BACKGROUND
// ============================================================================

class _AnimatedCoverBlobsBackground extends StatefulWidget {
  final Uint8List? artBytes;
  final bool isPlaying;

  const _AnimatedCoverBlobsBackground({
    required this.artBytes,
    required this.isPlaying,
  });

  @override
  State<_AnimatedCoverBlobsBackground> createState() =>
      _AnimatedCoverBlobsBackgroundState();
}

class _AnimatedCoverBlobsBackgroundState
    extends State<_AnimatedCoverBlobsBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<Color> _palette = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
    _extractPalette(widget.artBytes);
  }

  @override
  void didUpdateWidget(covariant _AnimatedCoverBlobsBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artBytes != widget.artBytes) {
      _extractPalette(widget.artBytes);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _extractPalette(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) {
      if (mounted) setState(() => _palette = []);
      return;
    }

    try {
      // Decode cover art to a tiny 6x6 grid to sample dominant colors rapidly
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 6,
        targetHeight: 6,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();

      if (byteData == null) return;
      final data = byteData.buffer.asUint8List();
      final extracted = <Color>[];

      // Sample 5 spread-out regions across the cover art
      const sampleIndices = [0, 5, 14, 21, 30, 35];
      for (final idx in sampleIndices) {
        final offset = idx * 4;
        if (offset + 3 < data.length) {
          final r = data[offset];
          final g = data[offset + 1];
          final b = data[offset + 2];
          final rawColor = Color.fromARGB(255, r, g, b);

          // Boost saturation slightly so background blobs look vibrant
          final hsl = HSLColor.fromColor(rawColor);
          final vibrant = hsl
              .withSaturation((hsl.saturation * 1.35).clamp(0.35, 0.95))
              .withLightness(hsl.lightness.clamp(0.25, 0.68))
              .toColor();
          extracted.add(vibrant);
        }
      }

      if (mounted && extracted.isNotEmpty) {
        setState(() => _palette = extracted);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final colors = _palette.length >= 4
        ? _palette
        : [
            scheme.primary,
            scheme.tertiary,
            scheme.secondary,
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ];

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surface),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 65, sigmaY: 65),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ColorBlobsPainter(
                    progress: _controller.value,
                    colors: colors,
                    isDark: isDark,
                  ),
                );
              },
            ),
          ),
          // Soft contrast scrim so lyrics stay crisp and legible
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: isDark ? 0.52 : 0.62),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorBlobsPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final bool isDark;

  const _ColorBlobsPainter({
    required this.progress,
    required this.colors,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;
    final shortestSide = size.shortestSide;

    // 5 organic drifting trajectories using harmonic sine/cosine waves
    final blobs = [
      Offset(
        size.width * (0.25 + 0.28 * math.sin(t + 0.4)),
        size.height * (0.22 + 0.20 * math.cos(t * 2 + 1.1)),
      ),
      Offset(
        size.width * (0.75 + 0.25 * math.cos(t + 2.0)),
        size.height * (0.30 + 0.25 * math.sin(t + 0.7)),
      ),
      Offset(
        size.width * (0.30 + 0.30 * math.cos(t * 2 + 3.2)),
        size.height * (0.68 + 0.22 * math.sin(t + 2.5)),
      ),
      Offset(
        size.width * (0.72 + 0.24 * math.sin(t + 4.5)),
        size.height * (0.75 + 0.20 * math.cos(t + 1.8)),
      ),
      Offset(
        size.width * (0.50 + 0.32 * math.sin(t * 2 + 5.1)),
        size.height * (0.48 + 0.28 * math.cos(t + 3.9)),
      ),
    ];

    final radii = [
      shortestSide * 0.68,
      shortestSide * 0.62,
      shortestSide * 0.72,
      shortestSide * 0.60,
      shortestSide * 0.58,
    ];

    final baseAlpha = isDark ? 0.68 : 0.55;

    for (var i = 0; i < blobs.length; i++) {
      final color = colors[i % colors.length];
      final center = blobs[i];
      final radius = radii[i];

      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            color.withValues(alpha: baseAlpha),
            color.withValues(alpha: baseAlpha * 0.45),
            color.withValues(alpha: 0.0),
          ],
          const [0.0, 0.55, 1.0],
        );

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColorBlobsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.colors != colors ||
        oldDelegate.isDark != isDark;
  }
}

class _FloatingTrackIsland extends StatelessWidget {
  final TrackInfo track;
  final NowPlayingController controller;
  final Duration livePosition;
  final String formattedLivePosition;
  final LyricsSyncType? syncType;
  final VoidCallback? onShareCard;
  final ValueChanged<Duration> onScrubUpdate;
  final ValueChanged<Duration> onSeekSelected;

  const _FloatingTrackIsland({
    required this.track,
    required this.controller,
    required this.livePosition,
    required this.formattedLivePosition,
    required this.syncType,
    this.onShareCard,
    required this.onScrubUpdate,
    required this.onSeekSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final maxMs = track.duration.inMilliseconds > 0
        ? track.duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMs = livePosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Cover Art + Title/Artist + Share Button + Play/Pause
              Row(
                children: [
                  AlbumArtView(
                    track: track,
                    mediaService: controller.mediaService,
                    size: 44,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${track.artist} • ${track.sourceAppName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onShareCard != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.photo_camera_back_rounded,
                        size: 20,
                      ),
                      tooltip: 'Create Lyrics Card',
                      onPressed: onShareCard,
                    ),
                  const SizedBox(width: 2),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(38, 38),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: controller.togglePlayPause,
                    icon: Icon(
                      track.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                    ),
                    tooltip: track.isPlaying ? 'Pause' : 'Play',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Material Design 3 Interactive Seek Bar (Tap & Slide)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5.0,
                  trackShape: const RoundedRectSliderTrackShape(),
                  activeTrackColor: scheme.primary,
                  inactiveTrackColor: scheme.surfaceContainerHighest,
                  thumbColor: scheme.primary,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6.5,
                    pressedElevation: 4.0,
                  ),
                  overlayColor: scheme.primary.withValues(alpha: 0.16),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12.0,
                  ),
                ),
                child: SizedBox(
                  height: 22,
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    allowedInteraction: SliderInteraction.tapAndSlide,
                    onChanged: track.duration.inMilliseconds > 0
                        ? (val) =>
                              onScrubUpdate(Duration(milliseconds: val.round()))
                        : null,
                    onChangeEnd: track.duration.inMilliseconds > 0
                        ? (val) => onSeekSelected(
                            Duration(milliseconds: val.round()),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedLivePosition,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),

                  Text(
                    track.formattedDuration,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordByWordActiveLine extends StatelessWidget {
  final LyricLine line;
  final Duration livePosition;
  final double fontSize;
  final bool isRtl;
  final ValueChanged<Duration>? onWordTap;

  const _WordByWordActiveLine({
    required this.line,
    required this.livePosition,
    required this.fontSize,
    this.isRtl = false,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontFamily: isRtl ? 'Vazirmatn' : null,
      fontWeight: FontWeight.w800,
      height: 1.35,
      fontSize: fontSize,
    );

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 0,
        runSpacing: 6,
        children: line.words.map((word) {
          final totalMs = (word.endTime - word.startTime).inMilliseconds.clamp(
            1,
            60000,
          );
          final elapsedMs = (livePosition - word.startTime).inMilliseconds;
          final progress = (elapsedMs / totalMs).clamp(0.0, 1.0);
          final isCurrentlySinging = progress > 0.0 && progress < 1.0;
          final verticalOffset = isCurrentlySinging ? -3.0 : 0.0;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onWordTap != null ? () => onWordTap!(word.startTime) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              transform: Matrix4.translationValues(0, verticalOffset, 0),
              child: progress <= 0.0
                  ? Text(
                      word.text.endsWith(' ') ? word.text : '${word.text} ',
                      style: baseStyle?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.35),
                      ),
                    )
                  : progress >= 1.0
                  ? Text(
                      word.text.endsWith(' ') ? word.text : '${word.text} ',
                      style: baseStyle?.copyWith(
                        color: scheme.primary,
                        shadows: [
                          Shadow(
                            color: scheme.primary.withValues(alpha: 0.45),
                            blurRadius: 16,
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
                        word.text.endsWith(' ') ? word.text : '${word.text} ',
                        style: baseStyle?.copyWith(
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: scheme.primary.withValues(alpha: 0.45),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
