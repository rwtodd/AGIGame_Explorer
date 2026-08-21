import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

class MockInterpreterDelegate extends DefaultAgiInterpreterDelegate {
  final List<String> printedMessages = [];
  final List<int> roomChanges = [];
  final List<int> soundsPlayed = [];
  final Map<int, AgiLogicScript> subLogics = {};
  List<int>? lastSaidChecked;
  bool nextSaidResult = false;

  @override
  void onPrint(String message, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    printedMessages.add(message);
  }

  @override
  void onNewRoom(int roomNumber) {
    roomChanges.add(roomNumber);
  }

  @override
  void onSound(int soundNumber, int completionFlag) {
    soundsPlayed.add(soundNumber);
  }

  @override
  AgiLogicScript? loadLogic(int logicNumber) {
    return subLogics[logicNumber];
  }

  @override
  bool checkSaid(List<int> wordGroupIds) {
    lastSaidChecked = wordGroupIds;
    return nextSaidResult;
  }

  List<dynamic>? lastPrintAtParams;

  @override
  void onPrintAt(String message, int row, int col, int width, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    lastPrintAtParams = [message, row, col, width, isModal, timeoutHalfSeconds];
  }

  List<int>? configuredScreenParams;

  @override
  void onConfigureScreen(int playTop, int inputLine, int statusLine) {
    configuredScreenParams = [playTop, inputLine, statusLine];
  }
}

