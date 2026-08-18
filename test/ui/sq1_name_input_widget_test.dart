import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';

LogicalKeyboardKey _charToKey(String char) {
  final lower = char.toLowerCase();
  switch (lower) {
    case 'a': return LogicalKeyboardKey.keyA;
    case 'b': return LogicalKeyboardKey.keyB;
    case 'c': return LogicalKeyboardKey.keyC;
    case 'd': return LogicalKeyboardKey.keyD;
    case 'e': return LogicalKeyboardKey.keyE;
    case 'f': return LogicalKeyboardKey.keyF;
    case 'g': return LogicalKeyboardKey.keyG;
    case 'h': return LogicalKeyboardKey.keyH;
    case 'i': return LogicalKeyboardKey.keyI;
    case 'j': return LogicalKeyboardKey.keyJ;
    case 'k': return LogicalKeyboardKey.keyK;
    case 'l': return LogicalKeyboardKey.keyL;
    case 'm': return LogicalKeyboardKey.keyM;
    case 'n': return LogicalKeyboardKey.keyN;
    case 'o': return LogicalKeyboardKey.keyO;
    case 'p': return LogicalKeyboardKey.keyP;
    case 'q': return LogicalKeyboardKey.keyQ;
    case 'r': return LogicalKeyboardKey.keyR;
    case 's': return LogicalKeyboardKey.keyS;
    case 't': return LogicalKeyboardKey.keyT;
    case 'u': return LogicalKeyboardKey.keyU;
    case 'v': return LogicalKeyboardKey.keyV;
    case 'w': return LogicalKeyboardKey.keyW;
    case 'x': return LogicalKeyboardKey.keyX;
    case 'y': return LogicalKeyboardKey.keyY;
    case 'z': return LogicalKeyboardKey.keyZ;
    case ' ': return LogicalKeyboardKey.space;
    default: return LogicalKeyboardKey.space;
  }
}

void main() {
  group('Space Quest 1 - Name Input Prompt in GameScreen', () {
    late Directory sq1Dir;

    setUp(() {
      sq1Dir = Directory('reference_games/space-quest-1');
    });

    testWidgets('types name using global key events without clicking or focusing TextField', (tester) async {
      if (!sq1Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq1Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await tester.runAsync(() async {
        await engine.initializeGame();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Advance into Room 69
      engine.handleKeyPress(32);
      await tester.runAsync(() async {
        await engine.tick();
      });
      await tester.pump();

      expect(engine.currentRoom, 69);
      expect(engine.activeInputPrompt, isNotNull);
      expect(engine.activeInputPrompt!.prompt, 'First Name: ');

      // Type "Rogerr" directly via global key events (no click/tap)
      const inputStr = 'Rogerr';
      for (int i = 0; i < inputStr.length; i++) {
        final char = inputStr[i];
        await tester.sendKeyEvent(_charToKey(char), character: char);
        await tester.pump();
      }

      expect(engine.activeInputPrompt!.currentText, 'Rogerr');

      // Press Backspace to fix typo
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(engine.activeInputPrompt!.currentText, 'Roger');

      // Type " Wilco"
      const rest = ' Wilco';
      for (int i = 0; i < rest.length; i++) {
        final char = rest[i];
        await tester.sendKeyEvent(_charToKey(char), character: char);
        await tester.pump();
      }

      expect(engine.activeInputPrompt!.currentText, 'Roger Wilco');

      // Press Enter to submit prompt
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        for (int i = 0; i < 50; i++) {
          await Future.delayed(const Duration(milliseconds: 20));
          if (engine.currentRoom == 2) break;
        }
      });
      await tester.pump();

      // Verify that SQ1 accepted the name and transitioned to Room 2
      expect(engine.memory.getString(1), 'Roger Wilco');
      expect(engine.currentRoom, 2);

      engine.dispose();
    });
  });
}
