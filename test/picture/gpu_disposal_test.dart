import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GPU decode / dispose races', () {
    test('toUiImage does not hang if the slice is disposed during decode', () async {
      final rgba = Uint8List(8 * 8 * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = EgaColors.rgbaBytes[2][0];
        rgba[i + 1] = EgaColors.rgbaBytes[2][1];
        rgba[i + 2] = EgaColors.rgbaBytes[2][2];
        rgba[i + 3] = 255;
      }
      final slice = PictureSlice(
        priority: 8,
        width: 8,
        height: 8,
        rgbaBytes: rgba,
        hasVisiblePixels: true,
      );

      final future = slice.toUiImage();
      slice.dispose();

      await future
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .timeout(const Duration(seconds: 2));
      expect(slice.cachedUiImage, isNull);
    });

    test('toUiImage throws immediately on an already-disposed slice', () async {
      final slice = PictureSlice(
        priority: 4,
        width: 1,
        height: 1,
        rgbaBytes: Uint8List(4),
        hasVisiblePixels: true,
      );
      slice.dispose();
      await expectLater(slice.toUiImage(), throwsA(isA<StateError>()));
    });
  });

  group('GPU Texture Lifecycle & Disposal Tests', () {
    test('onDrawPic disposes outgoing picture GPU textures', () async {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) {
        markTestSkipped('KQ2 reference game not present');
        return;
      }

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final pics = loader.presentPicNumbers;
      if (pics.length < 2) return;

      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame(startingRoom: 0);

      // Draw pic 1 and preload GPU textures
      await engine.onDrawPic(pics[0]);
      final pic1 = engine.currentPic;
      expect(pic1, isNotNull);
      await pic1!.preloadGpuTextures();

      final slice1 = pic1.activeSlices.first;
      expect(slice1.cachedUiImage, isNotNull);

      // Now draw pic 2
      await engine.onDrawPic(pics[1]);
      expect(engine.currentPic, isNot(same(pic1)));

      // Verify old slice GPU texture was disposed
      expect(slice1.cachedUiImage, isNull,
          reason: 'Outgoing picture slice textures must be disposed to prevent GPU memory leak');

      engine.dispose();
      loader.close();
    });

    test('onAddToPic disposes replaced slice GPU textures', () async {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) {
        markTestSkipped('KQ2 reference game not present');
        return;
      }

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final pics = loader.presentPicNumbers;
      final views = loader.presentViewNumbers;
      if (pics.isEmpty || views.isEmpty) return;

      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame(startingRoom: 0);

      await engine.onDrawPic(pics[0]);
      final pic = engine.currentPic!;
      await pic.preloadGpuTextures();

      final oldSlice = pic.activeSlices.first;
      expect(oldSlice.cachedUiImage, isNotNull);

      // Perform add.to.pic with an existing view targeting the active slice's priority
      await engine.onAddToPic(views[0], 0, 0, 80, 100, oldSlice.priority, 0);

      // Verify old slice was disposed upon slice replacement
      expect(oldSlice.cachedUiImage, isNull,
          reason: 'Old slices replaced by add.to.pic must be disposed to prevent GPU leaks');

      engine.dispose();
      loader.close();
    });

    test('changeRoom disposes currentPic GPU textures', () async {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) {
        markTestSkipped('KQ2 reference game not present');
        return;
      }

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame(startingRoom: 1);

      await engine.onDrawPic(1);
      final pic = engine.currentPic!;
      await pic.preloadGpuTextures();
      final oldSlice = pic.activeSlices.first;
      expect(oldSlice.cachedUiImage, isNotNull);

      engine.changeRoom(2);
      expect(engine.currentPic, isNull);
      expect(oldSlice.cachedUiImage, isNull);

      engine.dispose();
      loader.close();
    });
  });
}
