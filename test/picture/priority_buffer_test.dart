import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

void main() {
  group('PriorityBuffer Tests', () {
    test('initializes all pixels to default priority 4', () {
      final buffer = PriorityBuffer();
      expect(buffer.pixels.length, equals(160 * 168));
      expect(buffer.pixels.every((p) => p == 4), isTrue);
    });

    test('priorityAt and setPriorityAt mutate specific coordinates', () {
      final buffer = PriorityBuffer();
      buffer.setPriorityAt(15, 30, 9);
      expect(buffer.priorityAt(15, 30), equals(9));
      expect(buffer.priorityAt(16, 30), equals(4));
      expect(buffer.priorityAt(15, 31), equals(4));
    });

    test('effectivePriorityAt scans down columns for control lines < 4', () {
      final buffer = PriorityBuffer();

      // Normal depth priority (>= 4) returns immediately
      buffer.setPriorityAt(50, 20, 6);
      expect(buffer.effectivePriorityAt(50, 20), equals(6));

      // Control line 2 (unconditional barrier) at (50, 20), with depth band 8 below at (50, 25)
      buffer.setPriorityAt(50, 20, 2);
      buffer.setPriorityAt(50, 21, 1); // another control line
      buffer.setPriorityAt(50, 22, 3); // water line
      buffer.setPriorityAt(50, 23, 0); // trigger
      buffer.setPriorityAt(50, 24, 8); // depth band 8
      expect(buffer.effectivePriorityAt(50, 20), equals(8));
      expect(buffer.effectivePriorityAt(50, 21), equals(8));
      expect(buffer.effectivePriorityAt(50, 22), equals(8));
      expect(buffer.effectivePriorityAt(50, 23), equals(8));

      // Control line at bottom of screen with no >= 4 below returns 15 (background)
      for (int y = 0; y < 168; y++) {
        buffer.setPriorityAt(80, y, 2);
      }
      expect(buffer.effectivePriorityAt(80, 0), equals(15));
      expect(buffer.effectivePriorityAt(80, 160), equals(15));
    });

    test('control line classifications', () {
      final buffer = PriorityBuffer();
      buffer.setPriorityAt(10, 10, 0); // Trigger
      buffer.setPriorityAt(20, 20, 1); // Conditional barrier
      buffer.setPriorityAt(30, 30, 2); // Unconditional barrier
      buffer.setPriorityAt(40, 40, 3); // Water
      buffer.setPriorityAt(50, 50, 4); // Normal terrain

      expect(buffer.isTrigger(10, 10), isTrue);
      expect(buffer.isControlLine(10, 10), isTrue);
      expect(buffer.isWalkable(10, 10), isTrue);

      expect(buffer.isConditionalBarrier(20, 20), isTrue);
      expect(buffer.isWalkable(20, 20), isFalse);
      expect(buffer.isWalkable(20, 20, allowConditional: true), isTrue);

      expect(buffer.isUnconditionalBarrier(30, 30), isTrue);
      expect(buffer.isWalkable(30, 30), isFalse);
      expect(buffer.isWalkable(30, 30, allowConditional: true), isFalse);

      expect(buffer.isWater(40, 40), isTrue);
      expect(buffer.isControlLine(40, 40), isTrue);

      expect(buffer.isControlLine(50, 50), isFalse);
      expect(buffer.isWalkable(50, 50), isTrue);
    });

    test('renderPriorityMapRgba produces 320x200 RGBA buffer', () {
      final buffer = PriorityBuffer();
      buffer.setPriorityAt(0, 0, 1); // Blue

      final rgba = buffer.renderPriorityMapRgba();
      expect(rgba.length, equals(320 * 200 * 4));

      // Pixel 0,0 in 160x168 expands to x=0 and x=1 in 320x200
      final expectedCol = EgaColors.rgbaBytes[1];
      expect(rgba.sublist(0, 4), equals(expectedCol));
      expect(rgba.sublist(4, 8), equals(expectedCol));
    });

    test('renderControlMapRgba produces 320x200 RGBA buffer with transparent non-control pixels', () {
      final buffer = PriorityBuffer();
      buffer.setPriorityAt(0, 0, 2); // Unconditional barrier (Red)

      final rgba = buffer.renderControlMapRgba();
      expect(rgba.length, equals(320 * 200 * 4));

      // Pixel 0,0 in 160x168 expands to x=0 and x=1
      final expectedCol = EgaColors.controlRgbaBytes[2];
      expect(rgba.sublist(0, 4), equals(expectedCol));
      expect(rgba.sublist(4, 8), equals(expectedCol));

      // Pixel at (1, 0) was priority 4 (default non-control), so in 320x200 at x=2 and x=3 it should be transparent
      expect(rgba.sublist(8, 12), equals([0, 0, 0, 0]));
      expect(rgba.sublist(12, 16), equals([0, 0, 0, 0]));
    });
  });
}
