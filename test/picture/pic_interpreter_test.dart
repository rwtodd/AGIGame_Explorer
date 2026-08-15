import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/picture/pic_vector_interpreter.dart';

void main() {
  group('PicVectorInterpreter Golden Tests', () {
    test('decodes golden picture resource exactly matching reference output', () {
      final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();
      final expectedPic = File('test/fixtures/picbytes.bin').readAsBytesSync();
      final expectedPri = File('test/fixtures/pribytes.bin').readAsBytesSync();

      final interpreter = PicVectorInterpreter(isV3: false);
      final pic = interpreter.interpret(srcBytes);

      expect(pic.visualPixels, equals(expectedPic));
      expect(pic.priorityBuffer.pixels, equals(expectedPri));
      expect(pic.slices.length, equals(16));
    });
  });

  group('PicVectorInterpreter Basic Opcodes', () {
    test('initializes screen to visual 15 (white) and priority 4', () {
      final data = Uint8List.fromList([0xFF]); // Immediate end
      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      expect(pic.visualPixels.every((p) => p == 15), isTrue);
      expect(pic.priorityBuffer.pixels.every((p) => p == 4), isTrue);
    });

    test('0xF0, 0xF2, 0xF6: draws absolute line with visual and priority colors', () {
      final data = Uint8List.fromList([
        0xF0, 0x01, // Visual color = 1 (Blue)
        0xF2, 0x0C, // Priority color = 12 (Light Red)
        0xF6, // Absolute line
        10, 20, // Start (10, 20)
        10, 25, // End (10, 25)
        0xFF, // End
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      for (int y = 20; y <= 25; y++) {
        expect(pic.visualPixels[y * 160 + 10], equals(1), reason: 'Visual pixel at (10, $y)');
        expect(pic.priorityBuffer.priorityAt(10, y), equals(12), reason: 'Priority pixel at (10, $y)');
      }
      // Adjacent pixels should remain default
      expect(pic.visualPixels[20 * 160 + 11], equals(15));
      expect(pic.priorityBuffer.priorityAt(11, 20), equals(4));
    });

    test('0xF1, 0xF3: disables visual and priority drawing', () {
      final data = Uint8List.fromList([
        0xF0, 0x02, // Visual color = 2 (Green)
        0xF2, 0x03, // Priority color = 3 (Cyan)
        0xF1, // Disable visual draw
        0xF6, 5, 5, 5, 10, // Draw line with only priority active
        0xF0, 0x04, // Enable visual color 4
        0xF3, // Disable priority draw
        0xF6, 20, 20, 20, 25, // Draw line with only visual active
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      // Line 1: priority 3, visual unchanged (15)
      for (int y = 5; y <= 10; y++) {
        expect(pic.visualPixels[y * 160 + 5], equals(15));
        expect(pic.priorityBuffer.priorityAt(5, y), equals(3));
      }

      // Line 2: visual 4, priority unchanged (4)
      for (int y = 20; y <= 25; y++) {
        expect(pic.visualPixels[y * 160 + 20], equals(4));
        expect(pic.priorityBuffer.priorityAt(20, y), equals(4));
      }
    });

    test('0xF4: Y corner (vertical then horizontal alternating)', () {
      final data = Uint8List.fromList([
        0xF0, 0x05, // Magenta
        0xF4, // Y corner
        10, 10, // Start (10, 10)
        20, // y2 = 20 -> vertical to (10, 20)
        30, // x2 = 30 -> horizontal to (30, 20)
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      // Vertical segment (10, 10) to (10, 20)
      for (int y = 10; y <= 20; y++) {
        expect(pic.visualPixels[y * 160 + 10], equals(5));
      }
      // Horizontal segment (10, 20) to (30, 20)
      for (int x = 10; x <= 30; x++) {
        expect(pic.visualPixels[20 * 160 + x], equals(5));
      }
    });

    test('0xF5: X corner (horizontal then vertical alternating)', () {
      final data = Uint8List.fromList([
        0xF0, 0x06, // Brown
        0xF5, // X corner
        10, 10, // Start (10, 10)
        30, // x2 = 30 -> horizontal to (30, 10)
        20, // y2 = 20 -> vertical to (30, 20)
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      // Horizontal segment (10, 10) to (30, 10)
      for (int x = 10; x <= 30; x++) {
        expect(pic.visualPixels[10 * 160 + x], equals(6));
      }
      // Vertical segment (30, 10) to (30, 20)
      for (int y = 10; y <= 20; y++) {
        expect(pic.visualPixels[y * 160 + 30], equals(6));
      }
    });

    test('0xF7: Relative lines', () {
      final data = Uint8List.fromList([
        0xF0, 0x09, // Light Blue
        0xF7, // Relative line
        50, 50, // Start at (50, 50)
        // dx: positive 4 (0x40), dy: positive 3 (0x03) -> byte 0x43
        0x43, // moves to (54, 53)
        // dx: negative 2 (0x80 | 0x20 = 0xA0), dy: negative 1 (0x08 | 0x01 = 0x09) -> byte 0xA9
        0xA9, // moves to (52, 52)
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      expect(pic.visualPixels[50 * 160 + 50], equals(9));
      expect(pic.visualPixels[53 * 160 + 54], equals(9));
      expect(pic.visualPixels[52 * 160 + 52], equals(9));
    });

    test('0xF8: Flood fill fills enclosed area with visual color', () {
      final data = Uint8List.fromList([
        0xF0, 0x00, // Black boundary lines
        0xF6, // Absolute rectangle boundary
        10, 10,
        20, 10,
        20, 20,
        10, 20,
        10, 10,
        0xF0, 0x02, // Green fill color
        0xF8, // Flood fill
        15, 15, // Seed point inside rectangle
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      // Boundary should be black (0)
      expect(pic.visualPixels[10 * 160 + 10], equals(0));
      expect(pic.visualPixels[10 * 160 + 20], equals(0));

      // Inside should be green (2)
      expect(pic.visualPixels[15 * 160 + 15], equals(2));
      expect(pic.visualPixels[11 * 160 + 11], equals(2));
      expect(pic.visualPixels[19 * 160 + 19], equals(2));

      // Outside should remain white (15)
      expect(pic.visualPixels[5 * 160 + 5], equals(15));
      expect(pic.visualPixels[25 * 160 + 25], equals(15));
    });

    test('0xF9, 0xFA: Pen size and style plot', () {
      final data = Uint8List.fromList([
        0xF0, 0x04, // Red
        0xF9, 0x11, // Rectangle pen (0x10), solid (0x00), size 1 (0x01) -> width=2, height=3
        0xFA, // Draw pen
        50, 50, // Center at (50, 50)
        0xFF,
      ]);

      final interpreter = PicVectorInterpreter();
      final pic = interpreter.interpret(data);

      // Width = 2 (col 0, 1 from left = 50 - 1 = 49 -> x=49, 50)
      // Height = 3 (row 0, 1, 2 from top = 50 - 1 = 49 -> y=49, 50, 51)
      for (int y = 49; y <= 51; y++) {
        for (int x = 49; x <= 50; x++) {
          expect(pic.visualPixels[y * 160 + x], equals(4), reason: 'Pen pixel at ($x, $y)');
        }
      }
    });

    test('throws AgiException on invalid opcode', () {
      final data = Uint8List.fromList([0xEE]); // Invalid opcode
      final interpreter = PicVectorInterpreter();
      expect(() => interpreter.interpret(data), throwsA(isA<AgiException>()));
    });
  });
}
