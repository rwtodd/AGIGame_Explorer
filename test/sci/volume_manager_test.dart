import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';
import '../support/reference_games.dart';

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

    // Helper: write a RESOURCE.MAP pointing [type].[number] at volume 0 offset 0,
    // and a RESOURCE.000 containing one record with the given header/payload.
    (Directory, SciVolumeManager) setupSingleRecord({
      required SciResourceType type,
      required int number,
      required int headerId,
      required int compSize,
      required int decompSize,
      required int method,
      required List<int> payload,
    }) {
      final mapFile = File('${tempDir.path}/RESOURCE.MAP');
      final mapData = Uint8List(12);
      final mapBd = ByteData.sublistView(mapData);
      mapBd.setUint16(0, (type.typeCode << 11) | number, Endian.little);
      mapBd.setUint32(2, 0, Endian.little); // volume 0, offset 0
      mapBd.setUint32(8, 0xFFFFFFFF, Endian.little); // sentinel
      mapFile.writeAsBytesSync(mapData);

      final volFile = File('${tempDir.path}/RESOURCE.000');
      final volData = Uint8List(8 + payload.length);
      final volBd = ByteData.sublistView(volData);
      volBd.setUint16(0, headerId, Endian.little);
      volBd.setUint16(2, compSize, Endian.little);
      volBd.setUint16(4, decompSize, Endian.little);
      volBd.setUint16(6, method, Endian.little);
      volData.setRange(8, 8 + payload.length, payload);
      volFile.writeAsBytesSync(volData);

      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);
      return (tempDir, vm);
    }

    test('throws when volume header id differs from map entry (wrong resource)', () {
      // Map asks for text.0 (0x1800) but record header says view.5 (5).
      final (_, vm) = setupSingleRecord(
        type: SciResourceType.text,
        number: 0,
        headerId: 5, // view.5
        compSize: 4 + 3,
        decompSize: 3,
        method: 0,
        payload: [1, 2, 3],
      );
      expect(
        () => vm.getResource(SciResourceType.text, 0),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('throws when method 0 decompSize differs from payloadSize', () {
      // compSize 7 -> payloadSize 3, but decompSize claims 5.
      final (_, vm) = setupSingleRecord(
        type: SciResourceType.text,
        number: 0,
        headerId: (SciResourceType.text.typeCode << 11) | 0,
        compSize: 4 + 3,
        decompSize: 5,
        method: 0,
        payload: [1, 2, 3],
      );
      expect(
        () => vm.getResource(SciResourceType.text, 0),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });

    test('throws when compSize < 4', () {
      final (_, vm) = setupSingleRecord(
        type: SciResourceType.text,
        number: 0,
        headerId: (SciResourceType.text.typeCode << 11) | 0,
        compSize: 2,
        decompSize: 0,
        method: 0,
        payload: [],
      );
      expect(
        () => vm.getResource(SciResourceType.text, 0),
        throwsA(isA<SciCorruptResourceException>()),
      );
    });
  });

  group('Post-SCI01 compression flavor (synthetic)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sci_volume_flavor_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Writes a RESOURCE.MAP + RESOURCE.000 holding [records] concatenated
    /// in order, each as an 8-byte volume header plus its payload.
    void writeMulti(
      List<({
        SciResourceType type,
        int number,
        int method,
        int decompSize,
        List<int> payload,
      })>
          records,
    ) {
      final volBytes = BytesBuilder();
      final offsets = <int>[];
      for (final r in records) {
        offsets.add(volBytes.length);
        final rec = Uint8List(8 + r.payload.length);
        final bd = ByteData.sublistView(rec);
        bd.setUint16(
            0, (r.type.typeCode << 11) | r.number, Endian.little);
        bd.setUint16(2, r.payload.length + 4, Endian.little);
        bd.setUint16(4, r.decompSize, Endian.little);
        bd.setUint16(6, r.method, Endian.little);
        rec.setRange(8, 8 + r.payload.length, r.payload);
        volBytes.add(rec);
      }
      File('${tempDir.path}/RESOURCE.000').writeAsBytesSync(volBytes.toBytes());

      final mapData = Uint8List((records.length + 1) * 6);
      final mbd = ByteData.sublistView(mapData);
      for (var i = 0; i < records.length; i++) {
        final r = records[i];
        mbd.setUint16(i * 6, (r.type.typeCode << 11) | r.number, Endian.little);
        mbd.setUint32(i * 6 + 2, offsets[i], Endian.little); // volume 0
      }
      mbd.setUint32(records.length * 6 + 2, 0xFFFFFFFF, Endian.little);
      File('${tempDir.path}/RESOURCE.MAP').writeAsBytesSync(mapData);
    }

    test('view method 2 detects post-SCI01; text method 2 decodes as MSB LZW1',
        () {
      // Text payload: 'A', 'B' literals + terminator as 9-bit MSB codes.
      final writer = _TestBitWriterMSB();
      writer.writeBits(0x41, 9);
      writer.writeBits(0x42, 9);
      writer.writeBits(257, 9);
      final payload = writer.toBytes();

      writeMulti([
        (
          type: SciResourceType.view,
          number: 0,
          method: 2,
          decompSize: 4,
          payload: [1, 2, 3, 4],
        ),
        (
          type: SciResourceType.text,
          number: 0,
          method: 2,
          decompSize: 2,
          payload: payload,
        ),
      ]);

      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      expect(vm.usesPostSci01Compression, isTrue);
      expect(vm.getResource(SciResourceType.text, 0), equals([65, 66]));
    });

    test('view method 1 stays SCI0; legacy LSB LZW decode is unchanged', () {
      // Legacy LSB stream for 'A', 'B' + terminator (see decompressor tests).
      const lsbPayload = [0x41, 0x84, 0x04, 0x04];

      writeMulti([
        (
          type: SciResourceType.view,
          number: 0,
          method: 1,
          decompSize: 4,
          payload: [1, 2, 3, 4],
        ),
        (
          type: SciResourceType.text,
          number: 0,
          method: 1,
          decompSize: 2,
          payload: lsbPayload,
        ),
      ]);

      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      expect(vm.usesPostSci01Compression, isFalse);
      expect(vm.getResource(SciResourceType.text, 0), equals([65, 66]));
    });
  });

  group('Police Quest 2 Real Game Tests', () {
    const pq2Path = 'reference_games/police-quest-2';

    test('loads and decompresses all 763 resources from PQ2 volumes', () {
      final mapFile = File('$pq2Path/RESOURCE.MAP');
      if (skipIfPathMissing(mapFile.path)) return;

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

  group('Quest for Glory 2 Real Game Tests', () {
    const qfg2Path = 'reference_games/quest-for-glory-2';

    test('detects post-SCI01 compression and decompresses view/sound', () {
      if (skipIfPathMissing(qfg2Path)) return;

      final vm = SciVolumeManager.fromDirectory(qfg2Path);
      addTearDown(vm.close);

      expect(vm.usesPostSci01Compression, isTrue);
      expect(
        vm.resourceMap.entriesForType(SciResourceType.view).isNotEmpty,
        isTrue,
      );
      // View.0 and sound.10 are raw method 2 (MSB early-change LZW1).
      expect(vm.getResource(SciResourceType.view, 0), isNotEmpty);
      expect(vm.getResource(SciResourceType.sound, 10), isNotEmpty);
    });
  });
}

/// MSB-first bit writer mirroring [_TestBitWriterLSB] in the decompressor
/// tests: codes are emitted as their big-endian bit sequence.
class _TestBitWriterMSB {
  final List<int> _bytes = [];
  int _buffer = 0;
  int _bits = 0;

  void writeBits(int value, int count) {
    _buffer = (_buffer << count) | (value & ((1 << count) - 1));
    _bits += count;
    while (_bits >= 8) {
      final shift = _bits - 8;
      _bytes.add((_buffer >> shift) & 0xFF);
      _bits -= 8;
    }
  }

  Uint8List toBytes() {
    if (_bits > 0) {
      _bytes.add((_buffer << (8 - _bits)) & 0xFF);
      _buffer = 0;
      _bits = 0;
    }
    return Uint8List.fromList(_bytes);
  }
}
