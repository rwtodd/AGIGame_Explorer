import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/agi_view.dart';

/// CustomPainter that renders a single [AgiViewCel] with 2:1 EGA pixel aspect ratio
/// and transparent pixel handling.
class CelPainter extends CustomPainter {
  final AgiView view;
  final int loopIndex;
  final int celIndex;
  final double pixelScale;
  final List<Color>? palette;

  const CelPainter({
    required this.view,
    this.loopIndex = 0,
    this.celIndex = 0,
    this.pixelScale = 3.0,
    this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cel = view.getCel(loopIndex, celIndex);
    if (cel == null) return;

    final pixels = cel.getPixels(parentView: view, celIndex: celIndex);
    final effectivePalette = palette ?? EgaColors.palette;
    final p = Paint()..style = PaintingStyle.fill;

    final celDrawWidth = cel.width * 2.0 * pixelScale;
    final celDrawHeight = cel.height * 1.0 * pixelScale;
    final offsetX = (size.width - celDrawWidth) / 2.0;
    final offsetY = (size.height - celDrawHeight) / 2.0;

    for (int y = 0; y < cel.height; y++) {
      final rowOffset = y * cel.width;
      for (int x = 0; x < cel.width; x++) {
        final colorIdx = pixels[rowOffset + x] & 0x0F;
        if (colorIdx != cel.transparentColor) {
          final color = colorIdx < effectivePalette.length
              ? effectivePalette[colorIdx]
              : effectivePalette[0];
          p.color = color;
          canvas.drawRect(
            Rect.fromLTWH(
              offsetX + (x * 2.0 * pixelScale),
              offsetY + (y * 1.0 * pixelScale),
              2.0 * pixelScale,
              1.0 * pixelScale,
            ),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CelPainter oldDelegate) {
    return oldDelegate.view != view ||
        oldDelegate.loopIndex != loopIndex ||
        oldDelegate.celIndex != celIndex ||
        oldDelegate.pixelScale != pixelScale ||
        oldDelegate.palette != palette;
  }
}

/// Widget that displays an individual sprite cel from an [AgiView] resource.
class CelImageWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cel = view.getCel(loopIndex, celIndex);
    if (cel == null) {
      return const SizedBox.shrink();
    }

    final width = cel.width * 2.0 * scale;
    final height = cel.height * 1.0 * scale;

    return CustomPaint(
      size: Size(width, height),
      painter: CelPainter(
        view: view,
        loopIndex: loopIndex,
        celIndex: celIndex,
        pixelScale: scale,
        palette: palette,
      ),
    );
  }
}
