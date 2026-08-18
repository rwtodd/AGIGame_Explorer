import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Status Bar and Menu System UI Widget Tests', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine();
      engine.initializeGame();
      engine.onStatusLine(true);

      // Configure a test menu
      engine.onSetMenu('Sierra');
      engine.onSetMenuItem('About <F1>', 1);
      engine.onSetMenuItem('Help <F2>', 2);

      engine.onSetMenu('File');
      engine.onSetMenuItem('Save <F5>', 3);
      engine.onSetMenuItem('Restore <F7>', 4);
      engine.onSetMenuItem('--------', 99);
      engine.onSetMenuItem('Restart <F9>', 5);

      engine.onSubmitMenu();
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('renders GamePlayfieldWidget with status line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GamePlayfieldWidget), findsOneWidget);
      expect(engine.isStatusLineEnabled, isTrue);
      expect(engine.isMenuOpen, isFalse);
    });

    testWidgets('ESC opens menu, Arrow keys navigate, and Enter triggers controller', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pumpAndSettle();

      // Press ESC to open menu
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(engine.isMenuOpen, isTrue);
      expect(engine.menuManager.activeMenuIndex, 0); // Sierra menu
      expect(engine.menuManager.activeMenu!.selectedItemIndex, 0); // About

      // Navigate Right to File menu
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(engine.menuManager.activeMenuIndex, 1); // File menu
      expect(engine.menuManager.activeMenu!.name, 'File');

      // Navigate Down to Save (0) -> Restore (1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(engine.menuManager.activeMenu!.selectedItemIndex, 1); // Restore (ctl 4)

      // Press Enter to select Restore
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(engine.isMenuOpen, isFalse);
      expect(engine.memory.getController(4), isTrue); // Controller 4 triggered!
    });

    testWidgets('ESC closes active menu without triggering controller', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pumpAndSettle();

      // Open menu
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(engine.isMenuOpen, isTrue);

      // Close menu with ESC
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(engine.isMenuOpen, isFalse);
      expect(engine.memory.getController(1), isFalse);
    });

    testWidgets('Opening menu pauses game loop ticks and closing menu resumes them', (tester) async {
      engine.start();
      await tester.pump(const Duration(milliseconds: 150));
      final cyclesBefore = engine.cycleCount;
      expect(cyclesBefore, greaterThan(0));

      // Open menu with ESC
      engine.openMenu();
      expect(engine.isMenuOpen, isTrue);

      final cycleWhenOpened = engine.cycleCount;
      // Pump several periodic intervals while menu is open
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.cycleCount, equals(cycleWhenOpened), reason: 'Cycle count must not advance while menu is open');

      // Close menu
      engine.closeMenu();
      expect(engine.isMenuOpen, isFalse);

      // Pump periodic intervals after closing
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.cycleCount, greaterThan(cycleWhenOpened), reason: 'Cycle count must resume advancing after menu is closed');

      engine.stop();
    });
  });

  group('Reference Games Status Line & Menu Integration', () {
    test('King\'s Quest II sets up authentic menus and status line in gameplay room', () async {
      final dir = Directory('reference_games/kings-quest-2');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Title room (97) has status line disabled
      expect(engine.memory.getVar(0), 97);
      expect(engine.isStatusLineEnabled, isFalse);

      // Press key to start game (transitions to room 1)
      engine.handleKeyPress(13);
      await engine.tick();

      expect(engine.memory.getVar(0), 1);
      expect(engine.isStatusLineEnabled, isTrue);
      expect(engine.menuManager.isSubmitted, isTrue);
      expect(engine.menuManager.menus.isNotEmpty, isTrue);

      final menuNames = engine.menuManager.menus.map((m) => m.name.trim()).toList();
      expect(menuNames, contains('Sierra'));
      expect(menuNames, contains('File'));
      expect(menuNames, contains('Action'));
      expect(menuNames, contains('Special'));

      engine.dispose();
    });

    test('King\'s Quest III sets up menus including Speed menu in gameplay room', () async {
      final dir = Directory('reference_games/kings-quest-3');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Intro room (45) has status line off
      expect(engine.memory.getVar(0), 45);
      expect(engine.isStatusLineEnabled, isFalse);

      // Skip intro to room 7
      engine.handleKeyPress(13);
      await engine.tick();

      expect(engine.memory.getVar(0), 7);
      expect(engine.isStatusLineEnabled, isTrue);
      expect(engine.menuManager.isSubmitted, isTrue);

      final menuNames = engine.menuManager.menus.map((m) => m.name.trim()).toList();
      expect(menuNames, contains('Sierra'));
      expect(menuNames, contains('File'));
      expect(menuNames, contains('Speed'));

      engine.dispose();
    });

    test('The Black Cauldron boots with active status line in gameplay room', () async {
      final dir = Directory('reference_games/black-cauldron');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Title room is 67
      expect(engine.memory.getVar(0), 67);

      // Transition to room 8
      engine.changeRoom(8);
      await engine.tick();

      expect(engine.memory.getVar(0), 8);
      expect(engine.isStatusLineEnabled, isTrue);
      engine.dispose();
    });

    test('King\'s Quest IV (AGI V3) boots with menus and status line', () async {
      final dir = Directory('reference_games/kings-quest-4-agi');
      if (!dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Opening room in KQ4 AGI
      expect(engine.memory.getVar(0), isNot(0));
      expect(engine.menuManager.isSubmitted, isTrue);
      engine.dispose();
    });
  });
}
