import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';

void main() {
  group('GameMetaData & OnDiskMetaData', () {
    test('deriveNumericVersion converts version strings', () {
      expect(GameMetaData.deriveNumericVersion('2.936'), equals(2.936));
      expect(GameMetaData.deriveNumericVersion('2.411'), equals(2.411));
      expect(GameMetaData.deriveNumericVersion('3.002.149'), closeTo(3.002149, 0.000001));
    });

    test('extractVersionFromBytes finds version in AGIDATA.OVL', () {
      final header = ascii.encode('AGI ENGINE EMBEDDED STRING ');
      final version = ascii.encode('2.936');
      final trailer = ascii.encode(' EXTRA DATA');
      final ovlBytes = Uint8List.fromList([...header, ...version, ...trailer]);

      final extracted = OnDiskMetaData.extractVersionFromBytes(ovlBytes);
      expect(extracted, equals('2.936'));
    });

    test('extractVersionFromBytes finds V3 9-character version', () {
      final header = ascii.encode('SIERRA ON-LINE 1988 ');
      final version = ascii.encode('3.002.149');
      final trailer = ascii.encode(' DATA CONTINUES');
      final ovlBytes = Uint8List.fromList([...header, ...version, ...trailer]);

      final extracted = OnDiskMetaData.extractVersionFromBytes(ovlBytes);
      expect(extracted, equals('3.002.149'));
    });

    test('determinePrefix resolves game prefix for V3 files', () {
      final fileList = [
        'KQ4DIR',
        'KQ4VOL.0',
        'KQ4VOL.1',
        'AGIDATA.OVL',
        'SIERRA.COM',
      ];

      final prefix = OnDiskMetaData.determinePrefix(fileList);
      expect(prefix, equals('KQ4'));
    });
  });
}
