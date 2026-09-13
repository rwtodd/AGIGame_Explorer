import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('PQ2 boot path', () {
    test('cold start leaves room 99 for the intro (200), not the street', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      );
      engine.initializeGame();
      engine.start();
      var dest = 0;
      for (var t = 0; t < 80; t++) {
        engine.tick();
        final room = engine.segManager.globals.length > 11
            ? engine.segManager.globals[11].toUint16()
            : 0;
        if (room != 0 && room != 99) {
          dest = room;
          break;
        }
      }
      expect(dest, 200, reason: 'Btst(167) is clear on a cold start');
      final g110 = engine.segManager.globals[110].toUint16();
      expect(g110, greaterThan(20));
      expect(g110, lessThan(200));
      // PQ2 leaves setSpeed 0 on this path; host restores 6 so the intro
      // does not run unthrottled.
      expect(engine.segManager.globals[3].toUint16(), 6);
      expect(engine.segManager.globals[18].toUint16(), 6);
      engine.dispose();
    });

    test('restartGame sets flag 167 so PQ2 skips the intro to room 1', () {
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
        final room = engine.segManager.globals.length > 11
            ? engine.segManager.globals[11].toUint16()
            : 0;
        if (room != 0 && room != 99) {
          dest = room;
          break;
        }
      }
      expect(dest, 1, reason: 'Sierra restart Bset(167) then newRoom 1');
      final snap = engine.exportState();
      expect(snap['bootPath'], contains('restart-skip-intro'));
      expect(snap['flagsSet'], contains(167));
      expect(snap['clock'], isA<Map>());
      expect(snap['rooms']['current'], 1);
      expect(snap['rooms']['previous'], 99);
      engine.dispose();
    });
  });
}
