import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KQ3 room 7 engine runs multiple cycles without freezing', () {
    final kq3Dir = Directory('reference_games/kings-quest-3');
    if (!kq3Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
    final kq3Engine = AgiGameEngine(resourceLoader: loader);

    kq3Engine.initializeGame();

    // Skip intro to room 7
    kq3Engine.handleKeyPress(13);
    kq3Engine.tick();

    expect(kq3Engine.memory.getVar(0), 7);

    // Run 100 cycles in room 7
    for (int t = 1; t <= 100; t++) {
      kq3Engine.tick();
      expect(kq3Engine.lastError, isNull);
    }
  });

  testWidgets('KQ3 room 7 renders in GameScreen and pumps multiple frames with clock updates', (tester) async {
    final kq3Dir = Directory('reference_games/kings-quest-3');
    if (!kq3Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
    final kq3Engine = AgiGameEngine(resourceLoader: loader);
    kq3Engine.initializeGame();

    // Skip intro to room 7
    kq3Engine.handleKeyPress(13);
    kq3Engine.tick();
    expect(kq3Engine.memory.getVar(0), 7);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(engine: kq3Engine),
      ),
    );

    // Run 60 ticks in room 7 (at 20 Hz, crossing 1 second to trigger clock update on screen)
    for (int t = 1; t <= 60; t++) {
      kq3Engine.tick();
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify text screen buffer has content (KQ3 status bar / clock rendered)
    expect(kq3Engine.textScreenBuffer.hasContent, isTrue);
    expect(kq3Engine.lastError, isNull);

    kq3Engine.dispose();
  });
}
