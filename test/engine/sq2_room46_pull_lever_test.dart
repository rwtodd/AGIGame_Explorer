import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  test('Space Quest 2 Room 46 pull lever test', () async {
    final sq2Dir = Directory('reference_games/space-quest-2');
    if (!sq2Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
    final engine = AgiGameEngine(resourceLoader: loader);

    // Initialize in Room 46
    await engine.initializeGame(startingRoom: 46);

    // Set up variables and flags matching snapshot
    engine.memory.setFlag(32); // power on
    engine.memory.setVar(37, 1);     // VAC
    engine.memory.setVar(40, 5);     // altitude achieved

    // User submits command: "pull lever"
    engine.submitCommand('pull lever');
    await engine.tick();

    var dialogShownCount = 0;
    for (int t = 0; t < 25; t++) {
      await engine.tick();
      if (engine.activeDialog != null) {
        dialogShownCount++;
        expect(engine.activeDialog?.message, contains('Vertical controls are now ineffective'));
        engine.dismissDialog();
      }
    }

    // Must be shown exactly once, not looping
    expect(dialogShownCount, equals(1));
    expect(engine.memory.getVar(6), equals(0));
    expect(engine.ego.direction, equals(0));
    expect(engine.memory.getVar(32), equals(2)); // Centered / neutral throttle
    expect(engine.memory.getVar(30), equals(0)); // Countdown reached 0
    expect(engine.activeDialog, isNull);

    engine.dispose();
  });
}
