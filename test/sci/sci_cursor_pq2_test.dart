import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor_parser.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('Police Quest 2 CURSOR integration', () {
    late SciVolumeManager vm;

    setUp(() {
      vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    });

    test('finds and parses all CURSOR resources in PQ2', () {
      final entries = vm.resourceMap.entriesForType(SciResourceType.cursor);
      expect(entries.length, 2);

      final cursorIds = entries.map((e) => e.id.number).toList()..sort();
      expect(cursorIds, [997, 999]);

      for (final entry in entries) {
        final raw = vm.getResourceById(entry.id);
        expect(raw.length, 68);

        final cursor = SciCursorParser.parse(raw, cursorNumber: entry.id.number);
        expect(cursor.cursorNumber, entry.id.number);
        expect(cursor.width, 16);
        expect(cursor.height, 16);
      }
    });

    test('Cursor 999 (standard arrow pointer) has expected layout and hotspot', () {
      final raw = vm.getResource(SciResourceType.cursor, 999);
      final cursor = SciCursorParser.parse(raw, cursorNumber: 999);

      expect(SierraCursor.standardCursorName(cursor.cursorNumber), contains('Arrow'));
      expect(cursor.hotspotX, 0);
      expect(cursor.hotspotY, 0);

      // (0, 0) should be black tip of the arrow
      expect(cursor.getPixel(0, 0), SierraCursorPixel.black);

      // (1, 1) should be white interior of the arrow
      expect(cursor.getPixel(1, 1), SierraCursorPixel.white);

      // (15, 15) should be transparent background
      expect(cursor.getPixel(15, 15), SierraCursorPixel.transparent);

      // Count pixels of each type
      var blackCount = 0;
      var whiteCount = 0;
      var transparentCount = 0;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final p = cursor.getPixel(x, y);
          if (p == SierraCursorPixel.black) blackCount++;
          if (p == SierraCursorPixel.white) whiteCount++;
          if (p == SierraCursorPixel.transparent) transparentCount++;
        }
      }

      // Sierra arrow has a solid black outline with white interior, surrounded by transparent pixels
      expect(blackCount, greaterThan(20));
      expect(whiteCount, greaterThan(15));
      expect(transparentCount, greaterThan(150));
      expect(blackCount + whiteCount + transparentCount, 256);

      // RGBA conversion
      final rgba = cursor.toRgba();
      expect(rgba.length, 16 * 16 * 4);
    });

    test('Cursor 997 (crosshair / target reticle) has expected layout', () {
      final raw = vm.getResource(SciResourceType.cursor, 997);
      final cursor = SciCursorParser.parse(raw, cursorNumber: 997);

      expect(SierraCursor.standardCursorName(cursor.cursorNumber), contains('Crosshair'));
      expect(cursor.width, 16);
      expect(cursor.height, 16);

      // Check pixel distribution
      var nonTransparent = 0;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          if (cursor.getPixel(x, y) != SierraCursorPixel.transparent) {
            nonTransparent++;
          }
        }
      }
      expect(nonTransparent, greaterThan(20));

      final rgba = cursor.toRgba(scale: 2);
      expect(rgba.length, 32 * 32 * 4);
    });
  });
}
