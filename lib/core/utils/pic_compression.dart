import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';

/// Decompressor for AGI v3 PICTURE resources packed with 4-bit color nibbles.
class PicDecompressor {
  const PicDecompressor._();

  /// Expands packed V3 picture bytes [src] to [reslen] bytes.
  static Uint8List expand(Uint8List src, int reslen) {
    final expanded = Uint8List(reslen);
    final lastSrcIdx = src.length;
    var unaligned = false;
    var nextHalf = false;
    var srcIdx = 0;

    for (var idx = 0; idx < reslen; idx++) {
      if (srcIdx >= lastSrcIdx) {
        throw const AgiException('Out of source bytes while expanding V3 PIC.');
      }

      if (nextHalf) {
        if (unaligned) {
          expanded[idx] = src[srcIdx++] & 0x0F;
        } else {
          expanded[idx] = (src[srcIdx] & 0xF0) >> 4;
        }
        unaligned = !unaligned;
        nextHalf = false;
      } else {
        int nxtByte;
        if (unaligned) {
          var composed = (src[srcIdx++] & 0x0F) << 4;
          if (srcIdx >= lastSrcIdx) {
            throw const AgiException('Out of source bytes while expanding V3 PIC.');
          }
          composed |= (src[srcIdx] & 0xF0) >> 4;
          nxtByte = composed;
        } else {
          nxtByte = src[srcIdx++];
        }

        expanded[idx] = nxtByte;
        final op = nxtByte & 0xFF;
        nextHalf = (op == 0xF0 || op == 0xF2);
      }
    }

    if (srcIdx < (lastSrcIdx - 1)) {
      throw const AgiException('Extra source bytes when expanding PIC!');
    }

    return expanded;
  }
}
