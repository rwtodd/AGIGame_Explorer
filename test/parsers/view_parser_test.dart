import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/parsers/view_parser.dart';

Uint8List createSimpleViewData({
  String? description,
  int loopCount = 1,
  int celCount = 1,
  int width = 4,
  int height = 3,
  int transColor = 0,
  List<List<int>>? rowRleBytes,
  bool isMirrored = false,
  int mirrorLoop = 0,
}) {
  final buffer = <int>[];

  // Header: 2 unknown bytes, loopCount, descLoc (uint16)
  buffer.add(1);
  buffer.add(1);
  buffer.add(loopCount);
  buffer.add(0); // descLoc low byte placeholder
  buffer.add(0); // descLoc high byte placeholder

  // Loop directory table: loopCount * 2 bytes
  final loopDirectoryOffset = buffer.length;
  for (var i = 0; i < loopCount; i++) {
    buffer.add(0);
    buffer.add(0);
  }

  final loopOffsets = <int>[];

  // Build Loop 0 (forward cel)
  final loop0Start = buffer.length;
  loopOffsets.add(loop0Start);

  buffer.add(celCount); // cellCount
  // Cel directory table: celCount * 2 bytes
  final celDirStart = buffer.length;
  for (var j = 0; j < celCount; j++) {
    buffer.add(0);
    buffer.add(0);
  }

  for (var j = 0; j < celCount; j++) {
    final celStart = buffer.length;
    final celRelOffset = celStart - loop0Start;
    buffer[celDirStart + (j * 2)] = celRelOffset & 0xFF;
    buffer[celDirStart + (j * 2) + 1] = (celRelOffset >> 8) & 0xFF;

    buffer.add(width);
    buffer.add(height);
    // Cel header: mirroring (0) and transColor
    buffer.add(transColor & 0x0F);

    if (rowRleBytes != null) {
      for (final row in rowRleBytes) {
        buffer.addAll(row);
      }
    } else {
      // Default 4x3 checkerboard:
      // Row 0: 2 pixels color 4, 2 pixels color 1, row end (0)
      // Row 1: 4 pixels color 2, row end (0)
      // Row 2: 2 pixels color 14, 2 transparent (via 0 end of line)
      buffer.addAll([(4 << 4) | 2, (1 << 4) | 2, 0]);
      buffer.addAll([(2 << 4) | 4, 0]);
      buffer.addAll([(14 << 4) | 2, 0]);
    }
  }

  // If loopCount > 1 and isMirrored is true, create loop 1 as mirrored from loop 0
  if (loopCount > 1) {
    for (var l = 1; l < loopCount; l++) {
      final loopLStart = buffer.length;
      loopOffsets.add(loopLStart);

      buffer.add(celCount);
      final celDirLStart = buffer.length;
      for (var j = 0; j < celCount; j++) {
        buffer.add(0);
        buffer.add(0);
      }

      for (var j = 0; j < celCount; j++) {
        final celStart = buffer.length;
        final celRelOffset = celStart - loopLStart;
        buffer[celDirLStart + (j * 2)] = celRelOffset & 0xFF;
        buffer[celDirLStart + (j * 2) + 1] = (celRelOffset >> 8) & 0xFF;

        buffer.add(width);
        buffer.add(height);
        if (isMirrored) {
          // Mirroring flag: bit 3 set (0x08) | mirrorLoop (0) in high nibble
          final mirrorNibble = 0x08 | (mirrorLoop & 0x07);
          buffer.add((mirrorNibble << 4) | (transColor & 0x0F));
          // No pixel bytes follow for mirrored cels
        } else {
          buffer.add(transColor & 0x0F);
          buffer.addAll([(15 << 4) | 4, 0]); // white row
          buffer.addAll([(15 << 4) | 4, 0]);
          buffer.addAll([(15 << 4) | 4, 0]);
        }
      }
    }
  }

  // Write loop offsets into header
  for (var i = 0; i < loopOffsets.length; i++) {
    buffer[loopDirectoryOffset + (i * 2)] = loopOffsets[i] & 0xFF;
    buffer[loopDirectoryOffset + (i * 2) + 1] = (loopOffsets[i] >> 8) & 0xFF;
  }

  // Description string
  if (description != null) {
    final descLoc = buffer.length;
    buffer[3] = descLoc & 0xFF;
    buffer[4] = (descLoc >> 8) & 0xFF;
    buffer.addAll(ascii.encode(description));
    buffer.add(0); // Null terminator
  }

  return Uint8List.fromList(buffer);
}

