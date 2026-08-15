import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

void main() {
  group('Sierra AGI Game Startup & Initialization', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0, randomSeed: 42);
    });

    tearDown(() {
      engine.dispose();
    });

    test('initializeGame sets authentic Sierra system registers', () {
      engine.initializeGame();

      // System Variables
      expect(engine.memory.getVar(0), 0, reason: '%v0 current.room is 0 on boot');
      expect(engine.memory.getVar(1), 0, reason: '%v1 previous.room is 0 on boot');
      expect(engine.memory.getVar(8), 10, reason: '%v8 free memory pages is 10');
      expect(engine.memory.getVar(20), 0, reason: '%v20 machine.type is 0 (IBM PC)');
      expect(engine.memory.getVar(22), 1, reason: '%v22 num.voices is 1 (PC speaker)');
      expect(engine.memory.getVar(24), 41, reason: '%v24 max.input.length is 41');
      expect(engine.memory.getVar(26), 0, reason: '%v26 monitor.type is 0 (EGA/RGB)');

      // System Flags
      expect(engine.memory.getFlag(5), isFalse, reason: '%f5 init.log reset after startup scan');
      expect(engine.memory.getFlag(9), isTrue, reason: '%f9 sound.on is true by default');
    });

    test('tick resets Flag 5 and other transient flags at post-scan', () {
      engine.memory.setFlag(1); // obscured
      engine.memory.setFlag(2); // have.input
      engine.memory.setFlag(4); // said.accepted
      engine.memory.setFlag(5); // init.log
      engine.memory.setFlag(6); // restart
      engine.memory.setFlag(12); // restore
      engine.memory.setVar(4, 1); // obj hit
      engine.memory.setVar(5, 2); // edge hit

      engine.tick();

      expect(engine.memory.getFlag(1), isFalse);
      expect(engine.memory.getFlag(2), isFalse);
      expect(engine.memory.getFlag(4), isFalse);
      expect(engine.memory.getFlag(5), isFalse);
      expect(engine.memory.getFlag(6), isFalse);
      expect(engine.memory.getFlag(12), isFalse);
      expect(engine.memory.getVar(4), 0);
      expect(engine.memory.getVar(5), 0);
    });

    test('simulates room 0 bootstrap: LOGIC 0 transitions to intro room 45', () {
      // Mock LOGIC 45: in init pass, assign %v3 = 100, return
      final logic45 = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x03, 0x64, // assignn(%v3, 100)
          0x00,             // return
        ]),
        messages: const [],
        logicNumber: 45,
      );

      // Mock LOGIC 0:
      // if (equaln(%v0, 0)) -> new.room(45)
      // if (isset(%f5)) -> call(45)
      // return
      final logic0 = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          // IF equaln(%v0, 0)
          0xFF,
          0x01, 0x00, 0x00, // equaln(%v0, 0)
          0xFF,
          0x03, 0x00,       // jump 3 bytes
          0x12, 0x2D,       // new.room(45)
          0x00,             // return
          // IF isset(%f5)
          0xFF,
          0x07, 0x05,       // isset(%f5)
          0xFF,
          0x03, 0x00,       // jump 3 bytes
          0x16, 0x2D,       // call(45)
          0x00,
          0x00,             // return
        ]),
        messages: const [],
        logicNumber: 0,
      );

      // Setup interpreter with logic 0 and logic 45
      engine.interpreter.delegate = _TestDelegate(engine, logic0, logic45);
      engine.interpreter.loadRootScript(logic0, scriptNumber: 0);

      // Execute boot cycle
      engine.interpreter.executeCycle();

      // Verify room 0 successfully bootstrapped into room 45 and executed logic 45
      expect(engine.memory.getVar(0), 45); // current.room is now 45
      expect(engine.memory.getVar(1), 0);  // previous.room is 0
      expect(engine.memory.getVar(3), 100); // logic 45 was called and executed
    });

    test('boots King\'s Quest III reference game and sets opening picture', () {
      final kq3Dir = Directory('reference_games/kings-quest-3');
      if (!kq3Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
      final kq3Engine = AgiGameEngine(resourceLoader: loader);

      kq3Engine.initializeGame();

      // KQ3 boots to room 45 (the opening title sequence)
      expect(kq3Engine.memory.getVar(0), 45, reason: 'KQ3 bootstrap should transition to intro room 45');
      expect(kq3Engine.currentPic, isNotNull, reason: 'Opening room picture should be loaded');

      kq3Engine.dispose();
    });

    test('boots King\'s Quest II reference game to opening room', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-2');
      final kq2Engine = AgiGameEngine(resourceLoader: loader);

      kq2Engine.initializeGame();

      // KQ2 transitions to room 97 (the intro/copyright screen)
      expect(kq2Engine.memory.getVar(0), 97, reason: 'KQ2 bootstrap should transition to intro room 97');
      expect(kq2Engine.currentPic, isNotNull, reason: 'Opening room picture should be loaded');

      kq2Engine.dispose();
    });

    test('boots King\'s Quest IV (AGI V3) reference game to opening room', () {
      final kq4Dir = Directory('reference_games/kings-quest-4-agi');
      if (!kq4Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-4-agi');
      final kq4Engine = AgiGameEngine(resourceLoader: loader);

      kq4Engine.initializeGame();

      expect(kq4Engine.memory.getVar(0), isNot(0), reason: 'KQ4 bootstrap should transition from room 0');
      expect(kq4Engine.currentPic, isNotNull, reason: 'Opening room picture should be loaded');

      kq4Engine.dispose();
    });
  });
}

class _TestDelegate extends DefaultAgiInterpreterDelegate {
  final AgiGameEngine engine;
  final AgiLogicScript logic0;
  final AgiLogicScript logic45;

  _TestDelegate(this.engine, this.logic0, this.logic45);

  @override
  AgiLogicScript? loadLogic(int logicNumber) {
    if (logicNumber == 0) return logic0;
    if (logicNumber == 45) return logic45;
    return null;
  }

  @override
  void onNewRoom(int roomNumber) {
    engine.interpreter.loadRootScript(logic0, scriptNumber: 0);
  }
}
