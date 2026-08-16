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
  });
}
