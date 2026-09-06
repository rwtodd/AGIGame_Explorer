import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/decompressor_huffman.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciDecompressorHuffman Tests', () {
    test('returns empty byte array for decompSize <= 0', () {
      final res = SciDecompressorHuffman.decompress(Uint8List(0), 0);
      expect(res, isEmpty);
    });

    test('throws on payload too short (< 2 bytes)', () {
      expect(
        () => SciDecompressorHuffman.decompress(Uint8List.fromList([0x01]), 5),
        throwsA(isA<SciDecompressionException>()),
      );
    });

    test('throws when node table exceeds payload size', () {
      // numNodes = 10 (needs 20 bytes), but payload only has 2 bytes total
      final src = Uint8List.fromList([10, 0x00]);
      expect(
        () => SciDecompressorHuffman.decompress(src, 5),
        throwsA(isA<SciDecompressionException>()),
      );
    });

    test('decompresses simple tree with 0 (A) and 1 (B)', () {
      // 3 nodes (6 bytes):
      // Root (node 0): nodes[0]=0, nodes[1]=0x12 (bit 0 -> next 1 (node 1), bit 1 -> next 2 (node 2))
      // Node 1 (left):  nodes[2]='A'(65), nodes[3]=0 (leaf)
      // Node 2 (right): nodes[4]='B'(66), nodes[5]=0 (leaf)
      // Header:
      // byte 0: numNodes = 3
      // byte 1: terminator byte = 0xFF (so terminator is 0x1FF)
      // Nodes: [0, 0x12, 65, 0, 66, 0]
      // Bitstream for "ABBA" (bits: 0, 1, 1, 0, then pad 4 bits):
      // MSB bit sequence: 0b01100000 = 0x60
      final src = Uint8List.fromList([
        3, 0xFF, // numNodes, terminator
        0, 0x12, // root
        65, 0, // left leaf ('A')
        66, 0, // right leaf ('B')
        0x60, // bitstream
      ]);

      final dest = SciDecompressorHuffman.decompress(src, 4);
      expect(dest, equals(Uint8List.fromList([65, 66, 66, 65])));
    });

    test('terminates early when terminator token is encountered via escape byte', () {
      // Root (node 0): bit 0 -> node 1 ('A'), bit 1 -> escape (lower nibble = 0)
      // Header: numNodes = 2, terminator byte = 0x42 ('B' -> 0x142)
      // Nodes:
      // Node 0: nodes[0]=0, nodes[1]=0x10 (bit 0 -> next 1, bit 1 -> next 0: escape!)
      // Node 1: nodes[2]='A'(65), nodes[3]=0 (leaf)
      // Stream:
      // 1. Bit 0 -> emits 'A'
      // 2. Bit 1 -> escape! Reads 8 bits: 0x42 ('B' | 0x100 = 0x142 == terminator) -> terminates!
      // Bitstream MSB:
      // Bit 0, then Bit 1, followed by 8 bits of 0x42:
      // 0b01_01000010_000000 ->
      // Byte 1: bits 0, 1, 0, 1, 0, 0, 0, 0 = 0b01010000 = 0x50
      // Byte 2: bits 1, 0, 0, 0, 0, 0, 0, 0 = 0b10000000 = 0x80
      final src = Uint8List.fromList([
        2, 0x42, // numNodes=2, terminator=0x42
        0, 0x10, // root: bit 0 -> node 1, bit 1 -> escape
        65, 0, // node 1: 'A'
        0x50, 0x80, // bitstream
      ]);

      final dest = SciDecompressorHuffman.decompress(src, 1);
      expect(dest, equals(Uint8List.fromList([65])));
    });

    test('throws on premature stream exhaustion', () {
      // Root (node 0) with bits 0 and 1, but empty bitstream
      final src = Uint8List.fromList([
        2, 0xFF,
        0, 0x10,
        65, 0,
      ]);

      expect(
        () => SciDecompressorHuffman.decompress(src, 5),
        throwsA(isA<SciDecompressionException>()),
      );
    });
  });
}
