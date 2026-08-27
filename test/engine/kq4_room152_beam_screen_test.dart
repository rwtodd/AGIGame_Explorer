import 'dart:io';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KQ4 Room 152 (Beam me up Easter egg room) priority and add.to.pic tests', () {
    test('renders all 9 developers with accurate effective priorities when priority=0', () async {
      final gamePath = Directory('reference_games/kings-quest-4-agi').existsSync()
          ? 'reference_games/kings-quest-4-agi'
          : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
      if (!Directory(gamePath).existsSync()) return;
      final loader = await AgiResourceLoader.fromDirectory(gamePath);
      final engine = AgiGameEngine(resourceLoader: loader);

      final logic0 = loader.loadLogic(0);
      engine.interpreter.loadRootScript(logic0, scriptNumber: 0);
      engine.onNewRoom(152);
      await engine.tick(); // Execute new room init

      expect(engine.currentPic?.picNumber, 140);
      expect(engine.addToPicCalls.length, 9);

      final view168 = loader.loadView(168);

      // Verify each of the 9 developers stamped onto the background
      for (int celIdx = 0; celIdx < 9; celIdx++) {
        final call = engine.addToPicCalls[celIdx];
        expect(call.view, 168);
        expect(call.loop, 1);
        expect(call.cel, celIdx);
        expect(call.priority, 0, reason: 'Script passes priority 0 (automatic priority from Y)');

        final cel = view168.getCel(1, celIdx)!;
        final celPixels = cel.getPixels(parentView: view168, celIndex: celIdx);
        int opaqueCount = 0;
        int drawnCount = 0;
        final startY = call.y - cel.height + 1;

        for (int cy = 0; cy < cel.height; cy++) {
          final py = startY + cy;
          for (int cx = 0; cx < cel.width; cx++) {
            final px = call.x + cx;
            final color = celPixels[cy * cel.width + cx] & 0x0F;
            if (color != cel.transparentColor) {
              opaqueCount++;
              if (engine.currentPic!.visualPixels[py * AgiPic.nativeWidth + px] == color) {
                drawnCount++;
              }
            }
          }
        }

        expect(
          drawnCount,
          greaterThan(opaqueCount * 0.5),
          reason: 'Opaque pixels of developer $celIdx at (${call.x}, ${call.y}) must be drawn (only occluded by pri 15 foreground)',
        );
      }
    });
  });
}
