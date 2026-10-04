import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

SciObject _dummyClass() {
  return SciObject(
    pos: const SciReg.pointer(1, 0x10),
    variables: [
      const SciReg.fromInt(1),
      const SciReg.fromInt(0),
      const SciReg.fromInt(SciObjectInfoFlags.isClass),
      SciReg.nullReg,
    ],
    nameString: 'Dummy',
  );
}

void main() {
  test('clone offsets stay in 16-bit space and are recycled on dispose', () {
    final seg = SciSegManager();
    final src = _dummyClass();

    for (var i = 0; i < 70000; i++) {
      final cloned = seg.cloneObject(src);
      expect(cloned.pos.segment, SciSegManager.cloneSegmentId);
      expect(cloned.pos.offset, inInclusiveRange(1, 0xFFFF));
      expect(seg.getObject(cloned.pos), same(cloned));
      expect(seg.disposeClone(cloned.pos), isTrue);
    }
    expect(seg.clones, isEmpty);
  });

  test('live clones keep distinct 16-bit offsets', () {
    final seg = SciSegManager();
    final src = _dummyClass();
    final live = <SciObject>[];
    for (var i = 0; i < 256; i++) {
      live.add(seg.cloneObject(src));
    }
    final offsets = live.map((c) => c.pos.offset).toSet();
    expect(offsets.length, 256);
    expect(seg.clones.length, 256);
    for (final c in live) {
      expect(seg.disposeClone(c.pos), isTrue);
    }
    expect(seg.clones, isEmpty);
  });

  test('allocHunk allocates and freeHunk reclaims hunk memory', () {
    final seg = SciSegManager();
    final hunk1 = seg.allocHunk(32);
    final hunk2 = seg.allocHunk(64);

    expect(hunk1.segment, SciSegManager.hunkSegmentId);
    expect(hunk2.segment, SciSegManager.hunkSegmentId);
    expect(seg.hunkBuffers.containsKey(hunk1.offset), isTrue);
    expect(seg.hunkBuffers.containsKey(hunk2.offset), isTrue);

    expect(seg.getObject(hunk1), isNull, reason: 'hunk pointers must not resolve to objects');

    expect(seg.freeHunk(hunk1), isTrue);
    expect(seg.hunkBuffers.containsKey(hunk1.offset), isFalse);
    expect(seg.freeHunk(hunk1), isFalse, reason: 'double free returns false');

    expect(seg.freeHunk(const SciReg.pointer(SciSegManager.cloneSegmentId, 1)), isFalse);
    expect(seg.freeHunk(hunk2), isTrue);
    expect(seg.hunkBuffers, isEmpty);
  });

  test('purgeUnmappedScripts prunes classAddresses for purged segments', () {
    final seg = SciSegManager();
    // Register fake script 100 at segment 10
    seg.scriptToSegment[100] = 10;
    seg.loadedScripts[10] = SciScript(
      scriptNumber: 100,
      segmentId: 10,
      bytes: Uint8List(16),
      locals: [],
      objects: {},
      exports: [],
      synonyms: const [],
    );
    seg.registerClass(55, const SciReg.pointer(10, 0x20));
    expect(seg.classAddresses[55], const SciReg.pointer(10, 0x20));

    // Dispose script 100
    seg.disposeScript(100);
    expect(seg.hasPendingPurge, isTrue);

    // Purge unmapped scripts
    final freed = seg.purgeUnmappedScripts();
    expect(freed, 1);
    expect(seg.loadedScripts.containsKey(10), isFalse);
    expect(seg.classAddresses.containsKey(55), isFalse,
        reason: 'classAddresses pointing to purged segment must be pruned');
  });
}
