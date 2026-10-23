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
