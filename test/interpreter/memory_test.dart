import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';

void main() {
  group('AgiMemory', () {
    test('initializes with flag 5 true and registers 0', () {
      final mem = AgiMemory();

      expect(mem.getFlag(5), isTrue); // New room flag is set initially
      expect(mem.getFlag(0), isFalse);
      expect(mem.getVar(0), 0);
      expect(mem.getVar(1), 0);
      expect(mem.getString(0), '');
      expect(mem.getController(0), isFalse);
    });

    test('pins restore flags and variables via applyPins', () {
      final mem = AgiMemory();
      mem.pinFlag(36, true);
      mem.pinVar(3, 50);
      expect(mem.getFlag(36), isTrue);
      expect(mem.getVar(3), 50);

      mem.resetFlag(36);
      mem.setVar(3, 0);
      expect(mem.getFlag(36), isFalse);
      expect(mem.getVar(3), 0);

      mem.applyPins();
      expect(mem.getFlag(36), isTrue);
      expect(mem.getVar(3), 50);

      mem.unpinFlag(36);
      mem.resetFlag(36);
      mem.applyPins();
      expect(mem.getFlag(36), isFalse);
    });

    test('debug pins survive memory.reset and skip the Flag 1 getter hook', () {
      final mem = AgiMemory();
      mem.flagGetterHook = (i) => i == 1 ? true : null;
      expect(mem.getFlag(1), isTrue);

      mem.pinFlag(1, false);
      mem.pinVar(3, 50);
      mem.watchFlag(99);
      expect(mem.getFlag(1), isFalse, reason: 'pinned flags skip the obscurity hook');

      mem.reset();
      expect(mem.isFlagPinned(1), isTrue);
      expect(mem.isVarPinned(3), isTrue);
      expect(mem.watchedFlags.contains(99), isTrue);
      expect(mem.getFlag(1), isFalse, reason: 'reset zeros flags; pin is not live until applyPins');
      expect(mem.getVar(3), 0);

      mem.applyPins();
      expect(mem.getFlag(1), isFalse);
      expect(mem.getVar(3), 50);
    });

    test('handles 8-bit variable mutation and saturation at boundaries per AGI spec', () {
      final mem = AgiMemory();

      mem.setVar(10, 250);
      expect(mem.getVar(10), 250);

      // Increment to 255
      for (var i = 0; i < 5; i++) {
        mem.incrementVar(10);
      }
      expect(mem.getVar(10), 255);

      // Increment at 255 saturates (does not wrap to 0)
      mem.incrementVar(10);
      expect(mem.getVar(10), 255);

      // Decrement from 255
      mem.decrementVar(10);
      expect(mem.getVar(10), 254);

      // Decrement to 0
      mem.setVar(10, 1);
      mem.decrementVar(10);
      expect(mem.getVar(10), 0);

      // Decrement at 0 saturates (does not underflow to 255)
      mem.decrementVar(10);
      expect(mem.getVar(10), 0);

      // Truncation on direct set
      mem.setVar(10, 300);
      expect(mem.getVar(10), 300 & 0xFF);
    });

    test('toggles and resets flags', () {
      final mem = AgiMemory();

      expect(mem.getFlag(1), isFalse);
      mem.setFlag(1);
      expect(mem.getFlag(1), isTrue);
      mem.toggleFlag(1);
      expect(mem.getFlag(1), isFalse);
      mem.toggleFlag(1);
      expect(mem.getFlag(1), isTrue);
      mem.resetFlag(1);
      expect(mem.getFlag(1), isFalse);
    });

    test('manages string variables and controllers', () {
      final mem = AgiMemory();

      mem.setString(0, 'Sierra');
      mem.setString(23, 'AGI');
      expect(mem.getString(0), 'Sierra');
      expect(mem.getString(23), 'AGI');
      expect(mem.getString(24), ''); // Out of range

      mem.setController(10, true);
      expect(mem.getController(10), isTrue);
      mem.resetControllers();
      expect(mem.getController(10), isFalse);
    });

    test('supports custom symbol aliases with fallback to default descriptions', () {
      final mem = AgiMemory();

      expect(mem.getVarDisplayName(0), contains('Current room'));
      mem.setVarAlias(0, 'current_room_id');
      expect(mem.getVarDisplayName(0), 'current_room_id');

      expect(mem.getFlagDisplayName(5), contains('New room executed'));
      mem.setFlagAlias(5, 'f_new_room');
      expect(mem.getFlagDisplayName(5), 'f_new_room');
    });
  });
}
