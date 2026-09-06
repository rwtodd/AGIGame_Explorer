import 'dart:typed_data';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// MSB bitstream reader for Huffman decompression.
class _HuffmanBitReader {
  final Uint8List data;
  int _offset = 0;
  int _dwBits = 0;
  int _nBits = 0;

  _HuffmanBitReader(this.data);

  void _fetchBits() {
    while (_nBits <= 24 && _offset < data.length) {
      final b = data[_offset++] & 0xFF;
      _dwBits = (_dwBits | (b << (24 - _nBits))) & 0xFFFFFFFF;
      _nBits += 8;
    }
  }

  int getBit() {
    if (_nBits < 1) {
      _fetchBits();
    }
    if (_nBits < 1) {
      return -1;
    }
    final ret = (_dwBits >>> 31) & 0x1;
    _dwBits = (_dwBits << 1) & 0xFFFFFFFF;
    _nBits -= 1;
    return ret;
  }

  int getByte() {
    if (_nBits < 8) {
      _fetchBits();
    }
    if (_nBits < 8) {
      return -1;
    }
    final ret = (_dwBits >>> 24) & 0xFF;
    _dwBits = (_dwBits << 8) & 0xFFFFFFFF;
    _nBits -= 8;
    return ret;
  }
}

/// Huffman decompressor for Sierra SCI resources (predominantly vector pictures in SCI0).
class SciDecompressorHuffman {
  const SciDecompressorHuffman._();

  /// Decompresses [src] bytes into a newly allocated [Uint8List] of size [decompSize].
  static Uint8List decompress(Uint8List src, int decompSize) {
    if (decompSize <= 0) {
      return Uint8List(0);
    }

    if (src.length < 2) {
      throw const SciDecompressionException('Huffman compressed payload is too short');
    }

    final numNodes = src[0];
    final terminator = (src[1] & 0xFF) | 0x100;
    final nodesByteCount = numNodes << 1;

    if (2 + nodesByteCount > src.length) {
      throw SciDecompressionException(
        'Huffman node table ($nodesByteCount bytes) exceeds payload size (${src.length} bytes)',
      );
    }

    final nodes = Uint8List.sublistView(src, 2, 2 + nodesByteCount);
    final reader = _HuffmanBitReader(Uint8List.sublistView(src, 2 + nodesByteCount));
    final dest = Uint8List(decompSize);

    int getc2() {
      var nodeIdx = 0;
      while (nodes[nodeIdx + 1] != 0) {
        final bit = reader.getBit();
        if (bit < 0) {
          throw const SciDecompressionException('Premature end of Huffman stream in getc2');
        }
        int next;
        if (bit != 0) {
          next = nodes[nodeIdx + 1] & 0x0F;
          if (next == 0) {
            final byteVal = reader.getByte();
            if (byteVal < 0) {
              throw const SciDecompressionException('Premature end of Huffman stream reading escape byte');
            }
            return byteVal | 0x100;
          }
        } else {
          next = (nodes[nodeIdx + 1] >> 4) & 0x0F;
        }

        nodeIdx += next << 1;
        if (nodeIdx + 1 >= nodes.length) {
          throw SciDecompressionException(
            'Corrupt Huffman node table: node offset $nodeIdx exceeds table size ${nodes.length}',
          );
        }
      }
      return nodes[nodeIdx] | (nodes[nodeIdx + 1] << 8);
    }

    var dwWrote = 0;
    while (dwWrote < decompSize) {
      final c = getc2();
      if (c == terminator) {
        break;
      }
      if (c < 0) {
        throw SciDecompressionException('Negative character code returned in Huffman stream: $c');
      }
      dest[dwWrote++] = c & 0xFF;
    }

    if (dwWrote != decompSize) {
      throw SciDecompressionException(
        'Huffman decompression size mismatch: expanded $dwWrote bytes, expected $decompSize bytes',
      );
    }

    return dest;
  }
}
