import 'dart:convert';
import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late AgiGameEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agi_save_test_');
    engine = AgiGameEngine();
    engine.saveDirectory = tempDir;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GameStateSerializer JSON Serialization & Deserialization', () {
    test('serializes complete engine state to JSON map matching specification', () {
      final mem = engine.memory;
      mem.setVar(0, 14); // current room 14
      mem.setVar(1, 12); // previous room 12
      mem.setVar(3, 42); // score 42
      mem.setVar(7, 210); // max score 210
      mem.setVar(100, 255); // boundary variable
      mem.setFlag(9); // sound on
      mem.setFlag(50); // custom flag
      mem.setString(0, 'Kings Quest');
      mem.setString(5, 'Magic Mirror');
      mem.itemRooms[0] = 0; // in inventory
      mem.itemRooms[1] = 14; // in room 14
      mem.scanStartIp = 42;

      // Configure Ego and NPC
      final ego = engine.animatedObjects[0];
      ego.x = 80;
      ego.y = 120;
      ego.view = 1;
      ego.loop = 2;
      ego.cel = 3;
      ego.priority = 10;
      ego.fixedPriority = true;
      ego.isDrawn = true;
      ego.isAnimated = true;

      final npc = engine.animatedObjects[1];
      npc.x = 40;
      npc.y = 60;
      npc.view = 5;
      npc.isDrawn = true;

      final serialized = GameStateSerializer.serialize(
        engine,
        description: 'Before Dragon Lair',
      );

      expect(serialized['version'], equals('1.0'));
      expect(serialized['label'], equals('Before Dragon Lair'));
      expect(serialized['roomNumber'], equals(14));
      expect(serialized['score'], equals(42));
      expect(serialized['maxScore'], equals(210));
      expect(serialized['scanStartIp'], equals(42));
      expect(serialized['thumbnail'], isNotNull);

      // Variables
      final vars = serialized['variables'] as Map<String, dynamic>;
      expect(vars['0'], equals(14));
      expect(vars['1'], equals(12));
      expect(vars['3'], equals(42));
      expect(vars['7'], equals(210));
      expect(vars['100'], equals(255));

      // Flags
      final activeFlags = (serialized['activeFlags'] as List).cast<int>();
      expect(activeFlags, contains(9));
      expect(activeFlags, contains(50));
      expect(activeFlags, isNot(contains(51)));

      // Strings
      final strings = serialized['strings'] as Map<String, dynamic>;
      expect(strings['0'], equals('Kings Quest'));
      expect(strings['5'], equals('Magic Mirror'));

      // Items
      final items = serialized['itemRooms'] as Map<String, dynamic>;
      expect(items['0'], equals(0));
      expect(items['1'], equals(14));

      // Objects
      final objs = serialized['objects'] as List;
      expect(objs, isNotEmpty);
      final egoSnap = objs.firstWhere((o) => o['number'] == 0);
      expect(egoSnap['x'], equals(80));
      expect(egoSnap['y'], equals(120));
      expect(egoSnap['view'], equals(1));
      expect(egoSnap['loop'], equals(2));
      expect(egoSnap['cel'], equals(3));
      expect(egoSnap['priority'], equals(10));
      expect(egoSnap['fixedPriority'], isTrue);
    });

    test('round-trips full state through JSON string serialization and deserialization', () {
      final mem = engine.memory;
      mem.setVar(0, 7);
      mem.setVar(3, 85);
      mem.setVar(7, 150);
      mem.setVar(200, 128);
      mem.resetFlag(5); // Ensure flag 5 is false when saved
      mem.setFlag(10); // debug mode
      mem.setFlag(100);
      mem.setString(2, 'Sword of Power');
      mem.itemRooms[3] = 0;
      mem.itemRooms[4] = 7;

      final ego = engine.animatedObjects[0];
      ego.x = 95;
      ego.y = 140;
      ego.view = 2;
      ego.isDrawn = true;
      ego.isAnimated = true;

      // Serialize to JSON string
      final jsonString = GameStateSerializer.serializeToJson(
        engine,
        description: 'Near Castle Gate',
      );

      // Create new fresh target engine
      final targetEngine = AgiGameEngine();
      expect(targetEngine.memory.getVar(0), equals(0));
      expect(targetEngine.memory.getVar(3), equals(0));
      expect(targetEngine.memory.getFlag(100), isFalse);

      // Deserialize
      GameStateSerializer.deserializeFromJson(jsonString, targetEngine);

      expect(targetEngine.memory.getVar(0), equals(7));
      expect(targetEngine.memory.getVar(3), equals(85));
      expect(targetEngine.memory.getVar(7), equals(150));
      expect(targetEngine.memory.getVar(200), equals(128));
      expect(targetEngine.memory.getFlag(10), isTrue);
      expect(targetEngine.memory.getFlag(100), isTrue);
      expect(targetEngine.memory.getString(2), equals('Sword of Power'));
      expect(targetEngine.memory.itemRooms[3], equals(0));
      expect(targetEngine.memory.itemRooms[4], equals(7));

      // Restore flags in AGI specification (Flag 12 is set, Flag 5 is NOT set)
      expect(targetEngine.memory.getFlag(5), isFalse); // Flag 5 = new_room is NOT set on restore
      expect(targetEngine.memory.getFlag(12), isTrue); // Flag 12 = restore_in_progress is set

      // Objects restored
      final restoredEgo = targetEngine.animatedObjects[0];
      expect(restoredEgo.x, equals(95));
      expect(restoredEgo.y, equals(140));
      expect(restoredEgo.view, equals(2));
      expect(restoredEgo.isDrawn, isTrue);
    });

    test('backward-compatibility: deserializes legacy format save game files', () {
      final legacyJson = jsonEncode({
        'version': '1.0',
        'description': 'Legacy Save File',
        'currentRoom': 22,
        'score': 55,
        'scoreMax': 100,
        'variables': [0, 0, 0, 55, 0, 0, 0, 100, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 22],
        'flags': [false, false, false, false, false, false, false, false, false, true, false, false, false, true],
        'strings': {'0': 'Legacy String'},
        'itemRooms': {'1': 22},
        'animatedObjects': [
          {
            'number': 0,
            'x': 50,
            'y': 60,
            'view': 1,
            'loop': 0,
            'cel': 0,
            'priority': 4,
            'fixedPriority': false,
            'isDrawn': true,
            'isAnimated': true,
          }
        ]
      });

      final targetEngine = AgiGameEngine();
      GameStateSerializer.deserializeFromJson(legacyJson, targetEngine);

      expect(targetEngine.memory.getVar(3), equals(55));
      expect(targetEngine.memory.getVar(7), equals(100));
      expect(targetEngine.memory.getVar(21), equals(22));
      expect(targetEngine.memory.getFlag(9), isTrue);
      expect(targetEngine.memory.getFlag(13), isTrue);
      expect(targetEngine.memory.getString(0), equals('Legacy String'));
      expect(targetEngine.memory.itemRooms[1], equals(22));
      expect(targetEngine.animatedObjects[0].x, equals(50));
      expect(targetEngine.animatedObjects[0].y, equals(60));
    });
  });

  group('Multi-Slot Save & Restore File Management', () {
    test('saveToSlot writes slot_N.sav file with atomic rename', () async {
      engine.memory.setVar(0, 5);
      engine.memory.setVar(3, 20);

      final file = await GameStateSerializer.saveToSlot(
        engine,
        1,
        description: 'Test Slot 1',
        directory: tempDir,
      );

      expect(await file.exists(), isTrue);
      expect(file.path.endsWith('slot_1.sav'), isTrue);

      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      expect(map['label'], equals('Test Slot 1'));
      expect(map['roomNumber'], equals(5));
      expect(map['score'], equals(20));
      expect(map['thumbnail'], isNotNull);
    });

    test('listSlots returns info for all 12 slots with accurate exists flag and metadata', () async {
      // Save slots 1 and 3
      engine.memory.setVar(0, 10);
      engine.memory.setVar(3, 50);
      engine.memory.setVar(7, 100);
      await GameStateSerializer.saveToSlot(
        engine,
        1,
        description: 'First Save',
        directory: tempDir,
      );

      engine.memory.setVar(0, 25);
      engine.memory.setVar(3, 75);
      await GameStateSerializer.saveToSlot(
        engine,
        3,
        description: 'Third Save',
        directory: tempDir,
      );

      final slots = await GameStateSerializer.listSlots(
        directory: tempDir,
        maxSlots: 12,
      );

      expect(slots.length, equals(12));

      // Slot 1
      expect(slots[0].slot, equals(1));
      expect(slots[0].exists, isTrue);
      expect(slots[0].description, equals('First Save'));
      expect(slots[0].roomNumber, equals(10));
      expect(slots[0].score, equals(50));
      expect(slots[0].maxScore, equals(100));
      expect(slots[0].displayName, equals('Slot 1: First Save'));

      // Slot 2 (empty)
      expect(slots[1].slot, equals(2));
      expect(slots[1].exists, isFalse);
      expect(slots[1].displayName, equals('Slot 2: < Empty >'));

      // Slot 3
      expect(slots[2].slot, equals(3));
      expect(slots[2].exists, isTrue);
      expect(slots[2].description, equals('Third Save'));
      expect(slots[2].roomNumber, equals(25));
      expect(slots[2].score, equals(75));

      // Slot 12 (empty)
      expect(slots[11].slot, equals(12));
      expect(slots[11].exists, isFalse);
    });

    test('restoreFromSlot successfully restores saved state from disk', () async {
      engine.memory.setVar(0, 18);
      engine.memory.setVar(3, 99);
      engine.memory.setFlag(77);
      engine.ego.x = 110;
      engine.ego.y = 130;

      await GameStateSerializer.saveToSlot(
        engine,
        2,
        description: 'Slot 2 Checkpoint',
        directory: tempDir,
      );

      // Mutate engine state
      engine.memory.setVar(0, 1);
      engine.memory.setVar(3, 0);
      engine.memory.resetFlag(77);
      engine.ego.x = 10;
      engine.ego.y = 10;

      // Restore from slot 2
      final success = await GameStateSerializer.restoreFromSlot(
        engine,
        2,
        directory: tempDir,
      );

      expect(success, isTrue);
      expect(engine.memory.getVar(0), equals(18));
      expect(engine.memory.getVar(3), equals(99));
      expect(engine.memory.getFlag(77), isTrue);
      expect(engine.memory.getFlag(5), isFalse);
      expect(engine.memory.getFlag(12), isTrue);
      expect(engine.ego.x, equals(110));
      expect(engine.ego.y, equals(130));
    });

    test('restoreFromSlot returns false when slot file does not exist', () async {
      final success = await GameStateSerializer.restoreFromSlot(
        engine,
        9,
        directory: tempDir,
      );
      expect(success, isFalse);
    });

    test('deleteSlot removes slot file from disk', () async {
      await GameStateSerializer.saveToSlot(
        engine,
        5,
        description: 'To Delete',
        directory: tempDir,
      );

      var info = await GameStateSerializer.getSlotInfo(5, directory: tempDir);
      expect(info, isNotNull);
      expect(info!.exists, isTrue);

      final deleted = await GameStateSerializer.deleteSlot(5, directory: tempDir);
      expect(deleted, isTrue);

      info = await GameStateSerializer.getSlotInfo(5, directory: tempDir);
      expect(info, isNull);
    });

    test('restoring game preserves non-Ego animated objects (e.g. NPC wandering characters)', () async {
      // Room 9 with Ego (Object 0) and Red Riding Hood (Object 2)
      engine.memory.setVar(0, 9);
      engine.ego.x = 11;
      engine.ego.y = 61;
      engine.ego.isDrawn = true;

      final npc = engine.animatedObjects[2];
      npc.view = 2;
      npc.loop = 2;
      npc.cel = 1;
      npc.x = 61;
      npc.y = 166;
      npc.direction = 5;
      npc.isAnimated = true;
      npc.isDrawn = true;
      npc.isUpdating = true;
      npc.isCycling = true;
      npc.motionType = 1;

      // Save to slot 1
      await GameStateSerializer.saveToSlot(engine, 1, directory: tempDir);

      // Mutate engine state (e.g. player moves to room 2, npc is gone)
      engine.memory.setVar(0, 2);
      engine.ego.x = 80;
      engine.ego.y = 80;
      npc.reset();
      expect(npc.isDrawn, isFalse);

      // Restore slot 1
      final success = await GameStateSerializer.restoreFromSlot(engine, 1, directory: tempDir);
      expect(success, isTrue);

      // Verify room and Ego restored
      expect(engine.memory.getVar(0), equals(9));
      expect(engine.ego.x, equals(11));
      expect(engine.ego.y, equals(61));

      // Verify NPC Object 2 was NOT wiped and is intact
      final restoredNpc = engine.animatedObjects[2];
      expect(restoredNpc.isDrawn, isTrue);
      expect(restoredNpc.isAnimated, isTrue);
      expect(restoredNpc.view, equals(2));
      expect(restoredNpc.loop, equals(2));
      expect(restoredNpc.cel, equals(1));
      expect(restoredNpc.x, equals(61));
      expect(restoredNpc.y, equals(166));
      expect(restoredNpc.direction, equals(5));
      expect(restoredNpc.motionType, equals(1));
      expect(restoredNpc.isUpdating, isTrue);
      expect(restoredNpc.isCycling, isTrue);
    });

    test('save and restore preserves custom horizon, activeBlock, loadedLogics, and addToPicCalls with thumbnails', () async {
      engine.horizon = 48;
      engine.onBlock(20, 30, 80, 90);
      engine.loadLogic(104);
      engine.onAddToPic(5, 0, 0, 100, 120, 4, 3);

      await GameStateSerializer.saveToSlot(
        engine,
        4,
        description: 'Custom Barrier Room',
        directory: tempDir,
      );

      // Verify slot info has thumbnail
      final slotInfo = await GameStateSerializer.getSlotInfo(4, directory: tempDir);
      expect(slotInfo, isNotNull);
      expect(slotInfo!.exists, isTrue);
      expect(slotInfo.description, equals('Custom Barrier Room'));
      expect(slotInfo.thumbnailRgba, isNotNull);
      expect(slotInfo.thumbnailRgba!.length, 80 * 84 * 4);

      // Reset engine horizon, block, and change room
      engine.horizon = 36;
      engine.onUnblock();
      engine.changeRoom(2);
      expect(engine.horizon, 36);
      expect(engine.activeBlock, isNull);
      expect(engine.addToPicCalls, isEmpty);

      // Restore
      final restored = await GameStateSerializer.restoreFromSlot(engine, 4, directory: tempDir);
      expect(restored, isTrue);

      expect(engine.horizon, equals(48));
      expect(engine.activeBlock, isNotNull);
      expect(engine.activeBlock!.x1, equals(20));
      expect(engine.activeBlock!.y1, equals(30));
      expect(engine.activeBlock!.x2, equals(80));
      expect(engine.activeBlock!.y2, equals(90));
      expect(engine.loadedLogicNumbers, contains(104));
      expect(engine.addToPicCalls.length, 1);
      expect(engine.addToPicCalls[0].view, 5);
      expect(engine.addToPicCalls[0].x, 100);
      expect(engine.addToPicCalls[0].y, 120);
      expect(engine.addToPicCalls[0].boxPriority, 3);
    });
  });

  group('AgiGameEngine restartGame & cancelRestart lifecycle tests', () {
    test('restartGame resets memory, animated objects, and raises Flag 5, 6, 11', () {
      // Dirty the engine state
      engine.memory.setVar(0, 44);
      engine.memory.setVar(3, 150);
      engine.memory.setVar(50, 200);
      engine.memory.setFlag(20);
      engine.ego.x = 120;
      engine.ego.y = 150;

      engine.restartGame();

      // System variables reset
      expect(engine.memory.getVar(0), equals(0));
      expect(engine.memory.getVar(1), equals(0));
      expect(engine.memory.getVar(8), equals(10)); // free memory pages
      expect(engine.memory.getVar(20), equals(0)); // IBM PC machine type
      expect(engine.memory.getVar(22), equals(1)); // PC speaker sound
      expect(engine.memory.getVar(24), equals(41)); // max input length
      expect(engine.memory.getVar(50), equals(0)); // custom var reset

      // System flags
      expect(engine.memory.getFlag(9), isTrue); // sound on
      expect(engine.memory.getFlag(11), isTrue); // logic 0 run first time
      expect(engine.memory.getFlag(20), isFalse); // custom flag reset

      // Objects reset
      expect(engine.ego.x, equals(0));
      expect(engine.ego.y, equals(0));
    });

    test('cancelRestart raises Flag 16 (restart cancelled)', () {
      expect(engine.memory.getFlag(16), isFalse);
      engine.cancelRestart();
      expect(engine.memory.getFlag(16), isTrue);
    });
  });
}
