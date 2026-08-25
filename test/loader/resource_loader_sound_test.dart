import 'dart:typed_data';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';
import 'package:test/test.dart';

class _FakeResourceDirectory extends ResourceDirectory {
  final DirEntry soundEntry;
  _FakeResourceDirectory(this.soundEntry);

  @override
  int get logicCount => 0;
  @override
  int get picCount => 0;
  @override
  int get soundCount => 1;
  @override
  int get viewCount => 0;

  @override
  DirEntry findLogic(int index) => DirEntry.nonExistent;
  @override
  DirEntry findPic(int index) => DirEntry.nonExistent;
  @override
  DirEntry findSound(int index) => index == 1 ? soundEntry : DirEntry.nonExistent;
  @override
  DirEntry findView(int index) => DirEntry.nonExistent;
}

class _FakeVolumeManager implements VolumeManager {
  final Uint8List soundBytes;
  _FakeVolumeManager(this.soundBytes);

  @override
  bool isCompressed(DirEntry de) => false;

  @override
  void close() {}

  @override
  Uint8List getObjectsData() => Uint8List.fromList([
        3, 0, 16, // names start at 3 + 3 = 6, maxAnimated = 16
        3, 0, 1,  // object 1 offset 3 (starts at index 6), room 1
        65, 0,    // 'A\0'
      ]);

  @override
  Uint8List getWordsData() => Uint8List.fromList(List.filled(52, 0)); // Minimal empty WORDS.TOK

  @override
  Uint8List getResource(DirEntry de) => soundBytes;

  @override
  Future<Uint8List> getResourceAsync(DirEntry de) async => soundBytes;
}

void main() {
  group('AgiResourceLoader Sound Loading', () {
    final soundRawData = Uint8List.fromList([
      8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
      149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
      160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
      0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
    ]);

    test('loads and parses sound resource through loader', () {
      final meta = OnDiskMetaData(
        gamePath: '/test/game',
        version: 2.089, // < 2.411 so OBJECT is unencrypted
        versionString: '2.089',
      );

      final rdir = _FakeResourceDirectory(const DirEntry(0, 0x100));
      final vmgr = _FakeVolumeManager(soundRawData);

      final loader = AgiResourceLoader.custom(
        meta: meta,
        rdir: rdir,
        vmgr: vmgr,
      );

      final snd = loader.loadSound(1);
      expect(snd, isA<AgiSound>());
      expect(snd.voices.length, equals(1));
      expect(snd.noise, isNotNull);
      expect(snd.length, equals(15));
    });
  });
}
