import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_map.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciResourceMap Tests', () {
    test('throws SciCorruptResourceException if buffer is smaller than 6 bytes', () {
      expect(
        () => SciResourceMap.fromBytes(Uint8List(4)),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('parses entries and stops at 0xFFFFFFFF sentinel', () {
      // Create a 3-entry synthetic map (2 valid + 1 sentinel)
      // Entry 1: View 0 (type 0, num 0), volume 1, offset 0x1000
      // id = (0 << 11) | 0 = 0x0000
      // offset = (1 << 26) | 0x1000 = 0x04001000
      //
      // Entry 2: Pic 42 (type 1, num 42), volume 2, offset 0x2500
      // id = (1 << 11) | 42 = 0x082A
      // offset = (2 << 26) | 0x2500 = 0x08002500
      //
      // Entry 3: Sentinel offset 0xFFFFFFFF
      final buffer = Uint8List(18);
      final bd = ByteData.sublistView(buffer);

      bd.setUint16(0, 0x0000, Endian.little);
      bd.setUint32(2, 0x04001000, Endian.little);

      bd.setUint16(6, 0x082A, Endian.little);
      bd.setUint32(8, 0x08002500, Endian.little);

      bd.setUint16(12, 0x0000, Endian.little);
      bd.setUint32(14, 0xFFFFFFFF, Endian.little);

      final map = SciResourceMap.fromBytes(buffer);

      expect(map.length, equals(2));
      expect(map.contains(SciResourceType.view, 0), isTrue);
      expect(map.contains(SciResourceType.pic, 42), isTrue);
      expect(map.contains(SciResourceType.script, 0), isFalse);

      final view0 = map.find(SciResourceType.view, 0)!;
      expect(view0.volumeNumber, equals(1));
      expect(view0.fileOffset, equals(0x1000));
      expect(view0.isPatch, isFalse);

      final pic42 = map.find(SciResourceType.pic, 42)!;
      expect(pic42.volumeNumber, equals(2));
      expect(pic42.fileOffset, equals(0x2500));
    });

    test('first entry in map wins on duplicate resource IDs', () {
      // Entry 1: Script 10 at volume 1, offset 0x1000
      // Entry 2: Script 10 at volume 2, offset 0x9000 (duplicate!)
      // Entry 3: Sentinel
      final buffer = Uint8List(18);
      final bd = ByteData.sublistView(buffer);

      // Script = type 2. id = (2 << 11) | 10 = 0x100A
      bd.setUint16(0, 0x100A, Endian.little);
      bd.setUint32(2, 0x04001000, Endian.little); // vol 1, offset 0x1000

      bd.setUint16(6, 0x100A, Endian.little);
      bd.setUint32(8, 0x08009000, Endian.little); // vol 2, offset 0x9000

      bd.setUint16(12, 0x0000, Endian.little);
      bd.setUint32(14, 0xFFFFFFFF, Endian.little);

      final map = SciResourceMap.fromBytes(buffer);
      expect(map.length, equals(1));

      final script10 = map.find(SciResourceType.script, 10)!;
      expect(script10.volumeNumber, equals(1));
      expect(script10.fileOffset, equals(0x1000));
    });

    test('filters and lists entries by type', () {
      final buffer = Uint8List(24);
      final bd = ByteData.sublistView(buffer);

      // Pic 10
      bd.setUint16(0, (1 << 11) | 10, Endian.little);
      bd.setUint32(2, 0x04001000, Endian.little);

      // Pic 5
      bd.setUint16(6, (1 << 11) | 5, Endian.little);
      bd.setUint32(8, 0x04002000, Endian.little);

      // Sound 1
      bd.setUint16(12, (4 << 11) | 1, Endian.little);
      bd.setUint32(14, 0x04003000, Endian.little);

      // Sentinel
      bd.setUint16(18, 0, Endian.little);
      bd.setUint32(20, 0xFFFFFFFF, Endian.little);

      final map = SciResourceMap.fromBytes(buffer);

      final pics = map.entriesForType(SciResourceType.pic);
      expect(pics.length, equals(2));
      // sorted by resource number
      expect(pics[0].id.number, equals(5));
      expect(pics[1].id.number, equals(10));

      final picNums = map.numbersForType(SciResourceType.pic);
      expect(picNums, equals([5, 10]));

      final sounds = map.entriesForType(SciResourceType.sound);
      expect(sounds.length, equals(1));
      expect(sounds.first.id.number, equals(1));
    });

    test('withPatches overrides existing entries and adds new ones', () {
      final buffer = Uint8List(12);
      final bd = ByteData.sublistView(buffer);

      // Script 10 from volume 1
      bd.setUint16(0, (2 << 11) | 10, Endian.little);
      bd.setUint32(2, 0x04001000, Endian.little);

      // Sentinel
      bd.setUint16(6, 0, Endian.little);
      bd.setUint32(8, 0xFFFFFFFF, Endian.little);

      final map = SciResourceMap.fromBytes(buffer);
      expect(map.find(SciResourceType.script, 10)!.isPatch, isFalse);

      final dummyFile = File('/tmp/script.010');
      final patchedMap = map.withPatches([
        SciResourceEntry(
          id: const SciResourceId(SciResourceType.script, 10),
          patchFile: dummyFile,
        ),
        SciResourceEntry(
          id: const SciResourceId(SciResourceType.script, 701),
          patchFile: File('/tmp/script.701'),
        ),
      ]);

      expect(patchedMap.length, equals(2));
      expect(patchedMap.find(SciResourceType.script, 10)!.isPatch, isTrue);
      expect(patchedMap.find(SciResourceType.script, 701)!.isPatch, isTrue);
    });

    test('fromFile throws SciResourceNotFoundException for non-existent file', () {
      expect(
        () => SciResourceMap.fromFile(File('non_existent_resource.map')),
        throwsA(isA<SciResourceNotFoundException>()),
      );
    });
  });
}
