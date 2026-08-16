import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/parser/agi_said_matcher.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

class TestViewQueryDelegate extends DefaultAgiInterpreterDelegate {
  final Map<int, AgiView> views = {};
  final AgiDictionary testDictionary = AgiDictionary();
  late final AgiSaidMatcher matcher;

  String? lastGetStringPrompt;
  int? lastGetStringRow;
  int? lastGetStringCol;
  int? lastGetStringMaxLen;
  Completer<String?>? getStringCompleter;

  String? lastGetNumPrompt;
  Completer<int?>? getNumCompleter;

  TestViewQueryDelegate({AgiMemory? memory}) {
    matcher = AgiSaidMatcher(memory: memory);
  }

  @override
  AgiView? getView(int viewNumber) => views[viewNumber];

  @override
  AgiDictionary? get dictionary => testDictionary;

  @override
  bool checkSaid(List<int> wordGroupIds) => matcher.checkSaid(wordGroupIds);

  @override
  void onParse(String input) {
    final parser = AgiTextParser(testDictionary);
    final result = parser.parse(input);
    matcher.setInputFromResult(result);
  }

  @override
  Future<String?> onGetString(String prompt, int row, int col, int maxLen) {
    lastGetStringPrompt = prompt;
    lastGetStringRow = row;
    lastGetStringCol = col;
    lastGetStringMaxLen = maxLen;
    getStringCompleter = Completer<String?>();
    return getStringCompleter!.future;
  }

  @override
  Future<int?> onGetNum(String prompt) {
    lastGetNumPrompt = prompt;
    getNumCompleter = Completer<int?>();
    return getNumCompleter!.future;
  }
}

