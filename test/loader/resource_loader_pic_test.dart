import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';

class _MockVolumeManager extends VolumeManager {
  final Map<int, Uint8List> picMap;

  _MockVolumeManager(this.picMap);

  @override
  Uint8List getResource(DirEntry entry) {
    if (picMap.containsKey(entry.offset)) {
      return picMap[entry.offset]!;
    }
    throw ResourceNotPresentException('Not found in mock volume');
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry entry) async => getResource(entry);

  @override
  Uint8List getWordsData() => Uint8List.fromList([
        // Minimal WORDS.TOK
        0, 0,
      ]);

  @override
  Uint8List getObjectsData() => Uint8List.fromList([
        3, 0, 16, // names start offset, maxAnimated
        3, 0, 1, // entry 0: offset 3, room 1
        98, 111, 111, 107, 0, // 'book\0'
      ]);

  @override
  void close() {}
}

class _MockMetaData implements GameMetaData {
  @override
  final double version = 2.089;
  @override
  final String versionString = '2.089';
  @override
  final String? prefix = null;
  @override
  final String gamePath = '/dummy';
  @override
  final Uint8List decryptionKey = Uint8List(0);
  @override
  bool get isV3 => false;
  @override
  bool get isBeforeV3 => true;
}

void main() {
  group('AgiResourceLoader PICTURE Tests', () {
    test('loadPic loads and interprets picture from directory and volume', () {
      final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();
      final expectedPic = File('test/fixtures/picbytes.bin').readAsBytesSync();
      final expectedPri = File('test/fixtures/pribytes.bin').readAsBytesSync();

      // Setup PICDIR with PIC 5 at offset 0x1000 in volume 0
      // 3 bytes: 0x01, 0x00, 0x00 (volume 0, offset 0x1000)
      // For PIC 0..4 (FF FF FF), PIC 5 (00 10 00)
      final picDirBytes = Uint8List(18);
      picDirBytes.fillRange(0, 15, 0xFF);
      picDirBytes[15] = 0x00; // Vol 0, upper offset 0x0
      picDirBytes[16] = 0x10; // offset 0x10
      picDirBytes[17] = 0x00; // offset 0x00 -> offset 0x1000

      final rdir = V2ResourceDirectory(
        logics: Uint8List(0),
        pics: picDirBytes,
        views: Uint8List(0),
        sounds: Uint8List(0),
      );

      final vmgr = _MockVolumeManager({0x1000: srcBytes});
      final meta = _MockMetaData();

      final loader = AgiResourceLoader.custom(
        meta: meta,
        rdir: rdir,
        vmgr: vmgr,
      );

      final pic = loader.loadPic(5);
      expect(pic.visualPixels, equals(expectedPic));
      expect(pic.priorityBuffer.pixels, equals(expectedPri));
      expect(pic.slices.length, equals(16));
      expect(pic.slices[15]!.hasVisiblePixels, isTrue);
    });

    test('loadPic returns independent working copies from a cached template', () {
      final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();

      final picDirBytes = Uint8List(18);
      picDirBytes.fillRange(0, 15, 0xFF);
      picDirBytes[15] = 0x00;
      picDirBytes[16] = 0x10;
      picDirBytes[17] = 0x00;

      final loader = AgiResourceLoader.custom(
        meta: _MockMetaData(),
        rdir: V2ResourceDirectory(
          logics: Uint8List(0),
          pics: picDirBytes,
          views: Uint8List(0),
          sounds: Uint8List(0),
        ),
        vmgr: _MockVolumeManager({0x1000: srcBytes}),
      );

      final pic1 = loader.loadPic(5);
      final pic2 = loader.loadPic(5);

      expect(pic1.visualPixels, equals(pic2.visualPixels));
      expect(identical(pic1, pic2), isFalse);
      expect(identical(pic1.visualPixels, pic2.visualPixels), isFalse,
          reason: 'working copies must not share the cached template buffer');

      pic1.visualPixels[0] = (pic1.visualPixels[0] + 1) & 0x0F;
      expect(pic2.visualPixels[0], isNot(equals(pic1.visualPixels[0])),
          reason: 'mutating a drawn pic must not poison the cache');
    });

    test('loadPic throws ResourceNotPresentException if pic not in directory', () {
      final rdir = V2ResourceDirectory(
        logics: Uint8List(0),
        pics: Uint8List(0),
        views: Uint8List(0),
        sounds: Uint8List(0),
      );

      final vmgr = _MockVolumeManager({});
      final meta = _MockMetaData();

      final loader = AgiResourceLoader.custom(
        meta: meta,
        rdir: rdir,
        vmgr: vmgr,
      );

      expect(() => loader.loadPic(99), throwsA(isA<ResourceNotPresentException>()));
    });
  });
}
