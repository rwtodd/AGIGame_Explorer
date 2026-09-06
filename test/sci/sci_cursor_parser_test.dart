import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor_parser.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciCursorParser', () {
    test('parses synthetic 68-byte cursor buffer with all 4 pixel states and centered hotspot', () {
      final bytes = Uint8List(68);
      final bd = ByteData.sublistView(bytes);

      // Byte 3 = 1 -> centered hotspot in SCI0 (8, 8)
      bytes[3] = 1;

      // Row 0:
      // x=0: code 0 (bitA=0, bitB=0) -> black
      // x=1: code 1 (bitA=0, bitB=1) -> white
      // x=2: code 2 (bitA=1, bitB=0) -> transparent
      // x=3: code 3 (bitA=1, bitB=1) -> gray
      // maskA row 0: bits 13 and 12 set (0x2000 | 0x1000 = 0x3000)
      // maskB row 0: bits 14 and 12 set (0x4000 | 0x1000 = 0x5000)
      // Note:
      // x=0: bit 15 -> A=0, B=0 -> 0 (black)
      // x=1: bit 14 -> A=0, B=1 -> 1 (white)
      // x=2: bit 13 -> A=1, B=0 -> 2 (transparent)
      // x=3: bit 12 -> A=1, B=1 -> 3 (gray)
      bd.setUint16(4, 0x3000, Endian.little);
      bd.setUint16(36, 0x5000, Endian.little);

      final cursor = SciCursorParser.parse(bytes, cursorNumber: 999, isSci0: true);

      expect(cursor.cursorNumber, 999);
      expect(cursor.width, 16);
      expect(cursor.height, 16);
      expect(cursor.hotspotX, 8);
      expect(cursor.hotspotY, 8);

      expect(cursor.getPixel(0, 0), SierraCursorPixel.black);
      expect(cursor.getPixel(1, 0), SierraCursorPixel.white);
      expect(cursor.getPixel(2, 0), SierraCursorPixel.transparent);
      expect(cursor.getPixel(3, 0), SierraCursorPixel.gray);

      // Out of bounds returns transparent
      expect(cursor.getPixel(-1, 0), SierraCursorPixel.transparent);
      expect(cursor.getPixel(16, 0), SierraCursorPixel.transparent);
      expect(cursor.getPixel(0, 16), SierraCursorPixel.transparent);

      // RGBA conversion - SCI0 (gray renders as white)
      final rgbaSci0 = cursor.toRgba(scale: 1, isSci0: true);
      expect(rgbaSci0.length, 16 * 16 * 4);

      // x=0: black
      expect(rgbaSci0[0], 0);
      expect(rgbaSci0[1], 0);
      expect(rgbaSci0[2], 0);
      expect(rgbaSci0[3], 255);

      // x=1: white
      expect(rgbaSci0[4], 255);
      expect(rgbaSci0[5], 255);
      expect(rgbaSci0[6], 255);
      expect(rgbaSci0[7], 255);

      // x=2: transparent
      expect(rgbaSci0[8], 0);
      expect(rgbaSci0[9], 0);
      expect(rgbaSci0[10], 0);
      expect(rgbaSci0[11], 0);

      // x=3: white in SCI0
      expect(rgbaSci0[12], 255);
      expect(rgbaSci0[13], 255);
      expect(rgbaSci0[14], 255);
      expect(rgbaSci0[15], 255);

      // RGBA conversion - SCI1 (gray renders as EGA 7 / 170)
      final rgbaSci1 = cursor.toRgba(scale: 1, isSci0: false);
      expect(rgbaSci1[12], 170);
      expect(rgbaSci1[13], 170);
      expect(rgbaSci1[14], 170);
      expect(rgbaSci1[15], 255);
    });

    test('parses SCI1+ explicit hotspot coordinates', () {
      final bytes = Uint8List(68);
      final bd = ByteData.sublistView(bytes);
      bd.setUint16(0, 5, Endian.little); // hotspotX = 5
      bd.setUint16(2, 11, Endian.little); // hotspotY = 11

      final cursor = SciCursorParser.parse(bytes, cursorNumber: 100, isSci0: false);
      expect(cursor.hotspotX, 5);
      expect(cursor.hotspotY, 11);
    });

    test('throws SciCorruptResourceException when buffer is shorter than 68 bytes', () {
      expect(
        () => SciCursorParser.parse(Uint8List(67)),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('resolves standard cursor names and descriptions', () {
      expect(SierraCursor.standardCursorName(999), contains('Arrow'));
      expect(SierraCursor.standardCursorName(997), contains('Crosshair'));
      expect(SierraCursor.standardCursorName(998), contains('Hourglass'));
      expect(SierraCursor.standardCursorName(42), 'Cursor 42');

      expect(SierraCursor.standardCursorDescription(999), contains('arrow pointer'));
      expect(SierraCursor.standardCursorDescription(997), contains('Targeting'));
    });
  });
}
