import 'package:flutter/material.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../now_playing/presentation/controllers/now_playing_controller.dart';
import '../../../now_playing/presentation/widgets/permissions_modal.dart';

class SettingsScreen extends StatelessWidget {
  final AppSettingsController settings;
  final NowPlayingController nowPlayingController;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.nowPlayingController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & About')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final providers = settings.providerPriority;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              // --- APPEARANCE / THEME SECTION ---
              const _SectionHeader(title: 'Appearance'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme Mode', style: textTheme.titleSmall),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(
                                Icons.brightness_auto_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'System',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_rounded, size: 18),
                              label: Text(
                                'Light',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_rounded, size: 18),
                              label: Text('Dark', maxLines: 1, softWrap: false),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (selection) {
                            settings.setThemeMode(selection.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Material You Dynamic Color'),
                        subtitle: const Text(
                          'Use wallpaper colors on Android 12+',
                        ),
                        value: settings.useDynamicColor,
                        onChanged: settings.setUseDynamicColor,
                      ),
                      if (!settings.useDynamicColor) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Custom Accent Color',
                          style: textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          children: AppSettingsController.availableSeedColors
                              .map((color) {
                                final isSelected = settings.seedColor == color;
                                return GestureDetector(
                                  onTap: () => settings.setSeedColor(color),
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: color,
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                );
                              })
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pure Black (AMOLED)'),
                        subtitle: const Text(
                          'Use pitch black background in dark mode',
                        ),
                        value: settings.amoledDark,
                        onChanged: settings.setAmoledDark,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- ADJUSTABLE LYRICS PROVIDERS PRIORITY LIST ---
              const _SectionHeader(title: 'Lyrics Providers & Priority Order'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Drag to reorder priority. LRCSync queries #1 first and falls back down the list until lyrics are found.',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: providers.length,
                        onReorder: settings.reorderProviders,
                        itemBuilder: (context, index) {
                          final provider = providers[index];
                          final isEnabled = settings.isProviderEnabled(
                            provider,
                          );

                          return ListTile(
                            key: ValueKey(provider.name),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: isEnabled
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHighest,
                              child: Text(
                                '#${index + 1}',
                                style: textTheme.labelMedium?.copyWith(
                                  color: isEnabled
                                      ? scheme.onPrimaryContainer
                                      : scheme.outline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  provider.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isEnabled
                                        ? scheme.onSurface
                                        : scheme.outline,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'FREE',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${provider.description}\n${provider.baseUrl}',
                              style: textTheme.bodySmall?.copyWith(
                                color: isEnabled
                                    ? scheme.onSurfaceVariant
                                    : scheme.outline,
                              ),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: isEnabled,
                                  onChanged: (val) => settings
                                      .toggleProviderEnabled(provider, val),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.drag_indicator_rounded,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Cascade Fallback Across List'),
                        subtitle: Text(
                          'Active chain: ${settings.activeProvidersInOrder.map((p) => p.name).join(' → ')}',
                        ),
                        value: settings.useFallbackProvider,
                        onChanged: settings.setUseFallbackProvider,
                      ),
                      SwitchListTile(
                        title: const Text('Prefer Local / Cached .lrc First'),
                        subtitle: const Text(
                          'Load from device storage or internal streaming cache before querying online',
                        ),
                        value: settings.preferLocalLrcFirst,
                        onChanged: settings.setPreferLocalLrcFirst,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- PERMISSIONS & ABOUT SECTION ---
              const _SectionHeader(title: 'System & About'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.security_rounded),
                      title: const Text('Permissions Status'),
                      subtitle: const Text(
                        'Review notification & audio storage access',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) =>
                            PermissionsModal(controller: nowPlayingController),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('Clear Internal Lyrics Cache'),
                      subtitle: const Text(
                        'Delete cached lyrics saved for Spotify, YouTube Music & Telegram',
                      ),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear Cached Lyrics?'),
                            content: const Text(
                              'This will delete all streaming lyrics stored in LRCSync\'s internal cache. Local .lrc files in your music folders will not be touched.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete Cache'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && context.mounted) {
                          final deleted = await nowPlayingController
                              .clearInternalCache();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  deleted > 0
                                      ? 'Deleted $deleted cached lyrics file${deleted == 1 ? '' : 's'}.'
                                      : 'Internal lyrics cache is already empty.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const ListTile(
                      leading: Icon(Icons.lyrics_rounded),
                      title: Text('LRCSync'),
                      subtitle: Text(
                        'Version 1.1.0 • Real-time Android media session & local/streaming LRC synchronizer built with Flutter & Material You.',
                      ),
                      isThreeLine: true,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
