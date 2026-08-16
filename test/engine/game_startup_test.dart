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

    test('boots King\'s Quest III reference game and simulates opening sequence', () {
      final kq3Dir = Directory('reference_games/kings-quest-3');
      if (!kq3Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
      final kq3Engine = AgiGameEngine(resourceLoader: loader);

      kq3Engine.initializeGame();

      expect(kq3Engine.memory.getVar(0), 45, reason: 'KQ3 bootstrap should transition to intro room 45');
      expect(kq3Engine.currentPic, isNotNull, reason: 'Opening room picture should be loaded');
      expect(kq3Engine.isStatusLineEnabled, isFalse, reason: 'Status line should be disabled during intro');
      expect(kq3Engine.isInputEnabled, isFalse, reason: 'Input prompt should be disabled during intro');

      // Simulate 10 seconds of intro (200 cycles at 20 Hz)
      for (int t = 1; t <= 200; t++) {
        kq3Engine.tick();
      }

      expect(kq3Engine.memory.getVar(0), 45);
      expect(kq3Engine.lastError, isNull);

      // Now press a key (e.g. Enter / 13) to skip the intro
      kq3Engine.handleKeyPress(13);
      kq3Engine.tick();

      // Pressing a key during intro skips directly to gameplay in room 7
      expect(kq3Engine.memory.getVar(0), 7, reason: 'Pressing key during intro should skip to room 7');
      expect(kq3Engine.isStatusLineEnabled, isTrue, reason: 'Status line should be enabled in gameplay room 7');
      expect(kq3Engine.isInputEnabled, isTrue, reason: 'Input prompt should be enabled in gameplay room 7');

      kq3Engine.dispose();
    });

    test('add.to.pic respects background priority and masks "III" behind ribbon', () {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
      final kq3Engine = AgiGameEngine(resourceLoader: loader);
      kq3Engine.initializeGame();

      // In room 45, PIC 45 has the red/gold banner at y=80..100 with Priority 15.
      // add.to.pic with pri=4 should not overwrite the priority 15 ribbon banner.
      final pic = kq3Engine.currentPic!;
      
      // Check that ribbon center remains red (12) or gold (14) with priority 15
      expect(pic.priorityBuffer.priorityAt(75, 85), 15, reason: 'Ribbon banner must maintain priority 15');
      expect(pic.visualPixels[85 * 160 + 75], isIn([12, 14]), reason: 'Ribbon color must remain intact behind III');

      // Check that top of III is drawn at priority 4
      expect(pic.priorityBuffer.priorityAt(75, 60), 4, reason: 'Top of III must be stamped with priority 4');

      kq3Engine.dispose();
    });

    test('boots King\'s Quest II reference game, types look, and verifies single-shot dialog response', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-2');
      final kq2Engine = AgiGameEngine(resourceLoader: loader);

      kq2Engine.initializeGame();

      // KQ2 transitions to room 97 (the intro/copyright screen)
      expect(kq2Engine.memory.getVar(0), 97, reason: 'KQ2 bootstrap should transition to intro room 97');
      expect(kq2Engine.currentPic, isNotNull, reason: 'Opening room picture should be loaded');

      // Transition to room 1 (first gameplay screen)
      kq2Engine.changeRoom(1);
      expect(kq2Engine.memory.getVar(0), 1);

      // Run a cycle in room 1 to initialize
      kq2Engine.tick();
      expect(kq2Engine.activeDialog, isNull);

      // Type "look"
      kq2Engine.submitCommand('look');
      expect(kq2Engine.memory.getFlag(2), isTrue, reason: 'Flag 2 must be set on command submission');

      // Run tick: room 1 logic responds to "look" with a dialog
      kq2Engine.tick();
      expect(kq2Engine.activeDialog, isNotNull, reason: 'Dialog should appear in response to look command');

      // Dismiss dialog
      kq2Engine.dismissDialog();
      expect(kq2Engine.activeDialog, isNull);

      // Run subsequent cycles: dialog must NOT reappear
      for (var i = 0; i < 50; i++) {
        kq2Engine.tick();
        expect(kq2Engine.activeDialog, isNull, reason: 'Dialog must not reopen on subsequent cycle $i');
      }

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

    test('boots The Black Cauldron reference game and survives idle cycles in room 8 without dying', () {
      final bcDir = Directory('reference_games/black-cauldron');
      if (!bcDir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync('reference_games/black-cauldron');
      final bcEngine = AgiGameEngine(resourceLoader: loader);

      bcEngine.initializeGame();

      // Bootstrap transitions to title screen (room 67)
      expect(bcEngine.memory.getVar(0), 67, reason: 'Black Cauldron bootstrap should transition to title room 67');

      // Now transition to room 8 (first gameplay screen)
      bcEngine.changeRoom(8);
      expect(bcEngine.memory.getVar(0), 8);

      // Run for 500 cycles (~25 seconds of idle gameplay)
      for (var cycle = 0; cycle < 500; cycle++) {
        bcEngine.tick();
      }

      // Variable 93 (pig.timer.1) must stay 0 and not underflow to 255
      expect(bcEngine.memory.getVar(93), 0, reason: 'pig.timer.1 (var 93) must not underflow');

      // Variable 59 (certain.death) must be 0
      expect(bcEngine.memory.getVar(59), 0, reason: 'certain.death (var 59) must remain 0');

      // Variable 102 (current.status) must not be 13 (dead)
      expect(bcEngine.memory.getVar(102), isNot(13), reason: 'Ego must remain alive');

      // Now walk Ego South from Room 8 down to Room 13
      bcEngine.ego.x = 31;
      bcEngine.ego.y = 166;
      bcEngine.setEgoDirection(5); // South
      bcEngine.tick(); // moves to 167
      bcEngine.tick(); // crosses 167 -> triggers %v2 = 3 (bottom edge)

      // Script handles bottom edge and calls new.room(13)
      expect(bcEngine.memory.getVar(0), 13, reason: 'Ego should have transitioned to room 13');
      expect(bcEngine.horizon, 48, reason: 'Room 13 horizon should be 48');
      expect(bcEngine.ego.y, greaterThanOrEqualTo(49), reason: 'Ego Y must be below Room 13 horizon 48');

      // Run multiple cycles in Room 13; it must NOT bounce back to Room 8
      for (var i = 0; i < 50; i++) {
        bcEngine.tick();
        expect(bcEngine.memory.getVar(0), 13, reason: 'Room 13 must not bounce back to Room 8 on cycle $i');
      }

      bcEngine.dispose();
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
