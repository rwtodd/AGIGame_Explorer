import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';
import 'package:flutter_agigame/picture/pic_pen.dart';

void main() {
  group('PenPattern Tests', () {
    test('SolidPenPattern yields true for all iterations', () {
      const pattern = SolidPenPattern();
      expect(pattern.takesArgument, isFalse);
      expect(() => pattern.setPattern(5), throwsUnsupportedError);

      final it = pattern.createIterator();
      for (int i = 0; i < 50; i++) {
        expect(it.moveNext(), isTrue);
        expect(it.current, isTrue);
      }
    });

    test('SplatterPattern generates expected LFSR sequence for pattern 0', () {
      final pattern = SplatterPattern(0);
      expect(pattern.takesArgument, isTrue);

      final it = pattern.createIterator();
      final results = <bool>[];
      for (int i = 0; i < 16; i++) {
        it.moveNext();
        results.add(it.current);
      }

      // First few values generated from (0 | 1) with 0xB8 polynomial
      expect(results.length, equals(16));
      expect(results.contains(true), isTrue);
      expect(results.contains(false), isTrue);
    });

    test('SplatterPattern responds to setPattern', () {
      final pattern = SplatterPattern();
      pattern.setPattern(0x42);

      final it1 = pattern.createIterator();
      final seq1 = [for (int i = 0; i < 10; i++) it1.moveNext() ? it1.current : false];

      pattern.setPattern(0x99);
      final it2 = pattern.createIterator();
      final seq2 = [for (int i = 0; i < 10; i++) it2.moveNext() ? it2.current : false];

      expect(seq1, isNot(equals(seq2)));
    });
  });

  group('RectanglePen Tests', () {
    test('computes width, height, and offsets for all size classes 0..7', () {
      final pen = RectanglePen();
      for (int sz = 0; sz <= 7; sz++) {
        pen.size = sz;
        expect(pen.width, equals(sz + 1));
        expect(pen.height, equals(sz * 2 + 1));
        expect(pen.verticalOffset, equals(sz));
        expect(pen.horizontalOffset, equals((sz + 1) ~/ 2));
      }
    });

    test('drawAt draws solid rectangle into plot callback', () {
      final pen = RectanglePen()..size = 2; // width=3, height=5
      final plotted = <String>{};

      pen.drawAt((x, y) => plotted.add('$x,$y'), 50, 50, SolidPenPattern.instance);

      // horizontal offset = 3 ~/ 2 = 1 -> left = 50 - 1 = 49 (cols 49, 50, 51)
      // vertical offset = 2 -> top = 50 - 2 = 48 (rows 48, 49, 50, 51, 52)
      expect(plotted.length, equals(3 * 5));
      for (int y = 48; y <= 52; y++) {
        for (int x = 49; x <= 51; x++) {
          expect(plotted.contains('$x,$y'), isTrue);
        }
      }
    });

    test('drawAt clamps to screen edges', () {
      final pen = RectanglePen()..size = 2; // width=3, height=5
      final plotted = <String>{};

      // Near top-left (0, 0)
      pen.drawAt((x, y) => plotted.add('$x,$y'), 0, 0, SolidPenPattern.instance);
      expect(plotted.length, equals(15));
      for (int y = 0; y < 5; y++) {
        for (int x = 0; x < 3; x++) {
          expect(plotted.contains('$x,$y'), isTrue);
        }
      }
    });
  });

  group('CirclePen Tests', () {
    test('computes width, height, and offsets for all size classes 0..7', () {
      final pen = CirclePen();
      for (int sz = 0; sz <= 7; sz++) {
        pen.size = sz;
        expect(pen.width, equals(sz + 1));
        expect(pen.height, equals(sz * 2 + 1));
        expect(pen.verticalOffset, equals(sz));
        expect(pen.horizontalOffset, equals((sz + 1) ~/ 2));
      }
    });

    test('drawAt size 0 draws single point', () {
      final pen = CirclePen()..size = 0;
      final plotted = <String>{};
      pen.drawAt((x, y) => plotted.add('$x,$y'), 25, 30, SolidPenPattern.instance);
      expect(plotted, equals({'25,30'}));
    });

    test('V3CirclePen modifies size 1 circle rasterization', () {
      final v2Pen = CirclePen()..size = 1;
      final v3Pen = V3CirclePen()..size = 1;

      final v2Plotted = <String>{};
      final v3Plotted = <String>{};

      v2Pen.drawAt((x, y) => v2Plotted.add('$x,$y'), 50, 50, SolidPenPattern.instance);
      v3Pen.drawAt((x, y) => v3Plotted.add('$x,$y'), 50, 50, SolidPenPattern.instance);

      // V2 size 1 circle has 3 rows with 2 pixels each = 6 pixels
      expect(v2Plotted.length, equals(6));
      // V3 size 1 circle only draws row 1 = 2 pixels
      expect(v3Plotted.length, equals(2));
      expect(v3Plotted.contains('49,50'), isTrue);
      expect(v3Plotted.contains('50,50'), isTrue);
    });
  });
}
