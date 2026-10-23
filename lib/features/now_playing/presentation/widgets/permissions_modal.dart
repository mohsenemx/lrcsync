import 'package:flutter/material.dart';

import '../controllers/now_playing_controller.dart';

class PermissionsModal extends StatelessWidget {
  final NowPlayingController controller;

  const PermissionsModal({super.key, required this.controller});

  static Future<void> showIfNeeded(
    BuildContext context,
    NowPlayingController controller,
  ) async {
    if (controller.hasAllPermissions) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PermissionsModal(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
                      Icons.security_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Permissions Setup',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Required for LRCSync to detect songs and locate files',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _PermissionStepTile(
                icon: Icons.notifications_active_outlined,
                title: 'Media Notification Access',
                description: 'Reads the title, artist, album, and length from your active music player.',
                isGranted: controller.hasNotificationAccess,
                onAction: controller.requestNotificationAccess,
              ),
              const SizedBox(height: 12),
              _PermissionStepTile(
                icon: Icons.folder_open_rounded,
                title: 'Local Audio Storage',
                description: 'Matches the active song to its local file path so .lrc files can be synced.',
                isGranted: controller.hasAudioPermission,
                onAction: controller.requestAudioPermission,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    controller.hasAllPermissions
                        ? 'All Set — Continue'
                        : 'Continue Anyway',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PermissionStepTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onAction;

  const _PermissionStepTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted
              ? scheme.primary.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.check_circle_rounded : icon,
            color: isGranted ? scheme.primary : scheme.onSurfaceVariant,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!isGranted)
            FilledButton.tonal(onPressed: onAction, child: const Text('Grant'))
          else
            Text(
              'Granted',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
