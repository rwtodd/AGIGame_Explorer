import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

void main() {
  test('PQ2 restart skips intro and reaches the car, not the station-edge Print', () {
    final pq2Dir = Directory('reference_games/police-quest-2');
    if (!pq2Dir.existsSync()) {
      markTestSkipped('PQ2 reference tree missing');
      return;
    }
    final engine = SciGameEngine(
      volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
    );
    engine.initializeGame();
    // Play for 50 ticks first (e.g. cold boot into room 99/200)
    for (var i = 0; i < 50; i++) {
      engine.tick();
    }
    engine.restartGame();
    var dest = 0;
    final egoPositionsInRoom1 = <(int, int)>[];
    for (var t = 0; t < 80; t++) {
      engine.tick();
      dest = engine.segManager.globals[11].toUint16();
      final ego = engine.segManager.getObject(engine.segManager.globals[0]);
      int? ex, ey;
      if (ego != null) {
        ex = ego.getProp(engine.segManager, engine.selectors.findSelector('x')!).toSint16();
        ey = ego.getProp(engine.segManager, engine.selectors.findSelector('y')!).toSint16();
      }
      if (dest == 1) {
        if (ex != null && ey != null) {
          egoPositionsInRoom1.add((ex, ey));
        }
      }
      if (dest != 0 && dest != 99 && dest != 1) break;
    }
    expect(dest, 33, reason: 'driveUpScript state 1 does newRoom 33 when g160 is 0');

    // Sonny must stay parked at (0, 0) and not get pushed by findPosn colliding with Keith
    expect(egoPositionsInRoom1, isNotEmpty);
    for (final pos in egoPositionsInRoom1) {
      expect(pos, (0, 0), reason: 'Ego should stay at (0, 0) during driveUpScript, not displaced by Keith');
    }

    final texts = engine.sciWindows
        .expand((w) => w.controls)
        .whereType<SciTextControl>()
        .map((c) => c.text.toLowerCase())
        .join(' | ');
    expect(texts.contains('entrance'), isFalse, reason: texts);
    expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue,
        reason: 'No dialog window should pop up during car drive-up');

    final ego = engine.segManager.getObject(engine.segManager.globals[0]);
    expect(ego, isNotNull);
    engine.dispose();
  });
}

