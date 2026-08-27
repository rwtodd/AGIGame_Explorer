import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/parser/agi_said_extractor.dart';

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
  });
}
