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

    test('handles 8-bit variable mutation, overflow, and underflow', () {
      final mem = AgiMemory();

      mem.setVar(10, 250);
      expect(mem.getVar(10), 250);

      // Increment to 255
      for (var i = 0; i < 5; i++) {
        mem.incrementVar(10);
      }
      expect(mem.getVar(10), 255);

      // Overflow wrap to 0
      mem.incrementVar(10);
      expect(mem.getVar(10), 0);

      // Underflow wrap to 255
      mem.decrementVar(10);
      expect(mem.getVar(10), 255);

      // Clamping on direct set
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
