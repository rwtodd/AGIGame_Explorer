import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/ui/core/theme.dart';

/// Renders a crisp retro screen thumbnail for an [AgiGameStateSnapshot].
///
/// Converts the snapshot's 80x84 32-bit RGBA pixel array to an aspect-corrected (4:3)
/// hardware texture with pixelated nearest-neighbor filtering.
class SnapshotThumbnailWidget extends StatefulWidget {
  final Uint8List? thumbnailRgba;
  final double width;
  final double height;
  final int sourceWidth;
  final int sourceHeight;
  final bool showBorder;
  final Color? borderColor;

  const SnapshotThumbnailWidget({
    super.key,
    required this.thumbnailRgba,
    this.width = 80,
    this.height = 60,
    this.sourceWidth = 80,
    this.sourceHeight = 84,
    this.showBorder = true,
    this.borderColor,
  });

  @override
  State<SnapshotThumbnailWidget> createState() => _SnapshotThumbnailWidgetState();
}

class _SnapshotThumbnailWidgetState extends State<SnapshotThumbnailWidget> {
  ui.Image? _cachedImage;
  bool _isDecoding = false;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant SnapshotThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailRgba != widget.thumbnailRgba) {
      _cachedImage?.dispose();
      _cachedImage = null;
      _decodeImage();
    }
  }

  @override
  void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
    super.dispose();
  }

  void _decodeImage() {
    final rgba = widget.thumbnailRgba;
    if (rgba == null || rgba.isEmpty || _isDecoding) return;

    _isDecoding = true;
    ui.decodeImageFromPixels(
      rgba,
      widget.sourceWidth,
      widget.sourceHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) {
          setState(() {
            _cachedImage = image;
            _isDecoding = false;
          });
        } else {
          image.dispose();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderCol = widget.borderColor ?? AgiTheme.egaBorder;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black,
        border: widget.showBorder ? Border.all(color: borderCol, width: 1.2) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_cachedImage != null) {
      return RawImage(
        image: _cachedImage,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none, // Crisp authentic pixels
      );
    }

    return Center(
      child: Icon(
        Icons.videogame_asset_outlined,
        size: widget.width * 0.35,
        color: AgiTheme.egaMuted.withValues(alpha: 0.5),
      ),
    );
  }
}
