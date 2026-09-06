import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';

void main() {
  group('SciPicInterpreter Synthetic Tests', () {
    test('initializes 320x200 buffers and clears playfield to white (15)', () {
      final data = Uint8List.fromList([0xFF]); // just terminate
      final pic = SciPicInterpreter.interpret(data, portTop: 10);

      expect(pic.visualPixels.length, 320 * 200);
      expect(pic.priorityPixels.length, 320 * 200);
      expect(pic.controlPixels.length, 320 * 200);

      // Rows 0..9 are not cleared (stay 0)
      for (int y = 0; y < 10; y++) {
        expect(pic.visualAtPixel(160, y), 0);
      }
      // Rows 10..199 are cleared to 15 (white)
      for (int y = 10; y < 200; y++) {
        expect(pic.visualAtPixel(160, y), 15);
      }
    });

    test('interprets long lines across visual and priority buffers', () {
      // 0xF0 0x01 (visual color = palette[1] = 0x11 = Blue)
      // 0xF2 0x05 (priority = 5)
      // 0xF6 (long lines)
      //   abs coords: (10, 20) -> p=0, x=10, y=20
      //   abs coords: (50, 20) -> p=0, x=50, y=20
      // 0xFF (terminate)
      final data = Uint8List.fromList([
        0xF0, 0x01,
        0xF2, 0x05,
        0xF6,
        0x00, 10, 20,
        0x00, 50, 20,
        0xFF,
      ]);

      final pic = SciPicInterpreter.interpret(data, portTop: 10);

      // Y is offset by portTop (20 + 10 = 30)
      for (int x = 10; x <= 50; x++) {
        expect(pic.visualAtPixel(x, 30), 1); // Blue
        expect(pic.priorityAtPixel(x, 30), 5); // Priority 5
      }

      // Priority slices should have visible pixels at priority 5
      final slice5 = pic.getSlice(5);
      expect(slice5, isNotNull);
      expect(slice5!.hasVisiblePixels, isTrue);
    });

    test('interprets short lines and medium lines', () {
      // Short lines 0xF7, rel coord
      final data = Uint8List.fromList([
        0xF0, 0x04, // Red (0x44)
        0xF7,
        0x00, 100, 50, // start (100, 50)
        0x05, // dx = 0, dy = +5 -> (100, 55)
        0xFF,
      ]);

      final pic = SciPicInterpreter.interpret(data, portTop: 0);
      for (int y = 50; y <= 55; y++) {
        expect(pic.visualAtPixel(100, y), 4); // Red
      }
    });

    test('interprets flood fill bounded by lines', () {
      // Draw a box from (10, 10) to (30, 30) with color 4 (Red)
      // then fill inside at (20, 20) with color 2 (Green)
      final data = Uint8List.fromList([
        0xF0, 0x04, // Red
        0xF6, // Long lines box
        0x00, 10, 10,
        0x00, 30, 10,
        0x00, 30, 30,
        0x00, 10, 30,
        0x00, 10, 10,
        0xF0, 0x02, // Green
        0xF8, // Fill
        0x00, 20, 20,
        0xFF,
      ]);

      final pic = SciPicInterpreter.interpret(data, portTop: 0);

      // Inside should be Green (2)
      expect(pic.visualAtPixel(20, 20), 2);
      expect(pic.visualAtPixel(15, 15), 2);

      // Boundary should be Red (4)
      expect(pic.visualAtPixel(10, 10), 4);
      expect(pic.visualAtPixel(30, 30), 4);

      // Outside box should remain initial White (15)
      expect(pic.visualAtPixel(5, 5), 15);
      expect(pic.visualAtPixel(35, 35), 15);
    });

    test('supports authentic EGA dither vs undithered blended mode', () {
      // Palette entry 0x21 (33) in default EGA palette is 0x19 (Light Blue 9 + Blue 1)
      final data = Uint8List.fromList([
        0xF0, 33, // 0x19: c1 = 1 (Blue), c2 = 9 (Light Blue)
        0xF6,
        0x00, 10, 10,
        0x00, 20, 10,
        0xFF,
      ]);

      final pic = SciPicInterpreter.interpret(data, portTop: 0);

      // In dithered mode, alternating pixels should alternate between 1 and 9
      final d1 = pic.visualAtPixel(10, 10);
      final d2 = pic.visualAtPixel(11, 10);
      expect(d1 != d2, isTrue);
      expect([1, 9].contains(d1), isTrue);
      expect([1, 9].contains(d2), isTrue);

      // In undithered mode, rawColorPair holds both colors
      final pair = pic.rawColorPairAtPixel(10, 10);
      final c1 = (pair >> 4) & 0x0F;
      final c2 = pair & 0x0F;
      expect(c1, 1);
      expect(c2, 9);

      // Flat visual RGBA undithered should blend the two colors
      final unditheredRgba = pic.renderFlatVisualRgba(undithered: true);
      final offset = (10 * 320 + 10) * 4;
      final r = unditheredRgba[offset + 0];
      final g = unditheredRgba[offset + 1];
      final b = unditheredRgba[offset + 2];

      final col1 = EgaColors.rgbaBytes[1];
      final col2 = EgaColors.rgbaBytes[9];
      expect(r, (col1[0] + col2[0]) >> 1);
      expect(g, (col1[1] + col2[1]) >> 1);
      expect(b, (col1[2] + col2[2]) >> 1);
    });
  });
}
