import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/sci/font/sci_font_parser.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('Police Quest 2 FONT integration', () {
    late SciVolumeManager vm;

    setUp(() {
      vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    });

    test('parses all 5 PQ2 fonts with expected heights and 128 glyphs', () {
      final entries = vm.resourceMap.entriesForType(SciResourceType.font);
      expect(entries.length, 5);

      final expectedHeights = {
        0: 8,
        1: 12,
        4: 9,
        7: 8,
        999: 8,
      };

      for (final entry in entries) {
        final fontNum = entry.id.number;
        final raw = vm.getResourceById(entry.id);
        final font = SciFontParser.parse(raw, fontNumber: fontNum);

        expect(font.fontNumber, fontNum);
        expect(font.numChars, 128);
        expect(font.validGlyphCount, 128);
        expect(font.fontHeight, expectedHeights[fontNum], reason: 'Font $fontNum height');
      }
    });

    test('Font 0 (SYSFONT / Chicago 12) glyph properties and special UI characters', () {
      final raw = vm.getResource(SciResourceType.font, 0);
      final font = SciFontParser.parse(raw, fontNumber: 0);

      expect(SierraFont.standardFontName(font.fontNumber), contains('SYSFONT'));

      // Standard ASCII characters
      final glyphA = font.getGlyph(65)!; // 'A'
      expect(glyphA.width, 7);
      expect(glyphA.height, 9);
      expect(glyphA.isPixelSet(3, 0), isTrue); // apex of 'A'

      final glyphLowerA = font.getGlyph(97)!; // 'a'
      expect(glyphLowerA.width, 7);
      expect(glyphLowerA.height, 9);

      final glyphSpace = font.getGlyph(32)!; // ' '
      expect(glyphSpace.width, 5);
      expect(glyphSpace.height, 9);
      // Space has 0 ink pixels
      var spaceInk = 0;
      for (var y = 0; y < glyphSpace.height; y++) {
        for (var x = 0; x < glyphSpace.width; x++) {
          if (glyphSpace.isPixelSet(x, y)) spaceInk++;
        }
      }
      expect(spaceInk, 0);

      // Special Sierra UI glyphs
      final glyphCursor = font.getGlyph(0)!; // solid block cursor
      expect(glyphCursor.width, 10);
      expect(glyphCursor.height, 8);

      final glyphAlt = font.getGlyph(2)!; // 'ALT' key icon
      expect(glyphAlt.width, 11);
      expect(glyphAlt.height, 7);

      final glyphCtrl = font.getGlyph(3)!; // 'CTRL' key icon
      expect(glyphCtrl.width, 19);
      expect(glyphCtrl.height, 8);
    });

    test('Font 1 (USERFONT / New York 12) serif glyph properties', () {
      final raw = vm.getResource(SciResourceType.font, 1);
      final font = SciFontParser.parse(raw, fontNumber: 1);

      expect(SierraFont.standardFontName(font.fontNumber), contains('USERFONT'));
      expect(font.fontHeight, 12);

      final glyphA = font.getGlyph(65)!;
      expect(glyphA.width, 8);
      expect(glyphA.height, 8);

      final glyphLowerA = font.getGlyph(97)!;
      expect(glyphLowerA.width, 6);
      expect(glyphLowerA.height, 9);
    });

    test('measures and renders sample text correctly', () {
      final raw = vm.getResource(SciResourceType.font, 0);
      final font = SciFontParser.parse(raw, fontNumber: 0);

      const message = 'Police Quest 2';
      final width = font.measureTextWidth(message);
      expect(width, greaterThan(80));
      expect(width, lessThan(150));

      final rgba = font.renderTextToRgba(message);
      final renderHeight = font.measureRenderedTextHeight(message);
      expect(renderHeight, greaterThan(font.fontHeight)); // FONT 0 glyphs are 9px, advance is 8
      expect(rgba.length, width * renderHeight * 4);

      // Multi-line text
      const multiLine = 'Lytton Police Department\nOfficer Sonny Bonds';
      final multiHeight = font.measureTextHeight(multiLine, lineSpacing: 2);
      expect(multiHeight, 8 * 2 + 2); // 18 pixels
    });
  });
}
