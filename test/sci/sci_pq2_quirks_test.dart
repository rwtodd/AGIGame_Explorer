import 'dart:io';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_menu_bar.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for two PQ2 playthrough quirks:
/// (1) the top strip showed menu titles instead of the DrawStatus score line;
/// (2) unrecognized input produced no response dialog because parser-fail
/// dispatches targeted the wrong system globals (g0/g1 instead of g1/g2).
void main() {
  group('PQ2 playthrough quirks', () {
    late Directory tempDir;
    late SciGameEngine engine;
    bool hasPq2 = false;

    String dialogText() {
      final stack = engine.kernel.windowManager.windowStack;
      expect(stack, hasLength(1));
      final texts = stack.first.controls.whereType<SciTextControl>().toList();
      expect(texts, hasLength(1));
      return texts.first.text;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sci_pq2_quirks_');
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (pq2Dir.existsSync()) {
        hasPq2 = true;
        engine = SciGameEngine(
          volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
        );
        engine.saveDirectory = tempDir;
        engine.initializeGame();
        engine.restartGame();
        for (var t = 0; t < 100; t++) {
          engine.tick();
          if (engine.segManager.globals[SciGlobals.roomNumber].toUint16() == 33) {
            break;
          }
        }
      }
    });

    tearDown(() async {
      if (hasPq2) engine.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('status strip shows the DrawStatus score line, not menu titles', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      expect(engine.segManager.globals[SciGlobals.roomNumber].toUint16(), 33);

      final overlay = engine.kernel.menuBar.toOverlay();
      expect(overlay, isNotNull);
      final text = overlay!.controls
          .whereType<SciTextControl>()
          .map((c) => c.text)
          .join(' ');
      expect(text, contains('Score: 0 of 300'));
      expect(text, isNot(contains('File')));
    });

    test('menu strip is last-writer-wins between titles and status', () {
      final bar = SciMenuBar()
        ..addMenu(' File ', 'About:Help')
        ..addMenu(' Action ', 'Do:Thing');
      bar.visible = true;

      // No status drawn yet: titles show.
      var overlay = bar.toOverlay()!;
      expect(
        overlay.controls.whereType<SciTextControl>().map((c) => c.text),
        contains(' File '),
      );

      // DrawStatus paints over the titles.
      bar.statusText = 'Score: 0 of 300';
      bar.statusActive = true;
      overlay = bar.toOverlay()!;
      final shown = overlay.controls
          .whereType<SciTextControl>()
          .map((c) => c.text)
          .join(' ');
      expect(shown, contains('Score: 0 of 300'));
      expect(shown, isNot(contains('File')));

      // An open menu brings titles back; closing restores the status.
      bar.openMenu(1);
      overlay = bar.toOverlay()!;
      expect(
        overlay.controls.whereType<SciTextControl>().map((c) => c.text),
        contains(' File '),
      );
      bar.closeMenu();
      overlay = bar.toOverlay()!;
      expect(
        overlay.controls.whereType<SciTextControl>().map((c) => c.text).join(' '),
        contains('Score: 0 of 300'),
      );
    });

    test('unknown word opens the wordFail response dialog', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      engine.submitCommand('dfai');
      expect(
        dialogText(),
        contains('dfai'),
      );
    });

    test('known command reaches the room handler', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      engine.submitCommand('look');
      expect(dialogText(), contains('behind the wheel'));
    });

    test('pragmaFail on the game object prints a response', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final game = engine.segManager.globals[SciGlobals.game];
      expect(game.isNull, isFalse);
      expect(
        engine.segManager.getObject(game)?.lookupMethod(
              engine.segManager,
              engine.selectors.pragmaFail,
            ),
        isNotNull,
      );

      final str = engine.segManager.allocString('dfai');
      engine.vm.sendSelector(game, engine.selectors.pragmaFail, [str]);
      final stack = engine.kernel.windowManager.windowStack;
      expect(stack, hasLength(1));
      final texts = stack.first.controls.whereType<SciTextControl>().toList();
      expect(texts, hasLength(1));
      expect(texts.first.text, isNotEmpty);
    });
  });
}
