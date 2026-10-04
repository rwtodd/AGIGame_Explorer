import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';

Future<ui.Image> _createTestImage({int width = 8, int height = 8}) {
  final completer = Completer<ui.Image>();
  final pixels = Uint8List(width * height * 4);
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (image) {
    completer.complete(image);
  });
  return completer.future;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SCI kernel stub-hit stats', () {
    late SciKernel kernel;
    late SciVM vm;

    setUp(() {
      kernel = SciKernel();
      final seg = SciSegManager();
      final selectors = SciSelectors();
      vm = SciVM(segManager: seg, kernel: kernel, selectors: selectors);
    });

    test('stub flags mark _kStub ops but not implemented ones', () {
      expect(kernel.isStubKernel(0x57), isTrue, reason: 'SetDebug');
      expect(kernel.isStubKernel(0x62), isTrue, reason: 'GetCWD');
      expect(kernel.isStubKernel(0x08), isFalse, reason: 'DrawPic');
      expect(kernel.isStubKernel(0x03), isFalse, reason: 'DisposeScript');
      expect(kernel.isStubKernel(0x6B), isFalse, reason: 'FlushResources');
      expect(kernel.isStubKernel(0xFF), isTrue, reason: 'unknown id');
    });

    test('stub and unknown calls are counted; ranking and reset work', () {
      kernel.call(vm, 0x57, 0, []);
      kernel.call(vm, 0x57, 0, []);
      kernel.call(vm, 0x62, 0, []);
      kernel.call(vm, 0xFF, 0, []);

      expect(kernel.stubHitCounts[0x57], 2);
      expect(kernel.stubHitCounts[0x62], 1);
      expect(kernel.stubHitCounts[0xFF], 1);
      expect(kernel.stubHitTotal, 4);

      final top = kernel.topStubHits();
      expect(top.first.id, 0x57);
      expect(top.first.name, 'SetDebug');
      expect(top.first.hits, 2);
      expect(kernel.topStubHits(2), hasLength(2));

      kernel.clearStubStats();
      expect(kernel.stubHitTotal, 0);
      expect(kernel.topStubHits(), isEmpty);
    });

    test('topStubHits memoizes sorted result and recalculates only when stats change', () {
      kernel.call(vm, 0x57, 0, []);
      kernel.call(vm, 0x62, 0, []);

      final first = kernel.topStubHits();
      final second = kernel.topStubHits();
      expect(identical(first, second), isTrue);

      // Invalidate memoization by triggering another stub call
      kernel.call(vm, 0x62, 0, []);
      final third = kernel.topStubHits();
      expect(identical(first, third), isFalse);
      expect(third.first.id, 0x62);
      expect(third.first.hits, 2);
    });

    test('cel cache bounds texture memory and prunes inactive cels on DrawPic and reset', () async {
      final img1 = await _createTestImage();
      final img2 = await _createTestImage();
      final img3 = await _createTestImage();

      kernel.cacheCelImage(0, 0, 0, img1);
      kernel.cacheCelImage(1, 0, 0, img2);
      kernel.cacheCelImage(2, 0, 0, img3);
      expect(kernel.cachedCelImageCount, 3);

      // Only view 0 is in active sprites
      kernel.currentSprites = [
        PlayfieldActorSprite(
          priority: 5,
          baselineY: 100,
          objectNumber: 1,
          isUpdating: true,
          position: Offset.zero,
          viewNumber: 0,
          loopNumber: 0,
          celNumber: 0,
          image: img1,
        ),
      ];

      // Pruning inactive cels (as triggered on DrawPic)
      kernel.pruneCelCache();
      expect(kernel.cachedCelImageCount, 1);
      expect(kernel.getCelImage(0, 0, 0), isNotNull);
      expect(img2.debugDisposed, isTrue);
      expect(img3.debugDisposed, isTrue);

      // Reset clears everything
      kernel.reset();
      expect(kernel.cachedCelImageCount, 0);
      expect(img1.debugDisposed, isTrue);
    });

    test('caching beyond capacity automatically triggers inactive cel eviction', () async {
      for (int i = 0; i < 130; i++) {
        final img = await _createTestImage(width: 2, height: 2);
        kernel.cacheCelImage(100 + i, 0, 0, img);
      }

      // Since currentSprites is empty and capacity >= 128 triggered pruning to 64,
      // inactive cels were pruned down.
      expect(kernel.cachedCelImageCount, lessThanOrEqualTo(64));
    });
  });
}
