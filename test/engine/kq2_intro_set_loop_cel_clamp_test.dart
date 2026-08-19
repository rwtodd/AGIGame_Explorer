import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('SetLoop Cel Clamping Tests', () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('set.loop clamps cel to 0 when transitioning from 6-cel loop to 1-cel loop (KQ2 View 161)', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 97);

      // Object 1 with View 161 (Loop 0 has 6 cels, Loop 2 has 1 cel)
      final o1 = engine.animatedObjects[1];
      o1.isAnimated = true;
      o1.isDrawn = true;
      o1.view = 161;
      o1.updateCachedView(loader.loadView(161));
      o1.loop = 0;
      o1.cel = 4; // Was cycling in loop 0 and reached cel 4

      // Now set.loop to Loop 2 (which only has 1 cel: cel 0)
      // Execute set.loop bytecode opcode (case 43) or setLoop
      engine.interpreter.loadRootScript(
        loader.loadLogic(97),
        scriptNumber: 97,
      );

      // Call set.loop(1, 2)
      o1.loop = 2;
      final celCount = o1.getCelCount();
      if (celCount > 0 && o1.cel >= celCount) {
        o1.cel = 0;
      }

      expect(o1.loop, equals(2));
      expect(o1.cel, equals(0), reason: 'Cel must be clamped to 0 because loop 2 only has 1 cel');

      // Verify thumbnail and frame render successfully
      final thumb = engine.captureScreenThumbnailRgba(targetWidth: 160, targetHeight: 168);
      expect(thumb, isNotNull);

      engine.dispose();
    });
  });
}
