import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/sci/font/sci_font_parser.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciFontParser', () {
    test('parses synthetic font buffer with valid glyphs and empty slots', () {
      // Build a synthetic 3-glyph font
      // 0x00: flag = 0 (uint16)
      // 0x02: numChars = 3 (uint16)
      // 0x04: fontHeight = 8 (uint16)
      // 0x06: offset[0] = 12 (uint16) -> char 0: 4x4 block
      // 0x08: offset[1] = 20 (uint16) -> char 1: 3x3 diagonal
      // 0x0A: offset[2] = 0 (uint16) -> char 2: unmapped
      // 0x0C (12): width = 4, height = 4, followed by 4 bytes (0xF0, 0xF0, 0xF0, 0xF0)
      // 0x12 (18): padding / alignment
      // 0x14 (20): width = 3, height = 3, followed by 3 bytes (0x80, 0x40, 0x20)
      final bytes = Uint8List(26);
      final bd = ByteData.sublistView(bytes);
      bd.setUint16(0, 0x0000, Endian.little);
      bd.setUint16(2, 3, Endian.little);
      bd.setUint16(4, 8, Endian.little);
      bd.setUint16(6, 12, Endian.little);
      bd.setUint16(8, 20, Endian.little);
      bd.setUint16(10, 0, Endian.little);

      // Char 0 at offset 12
      bytes[12] = 4; // width
      bytes[13] = 4; // height
      bytes[14] = 0xF0; // 1111 0000
      bytes[15] = 0xF0;
      bytes[16] = 0xF0;
      bytes[17] = 0xF0;

      // Char 1 at offset 20
      bytes[20] = 3; // width
      bytes[21] = 3; // height
      bytes[22] = 0x80; // 1000 0000 (x=0 set)
      bytes[23] = 0x40; // 0100 0000 (x=1 set)
      bytes[24] = 0x20; // 0010 0000 (x=2 set)

      final font = SciFontParser.parse(bytes, fontNumber: 42);

      expect(font.fontNumber, 42);
      expect(font.formatFlag, 0);
      expect(font.fontHeight, 8);
      expect(font.numChars, 3);
      expect(font.validGlyphCount, 2);

      // Char 0
      final g0 = font.getGlyph(0);
      expect(g0, isNotNull);
      expect(g0!.width, 4);
      expect(g0.height, 4);
      expect(g0.charOffset, 12);
      expect(g0.isPixelSet(0, 0), isTrue);
      expect(g0.isPixelSet(3, 3), isTrue);
      expect(g0.isPixelSet(4, 0), isFalse); // out of bounds

      // Char 1
      final g1 = font.getGlyph(1);
      expect(g1, isNotNull);
      expect(g1!.width, 3);
      expect(g1.height, 3);
      expect(g1.isPixelSet(0, 0), isTrue);
      expect(g1.isPixelSet(1, 0), isFalse);
      expect(g1.isPixelSet(1, 1), isTrue);
      expect(g1.isPixelSet(2, 2), isTrue);

      // Char 2 (unmapped)
      expect(font.getGlyph(2), isNull);
      expect(font.getCharWidth(2), 0);
      expect(font.getCharHeight(2), 0);

      // Measure text
      expect(font.measureTextWidth(String.fromCharCodes([0, 1])), 4 + 3);
      expect(font.measureTextHeight('Line1\nLine2', lineSpacing: 2), 8 * 2 + 2);

      // Render RGBA
      final rgba = font.renderTextToRgba(
        String.fromCharCodes([0, 1]),
        fgColor: const Color(0xFFFF0000),
        bgColor: const Color(0xFF000000),
      );
      expect(rgba.length, (4 + 3) * 8 * 4);
      // Pixel (0, 0) should be Red (char 0, (0,0) is set)
      expect(rgba[0], 255);
      expect(rgba[1], 0);
      expect(rgba[2], 0);
      expect(rgba[3], 255);
    });

    test('throws SciCorruptResourceException for truncated font header or offset table', () {
      expect(
        () => SciFontParser.parse(Uint8List(4)),
        throwsA(isA<SciCorruptResourceException>()),
      );

      final truncatedTable = Uint8List(8);
      final bd = ByteData.sublistView(truncatedTable);
      bd.setUint16(0, 0, Endian.little);
      bd.setUint16(2, 10, Endian.little); // claims 10 chars -> needs 6 + 20 = 26 bytes
      bd.setUint16(4, 8, Endian.little);

      expect(
        () => SciFontParser.parse(truncatedTable),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('gracefully ignores invalid offsets or truncated glyph data without crashing', () {
      final bytes = Uint8List(14);
      final bd = ByteData.sublistView(bytes);
      bd.setUint16(0, 0, Endian.little);
      bd.setUint16(2, 2, Endian.little); // 2 chars
      bd.setUint16(4, 8, Endian.little);
      bd.setUint16(6, 50, Endian.little); // offset out of bounds
      bd.setUint16(8, 10, Endian.little); // offset 10: w=8, h=8 needs 10+2+8=20 bytes (> 14)

      bytes[10] = 8;
      bytes[11] = 8;

      final font = SciFontParser.parse(bytes);
      expect(font.numChars, 2);
      expect(font.validGlyphCount, 0);
      expect(font.getGlyph(0), isNull);
      expect(font.getGlyph(1), isNull);
    });

    test('renders greyed output with stipple masking', () {
      // 1-glyph font: 8x2 block
      final bytes = Uint8List(18);
      final bd = ByteData.sublistView(bytes);
      bd.setUint16(0, 0, Endian.little);
      bd.setUint16(2, 1, Endian.little);
      bd.setUint16(4, 2, Endian.little);
      bd.setUint16(6, 8, Endian.little);

      bytes[8] = 8; // width
      bytes[9] = 2; // height
      bytes[10] = 0xFF; // row 0: all 8 bits set
      bytes[11] = 0xFF; // row 1: all 8 bits set

      final font = SciFontParser.parse(bytes);
      final normal = font.renderTextToRgba(String.fromCharCode(0));
      final greyed = font.renderTextToRgba(String.fromCharCode(0), greyed: true);

      // Normal has all pixels set to white
      var normalSetCount = 0;
      for (var i = 0; i < normal.length; i += 4) {
        if (normal[i + 3] > 0) normalSetCount++;
      }
      expect(normalSetCount, 16);

      // Greyed has half the pixels masked
      var greyedSetCount = 0;
      for (var i = 0; i < greyed.length; i += 4) {
        if (greyed[i + 3] > 0) greyedSetCount++;
      }
      expect(greyedSetCount, 8);
    });

    test('resolves standard font names and descriptions', () {
      expect(SierraFont.standardFontName(0), contains('SYSFONT'));
      expect(SierraFont.standardFontName(1), contains('USERFONT'));
      expect(SierraFont.standardFontName(4), contains('SERIF9'));
      expect(SierraFont.standardFontName(7), contains('HELVETICA18'));
      expect(SierraFont.standardFontName(999), contains('GENEVA7'));
      expect(SierraFont.standardFontName(42), 'Font 42');

      expect(SierraFont.standardFontDescription(0), contains('System font'));
      expect(SierraFont.standardFontDescription(1), contains('User font'));
    });
  });
}
