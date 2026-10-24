import 'parsed_lyrics.dart';

class LyricsResult {
  final String content;
  final LyricsSyncType syncType;
  final String sourceName;
  final ParsedLyrics parsed;

  LyricsResult({
    required this.content,
    required this.syncType,
    required this.sourceName,
  }) : parsed = ParsedLyrics.parse(content);

  bool get isSynced => syncType != LyricsSyncType.plain;
  bool get isWordSynced => syncType == LyricsSyncType.wordByWord;
}
