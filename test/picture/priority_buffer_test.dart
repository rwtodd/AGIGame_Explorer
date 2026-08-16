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

    test('effectivePriorityAt returns >2 directly and scans down for control lines <= 2', () {
      final buffer = PriorityBuffer();

      // Normal depth priority (>= 4) returns immediately
      buffer.setPriorityAt(50, 20, 6);
      expect(buffer.effectivePriorityAt(50, 20), equals(6));

      // Water (priority 3) returns immediately without scanning down
      buffer.setPriorityAt(50, 20, 3);
      buffer.setPriorityAt(50, 30, 11); // tree below
      expect(buffer.effectivePriorityAt(50, 20), equals(3), reason: 'Water (pri 3) must not scan down into tree below');

      // Barrier control line (pri 0) across a tree:
      // Pixels (50, 20..22) are barrier 0, and (50, 23) is tree depth 11
      buffer.setPriorityAt(50, 20, 0);
      buffer.setPriorityAt(50, 21, 0);
      buffer.setPriorityAt(50, 22, 0);
      buffer.setPriorityAt(50, 23, 11);
      expect(buffer.effectivePriorityAt(50, 20), equals(11), reason: 'Barrier line over tree must resolve to tree depth 11');

      // Barrier at bottom of screen with no > 2 below defaults to base priority 4
      for (int y = 0; y < 168; y++) {
        buffer.setPriorityAt(80, y, 0);
      }
      expect(buffer.effectivePriorityAt(80, 0), equals(4));
      expect(buffer.effectivePriorityAt(80, 160), equals(4));
    });

    test('control line classifications', () {
      final buffer = PriorityBuffer();
      buffer.setPriorityAt(10, 10, 0); // Unconditional barrier
      buffer.setPriorityAt(20, 20, 1); // Conditional barrier
      buffer.setPriorityAt(30, 30, 2); // Trigger / Alarm
      buffer.setPriorityAt(40, 40, 3); // Water
      buffer.setPriorityAt(50, 50, 4); // Normal terrain

      expect(buffer.isUnconditionalBarrier(10, 10), isTrue);
      expect(buffer.isControlLine(10, 10), isTrue);
      expect(buffer.isWalkable(10, 10), isFalse);
      expect(buffer.isWalkable(10, 10, allowConditional: true), isFalse);

      expect(buffer.isConditionalBarrier(20, 20), isTrue);
      expect(buffer.isWalkable(20, 20), isFalse);
      expect(buffer.isWalkable(20, 20, allowConditional: true), isTrue);

      expect(buffer.isTrigger(30, 30), isTrue);
      expect(buffer.isControlLine(30, 30), isTrue);
      expect(buffer.isWalkable(30, 30), isTrue);

      expect(buffer.isWater(40, 40), isTrue);
      expect(buffer.isControlLine(40, 40), isTrue);
      expect(buffer.isWalkable(40, 40), isTrue);

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
      buffer.setPriorityAt(0, 0, 0); // Unconditional barrier (Red in control view)

      final rgba = buffer.renderControlMapRgba();
      expect(rgba.length, equals(320 * 200 * 4));

      // Pixel 0,0 in 160x168 expands to x=0 and x=1
      final expectedCol = EgaColors.controlRgbaBytes[0];
      expect(rgba.sublist(0, 4), equals(expectedCol));
      expect(rgba.sublist(4, 8), equals(expectedCol));

      // Pixel at (1, 0) was priority 4 (default non-control), so in 320x200 at x=2 and x=3 it should be transparent
      expect(rgba.sublist(8, 12), equals([0, 0, 0, 0]));
      expect(rgba.sublist(12, 16), equals([0, 0, 0, 0]));
    });
  });
}
