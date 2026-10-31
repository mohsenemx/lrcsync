import 'package:flutter/material.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../../core/widgets/album_art_view.dart';
import '../../../now_playing/data/models/lyrics_result.dart';
import '../../../now_playing/data/models/track_info.dart';
import '../../../now_playing/data/services/lyrics_service.dart';
import '../../../now_playing/data/services/native_media_service.dart';
import '../../../now_playing/presentation/widgets/lyrics_workspace.dart';
import '../../../now_playing/data/models/parsed_lyrics.dart';
import '../controllers/library_controller.dart';

import 'dart:io';

class LibraryScreen extends StatefulWidget {
  final LibraryController controller;
  final AppSettingsController settings;
  final LyricsService lyricsService;

  const LibraryScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.lyricsService,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.loadTracks();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openTrackLyricsModal(TrackInfo track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TrackLyricsModalSheet(
        track: track,
        mediaService: widget.controller.mediaService,
        lyricsService: widget.lyricsService,
        settings: widget.settings,
        onLrcSaved: (String lrcType) =>
            widget.controller.markTrackHasLrc(track.filePath, lrcType: lrcType),
      ),
    );
  }

  void _openBatchDownloadModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BatchDownloadModalSheet(
        controller: widget.controller,
        lyricsService: widget.lyricsService,
        settings: widget.settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.downloading_rounded),
            tooltip: 'Download Lyrics for All Songs',
            onPressed: _openBatchDownloadModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan Local Library',
            onPressed: widget.controller.loadTracks,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final tracks = widget.controller.filteredTracks;

          return Column(
            children: [
              // Active Batch Banner if running in background
              if (widget.controller.isBatchRunning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openBatchDownloadModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Batch downloading (${widget.controller.batchProcessed}/${widget.controller.batchTotal})...',
                              style: textTheme.labelLarge?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            'View',
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Filter Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Filter songs, artists, or albums...',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (widget.controller.searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          widget.controller.setSearchQuery('');
                        },
                      ),
                  ],
                  onChanged: widget.controller.setSearchQuery,
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                    scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  ),
                ),
              ),

              Expanded(
                child: widget.controller.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : tracks.isEmpty
                    ? Center(
                        child: Text(
                          'No audio files found.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: AlbumArtView(
                              track: track,
                              mediaService: widget.controller.mediaService,
                              size: 52,
                              borderRadius: 12,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${track.artist} •${track.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (track.hasLocalLrc)
                                  _LrcTypeBadge(
                                    type: track.localLrcType ?? 'LRC',
                                  )
                                else
                                  Icon(
                                    Icons.download_for_offline_outlined,
                                    color: scheme.onSurfaceVariant,
                                  ),
                              ],
                            ),
                            onTap: () => _openTrackLyricsModal(track),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BatchDownloadModalSheet extends StatelessWidget {
  final LibraryController controller;
  final LyricsService lyricsService;
  final AppSettingsController settings;

  const _BatchDownloadModalSheet({
    required this.controller,
    required this.lyricsService,
    required this.settings,
  });

  static const List<int> _delayOptionsMs = [100, 500, 1000, 2500];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final totalSongs = controller.allTracks.length;
        final existingLrcCount = controller.allTracks
            .where((t) => t.hasLocalLrc)
            .length;
        final progress = controller.batchTotal > 0
            ? controller.batchProcessed / controller.batchTotal
            : 0.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.downloading_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Batch Lyrics Downloader',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$totalSongs songs in library ($existingLrcCount already have .lrc)',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Option 1: Skip Existing Lyrics
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ignore songs that already have lyrics'),
                subtitle: const Text(
                  'Skip tracks where a local .lrc file exists',
                ),
                value: controller.skipExistingLrc,
                onChanged: controller.isBatchRunning
                    ? null
                    : controller.setSkipExistingLrc,
              ),
              const SizedBox(height: 8),

              // Option 2: Rate-Limit Protection Delay
              Text(
                'Delay between requests (prevents rate-limiting)',
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _delayOptionsMs.map((ms) {
                  final seconds = (ms / 1000).toStringAsFixed(1);
                  return ChoiceChip(
                    label: Text('${seconds}s'),
                    selected: controller.delayMilliseconds == ms,
                    onSelected: controller.isBatchRunning
                        ? null
                        : (_) => controller.setDelayMilliseconds(ms),
                  );
                }).toList(),
              ),
              // Warning banner when 100ms or 500ms is selected
              if (controller.delayMilliseconds <= 500) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'A ${controller.delayMilliseconds}ms delay is very short and may cause LRCLIB or LRC.red to rate-limit or temporarily block your requests.',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Progress & Results Box
              if (controller.isBatchRunning ||
                  controller.batchProcessed > 0) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            controller.isBatchRunning
                                ? 'Downloading...'
                                : 'Finished',
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          Text(
                            '${controller.batchProcessed} /${controller.batchTotal}',
                            style: textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                        ),
                      ),
                      if (controller.currentBatchTrackTitle != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          controller.currentBatchTrackTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StatChip(
                            label: 'Saved ',
                            count: controller.batchSucceeded,
                            color: scheme.primary,
                          ),
                          _StatChip(
                            label: 'Skipped ',
                            count: controller.batchSkipped,
                            color: scheme.secondary,
                          ),
                          _StatChip(
                            label: 'Not Found ',
                            count: controller.batchFailed,
                            color: scheme.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: controller.isBatchRunning
                    ? FilledButton.tonalIcon(
                        onPressed: controller.cancelBatchDownload,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop Batch Download'),
                      )
                    : FilledButton.icon(
                        onPressed: totalSongs == 0
                            ? null
                            : () => controller.startBatchDownload(
                                lyricsService: lyricsService,
                                settings: settings,
                              ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start Batch Download'),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label:$count',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _TrackLyricsModalSheet extends StatefulWidget {
  final TrackInfo track;
  final NativeMediaService mediaService;
  final LyricsService lyricsService;
  final AppSettingsController settings;
  final ValueChanged<String> onLrcSaved;

  const _TrackLyricsModalSheet({
    required this.track,
    required this.mediaService,
    required this.lyricsService,
    required this.settings,
    required this.onLrcSaved,
  });

  @override
  State<_TrackLyricsModalSheet> createState() => _TrackLyricsModalSheetState();
}

class _TrackLyricsModalSheetState extends State<_TrackLyricsModalSheet> {
  LyricsResult? _lyricsResult;
  bool _isFetching = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExistingLocalLrc();
  }

  Future<void> _loadExistingLocalLrc() async {
    final lrcPath = widget.track.expectedLrcPath;
    if (lrcPath == null) return;
    final file = File(lrcPath);
    if (await file.exists()) {
      final content = (await file.readAsString()).trim();
      if (content.isNotEmpty && mounted) {
        setState(() {
          _lyricsResult = LyricsResult(
            content: content,
            syncType: ParsedLyrics.detectSyncType(content),
            sourceName: 'Local Storage',
          );
        });
      }
    }
  }

  Future<void> _fetchLyrics({
    String? title,
    String? artist,
    String? album,
  }) async {
    setState(() {
      _isFetching = true;
      _error = null;
    });

    final res = await widget.lyricsService.fetchLyrics(
      track: widget.track,
      providersInOrder: widget.settings.activeProvidersInOrder,
      useFallback: widget.settings.useFallbackProvider,
      preferLocalFirst: false,
      preferStandardLrc: widget.settings.preferStandardLrcOverElrc,
      mediaService: widget.mediaService,
      customTitle: title,
      customArtist: artist,
      customAlbum: album,
    );

    if (!mounted) return;
    setState(() {
      _isFetching = false;
      if (res != null) {
        _lyricsResult = res;
      } else {
        final queriedTitle = title?.isNotEmpty == true
            ? title!
            : widget.track.title;
        _error = 'No lyrics found online for "$queriedTitle".';
      }
    });
  }

  Future<void> _saveLyrics() async {
    if (_lyricsResult == null || _isSaving) return;
    setState(() => _isSaving = true);

    final res = await widget.mediaService.saveLrcFile(
      targetPath: widget.track.expectedLrcPath,
      title: widget.track.title,
      artist: widget.track.artist,
      content: _lyricsResult!.content,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res.success) {
      final badgeType = _lyricsResult!.isWordSynced
          ? 'eLRC'
          : (_lyricsResult!.isSynced ? 'LRC' : 'Plain');
      widget.onLrcSaved(badgeType);
      Navigator.of(context).pop();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          res.success
              ? 'Saved to ${res.path}'
              : (res.error ?? 'Failed to save .lrc file.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AlbumArtView(
                  track: widget.track,
                  mediaService: widget.mediaService,
                  size: 64,
                  borderRadius: 16,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.track.artist} • ${widget.track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LyricsWorkspace(
              track: widget.track,
              lyricsResult: _lyricsResult,
              isFetchingLyrics: _isFetching,
              isSavingLyrics: _isSaving,
              lyricsError: _error,
              onFetchLyrics: _fetchLyrics,
              onSaveLyrics: _saveLyrics,
            ),
          ],
        ),
      ),
    );
  }
}

class _LrcTypeBadge extends StatelessWidget {
  final String type; // 'eLRC', 'LRC', or 'Plain'

  const _LrcTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isElrc = type == 'eLRC';
    final isPlain = type == 'Plain';

    final bgColor = isElrc
        ? scheme.tertiaryContainer
        : (isPlain ? scheme.surfaceContainerHighest : scheme.primaryContainer);
    final fgColor = isElrc
        ? scheme.onTertiaryContainer
        : (isPlain ? scheme.onSurfaceVariant : scheme.onPrimaryContainer);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isElrc) ...[
            Icon(Icons.auto_awesome_rounded, size: 12, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            type,
            style: textTheme.labelSmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
