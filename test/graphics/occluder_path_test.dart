import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';

/// AGI pic with a native x 10..19, y 5..9 region at priority 10.
/// Rendered (doubled) coverage: x 20..39, y 5..9. Everything else is the
/// default effective priority 4.
AgiPic _buildAgiPic() {
  final buffer = PriorityBuffer();
  for (var y = 5; y <= 9; y++) {
    for (var x = 10; x <= 19; x++) {
      buffer.setPriorityAt(x, y, 10);
    }
  }
  return AgiPic(
    visualPixels: Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight),
    priorityBuffer: buffer,
    slices: <int, PictureSlice>{},
  );
}

SciPic _buildSciPic() {
  final priorityPixels = Uint8List(320 * 200);
  priorityPixels[0] = 0x1A; // masked to 10
  priorityPixels[1] = 5;
  return SciPic(
    visualPixels: Uint8List(320 * 200),
    priorityPixels: priorityPixels,
    controlPixels: Uint8List(320 * 200),
    rawColorPairs: Uint8List(320 * 200),
    slices: <int, PictureSlice>{},
    unditheredSlices: <int, PictureSlice>{},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SierraPicture.occluderPathFor', () {
    test('AGI: contains follows rendered (doubled) priority region', () {
      final pic = _buildAgiPic();
      addTearDown(pic.dispose);

      final path = pic.occluderPathFor(4);
      expect(path.contains(const Offset(30, 7)), isTrue);
      expect(path.contains(const Offset(20.5, 5.5)), isTrue);
      expect(path.contains(const Offset(50, 7)), isFalse);
      expect(path.contains(const Offset(30, 15)), isFalse);
      expect(path.getBounds(), const ui.Rect.fromLTWH(20.0, 5.0, 20.0, 5.0));

      // Priority equal to the region priority does not occlude.
      expect(pic.occluderPathFor(10).contains(const Offset(30, 7)), isFalse);
      expect(pic.occluderPathFor(10).getBounds(), isEmpty);
    });

    test('AGI: adjacent runs merge; gaps are not contained', () {
      final pic = _buildAgiPic();
      addTearDown(pic.dispose);

      // Adjacent island: native x 20..24 -> rendered x 40..49, same y band.
      // Contiguous with the x 20..39 island, so it merges into one run.
      final buffer = pic.priorityBuffer;
      for (var y = 5; y <= 9; y++) {
        for (var x = 20; x <= 24; x++) {
          buffer.setPriorityAt(x, y, 10);
        }
      }
      // Disjoint island: native x 35..39 -> rendered x 70..79.
      for (var y = 5; y <= 9; y++) {
        for (var x = 35; x <= 39; x++) {
          buffer.setPriorityAt(x, y, 10);
        }
      }

      final path = pic.occluderPathFor(4);
      expect(path.getBounds(), const ui.Rect.fromLTWH(20.0, 5.0, 60.0, 5.0));
      expect(path.contains(const Offset(42, 7)), isTrue);
      expect(path.contains(const Offset(60, 7)), isFalse);
      expect(path.contains(const Offset(75, 7)), isTrue);
    });

    test('AGI: same instance twice; new instance after invalidation', () {
      final pic = _buildAgiPic();
      addTearDown(pic.dispose);

      final first = pic.occluderPathFor(4);
      expect(identical(pic.occluderPathFor(4), first), isTrue);

      // Simulate an in-place raster change (e.g. add.to.pic): drop the
      // priority region back to 4 and invalidate. AGI rasterEpoch is
      // always 0, so invalidation must be the explicit cache reset.
      final buffer = pic.priorityBuffer;
      for (var y = 5; y <= 9; y++) {
        for (var x = 10; x <= 19; x++) {
          buffer.setPriorityAt(x, y, 4);
        }
      }
      pic.invalidateCachedImages();

      final second = pic.occluderPathFor(4);
      expect(identical(second, first), isFalse);
      expect(second.contains(const Offset(30, 7)), isFalse);
    });

    test('SCI: 1:1 masked priorities; new instance after detach', () {
      final pic = _buildSciPic();
      addTearDown(pic.dispose);

      final path = pic.occluderPathFor(4);
      expect(path.contains(const Offset(0.5, 0.5)), isTrue);
      expect(path.contains(const Offset(1.5, 0.5)), isTrue);
      expect(path.contains(const Offset(2.5, 0.5)), isFalse);
      expect(pic.occluderPathFor(10).contains(const Offset(0.5, 0.5)), isFalse);

      expect(identical(pic.occluderPathFor(4), path), isTrue);
      pic.detachGpuCache();
      final rebuilt = pic.occluderPathFor(4);
      expect(identical(rebuilt, path), isFalse);
      expect(rebuilt.contains(const Offset(0.5, 0.5)), isTrue);
    });
  });
}
