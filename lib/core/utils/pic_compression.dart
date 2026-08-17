import 'dart:typed_data';

/// Decompressor for AGI v3 PICTURE resources packed with 4-bit color nibbles.
class PicDecompressor {
  const PicDecompressor._();

  /// Expands packed V3 picture bytes [src] to [reslen] bytes.
  static Uint8List expand(Uint8List src, [int? reslen]) {
    final List<int> expanded = [];
    final lastSrcIdx = src.length;
    var unaligned = false;
    var nextHalf = false;
    var srcIdx = 0;

    while (srcIdx < lastSrcIdx) {
      if (nextHalf) {
        if (unaligned) {
          expanded.add(src[srcIdx++] & 0x0F);
        } else {
          expanded.add((src[srcIdx] & 0xF0) >> 4);
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

        expanded.add(nxtByte);
        final op = nxtByte & 0xFF;
        if (op == 0xFF) {
          break;
        }
        nextHalf = (op == 0xF0 || op == 0xF2);
      }
    }

    return Uint8List.fromList(expanded);
  }
}
