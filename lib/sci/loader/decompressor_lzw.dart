import 'dart:typed_data';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// LSB/MSB bitstream reader for SCI compressed resources.
class _BitReader {
  final Uint8List data;
  final bool msb;
  int _offset = 0;
  int _dwBits = 0;
  int _nBits = 0;

  _BitReader(this.data, {this.msb = false});

  void _fetchBits() {
    while (_nBits <= 24 && _offset < data.length) {
      final b = data[_offset++] & 0xFF;
      if (msb) {
        _dwBits = (_dwBits | (b << (24 - _nBits))) & 0xFFFFFFFF;
      } else {
        _dwBits |= b << _nBits;
      }
      _nBits += 8;
    }
  }

  int getBits(int n) {
    if (_nBits < n) {
      _fetchBits();
    }
    if (_nBits < n) {
      return -1; // Stream exhausted
    }
    if (msb) {
      final ret = (_dwBits >>> (32 - n)) & 0xFFFFFFFF;
      _dwBits = (_dwBits << n) & 0xFFFFFFFF;
      _nBits -= n;
      return ret;
    } else {
      final ret = _dwBits & ((1 << n) - 1);
      _dwBits >>>= n;
      _nBits -= n;
      return ret;
    }
  }

  int getByte() => getBits(8);
}

/// LZW decompressor for Sierra SCI resources.
///
/// Handles SCI0 LZW (LSB-first, up to 12-bit dynamic dictionary, code limit 512).
/// Also supports SCI01/SCI1 LZW (MSB-first, code limit 511) via parameters.
class SciDecompressorLZW {
  const SciDecompressorLZW._();

  /// Decompresses [src] bytes into a newly allocated [Uint8List] of size [decompSize].
  ///
  /// [msb]: If true, reads bits MSB-first (SCI01/SCI1); if false, LSB-first (SCI0 standard).
  /// [earlyChange]: If true, adjusts codeLimit by -1 (SCI01/SCI1 early-change bug).
  static Uint8List decompress(
    Uint8List src,
    int decompSize, {
    bool msb = false,
    bool earlyChange = false,
  }) {
    if (decompSize <= 0) {
      return Uint8List(0);
    }

    final dest = Uint8List(decompSize);
    final reader = _BitReader(src, msb: msb);

    var codeBitLength = 9;
    var tableSize = 258;
    var codeLimit = earlyChange ? 511 : 512;

    final stringOffsets = Int32List(4096);
    final stringLengths = Int32List(4096);

    var dwWrote = 0;
    var terminatorFound = false;

    while (dwWrote < decompSize && !terminatorFound) {
      final code = reader.getBits(codeBitLength);

      if (code < 0) {
        throw SciDecompressionException(
          'Premature end of LZW stream: expanded $dwWrote/$decompSize bytes',
        );
      }

      if (code >= tableSize) {
        throw SciDecompressionException(
          'LZW code 0x${code.toRadixString(16)} exceeds table size 0x${tableSize.toRadixString(16)} '
          'at offset $dwWrote/$decompSize',
        );
      }

      if (code == 257) {
        // End-of-stream terminator
        terminatorFound = true;
        break;
      }

      if (code == 256) {
        // Reset command
        codeBitLength = 9;
        tableSize = 258;
        codeLimit = earlyChange ? 511 : 512;
        continue;
      }

      final newStringOffset = dwWrote;
      if (code <= 255) {
        dest[dwWrote++] = code;
      } else {
        final len = stringLengths[code];
        final start = stringOffsets[code];
        for (var i = 0; i < len && dwWrote < decompSize; i++) {
          dest[dwWrote++] = dest[start + i];
        }
      }

      if (tableSize < 4096) {
        if (tableSize == codeLimit && codeBitLength < 12) {
          codeBitLength++;
          codeLimit = 1 << codeBitLength;
          if (earlyChange) {
            codeLimit--;
          }
        }

        stringOffsets[tableSize] = newStringOffset;
        stringLengths[tableSize] = dwWrote - newStringOffset + 1;
        tableSize++;
      }
    }

    if (dwWrote != decompSize && !terminatorFound) {
      throw SciDecompressionException(
        'LZW decompression size mismatch: expanded $dwWrote bytes, expected $decompSize bytes',
      );
    }

    return dest;
  }
}
