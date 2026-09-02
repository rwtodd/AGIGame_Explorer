import 'dart:typed_data';

/// Decompressor for AGI v3 PICTURE resources packed with 4-bit color nibbles.
class PicDecompressor {
  const PicDecompressor._();

  /// Expands packed V3 picture bytes [src] to [reslen] bytes.
  static Uint8List expand(Uint8List src, [int? reslen]) {
    var buffer = Uint8List(reslen ?? (src.length * 2));
    var outIdx = 0;
    final lastSrcIdx = src.length;
    var unaligned = false;
    var nextHalf = false;
    var srcIdx = 0;

    void addByte(int byte) {
      if (outIdx >= buffer.length) {
        final newBuffer = Uint8List(buffer.length * 2);
        newBuffer.setRange(0, buffer.length, buffer);
        buffer = newBuffer;
      }
      buffer[outIdx++] = byte;
    }

    while (srcIdx < lastSrcIdx) {
      if (nextHalf) {
        if (unaligned) {
          addByte(src[srcIdx++] & 0x0F);
        } else {
          addByte((src[srcIdx] & 0xF0) >> 4);
        }
        unaligned = !unaligned;
        nextHalf = false;
      } else {
        int nxtByte;
        if (unaligned) {
          var composed = (src[srcIdx++] & 0x0F) << 4;
          if (srcIdx < lastSrcIdx) {
            composed |= (src[srcIdx] & 0xF0) >> 4;
          }
          nxtByte = composed;
        } else {
          nxtByte = src[srcIdx++];
        }

        addByte(nxtByte);
        final op = nxtByte & 0xFF;
        if (op == 0xFF) {
          break;
        }
        nextHalf = (op == 0xF0 || op == 0xF2);
      }
    }

    if (reslen != null && outIdx == reslen) {
      return buffer;
    }
    return Uint8List.sublistView(buffer, 0, outIdx);
  }
}
