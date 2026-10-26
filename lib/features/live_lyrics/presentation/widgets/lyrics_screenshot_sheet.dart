import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/widgets/album_art_view.dart';
import '../../../now_playing/data/models/parsed_lyrics.dart';
import '../../../now_playing/data/models/track_info.dart';
import '../../../now_playing/data/services/native_media_service.dart';

class _CardPalette {
  final String name;
  final List<Color> gradientColors;
  final Color textColor;

  const _CardPalette({
    required this.name,
    required this.gradientColors,
    this.textColor = Colors.white,
  });
}

class LyricsScreenshotSheet extends StatefulWidget {
  final TrackInfo track;
  final ParsedLyrics parsedLyrics;
  final int initialActiveIndex;
  final NativeMediaService mediaService;

  const LyricsScreenshotSheet({
    super.key,
    required this.track,
    required this.parsedLyrics,
    required this.initialActiveIndex,
    required this.mediaService,
  });

  @override
  State<LyricsScreenshotSheet> createState() => _LyricsScreenshotSheetState();
}

class _LyricsScreenshotSheetState extends State<LyricsScreenshotSheet> {
  final GlobalKey _cardBoundaryKey = GlobalKey();
  late final List<GlobalKey> _lineKeys;
  late final Set<int> _selectedIndices;
  int _selectedPaletteIndex = 0;
  bool _isExporting = false;

  static const List<_CardPalette> _palettes = [
    _CardPalette(
      name: 'Velvet Crimson',
      gradientColors: [Color(0xFF9B1B30), Color(0xFF3A0CA3)],
    ),
    _CardPalette(
      name: 'Spotify Emerald',
      gradientColors: [Color(0xFF1DB954), Color(0xFF0B3B24)],
    ),
    _CardPalette(
      name: 'Midnight Indigo',
      gradientColors: [Color(0xFF1E3C72), Color(0xFF2A5298), Color(0xFF0F172A)],
    ),
    _CardPalette(
      name: 'Sunset Amber',
      gradientColors: [Color(0xFFE65100), Color(0xFF6A1B9A)],
    ),
    _CardPalette(
      name: 'Obsidian Dark',
      gradientColors: [Color(0xFF1F1F1F), Color(0xFF090909)],
    ),
    _CardPalette(
      gradientColors: [Colors.white, Colors.white70],
      textColor: Colors.black,
      name: 'Flashbang',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndices = {};
    final total = widget.parsedLyrics.lines.length;
    _lineKeys = List.generate(
      total,
      (_) => GlobalKey(),
    ); // <-- 2. Initialize keys

    final start = widget.initialActiveIndex >= 0
        ? widget.initialActiveIndex
        : 0;
    if (total > 0) {
      for (var i = start; i < (start + 3) && i < total; i++) {
        if (widget.parsedLyrics.lines[i].text.trim().isNotEmpty) {
          _selectedIndices.add(i);
        }
      }
      if (_selectedIndices.isEmpty) {
        _selectedIndices.add(0);
      }

      // <-- 3. Auto-scroll to the currently playing line when sheet opens
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetCtx = _lineKeys[start.clamp(0, total - 1)].currentContext;
        if (targetCtx != null) {
          Scrollable.ensureVisible(
            targetCtx,
            alignment: 0.15,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  void _toggleLine(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        if (_selectedIndices.length > 1) {
          _selectedIndices.remove(index);
        }
      } else {
        if (_selectedIndices.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Maximum 5 lines can be selected for a card.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedIndices.add(index);
      }
    });
  }

  Future<void> _captureAndExport({required bool share}) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final boundary =
          _cardBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final cleanTitle = widget.track.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
          .take(30);
      final fileName =
          'LRCSync_${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.png';

      final res = await widget.mediaService.saveLyricsScreenshot(
        bytes: pngBytes,
        fileName: fileName,
        share: share,
      );

      if (!mounted) return;
      setState(() => _isExporting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            res.success
                ? 'Saved lyrics card to ${res.path}'
                : (res.error ?? 'Could not save lyrics card'),
          ),
        ),
      );

      if (res.success && !share) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final palette = _palettes[_selectedPaletteIndex];

    final sortedSelected = _selectedIndices.toList()..sort();
    final selectedLines = sortedSelected
        .map((i) => widget.parsedLyrics.lines[i].text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Sheet Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share Lyrics Card',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Select up to 5 lines (${_selectedIndices.length}/5 selected)',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  // --- LIVE SPOTIFY-STYLE CARD PREVIEW (Captured via RepaintBoundary) ---
                  RepaintBoundary(
                    key: _cardBoundaryKey,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: palette.gradientColors,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Track Header inside Screenshot Card
                          Row(
                            children: [
                              AlbumArtView(
                                track: widget.track,
                                mediaService: widget.mediaService,
                                size: 52,
                                borderRadius: 12,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(
                                        color: palette.textColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: palette.textColor.withValues(
                                          alpha: 0.78,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Selected Lyrics Lines
                          ...selectedLines.map(
                            (lineText) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                lineText,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: palette.textColor,
                                  fontWeight: FontWeight.w800,
                                  height: 1.28,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Subtle Spotify-style Footer Branding
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 16,
                                    color: palette.textColor.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'LRCSync',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: palette.textColor.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                widget.track.sourceAppName,
                                style: textTheme.labelSmall?.copyWith(
                                  color: palette.textColor.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- COLOR PALETTE PICKER ---
                  Text('Card Style', style: textTheme.titleSmall),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _palettes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final p = _palettes[index];
                        final isSelected = index == _selectedPaletteIndex;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedPaletteIndex = index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: p.gradientColors,
                              ),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              p.name,
                              style: textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- TAP LINES TO INCLUDE ---
                  Text(
                    'Tap Lyrics Lines to Include',
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(
                          widget.parsedLyrics.lines.length,
                          (index) {
                            final line = widget.parsedLyrics.lines[index].text
                                .trim();
                            if (line.isEmpty)
                              return SizedBox.shrink(key: _lineKeys[index]);
                            final isSelected = _selectedIndices.contains(index);

                            return Padding(
                              key: _lineKeys[index], // <-- Attach key here
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _toggleLine(index),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? scheme.primaryContainer
                                        : scheme.surfaceContainerHighest
                                              .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons
                                                  .radio_button_unchecked_rounded,
                                        size: 20,
                                        color: isSelected
                                            ? scheme.onPrimaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          line,
                                          style: textTheme.bodyMedium?.copyWith(
                                            color: isSelected
                                                ? scheme.onPrimaryContainer
                                                : scheme.onSurface,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Save & Share Action Bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _isExporting
                            ? null
                            : () => _captureAndExport(share: false),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Save to Gallery',
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _isExporting
                            ? null
                            : () => _captureAndExport(share: true),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Share Card',
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
