import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';

void main() {
  group('CryptoUtils', () {
    test('Avis Durgan XOR encryption and decryption is symmetric', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
      final working = Uint8List.fromList(original);

      CryptoUtils.decodeInPlace(working);
      expect(working, isNot(equals(original)));

      CryptoUtils.decodeInPlace(working);
      expect(working, equals(original));
    });

    test('asciizString extracts null terminated strings', () {
      final data = Uint8List.fromList([
        65, 66, 67, 0, // "ABC"
        68, 69, 0,     // "DE"
        70, 0          // "F"
      ]);

      expect(CryptoUtils.asciizString(data, 0), equals('ABC'));
      expect(CryptoUtils.asciizString(data, 4), equals('DE'));
      expect(CryptoUtils.asciizString(data, 7), equals('F'));
      expect(CryptoUtils.asciizString(data, 9), equals(''));
    });
  });
}
