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
      expect(find.byIcon(Icons.volume_down), findsOneWidget);

      // Verify Playfield Widget with integrated prompt
      expect(find.byType(GamePlayfieldWidget), findsOneWidget);
      expect(find.text('> '), findsOneWidget);
    });

    testWidgets('submits command on prompt submit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      // Type 'look at tree' and press Enter
      for (final char in 'look at tree'.split('')) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey.space,
          character: char,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
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

      // Dismiss dialog via tap
      await tester.tap(find.byType(DialogBoxWidget));
      await tester.pump();

      // Verify dialog is removed
      expect(find.byType(DialogBoxWidget), findsNothing);
      expect(engine.activeDialog, isNull);
    });

    testWidgets('displays positional dialog box on onPrintAt and dismisses on Enter key', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // Trigger print.at dialog with row=4, col=10, width=25
      engine.onPrintAt('Watch out for the dragon!', 4, 10, 25);
      await tester.pump();

      // Verify dialog is displayed with row and col preserved
      expect(find.byType(DialogBoxWidget), findsOneWidget);
      expect(find.text('Watch out for the dragon!'), findsOneWidget);
      expect(engine.activeDialog?.row, 4);
      expect(engine.activeDialog?.col, 10);
      expect(engine.activeDialog?.width, 25);

      // Dismiss dialog via Enter key
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Verify dialog is removed
      expect(find.byType(DialogBoxWidget), findsNothing);
      expect(engine.activeDialog, isNull);
    });

    testWidgets('opens slideout audio options panel and changes sound modes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      expect(engine.isSoundOn, isTrue);
      expect(find.byIcon(Icons.volume_down), findsOneWidget);

      // Tap sound button in left sidebar to open slide-out panel
      final soundButton = find.byIcon(Icons.volume_down);
      await tester.tap(soundButton);
      await tester.pumpAndSettle();

      // Verify Audio Options panel is open
      expect(find.text('AUDIO OPTIONS'), findsOneWidget);
      expect(find.text('Sound Off'), findsOneWidget);
      expect(find.text('IBM PC Speaker'), findsOneWidget);
      expect(find.text('PCjr / Tandy 3-Voice'), findsOneWidget);
      expect(find.text('Enhanced Mode'), findsOneWidget);

      // Switch to Enhanced Mode
      await tester.tap(find.text('Enhanced Mode'));
      await tester.pumpAndSettle();

      expect(engine.soundMode, equals(AgiSoundMode.enhanced));
      expect(find.text('ENHANCED WAVEFORM'), findsOneWidget);
      expect(find.text('DSP ROOM REVERB'), findsOneWidget);
      expect(find.text('Square'), findsOneWidget);
      expect(find.text('Sawtooth'), findsOneWidget);
      expect(find.text('PWM'), findsOneWidget);

      // Select Sawtooth waveform
      await tester.tap(find.text('Sawtooth'));
      await tester.pumpAndSettle();
      expect(engine.synthesizerConfig.waveform.name, equals('sawtooth'));

      // Switch to IBM PC Speaker
      await tester.tap(find.text('IBM PC Speaker'));
      await tester.pumpAndSettle();

      expect(engine.soundMode, equals(AgiSoundMode.ibmPc));
      expect(engine.memory.getVar(22), equals(1)); // %v22 = 1 voice

      // Switch to Sound Off
      await tester.tap(find.text('Sound Off'));
      await tester.pumpAndSettle();

      expect(engine.soundMode, equals(AgiSoundMode.off));
      expect(engine.memory.getFlag(9), isFalse); // %f9 = 0

      // Close panel
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('AUDIO OPTIONS'), findsNothing);
    });

    testWidgets('switches render modes and video options in slideout panel and loads textures', (tester) async {
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

      // Open Video Options panel via sidebar tv icon
      expect(find.byIcon(Icons.tv), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tv));
      await tester.pumpAndSettle();

      // Verify Video Options panel elements
      expect(find.text('VIDEO & DISPLAY'), findsOneWidget);
      expect(find.text('4:3 CRT Aspect Correction'), findsOneWidget);
      expect(find.text('Strict Integer Scaling'), findsOneWidget);
      expect(find.text('CRT Scanline Shader'), findsOneWidget);
      expect(find.text('Pixel Grid Overlay'), findsOneWidget);

      // Select Priority Depth Buffer mode
      expect(find.text('Priority Depth Buffer'), findsOneWidget);
      await tester.ensureVisible(find.text('Priority Depth Buffer'));
      await tester.tap(find.text('Priority Depth Buffer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedPriorityMapImage, isNotNull);

      // Select Control Screen
      expect(find.text('Control Screen'), findsOneWidget);
      await tester.ensureVisible(find.text('Control Screen'));
      await tester.tap(find.text('Control Screen'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedControlMapImage, isNotNull);

      // Select Flat Visual Background
      expect(find.text('Flat Visual Background'), findsOneWidget);
      await tester.ensureVisible(find.text('Flat Visual Background'));
      await tester.tap(find.text('Flat Visual Background'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(pic.cachedFlatVisualImage, isNotNull);

      // Toggle Strict Integer Scaling
      await tester.ensureVisible(find.text('Strict Integer Scaling'));
      await tester.tap(find.text('Strict Integer Scaling'));
      await tester.pumpAndSettle();

      // Toggle 4:3 Aspect Correction
      await tester.ensureVisible(find.text('4:3 CRT Aspect Correction'));
      await tester.tap(find.text('4:3 CRT Aspect Correction'));
      await tester.pumpAndSettle();
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

    testWidgets('shows integrated prompt when enabled and hides cleanly when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      final playfieldFinder = find.byType(GamePlayfieldWidget);
      expect(playfieldFinder, findsOneWidget);
      final initialPlayfieldSize = tester.getSize(playfieldFinder);

      // Input is enabled initially -> prompt visible
      expect(find.text('> '), findsOneWidget);

      // Script disables input (e.g. prevent.input)
      engine.isInputEnabled = false;
      await tester.pump();

      // Integrated prompt is cleanly hidden
      expect(find.text('> '), findsNothing);

      // Playfield size remains identical (no jumping or resizing)
      final disabledPlayfieldSize = tester.getSize(playfieldFinder);
      expect(disabledPlayfieldSize.height, initialPlayfieldSize.height);
      expect(disabledPlayfieldSize.width, initialPlayfieldSize.width);

      // Script re-enables input (e.g. accept.input)
      engine.isInputEnabled = true;
      await tester.pump();

      // Integrated prompt reappears
      expect(find.text('> '), findsOneWidget);
      final reenabledPlayfieldSize = tester.getSize(playfieldFinder);
      expect(reenabledPlayfieldSize.height, initialPlayfieldSize.height);
      expect(reenabledPlayfieldSize.width, initialPlayfieldSize.width);
    });

    testWidgets('sidebar restore button replays the last manual checkpoint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.backpack_outlined), findsNothing);
      expect(find.byIcon(Icons.restore), findsOneWidget);

      engine.ego.x = 22;
      engine.recordCheckpoint(label: 'Retry point');
      engine.ego.x = 77;
      await tester.pump();

      await tester.tap(find.byIcon(Icons.restore));
      await tester.pump();

      expect(engine.ego.x, 22);
      expect(find.textContaining('Restored: Retry point'), findsOneWidget);
    });

    testWidgets('custom controller key bindings (like = for swim) trigger controller and do not appear in command prompt', (tester) async {
      // Register = (ascii 61) -> Controller 22 (Swim)
      engine.controllerManager.setKey(0, 61, 22);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      expect(engine.memory.getController(22), isFalse);

      // Press '=' key
      await tester.sendKeyEvent(LogicalKeyboardKey.equal, character: '=');
      await tester.pump();

      // Controller 22 must be triggered
      expect(engine.memory.getController(22), isTrue, reason: 'Controller 22 should be active after pressing =');

      // Command prompt must NOT contain '='
      expect(find.text('='), findsNothing);
      expect(find.text('> '), findsOneWidget);

      // Normal typing still works as expected
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
      await tester.pump();

      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('typing !tp <room> teleports Ego directly to room', (tester) async {
      engine.changeRoom(2);
      expect(engine.currentRoom, 2);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );
      await tester.pump();

      for (final char in '!tp 65'.split('')) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey.space,
          character: char,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(engine.currentRoom, 65);
      expect(find.textContaining('Teleported to Room 65'), findsOneWidget);
    });
  });
}
