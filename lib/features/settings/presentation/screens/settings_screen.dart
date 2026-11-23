import 'package:flutter/material.dart';

import '../../../../core/services/update_service.dart';
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

  void _openSubpage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              _SettingsCategoryTile(
                icon: Icons.palette_outlined,
                iconBgColor: scheme.primaryContainer,
                iconColor: scheme.onPrimaryContainer,
                title: 'Customization & Typography',
                subtitle:
                    'Theme, Material You, app font (${settings.appFont.label}) & lyrics size',
                onTap: () => _openSubpage(
                  context,
                  _CustomizationSubpage(settings: settings),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCategoryTile(
                icon: Icons.picture_in_picture_alt_rounded,
                iconBgColor: scheme.tertiaryContainer,
                iconColor: scheme.onTertiaryContainer,
                title: 'Floating Lyrics Window',
                subtitle:
                    '${settings.overlayShape.label} • ${settings.overlayBackgroundStyle.label} • ${(settings.overlayOpacity * 100).round()}% opacity',
                onTap: () => _openSubpage(
                  context,
                  _FloatingOverlaySubpage(settings: settings),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCategoryTile(
                icon: Icons.tune_rounded,
                iconBgColor: scheme.secondaryContainer,
                iconColor: scheme.onSecondaryContainer,
                title: 'Lyrics & Behavior',
                subtitle:
                    'Provider priority (${settings.primaryProvider.name} first), LRC vs eLRC & fallback',
                onTap: () =>
                    _openSubpage(context, _BehaviorSubpage(settings: settings)),
              ),
              const SizedBox(height: 12),
              _SettingsCategoryTile(
                icon: Icons.folder_special_outlined,
                iconBgColor: scheme.tertiaryContainer,
                iconColor: scheme.onTertiaryContainer,
                title: 'Storage & Permissions',
                subtitle:
                    'Notification access, storage permissions & internal cache',
                onTap: () => _openSubpage(
                  context,
                  _StoragePermissionsSubpage(
                    nowPlayingController: nowPlayingController,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCategoryTile(
                icon: Icons.info_outline_rounded,
                iconBgColor: scheme.surfaceContainerHighest,
                iconColor: scheme.onSurfaceVariant,
                title: 'About & Updates',
                subtitle: UpdateService.isFdroidBuild
                    ? 'Version ${UpdateService.currentVersion}, GitHub repo & credits'
                    : 'Version ${UpdateService.currentVersion}, GitHub releases & credits',
                onTap: () => _openSubpage(
                  context,
                  _AboutSubpage(nowPlayingController: nowPlayingController),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsCategoryTile extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsCategoryTile({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: iconBgColor,
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: textTheme.bodySmall),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================
// 1. CUSTOMIZATION & TYPOGRAPHY SUBMENU
// ============================================================================

class _CustomizationSubpage extends StatelessWidget {
  final AppSettingsController settings;

  const _CustomizationSubpage({required this.settings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Customization')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader(title: 'Theme & Colors'),
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
                          onSelectionChanged: (s) =>
                              settings.setThemeMode(s.first),
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
                          'Pitch black background in dark mode',
                        ),
                        value: settings.amoledDark,
                        onChanged: settings.setAmoledDark,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Blur Unfocused Lyrics'),
                        subtitle: const Text(
                          'Apply a depth-of-field blur to inactive lines in Live Lyrics',
                        ),
                        value: settings.blurInactiveLyrics,
                        onChanged: settings.setBlurInactiveLyrics,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const _SectionHeader(title: 'Typography & Lyrics Text Size'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Font', style: textTheme.titleSmall),

                      const SizedBox(height: 10),
                      DropdownMenu<AppFont>(
                        initialSelection: settings.appFont,
                        expandedInsets: EdgeInsets.zero,
                        leadingIcon: const Icon(Icons.font_download_outlined),
                        textStyle: TextStyle(
                          fontFamily: settings.appFont.fontFamily,
                          fontWeight: FontWeight.w600,
                        ),

                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: scheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          outlineBorder: BorderSide(
                            strokeAlign: 10,
                            width: 10,
                            style: BorderStyle.solid,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ),
                        onSelected: (font) {
                          if (font != null) {
                            settings.setAppFont(font);
                          }
                        },
                        dropdownMenuEntries: AppFont.values.map((font) {
                          return DropdownMenuEntry<AppFont>(
                            value: font,
                            label: font.label,
                            style: MenuItemButton.styleFrom(
                              textStyle: TextStyle(
                                fontFamily: font.fontFamily,
                                fontSize: 15,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Fallback font for Persian/Arabic is Vazirmatn.',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Lyrics Text Size', style: textTheme.titleSmall),
                          Text(
                            '${settings.lyricsFontSize.round()} pt',
                            style: textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.lyricsFontSize,
                        min: 16.0,
                        max: 36.0,
                        divisions: 10,
                        label: '${settings.lyricsFontSize.round()} pt',
                        onChanged: settings.setLyricsFontSize,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '♪ Preview of live synced lyrics text',
                          style: TextStyle(
                            fontSize: settings.lyricsFontSize,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 2. LYRICS & BEHAVIOR SUBMENU
// ============================================================================

class _BehaviorSubpage extends StatelessWidget {
  final AppSettingsController settings;

  const _BehaviorSubpage({required this.settings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Lyrics & Behavior')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final providers = settings.providerPriority;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader(title: 'Format & Fetching Behavior'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Prefer Standard LRC over eLRC'),
                      subtitle: const Text(
                        'Save line-by-line .lrc instead of word-by-word eLRC (applies to single & batch downloads)',
                      ),
                      value: settings.preferStandardLrcOverElrc,
                      onChanged: settings.setPreferStandardLrcOverElrc,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Prefer Local / Cached .lrc First'),
                      subtitle: const Text(
                        'Load existing lyrics from storage before querying online',
                      ),
                      value: settings.preferLocalLrcFirst,
                      onChanged: settings.setPreferLocalLrcFirst,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Cascade Fallback Across Providers'),
                      subtitle: Text(
                        'Active chain: ${settings.activeProvidersInOrder.map((p) => p.name).join(' → ')}',
                      ),
                      value: settings.useFallbackProvider,
                      onChanged: settings.setUseFallbackProvider,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const _SectionHeader(title: 'Provider Priority Order'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Drag to reorder priority. LRCSync queries #1 first and falls back down the list.',
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
                            title: Text(
                              provider.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isEnabled
                                    ? scheme.onSurface
                                    : scheme.outline,
                              ),
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
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 3. STORAGE & PERMISSIONS SUBMENU
// ============================================================================

class _StoragePermissionsSubpage extends StatelessWidget {
  final NowPlayingController nowPlayingController;

  const _StoragePermissionsSubpage({required this.nowPlayingController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Permissions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Permissions Status'),
                  subtitle: const Text(
                    'Review notification listener & audio storage access',
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
                          'This deletes all streaming lyrics stored in LRCSync\'s internal cache. Local .lrc files in your music folders will not be touched.',
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. ABOUT & UPDATES SUBMENU
// ============================================================================

class _AboutSubpage extends StatelessWidget {
  final NowPlayingController nowPlayingController;

  const _AboutSubpage({required this.nowPlayingController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Updates')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.lyrics_rounded),
                  title: Text('LRCSync'),
                  subtitle: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version ${UpdateService.currentVersion} '),
                      const SizedBox(height: 6),
                      Text(
                        'Real-time Android media session & local/streaming LRC synchronizer built with Flutter & Material You.',
                      ),
                    ],
                  ),

                  isThreeLine: true,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                if (!UpdateService.isFdroidBuild)
                  ListTile(
                    leading: const Icon(Icons.system_update_rounded),
                    title: const Text('Check for Updates'),
                    subtitle: const Text(
                      'Query GitHub Releases for a newer version',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => UpdateService.checkAndShowModalIfNeeded(
                      context,
                      nowPlayingController.mediaService,
                      isManualCheck: true,
                    ),
                  ),
                if (!UpdateService.isFdroidBuild)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                if (!UpdateService.isFdroidBuild)
                  ListTile(
                    leading: const Icon(Icons.code_rounded),
                    title: const Text('GitHub Repository'),
                    subtitle: const Text('github.com/mohsenemx/lrcsync'),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => nowPlayingController.mediaService.openUrl(
                      'https://github.com/mohsenemx/lrcsync',
                    ),
                  ),
                if (UpdateService.isFdroidBuild)
                  ListTile(
                    leading: const Icon(Icons.code_rounded),
                    title: const Text('Updates'),
                    subtitle: const Text(
                      'Updates are provided through F-Droid.',
                    ),
                  ),
                if (UpdateService.isFdroidBuild)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                if (UpdateService.isFdroidBuild)
                  ListTile(
                    leading: const Icon(Icons.code_rounded),
                    title: const Text('Github Repository'),
                    subtitle: const Text(
                      'https://github.com/mohsenemx/lrcsync',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => nowPlayingController.mediaService.openUrl(
                      'https://github.com/mohsenemx/lrcsync',
                    ),
                  ),
              ],
            ),
          ),
        ],
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

// ============================================================================
// 5. FLOATING LYRICS WINDOW SUBMENU
// ============================================================================

class _FloatingOverlaySubpage extends StatelessWidget {
  final AppSettingsController settings;

  const _FloatingOverlaySubpage({required this.settings});

  Color _previewBgColor(ColorScheme scheme, bool isDark) {
    switch (settings.overlayBackgroundStyle) {
      case OverlayBackgroundStyle.themeSurface:
        final base = (isDark && settings.amoledDark)
            ? Colors.black
            : scheme.surfaceContainerHigh;
        return base.withValues(alpha: settings.overlayOpacity);
      case OverlayBackgroundStyle.amoledBlack:
        return Colors.black.withValues(alpha: settings.overlayOpacity);
      case OverlayBackgroundStyle.frostedDark:
        return const Color(0xFF14151A)
            .withValues(alpha: settings.overlayOpacity);
      case OverlayBackgroundStyle.frostedLight:
        return const Color(0xFFF6F7FB)
            .withValues(alpha: settings.overlayOpacity);
      case OverlayBackgroundStyle.transparent:
        return Colors.transparent;
      case OverlayBackgroundStyle.customColor:
        return settings.overlayCustomColor.withValues(
          alpha: settings.overlayOpacity,
        );
    }
  }

  Color _previewFgColor(ColorScheme scheme) {
    switch (settings.overlayBackgroundStyle) {
      case OverlayBackgroundStyle.amoledBlack:
      case OverlayBackgroundStyle.frostedDark:
      case OverlayBackgroundStyle.transparent:
        return Colors.white;
      case OverlayBackgroundStyle.frostedLight:
        return const Color(0xFF1A1C1E);
      case OverlayBackgroundStyle.customColor:
        return ThemeData.estimateBrightnessForColor(
                  settings.overlayCustomColor,
                ) ==
                Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1C1E);
      case OverlayBackgroundStyle.themeSurface:
        return scheme.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Floating Lyrics'),
        actions: [
          TextButton(
            onPressed: settings.resetOverlayDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final isTransparent =
              settings.overlayBackgroundStyle ==
              OverlayBackgroundStyle.transparent;
          final previewBg = _previewBgColor(scheme, isDark);
          final previewFg = _previewFgColor(scheme);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Live Preview over a wallpaper-like gradient backdrop
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.45),
                      scheme.tertiary.withValues(alpha: 0.40),
                      scheme.secondaryContainer,
                    ],
                  ),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  decoration: BoxDecoration(
                    color: previewBg,
                    borderRadius: BorderRadius.circular(
                      settings.overlayShape.borderRadius,
                    ),
                    border: settings.overlayShowBorder && !isTransparent
                        ? Border.all(color: previewFg.withValues(alpha: 0.18))
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.drag_indicator_rounded,
                            size: 14,
                            color: previewFg.withValues(alpha: 0.65),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Song Title • Artist',
                              style: textTheme.labelSmall?.copyWith(
                                color: previewFg.withValues(alpha: 0.75),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.open_in_full_rounded,
                            size: 15,
                            color: previewFg.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.pause_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Previous lyric line...',
                        style: textTheme.bodySmall?.copyWith(
                          color: previewFg.withValues(alpha: 0.40),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Active synced lyric line',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          shadows: isTransparent
                              ? const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 8,
                                    offset: Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Next upcoming lyric line',
                        style: textTheme.bodySmall?.copyWith(
                          color: previewFg.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Shape & Background
              const _SectionHeader(title: 'Shape & Background'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Window Shape', style: textTheme.titleSmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: OverlayShape.values.map((shape) {
                          return ChoiceChip(
                            label: Text(shape.label),
                            selected: settings.overlayShape == shape,
                            onSelected: (_) => settings.setOverlayShape(shape),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Text('Background Style', style: textTheme.titleSmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: OverlayBackgroundStyle.values.map((style) {
                          return ChoiceChip(
                            label: Text(style.label),
                            selected: settings.overlayBackgroundStyle == style,
                            onSelected: (_) =>
                                settings.setOverlayBackgroundStyle(style),
                          );
                        }).toList(),
                      ),
                      if (settings.overlayBackgroundStyle ==
                          OverlayBackgroundStyle.customColor) ...[
                        const SizedBox(height: 14),
                        Text('Custom Color', style: textTheme.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: AppSettingsController.availableOverlayColors
                              .map((color) {
                                final isSelected =
                                    settings.overlayCustomColor == color;
                                final checkColor =
                                    ThemeData.estimateBrightnessForColor(
                                          color,
                                        ) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black;
                                return GestureDetector(
                                  onTap: () =>
                                      settings.setOverlayCustomColor(color),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: color,
                                      child: isSelected
                                          ? Icon(
                                              Icons.check,
                                              color: checkColor,
                                              size: 18,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      ],
                      if (!isTransparent) ...[
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Background Opacity',
                              style: textTheme.titleSmall,
                            ),
                            Text(
                              '${(settings.overlayOpacity * 100).round()}%',
                              style: textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: settings.overlayOpacity,
                          min: 0.15,
                          max: 1.0,
                          divisions: 17,
                          label: '${(settings.overlayOpacity * 100).round()}%',
                          onChanged: settings.setOverlayOpacity,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Show Window Border'),
                          subtitle: const Text(
                            'Add a subtle outline around the floating card',
                          ),
                          value: settings.overlayShowBorder,
                          onChanged: settings.setOverlayShowBorder,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Dimensions
              const _SectionHeader(title: 'Default Size'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Full Screen Width'),
                        subtitle: const Text(
                          'Span across the screen width (or disable to customize width)',
                        ),
                        value: settings.overlayFullWidth,
                        onChanged: settings.setOverlayFullWidth,
                      ),
                      if (!settings.overlayFullWidth) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Window Width', style: textTheme.titleSmall),
                            Text(
                              '${settings.overlayWidthDp.round()} dp',
                              style: textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: settings.overlayWidthDp,
                          min: 220.0,
                          max: 420.0,
                          divisions: 20,
                          label: '${settings.overlayWidthDp.round()} dp',
                          onChanged: settings.setOverlayWidthDp,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Window Height', style: textTheme.titleSmall),
                          Text(
                            '${settings.overlayHeightDp.round()} dp',
                            style: textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.overlayHeightDp,
                        min: 120.0,
                        max: 400.0,
                        divisions: 28,
                        label: '${settings.overlayHeightDp.round()} dp',
                        onChanged: settings.setOverlayHeightDp,
                      ),
                      Text(
                        'Tip: You can also resize directly on the floating window using the ⤢ icon.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
