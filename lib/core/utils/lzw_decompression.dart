import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';

/// Sierra AGI 11-bit LZW decompression algorithm.
class LzwDecompressor {
  const LzwDecompressor._();

  static const int _invalid = -1;
  static const int _maxWidth = 11;
  static const int _clear = 256;
  static const int _eof = 257;

  /// Expands compressed LZW [src] bytes into a newly allocated [Uint8List] of size [expandedSize].
  static Uint8List expand(Uint8List src, int expandedSize) {
    final output = Uint8List(expandedSize);
    var outIdx = 0;

    final prefix = Int16List(1 << _maxWidth);
    final suffix = Uint8List(1 << _maxWidth);
    var width = 9;
    var hi = _eof;
    var overflow = 1 << 9;
    var last = _invalid;

    var readBits = 0;
    var readBitsSize = 0;

    for (final srcByte in src) {
      readBits |= (srcByte & 0xFF) << readBitsSize;
      readBitsSize += 8;

      while (readBitsSize >= width) {
        final current = readBits & ((1 << width) - 1);
        readBitsSize -= width;
        readBits >>= width;

        if (current < _clear) {
          final asByte = current & 0xFF;
          if (outIdx >= output.length) {
            throw AgiException('LZW output overflow beyond expected $expandedSize bytes');
          }
          output[outIdx++] = asByte;
          if (last != _invalid) {
            suffix[hi] = asByte;
            prefix[hi] = last;
          }
        } else if (current == _clear) {
          width = 9;
          hi = _eof;
          overflow = 1 << 9;
          last = _invalid;
          continue;
        } else if (current == _eof) {
          return output.sublist(0, outIdx);
        } else if (current <= hi) {
          var token = current;
          final beginIdx = outIdx;

          if (token == hi && last != _invalid) {
            token = last;
            while (token >= _clear) {
              token = prefix[token];
            }
            if (outIdx >= output.length) {
              throw AgiException('LZW output overflow beyond expected $expandedSize bytes');
            }
            output[outIdx++] = token & 0xFF;
            token = last;
          }

          while (token >= _clear) {
            if (outIdx >= output.length) {
              throw AgiException('LZW output overflow beyond expected $expandedSize bytes');
            }
            output[outIdx++] = suffix[token];
            token = prefix[token];
          }
          if (outIdx >= output.length) {
            throw AgiException('LZW output overflow beyond expected $expandedSize bytes');
          }
          output[outIdx++] = token & 0xFF;

          // Reverse the unpacked bytes from this code sequence
          final middle = (outIdx - beginIdx) ~/ 2;
          for (var i = 0; i < middle; i++) {
            final left = beginIdx + i;
            final right = outIdx - i - 1;
            final tmp = output[left];
            output[left] = output[right];
            output[right] = tmp;
          }

          if (last != _invalid) {
            suffix[hi] = token & 0xFF;
            prefix[hi] = last;
          }
        } else {
          throw const AgiException('Malformed LZW resource!');
        }

        last = current;
        hi++;
        if (hi >= overflow) {
          if (width == _maxWidth) {
            last = _invalid;
            hi--;
          } else {
            width++;
            overflow <<= 1;
          }
        }
      }
    }

    if (outIdx != output.length) {
      throw AgiException(
        'LZW: resource expected $expandedSize bytes, but only expanded $outIdx bytes.',
      );
    }

    return output;
  }
}
