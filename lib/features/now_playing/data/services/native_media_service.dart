import 'package:flutter/services.dart';

import '../models/track_info.dart';

class SaveLrcResult {
  final bool success;
  final String? path;
  final String? error;

  const SaveLrcResult({required this.success, this.path, this.error});
}

class NativeMediaService {
  static const _methodChannel = MethodChannel('lrcsync/media_methods');
  static const _eventChannel = EventChannel('lrcsync/media_events');

  // In-memory cover art cache keyed by albumId or filePath
  final Map<String, Uint8List?> _artCache = {};

  Stream<TrackInfo?> get trackStream {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event == null || event is! Map) return null;
      if ((event['title'] as String? ?? '').isEmpty) return null;
      return TrackInfo.fromMap(event);
    });
  }

  Future<bool> hasNotificationPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          'hasNotificationPermission',
        ) ??
        false;
  }

  Future<void> openNotificationSettings() async {
    await _methodChannel.invokeMethod('openNotificationSettings');
  }

  Future<bool> hasAudioPermission() async {
    return await _methodChannel.invokeMethod<bool>('hasAudioPermission') ??
        false;
  }

  Future<bool> requestAudioPermission() async {
    return await _methodChannel.invokeMethod<bool>('requestAudioPermission') ??
        false;
  }

  Future<void> refreshTrack() async {
    await _methodChannel.invokeMethod('refreshTrack');
  }

  Future<List<TrackInfo>> getDeviceTracks() async {
    final list = await _methodChannel.invokeMethod<List<dynamic>>(
      'getDeviceTracks',
    );
    if (list == null) return [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(TrackInfo.fromMap)
        .toList();
  }

  Future<Uint8List?> getAlbumArt({int? albumId, String? filePath}) async {
    final cacheKey = '${albumId ?? 0}_${filePath ?? ''}';
    if (_artCache.containsKey(cacheKey)) {
      return _artCache[cacheKey];
    }

    final bytes = await _methodChannel.invokeMethod<Uint8List>('getAlbumArt', {
      'albumId': albumId,
      'filePath': filePath,
    });

    if (_artCache.length > 250) {
      _artCache.remove(_artCache.keys.first);
    }
    _artCache[cacheKey] = bytes;
    return bytes;
  }

  Future<SaveLrcResult> saveLrcFile({
    required String? targetPath,
    required String title,
    required String artist,
    required String content,
  }) async {
    final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'saveLrcFile',
      {
        'targetPath': targetPath,
        'title': title,
        'artist': artist,
        'content': content,
      },
    );

    if (res == null) {
      return const SaveLrcResult(success: false, error: 'Unknown error');
    }

    return SaveLrcResult(
      success: (res['success'] as bool?) ?? false,
      path: res['path'] as String?,
      error: res['error'] as String?,
    );
  }
}
