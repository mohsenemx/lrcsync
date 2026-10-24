import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/settings/app_settings_controller.dart';
import '../models/lyrics_result.dart';
import '../models/parsed_lyrics.dart';
import '../models/track_info.dart';

class LyricsService {
  static const Map<String, String> _headers = {
    'User-Agent': 'LRCSync/1.2.0 (https://github.com/lrcsync/app)',
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

    // 1. Check local .lrc file first if enabled
    if (!isManualRetry && preferLocalFirst && track.expectedLrcPath != null) {
      final localFile = File(track.expectedLrcPath!);
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        if (content.trim().isNotEmpty) {
          final clean = content.trim();
          return LyricsResult(
            content: clean,
            syncType: ParsedLyrics.detectSyncType(clean),
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

    final durationSec = isManualRetry ? 0 : track.duration.inSeconds;

    // 2. Query Primary Provider
    final primaryResult = await _fetchFromProvider(
      title: effectiveTitle,
      artist: effectiveArtist,
      album: effectiveAlbum,
      durationSeconds: durationSec,
      provider: primaryProvider,
    );
    if (primaryResult != null) return primaryResult;

    // 3. Query Remaining Fallback Providers in order
    if (useFallback) {
      for (final candidate in LyricsProvider.values) {
        if (candidate == primaryProvider) continue;
        final res = await _fetchFromProvider(
          title: effectiveTitle,
          artist: effectiveArtist,
          album: effectiveAlbum,
          durationSeconds: durationSec,
          provider: candidate,
        );
        if (res != null) return res;
      }
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
      case LyricsProvider.lrcmux:
        return _fetchFromLrcMux(
          title: title,
          artist: artist,
          album: album,
          durationSeconds: durationSeconds,
        );
      case LyricsProvider.lrclib:
        return _fetchFromLrcLib(
          host: 'lrclib.net',
          sourceLabel: 'LRCLIB',
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

  /// --- LRCMUX IMPLEMENTATION (https://lrcmux.dev/docs) ---
  Future<LyricsResult?> _fetchFromLrcMux({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    final cleanArtist = artist == 'Unknown Artist' ? '' : artist;

    // 1. Try native LRCMux endpoint (/api/lyrics and /lyrics)
    for (final path in ['/api/lyrics', '/lyrics']) {
      try {
        final params = <String, String>{
          'title': title,
          'track_name': title,
          if (cleanArtist.isNotEmpty) 'artist': cleanArtist,
          if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
          if (album.isNotEmpty) 'album': album,
          if (album.isNotEmpty) 'album_name': album,
          if (durationSeconds > 0) 'duration': durationSeconds.toString(),
        };

        final uri = Uri.https('api.lrcmux.dev', path, params);
        final res = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final parsed = _parseLrcMuxPayload(utf8.decode(res.bodyBytes));
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    // 2. Try LRCMux's LRCLIB-compatible endpoints (/api/get & /api/search)
    return _fetchFromLrcLib(
      host: 'api.lrcmux.dev',
      sourceLabel: 'LRCMux',
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
  }

  LyricsResult? _parseLrcMuxPayload(String bodyText) {
    final trimmed = bodyText.trim();
    if (trimmed.isEmpty || trimmed.startsWith('<!DOCTYPE')) return null;

    // Raw LRC / Enhanced LRC response
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return LyricsResult(
        content: trimmed,
        syncType: ParsedLyrics.detectSyncType(trimmed),
        sourceName: 'LRCMux',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final sourceAttr = (decoded['source'] ?? decoded['provider'] ?? '')
            .toString()
            .trim();
        final label = sourceAttr.isNotEmpty ? 'LRCMux ($sourceAttr)' : 'LRCMux';

        // Check for direct Enhanced LRC / word-synced text fields
        for (final key in [
          'enhancedLyrics',
          'wordSyncedLyrics',
          'richsync',
          'elrc',
          'syncedLyrics',
          'lrc',
          'lyrics',
        ]) {
          final val = decoded[key];
          if (val is String && val.trim().isNotEmpty) {
            final clean = val.trim();
            return LyricsResult(
              content: clean,
              syncType: ParsedLyrics.detectSyncType(clean),
              sourceName: label,
            );
          }
        }

        // Check if structured lines/words array is returned and convert to Enhanced LRC
        final linesList = decoded['lines'] ?? decoded['subtitles'];
        if (linesList is List && linesList.isNotEmpty) {
          final converted = _convertStructuredLinesToEnhancedLrc(linesList);
          if (converted != null) {
            return LyricsResult(
              content: converted,
              syncType: ParsedLyrics.detectSyncType(converted),
              sourceName: label,
            );
          }
        }

        // Plain text fallback
        for (final key in ['plainLyrics', 'plain', 'text']) {
          final val = decoded[key];
          if (val is String && val.trim().isNotEmpty) {
            return LyricsResult(
              content: val.trim(),
              syncType: LyricsSyncType.plain,
              sourceName: label,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String? _convertStructuredLinesToEnhancedLrc(List<dynamic> lines) {
    final buffer = StringBuffer();
    for (final item in lines) {
      if (item is! Map<String, dynamic>) continue;
      final startMs = _extractMs(
        item['startTime'] ?? item['start'] ?? item['time'],
      );
      final lineTag = _formatLrcTimestamp(startMs);
      final words = item['words'] ?? item['syllables'];

      if (words is List && words.isNotEmpty) {
        buffer.write('$lineTag ');
        for (final w in words) {
          if (w is Map<String, dynamic>) {
            final wStart = _extractMs(
              w['startTime'] ?? w['start'] ?? w['time'] ?? startMs,
            );
            final wText = (w['text'] ?? w['word'] ?? '').toString();
            if (wText.isNotEmpty) {
              buffer.write('${_formatWordTimestamp(wStart)}$wText ');
            }
          }
        }
        buffer.writeln();
      } else {
        final text = (item['text'] ?? item['words'] ?? '').toString().trim();
        buffer.writeln('$lineTag $text');
      }
    }
    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : null;
  }

  int _extractMs(dynamic value) {
    if (value is int) return value;
    if (value is double) {
      // If value is in seconds (e.g. 14.52), convert to ms
      return value < 1000 ? (value * 1000).round() : value.round();
    }
    if (value is String) {
      final numVal = double.tryParse(value);
      if (numVal != null) {
        return numVal < 1000 ? (numVal * 1000).round() : numVal.round();
      }
    }
    return 0;
  }

  String _formatLrcTimestamp(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$min:$sec.$cs]';
  }

  String _formatWordTimestamp(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '<$min:$sec.$cs>';
  }

  /// --- LRCLIB / LRCMUX-COMPATIBLE IMPLEMENTATION ---
  Future<LyricsResult?> _fetchFromLrcLib({
    required String host,
    required String sourceLabel,
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    try {
      final cleanArtist = artist == 'Unknown Artist' ? '' : artist;

      if (cleanArtist.isNotEmpty && durationSeconds > 0) {
        final getUri = Uri.https(host, '/api/get', {
          'track_name': title,
          'artist_name': cleanArtist,
          if (album.isNotEmpty) 'album_name': album,
          'duration': durationSeconds.toString(),
        });
        final getRes = await http
            .get(getUri, headers: _headers)
            .timeout(const Duration(seconds: 10));

        if (getRes.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(getRes.bodyBytes)) as Map<String, dynamic>;
          final parsed = _extractLrcLibRecord(data, sourceLabel);
          if (parsed != null) return parsed;
        }
      }

      final searchParams = <String, String>{
        'track_name': title,
        if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
        if (album.isNotEmpty) 'album_name': album,
      };

      final searchUri = Uri.https(host, '/api/search', searchParams);
      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(searchRes.bodyBytes));
        final list = decoded is List ? decoded : <dynamic>[];

        // 1st priority: Word-by-word Enhanced LRC
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = _extractLrcLibRecord(item, sourceLabel);
            if (record != null && record.isWordSynced) return record;
          }
        }
        // 2nd priority: Line-synced LRC
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = _extractLrcLibRecord(item, sourceLabel);
            if (record != null && record.isSynced) return record;
          }
        }
        // 3rd priority: Plain lyrics
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = _extractLrcLibRecord(item, sourceLabel);
            if (record != null) return record;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  LyricsResult? _extractLrcLibRecord(
    Map<String, dynamic> data,
    String sourceLabel,
  ) {
    final providerTag = (data['source'] ?? data['provider'] ?? '')
        .toString()
        .trim();
    final effectiveLabel = providerTag.isNotEmpty
        ? '$sourceLabel ($providerTag)'
        : sourceLabel;

    // If record includes structured words array
    if (data['words'] is List && (data['words'] as List).isNotEmpty) {
      final converted = _convertStructuredLinesToEnhancedLrc(
        data['words'] as List,
      );
      if (converted != null) {
        return LyricsResult(
          content: converted,
          syncType: ParsedLyrics.detectSyncType(converted),
          sourceName: effectiveLabel,
        );
      }
    }

    final synced = (data['syncedLyrics'] as String?)?.trim();
    if (synced != null && synced.isNotEmpty) {
      return LyricsResult(
        content: synced,
        syncType: ParsedLyrics.detectSyncType(synced),
        sourceName: effectiveLabel,
      );
    }

    final plain = (data['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isNotEmpty) {
      return LyricsResult(
        content: plain,
        syncType: LyricsSyncType.plain,
        sourceName: effectiveLabel,
      );
    }
    return null;
  }

  /// --- LRC.RED IMPLEMENTATION ---
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
              syncType: ParsedLyrics.detectSyncType(lrcText),
              sourceName: 'lrc.red',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
