import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

void main() {
  group('Dialog Cleanup on Room Transitions', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0);
    });

    tearDown(() {
      engine.dispose();
    });

    test('changeRoom clears active non-modal dialog (flag 15 print.at / LEAVE_WIN)', () async {
      // Simulate showing a non-modal dialog like Room 141's question
      engine.onPrintAt('On page 2, what is the fourth word?', 5, 5, 30, isModal: false);

      expect(engine.activeDialog, isNotNull);
      expect(engine.activeDialog!.isModal, isFalse);
      expect(engine.activeDialog!.message, contains('what is the fourth word'));

      // Transition to room 96
      engine.changeRoom(96);

      // Dialog should now be cleared
      expect(engine.activeDialog, isNull);
      expect(engine.memory.getVar(0), 96);
    });

    test('changeRoom clears active modal dialog', () async {
      // Simulate showing a modal dialog
      engine.onPrint('Welcome to the kingdom!', isModal: true);

      expect(engine.activeDialog, isNotNull);
      expect(engine.activeDialog!.isModal, isTrue);

      // Transition to room 2
      engine.changeRoom(2);

      // Dialog should now be cleared
      expect(engine.activeDialog, isNull);
      expect(engine.memory.getVar(0), 2);
    });
  });
}
