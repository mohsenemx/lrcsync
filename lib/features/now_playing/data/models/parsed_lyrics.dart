enum LyricsSyncType {
  wordByWord,
  lineByLine,
  plain;

  String get label {
    switch (this) {
      case LyricsSyncType.wordByWord:
        return 'Word-by-Word LRC';
      case LyricsSyncType.lineByLine:
        return 'Line-Synced LRC';
      case LyricsSyncType.plain:
        return 'Plain Lyrics';
    }
  }
}

class LyricWord {
  final String text;
  final Duration startTime;
  final Duration endTime;

  const LyricWord({
    required this.text,
    required this.startTime,
    required this.endTime,
  });
}

class LyricLine {
  final Duration startTime;
  final Duration endTime;
  final String text;
  final List<LyricWord> words;

  const LyricLine({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.words = const [],
  });

  bool get hasWords => words.isNotEmpty;
}

class ParsedLyrics {
  final LyricsSyncType syncType;
  final List<LyricLine> lines;

  const ParsedLyrics({required this.syncType, required this.lines});

  static final RegExp _lineTimeRegex = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
  );
  static final RegExp _wordTimeRegex = RegExp(
    r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]*)',
  );
  static final RegExp _metadataTagRegex = RegExp(
    r'^\[(ar\vert{}ti\vert{}al\vert{}by\vert{}offset\vert{}length\vert{}re\vert{}ve):.*\]$',
    caseSensitive: false,
  );

  static LyricsSyncType detectSyncType(String raw) {
    if (_wordTimeRegex.hasMatch(raw)) {
      return LyricsSyncType.wordByWord;
    }
    if (_lineTimeRegex.hasMatch(raw)) {
      return LyricsSyncType.lineByLine;
    }
    return LyricsSyncType.plain;
  }

  factory ParsedLyrics.parse(String rawContent) {
    final rawLines = rawContent.split(RegExp(r'\r?\n'));
    final tempLines = <_TempLine>[];
    bool foundAnyWordSync = false;
    bool foundAnyLineSync = false;

    for (final rawLine in rawLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || _metadataTagRegex.hasMatch(trimmed)) continue;

      final lineMatches = _lineTimeRegex.allMatches(trimmed).toList();
      if (lineMatches.isEmpty) continue;

      foundAnyLineSync = true;
      final contentAfterLineTags = trimmed
          .substring(lineMatches.last.end)
          .trim();

      // Check for inline word timestamps: <mm:ss.xx>word
      final wordMatches = _wordTimeRegex
          .allMatches(contentAfterLineTags)
          .toList();
      final parsedWords = <_TempWord>[];

      if (wordMatches.isNotEmpty) {
        foundAnyWordSync = true;
        for (final wm in wordMatches) {
          final wordTime = _parseDuration(
            wm.group(1)!,
            wm.group(2)!,
            wm.group(3),
          );
          final wordText = wm.group(4) ?? '';
          if (wordText.trim().isNotEmpty) {
            parsedWords.add(_TempWord(text: wordText, startTime: wordTime));
          }
        }
      }

      // Clean text without <mm:ss.xx> tags
      final cleanText = contentAfterLineTags
          .replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'), '')
          .trim();

      for (final lm in lineMatches) {
        final lineTime = _parseDuration(
          lm.group(1)!,
          lm.group(2)!,
          lm.group(3),
        );
        tempLines.add(
          _TempLine(startTime: lineTime, text: cleanText, words: parsedWords),
        );
      }
    }

    // Plain unsynced lyrics fallback
    if (!foundAnyLineSync) {
      final plainLines = rawLines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map(
            (l) => LyricLine(
              startTime: Duration.zero,
              endTime: Duration.zero,
              text: l,
            ),
          )
          .toList();

      return ParsedLyrics(syncType: LyricsSyncType.plain, lines: plainLines);
    }

    tempLines.sort((a, b) => a.startTime.compareTo(b.startTime));

    final finalizedLines = <LyricLine>[];
    for (var i = 0; i < tempLines.length; i++) {
      final current = tempLines[i];
      final nextLineStart = (i + 1 < tempLines.length)
          ? tempLines[i + 1].startTime
          : current.startTime + const Duration(seconds: 5);

      final finalizedWords = <LyricWord>[];
      for (var w = 0; w < current.words.length; w++) {
        final cw = current.words[w];
        final nextWordStart = (w + 1 < current.words.length)
            ? current.words[w + 1].startTime
            : nextLineStart;
        finalizedWords.add(
          LyricWord(
            text: cw.text,
            startTime: cw.startTime,
            endTime: nextWordStart > cw.startTime
                ? nextWordStart
                : cw.startTime + const Duration(milliseconds: 350),
          ),
        );
      }

      finalizedLines.add(
        LyricLine(
          startTime: current.startTime,
          endTime: nextLineStart,
          text: current.text,
          words: finalizedWords,
        ),
      );
    }

    return ParsedLyrics(
      syncType: foundAnyWordSync
          ? LyricsSyncType.wordByWord
          : LyricsSyncType.lineByLine,
      lines: finalizedLines,
    );
  }

  static Duration _parseDuration(
    String minStr,
    String secStr,
    String? fracStr,
  ) {
    final minutes = int.tryParse(minStr) ?? 0;
    final seconds = int.tryParse(secStr) ?? 0;
    int milliseconds = 0;
    if (fracStr != null && fracStr.isNotEmpty) {
      final padded = fracStr.padRight(3, '0').substring(0, 3);
      milliseconds = int.tryParse(padded) ?? 0;
    }
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}

class _TempWord {
  final String text;
  final Duration startTime;

  const _TempWord({required this.text, required this.startTime});
}

class _TempLine {
  final Duration startTime;
  final String text;
  final List<_TempWord> words;

  const _TempLine({
    required this.startTime,
    required this.text,
    required this.words,
  });
}
