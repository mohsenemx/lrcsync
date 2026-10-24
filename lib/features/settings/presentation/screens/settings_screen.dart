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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              // --- APPEARANCE / THEME SECTION ---
              _SectionHeader(title: 'Appearance'),
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
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_rounded),
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_rounded),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_rounded),
                              label: Text('Dark'),
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

              // --- LYRICS PROVIDERS SECTION ---
              _SectionHeader(title: 'Lyrics Providers'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ...LyricsProvider.values.map((provider) {
                        return RadioListTile<LyricsProvider>(
                          value: provider,
                          groupValue: settings.primaryProvider,
                          onChanged: (val) {
                            if (val != null) settings.setPrimaryProvider(val);
                          },
                          title: Row(
                            children: [
                              Text(
                                provider.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
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
                          ),
                          isThreeLine: true,
                        );
                      }),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Automatic Fallback'),
                        subtitle: const Text(
                          'Try other enabled providers automatically if primary finds no match',
                        ),
                        value: settings.useFallbackProvider,
                        onChanged: settings.setUseFallbackProvider,
                      ),
                      SwitchListTile(
                        title: const Text('Prefer Local .lrc File First'),
                        subtitle: const Text(
                          'Check beside the audio file before querying online',
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
              _SectionHeader(title: 'System & About'),
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
                    const ListTile(
                      leading: Icon(Icons.lyrics_rounded),
                      title: Text('LRCSync'),
                      subtitle: Text(
                        'Version 1.0.0 • Real-time Android media session & local LRC synchronizer built with Flutter & Material You.',
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
