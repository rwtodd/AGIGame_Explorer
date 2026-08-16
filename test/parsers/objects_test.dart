import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/loader/parsers/objects_parser.dart';

void main() {
  group('ObjectsParser', () {
    test('parses single object (unencrypted)', () {
      final book = ascii.encode('book');
      final data = Uint8List.fromList([
        3, 0, 16, // names start at 3 + 3 = 6, maxAnimated = 16
        3, 0, 1,  // object 1 offset 3 (starts at 3+3=6), room 1
        ...book, 0,
      ]);

      final parsed = ObjectsParser.parse(data, isEncrypted: false);
      expect(parsed.maxAnimated, equals(16));
      expect(parsed.objects.length, equals(1));
      expect(parsed.objects.first, equals(const AgiObject(name: 'book', startingRoom: 1)));
    });

    test('parses two objects with rooms', () {
      final bank = ascii.encode('bank');
      final ramHead = ascii.encode('ram head');
      final data = Uint8List.fromList([
        6, 0, 117, // names start at 3 + 6 = 9, maxAnimated = 117
        6, 0, 10,  // obj 1 name offset 6 (at index 3+6=9), room 10
        11, 0, 30, // obj 2 name offset 11 (at index 3+11=14), room 30
        ...bank, 0,     // length 5 (indices 9..13)
        ...ramHead, 0,  // length 9 (indices 14..22)
      ]);

      final parsed = ObjectsParser.parse(data, isEncrypted: false);
      expect(parsed.maxAnimated, equals(117));
      expect(parsed.objects.length, equals(2));
      expect(parsed.objects[0], equals(const AgiObject(name: 'bank', startingRoom: 10)));
      expect(parsed.objects[1], equals(const AgiObject(name: 'ram head', startingRoom: 30)));
    });

    test('parses encrypted object table with Avis Durgan key', () {
      final bank = ascii.encode('gold coin');
      final plain = Uint8List.fromList([
        3, 0, 16,
        3, 0, 5,
        ...bank, 0,
      ]);

      final encrypted = Uint8List.fromList(plain);
      // Encrypt it with Avis Durgan key
      for (var i = 0; i < encrypted.length; i++) {
        final k = [65, 118, 105, 115, 32, 68, 117, 114, 103, 97, 110];
        encrypted[i] ^= k[i % k.length];
      }

      final parsed = ObjectsParser.parse(encrypted, isEncrypted: true);
      expect(parsed.maxAnimated, equals(16));
      expect(parsed.objects.length, equals(1));
      expect(parsed.objects.first.name, equals('gold coin'));
      expect(parsed.objects.first.startingRoom, equals(5));
    });

    test('auto-detects unencrypted vs encrypted OBJECT table', () {
      final key = ascii.encode('key');
      final plain = Uint8List.fromList([
        3, 0, 16,
        3, 0, 7,
        ...key, 0,
      ]);

      // Unencrypted auto-detect
      final unenc = ObjectsParser.parse(plain);
      expect(unenc.maxAnimated, equals(16));
      expect(unenc.objects.length, equals(1));
      expect(unenc.objects.first.name, equals('key'));
      expect(unenc.objects.first.startingRoom, equals(7));

      // Encrypted auto-detect
      final encrypted = Uint8List.fromList(plain);
      for (var i = 0; i < encrypted.length; i++) {
        final k = [65, 118, 105, 115, 32, 68, 117, 114, 103, 97, 110];
        encrypted[i] ^= k[i % k.length];
      }
      final autoEnc = ObjectsParser.parse(encrypted);
      expect(autoEnc.maxAnimated, equals(16));
      expect(autoEnc.objects.length, equals(1));
      expect(autoEnc.objects.first.name, equals('key'));
      expect(autoEnc.objects.first.startingRoom, equals(7));
    });
  });
}
