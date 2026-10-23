import 'package:flutter/material.dart';

import '../../data/models/lyrics_result.dart';
import '../../data/models/track_info.dart';

class LyricsWorkspace extends StatefulWidget {
  final TrackInfo track;
  final LyricsResult? lyricsResult;
  final bool isFetchingLyrics;
  final bool isSavingLyrics;
  final String? lyricsError;
  final void Function({String? title, String? artist, String? album})
  onFetchLyrics;
  final VoidCallback onSaveLyrics;

  const LyricsWorkspace({
    super.key,
    required this.track,
    required this.lyricsResult,
    required this.isFetchingLyrics,
    required this.isSavingLyrics,
    required this.lyricsError,
    required this.onFetchLyrics,
    required this.onSaveLyrics,
  });

  @override
  State<LyricsWorkspace> createState() => _LyricsWorkspaceState();
}

class _LyricsWorkspaceState extends State<LyricsWorkspace> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  bool _showManualEditor = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _artistController = TextEditingController();
    _albumController = TextEditingController();
    _syncControllersWithTrack();
  }

  @override
  void didUpdateWidget(covariant LyricsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.title != widget.track.title ||
        oldWidget.track.artist != widget.track.artist ||
        oldWidget.track.album != widget.track.album) {
      _syncControllersWithTrack();
      _showManualEditor = false;
    } else if (widget.lyricsError != null && oldWidget.lyricsError == null) {
      // Automatically expand the 3-field editor when a search returns no results
      _showManualEditor = true;
    }
  }

  void _syncControllersWithTrack() {
    _titleController.text = widget.track.title == 'Unknown Title'
        ? ''
        : widget.track.title;
    _artistController.text = widget.track.artist == 'Unknown Artist'
        ? ''
        : widget.track.artist;
    _albumController.text = widget.track.album == 'Unknown Album'
        ? ''
        : widget.track.album;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  void _triggerFetch() {
    FocusScope.of(context).unfocus();
    if (_showManualEditor) {
      widget.onFetchLyrics(
        title: _titleController.text.trim(),
        artist: _artistController.text.trim(),
        album: _albumController.text.trim(),
      );
    } else {
      widget.onFetchLyrics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fetch Button + Edit Song Info Button Row
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.isFetchingLyrics ? null : _triggerFetch,
                icon: widget.isFetchingLyrics
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        widget.lyricsResult == null
                            ? Icons.lyrics_rounded
                            : Icons.refresh_rounded,
                      ),
                label: Text(
                  widget.isFetchingLyrics
                      ? 'Searching Lyrics...'
                      : (_showManualEditor
                            ? 'Fetch with Custom Info'
                            : (widget.lyricsResult == null
                                  ? 'Fetch Lyrics'
                                  : 'Re-fetch Lyrics')),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: _showManualEditor
                  ? 'Hide Editor'
                  : 'Edit Title / Artist / Album',
              isSelected: _showManualEditor,
              onPressed: () {
                setState(() => _showManualEditor = !_showManualEditor);
              },
              icon: Icon(
                _showManualEditor ? Icons.close_rounded : Icons.edit_rounded,
              ),
            ),
          ],
        ),

        // Error Banner (if search returned no result)
        if (widget.lyricsError != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  color: scheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.lyricsError!,
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

        // 3-Field Manual Metadata Editor (Toggled via Edit button or Auto-opened on fail)
        if (_showManualEditor) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Custom Search Query',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _syncControllersWithTrack,
                      icon: const Icon(Icons.restart_alt_rounded, size: 16),
                      label: const Text('Reset'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _artistController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Artist',
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _albumController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _triggerFetch(),
                  decoration: InputDecoration(
                    labelText: 'Album (optional)',
                    hintText: 'Leave empty to ignore album',
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surface,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      tooltip: 'Clear album',
                      onPressed: _albumController.clear,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Fetched Lyrics Preview + Save to Storage Button
        if (widget.lyricsResult != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    widget.lyricsResult!.isSynced
                        ? Icons.timer_outlined
                        : Icons.subject_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.lyricsResult!.isSynced
                        ? 'Synced LRC'
                        : 'Plain Lyrics',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                'via ${widget.lyricsResult!.sourceName}',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.lyricsResult!.content,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: widget.isSavingLyrics ? null : widget.onSaveLyrics,
              icon: widget.isSavingLyrics
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(
                widget.isSavingLyrics ? 'Saving...' : 'Save .lrc to Storage',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
