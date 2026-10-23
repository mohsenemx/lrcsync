import 'package:flutter/material.dart';

import '../../data/models/lyrics_result.dart';
import '../../data/models/track_info.dart';

class TrackCard extends StatelessWidget {
  final TrackInfo track;
  final LyricsResult? lyricsResult;
  final bool isFetchingLyrics;
  final bool isSavingLyrics;
  final String? lyricsError;
  final VoidCallback onFetchLyrics;
  final VoidCallback onSaveLyrics;

  const TrackCard({
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Chip (Now Playing + Duration)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 16,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Now Playing',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  track.formattedDuration,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              track.title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),

            // Artist & Album
            Text(
              '${track.artist} • ${track.album}',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Fetch Lyrics Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isFetchingLyrics ? null : onFetchLyrics,
                icon: isFetchingLyrics
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        lyricsResult == null
                            ? Icons.lyrics_rounded
                            : Icons.refresh_rounded,
                      ),
                label: Text(
                  isFetchingLyrics
                      ? 'Fetching Lyrics...'
                      : (lyricsResult == null
                            ? 'Fetch Lyrics'
                            : 'Re-fetch Lyrics'),
                ),
              ),
            ),

            // Error Message
            if (lyricsError != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  lyricsError!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],

            // Fetched Lyrics Display + Save Button
            if (lyricsResult != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        lyricsResult!.isSynced
                            ? Icons.timer_outlined
                            : Icons.subject_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        lyricsResult!.isSynced ? 'Synced LRC' : 'Plain Lyrics',
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'via ${lyricsResult!.sourceName}',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    lyricsResult!.content,
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
                  onPressed: isSavingLyrics ? null : onSaveLyrics,
                  icon: isSavingLyrics
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.save_alt_rounded),
                  label: Text(
                    isSavingLyrics ? 'Saving...' : 'Save .lrc to Storage',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
