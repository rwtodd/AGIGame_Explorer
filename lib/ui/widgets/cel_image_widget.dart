import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/domain/agi_view.dart';

/// Widget that displays an individual sprite cel from an [AgiView] resource.
///
/// Features:
/// - Converts cel to RGBA bitmap with authentic 2:1 horizontal pixel aspect ratio.
/// - Renders using nearest-neighbor point sampling (`FilterQuality.none`) for razor-sharp EGA pixels.
/// - Completely eliminates subpixel seams and grid artifacting.
class CelImageWidget extends StatefulWidget {
  final AgiView view;
  final int loopIndex;
  final int celIndex;
  final double scale;
  final List<Color>? palette;

  const CelImageWidget({
    super.key,
    required this.view,
    this.loopIndex = 0,
    this.celIndex = 0,
    this.scale = 3.0,
    this.palette,
  });

  @override
  State<CelImageWidget> createState() => _CelImageWidgetState();
}

class _CelImageWidgetState extends State<CelImageWidget> {
  ui.Image? _cachedImage;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant CelImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        oldWidget.loopIndex != widget.loopIndex ||
        oldWidget.celIndex != widget.celIndex ||
        oldWidget.palette != widget.palette) {
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
    final cel = widget.view.getCel(widget.loopIndex, widget.celIndex);
    if (cel == null) {
      _cachedImage?.dispose();
      _cachedImage = null;
      return;
    }

    final key = '${widget.view.viewNumber}_${widget.loopIndex}_${widget.celIndex}';
    if (_cacheKey == key && _cachedImage != null) return;
    _cacheKey = key;

    final rgbaBytes = cel.toRgba(
      parentView: widget.view,
      celIndex: widget.celIndex,
      palette: widget.palette,
      scaleX: 2,
      scaleY: 1,
    );

    ui.decodeImageFromPixels(
      rgbaBytes,
      cel.width * 2,
      cel.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted && _cacheKey == key) {
          setState(() {
            _cachedImage?.dispose();
            _cachedImage = image;
          });
        } else {
          image.dispose();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cel = widget.view.getCel(widget.loopIndex, widget.celIndex);
    if (cel == null) {
      return const SizedBox.shrink();
    }

    final width = cel.width * 2.0 * widget.scale;
    final height = cel.height * 1.0 * widget.scale;

    if (_cachedImage != null) {
      return RawImage(
        image: _cachedImage,
        width: width,
        height: height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none, // Pure nearest-neighbor EGA pixel scaling
      );
    }

    return SizedBox(
      width: width,
      height: height,
    );
  }
}
