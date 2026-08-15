import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/dialog_box_widget.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';

void main() {
  group('GameScreen & UI Widgets', () {
    late AgiGameEngine engine;

    setUp(() {
      engine = AgiGameEngine(speedHz: 20.0);
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('renders status bar, playfield, and command prompt', (tester) async {
      engine.memory.setVar(3, 15); // Score = 15
      engine.memory.setVar(7, 100); // Max Score = 100

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // Verify Status Bar
      expect(find.text('Score: 15 of 100'), findsOneWidget);
      expect(find.text('Sound: ON'), findsOneWidget);

      // Verify Playfield Widget
      expect(find.byType(GamePlayfieldWidget), findsOneWidget);

      // Verify Command Prompt Input
      expect(find.text('> '), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('submits command on prompt submit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'look at tree');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(engine.lastSubmittedCommand, 'look at tree');
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1
    });

    testWidgets('displays modal dialog box on onPrint and dismisses on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // No dialog initially
      expect(find.byType(DialogBoxWidget), findsNothing);

      // Trigger print dialog
      engine.onPrint('Welcome to the Sierra Adventure!');
      await tester.pump();

      // Verify dialog is displayed with message
      expect(find.byType(DialogBoxWidget), findsOneWidget);
      expect(find.text('Welcome to the Sierra Adventure!'), findsOneWidget);
      expect(find.text('SIERRA AGI MESSAGE'), findsOneWidget);

      // Dismiss dialog via OK button
      final okButton = find.widgetWithText(ElevatedButton, 'OK');
      expect(okButton, findsOneWidget);
      await tester.tap(okButton);
      await tester.pump();

      // Verify dialog is removed
      expect(find.byType(DialogBoxWidget), findsNothing);
      expect(engine.activeDialog, isNull);
    });

    testWidgets('toggles sound on status bar tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      expect(engine.memory.getFlag(9), isTrue);
      expect(find.text('Sound: ON'), findsOneWidget);

      // Tap sound toggle in status bar
      final soundToggle = find.text('Sound: ON');
      await tester.tap(soundToggle);
      await tester.pump();

      expect(engine.memory.getFlag(9), isFalse);
      expect(find.text('Sound: OFF'), findsOneWidget);
    });
  });
}
