import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgiGameEngine.formatMessage', () {
    test('strips backslash escape before pipe and special characters', () {
      final engine = AgiGameEngine();

      expect(
        engine.formatMessage(r' DOPE IN THE CITY  \| PRESIDENT HICKLE'),
        equals(' DOPE IN THE CITY  | PRESIDENT HICKLE'),
      );
      expect(
        engine.formatMessage(r'The city of Lytton,\|'),
        equals('The city of Lytton,|'),
      );
      expect(
        engine.formatMessage(r'Escaped \\ and \%v1'),
        equals(r'Escaped \ and %v1'),
      );
    });

    test('replaces %v variable placeholders with and without padding', () {
      final engine = AgiGameEngine();
      engine.memory.setVar(6, 42);
      engine.memory.setVar(14, 7);

      expect(engine.formatMessage('Score: %v6'), equals('Score: 42'));
      expect(engine.formatMessage('Padded: %v14|3'), equals('Padded: 007'));
      expect(engine.formatMessage('Zero: %v10|2'), equals('Zero: 00'));
    });

    test('replaces %s string placeholders', () {
      final engine = AgiGameEngine();
      engine.memory.setString(1, 'Hero');

      expect(engine.formatMessage('Hello %s1!'), equals('Hello Hero!'));
    });
  });

  group('Police Quest 1 Room 116', () {
    test('renders newspaper text and photo object correctly', () {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/police-quest-1');
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.onNewRoom(116);
      engine.tick();

      // Verify newspaper headlines and text formatting (no backslashes)
      final line5 = engine.displayedTexts.firstWhere((t) => t.row == 5 && t.col == 1);
      expect(line5.message, equals(' DOPE IN THE CITY  | PRESIDENT HICKLE'));

      final line7 = engine.displayedTexts.firstWhere((t) => t.row == 7 && t.col == 1);
      expect(line7.message, equals('The city of Lytton,|'));

      // Verify photo object (Obj 1 with View 96) is drawn and positioned
      final photoObj = engine.animatedObjects[1];
      expect(photoObj.isDrawn, isTrue);
      expect(photoObj.view, equals(96));
      expect(photoObj.cel, equals(0));
      expect(photoObj.x, equals(93));
      expect(photoObj.y, equals(91));
    });
  });
}
