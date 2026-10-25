import 'package:flutter/foundation.dart';

import '../../../../core/settings/app_settings_controller.dart';
import '../../../now_playing/data/models/track_info.dart';
import '../../../now_playing/data/services/lyrics_service.dart';
import '../../../now_playing/data/services/native_media_service.dart';

class LibraryController extends ChangeNotifier {
  final NativeMediaService mediaService;

  List<TrackInfo> _allTracks = [];
  String _searchQuery = '';
  bool _isLoading = false;

  // Batch Download State
  bool _isBatchRunning = false;
  bool _cancelBatchRequested = false;
  bool _skipExistingLrc = true;
  int _delayMilliseconds = 2000; // Default 2.0s delay to avoid rate limits

  int _batchTotal = 0;
  int _batchProcessed = 0;
  int _batchSucceeded = 0;
  int _batchFailed = 0;
  int _batchSkipped = 0;
  String? _currentBatchTrackTitle;

  LibraryController(this.mediaService);

  List<TrackInfo> get allTracks => _allTracks;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  bool get isBatchRunning => _isBatchRunning;
  bool get skipExistingLrc => _skipExistingLrc;
  int get delayMilliseconds => _delayMilliseconds;
  int get batchTotal => _batchTotal;
  int get batchProcessed => _batchProcessed;
  int get batchSucceeded => _batchSucceeded;
  int get batchFailed => _batchFailed;
  int get batchSkipped => _batchSkipped;
  String? get currentBatchTrackTitle => _currentBatchTrackTitle;

  List<TrackInfo> get filteredTracks {
    if (_searchQuery.trim().isEmpty) return _allTracks;
    final q = _searchQuery.toLowerCase();
    return _allTracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q);
    }).toList();
  }

  void setSkipExistingLrc(bool value) {
    if (_isBatchRunning) return;
    _skipExistingLrc = value;
    notifyListeners();
  }

  void setDelayMilliseconds(int ms) {
    if (_isBatchRunning) return;
    _delayMilliseconds = ms;
    notifyListeners();
  }

  Future<void> loadTracks() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    _allTracks = await mediaService.getDeviceTracks();
    _isLoading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void markTrackHasLrc(String? filePath, {String lrcType = 'LRC'}) {
    if (filePath == null) return;
    final index = _allTracks.indexWhere((t) => t.filePath == filePath);
    if (index != -1) {
      _allTracks[index] = _allTracks[index].copyWith(
        hasLocalLrc: true,
        localLrcType: lrcType,
      );
      notifyListeners();
    }
  }

  Future<void> startBatchDownload({
    required LyricsService lyricsService,
    required AppSettingsController settings,
  }) async {
    if (_isBatchRunning || _allTracks.isEmpty) return;

    _isBatchRunning = true;
    _cancelBatchRequested = false;
    _batchTotal = _allTracks.length;
    _batchProcessed = 0;
    _batchSucceeded = 0;
    _batchFailed = 0;
    _batchSkipped = 0;
    _currentBatchTrackTitle = null;
    notifyListeners();

    final tracksSnapshot = List<TrackInfo>.from(_allTracks);

    for (var i = 0; i < tracksSnapshot.length; i++) {
      if (_cancelBatchRequested) break;

      final track = tracksSnapshot[i];
      _currentBatchTrackTitle = '${track.artist} -${track.title}';
      notifyListeners();

      // Skip songs that already have a local .lrc file if option is enabled
      if (_skipExistingLrc && track.hasLocalLrc) {
        _batchSkipped++;
        _batchProcessed++;
        notifyListeners();
        continue;
      }

      // Fetch lyrics online
      final result = await lyricsService.fetchLyrics(
        track: track,
        providersInOrder: settings.activeProvidersInOrder,
        useFallback: settings.useFallbackProvider,
        preferLocalFirst: false,
        mediaService: mediaService,
      );

      if (_cancelBatchRequested) break;

      if (result != null) {
        final saveRes = await mediaService.saveLrcFile(
          targetPath: track.expectedLrcPath,
          title: track.title,
          artist: track.artist,
          content: result.content,
        );

        if (saveRes.success) {
          _batchSucceeded++;
          final badgeType = result.isWordSynced
              ? 'eLRC'
              : (result.isSynced ? 'LRC' : 'Plain');
          markTrackHasLrc(track.filePath, lrcType: badgeType);
        } else {
          _batchFailed++;
        }
      } else {
        _batchFailed++;
      }

      _batchProcessed++;
      notifyListeners();

      // Rate-limit protection delay before the next network call
      if (i < tracksSnapshot.length - 1 && !_cancelBatchRequested) {
        await Future.delayed(Duration(milliseconds: _delayMilliseconds));
      }
    }

    _isBatchRunning = false;
    _currentBatchTrackTitle = null;
    notifyListeners();
  }

  void cancelBatchDownload() {
    if (_isBatchRunning) {
      _cancelBatchRequested = true;
      notifyListeners();
    }
  }
}
