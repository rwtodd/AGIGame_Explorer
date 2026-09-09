import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

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
}
