import 'dart:typed_data';
import 'package:flutter_agigame/domain/sierra_font.dart';

/// Authentic Sierra SCI 1-bit monochrome character glyph.
class SciFontGlyph extends SierraFontGlyph {
  @override
  final int charCode;

  @override
  final int width;

  @override
  final int height;

  /// Byte offset of this glyph in the original decompressed FONT resource.
  final int charOffset;

  /// Packed 1-bit monochrome bitmap data (MSB first, row by row).
  ///
  /// Length is `bytesPerRow * height`, where `bytesPerRow = (width + 7) ~/ 8`.
  final Uint8List rawBitmap;

  const SciFontGlyph({
    required this.charCode,
    required this.width,
    required this.height,
    required this.charOffset,
    required this.rawBitmap,
  });

  /// Bytes per row of 1-bit bitmap data.
  int get bytesPerRow => (width + 7) ~/ 8;

  @override
  bool isPixelSet(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    final rowOffset = y * bytesPerRow;
    final byteIndex = rowOffset + (x >> 3);
    if (byteIndex >= rawBitmap.length) return false;
    final bitMask = 0x80 >> (x & 7);
    return (rawBitmap[byteIndex] & bitMask) != 0;
  }

  @override
  String toString() =>
      'SciFontGlyph(char: $charCode [0x${charCode.toRadixString(16)}], '
      'size: ${width}x$height, offset: $charOffset)';
}

/// Parsed Sierra SCI0 FONT resource (`FONT`, type 7).
class SciFont extends SierraFont {
  @override
  final int fontNumber;

  /// Format flag / low-byte flag from resource header (usually 0x0000 in SCI0).
  final int formatFlag;

  @override
  final int fontHeight;

  @override
  final int numChars;

  /// List of all glyph slots (size [numChars]). Slots may be `null` or 0-width.
  final List<SciFontGlyph?> glyphs;

  SciFont({
    required this.fontNumber,
    required this.formatFlag,
    required this.fontHeight,
    required this.numChars,
    required this.glyphs,
  });

  @override
  int get validGlyphCount {
    var count = 0;
    for (final g in glyphs) {
      if (g != null && g.width > 0 && g.height > 0) {
        count++;
      }
    }
    return count;
  }

  @override
  SciFontGlyph? getGlyph(int charCode) {
    if (charCode < 0 || charCode >= glyphs.length) return null;
    return glyphs[charCode];
  }

  @override
  String toString() =>
      'SciFont($fontNumber: ${SierraFont.standardFontName(fontNumber)}, '
      'height: $fontHeight, numChars: $numChars, validGlyphs: $validGlyphCount)';
}
