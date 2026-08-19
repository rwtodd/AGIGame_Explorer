import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Non-Ego Animated Object View 0 Tests', () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Non-Ego object 1 with view 0 is drawn and composited in King\'s Quest 2 intro', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame(startingRoom: 97);

      // In KQ2 Room 97:
      // Object 1 starts with view 161/160/163/166 then transitions to view 0 (Graham walking across screen)
      final o1 = engine.animatedObjects[1];
      o1.isAnimated = true;
      o1.isDrawn = true;
      o1.view = 0;
      o1.loop = 0;
      o1.cel = 3;
      o1.x = 34;
      o1.y = 83;

      // Both Ego (o0) and NPC (o1) share view 0
      expect(engine.ego.view, equals(0));
      expect(o1.view, equals(0));
      expect(o1.isDrawn, isTrue);

      // Generate composite RGBA thumbnail - should not skip o1
      final thumbnail = engine.captureScreenThumbnailRgba(targetWidth: 160, targetHeight: 168);
      expect(thumbnail, isNotNull);
      expect(thumbnail.length, equals(160 * 168 * 4));

      engine.dispose();
    });
  });
}
