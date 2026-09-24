import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';
import 'package:flutter_agigame/sci/parser/sci_said_matcher.dart';

void main() {
  group('SciSaidSpec & SciSaidMatcher', () {
    late SciVocab vocab;

    setUpAll(() async {
      vocab = SciVocab();
      final vocabFile = File('reference_games/police-quest-2/VOCAB.000');
      if (await vocabFile.exists()) {
        final bytes = await vocabFile.readAsBytes();
        vocab.loadVocab000(bytes);
      }
    });

    test('decodes Said spec bytecode and decompiles to string', () {
      // Bytecode for: look (group 1000) / car (group 1020)
      final specBytes = Uint8List.fromList([
        0x03, 0xE8, // 1000 (look)
        SciSaidOp.slash,
        0x03, 0xFC, // 1020 (car)
        SciSaidOp.term,
      ]);

      final spec = SciSaidSpec.fromBytes(specBytes);
      expect(spec.tokens.length, 4);
      expect(spec.tokens[0].wordGroup, 1000);
      expect(spec.tokens[1].operator, SciSaidOp.slash);
      expect(spec.tokens[2].wordGroup, 1020);
      expect(spec.tokens[3].operator, SciSaidOp.term);
      expect(spec.isNonClaiming, isFalse);

      final str = spec.toSaidString(null);
      expect(str, '1000/1020');
    });

    test('toSaidString decompiles with vocabulary words', () {
      // Find group for "look" and "door" in PQ2 vocab
      final lookWords = vocab.lookup('look');
      final doorWords = vocab.lookup('door');

      if (lookWords != null && doorWords != null) {
        final lookWord = lookWords.first;
        final doorWord = doorWords.first;
        final specBytes = Uint8List.fromList([
          (lookWord.group >> 8) & 0xFF,
          lookWord.group & 0xFF,
          SciSaidOp.slash,
          (doorWord.group >> 8) & 0xFF,
          doorWord.group & 0xFF,
          SciSaidOp.term,
        ]);
        final spec = SciSaidSpec.fromBytes(specBytes);
        final decompiled = spec.toSaidString(vocab);
        expect(decompiled, contains('look'));
        expect(decompiled, contains('door'));
      }
    });

    test('matches exact verb/noun clause', () {
      final lookGroup = 1000;
      final carGroup = 1020;

      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        (lookGroup >> 8) & 0xFF,
        lookGroup & 0xFF,
        SciSaidOp.slash,
        (carGroup >> 8) & 0xFF,
        carGroup & 0xFF,
        SciSaidOp.term,
      ]));

      final inputWords = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'car', wordClass: SciVocab.classNoun, group: 1020),
      ];

      expect(SciSaidMatcher.match(spec, inputWords), isTrue);

      final wrongInput = <SciVocabWord>[
        const SciVocabWord(text: 'open', wordClass: SciVocab.classImperativeVerb, group: 1001),
        const SciVocabWord(text: 'car', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, wrongInput), isFalse);
    });

    test('matches ANYWORD wildcard (0x0FFF)', () {
      final lookGroup = 1000;

      // look / *
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        (lookGroup >> 8) & 0xFF,
        lookGroup & 0xFF,
        SciSaidOp.slash,
        0x0F, 0xFF, // ANYWORD
        SciSaidOp.term,
      ]));

      final inputWords = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'anything', wordClass: SciVocab.classNoun, group: 9999),
      ];

      expect(SciSaidMatcher.match(spec, inputWords), isTrue);
    });

    test('matches optional clause [open] / door', () {
      final openGroup = 1001;
      final doorGroup = 1002;

      // [open] / door
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        SciSaidOp.bracketOpen,
        (openGroup >> 8) & 0xFF,
        openGroup & 0xFF,
        SciSaidOp.bracketClose,
        SciSaidOp.slash,
        (doorGroup >> 8) & 0xFF,
        doorGroup & 0xFF,
        SciSaidOp.term,
      ]));

      // Input: "open door"
      final inputWithVerb = <SciVocabWord>[
        const SciVocabWord(text: 'open', wordClass: SciVocab.classImperativeVerb, group: 1001),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1002),
      ];
      expect(SciSaidMatcher.match(spec, inputWithVerb), isTrue);
    });

    test('look> is a partial match and does not require extra clauses', () {
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        0x03, 0xE8, // look
        SciSaidOp.gt,
        SciSaidOp.term,
      ]));
      expect(spec.isNonClaiming, isTrue);

      final lookDoor = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, lookDoor), isTrue);
    });

    test('optional [open]/door matches door and open door, not close door', () {
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        SciSaidOp.bracketOpen,
        0x03, 0xE9, // 1001 open
        SciSaidOp.bracketClose,
        SciSaidOp.slash,
        0x03, 0xFC, // 1020 door
        SciSaidOp.term,
      ]));

      final doorOnly = <SciVocabWord>[
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, doorOnly), isTrue);

      final openDoor = <SciVocabWord>[
        const SciVocabWord(text: 'open', wordClass: SciVocab.classImperativeVerb, group: 1001),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, openDoor), isTrue);

      final closeDoor = <SciVocabWord>[
        const SciVocabWord(text: 'close', wordClass: SciVocab.classImperativeVerb, group: 1003),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, closeDoor), isFalse);
    });

    test('amp is AND: both conjuncts must be present', () {
      // look / red & door
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        0x03, 0xE8, // 1000 look
        SciSaidOp.slash,
        0x03, 0xF2, // 1010 red
        SciSaidOp.amp,
        0x03, 0xFC, // 1020 door
        SciSaidOp.term,
      ]));
      expect(spec.toSaidString(null), '1000/1010&1020');

      final both = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'red', wordClass: SciVocab.classAdjective, group: 1010),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: 1020),
      ];
      expect(SciSaidMatcher.match(spec, both), isTrue);

      final missingDoor = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'red', wordClass: SciVocab.classAdjective, group: 1010),
      ];
      expect(SciSaidMatcher.match(spec, missingDoor), isFalse);
    });

    test('supports AI semantic matcher hook', () {
      final lookGroup = 1000;
      final carGroup = 1020;

      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        (lookGroup >> 8) & 0xFF,
        lookGroup & 0xFF,
        SciSaidOp.slash,
        (carGroup >> 8) & 0xFF,
        carGroup & 0xFF,
        SciSaidOp.term,
      ]));

      // Player typed a natural sentence that parser didn't map to 'look car'
      final inputWords = <SciVocabWord>[
        const SciVocabWord(text: 'inspect', wordClass: SciVocab.classImperativeVerb, group: 999),
        const SciVocabWord(text: 'vehicle', wordClass: SciVocab.classNoun, group: 888),
      ];

      // Without AI hook, standard match fails
      expect(SciSaidMatcher.match(spec, inputWords), isFalse);

      // Attach an AI hook that understands "inspect vehicle" == "look/car"
      SciSaidMatcher.aiHook = (candidateSpec, rawInput, words) {
        if (rawInput.contains('vehicle') && candidateSpec.toSaidString(null) == '1000/1020') {
          return true;
        }
        return false;
      };

      try {
        expect(
          SciSaidMatcher.match(
            spec,
            inputWords,
            rawInput: 'please inspect the vehicle',
          ),
          isTrue,
        );
      } finally {
        SciSaidMatcher.aiHook = null;
      }
    });

    test('supports aiHookOverride scoped to engine instance', () {
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        0x03, 0xE8, // 1000 look
        SciSaidOp.slash,
        0x03, 0xFC, // 1020 car
        SciSaidOp.term,
      ]));

      final inputWords = <SciVocabWord>[
        const SciVocabWord(text: 'inspect', wordClass: SciVocab.classImperativeVerb, group: 999),
      ];

      final matched = SciSaidMatcher.match(
        spec,
        inputWords,
        rawInput: 'inspect automobile',
        aiHookOverride: (candidate, raw, words) => raw.contains('automobile'),
      );
      expect(matched, isTrue);
    });

    test('matches optional direct object with omitted verb: [/room, floor, house, garage]', () {
      const roomGroup = 2001;
      const floorGroup = 2002;
      const houseGroup = 2003;
      const garageGroup = 2004;

      // Bytecode for: [/room, floor, house, garage]
      final specBytes = Uint8List.fromList([
        SciSaidOp.bracketOpen,
        SciSaidOp.slash,
        (roomGroup >> 8) & 0xFF, roomGroup & 0xFF,
        SciSaidOp.comma,
        (floorGroup >> 8) & 0xFF, floorGroup & 0xFF,
        SciSaidOp.comma,
        (houseGroup >> 8) & 0xFF, houseGroup & 0xFF,
        SciSaidOp.comma,
        (garageGroup >> 8) & 0xFF, garageGroup & 0xFF,
        SciSaidOp.bracketClose,
        SciSaidOp.term,
      ]);

      final spec = SciSaidSpec.fromBytes(specBytes);
      expect(spec.clauses.length, 3);
      expect(spec.clauses[0].isPresent, isFalse, reason: 'Verb is omitted');
      expect(spec.clauses[1].isPresent, isTrue);
      expect(spec.clauses[1].isOptional, isTrue, reason: 'Direct object is optional');
      expect(spec.clauses[2].isPresent, isFalse);

      // 1. Plain "look" with no direct object MUST match
      final lookOnly = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
      ];
      expect(
        SciSaidMatcher.match(spec, lookOnly),
        isTrue,
        reason: 'Typing "look" alone must match optional [/room, floor, house, garage]',
      );

      // 2. "look garage" MUST match
      final lookGarage = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'garage', wordClass: SciVocab.classNoun, group: garageGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookGarage), isTrue);

      // 3. "look sky" (non-matching direct object) MUST NOT match
      final lookSky = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'sky', wordClass: SciVocab.classNoun, group: 9990),
      ];
      expect(SciSaidMatcher.match(spec, lookSky), isFalse);
    });

    test('three-slot specs decompose uniformly, including optional slot 2', () {
      const verbGroup = 1000;
      const doorGroup = 1020;
      const keyGroup = 1030;

      // verb/door/key: all three slots present and required.
      final full = SciSaidSpec.fromBytes(Uint8List.fromList([
        (verbGroup >> 8) & 0xFF, verbGroup & 0xFF,
        SciSaidOp.slash,
        (doorGroup >> 8) & 0xFF, doorGroup & 0xFF,
        SciSaidOp.slash,
        (keyGroup >> 8) & 0xFF, keyGroup & 0xFF,
        SciSaidOp.term,
      ]));
      expect(full.clauses.length, 3);
      expect(full.clauses[0].isPresent, isTrue);
      expect(full.clauses[0].isOptional, isFalse);
      expect(full.clauses[1].isPresent, isTrue);
      expect(full.clauses[1].isOptional, isFalse);
      expect(full.clauses[2].isPresent, isTrue);
      expect(full.clauses[2].isOptional, isFalse);

      // verb/door[/key]: slot 2 present but optional via the shared parser.
      final optIndirect = SciSaidSpec.fromBytes(Uint8List.fromList([
        (verbGroup >> 8) & 0xFF, verbGroup & 0xFF,
        SciSaidOp.slash,
        (doorGroup >> 8) & 0xFF, doorGroup & 0xFF,
        SciSaidOp.bracketOpen,
        SciSaidOp.slash,
        (keyGroup >> 8) & 0xFF, keyGroup & 0xFF,
        SciSaidOp.bracketClose,
        SciSaidOp.term,
      ]));
      expect(optIndirect.clauses.length, 3);
      expect(optIndirect.clauses[0].isPresent, isTrue);
      expect(optIndirect.clauses[1].isPresent, isTrue);
      expect(optIndirect.clauses[1].isOptional, isFalse);
      expect(optIndirect.clauses[2].isPresent, isTrue);
      expect(optIndirect.clauses[2].isOptional, isTrue);
    });

    test('omitted verb with required noun: /pole, sign', () {
      const poleGroup = 3001;
      const signGroup = 3002;

      // /pole, sign
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        SciSaidOp.slash,
        (poleGroup >> 8) & 0xFF, poleGroup & 0xFF,
        SciSaidOp.comma,
        (signGroup >> 8) & 0xFF, signGroup & 0xFF,
        SciSaidOp.term,
      ]));

      expect(spec.clauses[0].isPresent, isFalse);
      expect(spec.clauses[1].isPresent, isTrue);
      expect(spec.clauses[1].isOptional, isFalse);

      // 1. Plain "look" must NOT match required /pole, sign
      final lookOnly = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
      ];
      expect(SciSaidMatcher.match(spec, lookOnly), isFalse);

      // 2. "look pole" MUST match
      final lookPole = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'pole', wordClass: SciVocab.classNoun, group: poleGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookPole), isTrue);

      // 3. "look sky" must NOT match
      final lookSky = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: 1000),
        const SciVocabWord(text: 'sky', wordClass: SciVocab.classNoun, group: 9990),
      ];
      expect(SciSaidMatcher.match(spec, lookSky), isFalse);
    });

    test('verb with optional noun: look[/door]', () {
      const lookGroup = 1000;
      const doorGroup = 1020;

      // look[/door] -> look [ / door ]
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        (lookGroup >> 8) & 0xFF, lookGroup & 0xFF,
        SciSaidOp.bracketOpen,
        SciSaidOp.slash,
        (doorGroup >> 8) & 0xFF, doorGroup & 0xFF,
        SciSaidOp.bracketClose,
        SciSaidOp.term,
      ]));

      expect(spec.clauses[0].isPresent, isTrue);
      expect(spec.clauses[0].isOptional, isFalse);
      expect(spec.clauses[1].isPresent, isTrue);
      expect(spec.clauses[1].isOptional, isTrue);

      // 1. "look" matches
      final lookOnly = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: lookGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookOnly), isTrue);

      // 2. "look door" matches
      final lookDoor = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: lookGroup),
        const SciVocabWord(text: 'door', wordClass: SciVocab.classNoun, group: doorGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookDoor), isTrue);

      // 3. "look window" does NOT match
      final lookWindow = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: lookGroup),
        const SciVocabWord(text: 'window', wordClass: SciVocab.classNoun, group: 9991),
      ];
      expect(SciSaidMatcher.match(spec, lookWindow), isFalse);
    });

    test('phrasal verb with qualifier: (look<in), search / pants', () {
      const lookGroup = 1000;
      const inGroup = 5001;
      const searchGroup = 1005;
      const pantsGroup = 6001;

      // (look < in), search / pants
      final spec = SciSaidSpec.fromBytes(Uint8List.fromList([
        SciSaidOp.parenOpen,
        (lookGroup >> 8) & 0xFF, lookGroup & 0xFF,
        SciSaidOp.lt,
        (inGroup >> 8) & 0xFF, inGroup & 0xFF,
        SciSaidOp.parenClose,
        SciSaidOp.comma,
        (searchGroup >> 8) & 0xFF, searchGroup & 0xFF,
        SciSaidOp.slash,
        (pantsGroup >> 8) & 0xFF, pantsGroup & 0xFF,
        SciSaidOp.term,
      ]));

      // 1. "look in pants" matches
      final lookInPants = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: lookGroup),
        const SciVocabWord(text: 'in', wordClass: SciVocab.classPreposition, group: inGroup),
        const SciVocabWord(text: 'pants', wordClass: SciVocab.classNoun, group: pantsGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookInPants), isTrue);

      // 2. "search pants" matches
      final searchPants = <SciVocabWord>[
        const SciVocabWord(text: 'search', wordClass: SciVocab.classImperativeVerb, group: searchGroup),
        const SciVocabWord(text: 'pants', wordClass: SciVocab.classNoun, group: pantsGroup),
      ];
      expect(SciSaidMatcher.match(spec, searchPants), isTrue);

      // 3. Plain "look pants" (without qualifier) should fail the qualifier branch
      final lookPants = <SciVocabWord>[
        const SciVocabWord(text: 'look', wordClass: SciVocab.classImperativeVerb, group: lookGroup),
        const SciVocabWord(text: 'pants', wordClass: SciVocab.classNoun, group: pantsGroup),
      ];
      expect(SciSaidMatcher.match(spec, lookPants), isFalse);
    });
  });
}
