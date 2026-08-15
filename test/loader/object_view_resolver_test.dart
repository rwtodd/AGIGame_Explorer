import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/object_view_resolver.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';

class _FakeVolumeManager extends VolumeManager {
  final Map<int, Uint8List> dataMap;
  _FakeVolumeManager(this.dataMap);

  @override
  Uint8List getResource(DirEntry entry) => dataMap[entry.offset]!;

  @override
  Future<Uint8List> getResourceAsync(DirEntry entry) async => getResource(entry);

  @override
  Uint8List getWordsData() {
    final bytes = Uint8List(54);
    bytes[0] = 0;
    bytes[1] = 52;
    bytes[52] = 0;
    bytes[53] = 0;
    return bytes;
  }

  @override
  Uint8List getObjectsData() => Uint8List.fromList([
        3, 0, 16,
        3, 0, 1,
        98, 111, 111, 107, 0, // 'book\0'
      ]);

  @override
  void close() {}
}

class _FakeMetaData implements GameMetaData {
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

/// Helper to craft a minimal binary VIEW resource with an embedded description string.
Uint8List _createMinimalViewData({String? description}) {
  final descBytes = description != null ? Uint8List.fromList([...description.codeUnits, 0]) : Uint8List(0);
  final descOffset = description != null ? 7 : 0;

  // Header: 2 unknown bytes, 1 loop, 2 bytes desc offset, 2 bytes loop 0 offset
  // Loop 0: 1 cel (offset 3)
  // Cel 0: width 4, height 4, trans 0x00, pixels (4x4)
  final view = <int>[
    0x01, 0x01, // unknown
    0x01, // 1 loop
    descOffset & 0xFF, (descOffset >> 8) & 0xFF, // desc offset
    0x00, 0x00, // loop 0 offset (relative) -> will adjust if needed
  ];

  // We can append description after header
  if (description != null) {
    view.addAll(descBytes);
  }

  final loop0Offset = view.length;
  view[5] = loop0Offset & 0xFF;
  view[6] = (loop0Offset >> 8) & 0xFF;

  // Loop 0: 1 cel
  view.add(1); // celCount
  view.add(3); // cel 0 rel offset (low)
  view.add(0); // cel 0 rel offset (high)

  // Cel 0: 4x4
  view.add(4); // width
  view.add(4); // height
  view.add(0); // transparent color
  // 4 rows of RLE data
  for (var r = 0; r < 4; r++) {
    view.addAll([0x14, 0x00]); // 4 pixels of color 1, then line end (0x00)
  }

  return Uint8List.fromList(view);
}

void main() {
  test('ObjectViewResolver matches object by description substring', () {
    // VIEW 0: Ego walking (no desc)
    // VIEW 1: Dagger ("A sharp steel dagger.")
    // VIEW 2: Gold Key ("A shiny golden key.")
    final v0 = _createMinimalViewData(description: null);
    final v1 = _createMinimalViewData(description: 'A sharp steel dagger.');
    final v2 = _createMinimalViewData(description: 'A shiny golden key.');

    final dirBytes = Uint8List(9);
    // View 0 at 0x1000, View 1 at 0x2000, View 2 at 0x3000
    dirBytes[0] = 0x00; dirBytes[1] = 0x10; dirBytes[2] = 0x00;
    dirBytes[3] = 0x00; dirBytes[4] = 0x20; dirBytes[5] = 0x00;
    dirBytes[6] = 0x00; dirBytes[7] = 0x30; dirBytes[8] = 0x00;

    final rdir = V2ResourceDirectory(
      logics: Uint8List(0),
      pics: Uint8List(0),
      views: dirBytes,
      sounds: Uint8List(0),
    );

    final vmgr = _FakeVolumeManager({
      0x1000: v0,
      0x2000: v1,
      0x3000: v2,
    });

    final loader = AgiResourceLoader.custom(
      meta: _FakeMetaData(),
      rdir: rdir,
      vmgr: vmgr,
    );

    final daggerObj = const AgiObject(name: 'dagger', startingRoom: 1);
    final keyObj = const AgiObject(name: 'gold key', startingRoom: 5);

    final daggerView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 1,
      object: daggerObj,
      loader: loader,
    );
    expect(daggerView, equals(1));

    final keyView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 2,
      object: keyObj,
      loader: loader,
    );
    expect(keyView, equals(2));
  });

  test('ObjectViewResolver maps 1-based index when description is present', () {
    // VIEW 0: Ego (no desc)
    // VIEW 1: Object 1 View ("Item 1")
    final v0 = _createMinimalViewData(description: null);
    final v1 = _createMinimalViewData(description: 'Magic item 1');

    final dirBytes = Uint8List(6);
    dirBytes[0] = 0x00; dirBytes[1] = 0x10; dirBytes[2] = 0x00;
    dirBytes[3] = 0x00; dirBytes[4] = 0x20; dirBytes[5] = 0x00;

    final rdir = V2ResourceDirectory(
      logics: Uint8List(0),
      pics: Uint8List(0),
      views: dirBytes,
      sounds: Uint8List(0),
    );

    final vmgr = _FakeVolumeManager({
      0x1000: v0,
      0x2000: v1,
    });

    final loader = AgiResourceLoader.custom(
      meta: _FakeMetaData(),
      rdir: rdir,
      vmgr: vmgr,
    );

    final unknownObj = const AgiObject(name: 'xyz', startingRoom: 1);
    final resolved = ObjectViewResolver.resolveViewNumber(
      objectIndex: 1,
      object: unknownObj,
      loader: loader,
    );
    expect(resolved, equals(1));
  });

  test('ObjectViewResolver correctly resolves KQ4 Magic Hen (#32 -> 245) and Earthworm (#34 -> 247)', () async {
    final loader = await AgiResourceLoader.fromDirectory('reference_games/kings-quest-4-agi');
    final objects = loader.initialObjects;

    // Object #32: Magic Hen -> VIEW 245
    expect(objects[32].name, equals('Magic Hen'));
    final henView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 32,
      object: objects[32],
      loader: loader,
    );
    expect(henView, equals(245));

    // Object #34: Large Earthworm -> VIEW 247
    expect(objects[34].name, equals('Large Earthworm'));
    final wormView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 34,
      object: objects[34],
      loader: loader,
    );
    expect(wormView, equals(247));
  });

  test('ObjectViewResolver correctly resolves KQ3 objects with base offset 100', () async {
    final loader = await AgiResourceLoader.fromDirectory('reference_games/kings-quest-3');
    final objects = loader.initialObjects;

    // Object #1: Chicken Feather* -> VIEW 101
    expect(objects[1].name, equals('Chicken Feather*'));
    final featherView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 1,
      object: objects[1],
      loader: loader,
    );
    expect(featherView, equals(101));

    // Object #33: Knife -> VIEW 133
    expect(objects[33].name, equals('Knife'));
    final knifeView = ObjectViewResolver.resolveViewNumber(
      objectIndex: 33,
      object: objects[33],
      loader: loader,
    );
    expect(knifeView, equals(133));
  });
}
