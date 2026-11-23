import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lrcsync/main.dart';

import '../../features/now_playing/data/services/native_media_service.dart';
import '../settings/app_settings_controller.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class ReleaseInfo {
  final String version;
  final String changelog;
  final String htmlUrl;
  final List<ReleaseAsset> apkAssets;

  const ReleaseInfo({
    required this.version,
    required this.changelog,
    required this.htmlUrl,
    required this.apkAssets,
  });

  /// Matches `lrcsync-{version}-{abi}.apk` in device priority order,
  /// falling back to `lrcsync-{version}-universal.apk`.
  ReleaseAsset? pickBestApk(List<String> supportedAbis) {
    if (apkAssets.isEmpty) return null;

    for (final abi in supportedAbis) {
      final needle = '-${abi.toLowerCase()}.apk';
      for (final asset in apkAssets) {
        if (asset.name.toLowerCase().endsWith(needle)) {
          return asset;
        }
      }
    }

    for (final asset in apkAssets) {
      if (asset.name.toLowerCase().endsWith('-universal.apk')) {
        return asset;
      }
    }

    return apkAssets.first;
  }
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
      if (!_isNewerVersion(currentVersion, latestVersion)) return null;

      final rawAssets = (data['assets'] as List<dynamic>?) ?? [];
      final apkAssets = <ReleaseAsset>[];

      for (final item in rawAssets) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['name'] as String? ?? '').trim();
        final url = (item['browser_download_url'] as String? ?? '').trim();
        if (!name.toLowerCase().endsWith('.apk') || url.isEmpty) continue;

        String? sha256;
        final digest = (item['digest'] as String?)?.trim();
        if (digest != null && digest.toLowerCase().startsWith('sha256:')) {
          sha256 = digest.substring(7).trim();
        }

        apkAssets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            sizeBytes: (item['size'] as num?)?.toInt() ?? 0,
            sha256: sha256,
          ),
        );
      }

      return ReleaseInfo(
        version: latestVersion,
        changelog: (data['body'] as String? ?? '').trim(),
        htmlUrl: (data['html_url'] as String?) ?? repoReleasesUrl,
        apkAssets: apkAssets,
      );
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
    AppSettingsController? settings,
    bool isManualCheck = false,
  }) async {
    if (isFdroidBuild) return;

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

    // Respect "Don't show again" on automatic startup checks
    if (!isManualCheck && settings?.skippedUpdateVersion == release.version) {
      return;
    }

    final supportedAbis = await mediaService.getSupportedAbis();
    if (!context.mounted) return;

    final matchedApk = release.pickBestApk(supportedAbis);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _UpdateBottomSheet(
        release: release,
        matchedApk: matchedApk,
        mediaService: mediaService,
        settings: settings,
      ),
    );
  }
}

class _UpdateBottomSheet extends StatefulWidget {
  final ReleaseInfo release;
  final ReleaseAsset? matchedApk;
  final NativeMediaService mediaService;
  final AppSettingsController? settings;

  const _UpdateBottomSheet({
    required this.release,
    required this.matchedApk,
    required this.mediaService,
    this.settings,
  });

  @override
  State<_UpdateBottomSheet> createState() => _UpdateBottomSheetState();
}

class _UpdateBottomSheetState extends State<_UpdateBottomSheet> {
  http.Client? _httpClient;
  bool _isDownloading = false;
  bool _isVerifyingAndInstalling = false;
  bool _cancelled = false;

  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedFilePath;
  String? _statusMessage;
  bool _isError = false;
  late bool _dontShowAgain;
  @override
  void initState() {
    super.initState();
    _dontShowAgain =
        widget.settings?.skippedUpdateVersion == widget.release.version;
  }

