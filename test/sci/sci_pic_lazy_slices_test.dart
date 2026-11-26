import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';

void main() {
  group('SciPic lazy slices', () {
    test('interpret(computeSlices: false) gives empty slices; ensureSlices populates', () {
      final data = Uint8List.fromList([
        0xF0, 0x01,
        0xF2, 0x05,
        0xF6,
        0x00, 10, 20,
        0x00, 50, 20,
        0xFF,
      ]);

      final pic = SciPicInterpreter.interpret(data, portTop: 10, computeSlices: false);
      expect(pic.slices, isEmpty);
      expect(pic.getSlice(5), isNull);

      final flat = pic.renderFlatVisualRgba();
      expect(flat.length, 320 * 200 * 4);
      expect(flat.any((b) => b != 0), isTrue);

      pic.ensureSlices();
      expect(pic.slices.length, equals(16));
      expect(pic.getSlice(5), isNotNull);
      expect(pic.getSlice(5)!.hasVisiblePixels, isTrue);
    });

    test('rebuildSlices without computed slices skips slicing but bumps epoch', () {
      final data = Uint8List.fromList([0xFF]);
      final pic = SciPicInterpreter.interpret(data, portTop: 10, computeSlices: false);
      final epoch = pic.rasterEpoch;

      pic.rebuildSlices();

      expect(pic.slices, isEmpty,
          reason: 'rebuildSlices must not force computation');
      expect(pic.rasterEpoch, greaterThan(epoch),
          reason: 'raster invalidation must still bump the epoch');
    });

    test('unsliced AddToPic mutation via rebuildSlices still invalidates raster caches', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = Uint8List.fromList([0xFF]);
      final pic = SciPicInterpreter.interpret(data, portTop: 10, computeSlices: false);
      expect(pic.slices, isEmpty);

      // Prime the cached flat GPU image (shader renderer reads this).
      final primed = await pic.toFlatVisualUiImage();
      expect(pic.cachedFlatVisualImage, isNotNull);
      final epochBefore = pic.rasterEpoch;

      // Representative _blitViewToPic mutation: in-place buffer edits.
      pic.visualPixels[0] = 0x0E;
      pic.priorityPixels[0] = 7;

      await pic.rebuildSlices();

      expect(pic.slices, isEmpty,
          reason: 'rebuildSlices must not force slice computation');
      expect(pic.rasterEpoch, greaterThan(epochBefore),
          reason: 'raster change must bump the epoch so the shader renderer re-reads buffers');
      expect(pic.cachedFlatVisualImage, isNull,
          reason: 'stale flat GPU image must be detached after AddToPic');
      // Detached by rebuildSlices; dispose once via the stash.
      expect(primed, isNotNull);
      pic.disposeDetachedGpuImages();
    });
  });
}
