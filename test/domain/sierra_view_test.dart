import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/agi_view.dart';

void main() {
  group('SierraViewCel buffer aliasing', () {
    test('mutating getPixels result does not corrupt later calls', () {
      final source = AgiViewCel.forward(
        width: 4,
        height: 2,
        transparentColor: 0,
        rawPixels: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );
      // Attempt to corrupt the buffer handed out to the caller.
      final first = source.getPixels();
      try {
        first[0] = 99;
      } catch (_) {
        // Unmodifiable views throw UnsupportedError here; either the
        // throw or a pristine second call is acceptable evidence.
      }
      final second = source.getPixels();
      expect(second.toList(), equals([1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test('mutating getUnflippedPixels result does not corrupt later calls', () {
      final source = AgiViewCel.forward(
        width: 4,
        height: 2,
        transparentColor: 0,
        rawPixels: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );
      final first = source.getUnflippedPixels();
      try {
        first[0] = 99;
      } catch (_) {}
      final second = source.getUnflippedPixels();
      expect(second.toList(), equals([1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test('mirrored getPixels result is detached (still mutable copy)',
        () {
      final srcCel = AgiViewCel.forward(
        width: 4,
        height: 1,
        transparentColor: 0,
        rawPixels: Uint8List.fromList([1, 2, 3, 4]),
      );
      final mirrored = AgiViewCel.mirrored(
        width: 4,
        height: 1,
        transparentColor: 0,
        mirrorLoop: 0,
      );
      final view = AgiView(viewNumber: 0, loops: [
        AgiViewLoop(loopNumber: 0, cels: [srcCel]),
        AgiViewLoop(loopNumber: 1, cels: [mirrored]),
      ]);
      final flipped = mirrored.getPixels(parentView: view, celIndex: 0);
      expect(flipped.toList(), equals([4, 3, 2, 1]));
      // The flipped copy is a fresh buffer: mutating it must not reach the
      // source cel, and the source must stay pristine.
      flipped[0] = 99;
      expect(srcCel.getPixels().toList(), equals([1, 2, 3, 4]));
    });
  });

  group('SierraViewCel mirror cycles and dimensions', () {
    AgiView cycleView() {
      // Loop 0 mirrors loop 1, loop 1 mirrors loop 0: resolution recurses
      // forever without cycle detection.
      final celA = AgiViewCel.mirrored(
        width: 4,
        height: 2,
        transparentColor: 0,
        mirrorLoop: 1,
      );
      final celB = AgiViewCel.mirrored(
        width: 4,
        height: 2,
        transparentColor: 0,
        mirrorLoop: 0,
      );
      return AgiView(viewNumber: 0, loops: [
        AgiViewLoop(loopNumber: 0, cels: [celA]),
        AgiViewLoop(loopNumber: 1, cels: [celB]),
      ]);
    }

    test('two loops mirroring each other throw AgiException, not overflow',
        () {
      final view = cycleView();
      final cel = view.loops[0].cels[0];
      expect(
        () => cel.getPixels(parentView: view, celIndex: 0),
        throwsA(isA<AgiException>()),
      );
    });

    test('self-mirroring loop throws AgiException', () {
      final cel = AgiViewCel.mirrored(
        width: 4,
        height: 2,
        transparentColor: 0,
        mirrorLoop: 0,
      );
      final view = AgiView(viewNumber: 0, loops: [
        AgiViewLoop(loopNumber: 0, cels: [cel]),
      ]);
      expect(
        () => cel.getUnflippedPixels(parentView: view, celIndex: 0),
        throwsA(isA<AgiException>()),
      );
    });

    test('dimension-mismatched mirror source throws AgiException', () {
      // Source cel is 4x2 (8 bytes) but the mirrored cel claims 8x8.
      final srcCel = AgiViewCel.forward(
        width: 4,
        height: 2,
        transparentColor: 0,
        rawPixels: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );
      final mismatched = AgiViewCel.mirrored(
        width: 8,
        height: 8,
        transparentColor: 0,
        mirrorLoop: 0,
      );
      final view = AgiView(viewNumber: 0, loops: [
        AgiViewLoop(loopNumber: 0, cels: [srcCel]),
        AgiViewLoop(loopNumber: 1, cels: [mismatched]),
      ]);
      expect(
        () => mismatched.getPixels(parentView: view, celIndex: 0),
        throwsA(
          allOf(
            isA<AgiException>(),
            predicate(
              (AgiException e) =>
                  e.message.contains('expected') && e.message.contains('actual'),
            ),
          ),
        ),
      );
    });
  });
}
