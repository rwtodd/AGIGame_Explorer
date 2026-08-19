import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Space Quest 2 Room 37 Picture Restoration Tests', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('Room 37 draws Picture 34, captures pictureNumber: 34, and restores it accurately', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      // Start in Room 37: Logic 37 initializes and draws Picture 34
      await engine.initializeGame(startingRoom: 37);
      expect(engine.currentRoom, equals(37));
      expect(engine.currentPic?.picNumber, equals(34));

      // Capture a snapshot in Room 37
      final snap = engine.createSnapshot(label: 'Room 37 with Picture 34');
      expect(snap.pictureNumber, equals(34));

      // Now switch engine to Room 2 (Picture 2)
      engine.changeRoom(2);
      await engine.tick();
      expect(engine.currentPic?.picNumber, equals(2));

      // Restore the snapshot of Room 37
      engine.restoreSnapshot(snap);
      expect(engine.currentRoom, equals(37));
      expect(engine.currentPic, isNotNull);
      expect(engine.currentPic?.picNumber, equals(34), reason: 'Restoring Room 37 must restore Picture 34');

      // Restoring a snapshot with no pictureNumber sets currentPic to null (black screen)
      final noPicSnap = AgiGameStateSnapshot(
        timestamp: DateTime.now().toIso8601String(),
        roomNumber: 99,
        pictureNumber: null,
        cycleCount: 10,
        speedHz: 20.0,
        score: 0,
        maxScore: 250,
        soundOn: true,
        isPaused: false,
        isInputEnabled: true,
        lastSubmittedCommand: '',
        variables: const {},
        activeFlags: const [],
        activeControllers: const [],
        itemRooms: const {},
        strings: const {},
        objects: const [],
        callStack: const [],
        scanStartIp: 0,
      );

      engine.restoreSnapshot(noPicSnap);
      expect(engine.currentPic, isNull, reason: 'Restoring snapshot without pictureNumber must make screen black (null currentPic)');

      engine.dispose();
    });
  });
}
