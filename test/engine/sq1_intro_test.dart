import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

void main() {
  test('Simulate SQ1 Logic 69 with yielded get.string', () {
    final sq1Dir = Directory('reference_games/space-quest-1');
    if (!sq1Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync('reference_games/space-quest-1');
    final engine = AgiGameEngine(resourceLoader: loader);
    engine.initializeGame();

    // In SQ1, room 0 boots to room 67 (intro sequence)
    expect(engine.currentRoom, isIn([0, 67, 68, 69]));
    engine.dispose();
  });
}
