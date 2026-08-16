import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';

void main() {
  group('AgiTextScreenBuffer', () {
    test('initializes with 40x25 blank cells', () {
      final buffer = AgiTextScreenBuffer();
      expect(AgiTextScreenBuffer.columns, equals(40));
      expect(AgiTextScreenBuffer.rows, equals(25));
      expect(buffer.hasContent, isFalse);

      final cell = buffer.getCell(0, 0);
      expect(cell.char, equals(' '));
      expect(cell.fg, equals(15));
      expect(cell.bg, equals(0));
    });

    test('writes string at row and column', () {
      final buffer = AgiTextScreenBuffer();
      buffer.writeString(5, 9, 'Welcome Aboard Arcada', fg: 14, bg: 1);

      expect(buffer.hasContent, isTrue);
      expect(buffer.getCell(5, 9).char, equals('W'));
      expect(buffer.getCell(5, 9).fg, equals(14));
      expect(buffer.getCell(5, 9).bg, equals(1));
      expect(buffer.getCell(5, 10).char, equals('e'));

      final cellBefore = buffer.getCell(5, 8);
      expect(cellBefore.char, equals(' '));
    });

    test('clears line ranges with clearLines', () {
      final buffer = AgiTextScreenBuffer();
      buffer.writeString(5, 0, 'Line 5 text');
      buffer.writeString(6, 0, 'Line 6 text');
      buffer.writeString(7, 0, 'Line 7 text');

      buffer.clearLines(5, 6, 0);
      expect(buffer.getCell(5, 0).char, equals(' '));
      expect(buffer.getCell(6, 0).char, equals(' '));
      expect(buffer.getCell(7, 0).char, equals('L'));
    });

    test('clears rectangular regions with clearTextRect', () {
      final buffer = AgiTextScreenBuffer();
      buffer.writeString(10, 5, '0123456789');
      buffer.writeString(11, 5, '0123456789');

      buffer.clearTextRect(10, 7, 11, 10, 4);
      expect(buffer.getCell(10, 6).char, equals('1'));
      expect(buffer.getCell(10, 7).char, equals(' '));
      expect(buffer.getCell(10, 7).bg, equals(4));
      expect(buffer.getCell(10, 10).char, equals(' '));
      expect(buffer.getCell(10, 11).char, equals('6'));
    });
  });

  group('AgiGameEngine Text Screen Mode & Synchronous Input Prompts', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('text.screen opcode enables text screen mode and graphics switches back', () {
      expect(engine.isTextScreen, isFalse);

      // text.screen (0x6A) -> opcode 106
      final textScript = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x6A,
          0x00,
        ]),
        messages: const [],
      );

      engine.interpreter.loadRootScript(textScript);
      engine.interpreter.executeCycle();

      expect(engine.isTextScreen, isTrue);

      // graphics (0x6B) -> opcode 107
      final graphicsScript = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x6B,
          0x00,
        ]),
        messages: const [],
      );

      engine.interpreter.loadRootScript(graphicsScript);
      engine.interpreter.executeCycle();

      expect(engine.isTextScreen, isFalse);
    });

    test('display and set.text.attribute populate textScreenBuffer', () {
      // set.text.attribute(fg: 14, bg: 4) -> 0x6D, 14, 4
      // display(row: 5, col: 9, m: 1) -> 0x67, 5, 9, 1
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x6D, 0x0E, 0x04,
          0x67, 0x05, 0x09, 0x01,
          0x00,
        ]),
        messages: [
          'Welcome Aboard Arcada',
        ],
      );

      engine.interpreter.loadRootScript(script);
      engine.interpreter.executeCycle();

      expect(engine.textScreenBuffer.getCell(5, 9).char, equals('W'));
      expect(engine.textScreenBuffer.getCell(5, 9).fg, equals(14));
      expect(engine.textScreenBuffer.getCell(5, 9).bg, equals(4));
    });

    test('SQ1 Logic 69 Name Prompt sequence pauses and resumes correctly', () {
      // Simulates SQ1 Logic 69 intro prompt:
      // text.screen() -> 0x6A
      // display(row 5, col 9, msg 1: "Welcome Aboard Arcada") -> 0x67, 5, 9, 1
      // get.string(s1, msg 2: "First Name: ", row 16, col 5, maxLen 18) -> 0x73, 1, 2, 16, 5, 18
      // set.string(s2, msg 3: "Roger") -> 0x72, 2, 3
      // return -> 0x00
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0x6A,
          0x67, 0x05, 0x09, 0x01,
          0x73, 0x01, 0x02, 0x10, 0x05, 0x12,
          0x72, 0x02, 0x03,
          0x00,
        ]),
        messages: [
          'Welcome Aboard Arcada',
          'First Name: ',
          'Roger',
        ],
      );

      engine.interpreter.loadRootScript(script);
      final cycleStatus = engine.interpreter.executeCycle();

      // Interpreter yielded at get.string
      expect(cycleStatus, equals(InterpreterStatus.yielded));
      expect(engine.isTextScreen, isTrue);
      expect(engine.activeInputPrompt, isNotNull);
      expect(engine.activeInputPrompt!.prompt, equals('First Name: '));
      expect(engine.activeInputPrompt!.row, equals(16));
      expect(engine.activeInputPrompt!.col, equals(5));
      expect(engine.activeInputPrompt!.maxLen, equals(18));

      // Notice that opcodes following get.string (like set.string s2) did NOT execute yet!
      expect(engine.memory.getString(2), isEmpty);

      // Player submits their name
      engine.submitInputPrompt('Wilco');

      // Prompt is closed and interpreter completed remaining instructions
      expect(engine.activeInputPrompt, isNull);
      expect(engine.memory.getString(1), equals('Wilco'));
      expect(engine.memory.getString(2), equals('Roger'));
    });
  });
}
