import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
