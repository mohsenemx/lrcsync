import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/now_playing/data/models/track_info.dart';
import '../../features/now_playing/data/services/native_media_service.dart';

class AlbumArtView extends StatefulWidget {
  final TrackInfo track;
  final NativeMediaService mediaService;
  final double size;
  final double borderRadius;

  const AlbumArtView({
    super.key,
    required this.track,
    required this.mediaService,
    this.size = 56,
    this.borderRadius = 14,
  });

  @override
  State<AlbumArtView> createState() => _AlbumArtViewState();
}

class _AlbumArtViewState extends State<AlbumArtView> {
  Future<Uint8List?>? _artFuture;

  @override
  void initState() {
    super.initState();
    _loadArt();
  }

  @override
  void didUpdateWidget(covariant AlbumArtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.filePath != widget.track.filePath ||
        oldWidget.track.albumId != widget.track.albumId ||
        oldWidget.track.artBytes != widget.track.artBytes) {
      _loadArt();
    }
  }

  void _loadArt() {
    if (widget.track.artBytes != null) {
      _artFuture = Future.value(widget.track.artBytes);
    } else {
      _artFuture = widget.mediaService.getAlbumArt(
        albumId: widget.track.albumId,
        filePath: widget.track.filePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<Uint8List?>(
          future: _artFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(
                bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            }
            return Container(
              color: scheme.secondaryContainer,
              child: Icon(
                Icons.album_rounded,
                size: widget.size * 0.45,
                color: scheme.onSecondaryContainer,
              ),
            );
          },
        ),
      ),
    );
  }
}
