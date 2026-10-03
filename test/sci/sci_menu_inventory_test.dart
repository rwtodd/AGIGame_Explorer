import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_test/flutter_test.dart';

/// QoL input paths for SCI games: TAB opens the inventory screen, ESC and
/// clicks on the menu/status strip bring up the pull-down menus.
void main() {
  group('SCI menu and inventory QoL (SQ3)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sci_menu_qol_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// Boots SQ3 to the room 2 gameplay state used by all probes below.
    /// Returns null when the reference tree is missing (tests skip).
    SciGameEngine? bootSq3() {
      final sq3Dir = Directory('reference_games/space-quest-3');
      if (!sq3Dir.existsSync()) return null;
      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(sq3Dir.path),
      );
      engine.saveDirectory = tempDir;
      engine.initializeGame();
      engine.restartGame();
      for (var t = 0; t < 400; t++) {
        engine.tick();
      }
      // Room 2's entrance runs on wall-clock Script.seconds, which headless
      // ticks outrun. Invoke the game's own HandsOn export to reach the
      // interactive state real play arrives at a few seconds later.
      engine.vm.executeMethod(0, 3, []);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
      return engine;
    }

    test('inventory command opens the game inventory window (TAB mechanism)',
        () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        expect(engine.segManager.globals[SciGlobals.roomNumber].toUint16(), 2);
        engine.submitCommand('inventory');
        for (var t = 0; t < 30; t++) {
          engine.tick();
        }
        expect(engine.kernel.windowManager.windowStack.isNotEmpty, isTrue,
            reason: 'inventory Said handler should open the Inv window');
      } finally {
        engine.dispose();
      }
    });

    test('strip title click opens that menu via the game MenuSelect path',
        () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        engine.handleMouseClick(const Offset(60, 5));
        expect(engine.kernel.menuBar.openMenuId, 2);
      } finally {
        engine.dispose();
      }
    });

    test('strip click that hits no title falls back to the first menu', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        // Far right of the strip: status text is showing, no title hit.
        engine.handleMouseClick(const Offset(310, 5));
        expect(engine.kernel.menuBar.openMenuId, 1);
      } finally {
        engine.dispose();
      }
    });

    test('click-away cancels an open menu without reopening it', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        engine.handleKeyPress(27, ascii: 27);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
        expect(engine.kernel.menuBar.openMenuId, isNotNull);
        engine.handleMouseClick(const Offset(160, 100));
        expect(engine.kernel.menuBar.openMenuId, isNull);
      } finally {
        engine.dispose();
      }
    });

    test('menus survive save and restore', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        expect(engine.kernel.menuBar.menus.isNotEmpty, isTrue);
        final titlesBefore = engine.kernel.menuBar.menus
            .map((m) => m.title)
            .join('|');
        engine.saveGameStateSync(slot: 1, description: 'menu test');
        // Simulate a fresh engine picking the save back up.
        expect(engine.restoreGameStateSync(slot: 1), isTrue);
        expect(
            engine.kernel.menuBar.menus.map((m) => m.title).join('|'),
            titlesBefore);
        engine.handleKeyPress(27, ascii: 27);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
        expect(engine.kernel.menuBar.openMenuId, 1,
            reason: 'ESC must open the menu after a restore');
      } finally {
        engine.dispose();
      }
    });

    test('menu Save routes to the host dialog when attached', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        var saveRequested = false;
        engine.kernel.onSaveGameRequested = () => saveRequested = true;
        final game = engine.segManager.globals[SciGlobals.game];
        engine.vm.sendSelector(
            game, engine.selectors.findSelector('save')!, []);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
        expect(saveRequested, isTrue);
        expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue,
            reason: 'script SaveDialog must not open instead');
      } finally {
        engine.dispose();
      }
    });

    test('menu Restore routes to the host dialog when attached', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        var restoreRequested = false;
        engine.kernel.onRestoreGameRequested = () => restoreRequested = true;
        final game = engine.segManager.globals[SciGlobals.game];
        engine.vm.sendSelector(
            game, engine.selectors.findSelector('restore')!, []);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
        expect(restoreRequested, isTrue);
        expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue,
            reason: 'script RestoreDialog must not open instead');
      } finally {
        engine.dispose();
      }
    });

    test('restore of a pre-menu save keeps the live menus', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        expect(engine.kernel.menuBar.menus.isNotEmpty, isTrue);
        // Simulate a save written before menu persistence existed.
        final map = jsonDecode(
                engine.saveGameStateSync(slot: 1).readAsStringSync())
            as Map<String, dynamic>;
        map.remove('menuBar');
        final dir = engine.saveDirectory!;
        File('${dir.path}${Platform.pathSeparator}slot_9.sav')
            .writeAsStringSync(jsonEncode(map));
        expect(engine.restoreGameStateSync(slot: 9, directory: dir), isTrue);
        expect(engine.kernel.menuBar.menus.isNotEmpty, isTrue,
            reason: 'old saves must not land menuless');
        engine.handleKeyPress(27, ascii: 27);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
        expect(engine.kernel.menuBar.openMenuId, 1);
      } finally {
        engine.dispose();
      }
    });

    test('title click leaves a MenuSelect trace in kernel logs', () {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        engine.kernel.recentCallLogs.clear();
        engine.handleMouseClick(const Offset(60, 5));
        expect(engine.kernel.menuBar.openMenuId, 2);
        expect(
            engine.kernel.recentCallLogs
                .any((l) => l.contains('MenuSelect fresh')),
            isTrue);
      } finally {
        engine.dispose();
      }
    });

    testWidgets('TAB key opens inventory through GameScreen', (tester) async {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        await tester.pumpWidget(
          MaterialApp(home: GameScreen(session: engine)),
        );
        await tester.pump();
        expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(engine.kernel.windowManager.windowStack.isNotEmpty, isTrue,
            reason: 'TAB should open the inventory window');
      } finally {
        engine.dispose();
      }
    });

    testWidgets('ESC opens menu and arrows navigate instead of walking ego',
        (tester) async {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        await tester.pumpWidget(
          MaterialApp(home: GameScreen(session: engine)),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(engine.kernel.menuBar.openMenuId, 1);

        final seg = engine.segManager;
        final ego = seg.getObject(seg.globals[SciGlobals.ego])!;
        final xSel = engine.selectors.findSelector('x')!;
        final ySel = engine.selectors.findSelector('y')!;
        final x0 = ego.getProp(seg, xSel);
        final y0 = ego.getProp(seg, ySel);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(engine.kernel.menuBar.highlightedItemId, 2);
        expect(ego.getProp(seg, xSel), x0);
        expect(ego.getProp(seg, ySel), y0);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(engine.kernel.menuBar.openMenuId, isNull);
      } finally {
        engine.dispose();
      }
    });

    testWidgets('tapping the strip opens a menu through GameScreen',
        (tester) async {
      final engine = bootSq3();
      if (engine == null) {
        markTestSkipped('SQ3 reference tree missing');
        return;
      }
      try {
        await tester.pumpWidget(
          MaterialApp(home: GameScreen(session: engine)),
        );
        await tester.pump();
        final rect = tester.getRect(find.byType(GamePlayfieldWidget));
        // The playfield is 4:3 aspect-fitted inside its rect; map the tap
        // into the fitted frame: near its top-right (strip rows, past the
        // menu titles, so the miss-click fallback is exercised).
        const targetAspect = 4.0 / 3.0;
        final fittedHeight = rect.width / targetAspect;
        final topOffset = (rect.height - fittedHeight) / 2;
        await tester.tapAt(Offset(rect.left + rect.width * 0.9,
            rect.top + topOffset + fittedHeight * 0.01));
        await tester.pump();
        expect(engine.kernel.menuBar.openMenuId, isNotNull);
      } finally {
        engine.dispose();
      }
    });
  });
}
