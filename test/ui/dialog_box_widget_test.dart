import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/dialog_box_widget.dart';

void main() {
  group('DialogBoxWidget', () {
    testWidgets('renders centered modal dialog when row and col are null', (tester) async {
      bool dismissed = false;
      final dialogState = AgiDialogState(
        message: 'This is a centered message.',
        isModal: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 480,
                child: DialogBoxWidget(
                  dialogState: dialogState,
                  onDismiss: () => dismissed = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('This is a centered message.'), findsOneWidget);
      expect(find.byType(Center), findsWidgets);

      // Tap to dismiss
      await tester.tap(find.byType(DialogBoxWidget));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('renders positional dialog at specified row and col', (tester) async {
      bool dismissed = false;
      final dialogState = AgiDialogState(
        message: 'Graham speaks from above.',
        row: 3,
        col: 5,
        width: 25,
        isModal: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DialogBoxWidget(
                dialogState: dialogState,
                onDismiss: () => dismissed = true,
                correctAspectRatio: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Graham speaks from above.'), findsOneWidget);
      expect(find.byType(Positioned), findsWidgets);

      // Verify positioned coordinates
      final positionedFinder = find.byWidgetPredicate(
        (widget) => widget is Positioned && widget.top != null && widget.left != null,
      );
      expect(positionedFinder, findsOneWidget);

      final positioned = tester.widget<Positioned>(positionedFinder);
      expect(positioned.top, greaterThan(0));
      expect(positioned.left, greaterThan(0));

      // Dismiss via Space key
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('dismisses on Escape key and numpad enter', (tester) async {
      bool dismissed = false;
      final dialogState = AgiDialogState(
        message: 'Press ESC to cancel',
        isModal: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogBoxWidget(
              dialogState: dialogState,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('non-modal dialog does not dismiss on tap', (tester) async {
      bool dismissed = false;
      final dialogState = AgiDialogState(
        message: 'Background information window',
        row: 18,
        col: 2,
        isModal: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogBoxWidget(
              dialogState: dialogState,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DialogBoxWidget));
      await tester.pump();
      expect(dismissed, isFalse);
    });

    testWidgets('handles very small custom width without constraint error', (tester) async {
      final dialogState = AgiDialogState(
        message: 'Small prompt',
        row: 5,
        col: 5,
        width: 8, // Very small width from script
        isModal: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: DialogBoxWidget(
                dialogState: dialogState,
                onDismiss: () {},
                correctAspectRatio: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Small prompt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
