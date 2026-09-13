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
    engine.restartGame();

    var dest = 0;
    for (var t = 0; t < 80; t++) {
      engine.tick();
      dest = engine.segManager.globals[11].toUint16();
      if (dest != 0 && dest != 99 && dest != 1) break;
    }
    expect(dest, 33, reason: 'driveUpScript state 1 does newRoom 33 when g160 is 0');

    final texts = engine.sciWindows
        .expand((w) => w.controls)
        .whereType<SciTextControl>()
        .map((c) => c.text.toLowerCase())
        .join(' | ');
    expect(texts.contains('entrance'), isFalse, reason: texts);

    final ego = engine.segManager.getObject(engine.segManager.globals[0]);
    expect(ego, isNotNull);
    engine.dispose();
  });
}
