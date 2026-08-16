import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
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

    testWidgets('renders left sidebar, playfield, and command prompt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // Verify Left Sidebar workbench tools
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

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

    testWidgets('toggles sound on sidebar button tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      expect(engine.memory.getFlag(9), isTrue);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Tap sound toggle in left sidebar
      final soundToggle = find.byIcon(Icons.volume_up);
      await tester.tap(soundToggle);
      await tester.pump();

      expect(engine.memory.getFlag(9), isFalse);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('switches render modes in game toolbar and loads textures', (tester) async {
      final visualPixels = Uint8List(160 * 168);
      final priorityBuffer = PriorityBuffer();
      final slices = <int, PictureSlice>{
        15: PictureSlice(
          priority: 15,
          width: 320,
          height: 200,
          rgbaBytes: Uint8List(320 * 200 * 4),
          hasVisiblePixels: true,
        ),
      };
      final pic = AgiPic(
        visualPixels: visualPixels,
        priorityBuffer: priorityBuffer,
        slices: slices,
      );
      engine.currentPic = pic;

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pumpAndSettle();

      // Open Render Mode popup menu
      expect(find.byIcon(Icons.layers), findsOneWidget);
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();

      // Select Priority Depth Map
      expect(find.text('Priority Depth Map'), findsOneWidget);
      await tester.tap(find.text('Priority Depth Map'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedPriorityMapImage, isNotNull);

      // Open Render Mode popup menu again
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();

      // Select Control Barrier Map
      expect(find.text('Control Barrier Map'), findsOneWidget);
      await tester.tap(find.text('Control Barrier Map'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedControlMapImage, isNotNull);

      // Open Render Mode popup menu again
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();

      // Select Flat Visual Background
      expect(find.text('Flat Visual Background'), findsOneWidget);
      await tester.tap(find.text('Flat Visual Background'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedFlatVisualImage, isNotNull);
    });

    testWidgets('routes keyboard typing to prompt automatically while arrow keys move Ego', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      expect(engine.ego.direction, 0);

      // Type 'open door' via keyboard events without clicking into TextField
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP, character: 'p');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE, character: 'e');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
      await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD, character: 'd');
      await tester.pump();

      expect(find.text('open d'), findsOneWidget);

      // Press Arrow Right (3) while typing -> moves Ego without clearing text
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(engine.ego.direction, 3);
      expect(find.text('open d'), findsOneWidget);

      // Press Arrow Right (3) again -> stops Ego (0)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(engine.ego.direction, 0);
      expect(find.text('open d'), findsOneWidget);

      // Backspace removes character
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('open '), findsOneWidget);

      // Escape clears prompt
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('open '), findsNothing);

      // Type and submit with Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL, character: 'l');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(engine.lastSubmittedCommand, 'look');
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1
    });

    testWidgets('maintains constant input bar height and stable playfield layout when input is disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      final playfieldFinder = find.byType(GamePlayfieldWidget);
      expect(playfieldFinder, findsOneWidget);
      final initialPlayfieldSize = tester.getSize(playfieldFinder);

      // Input is enabled initially
      expect(find.text('Type a command (e.g. look around)...'), findsOneWidget);

      // Script disables input (e.g. prevent.input)
      engine.isInputEnabled = false;
      await tester.pump();

      // Input bar remains present in disabled state
      expect(find.text('[INPUT DISABLED]'), findsOneWidget);

      // Playfield size remains identical (no jumping or resizing)
      final disabledPlayfieldSize = tester.getSize(playfieldFinder);
      expect(disabledPlayfieldSize.height, initialPlayfieldSize.height);
      expect(disabledPlayfieldSize.width, initialPlayfieldSize.width);

      // Script re-enables input
      engine.isInputEnabled = true;
      await tester.pump();

      expect(find.text('Type a command (e.g. look around)...'), findsOneWidget);
      final reenabledPlayfieldSize = tester.getSize(playfieldFinder);
      expect(reenabledPlayfieldSize.height, initialPlayfieldSize.height);
      expect(reenabledPlayfieldSize.width, initialPlayfieldSize.width);
    });
  });
}
