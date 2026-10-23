import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/settings/app_settings_controller.dart';
import '../models/lyrics_result.dart';
import '../models/track_info.dart';

class LyricsService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'LRCSync/1.0.0 (https://github.com/lrcsync/app; contact@lrcsync.app)',
    'Accept': 'application/json, text/plain, */*',
  };

  Future<LyricsResult?> fetchLyrics({
    required TrackInfo track,
    required LyricsProvider primaryProvider,
    required bool useFallback,
    required bool preferLocalFirst,
  }) async {
    // 1. Check local .lrc file first if enabled
    if (preferLocalFirst && track.expectedLrcPath != null) {
      final localFile = File(track.expectedLrcPath!);
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        if (content.trim().isNotEmpty) {
          return LyricsResult(
            content: content.trim(),
            isSynced: _looksLikeSyncedLrc(content),
            sourceName: 'Local Storage',
          );
        }
      }
    }

    // 2. Query Primary Provider
    final primaryResult = await _fetchFromProvider(track, primaryProvider);
    if (primaryResult != null) return primaryResult;

    // 3. Query Fallback Provider if enabled
    if (useFallback) {
      final fallbackProvider = primaryProvider == LyricsProvider.lrclib
          ? LyricsProvider.lrcRed
          : LyricsProvider.lrclib;
      return await _fetchFromProvider(track, fallbackProvider);
    }

    return null;
  }

  Future<LyricsResult?> _fetchFromProvider(
    TrackInfo track,
    LyricsProvider provider,
  ) async {
    switch (provider) {
      case LyricsProvider.lrclib:
        return _fetchFromLrcLib(track);
      case LyricsProvider.lrcRed:
        return _fetchFromLrcRed(track);
    }
  }

  /// --- LRCLIB IMPLEMENTATION ---
  Future<LyricsResult?> _fetchFromLrcLib(TrackInfo track) async {
    try {
      // Attempt 1: Exact match via /api/get
      final queryParams = <String, String>{
        'track_name': track.title,
        'artist_name': track.artist,
        if (track.album != 'Unknown Album') 'album_name': track.album,
        if (track.duration.inSeconds > 0)
          'duration': track.duration.inSeconds.toString(),
      };

      final getUri = Uri.https('lrclib.net', '/api/get', queryParams);
      final getRes = await http
          .get(getUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (getRes.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(getRes.bodyBytes)) as Map<String, dynamic>;
        final parsed = _extractLrcLibRecord(data);
        if (parsed != null) return parsed;
      }

      // Attempt 2: Fallback to /api/search if duration/album tag slightly differed
      final searchUri = Uri.https('lrclib.net', '/api/search', {
        'track_name': track.title,
        'artist_name': track.artist,
      });

      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final list =
            jsonDecode(utf8.decode(searchRes.bodyBytes)) as List<dynamic>;
        // Prefer synced lyrics first
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final synced = (item['syncedLyrics'] as String?)?.trim();
            if (synced != null && synced.isNotEmpty) {
              return LyricsResult(
                content: synced,
                isSynced: true,
                sourceName: 'LRCLIB',
              );
            }
          }
        }
        // Fallback to plain lyrics
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final parsed = _extractLrcLibRecord(item);
            if (parsed != null) return parsed;
          }
        }
      }
    } catch (_) {
      // Network or parsing error; allow fallback to continue
    }
    return null;
  }

  LyricsResult? _extractLrcLibRecord(Map<String, dynamic> data) {
    final synced = (data['syncedLyrics'] as String?)?.trim();
    if (synced != null && synced.isNotEmpty) {
      return LyricsResult(
        content: synced,
        isSynced: true,
        sourceName: 'LRCLIB',
      );
    }
    final plain = (data['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isNotEmpty) {
      return LyricsResult(
        content: plain,
        isSynced: false,
        sourceName: 'LRCLIB',
      );
    }
    return null;
  }

  /// --- LRC.RED IMPLEMENTATION ---
  Future<LyricsResult?> _fetchFromLrcRed(TrackInfo track) async {
    try {
      // Step 1: Search for track ISRC via /search.json
      final query = '${track.title} ${track.artist}'.trim();
      final searchUri = Uri.https('lrc.red', '/search.json', {'q': query});

      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (searchRes.statusCode != 200) return null;

      final body =
          jsonDecode(utf8.decode(searchRes.bodyBytes)) as Map<String, dynamic>;
      final hits = (body['hits'] as List<dynamic>?) ?? [];
      if (hits.isEmpty) return null;

      // Rank candidates by closeness to track duration (if known)
      final candidates = hits.whereType<Map<String, dynamic>>().where((h) {
        final isrc = h['isrc'] as String?;
        return isrc != null && isrc.isNotEmpty;
      }).toList();

      if (track.duration.inSeconds > 0) {
        final targetSec = track.duration.inSeconds;
        candidates.sort((a, b) {
          final durA = (a['duration'] as num?)?.toDouble() ?? 0;
          final durB = (b['duration'] as num?)?.toDouble() ?? 0;
          return (durA - targetSec).abs().compareTo((durB - targetSec).abs());
        });
      }

      // Step 2: Try fetching /s/{isrc}.lrc for the top matching candidates
      for (final candidate in candidates.take(3)) {
        final isrc = candidate['isrc'] as String;
        final lrcUri = Uri.https('lrc.red', '/s/$isrc.lrc');
        final lrcRes = await http
            .get(lrcUri, headers: _headers)
            .timeout(const Duration(seconds: 10));

        if (lrcRes.statusCode == 200) {
          final lrcText = utf8.decode(lrcRes.bodyBytes).trim();
          if (lrcText.isNotEmpty && !lrcText.startsWith('<!DOCTYPE')) {
            return LyricsResult(
              content: lrcText,
              isSynced: _looksLikeSyncedLrc(lrcText),
              sourceName: 'lrc.red',
            );
          }
        }
      }
    } catch (_) {
      // Network or parsing error
    }
    return null;
  }

  bool _looksLikeSyncedLrc(String text) {
    return RegExp(r'\[\d{2}:\d{2}(\.\d{1,3})?\]').hasMatch(text);
  }
}
