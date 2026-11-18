import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/lzw_decompression.dart';

void main() {
  group('LzwDecompressor', () {
    test('decompresses simple literal sequence with clear and eof codes', () {
      // 9-bit bitstream containing:
      // Clear code (256 = 0x100) -> 9 bits
      // Literal 'A' (65 = 0x41)  -> 9 bits
      // Literal 'B' (66 = 0x42)  -> 9 bits
      // Literal 'C' (67 = 0x43)  -> 9 bits
      // EOF code (257 = 0x101)   -> 9 bits
      // Total 45 bits -> 6 bytes
      final codes = [256, 65, 66, 67, 257];
      var bitBuffer = 0;
      var bitCount = 0;
      final bytes = <int>[];

      for (final code in codes) {
        bitBuffer |= (code << bitCount);
        bitCount += 9;
        while (bitCount >= 8) {
          bytes.add(bitBuffer & 0xFF);
          bitBuffer >>= 8;
          bitCount -= 8;
        }
      }
      if (bitCount > 0) {
        bytes.add(bitBuffer & 0xFF);
      }

      final compressed = Uint8List.fromList(bytes);
      final expanded = LzwDecompressor.expand(compressed, 3);
      expect(expanded, equals(Uint8List.fromList([65, 66, 67])));
    });

    test('throws AgiException when EOF arrives before expandedSize is reached', () {
      // Codes [256, 65, 257] with expandedSize 3: only one byte is produced
      // before EOF, so the decoder must throw rather than returning it short.
      final codes = [256, 65, 257];
      var bitBuffer = 0;
      var bitCount = 0;
      final bytes = <int>[];

      for (final code in codes) {
        bitBuffer |= (code << bitCount);
        bitCount += 9;
        while (bitCount >= 8) {
          bytes.add(bitBuffer & 0xFF);
          bitBuffer >>= 8;
          bitCount -= 8;
        }
      }
      if (bitCount > 0) {
        bytes.add(bitBuffer & 0xFF);
      }

      final compressed = Uint8List.fromList(bytes);
      expect(
        () => LzwDecompressor.expand(compressed, 3),
        throwsA(isA<AgiException>()),
      );
    });

    test('round-trips literal stream across code-width growth (9 -> 10 bits)', () {
      // Write clear, then 260 literals, then EOF, packing with the same
      // width-growth rule the decoder uses (width increases when hi reaches
      // overflow; clear resets width/hi/overflow and does not advance hi).
      // hi starts at 257 with overflow 512, so the 255th literal pushes hi
      // to 512 and the following codes are packed at 10 bits.
      final writer = _AgiLzwWriter();
      writer.writeCode(256); // clear
      final literals = List<int>.generate(260, (_) => 65);
      for (final literal in literals) {
        writer.writeCode(literal);
      }
      writer.writeCode(257); // EOF

      final compressed = writer.toBytes();
      final expanded = LzwDecompressor.expand(compressed, 260);
      expect(expanded, equals(Uint8List.fromList(literals)));
    });
  });
}

class _AgiLzwWriter {
  int _bitBuffer = 0;
  int _bitCount = 0;
  final List<int> _bytes = [];

  int _width = 9;
  int _hi = 257;
  int _overflow = 1 << 9;

  void writeCode(int code) {
    _bitBuffer |= (code << _bitCount);
    _bitCount += _width;
    while (_bitCount >= 8) {
      _bytes.add(_bitBuffer & 0xFF);
      _bitBuffer >>= 8;
      _bitCount -= 8;
    }

    if (code == 256) {
      _width = 9;
      _hi = 257;
      _overflow = 1 << 9;
      return;
    }
    if (code == 257) {
      return;
    }
    _hi++;
    if (_hi >= _overflow) {
      _width++;
      _overflow <<= 1;
    }
  }

  Uint8List toBytes() {
    if (_bitCount > 0) {
      _bytes.add(_bitBuffer & 0xFF);
    }
    return Uint8List.fromList(_bytes);
  }
}
