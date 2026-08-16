import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/parser/agi_said_matcher.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

void main() {
  group('AgiTextParser', () {
    late AgiDictionary dictionary;
    late AgiTextParser parser;

    setUp(() {
      dictionary = AgiDictionary();
      // Group 0: Ignored / noise words
      dictionary.addWord('a', 0);
      dictionary.addWord('an', 0);
      dictionary.addWord('the', 0);
      dictionary.addWord('at', 0);
      dictionary.addWord('to', 0);
      dictionary.addWord('in', 0);
      dictionary.addWord('on', 0);
      dictionary.addWord('with', 0);

      // Group IDs > 0: Action verbs, nouns, etc.
      dictionary.addWord('look', 10);
      dictionary.addWord('examine', 10); // synonym
      dictionary.addWord('see', 10);     // synonym
      dictionary.addWord('take', 20);
      dictionary.addWord('get', 20);      // synonym
      dictionary.addWord('open', 30);
      dictionary.addWord('door', 100);
      dictionary.addWord('tree', 101);
      dictionary.addWord('chest', 102);
      dictionary.addWord('box', 102);     // synonym
      dictionary.addWord('key', 103);
      dictionary.addWord('gold', 104);

      // Contraction words in dictionary
      dictionary.addWord('dont', 50);
      dictionary.addWord('cant', 51);
      dictionary.addWord('its', 52);
      dictionary.addWord('im', 53);

      // Multi-word phrases and noise word prefixes (e.g. KQ2)
      dictionary.addWord('little', 0); // Noise word when alone
      dictionary.addWord('little red riding hood', 18);
      dictionary.addWord('magic door', 105);

      parser = AgiTextParser(dictionary);
    });

    test('greedy longest-match chooses multi-word phrase over prefix words', () {
      // "little" is group 0 (ignored), but "little red riding hood" is group 18
      final result = parser.parse('look little red riding hood');
      expect(result.isSuccess, isTrue);
      expect(result.wordGroupIds, equals([10, 18]));
      expect(result.originalTokens, equals(['look', 'little red riding hood']));
      expect(result.filteredTokens, equals(['look', 'little red riding hood']));
    });

    test('multi-word phrase with noise word prefix matches longest phrase', () {
      final r1 = parser.parse('open the magic door');
      expect(r1.isSuccess, isTrue);
      expect(r1.wordGroupIds, equals([30, 105]));
      expect(r1.originalTokens, equals(['open', 'the', 'magic door']));
    });

    test('normalizes lowercase and removes whitespace', () {
      expect(parser.normalize('  LOOK   AT   TREE  '), equals('look at tree'));
      expect(parser.normalize('Look AT ThE DooR'), equals('look at the door'));
    });

    test('replaces standard punctuation with spaces', () {
      expect(parser.normalize('look, at the tree!'), equals('look at the tree'));
      expect(parser.normalize('open door; take key.'), equals('open door take key'));
      expect(parser.normalize('what? look (at) [the] {chest}...'), equals('what look at the chest'));
    });

    test('normalizes common English contractions', () {
      expect(parser.normalize("don't open door"), equals('dont open door'));
      expect(parser.normalize("can't take key"), equals('cant take key'));
      expect(parser.normalize("it's a chest"), equals('its a chest'));
      expect(parser.normalize("I'm looking"), equals('im looking'));
      // Curly apostrophe support
      expect(parser.normalize("don’t open"), equals('dont open'));
    });

    test('preserves raw input on AgiParseResult', () {
      const raw = '  Look, AT the chest!  ';
      final result = parser.parse(raw);
      expect(result.rawInput, equals(raw));
      expect(result.normalizedInput, equals('look at the chest'));
      expect(result.isSuccess, isTrue);
    });

    test('filters out Group 0 noise words', () {
      final result = parser.parse('look at the big tree');
      // 'at' (0) and 'the' (0) should be ignored, 'big' is unknown
      expect(result.isSuccess, isFalse);
      expect(result.unknownWord, equals('big'));

      final validResult = parser.parse('look at the tree');
      expect(validResult.isSuccess, isTrue);
      expect(validResult.originalTokens, equals(['look', 'at', 'the', 'tree']));
      expect(validResult.filteredTokens, equals(['look', 'tree']));
      expect(validResult.wordGroupIds, equals([10, 101]));
    });

    test('handles synonyms mapping to same word group ID', () {
      final r1 = parser.parse('look door');
      final r2 = parser.parse('examine door');
      final r3 = parser.parse('see door');

      expect(r1.wordGroupIds, equals([10, 100]));
      expect(r2.wordGroupIds, equals([10, 100]));
      expect(r3.wordGroupIds, equals([10, 100]));
    });

    test('detects unknown words and sets 1-based index', () {
      final result = parser.parse('take shiny key');
      expect(result.isSuccess, isFalse);
      expect(result.unknownWord, equals('shiny'));
      expect(result.unknownWordIndex, equals(2));
      expect(result.errorMessage, equals("I don't understand 'shiny'"));
      expect(result.wordGroupIds, isEmpty);
    });

    test('handles empty or whitespace-only input', () {
      final r1 = parser.parse('');
      expect(r1.isSuccess, isTrue);
      expect(r1.wordGroupIds, isEmpty);
      expect(r1.originalTokens, isEmpty);

      final r2 = parser.parse('     ');
      expect(r2.isSuccess, isTrue);
      expect(r2.wordGroupIds, isEmpty);
      expect(r2.originalTokens, isEmpty);
    });
  });

  group('AgiSaidMatcher - Pure Pattern Matching', () {
    test('matches exact word groups', () {
      expect(AgiSaidMatcher.matchWords([10, 100], [10, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([10], [10]), isTrue);
      expect(AgiSaidMatcher.matchWords([], []), isTrue);

      // Mismatched words
      expect(AgiSaidMatcher.matchWords([10, 100], [10, 101]), isFalse);
      expect(AgiSaidMatcher.matchWords([20, 100], [10, 100]), isFalse);

      // Mismatched word count
      expect(AgiSaidMatcher.matchWords([10], [10, 100]), isFalse);
      expect(AgiSaidMatcher.matchWords([10, 100], [10]), isFalse);
    });

    test('matches ANYWORD (1) single-word wildcard', () {
      // 1 matches any single word token
      expect(AgiSaidMatcher.matchWords([10, 1], [10, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([10, 1], [10, 101]), isTrue);
      expect(AgiSaidMatcher.matchWords([1, 100], [10, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([1, 1], [10, 100]), isTrue);

      // Does not match wrong count
      expect(AgiSaidMatcher.matchWords([10, 1], [10]), isFalse);
      expect(AgiSaidMatcher.matchWords([10, 1], [10, 100, 101]), isFalse);
    });

    test('matches ROL (9999) rest-of-line wildcard', () {
      // ROL at end matches 0, 1, or more remaining words
      expect(AgiSaidMatcher.matchWords([10, 9999], [10]), isTrue);
      expect(AgiSaidMatcher.matchWords([10, 9999], [10, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([10, 9999], [10, 100, 101, 102]), isTrue);

      // First word must match
      expect(AgiSaidMatcher.matchWords([10, 9999], [20, 100]), isFalse);

      // ROL alone matches any input
      expect(AgiSaidMatcher.matchWords([9999], []), isTrue);
      expect(AgiSaidMatcher.matchWords([9999], [10]), isTrue);
      expect(AgiSaidMatcher.matchWords([9999], [10, 20, 30]), isTrue);

      // ROL before another word (e.g. wildcard prefix)
      expect(AgiSaidMatcher.matchWords([9999, 100], [100]), isTrue);
      expect(AgiSaidMatcher.matchWords([9999, 100], [10, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([9999, 100], [10, 20, 100]), isTrue);
      expect(AgiSaidMatcher.matchWords([9999, 100], [10, 20, 99]), isFalse);
    });
  });

  group('AgiSaidMatcher - Stateful Cycle & Memory Sync', () {
    late AgiMemory memory;
    late AgiSaidMatcher matcher;
    late AgiDictionary dictionary;
    late AgiTextParser parser;

    setUp(() {
      memory = AgiMemory();
      matcher = AgiSaidMatcher(memory: memory);

      dictionary = AgiDictionary();
      dictionary.addWord('a', 0);
      dictionary.addWord('at', 0);
      dictionary.addWord('the', 0);
      dictionary.addWord('look', 10);
      dictionary.addWord('tree', 100);
      dictionary.addWord('door', 101);
      parser = AgiTextParser(dictionary);
    });

    test('setInput sets Flag 2 (have.input) and resets Flag 4 (said.accepted)', () {
      expect(matcher.hasInput, isFalse);
      expect(matcher.saidAccepted, isFalse);
      expect(memory.getFlag(2), isFalse);
      expect(memory.getFlag(4), isFalse);

      matcher.setInput([10, 100]);

      expect(matcher.hasInput, isTrue);
      expect(matcher.saidAccepted, isFalse);
      expect(memory.getFlag(2), isTrue);
      expect(memory.getFlag(4), isFalse);
    });

    test('checkSaid accepts matching input and sets Flag 4', () {
      matcher.setInput([10, 100]);

      // Non-matching check returns false and does not accept
      expect(matcher.checkSaid([10, 101]), isFalse);
      expect(matcher.saidAccepted, isFalse);
      expect(memory.getFlag(4), isFalse);

      // Matching check returns true and accepts
      expect(matcher.checkSaid([10, 100]), isTrue);
      expect(matcher.saidAccepted, isTrue);
      expect(memory.getFlag(4), isTrue);

      // Second matching check in same cycle returns false (already accepted)
      expect(matcher.checkSaid([10, 100]), isFalse);
    });

    test('setInputFromResult handles valid parse and unknown word with Var 9', () {
      final valid = parser.parse('look at the tree');
      matcher.setInputFromResult(valid);
      expect(matcher.hasInput, isTrue);
      expect(matcher.currentWordIds, equals([10, 100]));

      // Unknown word input
      final invalid = parser.parse('look goblin tree');
      matcher.setInputFromResult(invalid);
      expect(matcher.hasInput, isFalse);
      expect(matcher.currentWordIds, isEmpty);
      expect(memory.getVar(9), equals(2)); // 'goblin' was token #2
    });

    test('clearInput clears state at end of cycle', () {
      matcher.setInput([10, 100]);
      matcher.checkSaid([10, 100]);
      expect(matcher.saidAccepted, isTrue);

      matcher.clearInput();
      expect(matcher.hasInput, isFalse);
      expect(matcher.saidAccepted, isFalse);
      expect(matcher.currentWordIds, isEmpty);
      expect(memory.getFlag(2), isFalse);
      expect(memory.getFlag(4), isFalse);
    });
  });

  group('Interpreter Integration with AgiSaidMatcher', () {
    test('AgiLogicInterpreter executes 0x0E (said) opcode through matcher', () {
      final memory = AgiMemory();
      final matcher = AgiSaidMatcher(memory: memory);

      // Script:
      // if (said(look, tree)) { print("You see a tall tree."); }
      // if (said(open, door)) { print("The door is locked."); }
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x64, 0x00, // said(2, 10, 100) -> look tree
          0xFF,
          0x02, 0x00,
          0x65, 0x01, // print(1) -> "You see a tall tree."
          0xFF,
          0x0E, 0x02, 0x1E, 0x00, 0x65, 0x00, // said(2, 30, 101) -> open door
          0xFF,
          0x02, 0x00,
          0x65, 0x02, // print(2) -> "The door is locked."
          0x00,
        ]),
        messages: [
          'You see a tall tree.',
          'The door is locked.',
        ],
      );

      // Track printed messages via test delegate
      final printed = <String>[];
      final testDelegate = _RecordingSaidDelegate(matcher, printed);
      final testVm = AgiLogicInterpreter(memory: memory, delegate: testDelegate);

      // Cycle 1: Player enters "look tree" -> matches first if block
      matcher.setInput([10, 100]);
      testVm.loadRootScript(script);
      testVm.executeCycle();

      expect(printed, equals(['You see a tall tree.']));
      expect(memory.getFlag(4), isTrue); // said.accepted = 1

      // Cycle 2: End of cycle cleanup, then user enters "open door"
      printed.clear();
      matcher.clearInput();
      matcher.setInput([30, 101]);
      testVm.loadRootScript(script);
      testVm.executeCycle();

      expect(printed, equals(['The door is locked.']));
      expect(memory.getFlag(4), isTrue);
    });
  });
}

class _RecordingSaidDelegate extends DefaultAgiInterpreterDelegate {
  final AgiSaidMatcher matcher;
  final List<String> printedMessages;

  _RecordingSaidDelegate(this.matcher, this.printedMessages);

  @override
  bool checkSaid(List<int> wordGroupIds) => matcher.checkSaid(wordGroupIds);

  @override
  void onPrint(String message) {
    printedMessages.add(message);
  }
}
