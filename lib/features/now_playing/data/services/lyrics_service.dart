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
    String? customTitle,
    String? customArtist,
    String? customAlbum,
  }) async {
    final isManualRetry =
        customTitle != null || customArtist != null || customAlbum != null;

    // 1. Check local .lrc file first (only on initial fetch, not manual retry)
    if (!isManualRetry && preferLocalFirst && track.expectedLrcPath != null) {
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

    final effectiveTitle = (customTitle ?? track.title).trim();
    final effectiveArtist = (customArtist ?? track.artist).trim();
    final effectiveAlbum = customAlbum != null
        ? customAlbum.trim()
        : (track.album == 'Unknown Album' ? '' : track.album.trim());

    if (effectiveTitle.isEmpty) return null;

    // 2. Query Primary Provider
    final primaryResult = await _fetchFromProvider(
      title: effectiveTitle,
      artist: effectiveArtist,
      album: effectiveAlbum,
      durationSeconds: isManualRetry ? 0 : track.duration.inSeconds,
      provider: primaryProvider,
    );
    if (primaryResult != null) return primaryResult;

    // 3. Query Fallback Provider if enabled
    if (useFallback) {
      final fallbackProvider = primaryProvider == LyricsProvider.lrclib
          ? LyricsProvider.lrcRed
          : LyricsProvider.lrclib;
      return await _fetchFromProvider(
        title: effectiveTitle,
        artist: effectiveArtist,
        album: effectiveAlbum,
        durationSeconds: isManualRetry ? 0 : track.duration.inSeconds,
        provider: fallbackProvider,
      );
    }

    return null;
  }

  Future<LyricsResult?> _fetchFromProvider({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
    required LyricsProvider provider,
  }) async {
    switch (provider) {
      case LyricsProvider.lrclib:
        return _fetchFromLrcLib(
          title: title,
          artist: artist,
          album: album,
          durationSeconds: durationSeconds,
        );
      case LyricsProvider.lrcRed:
        return _fetchFromLrcRed(
          title: title,
          artist: artist,
          album: album,
          durationSeconds: durationSeconds,
        );
    }
  }

  Future<LyricsResult?> _fetchFromLrcLib({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    try {
      // Attempt 1: /api/get when album and duration are both known
      if (album.isNotEmpty && durationSeconds > 0) {
        final getUri = Uri.https('lrclib.net', '/api/get', {
          'track_name': title,
          'artist_name': artist,
          'album_name': album,
          'duration': durationSeconds.toString(),
        });
        final getRes = await http
            .get(getUri, headers: _headers)
            .timeout(const Duration(seconds: 10));

        if (getRes.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(getRes.bodyBytes)) as Map<String, dynamic>;
          final parsed = _extractLrcLibRecord(data);
          if (parsed != null) return parsed;
        }
      }

      // Attempt 2: /api/search (works with or without album)
      final searchParams = <String, String>{
        'track_name': title,
        if (artist.isNotEmpty && artist != 'Unknown Artist')
          'artist_name': artist,
        if (album.isNotEmpty) 'album_name': album,
      };

      final searchUri = Uri.https('lrclib.net', '/api/search', searchParams);
      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final list =
            jsonDecode(utf8.decode(searchRes.bodyBytes)) as List<dynamic>;
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
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final parsed = _extractLrcLibRecord(item);
            if (parsed != null) return parsed;
          }
        }
      }
    } catch (_) {}
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

  Future<LyricsResult?> _fetchFromLrcRed({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    try {
      final cleanArtist = artist == 'Unknown Artist' ? '' : artist;
      final query = [
        title,
        cleanArtist,
        album,
      ].where((s) => s.isNotEmpty).join(' ').trim();

      final searchUri = Uri.https('lrc.red', '/search.json', {'q': query});
      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (searchRes.statusCode != 200) return null;

      final body =
          jsonDecode(utf8.decode(searchRes.bodyBytes)) as Map<String, dynamic>;
      final hits = (body['hits'] as List<dynamic>?) ?? [];
      if (hits.isEmpty) return null;

      final candidates = hits.whereType<Map<String, dynamic>>().where((h) {
        final isrc = h['isrc'] as String?;
        return isrc != null && isrc.isNotEmpty;
      }).toList();

      if (durationSeconds > 0) {
        candidates.sort((a, b) {
          final durA = (a['duration'] as num?)?.toDouble() ?? 0;
          final durB = (b['duration'] as num?)?.toDouble() ?? 0;
          return (durA - durationSeconds).abs().compareTo(
            (durB - durationSeconds).abs(),
          );
        });
      }

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
    } catch (_) {}
    return null;
  }

  bool _looksLikeSyncedLrc(String text) {
    return RegExp(r'\[\d{2}:\d{2}(\.\d{1,3})?\]').hasMatch(text);
  }
}
