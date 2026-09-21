import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/parser/agi_said_extractor.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('AgiSaidExtractor', () {
    late AgiDictionary dictionary;
    late AgiSaidExtractor extractor;

    setUp(() {
      dictionary = AgiDictionary();
      dictionary.addWord('look', 10);
      dictionary.addWord('examine', 10);
      dictionary.addWord('see', 10);
      dictionary.addWord('take', 20);
      dictionary.addWord('get', 20);
      dictionary.addWord('open', 30);
      dictionary.addWord('door', 100);
      dictionary.addWord('tree', 101);
      dictionary.addWord('screen', 102);
      dictionary.addWord('terminal', 102);

      extractor = AgiSaidExtractor();
    });

    test('extracts multiple said statements from logic bytecode AST', () {
      // Script with:
      // if (said(look, screen)) { ... }
      // if (said(take, tree)) { ... }
      // if (said(open, door)) { ... }
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x66, 0x00, // said(10, 102) -> look screen
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0xFF,
          0x0E, 0x02, 0x14, 0x00, 0x65, 0x00, // said(20, 101) -> take tree
          0xFF, 0x02, 0x00, 0x65, 0x02,
          0xFF,
          0x0E, 0x02, 0x1E, 0x00, 0x64, 0x00, // said(30, 100) -> open door
          0xFF, 0x02, 0x00, 0x65, 0x03,
          0x00,
        ]),
        messages: const [],
      );

      final extracted = extractor.extractFromScript(
        script: script,
        dictionary: dictionary,
        scriptNumber: 2,
      );

      expect(extracted.length, equals(3));
      expect(extracted[0].canonicalPhrase, equals('look screen'));
      expect(extracted[0].wordGroupIds, equals([10, 102]));
      expect(extracted[0].scriptNumber, equals(2));
      expect(extracted[0].wordSynonyms[0], equals(['look', 'examine', 'see']));
      expect(extracted[0].wordSynonyms[1], equals(['screen', 'terminal']));
      expect(extractor.peekScript(2), same(extracted));

      expect(extracted[1].canonicalPhrase, equals('take tree'));
      expect(extracted[2].canonicalPhrase, equals('open door'));
    });

    test('extractActiveRoomCommands combines room logic and logic 0 deduplicated', () {
      final roomScript = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x66, 0x00, // said(10, 102) -> look screen
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0x00,
        ]),
        messages: const [],
      );

      final logic0Script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x66, 0x00, // duplicate look screen in logic 0
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0xFF,
          0x0E, 0x02, 0x1E, 0x00, 0x64, 0x00, // said(30, 100) -> open door
          0xFF, 0x02, 0x00, 0x65, 0x02,
          0x00,
        ]),
        messages: const [],
      );

      final combined = extractor.extractActiveRoomCommands(
        logic0: logic0Script,
        roomLogic: roomScript,
        dictionary: dictionary,
        roomNumber: 2,
      );

      expect(combined.length, equals(2));
      expect(combined[0].canonicalPhrase, equals('look screen'));
      expect(combined[0].scriptNumber, equals(2)); // from room logic
      expect(combined[1].canonicalPhrase, equals('open door'));
      expect(combined[1].scriptNumber, equals(0)); // from logic 0
    });

    test('caches extracted said commands per scriptNumber and clears cache on demand', () {
      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x66, 0x00, // said(10, 102) -> look screen
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0x00,
        ]),
        messages: const [],
      );

      expect(extractor.cachedScriptCount, equals(0));

      final firstExtraction = extractor.extractFromScript(
        script: script,
        dictionary: dictionary,
        scriptNumber: 5,
      );

      expect(extractor.cachedScriptCount, equals(1));

      // Second extraction should return identical cached list instance
      final secondExtraction = extractor.extractFromScript(
        script: script,
        dictionary: dictionary,
        scriptNumber: 5,
      );

      expect(identical(firstExtraction, secondExtraction), isTrue);
      expect(extractor.cachedScriptCount, equals(1));

      // Clear cache
      extractor.clearCache();
      expect(extractor.cachedScriptCount, equals(0));
    });

    test('picks natural canonical words over alphabetical order and formats rich prompt descriptions', () {
      final dict = AgiDictionary();
      // Overloaded verb group: acquire, capture, get, grab, take
      dict.addWord('acquire', 20);
      dict.addWord('capture', 20);
      dict.addWord('get', 20);
      dict.addWord('grab', 20);
      dict.addWord('take', 20);

      // Overloaded noun group: guy, magician, manannan, sorcerer, warlock, wizard
      dict.addWord('guy', 50);
      dict.addWord('magician', 50);
      dict.addWord('manannan', 50);
      dict.addWord('sorcerer', 50);
      dict.addWord('warlock', 50);
      dict.addWord('wizard', 50);

      final script = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x14, 0x00, 0x32, 0x00, // said(20, 50)
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0x00,
        ]),
        messages: const [],
      );

      final extracted = extractor.extractFromScript(
        script: script,
        dictionary: dict,
        scriptNumber: 10,
      );

      expect(extracted.length, equals(1));
      // Prefers 'take' and 'wizard' over 'acquire' and 'guy'
      expect(extracted[0].canonicalPhrase, equals('take wizard'));
      // Formats rich prompt description with distinct alternative synonyms
      expect(
        extracted[0].toPromptDescription(),
        equals('take wizard (synonyms: acquire, capture, get, grab, guy, magician)'),
      );
    });

    test('generateCandidatePhrases truncates permutations at maxCandidates', () {
      // 10 synonyms in slot 0, 10 synonyms in slot 1
      const cmd = ExtractedSaidCommand(
        scriptNumber: 1,
        wordGroupIds: [1, 2],
        canonicalPhrase: 'look screen',
        wordSynonyms: [
          ['w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7', 'w8', 'w9'],
          ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9'],
        ],
      );

      final candidates = cmd.generateCandidatePhrases(maxCandidates: 10);
      expect(candidates.length, equals(10));
      expect(candidates.first, equals('look screen'));
    });

    test('generateCandidatePhrases respects maxCandidates cap on deduplicated synonyms', () {
      // 2 synonyms in slot 0, 3 synonyms in slot 1 -> 6 permutations <= 25
      const cmd = ExtractedSaidCommand(
        scriptNumber: 1,
        wordGroupIds: [1, 2],
        canonicalPhrase: 'look screen',
        wordSynonyms: [
          ['look', 'see'],
          ['screen', 'monitor', 'terminal'],
        ],
      );

      final candidates = cmd.generateCandidatePhrases(maxCandidates: 3);
      expect(candidates.length, equals(3));
      expect(candidates.first, equals('look screen'));
    });

    test('generateCandidatePhrases keeps canonical first when it is not first in the product', () {
      const cmd = ExtractedSaidCommand(
        scriptNumber: 1,
        wordGroupIds: [1, 2],
        canonicalPhrase: 'gaze pane',
        wordSynonyms: [
          ['look', 'gaze'],
          ['window', 'pane'],
        ],
      );

      final candidates = cmd.generateCandidatePhrases(maxCandidates: 3);
      expect(candidates.first, equals('gaze pane'));
      expect(candidates, contains('gaze pane'));
      expect(candidates.length, equals(3));
    });

    test('extractSaidWordGroupIds extracts unique word group IDs from bytecode', () {
      final bytecode = Uint8List.fromList([
        0xFF,
        0x0E, 0x02, 0x14, 0x00, 0x32, 0x00, // said(20, 50)
        0xFF, 0x02, 0x00, 0x65, 0x01,
        0xFF,
        0x0E, 0x01, 0x64, 0x00, // said(100)
        0x00,
      ]);

      final ids = AgiSaidExtractor.extractSaidWordGroupIds(bytecode);
      expect(ids, equals({20, 50, 100}));
    });

    test('extractActiveRoomCommands on reference PQ1 generates bounded candidate count', () {
      final pqDir = Directory('/Users/rtodd/src/flutter_agigame/reference_games/police-quest-1');
      if (!pqDir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(pqDir.path);
      final logic0 = loader.loadLogic(0);
      final logic1 = loader.loadLogic(1);

      final extracted = extractor.extractActiveRoomCommands(
        logic0: logic0,
        roomLogic: logic1,
        dictionary: loader.dictionary,
        roomNumber: 1,
      );

      int totalCandidates = 0;
      for (final cmd in extracted) {
        totalCandidates += cmd.generateCandidatePhrases().length;
      }
      // Without any bounds this was 7,452! With maxCandidates truncation it is bounded (< 3,000).
      expect(totalCandidates, lessThan(3000));
    });

    test('extractActiveRoomCommands includes commands from additionalLogics overlay scripts', () {
      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('room', 3);
      dict.addWord('cat', 4);
      dict.addWord('global', 5);

      final logic0 = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF, 0x0E, 0x02, 0x02, 0x00, 0x05, 0x00, // said("look", "global")
          0xFF, 0x00, 0x00,
        ]),
        messages: const [],
        logicNumber: 0,
      );

      final roomLogic = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF, 0x0E, 0x02, 0x02, 0x00, 0x03, 0x00, // said("look", "room")
          0xFF, 0x00, 0x00,
        ]),
        messages: const [],
        logicNumber: 5,
      );

      final catLogic = AgiLogicScript(
        bytecodes: Uint8List.fromList([
          0xFF, 0x0E, 0x02, 0x02, 0x00, 0x04, 0x00, // said("look", "cat")
          0xFF, 0x00, 0x00,
        ]),
        messages: const [],
        logicNumber: 104,
      );

      final extracted = extractor.extractActiveRoomCommands(
        logic0: logic0,
        roomLogic: roomLogic,
        additionalLogics: [catLogic],
        dictionary: dict,
        roomNumber: 5,
      );

      final phrases = extracted.map((c) => c.canonicalPhrase).toList();
      expect(phrases, contains('look cat'));
      expect(phrases, contains('look room'));
      expect(phrases, contains('look global'));
    });
  });
}