void main() {
  group('AgiLogicInterpreter', () {
    late AgiMemory memory;
    late MockInterpreterDelegate delegate;
    late AgiLogicInterpreter vm;

    setUp(() {
      memory = AgiMemory();
      delegate = MockInterpreterDelegate();
      vm = AgiLogicInterpreter(
        memory: memory,
        delegate: delegate,
        randomSeed: 42,
      );
    });

    test('executes arithmetic and assignment opcodes', () {
      // assignn(%v0, 50) -> 03 00 32
      // assignv(%v1, %v0) -> 04 01 00
      // addn(%v0, 10)     -> 05 00 0A
      // addv(%v0, %v1)    -> 06 00 01
      // subn(%v0, 20)     -> 07 00 14
      // mul.n(%v1, 2)     -> A5 01 02
      // div.n(%v1, 5)     -> A7 01 05
      // return            -> 00
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x00, 0x32,
          0x04, 0x01, 0x00,
          0x05, 0x00, 0x0A,
          0x06, 0x00, 0x01,
          0x07, 0x00, 0x14,
          0xA5, 0x01, 0x02,
          0xA7, 0x01, 0x05,
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();

      expect(status, InterpreterStatus.completed);
      // %v0: 50 -> +10 = 60 -> +50 = 110 -> -20 = 90
      expect(memory.getVar(0), 90);
      // %v1: 50 -> *2 = 100 -> /5 = 20
      expect(memory.getVar(1), 20);
    });

    test('executes indirect variable operations (lindirect, rindirect)', () {
      // assignn(%v1, 10)       -> 03 01 0A
      // assignn(%v2, 20)       -> 03 02 14
      // assignn(%v10, 99)      -> 03 0A 63
      // lindirectn(%v1, 77)    -> 0B 01 4D (%v10 = 77)
      // rindirect(%v2, %v1)    -> 0A 02 01 (%v2 = %v10 = 77)
      // assignn(%v3, 10)       -> 03 03 0A
      // assignn(%v4, 100)      -> 03 04 64
      // lindirectv(%v3, %v4)   -> 09 03 04 (%v10 = %v4 = 100)
      // return                 -> 00
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x01, 0x0A,
          0x03, 0x02, 0x14,
          0x03, 0x0A, 0x63,
          0x0B, 0x01, 0x4D,
          0x0A, 0x02, 0x01,
          0x03, 0x03, 0x0A,
          0x03, 0x04, 0x64,
          0x09, 0x03, 0x04,
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(2), 77);
      expect(memory.getVar(10), 100);
    });

    test('executes flag operations and variable flag operations', () {
      // set(%f1)          -> 0C 01
      // toggle(%f1)       -> 0E 01
      // assignn(%v0, 10)  -> 03 00 0A
      // set.v(%v0)        -> 0F 00 (%f10 = true)
      // toggle.v(%v0)     -> 11 00 (%f10 = false)
      // return            -> 00
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x0C, 0x01,
          0x0E, 0x01,
          0x03, 0x00, 0x0A,
          0x0F, 0x00,
          0x11, 0x00,
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getFlag(1), isFalse);
      expect(memory.getFlag(10), isFalse);
    });

    test('executes IF branching when condition is true vs false', () {
      // Script 1: equaln(%v0, 5) -> TRUE: sets %f1
      final scriptTrue = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x00, 0x05, // assignn(%v0, 5)
          0xFF,
          0x01, 0x00, 0x05, // equaln(%v0, 5)
          0xFF,
          0x02, 0x00, // jump 2 bytes
          0x0C, 0x01, // set(%f1)
          0x00, // return
        ]),
        messages: const [],
      );

      vm.loadRootScript(scriptTrue);
      vm.executeCycle();
      expect(memory.getFlag(1), isTrue);

      // Reset and run False branch
      memory.reset();
      final scriptFalse = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x00, 0x09, // assignn(%v0, 9)
          0xFF,
          0x01, 0x00, 0x05, // equaln(%v0, 5) -> FALSE
          0xFF,
          0x02, 0x00, // jump 2 bytes over THEN
          0x0C, 0x01, // set(%f1) (skipped)
          0x00, // return
        ]),
        messages: const [],
      );

      vm.loadRootScript(scriptFalse);
      vm.executeCycle();
      expect(memory.getFlag(1), isFalse);
    });

    test('executes nested script call and return', () {
      // SubLogic 2: assignn(%v0, 42), return
      final subLogic = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x00, 0x2A,
          0x00,
        ]),
        messages: const [],
        logicNumber: 2,
      );
      delegate.subLogics[2] = subLogic;

      // Root script: call(2), set(%f1), return
      final rootScript = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x16, 0x02, // call(2)
          0x0C, 0x01, // set(%f1)
          0x00, // return
        ]),
        messages: const [],
        logicNumber: 0,
      );

      vm.loadRootScript(rootScript);
      vm.executeCycle();

      expect(memory.getVar(0), 42);
      expect(memory.getFlag(1), isTrue);
    });

    test('executes said() check and print message actions', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x05, 0x00, 0x0A, 0x00, // said(%w5, %w10)
          0xFF,
          0x02, 0x00,
          0x65, 0x01, // print(%m1)
          0x00,
        ]),
        messages: ['You opened the treasure chest!'],
      );

      // When said() returns false
      delegate.nextSaidResult = false;
      vm.loadRootScript(script);
      vm.executeCycle();
      expect(delegate.printedMessages.isEmpty, isTrue);

      // When said() returns true
      delegate.nextSaidResult = true;
      vm.loadRootScript(script);
      vm.executeCycle();
      expect(delegate.printedMessages, contains('You opened the treasure chest!'));
      expect(delegate.lastSaidChecked, equals([5, 10]));
    });

    test('executes new.room and transitions room state', () {
      // assignn(%v0, 1), new.room(15)
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x03, 0x00, 0x01,
          0x12, 0x0F, // new.room(15)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(0), 15); // %v0 is new room
      expect(memory.getVar(1), 1); // %v1 is previous room
      expect(memory.getFlag(5), isTrue); // %f5 set
      expect(delegate.roomChanges, contains(15));
    });

    test('executes animated object manipulation opcodes', () {
      // position(0, 100, 120), set.view(0, 3), set.loop(0, 2), set.cel(0, 1), set.priority(0, 8)
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x25, 0x00, 0x64, 0x78, // position(%o0, 100, 120)
          0x29, 0x00, 0x03, // set.view(%o0, 3)
          0x2B, 0x00, 0x02, // set.loop(%o0, 2)
          0x2F, 0x00, 0x01, // set.cel(%o0, 1)
          0x36, 0x00, 0x08, // set.priority(%o0, 8)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      final ego = vm.getObj(0);
      expect(ego.x, 100);
      expect(ego.y, 120);
      expect(ego.view, 3);
      expect(ego.loop, 2);
      expect(ego.cel, 1);
      expect(ego.priority, 8);
      expect(ego.fixedPriority, isTrue);
    });

    test('executes deterministic random() generation', () {
      // random(10, 20, %v5), return
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x82, 0x0A, 0x14, 0x05, // random(10, 20, %v5)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      final val = memory.getVar(5);
      expect(val, greaterThanOrEqualTo(10));
      expect(val, lessThanOrEqualTo(20));
    });

    test('executes configure.screen opcode (111 / 0x6F)', () {
      // configure.screen(1, 23, 0), return
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x6F, 0x01, 0x17, 0x00, // configure.screen(1, 23, 0)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(delegate.configuredScreenParams, [1, 23, 0]);
    });

    test('executes print.at opcode (151 / 0x97) with row, col, width', () {
      // print.at(1, 4, 12, 28)
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x97, 0x01, 0x04, 0x0C, 0x1C,
          0x00,
        ]),
        messages: const ['Beware of the falling rocks!'],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();

      expect(status, InterpreterStatus.yielded);
      expect(delegate.lastPrintAtParams, [
        'Beware of the falling rocks!',
        4, // row
        12, // col
        28, // width
        true, // isModal
        0, // timeout
      ]);
    });

    test('executes print.at.v opcode (152 / 0x98) with row, col, width', () {
      // Set %v1 = 2 (message 2)
      memory.setVar(1, 2);
      // print.at.v(%v1, 8, 15, 30)
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x98, 0x01, 0x08, 0x0F, 0x1E,
          0x00,
        ]),
        messages: const ['Msg1', 'The wizard appears!'],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();

      expect(status, InterpreterStatus.yielded);
      expect(delegate.lastPrintAtParams, [
        'The wizard appears!',
        8, // row
        15, // col
        30, // width
        true, // isModal
        0, // timeout
      ]);
    });

    test('distance() is 255 unless both objects are drawn', () {
      final ego = vm.getObj(0);
      final droid = vm.getObj(16);
      ego.x = 40;
      ego.y = 80;
      ego.isDrawn = true;
      droid.x = 0;
      droid.y = 71;
      droid.isDrawn = false;

      vm.loadRootScript(AgiLogicScript(
        bytecodes: Uint8List.fromList([69, 0, 16, 5, 0]), // distance(o0, o16, %v5)
        messages: const [],
      ));
      vm.executeCycle();
      expect(memory.getVar(5), 255, reason: 'undrawn objects must not look nearby');

      droid.isDrawn = true;
      vm.loadRootScript(AgiLogicScript(
        bytecodes: Uint8List.fromList([69, 0, 16, 5, 0]),
        messages: const [],
      ));
      vm.executeCycle();
      expect(memory.getVar(5), isNot(255));
    });

    test('obj.in.box requires the whole baseline inside the box', () {
      final ego = vm.getObj(0);
      ego.x = 10;
      ego.y = 50;
      // Default cel width is 4, so right edge is 13. Box 10..12 contains left but not right.
      vm.loadRootScript(AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x10, 0x00, 10, 40, 12, 60, // obj.in.box(o0, 10, 40, 12, 60)
          0xFF,
          0x02, 0x00, // then-length
          0x0C, 0x01, // set(f1)
          0x00,
        ]),
        messages: const [],
      ));
      vm.executeCycle();
      expect(memory.getFlag(1), isFalse);

      vm.loadRootScript(AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0B, 0x00, 10, 40, 12, 60, // posn(o0) uses the left corner
          0xFF,
          0x02, 0x00,
          0x0C, 0x02, // set(f2)
          0x00,
        ]),
        messages: const [],
      ));
      vm.executeCycle();
      expect(memory.getFlag(2), isTrue);
    });
  });
}
