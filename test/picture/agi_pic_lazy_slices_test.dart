import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

AgiPic _picWithBand({required int priority, required int color}) {
  final visual = Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight);
  visual.fillRange(0, visual.length, 15);
  final pri = PriorityBuffer();
  for (int y = 0; y < 84; y++) {
    for (int x = 0; x < AgiPic.nativeWidth; x++) {
      pri.setPriorityAt(x, y, priority);
      visual[y * AgiPic.nativeWidth + x] = color;
    }
  }
  return AgiPic(visualPixels: visual, priorityBuffer: pri, slices: <int, PictureSlice>{});
}

void main() {
  group('AgiPic.ensureSlices (lazy slices)', () {
    test('starts with empty slices; flat rendering works without slices', () {
      final pic = _picWithBand(priority: 6, color: 2);

      expect(pic.slices, isEmpty);
      expect(pic.activeSlices, isEmpty);

      final flat = pic.renderFlatVisualRgba();
      expect(flat.length, 320 * 200 * 4);
      expect(flat.any((b) => b != 0), isTrue,
          reason: 'flat visual must be non-empty without slices');
    });

    test('ensureSlices populates slices and is idempotent', () {
      final pic = _picWithBand(priority: 6, color: 2);

      pic.ensureSlices();
      expect(pic.slices.length, equals(16));
      expect(pic.slices[6]!.hasVisiblePixels, isTrue);
      expect(pic.getSlice(6)!.hasVisiblePixels, isTrue);
      expect(pic.activeSlices.length, greaterThan(0));

      final first = pic.slices[6];
      pic.ensureSlices();
      expect(identical(pic.slices[6], first), isTrue,
          reason: 'second ensureSlices must be a no-op');
    });
  });
}
