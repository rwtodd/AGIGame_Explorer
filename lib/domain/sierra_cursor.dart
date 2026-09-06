import 'dart:math' as math;
import 'dart:typed_data';

/// Pixel state within a 2-bit masked Sierra cursor.
enum SierraCursorPixel {
  /// Opaque black outline (EGA 0: #000000).
  black,

  /// Opaque white interior (EGA 15: #FFFFFF).
  white,

  /// Fully transparent background pixel (alpha = 0).
  transparent,

  /// Inverted / secondary color (white in SCI0, light gray EGA 7 in SCI1).
  gray,
}

/// Abstract representation of a Sierra mouse cursor resource.
abstract class SierraCursor {
  const SierraCursor();

  /// Resource ID number (e.g. 999 for standard arrow, 997 for crosshairs).
  int get cursorNumber;

  /// Width in screen pixels (typically 16).
  int get width;

  /// Height in screen pixels (typically 16).
  int get height;

  /// Horizontal hotspot anchor coordinate in cursor-relative pixel space.
  int get hotspotX;

  /// Vertical hotspot anchor coordinate in cursor-relative pixel space.
  int get hotspotY;

  /// Retrieves the [SierraCursorPixel] at ([x], [y]).
  SierraCursorPixel getPixel(int x, int y);

  /// Converts the cursor into a 32-bit RGBA pixel byte array.
  ///
  /// Transparent pixels receive alpha = 0.
  /// [scale] applies an integer multiplier to width and height.
  /// If [isSci0] is true, [SierraCursorPixel.gray] is mapped to white (authentic SCI0 behavior).
  Uint8List toRgba({
    int scale = 1,
    bool isSci0 = true,
  }) {
    final effectiveScale = math.max(1, scale);
    final outWidth = width * effectiveScale;
    final outHeight = height * effectiveScale;
    final rgba = Uint8List(outWidth * outHeight * 4);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = getPixel(x, y);

        int r = 0;
        int g = 0;
        int b = 0;
        int a = 0;

        switch (pixel) {
          case SierraCursorPixel.black:
            r = 0;
            g = 0;
            b = 0;
            a = 255;
            break;
          case SierraCursorPixel.white:
            r = 255;
            g = 255;
            b = 255;
            a = 255;
            break;
          case SierraCursorPixel.transparent:
            a = 0;
            break;
          case SierraCursorPixel.gray:
            if (isSci0) {
              r = 255;
              g = 255;
              b = 255;
            } else {
              r = 170;
              g = 170;
              b = 170; // EGA 7 Light Gray
            }
            a = 255;
            break;
        }

        for (var sy = 0; sy < effectiveScale; sy++) {
          final outY = y * effectiveScale + sy;
          for (var sx = 0; sx < effectiveScale; sx++) {
            final outX = x * effectiveScale + sx;
            final idx = (outY * outWidth + outX) * 4;
            rgba[idx] = r;
            rgba[idx + 1] = g;
            rgba[idx + 2] = b;
            rgba[idx + 3] = a;
          }
        }
      }
    }

    return rgba;
  }

  /// Resolves the standard Sierra cursor name from common SCI conventions.
  static String standardCursorName(int cursorId) {
    switch (cursorId) {
      case 999:
        return 'Arrow Pointer';
      case 997:
        return 'Crosshair / Target';
      case 998:
        return 'Hourglass / Wait';
      case 996:
        return 'Help / Question';
      default:
        return 'Cursor $cursorId';
    }
  }

  /// Resolves a descriptive role summary for the cursor.
  static String standardCursorDescription(int cursorId) {
    switch (cursorId) {
      case 999:
        return 'Default arrow pointer for mouse interaction and menus';
      case 997:
        return 'Targeting reticle / magnifying crosshair cursor';
      case 998:
        return 'Busy wait hourglass indicator';
      case 996:
        return 'Context-sensitive help pointer';
      default:
        return 'Game-specific custom mouse cursor';
    }
  }
}
