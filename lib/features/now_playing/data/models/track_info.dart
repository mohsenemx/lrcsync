import 'dart:typed_data';

class TrackInfo {
  final String title;
  final String artist;
  final String album;
  final int? albumId;
  final Duration duration;
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
    this.filePath,
    this.playerPackage,
    this.artBytes,
    this.hasLocalLrc = false,
  });

  factory TrackInfo.fromMap(Map<dynamic, dynamic> map) {
    final durationMs = (map['durationMs'] as int?) ?? 0;
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
      filePath: map['filePath'] as String?,
      playerPackage: map['playerPackage'] as String?,
      artBytes: map['artBytes'] as Uint8List?,
      hasLocalLrc: (map['hasLocalLrc'] as bool?) ?? false,
    );
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
