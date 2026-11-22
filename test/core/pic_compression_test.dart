import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/pic_compression.dart';

void main() {
  group('PicDecompressor', () {
    test('decompresses picture stream with nibble-packed color and aligned terminating 0xFF', () {
      final packed = Uint8List.fromList([
        0xF0, // opcode: set visual color (triggers nextHalf)
        0x4F, // high nibble: color 4, low nibble: 0xF
        0xF0, // high nibble: 0xF (combined with low nibble of prev -> 0xFF)
      ]);

      final expandedNoReslen = PicDecompressor.expand(packed);
      final expandedWithReslen = PicDecompressor.expand(packed, expandedNoReslen.length);

      expect(expandedWithReslen, equals(expandedNoReslen));
      expect(expandedNoReslen, equals(Uint8List.fromList([0xF0, 4, 0xFF])));
      expect(expandedNoReslen.last, equals(0xFF));
    });

    test('expand with reslen 0 throws CorruptResourceException', () {
      expect(
        () => PicDecompressor.expand(Uint8List.fromList([0xFF]), 0),
        throwsA(isA<CorruptResourceException>()),
      );
    });

    test('reslen larger than actual output throws CorruptResourceException', () {
      final packed = Uint8List.fromList([0xFF]);
      expect(
        () => PicDecompressor.expand(packed, 10),
        throwsA(isA<CorruptResourceException>()),
      );
    });

    test('reslen smaller than expanded output throws CorruptResourceException', () {
      final packed = Uint8List.fromList([
        0x01,
        0x02,
        0x03,
        0x04,
        0xFF,
      ]);

      expect(
        () => PicDecompressor.expand(packed, 1),
        throwsA(isA<CorruptResourceException>()),
      );
      expect(PicDecompressor.expand(packed), equals(Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0xFF])));
    });
  });
}
