import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';

void main() {
  group('SciVocab & VOCAB.000', () {
    test('loads VOCAB.000 from Police Quest 2 and resolves word groups', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference game missing');
        return;
      }

      final volMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final vocabBytes = volMgr.getResource(SciResourceType.vocab, 0);
      final vocab = SciVocab();
      vocab.loadVocab000(vocabBytes);

      expect(vocab.isEmpty, isFalse);
      expect(vocab.wordCount, greaterThan(1000));
      expect(vocab.groupCount, greaterThan(500));

      // Test core words
      final lookWords = vocab.lookup('look');
      expect(lookWords, isNotNull);
      expect(lookWords, isNotEmpty);
      final lookGroup = lookWords!.first.group;

      // "examine" should share the group or be a synonym
      final examineWords = vocab.lookup('examine');
      expect(examineWords, isNotNull);
      expect(examineWords!.first.group, lookGroup);

      // Plural resolution
      final doorsWords = vocab.lookup('doors');
      expect(doorsWords, isNotNull);
      final doorWords = vocab.lookup('door');
      expect(doorWords, isNotNull);
      expect(doorsWords!.first.group, doorWords!.first.group);

      // Number lookup
      final numWords = vocab.lookup('42');
      expect(numWords, isNotNull);
      expect(numWords!.first.group, SciVocab.groupNumber);

      // Group text resolution
      final lookText = vocab.getWordGroupText(lookGroup);
      expect(lookText, anyOf('look', 'examine', 'see', 'gaze'));

      // Synonyms
      vocab.setSynonym(999, lookGroup);
      expect(vocab.resolveGroup(999), lookGroup);
    });
  });
}
