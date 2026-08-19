import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  test('Space Quest 2 Room 62 Ego top bounds and horizon test', () async {
    final sq2Dir = Directory('reference_games/space-quest-2');
    if (!sq2Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
    final engine = AgiGameEngine(resourceLoader: loader);

    // Initialize in Room 62 (which sets horizon to 10)
    await engine.initializeGame(startingRoom: 62);

    final ego = engine.ego;
    final celHeight = ego.getCelHeight();
    expect(celHeight, greaterThan(15), reason: 'Ego standing cel has a non-zero height');

    // Position Ego inside the closet corridor and walk North
    ego.x = 94;
    ego.y = 42;
    engine.setEgoDirection(1); // North

    // Walk North until stopped
    for (int t = 0; t < 50; t++) {
      await engine.tick();
      if (ego.direction == 0) break;
    }

    final egoTop = ego.y - ego.getCelHeight() + 1;
    expect(egoTop, greaterThanOrEqualTo(0), reason: 'Ego top pixel must not cross into status line row 0');
    expect(ego.y, greaterThanOrEqualTo(ego.getCelHeight() - 1), reason: 'Ego baseline must respect celHeight top boundary');

    engine.dispose();
  });
}
