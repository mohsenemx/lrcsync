import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lrcsync/main.dart';

import '../../features/now_playing/data/services/native_media_service.dart';

class ReleaseInfo {
  final String version;
  final String changelog;
  final String htmlUrl;

  const ReleaseInfo({
    required this.version,
    required this.changelog,
    required this.htmlUrl,
  });
}

class UpdateService {
  static String currentVersion = appVersion;
  static const String repoReleasesUrl =
      'https://github.com/mohsenemx/lrcsync/releases';
  static const String _latestApiUrl =
      'https://api.github.com/repos/mohsenemx/lrcsync/releases/latest';

  // Allows F-Droid builds (--dart-define=FDROID=true) to disable startup update checks
  static const bool isFdroidBuild = bool.fromEnvironment(
    'FDROID',
    defaultValue: false,
  );

  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final res = await http
          .get(
            Uri.parse(_latestApiUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'LRCSync/$currentVersion',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final rawTag = (data['tag_name'] as String? ?? '').trim();
      if (rawTag.isEmpty) return null;

      final latestVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '');
      if (_isNewerVersion(currentVersion, latestVersion)) {
        return ReleaseInfo(
          version: latestVersion,
          changelog: (data['body'] as String? ?? '').trim(),
          htmlUrl: (data['html_url'] as String?) ?? repoReleasesUrl,
        );
      }
    } catch (_) {}
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    final currParts = current
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final latestParts = latest
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final maxLen = currParts.length > latestParts.length
        ? currParts.length
        : latestParts.length;
    for (var i = 0; i < maxLen; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static Future<void> checkAndShowModalIfNeeded(
    BuildContext context,
    NativeMediaService mediaService, {
    bool isManualCheck = false,
  }) async {
    if (!isManualCheck && isFdroidBuild) return;

    final release = await checkForUpdate();
    if (!context.mounted) return;

    if (release == null) {
      if (isManualCheck) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('You are on the latest version (v$currentVersion).'),
          ),
        );
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;

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
                      Icons.system_update_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'v$currentVersion → v${release.version}',
                          style: textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (release.changelog.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'What\'s New',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.changelog,
                      style: textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        mediaService.openUrl(release.htmlUrl);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('GitHub Releases'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
