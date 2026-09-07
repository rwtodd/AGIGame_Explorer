import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Represents an individual font character glyph.
abstract class SierraFontGlyph {
  const SierraFontGlyph();

  /// Character code (e.g. ASCII 0..127 or 0..255).
  int get charCode;

  /// Pixel advance width of this glyph.
  int get width;

  /// Pixel height of this glyph.
  int get height;

  /// Returns whether the pixel at ([x], [y]) is foreground (ink) or background.
  bool isPixelSet(int x, int y);

  /// Converts this glyph into a 32-bit RGBA pixel byte array.
  ///
  /// If [bgColor] is omitted, transparent background pixels (alpha = 0) are used.
  /// [scale] applies an integer multiplier to both width and height.
  Uint8List toRgba({
    Color fgColor = const Color(0xFFFFFFFF),
    Color? bgColor,
    int scale = 1,
  }) {
    final effectiveScale = math.max(1, scale);
    final outWidth = width * effectiveScale;
    final outHeight = height * effectiveScale;
    final rgba = Uint8List(outWidth * outHeight * 4);

    final fgR = (fgColor.r * 255.0).round().clamp(0, 255);
    final fgG = (fgColor.g * 255.0).round().clamp(0, 255);
    final fgB = (fgColor.b * 255.0).round().clamp(0, 255);
    final fgA = (fgColor.a * 255.0).round().clamp(0, 255);

    final bgR = bgColor != null ? (bgColor.r * 255.0).round().clamp(0, 255) : 0;
    final bgG = bgColor != null ? (bgColor.g * 255.0).round().clamp(0, 255) : 0;
    final bgB = bgColor != null ? (bgColor.b * 255.0).round().clamp(0, 255) : 0;
    final bgA = bgColor != null ? (bgColor.a * 255.0).round().clamp(0, 255) : 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final set = isPixelSet(x, y);
        final r = set ? fgR : bgR;
        final g = set ? fgG : bgG;
        final b = set ? fgB : bgB;
        final a = set ? fgA : bgA;

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
}

/// Abstract font interface representing a Sierra typography resource.
abstract class SierraFont {
  const SierraFont();

  /// Resource ID number (e.g. 0 for SYSFONT, 1 for USERFONT, 999 for GENEVA7).
  int get fontNumber;

  /// Line height / nominal vertical font advance in screen pixels.
  int get fontHeight;

  /// Total character slots allocated in the font header (typically 128 or 256).
  int get numChars;

  /// Number of non-empty / valid glyphs defined in this font.
  int get validGlyphCount;

  /// Retrieves the [SierraFontGlyph] for [charCode], or `null` if unmapped.
  SierraFontGlyph? getGlyph(int charCode);

  /// Horizontal character advance width in pixels (0 for missing characters).
  int getCharWidth(int charCode) => getGlyph(charCode)?.width ?? 0;

  /// Character height in pixels (0 for missing characters).
  int getCharHeight(int charCode) => getGlyph(charCode)?.height ?? 0;

  /// Measures total width in pixels of a single-line string.
  int measureTextWidth(String text) {
    var width = 0;
    for (var i = 0; i < text.length; i++) {
      width += getCharWidth(text.codeUnitAt(i));
    }
    return width;
  }

  /// Measures total height in pixels of a string, taking into account `\n` line breaks.
  ///
  /// Uses [fontHeight] as the line advance (kernel `TextWidth` / `GetLongest`
  /// layout). Glyphs may ink past this; see [measureRenderedTextHeight].
  int measureTextHeight(String text, {int lineSpacing = 1}) {
    if (text.isEmpty) return 0;
    final lines = text.split('\n');
    return lines.length * fontHeight + (lines.length - 1) * lineSpacing;
  }

  /// Pixel height of [text] as drawn by [renderTextToRgba].
  ///
  /// Line advance is still [fontHeight]; this is taller when a glyph's bitmap
  /// extends past the nominal advance (PQ2 FONT 0: `fontHeight` 8, `'A'` 9).
  int measureRenderedTextHeight(String text, {int lineSpacing = 1}) {
    final lines = text.isEmpty ? const [''] : text.split('\n');
    var y = 0;
    var bottom = 0;
    for (final line in lines) {
      var ink = 0;
      for (var i = 0; i < line.length; i++) {
        final h = getCharHeight(line.codeUnitAt(i));
        if (h > ink) ink = h;
      }
      final lineBottom = y + ink;
      if (lineBottom > bottom) bottom = lineBottom;
      y += fontHeight + lineSpacing;
    }
    return math.max(1, bottom);
  }

