import 'dart:typed_data';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// Parser for authentic Sierra SCI 68-byte CURSOR resources (`CURSOR`, type 8).
class SciCursorParser {
  const SciCursorParser._();

  /// Total binary resource length for a standard Sierra CURSOR resource.
  static const int resourceSize = 68;

  /// Standard cursor sprite width and height in screen pixels.
  static const int dimension = 16;

  /// Parses a decompressed Sierra SCI `CURSOR` resource.
  ///
  /// [bytes] must contain at least 68 bytes of data.
  /// [cursorNumber] is the resource ID number (e.g. 999 for arrow).
  /// [isSci0] controls hotspot and color mapping (true for SCI0/01, false for SCI1+).
  static SciCursor parse(
    Uint8List bytes, {
    int cursorNumber = 0,
    bool isSci0 = true,
  }) {
    if (bytes.length < resourceSize) {
      throw SciCorruptResourceException(
        'Cursor resource too short (< $resourceSize bytes, got ${bytes.length})',
      );
    }

    final bd = ByteData.sublistView(bytes);

    final int hotspotX;
    final int hotspotY;

    if (isSci0) {
      // In SCI0, byte 3 determines whether the hotspot is centered at (8, 8) or top-left (0, 0)
      final centerFlag = bytes[3] != 0;
      hotspotX = centerFlag ? dimension ~/ 2 : 0;
      hotspotY = centerFlag ? dimension ~/ 2 : 0;
    } else {
      // In SCI1+, coordinates are stored as little-endian 16-bit integers
      hotspotX = bd.getUint16(0, Endian.little);
      hotspotY = bd.getUint16(2, Endian.little);
    }

    // Mask A: 16 little-endian words at bytes 4..35
    // Mask B: 16 little-endian words at bytes 36..67
    final maskA = Uint8List.sublistView(bytes, 4, 36);
    final maskB = Uint8List.sublistView(bytes, 36, 68);

    final pixels = List<SierraCursorPixel>.filled(
      dimension * dimension,
      SierraCursorPixel.transparent,
    );

    for (var y = 0; y < dimension; y++) {
      final wordA = bd.getUint16(4 + (y << 1), Endian.little);
      final wordB = bd.getUint16(36 + (y << 1), Endian.little);

      for (var x = 0; x < dimension; x++) {
        final bitMask = 0x8000 >> x;
        final bitA = (wordA & bitMask) != 0 ? 1 : 0;
        final bitB = (wordB & bitMask) != 0 ? 1 : 0;
        final code = (bitA << 1) | bitB;

        final SierraCursorPixel pixel;
        switch (code) {
          case 0:
            pixel = SierraCursorPixel.black;
            break;
          case 1:
            pixel = SierraCursorPixel.white;
            break;
          case 2:
            pixel = SierraCursorPixel.transparent;
            break;
          case 3:
            pixel = SierraCursorPixel.gray;
            break;
          default:
            pixel = SierraCursorPixel.transparent;
            break;
        }

        pixels[y * dimension + x] = pixel;
      }
    }

    return SciCursor(
      cursorNumber: cursorNumber,
      width: dimension,
      height: dimension,
      hotspotX: hotspotX,
      hotspotY: hotspotY,
      pixels: pixels,
      maskA: maskA,
      maskB: maskB,
    );
  }
}
