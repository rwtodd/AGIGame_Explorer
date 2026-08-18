import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

class _MockInterpreterDelegate extends AgiInterpreterDelegate {
  final Map<int, AgiLogicScript> loadedLogics = {};

  @override
  AgiLogicScript? loadLogic(int number) => loadedLogics[number];

  @override
  void onNewRoom(int roomNumber) {}
}

void main() {
  group('Per-Script Scan Start & Space Quest 2 Intro Tests', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('set.scan.start is isolated per-logic script and does not corrupt Logic 0', () {
      final memory = AgiMemory();
      final delegate = _MockInterpreterDelegate();
      final interpreter = AgiLogicInterpreter(
        memory: memory,
        delegate: delegate,
      );

      // Logic 0: Calls sub-logic 140, then returns
      // 0x16 0x8C (call 140), 0x00 (return)
      final logic0 = AgiLogicScript(
        bytecodes: Uint8List.fromList([22, 140, 0]),
        messages: const [],
      );

      // Logic 140:
      // 0x91 (set.scan.start), 0x01 0x0A (increment var 10), 0x00 (return)
      final logic140 = AgiLogicScript(
        bytecodes: Uint8List.fromList([145, 1, 10, 0]),
        messages: const [],
      );

      // Logic 2 (new room):
      // 0x00 (return)
      final logic2 = AgiLogicScript(
        bytecodes: Uint8List.fromList([0]),
        messages: const [],
      );

      delegate.loadedLogics[0] = logic0;
      delegate.loadedLogics[140] = logic140;
      delegate.loadedLogics[2] = logic2;

      interpreter.loadRootScript(logic0, scriptNumber: 0);

      // Cycle 1: Logic 0 calls Logic 140.
      // Logic 140 sets its scan start to 1 (past opcode 145), increments var 10 -> 1, returns.
      interpreter.executeCycle();
      expect(memory.getVar(10), 1);
      expect(memory.getScanStart(0), 0, reason: 'Logic 0 scan start must remain 0');
      expect(memory.getScanStart(140), 1, reason: 'Logic 140 scan start must be 1');

      // Cycle 2: Logic 0 executes again from 0.
      // Calls Logic 140, which now starts at startIp=1 (increment var 10 directly).
      interpreter.executeCycle();
      expect(memory.getVar(10), 2);
      expect(memory.getScanStart(0), 0);
      expect(memory.getScanStart(140), 1);

      // Logic 0 calls new.room(2): [18, 2, 0]
      final logic0WithNewRoom = AgiLogicScript(
        bytecodes: Uint8List.fromList([18, 2, 0]),
        messages: const [],
      );
      delegate.loadedLogics[0] = logic0WithNewRoom;
      interpreter.loadRootScript(logic0WithNewRoom, scriptNumber: 0);
      interpreter.executeCycle();

      expect(memory.getScanStart(140), 0, reason: 'New room must reset non-root scan starts');
      expect(memory.getScanStart(0), 0);
    });

    test('Space Quest 2 runs intro past cycle 600 without opcode 0xfd error', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      for (int cycle = 1; cycle <= 600; cycle++) {
        await engine.tick();
        expect(engine.lastError, isNull,
            reason: 'Engine must not throw in cycle $cycle');
      }

      expect(engine.currentRoom, 140);
      engine.dispose();
    });

    test('AgiGameStateSnapshot preserves and restores per-script scan starts', () {
      final memory = AgiMemory();
      memory.setScanStart(0, 10);
      memory.setScanStart(140, 25);

      final snapshot = AgiGameStateSnapshot(
        timestamp: DateTime.now().toIso8601String(),
        roomNumber: 140,
        cycleCount: 100,
        speedHz: 20.0,
        score: 0,
        maxScore: 250,
        soundOn: true,
        isPaused: false,
        isInputEnabled: true,
        lastSubmittedCommand: '',
        variables: {},
        activeFlags: [],
        activeControllers: [],
        itemRooms: {},
        strings: {},
        objects: [],
        callStack: [],
        scanStartIp: 10,
        scanStarts: {'0': 10, '140': 25},
      );

      final json = snapshot.toJson();
      final restoredSnap = AgiGameStateSnapshot.fromJson(json);

      expect(restoredSnap.scanStarts['0'], 10);
      expect(restoredSnap.scanStarts['140'], 25);
    });
  });
}
