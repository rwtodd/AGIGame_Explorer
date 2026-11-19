import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';

AgiPic _buildAgiPic() {
  final buffer = PriorityBuffer();
  // Control pixel (0) at (3, 4) over depth pixel (7) at (3, 5).
  buffer.setPriorityAt(3, 4, 0);
  buffer.setPriorityAt(3, 5, 7);
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

  group('priority texture', () {
    test('AGI texture is doubled effective priorities with R = eff*17', () {
      final pic = _buildAgiPic();
      final rgba = pic.renderPriorityTextureRgba();
      expect(rgba.length, equals(320 * 200 * 4));

      // Control pixel (3,4) over depth 7 at (3,5): effective 7 -> R 119.
      const y = 4;
      const x = 3;
      final i1 = (y * 320 + x * 2) * 4;
      final i2 = i1 + 4;
      expect(rgba[i1], equals(7 * 17));
      expect(rgba[i1 + 1], equals(0));
      expect(rgba[i1 + 2], equals(0));
      expect(rgba[i1 + 3], equals(255));
      expect(rgba[i2], equals(7 * 17));
      expect(rgba[i2 + 1], equals(0));
      expect(rgba[i2 + 2], equals(0));
      expect(rgba[i2 + 3], equals(255));

      // The depth pixel itself (3,5) and the default 4 -> R 68 at (0,0).
      final j1 = (5 * 320 + 3 * 2) * 4;
      expect(rgba[j1], equals(7 * 17));
      expect(rgba[0], equals(4 * 17));

      // Bottom rows 168..199 have R = 0.
      for (final row in [168, 175, 199]) {
        for (final col in [0, 160, 319]) {
          final i = (row * 320 + col) * 4;
          expect(rgba[i], equals(0), reason: 'bottom row $row col $col');
          expect(rgba[i + 1], equals(0));
          expect(rgba[i + 2], equals(0));
          expect(rgba[i + 3], equals(255));
        }
      }
      pic.dispose();
    });

    test('SCI texture is 1:1 with masking to a nibble', () {
      final pic = _buildSciPic();
      final rgba = pic.renderPriorityTextureRgba();
      expect(rgba.length, equals(320 * 200 * 4));

      // 0x1A masked to 10 -> R 170.
      expect(rgba[0], equals(10 * 17));
      expect(rgba[1], equals(0));
      expect(rgba[2], equals(0));
      expect(rgba[3], equals(255));
      // Second pixel 5 -> R 85.
      expect(rgba[4], equals(5 * 17));
      expect(rgba[7], equals(255));
      // Zero-filled remainder pixels have R 0, A 255.
      expect(rgba[8], equals(0));
      expect(rgba[11], equals(255));

      pic.dispose();
    });

    test('decode round-trip and invalidateCachedImages (AGI)', () async {
      final pic = _buildAgiPic();
      expect(pic.cachedPriorityTextureImage, isNull);
      final image = await pic.toPriorityTextureUiImage();
      expect(image.width, equals(320));
      expect(image.height, equals(200));
      expect(pic.cachedPriorityTextureImage, isNotNull);
      expect(pic.isDisposed, isFalse);

      pic.invalidateCachedImages();
      expect(pic.cachedPriorityTextureImage, isNull);
      expect(pic.cachedFlatVisualImage, isNull);
      expect(pic.cachedPriorityMapImage, isNull);
      expect(pic.cachedControlMapImage, isNull);
      expect(pic.isDisposed, isFalse);

      pic.dispose();
      expect(pic.isDisposed, isTrue);
    });

    test('decode round-trip and invalidateCachedImages (SCI stash)', () async {
      final pic = _buildSciPic();
      final image = await pic.toPriorityTextureUiImage();
      expect(image.width, equals(320));
      expect(image.height, equals(200));
      expect(pic.cachedPriorityTextureImage, isNotNull);

      pic.invalidateCachedImages();
      expect(pic.cachedPriorityTextureImage, isNull);
      expect(pic.isDisposed, isFalse);

      pic.dispose();
      expect(pic.isDisposed, isTrue);
    });

    test('preloadGpuTextures includeShaderTextures decodes priority texture', () async {
      final pic = _buildAgiPic();
      expect(pic.cachedPriorityTextureImage, isNull);
      await pic.preloadGpuTextures(includeShaderTextures: true);
      expect(pic.cachedFlatVisualImage, isNotNull);
      expect(pic.cachedPriorityTextureImage, isNotNull);
      pic.dispose();
    });
  });
}
