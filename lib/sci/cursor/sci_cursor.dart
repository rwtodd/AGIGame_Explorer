import 'dart:typed_data';
import 'package:flutter_agigame/domain/sierra_cursor.dart';

/// Authentic Sierra SCI 16x16 masked cursor sprite (`CURSOR`, type 8).
class SciCursor extends SierraCursor {
  @override
  final int cursorNumber;

  @override
  final int width;

  @override
  final int height;

  @override
  final int hotspotX;

  @override
  final int hotspotY;

  /// 16x16 grid of resolved pixel states (length 256).
  final List<SierraCursorPixel> pixels;

  /// Raw 32 bytes of Mask A (16 words, one per scanline).
  final Uint8List maskA;

  /// Raw 32 bytes of Mask B (16 words, one per scanline).
  final Uint8List maskB;

  const SciCursor({
    required this.cursorNumber,
    this.width = 16,
    this.height = 16,
    required this.hotspotX,
    required this.hotspotY,
    required this.pixels,
    required this.maskA,
    required this.maskB,
  });

  @override
  SierraCursorPixel getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return SierraCursorPixel.transparent;
    }
    return pixels[y * width + x];
  }

  @override
  String toString() =>
      'SciCursor($cursorNumber: ${SierraCursor.standardCursorName(cursorNumber)}, '
      'hotspot: ($hotspotX, $hotspotY), size: ${width}x$height)';
}