void main() {
  group('View-Querying Opcodes (last.cel & number.of.loops)', () {
    late AgiMemory memory;
    late List<AnimatedObject> animatedObjects;
    late TestViewQueryDelegate delegate;
    late AgiLogicInterpreter vm;

    setUp(() {
      memory = AgiMemory();
      animatedObjects = List.generate(16, (i) => AnimatedObject(number: i));
      delegate = TestViewQueryDelegate(memory: memory);
      vm = AgiLogicInterpreter(
        memory: memory,
        animatedObjects: animatedObjects,
        delegate: delegate,
      );

      // Create dummy views for testing
      // View 1: 4 loops, loop 0 has 4 cels, loop 1 has 2 cels, loop 2 has 1 cel, loop 3 has 3 cels
      final view1 = AgiView(
        viewNumber: 1,
        loops: [
          AgiViewLoop(
            loopNumber: 0,
            cels: List.generate(
              4,
              (i) => AgiViewCel.forward(
                width: 10,
                height: 10,
                transparentColor: 0,
                rawPixels: Uint8List(100),
              ),
            ),
          ),
          AgiViewLoop(
            loopNumber: 1,
            cels: List.generate(
              2,
              (i) => AgiViewCel.forward(
                width: 10,
                height: 10,
                transparentColor: 0,
                rawPixels: Uint8List(100),
              ),
            ),
          ),
          AgiViewLoop(
            loopNumber: 2,
            cels: [
              AgiViewCel.forward(
                width: 10,
                height: 10,
                transparentColor: 0,
                rawPixels: Uint8List(100),
              ),
            ],
          ),
          AgiViewLoop(
            loopNumber: 3,
            cels: List.generate(
              3,
              (i) => AgiViewCel.forward(
                width: 10,
                height: 10,
                transparentColor: 0,
                rawPixels: Uint8List(100),
              ),
            ),
          ),
        ],
      );

      // View 2: 2 loops
      final view2 = AgiView(
        viewNumber: 2,
        loops: [
          AgiViewLoop(
            loopNumber: 0,
            cels: [
              AgiViewCel.forward(
                width: 8,
                height: 8,
                transparentColor: 0,
                rawPixels: Uint8List(64),
              ),
            ],
          ),
          AgiViewLoop(
            loopNumber: 1,
            cels: [
              AgiViewCel.forward(
                width: 8,
                height: 8,
                transparentColor: 0,
                rawPixels: Uint8List(64),
              ),
            ],
          ),
        ],
      );

      delegate.views[1] = view1;
      delegate.views[2] = view2;
    });

    test('last.cel(o, %v) queries cel count from active view loop and sets v = count - 1', () {
      final ego = animatedObjects[0];
      ego.view = 1;
      ego.loop = 0; // 4 cels in loop 0
      ego.cel = 1;

      // last.cel(o0, %v10) -> opcode 49, obj 0, var 10
      // return -> opcode 0
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x31, 0x00, 0x0A,
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();

      expect(status, equals(InterpreterStatus.completed));
      expect(memory.getVar(10), equals(3)); // 4 cels -> last cel is 3
    });

    test('last.cel(o, %v) queries different loops on the same view', () {
      final ego = animatedObjects[0];
      ego.view = 1;
      ego.loop = 1; // 2 cels in loop 1

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x31, 0x00, 0x05, // last.cel(o0, %v5)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(5), equals(1)); // 2 cels -> last cel is 1
    });

    test('last.cel(o, %v) safely defaults to o.cel when view is not loaded', () {
      final obj = animatedObjects[2];
      obj.view = 99; // View 99 is not loaded in delegate
      obj.loop = 0;
      obj.cel = 5;

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x31, 0x02, 0x14, // last.cel(o2, %v20)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(20), equals(5)); // Defaults to current cel (5)
    });

    test('last.cel(o, %v) safely defaults to o.cel when loop index is out of bounds', () {
      final obj = animatedObjects[1];
      obj.view = 1;
      obj.loop = 10; // Loop 10 is out of bounds (View 1 has 4 loops)
      obj.cel = 2;

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x31, 0x01, 0x07, // last.cel(o1, %v7)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(7), equals(2)); // Defaults to current cel (2)
    });

    test('number.of.loops(o, %v) queries loopCount from active view', () {
      final ego = animatedObjects[0];
      ego.view = 1; // View 1 has 4 loops

      final npc = animatedObjects[3];
      npc.view = 2; // View 2 has 2 loops

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x35, 0x00, 0x01, // number.of.loops(o0, %v1) -> 4
          0x35, 0x03, 0x02, // number.of.loops(o3, %v2) -> 2
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(1), equals(4));
      expect(memory.getVar(2), equals(2));
    });

    test('number.of.loops(o, %v) safely defaults to 1 if view is not available', () {
      final obj = animatedObjects[5];
      obj.view = 99; // Missing view

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x35, 0x05, 0x08, // number.of.loops(o5, %v8) -> default 1
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getVar(8), equals(1));
    });
  });

  group('String Parsing & Vocabulary Opcodes (word.to.string & parse)', () {
    late AgiMemory memory;
    late TestViewQueryDelegate delegate;
    late AgiLogicInterpreter vm;

    setUp(() {
      memory = AgiMemory();
      delegate = TestViewQueryDelegate(memory: memory);
      vm = AgiLogicInterpreter(
        memory: memory,
        delegate: delegate,
      );

      // Populate test dictionary
      delegate.testDictionary.addWord('a', 0);
      delegate.testDictionary.addWord('at', 0);
      delegate.testDictionary.addWord('the', 0);
      delegate.testDictionary.addWord('look', 10);
      delegate.testDictionary.addWord('examine', 10);
      delegate.testDictionary.addWord('tree', 101);
      delegate.testDictionary.addWord('door', 102);
      delegate.testDictionary.addWord('open', 30);
      delegate.testDictionary.addWord('brass key', 150);
    });

    test('word.to.string(w, s) assigns primary dictionary word to string register', () {
      // word.to.string(w: 10, s: 1) -> 0x74, 10, 1
      // word.to.string(w: 101, s: 2) -> 0x74, 101, 2
      // return -> 0x00
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x74, 0x0A, 0x01, // word.to.string(10, s1) -> "look"
          0x74, 0x65, 0x02, // word.to.string(101, s2) -> "tree"
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getString(1), equals('look'));
      expect(memory.getString(2), equals('tree'));
    });

    test('word.to.string(w, s) sets empty string for unrecognized word group ID', () {
      memory.setString(3, 'old content');

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x74, 0xFE, 0x03, // word.to.string(254, s3) -> unknown ID
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getString(3), equals(''));
    });

    test('parse(s) tokenizes string and enables subsequent said(...) matching in script', () {
      memory.setString(0, 'look at the tree');

      // Bytecode:
      // parse(s0) -> 0x75, 0x00
      // if (said(2, 10, 101)) { assignn(%v5, 99) }
      // 0xFF, (test op 0x0E, count 2, w1=10, w2=101, test end 0xFF), then-length 3, assignn(%v5, 99), return
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x75, 0x00, // parse(s0)
          0xFF, // IF
          0x0E, 0x02, 0x0A, 0x00, 0x65, 0x00, 0xFF, // said(look, tree)
          0x03, 0x00, // Branch target offset (+3 bytes)
          0x03, 0x05, 0x63, // assignn(%v5, 99)
          0x00, // return
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getFlag(2), isTrue); // have.input = 1
      expect(memory.getFlag(4), isTrue); // said.accepted = 1
      expect(memory.getVar(5), equals(99)); // action executed
      expect(memory.getVar(9), equals(0)); // no unknown word
    });

    test('parse(s) sets variable 9 when an unknown word is encountered', () {
      memory.setString(1, 'open the mysterious door');

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x75, 0x01, // parse(s1)
          0x00,
        ]),
        messages: const [],
      );

      vm.loadRootScript(script);
      vm.executeCycle();

      expect(memory.getFlag(2), isFalse); // have.input = 0 on failed parse
      expect(memory.getVar(9), equals(3)); // "mysterious" is token index 3
    });
  });

  group('Interactive Prompts Opcodes (get.string & get.num)', () {
    late AgiMemory memory;
    late TestViewQueryDelegate delegate;
    late AgiLogicInterpreter vm;

    setUp(() {
      memory = AgiMemory();
      delegate = TestViewQueryDelegate(memory: memory);
      vm = AgiLogicInterpreter(
        memory: memory,
        delegate: delegate,
      );
    });

    test('get.string prompts delegate and stores submitted text in string register', () {
      // get.string(s: 2, m: 1, row: 10, col: 5, maxLen: 12) -> 0x73, 2, 1, 10, 5, 12
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x73, 0x02, 0x01, 0x0A, 0x05, 0x0C,
          0x00,
        ]),
        messages: [
          'What is your name?',
        ],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();
      expect(status, equals(InterpreterStatus.yielded));
      expect(vm.hasPendingInput, isTrue);

      expect(delegate.lastGetStringPrompt, equals('What is your name?'));
      expect(delegate.lastGetStringRow, equals(10));
      expect(delegate.lastGetStringCol, equals(5));
      expect(delegate.lastGetStringMaxLen, equals(12));

      // Resume interpreter with input
      final resumeStatus = vm.resumeWithInput('Sir Graham');
      expect(resumeStatus, equals(InterpreterStatus.completed));
      expect(memory.getString(2), equals('Sir Graham'));
    });

    test('get.string clamps entered text to maxLen', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x73, 0x00, 0x01, 0x00, 0x00, 0x04, // maxLen = 4
          0x00,
        ]),
        messages: [
          'Enter PIN:',
        ],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();
      expect(status, equals(InterpreterStatus.yielded));

      vm.resumeWithInput('123456789');
      expect(memory.getString(0), equals('1234'));
    });

    test('get.num prompts delegate and stores numeric value in variable', () {
      // get.num(m: 1, %v15) -> 0x76, 1, 15
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x76, 0x01, 0x0F,
          0x00,
        ]),
        messages: [
          'How much do you want to gamble?',
        ],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();
      expect(status, equals(InterpreterStatus.yielded));

      expect(delegate.lastGetNumPrompt, equals('How much do you want to gamble?'));

      vm.resumeWithInput('75');
      expect(memory.getVar(15), equals(75));
    });

    test('get.num clamps numeric input to 0 - 255', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x76, 0x01, 0x02,
          0x00,
        ]),
        messages: [
          'Enter number:',
        ],
      );

      vm.loadRootScript(script);
      final status = vm.executeCycle();
      expect(status, equals(InterpreterStatus.yielded));

      vm.resumeWithInput('999');
      expect(memory.getVar(2), equals(255));
    });
  });
}
