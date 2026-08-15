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

    test('maps control line pixels to effective depth priority slice', () {
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

      // Slice 2 should have NO visible pixels because the barrier is mapped to depth band 8
      expect(slices[2]!.hasVisiblePixels, isFalse);

      // Slice 8 should have the brown pixel at (10, 10) -> x=20 and x=21 in 320x200
      final slice8Bytes = slices[8]!.rgbaBytes;
      final brownRgba = EgaColors.rgbaBytes[6];
      final offset1 = (10 * 320 + 20) * 4;
      final offset2 = (10 * 320 + 21) * 4;
      expect(slice8Bytes.sublist(offset1, offset1 + 4), equals(brownRgba));
      expect(slice8Bytes.sublist(offset2, offset2 + 4), equals(brownRgba));
    });
  });
}
