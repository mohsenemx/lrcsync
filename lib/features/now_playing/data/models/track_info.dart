import 'dart:typed_data';

class TrackInfo {
  final String title;
  final String artist;
  final String album;
  final int? albumId;
  final Duration duration;
  final int positionMs;
  final bool isPlaying;
  final double playbackSpeed;
  final int timestampEpochMs;
  final String? filePath;
  final String? playerPackage;
  final Uint8List? artBytes;
  final bool hasLocalLrc;

  const TrackInfo({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumId,
    this.positionMs = 0,
    this.isPlaying = false,
    this.playbackSpeed = 1.0,
    this.timestampEpochMs = 0,
    this.filePath,
    this.playerPackage,
    this.artBytes,
    this.hasLocalLrc = false,
  });

  factory TrackInfo.fromMap(Map<dynamic, dynamic> map) {
    final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
    final rawArtist = (map['artist'] as String?)?.trim() ?? '';
    final rawAlbum = (map['album'] as String?)?.trim() ?? '';

    return TrackInfo(
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : 'Unknown Title',
      artist: rawArtist.isNotEmpty && rawArtist != '<unknown>'
          ? rawArtist
          : 'Unknown Artist',
      album: rawAlbum.isNotEmpty && rawAlbum != '<unknown>'
          ? rawAlbum
          : 'Unknown Album',
      albumId: (map['albumId'] as num?)?.toInt(),
      duration: Duration(milliseconds: durationMs > 0 ? durationMs : 0),
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      isPlaying: (map['isPlaying'] as bool?) ?? false,
      playbackSpeed: (map['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      timestampEpochMs:
          (map['timestampEpochMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      filePath: map['filePath'] as String?,
      playerPackage: map['playerPackage'] as String?,
      artBytes: map['artBytes'] as Uint8List?,
      hasLocalLrc: (map['hasLocalLrc'] as bool?) ?? false,
    );
  }

  /// Calculates the exact live playback position right now
  Duration get estimatedLivePosition {
    if (!isPlaying || timestampEpochMs <= 0) {
      return Duration(
        milliseconds: positionMs.clamp(
          0,
          duration.inMilliseconds > 0 ? duration.inMilliseconds : 86400000,
        ),
      );
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - timestampEpochMs;
    final extrapolated = positionMs + (elapsed * playbackSpeed).round();
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : 86400000;
    return Duration(milliseconds: extrapolated.clamp(0, maxMs));
  }

  TrackInfo copyWith({
    String? title,
    String? artist,
    String? album,
    bool? hasLocalLrc,
  }) {
    return TrackInfo(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId,
      duration: duration,
      positionMs: positionMs,
      isPlaying: isPlaying,
      playbackSpeed: playbackSpeed,
      timestampEpochMs: timestampEpochMs,
      filePath: filePath,
      playerPackage: playerPackage,
      artBytes: artBytes,
      hasLocalLrc: hasLocalLrc ?? this.hasLocalLrc,
    );
  }

  String? get expectedLrcPath {
    if (filePath == null) return null;
    final lastDot = filePath!.lastIndexOf('.');
    if (lastDot == -1) return '${filePath!}.lrc';
    return '${filePath!.substring(0, lastDot)}.lrc';
  }

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
