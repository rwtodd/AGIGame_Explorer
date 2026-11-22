import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';
import 'package:flutter_agigame/sci/view/sci_view_parser.dart';

/// Builds a minimal SCI0 EGA VIEW.
///
/// Unmirrored loops each get their own copy of [rle] (or the default 4×2
/// checker). Loops whose bit is set in [mirrorBits] share loop 0's directory
/// offset, matching PQ2 (e.g. view 0 loop 1).
///
/// When [paletteBytes] is given, it is appended after all cel data and the
/// header paletteOffset word points at it (SCI1-EGA 8x16 EGA mapping table).
Uint8List createSciEgaViewData({
  int loopCount = 1,
  int celCount = 1,
  int width = 4,
  int height = 2,
  int clearKey = 0,
  int mirrorBits = 0,
  int displaceX = 0,
  int displaceY = 0,
  int flags = 0,
  int version = 0,
  List<int>? rle,
  List<int>? paletteBytes,
  int? paletteOffset,
}) {
  final payload = rle ?? const [0x24, 0x21, 0x42]; // 4,4,1,1 / 2,2,2,2
  final dx = displaceX & 0xFF;

  final header = <int>[
    loopCount,
    flags,
    mirrorBits & 0xFF,
    (mirrorBits >> 8) & 0xFF,
    version & 0xFF,
    (version >> 8) & 0xFF,
    0,
    0, // paletteOffset
  ];

  // Loop directory placeholders.
  final loopDirStart = header.length;
  for (var i = 0; i < loopCount; i++) {
    header.add(0);
    header.add(0);
  }

  final loopOffsets = List<int>.filled(loopCount, 0);
  int? sharedOffset;

  for (var loopNo = 0; loopNo < loopCount; loopNo++) {
    final isMirror = (mirrorBits & (1 << loopNo)) != 0;
    if (isMirror && sharedOffset != null) {
      loopOffsets[loopNo] = sharedOffset;
      continue;
    }

    final loopStart = header.length;
    loopOffsets[loopNo] = loopStart;
    if (!isMirror) {
      sharedOffset ??= loopStart;
    }

    header.add(celCount & 0xFF);
    header.add((celCount >> 8) & 0xFF);
    header.add(0);
    header.add(0); // unknown
    final celDirStart = header.length;
    for (var c = 0; c < celCount; c++) {
      header.add(0);
      header.add(0);
    }

    for (var c = 0; c < celCount; c++) {
      final celStart = header.length;
      header[celDirStart + c * 2] = celStart & 0xFF;
      header[celDirStart + c * 2 + 1] = (celStart >> 8) & 0xFF;
      header.add(width & 0xFF);
      header.add((width >> 8) & 0xFF);
      header.add(height & 0xFF);
      header.add((height >> 8) & 0xFF);
      header.add(dx);
      header.add(displaceY & 0xFF);
      header.add(clearKey & 0x0F);
      header.addAll(payload);
    }
  }

  for (var i = 0; i < loopCount; i++) {
    header[loopDirStart + i * 2] = loopOffsets[i] & 0xFF;
    header[loopDirStart + i * 2 + 1] = (loopOffsets[i] >> 8) & 0xFF;
  }

  if (paletteBytes != null) {
    final offset = paletteOffset ?? header.length;
    header[6] = offset & 0xFF;
    header[7] = (offset >> 8) & 0xFF;
    header.addAll(paletteBytes);
  } else if (paletteOffset != null) {
    header[6] = paletteOffset & 0xFF;
    header[7] = (paletteOffset >> 8) & 0xFF;
  }

  return Uint8List.fromList(header);
}