void main() {
  group('ViewParser', () {
    test('parses single-loop single-cel unmirrored view correctly', () {
      final data = createSimpleViewData(
        description: 'Ego Walking',
        loopCount: 1,
        celCount: 1,
        width: 4,
        height: 3,
        transColor: 0,
      );

      final view = ViewParser.parse(data, viewNumber: 1);

      expect(view.viewNumber, equals(1));
      expect(view.description, equals('Ego Walking'));
      expect(view.loopCount, equals(1));

      final loop0 = view.loops.first;
      expect(loop0.loopNumber, equals(0));
      expect(loop0.celCount, equals(1));
      expect(loop0.maxWidth, equals(4));
      expect(loop0.maxHeight, equals(3));

      final cel0 = loop0.cels.first;
      expect(cel0.width, equals(4));
      expect(cel0.height, equals(3));
      expect(cel0.transparentColor, equals(0));
      expect(cel0.isMirrored, isFalse);

      final pixels = cel0.getPixels(parentView: view);
      expect(pixels.length, equals(12));

      // Row 0: 2 pixels of color 4, 2 pixels of color 1
      expect(pixels.sublist(0, 4), equals([4, 4, 1, 1]));
      // Row 1: 4 pixels of color 2
      expect(pixels.sublist(4, 8), equals([2, 2, 2, 2]));
      // Row 2: 2 pixels of color 14, 2 pixels of transparent (0)
      expect(pixels.sublist(8, 12), equals([14, 14, 0, 0]));
    });

    test('parses multi-loop view with mirrored cells', () {
      final data = createSimpleViewData(
        loopCount: 2,
        celCount: 1,
        width: 4,
        height: 3,
        transColor: 0,
        isMirrored: true,
        mirrorLoop: 0,
      );

      final view = ViewParser.parse(data, viewNumber: 2);
      expect(view.loopCount, equals(2));

      final loop0 = view.loops[0];
      final loop1 = view.loops[1];

      expect(loop0.cels[0].isMirrored, isFalse);
      expect(loop1.cels[0].isMirrored, isTrue);
      expect(loop1.cels[0].mirrorLoop, equals(0));

      // Check unmirrored pixels from loop 0
      final loop0Pixels = loop0.cels[0].getPixels(parentView: view);
      expect(loop0Pixels.sublist(0, 4), equals([4, 4, 1, 1]));

      // Check mirrored pixels from loop 1 (horizontally flipped row by row)
      final loop1Pixels = loop1.cels[0].getPixels(parentView: view, celIndex: 0);
      expect(loop1Pixels.sublist(0, 4), equals([1, 1, 4, 4])); // [4, 4, 1, 1] reversed
      expect(loop1Pixels.sublist(4, 8), equals([2, 2, 2, 2]));
      expect(loop1Pixels.sublist(8, 12), equals([0, 0, 14, 14])); // [14, 14, 0, 0] reversed
    });

    test('renders RGBA buffer with transparency and horizontal scaling', () {
      final data = createSimpleViewData(
        loopCount: 1,
        celCount: 1,
        width: 4,
        height: 3,
        transColor: 0,
      );

      final view = ViewParser.parse(data, viewNumber: 3);
      final cel = view.loops[0].cels[0];

      // 1x scale
      final rgba = cel.toRgba(parentView: view);
      expect(rgba.length, equals(4 * 3 * 4));

      // Row 2, pixel (x=2, y=2) should be transparent (alpha = 0)
      final pixelOffset = (2 * 4 + 2) * 4;
      expect(rgba[pixelOffset + 3], equals(0)); // alpha = 0

      // Row 0, pixel (x=0, y=0) is color 4 (Red) -> alpha = 255, R > 0
      expect(rgba[3], equals(255));
      expect(rgba[0], isPositive); // Red channel

      // 2x horizontal scaling (AGI aspect correction)
      final rgbaScaled = cel.toRgba(parentView: view, scaleX: 2, scaleY: 1);
      expect(rgbaScaled.length, equals(8 * 3 * 4));
    });

    test('throws AgiException on truncated or corrupted data', () {
      expect(
        () => ViewParser.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AgiException>()),
      );

      // Loop offset out of bounds
      final corruptLoop = Uint8List.fromList([
        1, 1, 1, 0, 0,
        255, 255, // loop offset 65535 exceeds file length
      ]);
      expect(
        () => ViewParser.parse(corruptLoop),
        throwsA(isA<AgiException>()),
      );
    });
  });
}
