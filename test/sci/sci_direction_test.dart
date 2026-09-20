import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('SciGameEngine Direction Toggling & Speed Options', () {
    final pq2Dir = Directory('reference_games/police-quest-2');

    test('direction toggles to 0 when pressing same direction repeatedly while moving', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();

      // Initially stopped: pressing 1 moves North (posts direction 1)
      // Note: handleDirection calls tick(), which processes and consumes events in VM
      // so we can observe events posted to kernel or track direction commands.
      engine.handleDirection(1);
      expect(engine.lastDirectionForTest, 1);

      // Pressing 1 again while in motion toggles to 0 (stop)
      engine.handleDirection(1);
      expect(engine.lastDirectionForTest, 0);

      // Pressing 1 again while stopped moves North (posts direction 1)
      engine.handleDirection(1);
      expect(engine.lastDirectionForTest, 1);

      // Pressing 3 changes direction to East (3)
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 3);

      // Pressing 3 again toggles to 0 (stop)
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 0);

      // Pressing explicit 0 keeps 0 (stop)
      engine.handleDirection(0);
      expect(engine.lastDirectionForTest, 0);

      // Mouse click resets direction tracking so pressing 3 afterwards moves East instead of toggling
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 3);
      engine.handleMouseClick(const ui.Offset(100, 100));
      expect(engine.lastDirectionForTest, 0);
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 3);

      engine.dispose();
    });

    test('speed options update engine speedHz and synchronize with SCI wait ticks', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();

      // Default speed is 20 Hz -> 6 SCI ticks (100 ms baseline)
      expect(engine.speedHz, 20.0);
      expect(engine.currentSciWaitSpeed, 6);
      if (engine.segManager.globals.length > 3) {
        expect(engine.segManager.globals[3].toUint16(), 6);
      }

      // 10 Hz (Slow) -> 12 SCI ticks (200 ms)
      engine.setSpeedHz(10.0);
      expect(engine.speedHz, 10.0);
      expect(engine.currentSciWaitSpeed, 12);
      if (engine.segManager.globals.length > 3) {
        expect(engine.segManager.globals[3].toUint16(), 12);
      }
      if (engine.segManager.globals.length > 18) {
        expect(engine.segManager.globals[18].toUint16(), 12);
      }

      // 30 Hz (Fast) -> 3 SCI ticks (50 ms)
      engine.setSpeedHz(30.0);
      expect(engine.speedHz, 30.0);
      expect(engine.currentSciWaitSpeed, 3);
      if (engine.segManager.globals.length > 3) {
        expect(engine.segManager.globals[3].toUint16(), 3);
      }
      if (engine.segManager.globals.length > 18) {
        expect(engine.segManager.globals[18].toUint16(), 3);
      }

      // 60 Hz (Fastest) -> 1 SCI tick (16.7 ms)
      engine.setSpeedHz(60.0);
      expect(engine.speedHz, 60.0);
      expect(engine.currentSciWaitSpeed, 1);
      if (engine.segManager.globals.length > 3) {
        expect(engine.segManager.globals[3].toUint16(), 1);
      }
      if (engine.segManager.globals.length > 18) {
        expect(engine.segManager.globals[18].toUint16(), 1);
      }

      engine.dispose();
    });

    test('Room 99 speed test is protected from speed synchronization override', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();

      // Simulate room 99 active speed test (speed = 0, room = 99)
      if (engine.segManager.globals.length > 11) {
        engine.segManager.globals[11] = const SciReg.fromInt(99);
      }
      if (engine.segManager.globals.length > 3) {
        engine.segManager.globals[3] = const SciReg.fromInt(0);
      }

      // setSpeedHz should not overwrite global 3 during room 99 speed test
      engine.setSpeedHz(30.0);
      expect(engine.segManager.globals[3].toUint16(), 0);

      engine.dispose();
    });

    test('direction toggling works during active gameplay cycle', () {
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();
      engine.start();

      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      // Initial command: move East (3)
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 3);

      // Same direction again: toggles to 0 (stop)
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 0);

      // Same direction again: moves East (3)
      engine.handleDirection(3);
      expect(engine.lastDirectionForTest, 3);

      // Different direction: changes to North (1)
      engine.handleDirection(1);
      expect(engine.lastDirectionForTest, 1);

      // Same direction again: toggles to 0 (stop)
      engine.handleDirection(1);
      expect(engine.lastDirectionForTest, 0);

      engine.dispose();
    });
  });
}
