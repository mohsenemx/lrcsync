class TrackInfo {
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? filePath;
  final String? playerPackage;

  const TrackInfo({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.filePath,
    this.playerPackage,
  });

  factory TrackInfo.fromMap(Map<dynamic, dynamic> map) {
    final durationMs = (map['durationMs'] as int?) ?? 0;
    return TrackInfo(
      title: (map['title'] as String?)?.isNotEmpty == true
          ? map['title']
          : 'Unknown Title',
      artist: (map['artist'] as String?)?.isNotEmpty == true
          ? map['artist']
          : 'Unknown Artist',
      album: (map['album'] as String?)?.isNotEmpty == true
          ? map['album']
          : 'Unknown Album',
      duration: Duration(milliseconds: durationMs > 0 ? durationMs : 0),
      filePath: map['filePath'] as String?,
      playerPackage: map['playerPackage'] as String?,
    );
  }

  /// Helper to get the expected .lrc file path next to the audio file
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
