import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

void main() {
  test('(a) repeated alloc/free keeps offsets in 16-bit space without wrap collisions', () {
    final seg = SciSegManager();
    for (var i = 0; i < 1000; i++) {
      final hunk = seg.allocHunk(100);
      expect(hunk.segment, SciSegManager.hunkSegmentId);
      expect(hunk.offset, lessThan(0x10000),
          reason: 'iteration $i: offset ${hunk.offset} must stay in 16-bit space');
      expect(seg.getHunk(hunk), isNotNull,
          reason: 'iteration $i: live hunk must be retrievable via getHunk');
      expect(seg.freeHunk(hunk), isTrue);
    }

    final a = seg.allocHunk(60000);
    final b = seg.allocHunk(5000);
    expect(seg.freeHunk(a), isTrue);

    final c = seg.allocHunk(50000);
    expect(c.offset, lessThan(b.offset),
        reason: 'C must reuse freed space below B (C=${c.offset}, B=${b.offset})');
    seg.getHunk(b)![0] = 0xAB;
    seg.getHunk(c)![0] = 0xCD;
    expect(seg.getHunk(b)![0], 0xAB);
    expect(seg.getHunk(c)![0], 0xCD);
  });

  test('(b) hunk exhaustion throws instead of returning a wrapped pointer', () {
    final seg = SciSegManager();
    final big = seg.allocHunk(0xFFF0);
    expect(seg.getHunk(big), isNotNull);
    expect(() => seg.allocHunk(0x100), throwsA(isA<SciException>()));
  });

  test('(c) exhausted node pool returns nullReg without overwriting offset 1', () {
    final seg = SciSegManager();
    for (var i = 0; i < 65535; i++) {
      final pos = seg.newNode(SciReg.fromInt(i));
      expect(pos, isNot(SciReg.nullReg), reason: 'node $i must allocate');
    }
    expect(seg.nodes.length, 65535);
    expect(seg.nodes[1]!.value, SciReg.fromInt(0));

    final overflow = seg.newNode(SciReg.fromInt(99999));
    expect(overflow, SciReg.nullReg);
    expect(seg.nodes.length, 65535);
    expect(seg.nodes[1]!.value, SciReg.fromInt(0),
        reason: 'live node at offset 1 must not be overwritten');
  });

  test('(d) rebuildHunkFreeList recovers gaps after restore-style assignment', () {
    final seg = SciSegManager();
    // Simulate snapshot restore: only B (at 60001) survived; A (1..60000)
    // is a gap below nextHunkOffset.
    seg.hunkBuffers[60001] = Uint8List(5000);
    seg.nextHunkOffset = 65001;

    seg.rebuildHunkFreeList();
    final c = seg.allocHunk(50000);
    expect(c.offset, lessThan(60001),
        reason: 'post-restore alloc must fit into the gap below the live hunk');
  });
}
