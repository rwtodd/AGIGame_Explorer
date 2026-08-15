import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';
import '../parsers/view_parser_test.dart';

class MockVolumeManager implements VolumeManager {
  final Map<DirEntry, Uint8List> resources = {};

  @override
  Uint8List getObjectsData() => Uint8List.fromList([3, 0, 16, 3, 0, 1, 65, 0]);

  @override
  Uint8List getWordsData() => Uint8List.fromList([0, 2, 0, (65 ^ 0x7F) | 0x80, 0, 1]);

  @override
  Uint8List getResource(DirEntry de) {
    final data = resources[de];
    if (data == null) {
      throw const ResourceNotPresentException('Resource not found.');
    }
    return data;
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry de) async {
    return getResource(de);
  }

  @override
  void close() {}
}

class MockResourceDirectory extends ResourceDirectory {
  final Map<int, DirEntry> views = {};

  @override
  DirEntry findView(int number) => views[number] ?? DirEntry.nonExistent;

  @override
  DirEntry findLogic(int number) => DirEntry.nonExistent;

  @override
  DirEntry findPic(int number) => DirEntry.nonExistent;

  @override
  DirEntry findSound(int number) => DirEntry.nonExistent;

  @override
  int get logicCount => 0;

  @override
  int get picCount => 0;

  @override
  int get soundCount => 0;

  @override
  int get viewCount => views.length;
}

void main() {
  group('AgiResourceLoader (VIEW Integration)', () {
    test('loads and caches parsed VIEW resources', () async {
      final meta = OnDiskMetaData(
        gamePath: '/mock/game',
        version: 2.272,
        versionString: '2.272',
      );

      final rdir = MockResourceDirectory();
      final vmgr = MockVolumeManager();

      final view0Data = createSimpleViewData(
        description: 'Ego Walking View 0',
        loopCount: 2,
        celCount: 1,
        width: 8,
        height: 12,
      );

      final de0 = const DirEntry(0, 0x1000);
      rdir.views[0] = de0;
      vmgr.resources[de0] = view0Data;

      final loader = AgiResourceLoader.custom(
        meta: meta,
        rdir: rdir,
        vmgr: vmgr,
      );

      // First load (parses and caches)
      final view0 = loader.loadView(0);
      expect(view0.viewNumber, equals(0));
      expect(view0.description, equals('Ego Walking View 0'));
      expect(view0.loopCount, equals(2));

      // Second load (returns cached instance)
      final view0Again = loader.loadView(0);
      expect(identical(view0, view0Again), isTrue);

      // Async load
      final view0Async = await loader.loadViewAsync(0);
      expect(identical(view0, view0Async), isTrue);
    });

    test('throws ResourceNotPresentException for missing view', () {
      final meta = OnDiskMetaData(
        gamePath: '/mock/game',
        version: 2.272,
        versionString: '2.272',
      );

      final rdir = MockResourceDirectory();
      final vmgr = MockVolumeManager();

      final loader = AgiResourceLoader.custom(
        meta: meta,
        rdir: rdir,
        vmgr: vmgr,
      );

      expect(() => loader.loadView(99), throwsA(isA<ResourceNotPresentException>()));
    });
  });
}
