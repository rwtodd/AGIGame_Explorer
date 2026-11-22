import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/loader/parsers/words_parser.dart';

Uint8List _wordsTokStr(String word) {
  final answer = Uint8List.fromList(ascii.encode(word));
  for (var i = 0; i < answer.length; i++) {
    answer[i] = (answer[i] & 0x7F) ^ 0x7F;
  }
  // Set the high bit on the last character
  answer[answer.length - 1] |= 0x80;
  return answer;
}

void main() {
  group('WordsParser', () {
    test('single word in WORDS.TOK', () {
      final abc = _wordsTokStr('abc');
      final data = Uint8List.fromList([
        0, 2, // header: offset to 'A' words is at byte 2
        0, abc[0], abc[1], abc[2], 0, 1, // word 'abc' with ID 1
      ]);

      final dict = WordsParser.parse(data);
      expect(dict.wordCount, equals(1));
      expect(dict.wordToId('abc'), equals(1));
      expect(dict.wordToId('other'), equals(-1));
      expect(dict.idToWords(1), equals(['abc']));
    });

    test('two words with shared prefix overlap', () {
      final w1 = _wordsTokStr('abc');
      final w2 = _wordsTokStr('zz');
      final data = Uint8List.fromList([
        0, 2, // header offset = 2
        0, w1[0], w1[1], w1[2], 1, 0, // 'abc' with ID 256
        1, w2[0], w2[1], 0, 20,       // 'azz' with ID 20 (skip 1 byte 'a', then 'zz')
      ]);

      final dict = WordsParser.parse(data);
      expect(dict.wordCount, equals(2));
      expect(dict.wordToId('abc'), equals(256));
      expect(dict.wordToId('azz'), equals(20));
      expect(dict.idToWords(256), equals(['abc']));
      expect(dict.idToWords(20), equals(['azz']));
    });

    test('three words with prefix overlap', () {
      final w1 = _wordsTokStr('abc');
      final w2 = _wordsTokStr('zg');
      final w3 = _wordsTokStr('png');
      final data = Uint8List.fromList([
        0, 2, // header offset = 2
        0, w1[0], w1[1], w1[2], 1, 0,   // 'abc' -> ID 256
        1, w2[0], w2[1], 0, 20,         // 'azg' -> ID 20
        0, w3[0], w3[1], w3[2], 0, 30,  // 'png' -> ID 30
      ]);

      final dict = WordsParser.parse(data);
      expect(dict.wordCount, equals(3));
      expect(dict.wordToId('abc'), equals(256));
      expect(dict.wordToId('azg'), equals(20));
      expect(dict.wordToId('png'), equals(30));
    });

    test('startOffset beyond data throws CorruptResourceException', () {
      final data = Uint8List.fromList([0, 10, 0, 1]);
      expect(
        () => WordsParser.parse(data),
        throwsA(isA<CorruptResourceException>()),
      );
    });

    test('truncated mid-suffix throws CorruptResourceException', () {
      final abc = _wordsTokStr('abc');
      final full = Uint8List.fromList([
        0, 2,
        0, abc[0], abc[1], abc[2], 0, 1,
      ]);
      expect(WordsParser.parse(full).wordToId('abc'), equals(1));
      final truncated = Uint8List.fromList([0, 2, 0, abc[0], abc[1]]);
      expect(
        () => WordsParser.parse(truncated),
        throwsA(isA<CorruptResourceException>()),
      );
    });

    test('complete final word ending exactly at EOF parses', () {
      final abc = _wordsTokStr('abc');
      final data = Uint8List.fromList([0, 2, 0, abc[0], abc[1], abc[2], 0, 1]);
      expect(WordsParser.parse(data).wordToId('abc'), equals(1));
    });
  });

  group('AgiDictionary consistency', () {
    test('reassigning a word to a new group removes it from the old group',
        () {
      final dict = AgiDictionary();
      dict.addWord('run', 1);
      expect(dict.wordToId('run'), equals(1));
      expect(dict.idToWords(1), contains('run'));

      dict.addWord('run', 2);
      expect(dict.wordToId('run'), equals(2));
      expect(dict.idToWords(1), isNot(contains('run')));
      expect(dict.idToWords(2), contains('run'));
    });

    test('adding the same word to the same group twice yields it once', () {
      final dict = AgiDictionary();
      dict.addWord('run', 1);
      dict.addWord('run', 1);
      expect(dict.idToWords(1).where((w) => w == 'run').length, equals(1));
      expect(dict.wordCount, equals(1));
    });

    test('mutating the list returned by idToWords does not affect the dictionary',
        () {
      final dict = AgiDictionary();
      dict.addWord('run', 1);
      final words = dict.idToWords(1);
      try {
        words.add('corrupt');
      } catch (_) {
        // Unmodifiable views throw UnsupportedError.
      }
      expect(dict.idToWords(1), isNot(contains('corrupt')));
    });

    test('mutating the list passed to setDeduplicatedWords does not affect the dictionary',
        () {
      final dict = AgiDictionary();
      dict.addWord('run', 1);
      final synonyms = ['run', 'jog'];
      dict.setDeduplicatedWords(1, synonyms);
      synonyms.add('corrupt');
      synonyms[0] = 'corrupt';
      expect(dict.idToDeduplicatedWords(1), equals(['run', 'jog']));
    });

    test('mutating the map passed to loadDeduplicatedWords does not affect the dictionary',
        () {
      final dict = AgiDictionary();
      dict.addWord('run', 1);
      final groups = {
        1: ['run', 'jog'],
      };
      dict.loadDeduplicatedWords(groups);
      groups[1]!.add('corrupt');
      groups[2] = ['sprint'];
      expect(dict.idToDeduplicatedWords(1), equals(['run', 'jog']));
      expect(dict.idToDeduplicatedWords(2), isNot(contains('sprint')));
    });
  });
}
