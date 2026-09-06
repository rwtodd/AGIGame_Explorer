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

    test('slices 320x200 SCI0 visual and priority buffers with 1:1 mapping and pure-Z', () {
      final visual = Uint8List(320 * 200);
      final priority = Uint8List(320 * 200);
      priority.fillRange(0, priority.length, 4);

      // In SCI, priority values 0..3 are pure-Z depth slices (NOT AGI control lines).
      // Place a pixel at (10, 20) with priority 1 (Red)
      visual[20 * 320 + 10] = 4; // Red
      priority[20 * 320 + 10] = 1;

      // Place a pixel at (11, 20) with priority 7 (Green)
      visual[20 * 320 + 11] = 2; // Green
      priority[20 * 320 + 11] = 7;

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityPixels: priority,
        profile: DisplayProfile.sci0,
      );

      expect(slices.length, equals(16));
      expect(slices[1]!.hasVisiblePixels, isTrue);
      expect(slices[7]!.hasVisiblePixels, isTrue);
      expect(slices[0]!.hasVisiblePixels, isFalse);
      expect(slices[4]!.hasVisiblePixels, isTrue);

      final slice1Bytes = slices[1]!.rgbaBytes;
      final redRgba = EgaColors.rgbaBytes[4];

      // Pixel at (10, 20) must be red
      final offset10 = (20 * 320 + 10) * 4;
      expect(slice1Bytes.sublist(offset10, offset10 + 4), equals(redRgba));

      // 1:1 pixel mapping: pixel at (11, 20) must NOT be doubled, must be transparent in slice 1
      final offset11 = (20 * 320 + 11) * 4;
      expect(slice1Bytes.sublist(offset11, offset11 + 4), equals([0, 0, 0, 0]));

      // Slice 7 must have the green pixel at (11, 20)
      final slice7Bytes = slices[7]!.rgbaBytes;
      final greenRgba = EgaColors.rgbaBytes[2];
      expect(slice7Bytes.sublist(offset11, offset11 + 4), equals(greenRgba));
      expect(slice7Bytes.sublist(offset10, offset10 + 4), equals([0, 0, 0, 0]));
    });

    test('supports custom packed RGBA palette for undithered SCI mode', () {
      final visual = Uint8List(320 * 200);
      final priority = Uint8List(320 * 200);
      priority.fillRange(0, priority.length, 4);

      // Create a 40-color palette where index 25 is a custom 32-bit packed color (e.g. 0xFF112233)
      final customPalette = List<int>.filled(40, 0);
      customPalette[25] = 0xFF112233;

      visual[50 * 320 + 100] = 25;
      priority[50 * 320 + 100] = 9;

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityPixels: priority,
        profile: DisplayProfile.sci0,
        paletteRgbaPacked: customPalette,
      );

      final slice9View = ByteData.sublistView(slices[9]!.rgbaBytes);
      final readPacked = slice9View.getUint32((50 * 320 + 100) * 4, Endian.host);
      expect(readPacked, equals(0xFF112233));
    });

    test('sliceSinglePriority works with DisplayProfile.sci0', () {
      final visual = Uint8List(320 * 200);
      final priority = Uint8List(320 * 200);
      priority.fillRange(0, priority.length, 4);

      visual[15 * 320 + 30] = 5; // Magenta
      priority[15 * 320 + 30] = 3;

      final singleSlice3 = PictureSlicer.sliceSinglePriority(
        visualPixels: visual,
        priorityPixels: priority,
        priority: 3,
        profile: DisplayProfile.sci0,
      );

      expect(singleSlice3.hasVisiblePixels, isTrue);
      final offset = (15 * 320 + 30) * 4;
      expect(singleSlice3.rgbaBytes.sublist(offset, offset + 4), equals(EgaColors.rgbaBytes[5]));

      // Empty slice returns hasVisiblePixels: false
      final emptySlice0 = PictureSlicer.sliceSinglePriority(
        visualPixels: visual,
        priorityPixels: priority,
        priority: 0,
        profile: DisplayProfile.sci0,
      );
      expect(emptySlice0.hasVisiblePixels, isFalse);
    });

    test('throws ArgumentError if neither priorityBuffer nor priorityPixels is provided', () {
      final visual = Uint8List(160 * 168);
      expect(
        () => PictureSlicer.slice(visualPixels: visual),
        throwsArgumentError,
      );
      expect(
        () => PictureSlicer.sliceSinglePriority(
          visualPixels: visual,
          priority: 5,
        ),
        throwsArgumentError,
      );
    });
  });
}
