import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/decompressor_lzw.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciDecompressorLZW Tests', () {
    test('returns empty byte array for decompSize <= 0', () {
      final res = SciDecompressorLZW.decompress(Uint8List(0), 0);
      expect(res, isEmpty);
    });

    test('decompresses simple literal sequence', () {
      // Encode "ABC":
      // Code for 'A' (65) in 9 bits (LSB): 0b001000001
      // Code for 'B' (66) in 9 bits (LSB): 0b001000010
      // Terminator (257) in 9 bits (LSB): 0b100000001
      // Bitstream (27 bits):
      // 65:  001000001
      // 66:  001000010
      // 257: 100000001
      // Pack into bytes:
      // bits 0..7 of code 65: 65 (0x41)
      // bit 8 of code 65 (0) + bits 0..6 of code 66 (0b1000010): 0 | (0x42 << 1) = 0x84
      // bit 7..8 of code 66 (0) + bits 0..5 of 257 (0b000001): (1 << 2) = 0x04
      // bits 6..8 of 257 (0b100 = 4): 4
      final src = Uint8List.fromList([0x41, 0x84, 0x04, 0x04]);
      final decomp = SciDecompressorLZW.decompress(src, 2);
      expect(decomp, equals(Uint8List.fromList([65, 66])));
    });

    test('handles table reset code 256', () {
      // Code 65 ('A'), then code 256 (reset), then code 66 ('B'), then 257 (terminator)
      // 9-bit codes: [65, 256, 66, 257]
      // 36 bits total = 5 bytes
      final writer = _TestBitWriterLSB();
      writer.writeBits(65, 9);
      writer.writeBits(256, 9);
      writer.writeBits(66, 9);
      writer.writeBits(257, 9);
      final src = writer.toBytes();

      final decomp = SciDecompressorLZW.decompress(src, 2);
      expect(decomp, equals(Uint8List.fromList([65, 66])));
    });

    test('reconstructs repeated strings using dictionary entries', () {
      // Encode "ABAB":
      // 1. Code 65 ('A') -> emits 'A'. Table entry 258 defined (will be "AB").
      // 2. Code 66 ('B') -> emits 'B'. Table entry 259 defined.
      // 3. Code 258 -> emits "AB".
      // 4. Code 257 -> terminator.
      final writer = _TestBitWriterLSB();
      writer.writeBits(65, 9);
      writer.writeBits(66, 9);
      writer.writeBits(258, 9);
      writer.writeBits(257, 9);
      final src = writer.toBytes();

      final decomp = SciDecompressorLZW.decompress(src, 4);
      expect(decomp, equals(Uint8List.fromList([65, 66, 65, 66])));
    });

    test('throws SciDecompressionException on code exceeding table size', () {
      final writer = _TestBitWriterLSB();
      writer.writeBits(300, 9); // Table size starts at 258, so 300 is invalid
      final src = writer.toBytes();

      expect(
        () => SciDecompressorLZW.decompress(src, 10),
        throwsA(isA<SciDecompressionException>()),
      );
    });

    test('throws SciDecompressionException on size mismatch without terminator', () {
      final writer = _TestBitWriterLSB();
      writer.writeBits(65, 9); // only 1 byte written, expected 10
      final src = writer.toBytes();

      expect(
        () => SciDecompressorLZW.decompress(src, 10),
        throwsA(isA<SciDecompressionException>()),
      );
    });
  });
}

class _TestBitWriterLSB {
  final List<int> _bytes = [];
  int _buffer = 0;
  int _bits = 0;

  void writeBits(int value, int count) {
    _buffer |= (value & ((1 << count) - 1)) << _bits;
    _bits += count;
    while (_bits >= 8) {
      _bytes.add(_buffer & 0xFF);
      _buffer >>>= 8;
      _bits -= 8;
    }
  }

  Uint8List toBytes() {
    if (_bits > 0) {
      _bytes.add(_buffer & 0xFF);
      _buffer = 0;
      _bits = 0;
    }
    return Uint8List.fromList(_bytes);
  }
}
