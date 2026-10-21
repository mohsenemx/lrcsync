import 'package:flutter/services.dart';

import '../models/track_info.dart';

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

  Future<void> refreshTrack() async {
    await _methodChannel.invokeMethod('refreshTrack');
  }
}
