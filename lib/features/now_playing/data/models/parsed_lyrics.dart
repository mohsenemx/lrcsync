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
  final bool isInstrumental;

  const LyricLine({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.words = const [],
    this.isInstrumental = false,
  });

  bool get hasWords => words.isNotEmpty;
}

class ParsedLyrics {
  final LyricsSyncType syncType;
  final List<LyricLine> lines;

  const ParsedLyrics({required this.syncType, required this.lines});

  static const Duration _instrumentalGapThreshold = Duration(seconds: 5);

  static final RegExp _lineTimeRegex = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[.:](\d+))?\]',
  );
  static final RegExp _leadingLineTagsRegex = RegExp(
    r'^(?:\s*\[\d{1,3}:\d{2}(?:[.:]\d+)?\])+',
  );
  static final RegExp _inlineWordTagRegex = RegExp(
    r'[<\[]((\d{1,3}):(\d{2})(?:[.:](\d+))?)[>\]]',
  );
  static final RegExp _wordDetectRegex = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d+)?>');
  static final RegExp _metadataTagRegex = RegExp(
    r'^\[(ar|ti|al|by|offset|length|re|ve):.*\]$',
    caseSensitive: false,
  );
  static final RegExp _offsetTagRegex = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]$',
    caseSensitive: false,
  );

  static LyricsSyncType detectSyncType(String raw) {
    if (_wordDetectRegex.hasMatch(raw)) {
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
    int offsetMs = 0;

    for (final rawLine in rawLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final offsetMatch = _offsetTagRegex.firstMatch(trimmed);
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }

      if (_metadataTagRegex.hasMatch(trimmed)) continue;

      final leadingMatch = _leadingLineTagsRegex.firstMatch(trimmed);
      if (leadingMatch == null) continue;

      final leadingTagBlock = leadingMatch.group(0)!;
      final lineMatches = _lineTimeRegex.allMatches(leadingTagBlock).toList();
      if (lineMatches.isEmpty) continue;

      foundAnyLineSync = true;
      final contentAfterLineTags = trimmed.substring(leadingMatch.end).trim();

      final lineTimes = lineMatches
          .map(
            (lm) => _applyOffset(
              _parseDuration(lm.group(1)!, lm.group(2)!, lm.group(3)),
              offsetMs,
            ),
          )
          .toList();

      final firstLineTime = lineTimes.first;
      final inlineMatches = _inlineWordTagRegex
          .allMatches(contentAfterLineTags)
          .toList();
      final parsedWords = <_TempWord>[];

      if (inlineMatches.isNotEmpty) {
        foundAnyWordSync = true;

        // Capture untagged leading text before the first <...> tag
        final leadingText = contentAfterLineTags.substring(
          0,
          inlineMatches.first.start,
        );
        if (leadingText.trim().isNotEmpty) {
          final firstTagTime = _applyOffset(
            _parseDuration(
              inlineMatches.first.group(2)!,
              inlineMatches.first.group(3)!,
              inlineMatches.first.group(4),
            ),
            offsetMs,
          );
          final firstTagTextEnd = inlineMatches.length > 1
              ? inlineMatches[1].start
              : contentAfterLineTags.length;
          final firstTagIsClosing = contentAfterLineTags
              .substring(inlineMatches.first.end, firstTagTextEnd)
              .trim()
              .isEmpty;

          parsedWords.add(
            _TempWord(
              text: leadingText,
              startTime: firstLineTime,
              closingTagTime:
                  (firstTagIsClosing && firstTagTime > firstLineTime)
                  ? firstTagTime
                  : null,
            ),
          );
        }

        // Process inline tags, distinguishing real empty closing tags from next-word tags
        for (var m = 0; m < inlineMatches.length; m++) {
          final currentMatch = inlineMatches[m];
          final wordStart = _applyOffset(
            _parseDuration(
              currentMatch.group(2)!,
              currentMatch.group(3)!,
              currentMatch.group(4),
            ),
            offsetMs,
          );

          final textStart = currentMatch.end;
          final textEnd = (m + 1 < inlineMatches.length)
              ? inlineMatches[m + 1].start
              : contentAfterLineTags.length;
          final wordText = contentAfterLineTags.substring(textStart, textEnd);

          if (wordText.trim().isEmpty) continue;

          Duration? closingTagTime;
          if (m + 1 < inlineMatches.length) {
            final nextMatch = inlineMatches[m + 1];
            final nextTextEnd = (m + 2 < inlineMatches.length)
                ? inlineMatches[m + 2].start
                : contentAfterLineTags.length;
            final nextTagIsClosing = contentAfterLineTags
                .substring(nextMatch.end, nextTextEnd)
                .trim()
                .isEmpty;

            if (nextTagIsClosing) {
              final nextTime = _applyOffset(
                _parseDuration(
                  nextMatch.group(2)!,
                  nextMatch.group(3)!,
                  nextMatch.group(4),
                ),
                offsetMs,
              );
              if (nextTime > wordStart) {
                closingTagTime = nextTime;
              }
            }
          }

          parsedWords.add(
            _TempWord(
              text: wordText,
              startTime: wordStart,
              closingTagTime: closingTagTime,
            ),
          );
        }
      }

      final cleanText = contentAfterLineTags
          .replaceAll(_inlineWordTagRegex, '')
          .replaceAll(RegExp(r' {2,}'), ' ')
          .trim();

      for (final lineTime in lineTimes) {
        final shift = lineTime - firstLineTime;
        final shiftedWords = shift == Duration.zero
            ? parsedWords
            : parsedWords
                  .map(
                    (w) => _TempWord(
                      text: w.text,
                      startTime: _clampZero(w.startTime + shift),
                      closingTagTime: w.closingTagTime != null
                          ? _clampZero(w.closingTagTime! + shift)
                          : null,
                    ),
                  )
                  .toList();

        tempLines.add(
          _TempLine(startTime: lineTime, text: cleanText, words: shiftedWords),
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

    // Add leading "..." if the intro before the first lyric is 5+ seconds
    if (tempLines.isNotEmpty &&
        tempLines.first.text.isNotEmpty &&
        tempLines.first.startTime >= _instrumentalGapThreshold) {
      finalizedLines.add(
        LyricLine(
          startTime: Duration.zero,
          endTime: tempLines.first.startTime,
          text: '...',
          isInstrumental: true,
        ),
      );
    }

    for (var i = 0; i < tempLines.length; i++) {
      final current = tempLines[i];
      final nextLineStart = (i + 1 < tempLines.length)
          ? tempLines[i + 1].startTime
          : current.startTime + const Duration(seconds: 5);

      // Convert existing blank timestamp lines in the LRC into "..." markers
      if (current.text.isEmpty) {
        if (finalizedLines.isEmpty || !finalizedLines.last.isInstrumental) {
          finalizedLines.add(
            LyricLine(
              startTime: current.startTime,
              endTime: nextLineStart,
              text: '...',
              isInstrumental: true,
            ),
          );
        }
        continue;
      }

      final sortedWords = List<_TempWord>.from(current.words)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final finalizedWords = <LyricWord>[];
      for (var w = 0; w < sortedWords.length; w++) {
        final cw = sortedWords[w];
        final isLastWord = w == sortedWords.length - 1;
        final upperBound = isLastWord
            ? nextLineStart
            : sortedWords[w + 1].startTime;

        // Natural max sweep duration when no explicit closing tag is present
        final naturalMaxMs = (cw.text.trim().length * 160).clamp(650, 2400);
        final naturalCapEnd =
            cw.startTime + Duration(milliseconds: naturalMaxMs);

        Duration endTime;
        if (cw.closingTagTime != null && cw.closingTagTime! > cw.startTime) {
          // Trust explicit empty closing tags (capped at 6s against corrupt data)
          final maxExplicitEnd = cw.startTime + const Duration(seconds: 6);
          endTime = cw.closingTagTime! < maxExplicitEnd
              ? cw.closingTagTime!
              : maxExplicitEnd;
          if (!isLastWord &&
              upperBound > cw.startTime &&
              endTime > upperBound) {
            endTime = upperBound;
          }
        } else if (upperBound > cw.startTime) {
          // Cap mid-line and end-of-line pauses so words never hang mid-sweep
          endTime = upperBound < naturalCapEnd ? upperBound : naturalCapEnd;
        } else {
          // Fallback for duplicate/inverted timestamps
          endTime = cw.startTime + const Duration(milliseconds: 350);
        }

        finalizedWords.add(
          LyricWord(text: cw.text, startTime: cw.startTime, endTime: endTime),
        );
      }

      // Estimate when singing actually finishes on this line
      final Duration singingEndTime;
      if (finalizedWords.isNotEmpty) {
        singingEndTime = finalizedWords.last.endTime;
      } else {
        final estMs = (current.text.length * 65).clamp(1500, 4500);
        final estEnd = current.startTime + Duration(milliseconds: estMs);
        singingEndTime = estEnd < nextLineStart ? estEnd : nextLineStart;
      }

      // Check if there is a 5+ second gap before the next non-empty line
      final bool hasNextLine = i + 1 < tempLines.length;
      final bool nextIsAlreadyEmpty =
          hasNextLine && tempLines[i + 1].text.isEmpty;
      final gap = nextLineStart - singingEndTime;
      final shouldInsertBreak =
          hasNextLine &&
          !nextIsAlreadyEmpty &&
          gap >= _instrumentalGapThreshold;

      final breakStart = singingEndTime + const Duration(milliseconds: 400);

      finalizedLines.add(
        LyricLine(
          startTime: current.startTime,
          endTime: shouldInsertBreak ? breakStart : nextLineStart,
          text: current.text,
          words: finalizedWords,
        ),
      );

      if (shouldInsertBreak && breakStart < nextLineStart) {
        finalizedLines.add(
          LyricLine(
            startTime: breakStart,
            endTime: nextLineStart,
            text: '...',
            isInstrumental: true,
          ),
        );
      }
    }

    return ParsedLyrics(
      syncType: foundAnyWordSync
          ? LyricsSyncType.wordByWord
          : LyricsSyncType.lineByLine,
      lines: finalizedLines,
    );
  }

  static Duration _applyOffset(Duration d, int offsetMs) {
    if (offsetMs == 0) return d;
    return _clampZero(d - Duration(milliseconds: offsetMs));
  }

  static Duration _clampZero(Duration d) => d.isNegative ? Duration.zero : d;

  static Duration _parseDuration(
    String minStr,
    String secStr,
    String? fracStr,
  ) {
    final minutes = int.tryParse(minStr) ?? 0;
    final seconds = int.tryParse(secStr) ?? 0;
    int milliseconds = 0;
    if (fracStr != null && fracStr.isNotEmpty) {
      final normalized = fracStr.padRight(3, '0').substring(0, 3);
      milliseconds = int.tryParse(normalized) ?? 0;
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
  final Duration? closingTagTime;

  const _TempWord({
    required this.text,
    required this.startTime,
    this.closingTagTime,
  });
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