  @override
  void dispose() {
    _cancelled = true;
    _httpClient?.close();
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    final asset = widget.matchedApk;
    if (asset == null) return;

    // If already downloaded (e.g., user just enabled "Install unknown apps"), install directly
    if (_downloadedFilePath != null &&
        await File(_downloadedFilePath!).exists()) {
      await _triggerInstall(_downloadedFilePath!, asset.sha256);
      return;
    }

    setState(() {
      _isDownloading = true;
      _cancelled = false;
      _receivedBytes = 0;
      _totalBytes = asset.sizeBytes;
      _statusMessage = null;
      _isError = false;
    });

    File? targetFile;
    IOSink? sink;

    try {
      final cacheDir = await widget.mediaService.getUpdateCacheDir();
      if (cacheDir == null) {
        throw Exception('Could not access app cache directory.');
      }

      // Clean up older APKs before downloading the new one
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.apk')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }

      targetFile = File('$cacheDir/${asset.name}');
      sink = targetFile.openWrite();

      final client = http.Client();
      _httpClient = client;

      final request = http.Request('GET', Uri.parse(asset.downloadUrl))
        ..headers['User-Agent'] = 'LRCSync/${UpdateService.currentVersion}';

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed (HTTP ${response.statusCode}).');
      }

      final contentLength = response.contentLength ?? asset.sizeBytes;
      if (mounted) {
        setState(() => _totalBytes = contentLength);
      }

      var lastUiUpdate = DateTime.now();

      await for (final chunk in response.stream) {
        if (_cancelled) break;
        sink.add(chunk);
        _receivedBytes += chunk.length;

        final now = DateTime.now();
        if (mounted && now.difference(lastUiUpdate).inMilliseconds >= 80) {
          lastUiUpdate = now;
          setState(() {});
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      client.close();
      _httpClient = null;

      if (_cancelled) {
        if (await targetFile.exists()) await targetFile.delete();
        return;
      }

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadedFilePath = targetFile!.path;
      });

      await _triggerInstall(targetFile.path, asset.sha256);
    } catch (e) {
      await sink?.close();
      if (targetFile != null && await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      _httpClient?.close();
      _httpClient = null;

      if (!mounted || _cancelled) return;
      setState(() {
        _isDownloading = false;
        _isVerifyingAndInstalling = false;
        _isError = true;
        _statusMessage =
            'Download failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _triggerInstall(String filePath, String? expectedSha256) async {
    if (!mounted) return;
    setState(() {
      _isVerifyingAndInstalling = true;
      _statusMessage = expectedSha256 != null
          ? 'Verifying SHA-256 & launching installer...'
          : 'Launching installer...';
      _isError = false;
    });

    final result = await widget.mediaService.installApk(
      filePath: filePath,
      expectedSha256: expectedSha256,
    );

    if (!mounted) return;

    if (result.isLaunched) {
      setState(() {
        _isVerifyingAndInstalling = false;
        _statusMessage = 'Installer opened.';
      });
    } else if (result.needsPermission) {
      setState(() {
        _isVerifyingAndInstalling = false;
        _isError = false;
        _statusMessage =
            result.error ??
            'Allow installing unknown apps, then tap Install Update.';
      });
    } else {
      setState(() {
        _isVerifyingAndInstalling = false;
        _downloadedFilePath = null;
        _isError = true;
        _statusMessage = result.error ?? 'Failed to install update.';
      });
    }
  }

  void _cancelDownload() {
    setState(() {
      _cancelled = true;
      _isDownloading = false;
      _statusMessage = 'Download cancelled.';
      _isError = false;
    });
    _httpClient?.close();
    _httpClient = null;
  }

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final asset = widget.matchedApk;

    final double? progress = (_totalBytes > 0)
        ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
        : null;

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
                      'v${UpdateService.currentVersion} → v${widget.release.version}',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open on GitHub',
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                onPressed: () =>
                    widget.mediaService.openUrl(widget.release.htmlUrl),
              ),
            ],
          ),

          if (asset != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.android_rounded,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (asset.formattedSize.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      asset.formattedSize,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          if (widget.release.changelog.isNotEmpty) ...[
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
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.changelog,
                  style: textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ),
          ],

          if (_isDownloading) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 7),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _totalBytes > 0
                      ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)} MB'
                      : '${_formatMb(_receivedBytes)} MB downloaded',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (progress != null)
                  Text(
                    '${(progress * 100).round()}%',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],

          if (_statusMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _isError
                    ? scheme.errorContainer
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: _isError
                      ? scheme.onErrorContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (widget.settings != null && !_isDownloading) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                final next = !_dontShowAgain;
                setState(() => _dontShowAgain = next);
                widget.settings!.setSkippedUpdateVersion(
                  next ? widget.release.version : null,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _dontShowAgain,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        final next = val ?? false;
                        setState(() => _dontShowAgain = next);
                        widget.settings!.setSkippedUpdateVersion(
                          next ? widget.release.version : null,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Don't show again for v${widget.release.version}",
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isDownloading
                      ? _cancelDownload
                      : () => Navigator.pop(context),
                  child: Text(_isDownloading ? 'Cancel' : 'Later'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: asset != null
                    ? FilledButton.icon(
                        onPressed: (_isDownloading || _isVerifyingAndInstalling)
                            ? null
                            : _downloadAndInstall,
                        icon: (_isDownloading || _isVerifyingAndInstalling)
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Icon(
                                _downloadedFilePath != null
                                    ? Icons.install_mobile_rounded
                                    : Icons.download_rounded,
                                size: 18,
                              ),
                        label: Text(
                          _isDownloading
                              ? 'Downloading...'
                              : (_isVerifyingAndInstalling
                                    ? 'Preparing...'
                                    : (_downloadedFilePath != null
                                          ? 'Install Update'
                                          : 'Download & Install')),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.mediaService.openUrl(widget.release.htmlUrl);
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
  }
}
