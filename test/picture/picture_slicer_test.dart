import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

void main() {
  group('PictureSlicer Tests', () {
    test('slices visual and priority buffers into 16 320x200 RGBA slices', () {
      final visual = Uint8List(160 * 168);
      visual.fillRange(0, 160 * 168, 15); // all white

      final pri = PriorityBuffer();
      // Band 6 across top half, band 10 across bottom half
      for (int y = 0; y < 84; y++) {
        for (int x = 0; x < 160; x++) {
          pri.setPriorityAt(x, y, 6);
          visual[y * 160 + x] = 2; // Green
        }
      }
      for (int y = 84; y < 168; y++) {
        for (int x = 0; x < 160; x++) {
          pri.setPriorityAt(x, y, 10);
          visual[y * 160 + x] = 4; // Red
        }
      }

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityBuffer: pri,
      );

      expect(slices.length, equals(16));

      // Slice 6 and 10 should have visible pixels; other slices should be empty
      expect(slices[6]!.hasVisiblePixels, isTrue);
      expect(slices[10]!.hasVisiblePixels, isTrue);
      expect(slices[0]!.hasVisiblePixels, isFalse);
      expect(slices[4]!.hasVisiblePixels, isFalse);
      expect(slices[15]!.hasVisiblePixels, isFalse);

      // Verify pixel doubling and colors in slice 6 (top row)
      final slice6Bytes = slices[6]!.rgbaBytes;
      expect(slice6Bytes.length, equals(320 * 200 * 4));

      final greenRgba = EgaColors.rgbaBytes[2];
      // Pixel at x=0 (expands to x=0 and x=1)
      expect(slice6Bytes.sublist(0, 4), equals(greenRgba));
      expect(slice6Bytes.sublist(4, 8), equals(greenRgba));

      // In slice 6, bottom row (y=100) should be transparent
      final bottomRowOffset = (100 * 320 + 0) * 4;
      expect(slice6Bytes.sublist(bottomRowOffset, bottomRowOffset + 4), equals([0, 0, 0, 0]));

      // Lines 168 to 199 should be completely transparent across all slices
      final blankRowOffset = (180 * 320 + 0) * 4;
      expect(slice6Bytes.sublist(blankRowOffset, blankRowOffset + 4), equals([0, 0, 0, 0]));
    });

    test('maps control line pixels to underlying depth priority slice 8', () {
      final visual = Uint8List(160 * 168);
      final pri = PriorityBuffer();

      // Everything is priority 8 (depth band) and color 3 (cyan)
      for (int y = 0; y < 168; y++) {
        for (int x = 0; x < 160; x++) {
          pri.setPriorityAt(x, y, 8);
          visual[y * 160 + x] = 3;
        }
      }

      // Add a barrier control line (pri 2) at (10, 10) with color 6 (brown)
      pri.setPriorityAt(10, 10, 2);
      visual[10 * 160 + 10] = 6;

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityBuffer: pri,
      );

      // Slice 2 should have NO visible pixels because control lines are mapped to underlying depth band 8
      expect(slices[2]!.hasVisiblePixels, isFalse);

      // Slice 8 should have the brown pixel at (10, 10) -> x=20 and x=21 in 320x200
      final slice8Bytes = slices[8]!.rgbaBytes;
      final brownRgba = EgaColors.rgbaBytes[6];
      final offset1 = (10 * 320 + 20) * 4;
      final offset2 = (10 * 320 + 21) * 4;
      expect(slice8Bytes.sublist(offset1, offset1 + 4), equals(brownRgba));
      expect(slice8Bytes.sublist(offset2, offset2 + 4), equals(brownRgba));
    });

    test('King\'s Quest II Picture 9 preserves exact tree bounds without slurping adjacent water', () {
      final visual = Uint8List(160 * 168);
      final pri = PriorityBuffer();

      // Water (priority 3, visual 9) across row 95
      for (int x = 0; x < 160; x++) {
        pri.setPriorityAt(x, 95, 3);
        visual[95 * 160 + x] = 9;
      }

      // Foreground tree at x=40..49 (priority 11, visual 6)
      for (int x = 40; x <= 49; x++) {
        pri.setPriorityAt(x, 95, 11);
        visual[95 * 160 + x] = 6;
      }

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityBuffer: pri,
      );

      final slice11 = slices[11]!;
      final slice11Bytes = slice11.rgbaBytes;

      // In slice 11 at row 95, only x=40..49 (columns 80..99 in 320x200) must be visible
      for (int x = 0; x < 160; x++) {
        final offset = (95 * 320 + (x * 2)) * 4;
        final isVisible = slice11Bytes[offset + 3] > 0;
        if (x >= 40 && x <= 49) {
          expect(isVisible, isTrue, reason: 'Tree pixel at x=$x must be visible in slice 11');
        } else {
          expect(isVisible, isFalse, reason: 'Water pixel at x=$x must NOT be in slice 11');
        }
      }
    });

    test('lowering a pixel priority leaves stale texels unless the old slice is resliced', () {
      final visual = Uint8List(160 * 168);
      visual.fillRange(0, visual.length, 2); // green
      final pri = PriorityBuffer();
      for (int y = 0; y < 168; y++) {
        for (int x = 0; x < 160; x++) {
          pri.setPriorityAt(x, y, 8);
        }
      }

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityBuffer: pri,
      );
      expect(slices[8]!.hasVisiblePixels, isTrue);

      // Lower one pixel from priority 8 to 5
      pri.setPriorityAt(10, 10, 5);
      visual[10 * 160 + 10] = 4; // red

      final newSlice5 = PictureSlicer.sliceSinglePriority(
        visualPixels: visual,
        priorityBuffer: pri,
        priority: 5,
      );
      expect(newSlice5.hasVisiblePixels, isTrue);

      final offset = (10 * 320 + 20) * 4;
      expect(
        slices[8]!.rgbaBytes[offset + 3],
        greaterThan(0),
        reason: 'old slice 8 still holds the previous pixel if not rebuilt',
      );

      final rebuiltSlice8 = PictureSlicer.sliceSinglePriority(
        visualPixels: visual,
        priorityBuffer: pri,
        priority: 8,
      );
      expect(
        rebuiltSlice8.rgbaBytes[offset + 3],
        equals(0),
        reason: 'rebuilt slice 8 must be transparent at the lowered pixel',
      );
    });
  });
}
