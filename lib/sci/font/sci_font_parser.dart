import 'dart:typed_data';
import 'package:flutter_agigame/sci/font/sci_font.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// Parser for authentic Sierra SCI 1-bit monochrome FONT resources.
class SciFontParser {
  const SciFontParser._();

  /// Parses a decompressed Sierra SCI `FONT` resource (type 7).
  ///
  /// [bytes] contains the raw decompressed font data.
  /// [fontNumber] specifies the font resource ID (e.g. 0 for SYSFONT).
  static SciFont parse(Uint8List bytes, {int fontNumber = 0}) {
    if (bytes.length < 6) {
      throw const SciCorruptResourceException(
        'Font resource is too short (< 6 bytes)',
      );
    }

    final bd = ByteData.sublistView(bytes);
    final formatFlag = bd.getUint16(0, Endian.little);
    final numChars = bd.getUint16(2, Endian.little);
    final fontHeight = bd.getUint16(4, Endian.little);

    final minTableSize = 6 + numChars * 2;
    if (bytes.length < minTableSize) {
      throw SciCorruptResourceException(
        'Font charOffsets table exceeds resource size (needs $minTableSize bytes, got ${bytes.length})',
      );
    }

    final glyphs = List<SciFontGlyph?>.filled(numChars, null);

    for (var i = 0; i < numChars; i++) {
      final charOffset = bd.getUint16(6 + i * 2, Endian.little);

      // Validate offset bounds (allow 0 or invalid offsets as empty characters,
      // matching ScummVM bug #10509 workaround for fan games).
      if (charOffset == 0 || charOffset + 2 > bytes.length) {
        continue;
      }

      final width = bytes[charOffset];
      final height = bytes[charOffset + 1];

      if (width == 0 || height == 0) {
        continue;
      }

      final bytesPerRow = (width + 7) ~/ 8;
      final dataSize = bytesPerRow * height;
      final dataEnd = charOffset + 2 + dataSize;

      if (dataEnd > bytes.length) {
        // Truncated glyph data
        continue;
      }

      final rawBitmap = Uint8List.sublistView(bytes, charOffset + 2, dataEnd);

      glyphs[i] = SciFontGlyph(
        charCode: i,
        width: width,
        height: height,
        charOffset: charOffset,
        rawBitmap: rawBitmap,
      );
    }

    return SciFont(
      fontNumber: fontNumber,
      formatFlag: formatFlag,
      fontHeight: fontHeight,
      numChars: numChars,
      glyphs: glyphs,
    );
  }
}
