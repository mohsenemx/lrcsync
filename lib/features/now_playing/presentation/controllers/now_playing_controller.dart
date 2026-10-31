import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../data/models/lyrics_result.dart';
import '../../data/models/parsed_lyrics.dart';
import '../../data/models/track_info.dart';
import '../../data/services/lyrics_service.dart';
import '../../data/services/native_media_service.dart';

class NowPlayingController extends ChangeNotifier {
  final NativeMediaService mediaService;
  final LyricsService lyricsService;
  StreamSubscription<TrackInfo?>? _subscription;

  TrackInfo? _currentTrack;
  bool _hasNotificationAccess = false;
  bool _hasAudioPermission = false;
  bool _hasShownInitialModal = false;

  LyricsResult? _lyricsResult;
  bool _isFetchingLyrics = false;
  String? _lyricsError;
  bool _isSavingLyrics = false;

  NowPlayingController(this.mediaService, {LyricsService? lyricsService})
    : lyricsService = lyricsService ?? LyricsService();

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
    _hasNotificationAccess = await mediaService.hasNotificationPermission();
    _hasAudioPermission = await mediaService.hasAudioPermission();

    if (_hasNotificationAccess) {
      await mediaService.refreshTrack();
    }
    notifyListeners();
  }

  Future<void> requestAudioPermission() async {
    await mediaService.requestAudioPermission();
    await checkPermissions();
  }

  Future<void> requestNotificationAccess() async {
    await mediaService.openNotificationSettings();
  }

  Future<void> fetchLyrics(
    AppSettingsController settings, {
    String? customTitle,
    String? customArtist,
    String? customAlbum,
    bool forceRemote = false,
  }) async {
    final track = _currentTrack;
    if (track == null || _isFetchingLyrics) return;

    // Bypass local/cached storage if user pressed Re-fetch or forced remote API
    final shouldCheckLocalFirst =
        !forceRemote && _lyricsResult == null && settings.preferLocalLrcFirst;

    _isFetchingLyrics = true;
    _lyricsError = null;
    notifyListeners();

    final result = await lyricsService.fetchLyrics(
      track: track,
      providersInOrder: settings.activeProvidersInOrder,
      useFallback: settings.useFallbackProvider,
      preferLocalFirst: shouldCheckLocalFirst,
      preferStandardLrc: settings.preferStandardLrcOverElrc,
      mediaService: mediaService,
      customTitle: customTitle,
      customArtist: customArtist,
      customAlbum: customAlbum,
    );

    _isFetchingLyrics = false;
    if (result != null) {
      _lyricsResult = result;
    } else {
      final queriedTitle = customTitle?.isNotEmpty == true
          ? customTitle!
          : track.title;
      _lyricsError = 'No lyrics found online for "$queriedTitle".';
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

    final result = await mediaService.saveLrcFile(
      targetPath: track.expectedLrcPath,
      title: track.title,
      artist: track.artist,
      playerPackage: track.playerPackage,
      content: lyrics.content,
    );

    _isSavingLyrics = false;
    notifyListeners();
    return result;
  }

  Future<void> seekTo(Duration position) async {
    if (_currentTrack != null) {
      // Optimistically update position & timestamp so the 60fps ticker doesn't snap back
      _currentTrack = _currentTrack!.copyWith(
        positionMs: position.inMilliseconds,
        timestampEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
    await mediaService.seekTo(position);
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack != null) {
      final nowPlaying = !_currentTrack!.isPlaying;
      final currentLiveMs = _currentTrack!.estimatedLivePosition.inMilliseconds;
      _currentTrack = _currentTrack!.copyWith(
        isPlaying: nowPlaying,
        positionMs: currentLiveMs,
        timestampEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
    await mediaService.togglePlayPause();
  }

  Future<int> clearInternalCache() async {
    return await mediaService.clearInternalLyricsCache();
  }

  Future<void> _autoLoadStoredLyricsForTrack(TrackInfo track) async {
    // 1. Check local .lrc beside audio file
    if (track.expectedLrcPath != null) {
      final file = File(track.expectedLrcPath!);
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isNotEmpty && _currentTrack?.title == track.title) {
          _lyricsResult = LyricsResult(
            content: content,
            syncType: ParsedLyrics.detectSyncType(content),
            sourceName: 'Local Storage',
          );
          notifyListeners();
          return;
        }
      }
    }

    // 2. Check LRCSync internal cache (Spotify, YouTube Music, Telegram, etc.)
    final cached = await mediaService.readInternalLrc(
      title: track.title,
      artist: track.artist,
      playerPackage: track.playerPackage,
    );
    if (cached != null &&
        cached.trim().isNotEmpty &&
        _currentTrack?.title == track.title) {
      final clean = cached.trim();
      _lyricsResult = LyricsResult(
        content: clean,
        syncType: ParsedLyrics.detectSyncType(clean),
        sourceName: 'Cached',
      );
      notifyListeners();
    }
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = mediaService.trackStream.listen((track) {
      final trackChanged =
          _currentTrack?.title != track?.title ||
          _currentTrack?.artist != track?.artist;

      _currentTrack = track;
      if (trackChanged) {
        _lyricsResult = null;
        _lyricsError = null;
        _isFetchingLyrics = false;
        if (track != null) {
          _autoLoadStoredLyricsForTrack(track);
        }
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
