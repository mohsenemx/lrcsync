import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/settings/app_settings_controller.dart';
import '../../../../main.dart';
import '../models/lyrics_result.dart';
import '../models/parsed_lyrics.dart';
import '../models/track_info.dart';
import 'native_media_service.dart';

class LyricsService {
  final Map<String, String> _headers = {
    'User-Agent': 'LRCSync/$appVersion (https://github.com/mohsenemx/lrcsync)',
    'Accept': 'application/json, text/plain, */*',
  };

  Future<LyricsResult?> fetchLyrics({
    required TrackInfo track,
    required List<LyricsProvider> providersInOrder,
    required bool useFallback,
    required bool preferLocalFirst,
    bool preferStandardLrc = false,
    NativeMediaService? mediaService,
    String? customTitle,
    String? customArtist,
    String? customAlbum,
  }) async {
    final isManualRetry =
        customTitle != null || customArtist != null || customAlbum != null;

    // 1A. Check local .lrc beside audio file if track is on device storage
    if (!isManualRetry && preferLocalFirst && track.expectedLrcPath != null) {
      final localFile = File(track.expectedLrcPath!);
      if (await localFile.exists()) {
        final content = (await localFile.readAsString()).trim();
        if (content.isNotEmpty) {
          return LyricsResult(
            content: content,
            syncType: ParsedLyrics.detectSyncType(content),
            sourceName: 'Local Storage',
          );
        }
      }
    }

    // 1B. Check LRCSync internal cache (for Spotify, YT Music, Telegram, etc.)
    if (!isManualRetry && preferLocalFirst && mediaService != null) {
      final cached = await mediaService.readInternalLrc(
        title: track.title,
        artist: track.artist,
        playerPackage: track.playerPackage,
      );
      if (cached != null && cached.trim().isNotEmpty) {
        final clean = cached.trim();
        return LyricsResult(
          content: clean,
          syncType: ParsedLyrics.detectSyncType(clean),
          sourceName: 'Cached',
        );
      }
    }

    final effectiveTitle = (customTitle ?? track.title).trim();
    final effectiveArtist = (customArtist ?? track.artist).trim();
    final effectiveAlbum = customAlbum != null
        ? customAlbum.trim()
        : (track.album == 'Unknown Album' ? '' : track.album.trim());

    if (effectiveTitle.isEmpty || providersInOrder.isEmpty) return null;

    final durationSec = isManualRetry ? 0 : track.duration.inSeconds;
    final chain = useFallback ? providersInOrder : [providersInOrder.first];

    // 2. Cascade through providers in the user's configured priority order
    for (final provider in chain) {
      final rawResult = await _fetchFromProvider(
        title: effectiveTitle,
        artist: effectiveArtist,
        album: effectiveAlbum,
        durationSeconds: durationSec,
        provider: provider,
      );

      if (rawResult != null) {
        final result = _normalizeResult(rawResult, preferStandardLrc);
        if (track.isStreamingOrExternal && mediaService != null) {
          await mediaService.saveLrcFile(
            targetPath: null,
            title: track.title,
            artist: track.artist,
            playerPackage: track.playerPackage,
            content: result.content,
          );
        }
        return result;
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
          basePath: '/api',
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

  Future<LyricsResult?> _fetchFromLrcMux({
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    final cleanArtist = artist == 'Unknown Artist' ? '' : artist;

    // 1. Try LRCMux KPOE v2 compatibility endpoint (/compat/kpoe/v2/lyrics/get)
    // This endpoint returns word-by-word (syllable) or line-synced JSON.
    try {
      final kpoeParams = <String, String>{
        'title': title,
        if (cleanArtist.isNotEmpty) 'artist': cleanArtist,
        if (album.isNotEmpty) 'album': album,
        if (durationSeconds > 0) 'duration': durationSeconds.toString(),
      };

      final kpoeUri = Uri.https(
        'api.lrcmux.dev',
        '/compat/kpoe/v2/lyrics/get',
        kpoeParams,
      );
      final kpoeRes = await http
          .get(kpoeUri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (kpoeRes.statusCode == 200) {
        final parsed = _parseKpoeOrMuxPayload(utf8.decode(kpoeRes.bodyBytes));
        if (parsed != null) return parsed;
      }
    } catch (_) {}

    // 2. Try LRCMux LRCLIB compatibility endpoints (/compat/lrclib/api/get & /search)
    final lrclibCompatResult = await _fetchFromLrcLib(
      host: 'api.lrcmux.dev',
      basePath: '/compat/lrclib/api',
      sourceLabel: 'LRCMux',
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
    if (lrclibCompatResult != null) return lrclibCompatResult;

    return null;
  }

  LyricsResult? _parseKpoeOrMuxPayload(String bodyText) {
    final trimmed = bodyText.trim();
    if (trimmed.isEmpty || trimmed.startsWith('<!DOCTYPE')) return null;

    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return LyricsResult(
        content: trimmed,
        syncType: ParsedLyrics.detectSyncType(trimmed),
        sourceName: 'LRCMux',
      );
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;

      final dataMap = (decoded['data'] is Map<String, dynamic>)
          ? decoded['data'] as Map<String, dynamic>
          : decoded;

      const sourceLabel = 'LRCMux';

      // A. Direct LRC / Enhanced LRC string fields
      for (final key in ['syncedLyrics', 'enhancedLyrics', 'elrc', 'lrc']) {
        final val = dataMap[key];
        if (val is String && val.trim().isNotEmpty) {
          final clean = val.trim();
          return LyricsResult(
            content: clean,
            syncType: ParsedLyrics.detectSyncType(clean),
            sourceName: sourceLabel,
          );
        }
      }

      // B. KPOE v2 structured `lyrics` list (Line or Word/Syllable synced)
      final lyricsList =
          dataMap['lyrics'] ?? dataMap['lines'] ?? dataMap['subtitles'];
      if (lyricsList is List && lyricsList.isNotEmpty) {
        final syncTypeField = (dataMap['type'] ?? '').toString().toLowerCase();
        final converted = _convertKpoeLinesToEnhancedLrc(
          lyricsList,
          syncTypeField,
        );
        if (converted != null) {
          return LyricsResult(
            content: converted,
            syncType: ParsedLyrics.detectSyncType(converted),
            sourceName: sourceLabel,
          );
        }
      }

      // C. Plain lyrics string
      for (final key in ['plainLyrics', 'plain', 'text', 'lyrics']) {
        final val = dataMap[key];
        if (val is String && val.trim().isNotEmpty) {
          final clean = val.trim();
          return LyricsResult(
            content: clean,
            syncType: ParsedLyrics.detectSyncType(clean),
            sourceName: sourceLabel,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  String? _convertKpoeLinesToEnhancedLrc(
    List<dynamic> lines,
    String declaredType,
  ) {
    final buffer = StringBuffer();
    for (final item in lines) {
      if (item is! Map<String, dynamic>) continue;
      final startMs = _extractMs(
        item['time'] ?? item['startTime'] ?? item['start'],
      );
      final lineTag = _formatLrcTimestamp(startMs);
      final syllables = item['syllabus'] ?? item['words'] ?? item['syllables'];

      if (syllables is List && syllables.isNotEmpty && declaredType != 'line') {
        buffer.write('$lineTag ');
        for (final s in syllables) {
          if (s is Map<String, dynamic>) {
            final sStart = _extractMs(
              s['time'] ?? s['startTime'] ?? s['start'] ?? startMs,
            );
            final sText = (s['text'] ?? s['word'] ?? '').toString();
            if (sText.isNotEmpty) {
              buffer.write('${_formatWordTimestamp(sStart)}$sText');
              if (!sText.endsWith(' ')) buffer.write(' ');
            }
          }
        }
        buffer.writeln();
      } else {
        final text = (item['text'] ?? '').toString().trim();
        buffer.writeln('$lineTag $text');
      }
    }
    final out = buffer.toString().trim();
    return out.isNotEmpty ? out : null;
  }

  int _extractMs(dynamic value) {
    if (value is int) return value;
    if (value is double) {
      return value < 1000 ? (value * 1000).round() : value.round();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed < 1000 ? (parsed * 1000).round() : parsed.round();
      }
    }
    return 0;
  }

  static final RegExp _inlineWordTagRegex = RegExp(
    r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>\s*',
  );

  LyricsResult _normalizeResult(LyricsResult result, bool preferStandardLrc) {
    if (!preferStandardLrc || result.syncType != LyricsSyncType.wordByWord) {
      return result;
    }
    // Strip <mm:ss.xx> word tags and collapse extra spaces per line
    final cleanedLines = result.content
        .split(RegExp(r'\r?\n'))
        .map((line) {
          return line
              .replaceAll(_inlineWordTagRegex, '')
              .replaceAll(RegExp(r' {2,}'), ' ')
              .trim();
        })
        .join('\n');

    return LyricsResult(
      content: cleanedLines,
      syncType: ParsedLyrics.detectSyncType(cleanedLines),
      sourceName: result.sourceName,
    );
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

  /// --- LRCLIB & LRCMUX (/compat/lrclib/api) IMPLEMENTATION ---
  Future<LyricsResult?> _fetchFromLrcLib({
    required String host,
    required String basePath,
    required String sourceLabel,
    required String title,
    required String artist,
    required String album,
    required int durationSeconds,
  }) async {
    try {
      final cleanArtist = artist == 'Unknown Artist' ? '' : artist;

      // Attempt 1: /get ( works with track_name & artist_name; duration/album optional on LRCMux )
      if (cleanArtist.isNotEmpty) {
        final getParams = <String, String>{
          'track_name': title,
          'artist_name': cleanArtist,
          if (album.isNotEmpty) 'album_name': album,
          if (durationSeconds > 0) 'duration': durationSeconds.toString(),
        };

        final getUri = Uri.https(host, '$basePath/get', getParams);
        final getRes = await http
            .get(getUri, headers: _headers)
            .timeout(const Duration(seconds: 12));

        if (getRes.statusCode == 200) {
          final data =
              jsonDecode(utf8.decode(getRes.bodyBytes)) as Map<String, dynamic>;
          final parsed = _extractLrcLibRecord(data, sourceLabel);
          if (parsed != null) return parsed;
        }
      }

      // Attempt 2: /search fallback
      final searchParams = <String, String>{
        'track_name': title,
        if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
        if (album.isNotEmpty) 'album_name': album,
      };

      final searchUri = Uri.https(host, '$basePath/search', searchParams);
      final searchRes = await http
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (searchRes.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(searchRes.bodyBytes));
        final list = decoded is List ? decoded : <dynamic>[];

        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = _extractLrcLibRecord(item, sourceLabel);
            if (record != null && record.isWordSynced) return record;
          }
        }
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final record = _extractLrcLibRecord(item, sourceLabel);
            if (record != null && record.isSynced) return record;
          }
        }
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
    final effectiveLabel = sourceLabel;

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
