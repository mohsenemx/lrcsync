import 'package:flutter/material.dart';

import '../../../../core/widgets/album_art_view.dart';
import '../../data/models/lyrics_result.dart';
import '../../data/models/track_info.dart';
import '../../data/services/native_media_service.dart';
import 'lyrics_workspace.dart';

class TrackCard extends StatelessWidget {
  final TrackInfo track;
  final NativeMediaService mediaService;
  final LyricsResult? lyricsResult;
  final bool isFetchingLyrics;
  final bool isSavingLyrics;
  final String? lyricsError;
  final void Function({String? title, String? artist, String? album})
  onFetchLyrics;
  final VoidCallback onSaveLyrics;

  const TrackCard({
    super.key,
    required this.track,
    required this.mediaService,
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
        padding: const EdgeInsets.all(20.0),
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
            const SizedBox(height: 16),

            // Compact Cover Art + Track Metadata Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AlbumArtView(
                  track: track,
                  mediaService: mediaService,
                  size: 76,
                  borderRadius: 18,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.album,
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

            // Lyrics Fetch / Retry / Preview / Save Workspace
            LyricsWorkspace(
              track: track,
              lyricsResult: lyricsResult,
              isFetchingLyrics: isFetchingLyrics,
              isSavingLyrics: isSavingLyrics,
              lyricsError: lyricsError,
              onFetchLyrics: onFetchLyrics,
              onSaveLyrics: onSaveLyrics,
            ),
          ],
        ),
      ),
    );
  }
}
