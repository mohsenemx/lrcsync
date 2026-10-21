import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/track_info.dart';
import '../../data/services/native_media_service.dart';

class NowPlayingController extends ChangeNotifier {
  final NativeMediaService _mediaService;
  StreamSubscription<TrackInfo?>? _subscription;

  TrackInfo? _currentTrack;
  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;

  NowPlayingController(this._mediaService);

  TrackInfo? get currentTrack => _currentTrack;
  bool get hasNotificationAccess => _hasNotificationAccess;
  bool get hasAudioPermission => _hasAudioPermission;

  Future<void> initialize() async {
    await checkPermissions();
    _startListening();
  }

  Future<void> checkPermissions() async {
    _hasNotificationAccess = await _mediaService.hasNotificationPermission();

    // Check Android 13+ Audio permission or legacy Storage permission
    final audioStatus = await Permission.audio.status;
    final storageStatus = await Permission.storage.status;
    _hasAudioPermission = audioStatus.isGranted || storageStatus.isGranted;

    if (_hasNotificationAccess) {
      await _mediaService.refreshTrack();
    }
    notifyListeners();
  }

  Future<void> requestAudioPermission() async {
    // Request both; Android will automatically ignore the irrelevant one based on SDK version
    await [Permission.audio, Permission.storage].request();
    await checkPermissions();
  }

  Future<void> requestNotificationAccess() async {
    await _mediaService.openNotificationSettings();
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = _mediaService.trackStream.listen((track) {
      _currentTrack = track;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
