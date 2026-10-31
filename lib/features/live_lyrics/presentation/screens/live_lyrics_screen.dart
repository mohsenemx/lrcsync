import 'dart:ui';

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

  const LiveLyricsScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  @override
  State<LiveLyricsScreen> createState() => _LiveLyricsScreenState();
}

class _LiveLyricsScreenState extends State<LiveLyricsScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ScrollController _scrollController = ScrollController();

  Duration _livePosition = Duration.zero;
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

    final newPos = track.estimatedLivePosition;
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

    if (lineChanged && newActiveIndex >= 0) {
      _scrollToActiveLine(newActiveIndex);
    }
  }

  void _scrollToActiveLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final ctx = _lineKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.34,
        duration: const Duration(milliseconds: 480),
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

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Blurred Cover Art Ambient Backdrop
              if (track.artBytes != null)
                Opacity(
                  opacity: Theme.of(context).brightness == Brightness.dark
                      ? 0.28
                      : 0.16,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                    child: Image.memory(track.artBytes!, fit: BoxFit.cover),
                  ),
                ),

              // 2. Gradient Scrim
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface.withValues(alpha: 0.82),
                      scheme.surface.withValues(alpha: 0.62),
                      scheme.surface.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),

              // 3. Full-Screen Lyrics Viewport
              Positioned.fill(child: _buildLyricsBody(context, parsed)),

              // 4. Combined Bottom Floating Island (Header + Controls + Progress)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    // Clears the compact floating navbar at the bottom
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _FloatingTrackIsland(
                      track: track,
                      controller: widget.controller,
                      livePosition: _livePosition,
                      formattedLivePosition: _formatDuration(_livePosition),
                      syncType: parsed?.syncType,
                      onShareCard: parsed != null && parsed.lines.isNotEmpty
                          ? _openScreenshotSheet
                          : null,
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

    // Plain Unsynced Mode (Full Screen with bottom clearance for the island)
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
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        24,
        topInset + MediaQuery.of(context).size.height * 0.14,
        24,
        240, // Ensures bottom lines scroll cleanly above the floating island
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(parsed.lines.length, (index) {
          final line = parsed.lines[index];
          final isActive = index == _activeLineIndex;
          final isPast = index < _activeLineIndex;
          final distance = (_activeLineIndex - index).abs();
          final isRtl = RtlHelper.isRtl(line.text);

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
                      : (isPast ? 0.30 : (distance == 1 ? 0.55 : 0.35)),
                  child: line.hasWords && isActive
                      ? _WordByWordActiveLine(
                          line: line,
                          livePosition: _livePosition,
                          isRtl: isRtl,
                          fontSize: widget.settings.lyricsFontSize,
                          onWordTap: (wordStart) =>
                              _seekToPosition(wordStart, index),
                        )
                      : Text(
                          line.text.isEmpty ? '•••' : line.text,
                          textDirection: isRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          textAlign: isRtl ? TextAlign.right : TextAlign.left,
                          style: textTheme.headlineSmall?.copyWith(
                            fontFamily: isRtl ? 'Vazirmatn' : null,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isActive ? scheme.primary : scheme.onSurface,
                            height: 1.35,
                            fontSize: widget.settings.lyricsFontSize,
                            shadows: isActive
                                ? [
                                    Shadow(
                                      color: scheme.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 18,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FloatingTrackIsland extends StatelessWidget {
  final TrackInfo track;
  final NowPlayingController controller;
  final Duration livePosition;
  final String formattedLivePosition;
  final LyricsSyncType? syncType;
  final VoidCallback? onShareCard;

  const _FloatingTrackIsland({
    required this.track,
    required this.controller,
    required this.livePosition,
    required this.formattedLivePosition,
    required this.syncType,
    this.onShareCard,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
              const SizedBox(height: 10),

              // Bottom Section: Progress Bar + Timestamps & Sync Type
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 4.5,
                  value: track.duration.inMilliseconds > 0
                      ? (livePosition.inMilliseconds /
                                track.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                      : 0.0,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedLivePosition,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    [
                      track.isPlaying ? 'LIVE' : 'PAUSED',
                      if (syncType != null)
                        syncType == LyricsSyncType.wordByWord
                            ? 'WORD SYNC'
                            : (syncType == LyricsSyncType.lineByLine
                                  ? 'LINE SYNC'
                                  : 'PLAIN'),
                    ].join(' • '),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    track.formattedDuration,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
