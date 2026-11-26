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

    test('rebuildSlices is a no-op when slices were never computed', () {
      final data = Uint8List.fromList([0xFF]);
      final pic = SciPicInterpreter.interpret(data, portTop: 10, computeSlices: false);
      final epoch = pic.rasterEpoch;

      pic.rebuildSlices();

      expect(pic.slices, isEmpty,
          reason: 'rebuildSlices must not force computation');
      expect(pic.rasterEpoch, equals(epoch),
          reason: 'no-op rebuild must not bump the epoch');
    });
  });
}
