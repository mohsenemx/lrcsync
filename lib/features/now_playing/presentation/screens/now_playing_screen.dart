import 'package:flutter/material.dart';

import '../controllers/now_playing_controller.dart';
import '../widgets/track_card.dart';

class NowPlayingScreen extends StatefulWidget {
  final NowPlayingController controller;

  const NowPlayingScreen({super.key, required this.controller});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check permissions automatically when user returns from Android Settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.checkPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LRCSync'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Playing Track',
            onPressed: widget.controller.checkPermissions,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!widget.controller.hasNotificationAccess)
                _PermissionBanner(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Access Required',
                  subtitle: 'LRCSync needs access to media notifications to detect the currently playing song.',
                  buttonText: 'Grant Access',
                  onPressed: widget.controller.requestNotificationAccess,
                ),
              if (!widget.controller.hasAudioPermission)
                _PermissionBanner(
                  icon: Icons.folder_open_rounded,
                  title: 'Audio Storage Permission',
                  subtitle: 'Needed to resolve the local file path of the currently playing song.',
                  buttonText: 'Allow Audio Access',
                  onPressed: widget.controller.requestAudioPermission,
                ),
              const SizedBox(height: 8),
              if (widget.controller.currentTrack != null)
                TrackCard(track: widget.controller.currentTrack!)
              else
                const _EmptyMediaState(),
            ],
          );
        },
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _PermissionBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonText),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 64),
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
