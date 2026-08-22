import 'dart:typed_data';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_test/flutter_test.dart';

AgiView _bannerView() {
  return AgiView(
    viewNumber: 246,
    loops: [
      AgiViewLoop(
        loopNumber: 0,
        cels: [
          AgiViewCel.forward(
            width: 40,
            height: 5,
            transparentColor: 0,
            rawPixels: Uint8List(40 * 5),
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('Playfield display() text vs sprites', () {
    test('clearTransparentGlyphs wipes bg=0 glyphs but not newspaper fills', () {
      final buf = AgiTextScreenBuffer();
      buf.writeString(6, 16, '........', fg: 15, bg: 0);
      buf.writeString(10, 2, 'NEWS', fg: 0, bg: 15);

      buf.clearTransparentGlyphs(row0: 6, col0: 0, row1: 6, col1: 39);

      expect(
        List.generate(40, (c) => buf.getCell(6, c).char).join().trim(),
        isEmpty,
      );
      expect(buf.getCell(6, 16).isWritten, isFalse);
      expect(buf.getCell(10, 2).char, 'N');
      expect(buf.getCell(10, 2).bg, 15);
    });

    test('reposition.to union dirty-rect blanks keypad dots, walking does not', () {
      final engine = AgiGameEngine(speedHz: 20, randomSeed: 1);
      addTearDown(engine.dispose);
      final priBuf = PriorityBuffer();
      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );

      engine.textScreenBuffer.writeString(6, 16, '........', fg: 15, bg: 0);
      engine.textScreenBuffer.writeString(12, 5, 'HELLO', fg: 15, bg: 0);

      final banner = engine.animatedObjects[2];
      banner.updateCachedView(_bannerView());
      banner.view = 246;
      banner.isDrawn = true;
      banner.isAnimated = true;
      banner.x = 0;
      banner.y = 46;

      // SQ1 logic 65: teleport from the left parking spot to the right.
      engine.onReposition(banner, 113, 46);
      banner.x = 113;
      banner.y = 46;

      final row6 = List.generate(40, (c) => engine.textScreenBuffer.getCell(6, c).char).join();
      expect(row6.contains('.'), isFalse, reason: 'union 0→113 dirties the keypad row');

      // HELLO at row 12 is below the 5px-tall banner at y=46.
      expect(
        List.generate(40, (c) => engine.textScreenBuffer.getCell(12, c).char).join(),
        contains('HELLO'),
      );

      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;
      engine.ego.isUpdating = true;
      engine.ego.x = 20;
      engine.ego.y = 100;
      engine.ego.direction = 3;
      engine.ego.stepSize = 1;
      engine.ego.stepTime = 1;
      engine.ego.stepTimer = 1;
      engine.ego.ignoreObjects = true;

      for (var i = 0; i < 10; i++) {
        engine.tick();
      }
      expect(
        List.generate(40, (c) => engine.textScreenBuffer.getCell(12, c).char).join(),
        contains('HELLO'),
        reason: 'ordinary walking must not eat overlay display() text',
      );
    });
  });
}
