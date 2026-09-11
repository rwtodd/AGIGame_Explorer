import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/parser/sci_said_matcher.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

void main() {
  group('SCI0 Stage 11 Parser & Said Matcher Integration Tests', () {
    late SciVolumeManager volumeManager;

    setUpAll(() async {
      final dir = Directory('reference_games/police-quest-2');
      if (await dir.exists()) {
        volumeManager = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      }
    });

    test('initializes game and loads VOCAB.000 into kernel', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();

      expect(engine.kernel.vocab, isNotNull);
      expect(engine.kernel.vocab!.wordCount, greaterThan(1000));
      expect(engine.kernel.vocab!.lookup('look'), isNotNull);
      expect(engine.kernel.vocab!.lookup('door'), isNotNull);
      expect(engine.kernel.vocab!.lookup('car'), isNotNull);
    });

    test('kDrawStatus updates status line and fires callback', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();

      String? updatedStatus;
      engine.kernel.onDrawStatus = (text) => updatedStatus = text;

      final textReg = engine.segManager.allocString('Score: 10 of 300');
      final res = engine.kernel.call(engine.vm, 0x23, 1, [textReg]);

      expect(res, isA<SciReg>());
      expect(engine.kernel.currentStatusLine, 'Score: 10 of 300');
      expect(engine.statusLine, 'Score: 10 of 300');
      expect(updatedStatus, 'Score: 10 of 300');
    });

    test('kParse tokenizes known words and sets claimed to 0', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();

      final eventReg = SciReg.pointer(SciSegManager.cloneSegmentId, 9991);
      final eventObj = SciObject(
        pos: eventReg,
        variables: List<SciReg>.filled(16, const SciReg.fromInt(0)),
      );
      engine.segManager.clones[9991] = eventObj;
      eventObj.baseVars.addAll([
        engine.selectors.type,
        engine.selectors.message,
        engine.selectors.modifiers,
        engine.selectors.claimed,
      ]);

      final strReg = engine.segManager.allocString('look car');
      final res = engine.kernel.call(engine.vm, 0x24, 2, [strReg, eventReg]);

      expect(res.toUint16(), 1);
      expect(engine.kernel.parserIsValid, isTrue);
      expect(engine.kernel.lastParsedWords.length, 2);
      expect(engine.kernel.lastParsedWords[0].text, anyOf('look', 'gaze', 'examine', 'see'));
      expect(engine.kernel.lastParsedWords[1].text, 'car');
      expect(engine.kernel.lastUnknownWord, isNull);
      expect(eventObj.getProp(engine.segManager, engine.selectors.claimed).toUint16(), 0);
    });

    test('kParse flags unknown word and sets claimed to 1', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();

      final eventReg = SciReg.pointer(SciSegManager.cloneSegmentId, 9992);
      final eventObj = SciObject(
        pos: eventReg,
        variables: List<SciReg>.filled(16, const SciReg.fromInt(0)),
      );
      engine.segManager.clones[9992] = eventObj;
      eventObj.baseVars.addAll([
        engine.selectors.type,
        engine.selectors.message,
        engine.selectors.modifiers,
        engine.selectors.claimed,
      ]);

      final strReg = engine.segManager.allocString('xyzzy frobozz');
      final res = engine.kernel.call(engine.vm, 0x24, 2, [strReg, eventReg]);

      expect(res.toUint16(), 1);
      expect(engine.kernel.parserIsValid, isFalse);
      expect(engine.kernel.lastUnknownWord, 'xyzzy');
      expect(eventObj.getProp(engine.segManager, engine.selectors.claimed).toUint16(), 1);
    });

    test('kSaid evaluates Said specs and claims event on match', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();

      final lookWord = engine.kernel.vocab!.lookup('look')!.first;
      final keyWord = engine.kernel.vocab!.lookup('key')!.first;

      final eventReg = SciReg.pointer(SciSegManager.cloneSegmentId, 9993);
      final eventObj = SciObject(
        pos: eventReg,
        variables: List<SciReg>.filled(16, const SciReg.fromInt(0)),
      );
      engine.segManager.clones[9993] = eventObj;
      eventObj.baseVars.addAll([
        engine.selectors.type,
        engine.selectors.message,
        engine.selectors.modifiers,
        engine.selectors.claimed,
      ]);

      // Parse 'look key'
      final strReg = engine.segManager.allocString('look key');
      engine.kernel.call(engine.vm, 0x24, 2, [strReg, eventReg]);

      // Create a matching Said spec: look / key
      final specBytes = [
        (lookWord.group >> 8) & 0xFF,
        lookWord.group & 0xFF,
        SciSaidOp.slash,
        (keyWord.group >> 8) & 0xFF,
        keyWord.group & 0xFF,
        SciSaidOp.term,
      ];
      final specReg = engine.segManager.allocHunk(specBytes.length);
      final buf = engine.segManager.hunkBuffers[specReg.offset]!;
      for (int i = 0; i < specBytes.length; i++) {
        buf[i] = specBytes[i];
      }

      // Call kSaid
      final saidRes = engine.kernel.call(engine.vm, 0x25, 1, [specReg]);
      expect(saidRes.toUint16(), 1);
      expect(eventObj.getProp(engine.segManager, engine.selectors.claimed).toUint16(), 1);
      expect(engine.kernel.activeCycleSaidSpecs.isNotEmpty, isTrue);
      expect(engine.kernel.activeCycleSaidSpecs.last.toSaidString(engine.kernel.vocab), contains('key'));
    });

    test('submitCommand executes end-to-end command in room 33', () {
      final engine = SciGameEngine(volumeManager: volumeManager);
      engine.initializeGame();
      engine.restartGame();

      // Run until canInput is enabled (around cycle 91)
      for (int i = 0; i < 120; i++) {
        engine.tick();
        if (engine.isInputEnabled) break;
      }
      expect(engine.isInputEnabled, isTrue);

      // Submit command 'look key'
      engine.submitCommand('look key');

      // Verify Said specs evaluated and state export includes parser info
      expect(engine.kernel.activeCycleSaidSpecs.isNotEmpty, isTrue);
      final exported = engine.exportState();
      expect(exported['parser'], isNotNull);
      expect(exported['parser']['lastInput'], 'look key');
      expect(exported['parser']['activeCycleSaidSpecs'], isNotEmpty);

      engine.dispose();
    });
  });
}
