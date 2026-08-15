import 'dart:convert';
import 'dart:typed_data';

/// Cryptographic and string utilities for Sierra AGI resources.
class CryptoUtils {
  const CryptoUtils._();

  /// Default Sierra XOR decryption key: "Avis Durgan"
  static const List<int> avisDurganKey = [
    65, 118, 105, 115, 32, 68, 117, 114, 103, 97, 110,
  ];

  /// Decode [src] in place using repeated XOR against [key] (defaults to Avis Durgan).
  static Uint8List decodeInPlace(
    Uint8List src, {
    List<int>? key,
    int start = 0,
    int? end,
  }) {
    final k = (key != null && key.isNotEmpty) ? key : avisDurganKey;
    final stop = end ?? src.length;
    var kIdx = 0;
    for (var i = start; i < stop; i++) {
      src[i] ^= k[kIdx];
      kIdx++;
      if (kIdx == k.length) {
        kIdx = 0;
      }
    }
    return src;
  }

  /// Extracts a null-terminated ASCII string from [src] starting at byte offset [offset].
  static String asciizString(Uint8List src, int offset) {
    if (offset < 0 || offset >= src.length) {
      return '';
    }
    var zero = offset;
    while (zero < src.length && src[zero] != 0) {
      zero++;
    }
    return ascii.decode(src.sublist(offset, zero));
  }
}
