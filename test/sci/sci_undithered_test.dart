import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_canvas.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('SCI undithered pictures', () {
    test('default kernel flag is dithered', () {
      expect(SciKernel().unditheredPictures, isFalse);
    });

    test('setUnditheredPictures flips the current pic and the kernel flag', () {
      final engine = SciGameEngine();
      addTearDown(engine.dispose);

      // Synthetic pic with a real dither pair: canvas visual byte 0x13
      // decodes to pair (2, 3) via ditherInto.
      final canvas = SciPicCanvas(portTop: 0);
      canvas.visual[0] = 0x13;
      final pic = canvas.toSciPic(computeSlices: true);
      engine.kernel.currentPic = pic;

      var notified = 0;
      engine.addListener(() => notified++);

      engine.setUnditheredPictures(true);
      expect(engine.kernel.unditheredPictures, isTrue);
      expect(pic.isUndithered, isTrue);
      expect(notified, 1);

      engine.setUnditheredPictures(false);
      expect(engine.kernel.unditheredPictures, isFalse);
      expect(pic.isUndithered, isFalse);
      expect(notified, 2);
    });

    test('synthetic dither pair renders differently undithered vs dithered', () {
      final canvas = SciPicCanvas(portTop: 0);
      canvas.visual[0] = 0x13;
      final pic = canvas.toSciPic();
      expect(pic.rawColorPairAtPixel(0, 0), 0x23); // c1 = 2, c2 = 3
      expect(
        pic.renderFlatVisualRgba(undithered: true),
        isNot(equals(pic.renderFlatVisualRgba(undithered: false))),
      );
    });

    test('PQ2 initPicture honors unditheredPictures (guarded)', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      // Find the first pic that contains at least one dither pair.
      final kernel = SciKernel();
      kernel.volumeManager = SciVolumeManager.fromDirectory(pq2Dir.path);
      kernel.unditheredPictures = true;
      var picNum = -1;
      for (var n = 1; n <= 10 && picNum < 0; n++) {
        kernel.currentPic = null;
        kernel.initPicture(n);
        final pic = kernel.currentPic;
        if (pic == null) continue;
        var hasPairs = false;
        for (final b in pic.rawColorPairs) {
          if ((b >> 4) != (b & 0x0F)) {
            hasPairs = true;
            break;
          }
        }
        if (hasPairs) picNum = n;
      }
      expect(picNum, greaterThanOrEqualTo(1),
          reason: 'no PQ2 pic with dither pairs found');
      final pic = kernel.currentPic!;
      expect(pic.isUndithered, isTrue);
      // renderFlatVisualRgba() with the flag on equals the undithered render
      // and differs from the dithered one on this pic.
      expect(
        pic.renderFlatVisualRgba(),
        equals(pic.renderFlatVisualRgba(undithered: true)),
      );
      expect(
        pic.renderFlatVisualRgba(),
        isNot(equals(pic.renderFlatVisualRgba(undithered: false))),
      );
      // Slices follow the flag.
      expect(pic.slices, equals(pic.unditheredSlices));
    });

    test('PQ2 initPicture stays dithered by default (guarded)', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final kernel = SciKernel();
      kernel.volumeManager = SciVolumeManager.fromDirectory(pq2Dir.path);
      kernel.initPicture(1);
      expect(kernel.currentPic, isNotNull);
      expect(kernel.currentPic!.isUndithered, isFalse);
    });
  });
}
