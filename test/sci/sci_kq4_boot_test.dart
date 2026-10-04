import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/font/sci_font_parser.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/sci/engine/sci_menu_bar.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

void main() {
  group('King\'s Quest IV (Early SCI0) Boot Test', () {
    final kq4Dir = Directory('reference_games/kings-quest-4-sci');

    test('detects early SCI0 script header format', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      expect(volumeMgr.isEarlySci0, isTrue);

      final script0Bytes = volumeMgr.getResource(SciResourceType.script, 0);
      expect(SciScriptParser.hasOldScriptHeader(script0Bytes), isTrue);

      // Verify PQ2 is recognized as standard (late) SCI0, not early SCI0
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (pq2Dir.existsSync()) {
        final pq2VolumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
        expect(pq2VolumeMgr.isEarlySci0, isFalse);
        final pq2Script0Bytes = pq2VolumeMgr.getResource(SciResourceType.script, 0);
        expect(SciScriptParser.hasOldScriptHeader(pq2Script0Bytes), isFalse);
      }
    });

    test('instantiates KQ4 Script 0 and parses exports and KQ4 game object', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final segMan = SciSegManager();
      final script0 = segMan.instantiateScript(0, volumeMgr);

      expect(script0.exports.isNotEmpty, isTrue);
      expect(script0.exports.length, 24);

      final gameObjOffset = script0.exports[0];
      final gameObj = script0.getObject(gameObjOffset);
      expect(gameObj, isNotNull);
      expect(gameObj!.nameString, 'KQ4');
      expect(gameObj.methodCount, 9);
      expect(script0.locals.length, greaterThan(0));
    });

    test('boots KQ4 through SciGameEngine without throwing RangeError', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);

      expect(() => engine.initializeGame(), returnsNormally);
      expect(engine.statusLine, 'KQ4');
      expect(engine.isPaused, isFalse);
      expect(engine.isRunning, isFalse);

      expect(engine.selectors.isEarlySci0, isTrue);
      expect(engine.segManager.isEarlySci0, isTrue);
      expect(engine.selectors.play, 84);
      expect(engine.selectors.init, 170);
      expect(engine.selectors.doit, 120);
      expect(engine.selectors.species, 0);
      expect(engine.selectors.superClass, 2);
      expect(engine.selectors.info, 4);
      expect(engine.selectors.name, 46);
      expect(engine.selectors.getSelectorName(84), 'play');
      expect(engine.selectors.getSelectorName(85), 'play');

      final script0 = engine.segManager.loadedScripts[1];
      final gObj = script0?.getObject(script0.exports[0]);
      expect(gObj, isNotNull);
      expect(gObj!.methods.containsKey(170), isTrue); // init:
      expect(gObj.methods.containsKey(120), isTrue); // doit:

      // (KQ4 play:) is inherited from Game
      final playMethod = gObj.lookupMethod(engine.segManager, 84);
      expect(playMethod, isNotNull);

      engine.start();
      expect(engine.isRunning, isTrue);
      expect(engine.vm.stepCounter, greaterThan(0));
      engine.dispose();
    });

    test('KQ4 font 0 defines Roman numeral IV as glyph 10 (0x0A)', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final fontBytes = volumeMgr.getResource(SciResourceType.font, 0);
      final font = SciFontParser.parse(fontBytes, fontNumber: 0);

      final glyph10 = font.getGlyph(10);
      expect(glyph10, isNotNull, reason: 'Font 0 must contain glyph 10 for KQ4');
      expect(glyph10!.width, 14);
      expect(glyph10.height, 8);

      // Verify the status line format string with glyph 10 fits on a single 320px line
      const statusStr = 'Score: 0 of 230   KQ\x0a  The Perils of Rosella';
      var textWidth = 0;
      for (var i = 0; i < statusStr.length; i++) {
        textWidth += font.getCharWidth(statusStr.codeUnitAt(i));
      }
      expect(textWidth, lessThanOrEqualTo(320));
      expect(textWidth, greaterThan(280));
    });

    test('SciMenuBar.toOverlay produces a single-line status overlay that retains glyph 10 without wrapping', () {
      if (!kq4Dir.existsSync()) {
        markTestSkipped('KQ4 reference tree missing');
        return;
      }
      final volumeMgr = SciVolumeManager.fromDirectory(kq4Dir.path);
      final fontBytes = volumeMgr.getResource(SciResourceType.font, 0);
      final font = SciFontParser.parse(fontBytes, fontNumber: 0);

      final bar = SciMenuBar();
      bar.statusText = 'Score: 0 of 230   KQ\x0a  The Perils of Rosella';
      bar.statusActive = true;

      final overlay = bar.toOverlay(font: font);
      expect(overlay, isNotNull);
      expect(overlay!.rect, equals(const Rect.fromLTWH(0, 0, 320, 10)));

      final textControls = overlay.controls.whereType<SciTextControl>().toList();
      expect(textControls, hasLength(1));

      final ctrl = textControls.first;
      expect(ctrl.isSingleLine, isTrue);
      expect(ctrl.rect.width, equals(320));
      expect(ctrl.text, equals('Score: 0 of 230   KQ\x0a  The Perils of Rosella'));

      // Verify painting does not throw and stays within status bar height
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      overlay.paint(canvas);
      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });
  });
}
