import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  test('KQ4: Riding unicorn carries Rosella across rooms 20, 27, 28, 29, 30 to Room 79', () async {
    final gamePath = Directory('reference_games/kings-quest-4-agi').existsSync()
        ? 'reference_games/kings-quest-4-agi'
        : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
    if (!Directory(gamePath).existsSync()) return;
    final loader = await AgiResourceLoader.fromDirectory(gamePath);
    final engine = AgiGameEngine(resourceLoader: loader);

    final logic0 = loader.loadLogic(0);
    engine.interpreter.loadRootScript(logic0, scriptNumber: 0);
    engine.onNewRoom(20);
    await engine.tick(); // Init room 20

    // Initial state: Rosella is mounted on the bridled unicorn in Room 20
    engine.memory.setFlag(176); // Riding unicorn flag
    engine.memory.setFlag(36); // Program control flag
    engine.ego.view = 211;
    engine.ego.x = 65;
    engine.ego.y = 92;
    engine.animatedObjects[12].x = 65;
    engine.animatedObjects[12].y = 92;
    engine.ego.direction = 3;
    engine.ego.isCycling = true;
    engine.memory.setVar(155, 3);
    engine.memory.setFlag(223); // Trigger move.obj sequence

    int cycles = 0;
    while (cycles < 1000 && engine.memory.getVar(0) != 79) {
      await engine.tick();
      cycles++;
    }

    expect(engine.memory.getVar(0), 79, reason: 'Unicorn ride should carry Rosella all the way to Room 79 (Genesta\'s island)');
    expect(cycles, lessThan(1000));
  });
}