  /// Renders [text] into a 320-pixel (or fitted) 32-bit RGBA pixel byte array.
  ///
  /// Supports multi-line text separated by `\n`.
  /// If [fitWidth] is true, the bitmap width fits the longest line; otherwise,
  /// it defaults to 320 (native Sierra screen width).
  Uint8List renderTextToRgba(
    String text, {
    Color fgColor = const Color(0xFFFFFFFF),
    Color? bgColor,
    int scale = 1,
    bool greyed = false,
    int lineSpacing = 1,
    bool fitWidth = true,
  }) {
    final effectiveScale = math.max(1, scale);
    final lines = text.isEmpty ? [''] : text.split('\n');

    var maxLineWidth = 0;
    for (final line in lines) {
      final w = measureTextWidth(line);
      if (w > maxLineWidth) maxLineWidth = w;
    }

    final nativeWidth = fitWidth ? math.max(1, maxLineWidth) : 320;
    final nativeHeight = measureRenderedTextHeight(text, lineSpacing: lineSpacing);

    final outWidth = nativeWidth * effectiveScale;
    final outHeight = nativeHeight * effectiveScale;
    final rgba = Uint8List(outWidth * outHeight * 4);

    final fgR = (fgColor.r * 255.0).round().clamp(0, 255);
    final fgG = (fgColor.g * 255.0).round().clamp(0, 255);
    final fgB = (fgColor.b * 255.0).round().clamp(0, 255);
    final fgA = (fgColor.a * 255.0).round().clamp(0, 255);

    final bgR = bgColor != null ? (bgColor.r * 255.0).round().clamp(0, 255) : 0;
    final bgG = bgColor != null ? (bgColor.g * 255.0).round().clamp(0, 255) : 0;
    final bgB = bgColor != null ? (bgColor.b * 255.0).round().clamp(0, 255) : 0;
    final bgA = bgColor != null ? (bgColor.a * 255.0).round().clamp(0, 255) : 0;

    // Fill background if specified
    if (bgColor != null && bgA > 0) {
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = bgR;
        rgba[i + 1] = bgG;
        rgba[i + 2] = bgB;
        rgba[i + 3] = bgA;
      }
    }

    var cursorY = 0;
    for (final line in lines) {
      var cursorX = 0;
      for (var i = 0; i < line.length; i++) {
        final code = line.codeUnitAt(i);
        final glyph = getGlyph(code);
        if (glyph == null || glyph.width == 0) continue;

        for (var gy = 0; gy < glyph.height; gy++) {
          final targetY = cursorY + gy;
          if (targetY >= nativeHeight) break;

          // Authentic Sierra greyed stipple: alternate bits on odd/even lines
          final mask = greyed ? ((targetY % 2 == 1) ? 0xAA : 0x55) : 0xFF;

          for (var gx = 0; gx < glyph.width; gx++) {
            final targetX = cursorX + gx;
            if (targetX >= nativeWidth) break;

            if (glyph.isPixelSet(gx, gy)) {
              if (greyed && ((mask & (0x80 >> (gx & 7))) == 0)) {
                continue;
              }

              for (var sy = 0; sy < effectiveScale; sy++) {
                final outY = targetY * effectiveScale + sy;
                for (var sx = 0; sx < effectiveScale; sx++) {
                  final outX = targetX * effectiveScale + sx;
                  final idx = (outY * outWidth + outX) * 4;
                  rgba[idx] = fgR;
                  rgba[idx + 1] = fgG;
                  rgba[idx + 2] = fgB;
                  rgba[idx + 3] = fgA;
                }
              }
            }
          }
        }
        cursorX += glyph.width;
      }
      cursorY += fontHeight + lineSpacing;
    }

    return rgba;
  }

  /// Resolves the standard Sierra font role name from standard SCI conventions.
  static String standardFontName(int fontId) {
    switch (fontId) {
      case 0:
        return 'SYSFONT / Chicago 12';
      case 1:
        return 'USERFONT / New York 12';
      case 2:
        return 'GENEVA12';
      case 3:
        return 'SMALL9';
      case 4:
        return 'SERIF9';
      case 7:
        return 'HELVETICA18';
      case 999:
        return 'GENEVA7';
      default:
        return 'Font $fontId';
    }
  }

  /// Resolves the standard Sierra font role description.
  static String standardFontDescription(int fontId) {
    switch (fontId) {
      case 0:
        return 'System font: menus, dialogs, buttons, story text';
      case 1:
        return 'User font: narrative passages, descriptions, books';
      case 2:
        return '12px clean sans-serif font';
      case 3:
        return '9px condensed sans-serif for compact prompts';
      case 4:
        return '9px small serif font';
      case 7:
        return '18px large headline / title font';
      case 999:
        return '7px status line and notice font';
      default:
        return 'Game-specific custom font';
    }
  }
}
