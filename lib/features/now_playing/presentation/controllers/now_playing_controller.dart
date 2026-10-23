import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../data/models/lyrics_result.dart';
import '../../data/models/track_info.dart';
import '../../data/services/lyrics_service.dart';
import '../../data/services/native_media_service.dart';

class NowPlayingController extends ChangeNotifier {
  final NativeMediaService _mediaService;
  final LyricsService _lyricsService;
  StreamSubscription<TrackInfo?>? _subscription;

  TrackInfo? _currentTrack;
  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;
  bool _hasShownInitialModal = false;

  LyricsResult? _lyricsResult;
  bool _isFetchingLyrics = false;
  String? _lyricsError;
  bool _isSavingLyrics = false;

  NowPlayingController(this._mediaService, {LyricsService? lyricsService})
    : _lyricsService = lyricsService ?? LyricsService();

  TrackInfo? get currentTrack => _currentTrack;
  bool get hasNotificationAccess => _hasNotificationAccess;
  bool get hasAudioPermission => _hasAudioPermission;
  bool get hasAllPermissions => _hasNotificationAccess && _hasAudioPermission;
  bool get hasShownInitialModal => _hasShownInitialModal;

  LyricsResult? get lyricsResult => _lyricsResult;
  bool get isFetchingLyrics => _isFetchingLyrics;
  String? get lyricsError => _lyricsError;
  bool get isSavingLyrics => _isSavingLyrics;

  void markInitialModalShown() {
    _hasShownInitialModal = true;
  }

  Future<void> initialize() async {
    await checkPermissions();
    _startListening();
  }

  Future<void> checkPermissions() async {
    _hasNotificationAccess = await _mediaService.hasNotificationPermission();
    _hasAudioPermission = await _mediaService.hasAudioPermission();

    if (_hasNotificationAccess) {
      await _mediaService.refreshTrack();
    }
    notifyListeners();
  }

  Future<void> requestAudioPermission() async {
    await _mediaService.requestAudioPermission();
    await checkPermissions();
  }

  Future<void> requestNotificationAccess() async {
    await _mediaService.openNotificationSettings();
  }

  Future<void> fetchLyrics(AppSettingsController settings) async {
    final track = _currentTrack;
    if (track == null || _isFetchingLyrics) return;

    _isFetchingLyrics = true;
    _lyricsError = null;
    notifyListeners();

    final result = await _lyricsService.fetchLyrics(
      track: track,
      primaryProvider: settings.primaryProvider,
      useFallback: settings.useFallbackProvider,
      preferLocalFirst: settings.preferLocalLrcFirst,
    );

    _isFetchingLyrics = false;
    if (result != null) {
      _lyricsResult = result;
    } else {
      _lyricsError = 'No lyrics found for "${track.title}".';
    }
    notifyListeners();
  }

  Future<SaveLrcResult> saveLyricsToStorage() async {
    final track = _currentTrack;
    final lyrics = _lyricsResult;
    if (track == null || lyrics == null || _isSavingLyrics) {
      return const SaveLrcResult(success: false, error: 'Nothing to save');
    }

    _isSavingLyrics = true;
    notifyListeners();

    final result = await _mediaService.saveLrcFile(
      targetPath: track.expectedLrcPath,
      title: track.title,
      artist: track.artist,
      content: lyrics.content,
    );

    _isSavingLyrics = false;
    notifyListeners();
    return result;
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = _mediaService.trackStream.listen((track) {
      final trackChanged =
          _currentTrack?.title != track?.title ||
          _currentTrack?.artist != track?.artist;

      _currentTrack = track;
      if (trackChanged) {
        _lyricsResult = null;
        _lyricsError = null;
        _isFetchingLyrics = false;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