void main() {
  group('SciViewParser synthetic kViewEga', () {
    test('decodes inverted-nibble RLE into native 320-space pixels', () {
      final view = SciViewParser.parse(
        createSciEgaViewData(),
        viewNumber: 7,
      );

      expect(view.viewNumber, 7);
      expect(view.isSci, isTrue);
      expect(view.pixelScaleX, 1);
      expect(view.loopCount, 1);
      expect(view.totalCelsCount, 1);

      final cel = view.getCel(0, 0)!;
      expect(cel.width, 4);
      expect(cel.height, 2);
      expect(cel.transparentColor, 0);
      expect(cel.isMirrored, isFalse);
      expect(cel.getUnflippedPixels(), equals([4, 4, 1, 1, 2, 2, 2, 2]));
    });

    test('mirrors share the source loop offset and negate displaceX', () {
      final data = createSciEgaViewData(
        loopCount: 2,
        mirrorBits: 0x2,
        displaceX: 6,
        displaceY: 3,
      );
      final view = SciViewParser.parse(data, viewNumber: 0);

      expect(view.mirrorBits, 0x2);
      expect(view.loopCount, 2);

      final src = view.getCel(0, 0)!;
      expect(src.isMirrored, isFalse);
      expect(src.displaceX, 6);
      expect(src.displaceY, 3);
      expect(src.rawPixels, isNotNull);

      final mirrored = view.getCel(1, 0)!;
      expect(mirrored.isMirrored, isTrue);
      expect(mirrored.mirrorLoop, 0);
      expect(mirrored.displaceX, -6);
      expect(mirrored.displaceY, 3);
      expect(mirrored.rawPixels, isNull);

      expect(
        mirrored.getUnflippedPixels(parentView: view),
        equals(src.getUnflippedPixels()),
      );
      expect(
        mirrored.getPixels(parentView: view),
        equals([1, 1, 4, 4, 2, 2, 2, 2]),
      );
    });

    test('stores signed displaceX from the cel header', () {
      final view = SciViewParser.parse(
        createSciEgaViewData(displaceX: -2, displaceY: 1),
      );
      final cel = view.getCel(0, 0)!;
      expect(cel.displaceX, -2);
      expect(cel.displaceY, 1);
    });

    test('rejects VGA-in-EGA views (flags 0x80, bit-tested)', () {
      expect(
        () => SciViewParser.parse(createSciEgaViewData(flags: 0x80)),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('rejects VGA-in-EGA views (flags 0xC0 sets bit 0x80 too)', () {
      expect(
        () => SciViewParser.parse(createSciEgaViewData(flags: 0xC0)),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('remaps cel pixels through the SCI1-EGA mapping (table 0)', () {
      // mapping[0] swaps 4 -> 9 and 1 -> 2, leaves others; rest straight.
      final mapping0 = List<int>.generate(16, (i) => i);
      mapping0[4] = 9;
      mapping0[1] = 2;
      final palette = <int>[];
      for (var t = 0; t < 8; t++) {
        palette.addAll(t == 0 ? mapping0 : List<int>.generate(16, (i) => i));
      }
      // Default RLE decodes to [4,4,1,1, 2,2,2,2]; clearKey 0 is untouched
      // by the mapping, so no pixel becomes transparent through remapping.
      final view = SciViewParser.parse(
        createSciEgaViewData(paletteBytes: palette),
        viewNumber: 3,
      );

      final cel = view.getCel(0, 0)!;
      expect(cel.transparentColor, 0);
      expect(cel.getUnflippedPixels(), equals([9, 9, 2, 2, 2, 2, 2, 2]));
    });

    test('remapped pixels are compared to clearKey after mapping', () {
      // mapping[0] sends color 4 to 0; with clearKey 0 those pixels become
      // transparent downstream (toRgba alpha 0), matching ScummVM's
      // `if (color != clearKey)` on the mapped color.
      final mapping0 = List<int>.generate(16, (i) => i);
      mapping0[4] = 0;
      final palette = <int>[];
      for (var t = 0; t < 8; t++) {
        palette.addAll(t == 0 ? mapping0 : List<int>.generate(16, (i) => i));
      }
      final view = SciViewParser.parse(
        createSciEgaViewData(clearKey: 0, paletteBytes: palette),
      );

      final cel = view.getCel(0, 0)!;
      expect(cel.getUnflippedPixels(), equals([0, 0, 1, 1, 2, 2, 2, 2]));
      // Downstream transparency check: remapped 0 == clearKey yet only the
      // first two pixels are transparent; original clearKey pixels also 0.
      final rgba = cel.toRgba();
      expect(rgba[0 * 4 + 3], 0);
      expect(rgba[1 * 4 + 3], 0);
      expect(rgba[2 * 4 + 3], 255);
    });

    test('ignores an all-straight mapping table', () {
      final palette = <int>[];
      for (var t = 0; t < 8; t++) {
        palette.addAll(List<int>.generate(16, (i) => i));
      }
      final view = SciViewParser.parse(
        createSciEgaViewData(paletteBytes: palette),
      );
      final cel = view.getCel(0, 0)!;
      expect(cel.getUnflippedPixels(), equals([4, 4, 1, 1, 2, 2, 2, 2]));
    });

    test('ignores paletteOffset 0 and 0x100 even with table bytes present', () {
      final mapping0 = List<int>.generate(16, (i) => i);
      mapping0[4] = 9;
      final palette = <int>[];
      for (var t = 0; t < 8; t++) {
        palette.addAll(t == 0 ? mapping0 : List<int>.generate(16, (i) => i));
      }
      for (final offset in [0, 0x100]) {
        final view = SciViewParser.parse(
          createSciEgaViewData(paletteBytes: palette, paletteOffset: offset),
        );
        final cel = view.getCel(0, 0)!;
        expect(view.paletteOffset, offset);
        expect(cel.getUnflippedPixels(), equals([4, 4, 1, 1, 2, 2, 2, 2]));
      }
    });

    test('rejects SCI1.1 views (version word 1)', () {
      expect(
        () => SciViewParser.parse(createSciEgaViewData(version: 1)),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('throws on truncated headers', () {
      expect(
        () => SciViewParser.parse(Uint8List.fromList([1, 0, 0])),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('parses an empty stub view (loopCount 0)', () {
      final view = SciViewParser.parse(Uint8List(8), viewNumber: 140);
      expect(view.loopCount, 0);
      expect(view.totalCelsCount, 0);
      expect(view.loops, isEmpty);
    });
  });
}
