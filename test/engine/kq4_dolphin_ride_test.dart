import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KQ4 Room 43: Riding dolphin moves Ego East under program control', () async {
    const gamePath = '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
    final loader = await AgiResourceLoader.fromDirectory(gamePath);
    final engine = AgiGameEngine(resourceLoader: loader);

    // Initial state from user in Room 43 right after getting on dolphin (%v156 = 5 or 6)
    final logic0 = loader.loadLogic(0);
    engine.interpreter.loadRootScript(logic0, scriptNumber: 0);
    engine.onNewRoom(43);
    await engine.tick(); // Complete new room first cycle (clears f5 and logic 100 inits)
    engine.onUserControl(false); // under program.control()

    final ego = engine.ego;
    ego.x = 117;
    ego.y = 149;
    ego.view = 29;
    ego.loop = 0;
    ego.cel = 0;
    ego.direction = 0;
    ego.isCycling = false;

    // Simulate user typing "ride dolphin" in room 43
    engine.memory.setFlag(180); // Riding dolphin flag
    engine.memory.setFlag(224); // Animation trigger flag
    engine.memory.setVar(156, 5); // Sequence step 5
    engine.memory.setVar(37, 204);

    // Tick 1: Script advances steps 5 and 6, sets view 29, loop 0, and %v6 = 3 (East)
    await engine.tick();

    expect(engine.memory.getVar(156), 7);
    expect(engine.memory.getVar(6), 3, reason: 'Variable 6 should be set to 3 (East)');
    expect(ego.direction, 3, reason: 'Ego direction should be 3 (East)');
    expect(ego.isCycling, isTrue, reason: 'Ego should be cycling while moving on dolphin');

    // Simulate cycles until dolphin and Ego reach screen edge and transition to Room 31
    int cycles = 0;
    while (engine.memory.getVar(0) == 43 && cycles < 100) {
      await engine.tick();
      cycles++;
    }

    expect(engine.memory.getVar(0), 31, reason: 'Dolphin ride should transition to room 31 at the screen boundary');
  });
}
