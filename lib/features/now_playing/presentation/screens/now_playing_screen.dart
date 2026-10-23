import 'package:flutter/material.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../controllers/now_playing_controller.dart';
import '../widgets/permissions_modal.dart';
import '../widgets/track_card.dart';

class NowPlayingScreen extends StatefulWidget {
  final NowPlayingController controller;
  final AppSettingsController settings;

  const NowPlayingScreen({
    super.key,
    required this.controller,
    required this.settings,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  Future<void> _handleSaveLyrics() async {
    final result = await widget.controller.saveLyricsToStorage();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          result.success
              ? 'Saved automatically to ${result.path}'
              : (result.error ?? 'Failed to save .lrc file.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LRCSync'),
        actions: [
          if (!widget.controller.hasAllPermissions)
            IconButton(
              icon: Badge(
                child: Icon(Icons.shield_outlined, color: scheme.error),
              ),
              tooltip: 'Permissions Setup',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => PermissionsModal(controller: widget.controller),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Playing Track',
            onPressed: widget.controller.checkPermissions,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, widget.settings]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.cloud_outlined, size: 16),
                  label: Text(
                    'Source: ${widget.settings.primaryProvider.name}',
                  ),
                  onPressed: null,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.controller.currentTrack != null)
                TrackCard(
                  track: widget.controller.currentTrack!,
                  mediaService: widget.controller.mediaService,
                  lyricsResult: widget.controller.lyricsResult,
                  isFetchingLyrics: widget.controller.isFetchingLyrics,
                  isSavingLyrics: widget.controller.isSavingLyrics,
                  lyricsError: widget.controller.lyricsError,
                  onFetchLyrics: ({title, artist, album}) =>
                      widget.controller.fetchLyrics(
                        widget.settings,
                        customTitle: title,
                        customArtist: artist,
                        customAlbum: album,
                      ),
                  onSaveLyrics: _handleSaveLyrics,
                )
              else
                const _EmptyMediaState(),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyMediaState extends StatelessWidget {
  const _EmptyMediaState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Column(
        children: [
          Icon(Icons.music_off_rounded, size: 64, color: scheme.outline),
          const SizedBox(height: 16),
          Text(
            'No Active Music Detected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Play a song in your favorite music player\nand it will appear here automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
