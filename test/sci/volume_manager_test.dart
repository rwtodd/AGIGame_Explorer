import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  group('SciVolumeManager Synthetic Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sci_volume_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('throws SciResourceNotFoundException for non-existent game directory', () {
      expect(
        () => SciVolumeManager.fromDirectory('/non/existent/path/to/game'),
        throwsA(isA<SciResourceNotFoundException>()),
      );
    });

    test('throws SciResourceNotFoundException when RESOURCE.MAP is missing', () {
      expect(
        () => SciVolumeManager.fromDirectory(tempDir.path),
        throwsA(isA<SciResourceNotFoundException>()),
      );
    });

    test('reads uncompressed (method 0) and loose patch resources correctly', () {
      // 1. Create RESOURCE.MAP with 1 entry: Text 0 at volume 1, offset 0
      final mapFile = File('${tempDir.path}/RESOURCE.MAP');
      final mapData = Uint8List(12);
      final mapBd = ByteData.sublistView(mapData);

      // Text is type 3. id = (3 << 11) | 0 = 0x1800
      mapBd.setUint16(0, 0x1800, Endian.little);
      // Volume 1, offset 0
      mapBd.setUint32(2, 1 << 26, Endian.little);
      // Sentinel
      mapBd.setUint32(8, 0xFFFFFFFF, Endian.little);
      mapFile.writeAsBytesSync(mapData);

      // 2. Create RESOURCE.001 with 8-byte header + "Hello SCI!"
      final volFile = File('${tempDir.path}/RESOURCE.001');
      final payload = Uint8List.fromList('Hello SCI!'.codeUnits);
      final volData = Uint8List(8 + payload.length);
      final volBd = ByteData.sublistView(volData);

      volBd.setUint16(0, 0x1800, Endian.little); // id
      volBd.setUint16(2, payload.length + 4, Endian.little); // compSize = payload + 4
      volBd.setUint16(4, payload.length, Endian.little); // decompSize
      volBd.setUint16(6, 0, Endian.little); // method 0 (none)
      volData.setRange(8, 8 + payload.length, payload);
      volFile.writeAsBytesSync(volData);

      // 3. Create a loose patch: script.701
      // Header: byte 0 = 0x82 (script), byte 1 = extra header length (e.g. 0)
      final patchFile = File('${tempDir.path}/script.701');
      final patchPayload = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      final patchData = Uint8List(2 + patchPayload.length);
      patchData[0] = 0x82; // script
      patchData[1] = 0x00; // extraHeaderLen
      patchData.setRange(2, 2 + patchPayload.length, patchPayload);
      patchFile.writeAsBytesSync(patchData);

      // 4. Initialize SciVolumeManager
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      expect(vm.hasResource(SciResourceType.text, 0), isTrue);
      expect(vm.hasResource(SciResourceType.script, 701), isTrue);
      expect(vm.hasResource(SciResourceType.view, 999), isFalse);

      // Read volume resource
      final text0 = vm.getResource(SciResourceType.text, 0);
      expect(String.fromCharCodes(text0), equals('Hello SCI!'));

      // Read loose patch resource
      final script701 = vm.getResource(SciResourceType.script, 701);
      expect(script701, equals(patchPayload));

      // Verify readHeader
      final entry = vm.resourceMap.find(SciResourceType.text, 0)!;
      final header = vm.readHeader(entry);
      expect(header.resourceType, equals(SciResourceType.text));
      expect(header.resourceNumber, equals(0));
      expect(header.method, equals(0));
      expect(header.decompSize, equals(10));
    });
  });

  group('Police Quest 2 Real Game Tests', () {
    const pq2Path = 'reference_games/police-quest-2';

    test('loads and decompresses all 763 resources from PQ2 volumes', () {
      final mapFile = File('$pq2Path/RESOURCE.MAP');
      if (!mapFile.existsSync()) {
        // Skip if reference game is not available in current environment
        return;
      }

      final vm = SciVolumeManager.fromDirectory(pq2Path);
      addTearDown(vm.close);

      final map = vm.resourceMap;
      expect(map.rawRecordCount, equals(763));
      expect(map.duplicateCount, equals(224));
      expect(map.length, equals(540)); // 539 unique in map + 1 loose patch (script.701)

      // Check loose patches
      expect(map.find(SciResourceType.script, 701)?.isPatch, isTrue);
      expect(map.find(SciResourceType.patch, 0)?.isPatch, isTrue);
      expect(map.find(SciResourceType.patch, 101)?.isPatch, isTrue);

      // Test specific resource types and compression methods:
      // Method 1 (LZW): View 0 (Ego)
      expect(map.contains(SciResourceType.view, 0), isTrue);
      final view0 = vm.getResource(SciResourceType.view, 0);
      expect(view0, isNotEmpty);

      // Method 2 (Huffman): Pic 1
      expect(map.contains(SciResourceType.pic, 1), isTrue);
      final pic1 = vm.getResource(SciResourceType.pic, 1);
      expect(pic1, isNotEmpty);

      // Decompress all entries to ensure zero errors across all 763 resources
      var decompressedCount = 0;
      for (final entry in map.allEntries) {
        final data = vm.getResourceById(entry.id);
        expect(data, isNotEmpty, reason: 'Failed on resource ${entry.id}');
        decompressedCount++;
      }

      expect(decompressedCount, equals(map.length));
    });
  });
}
