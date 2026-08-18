import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

void main() {
  group('AgiGameStateSnapshot & Diffing', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 42);
      final priBuf = PriorityBuffer();
      engine.currentPic = AgiPic(
        visualPixels: Uint8List(160 * 168),
        priorityBuffer: priBuf,
        slices: PictureSlicer.slice(
          visualPixels: Uint8List(160 * 168),
          priorityBuffer: priBuf,
        ),
      );
    });

    tearDown(() {
      engine.dispose();
    });

    test('captures and serializes game state to JSON round-trip', () {
      // Setup specific state
      engine.memory.setVar(0, 7); // Room 7
      engine.memory.setVar(3, 25); // Score 25
      engine.memory.setVar(6, 3); // Ego dir East
      engine.memory.setFlag(0); // on water
      engine.memory.setFlag(3); // ego signal
      engine.memory.setFlag(9); // sound
      engine.memory.itemRooms[1] = 0; // Item 1 in player inventory
      engine.memory.setString(0, 'look room');

      engine.ego.x = 95;
      engine.ego.y = 110;
      engine.ego.view = 2;
      engine.ego.loop = 1;
      engine.ego.cel = 3;
      engine.ego.priority = 8;
      engine.ego.isAnimated = true;
      engine.ego.isDrawn = true;

      // Spawn an NPC
      final npc = engine.animatedObjects[1];
      npc.isAnimated = true;
      npc.isDrawn = true;
      npc.x = 40;
      npc.y = 80;
      npc.view = 5;

      final snapshot = engine.createSnapshot(label: 'Test Snapshot');

      expect(snapshot.label, 'Test Snapshot');
      expect(snapshot.roomNumber, 7);
      expect(snapshot.score, 25);
      expect(snapshot.variables['0'], 7);
      expect(snapshot.variables['3'], 25);
      expect(snapshot.variables['6'], 3);
      expect(snapshot.activeFlags, containsAll([0, 3, 9]));
      expect(snapshot.itemRooms['1'], 0);
      expect(snapshot.strings['0'], 'look room');
      expect(snapshot.objects.length, 2);

      // JSON round-trip
      final jsonStr = snapshot.toJsonString();
      final decoded = AgiGameStateSnapshot.fromJsonString(jsonStr);

      expect(decoded.label, snapshot.label);
      expect(decoded.score, snapshot.score);
      expect(decoded.variables['3'], 25);
      expect(decoded.activeFlags, containsAll([0, 3, 9]));
      expect(decoded.strings['0'], 'look room');

      final egoSnap = decoded.objects.firstWhere((o) => o.number == 0);
      expect(egoSnap.x, 95);
      expect(egoSnap.y, 110);
      expect(egoSnap.view, 2);
      expect(egoSnap.cel, 3);
    });

    test('restores engine state completely from snapshot', () {
      // 1. Set initial state
      engine.memory.setVar(3, 50);
      engine.memory.setFlag(3);
      engine.ego.x = 120;
      engine.ego.y = 130;
      final snap = engine.createSnapshot(label: 'Checkpoint A');

      // 2. Mutate state
      engine.memory.setVar(3, 0);
      engine.memory.resetFlag(3);
      engine.ego.x = 10;
      engine.ego.y = 20;

      expect(engine.memory.getVar(3), 0);
      expect(engine.memory.getFlag(3), isFalse);
      expect(engine.ego.x, 10);

      // 3. Restore snapshot
      engine.restoreSnapshot(snap);

      expect(engine.memory.getVar(3), 50);
      expect(engine.memory.getFlag(3), isTrue);
      expect(engine.ego.x, 120);
      expect(engine.ego.y, 130);
    });

    test('computes accurate before and after state diff', () {
      engine.memory.setVar(0, 1);
      engine.memory.setVar(6, 1); // dir North
      engine.memory.resetFlag(0);
      engine.ego.x = 50;
      engine.ego.y = 70;
      final before = engine.createSnapshot(label: 'Before Action');

      // Action occurs: Ego moves East, hits trigger line f3, submits command
      engine.memory.setVar(6, 3); // dir East
      engine.memory.setFlag(3); // Trigger flag set
      engine.ego.x = 52;
      engine.submitCommand('open door');

      final after = engine.createSnapshot(label: 'After Action');

      final diff = AgiGameStateDiff(before, after);

      expect(diff.changedVariables[6], (1, 3));
      expect(diff.flagsSet, contains(3));
      expect(diff.flagsReset, isEmpty);
      expect(diff.objectChanges[0], contains('pos: (50, 70) -> (52, 70)'));

      final md = diff.toMarkdown();
      expect(md, contains('AGI Game State Diff'));
      expect(md, contains('`%v6 (ego_direction)`: `1` &rarr; `3`'));
      expect(md, contains('`%f3 (ego_signal / hit_special_2)` = ON'));
      expect(md, contains('Command Executed'));
    });

    test('manages rolling checkpoint history in game engine', () {
      expect(engine.checkpointHistory, isEmpty);

      engine.recordCheckpoint(label: 'Snap 1');
      engine.recordCheckpoint(label: 'Snap 2');

      expect(engine.checkpointHistory.length, 2);
      expect(engine.checkpointHistory[0].label, 'Snap 2');
      expect(engine.checkpointHistory[1].label, 'Snap 1');

      engine.removeCheckpoint(0);
      expect(engine.checkpointHistory.length, 1);
      expect(engine.checkpointHistory[0].label, 'Snap 1');

      engine.clearCheckpoints();
      expect(engine.checkpointHistory, isEmpty);
    });

    test('generates and serializes composite thumbnail and room transition flag', () {
      final snap = engine.createSnapshot(label: 'Thumbnail Test', isRoomTransition: true);

      expect(snap.isRoomTransition, isTrue);
      expect(snap.thumbnailRgba, isNotNull);
      expect(snap.thumbnailRgba!.length, 80 * 84 * 4);

      // JSON round-trip preserves thumbnail and room transition flag by default
      final jsonStr = snap.toJsonString();
      expect(jsonStr.contains('"thumbnail"'), isTrue);
      final decoded = AgiGameStateSnapshot.fromJsonString(jsonStr);

      expect(decoded.isRoomTransition, isTrue);
      expect(decoded.thumbnailRgba, isNotNull);
      expect(decoded.thumbnailRgba!.length, 80 * 84 * 4);

      // JSON string with includeThumbnail: false omits thumbnail
      final jsonNoThumb = snap.toJsonString(includeThumbnail: false);
      expect(jsonNoThumb.contains('"thumbnail"'), isFalse);
      final decodedNoThumb = AgiGameStateSnapshot.fromJsonString(jsonNoThumb);
      expect(decodedNoThumb.thumbnailRgba, isNull);
      expect(decodedNoThumb.roomNumber, snap.roomNumber);
      expect(decodedNoThumb.cycleCount, snap.cycleCount);
    });

    test('automatically captures rolling 5 room transition checkpoints upon room change', () {
      expect(engine.roomCheckpoints, isEmpty);

      // Simulate room transitions
      for (int room = 1; room <= 7; room++) {
        engine.changeRoom(room);
        expect(engine.memory.getFlag(5), isTrue);
        engine.tick(); // Post-scan executes and captures room transition checkpoint
      }

      // Room checkpoints should be capped at 5
      expect(engine.roomCheckpoints.length, 5);
      expect(engine.roomCheckpoints[0].roomNumber, 7);
      expect(engine.roomCheckpoints[0].isRoomTransition, isTrue);
      expect(engine.roomCheckpoints[0].label, '🚪 Room 7 Entrance');
      expect(engine.roomCheckpoints[1].roomNumber, 6);
      expect(engine.roomCheckpoints[2].roomNumber, 5);
      expect(engine.roomCheckpoints[3].roomNumber, 4);
      expect(engine.roomCheckpoints[4].roomNumber, 3);

      // Old room transition checkpoints are garbage-collected from global checkpoint history
      expect(engine.checkpointHistory.length, 5);
      expect(engine.checkpointHistory.every((s) => s.isRoomTransition), isTrue);
    });

    test('resuming/restoring a room transition checkpoint does not create duplicate room checkpoint on subsequent ticks', () {
      engine.changeRoom(3);
      engine.tick();

      expect(engine.roomCheckpoints.length, 1);
      final room3Snap = engine.roomCheckpoints.first;

      // Advance to Room 4
      engine.changeRoom(4);
      engine.tick();
      expect(engine.roomCheckpoints.length, 2);

      // Restore Room 3 snapshot
      engine.restoreSnapshot(room3Snap);
      expect(engine.memory.getFlag(5), isFalse);
      expect(engine.memory.getFlag(12), isTrue);

      // Tick several cycles
      engine.tick();
      engine.tick();
      engine.tick();

      // Should still be only 2 room checkpoints, no duplicate Room 3 entrance created on resume
      expect(engine.roomCheckpoints.length, 2);
      expect(engine.checkpointHistory.length, 2);
      expect(engine.memory.getFlag(5), isFalse);
    });

    test('restoring snapshot preserves whatever pause state the engine is currently in', () {
      final snap = engine.createSnapshot(label: 'Running Snapshot');
      expect(snap.isPaused, isFalse);

      // Scenario 1: Engine is paused (e.g. in Debug Workbench) -> restore keeps it paused
      engine.pause();
      expect(engine.isPaused, isTrue);

      engine.restoreSnapshot(snap);
      expect(engine.isPaused, isTrue, reason: 'Restoring snapshot while paused must keep engine paused');

      // Scenario 2: Engine is running -> restore keeps it running
      engine.resume();
      expect(engine.isPaused, isFalse);

      engine.restoreSnapshot(snap);
      expect(engine.isPaused, isFalse, reason: 'Restoring snapshot while running must keep engine running');
    });

    test('captures, serializes, and restores add.to.pic background modifications', () {
      expect(engine.addToPicCalls, isEmpty);

      // Trigger add.to.pic calls
      engine.onAddToPic(10, 0, 1, 40, 50, 4, 0);
      engine.onAddToPic(12, 1, 0, 80, 90, 8, 4);

      expect(engine.addToPicCalls.length, 2);
      expect(engine.addToPicCalls[0].view, 10);
      expect(engine.addToPicCalls[0].x, 40);
      expect(engine.addToPicCalls[1].view, 12);
      expect(engine.addToPicCalls[1].priority, 8);
      expect(engine.addToPicCalls[1].boxPriority, 4);

      // Capture snapshot
      final snap = engine.createSnapshot(label: 'Add to pic test');
      expect(snap.addToPicEntries.length, 2);
      expect(snap.addToPicEntries[0].view, 10);
      expect(snap.addToPicEntries[1].view, 12);

      // JSON round-trip
      final jsonStr = snap.toJsonString();
      final decoded = AgiGameStateSnapshot.fromJsonString(jsonStr);
      expect(decoded.addToPicEntries.length, 2);
      expect(decoded.addToPicEntries[0].view, 10);
      expect(decoded.addToPicEntries[0].y, 50);
      expect(decoded.addToPicEntries[1].view, 12);
      expect(decoded.addToPicEntries[1].boxPriority, 4);

      // Changing room clears addToPicCalls
      engine.changeRoom(8);
      expect(engine.addToPicCalls, isEmpty);

      // Restoring snapshot repopulates addToPicCalls
      engine.restoreSnapshot(decoded);
      expect(engine.addToPicCalls.length, 2);
      expect(engine.addToPicCalls[0].view, 10);
      expect(engine.addToPicCalls[1].view, 12);
    });
  });
}
