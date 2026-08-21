import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Debug flag/var pins', () {
    test('pinned values are restored after each tick', () {
      final engine = AgiGameEngine(speedHz: 20);
      engine.memory.pinFlag(36, true);
      engine.memory.pinVar(3, 42);

      engine.memory.resetFlag(36);
      engine.memory.setVar(3, 7);
      engine.tick();

      expect(engine.memory.getFlag(36), isTrue);
      expect(engine.memory.getVar(3), 42);

      engine.memory.unpinVar(3);
      engine.memory.setVar(3, 1);
      engine.tick();
      expect(engine.memory.getVar(3), 1);

      engine.dispose();
    });

    test('pinned-off flags survive the post-scan transient resets', () {
      final engine = AgiGameEngine(speedHz: 20);
      // f2 is cleared every tick; pinning it ON keeps it for the next scan.
      engine.memory.pinFlag(2, true);
      engine.tick();
      expect(engine.memory.getFlag(2), isTrue);
      engine.dispose();
    });

    test('unpinned SET values are not restored after a tick', () {
      final engine = AgiGameEngine(speedHz: 20);
      engine.memory.setFlag(36);
      engine.memory.setVar(3, 42);
      engine.memory.watchFlag(36);
      engine.memory.watchVar(3);

      engine.memory.resetFlag(36);
      engine.memory.setVar(3, 7);
      engine.tick();

      expect(engine.memory.getFlag(36), isFalse);
      expect(engine.memory.getVar(3), 7);
      engine.dispose();
    });

    test('pinned-to-zero variables survive post-scan zeroing', () {
      final engine = AgiGameEngine(speedHz: 20);
      // v4 is cleared every tick as a transient edge-hit register.
      engine.memory.pinVar(4, 0);
      engine.memory.setVar(4, 9);
      engine.tick();
      expect(engine.memory.getVar(4), 0);
      expect(engine.memory.isVarPinned(4), isTrue);
      engine.dispose();
    });
  });
}
