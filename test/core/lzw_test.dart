import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
