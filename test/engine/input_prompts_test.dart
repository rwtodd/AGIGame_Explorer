import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/input_prompt_dialog.dart';

void main() {
  group('AgiGameEngine Input Prompts & Delegations (Unit Tests)', () {
    late AgiMemory memory;
    late AgiGameEngine engine;

    setUp(() {
      memory = AgiMemory();
      engine = AgiGameEngine(memory: memory);
    });

    tearDown(() {
      engine.dispose();
    });

    test('onGetString creates activeInputPrompt and completes future on submit', () async {
      expect(engine.activeInputPrompt, isNull);

      final future = engine.onGetString('Enter your name:', 10, 5, 20);

      expect(engine.activeInputPrompt, isNotNull);
      expect(engine.activeInputPrompt!.type, equals(AgiInputPromptType.string));
      expect(engine.activeInputPrompt!.prompt, equals('Enter your name:'));
      expect(engine.activeInputPrompt!.row, equals(10));
      expect(engine.activeInputPrompt!.col, equals(5));
      expect(engine.activeInputPrompt!.maxLen, equals(20));

      engine.submitInputPrompt('Princess Rosella');
      final result = await future;

      expect(result, equals('Princess Rosella'));
      expect(engine.activeInputPrompt, isNull);
    });

    test('onGetString clamps submitted text to maxLen', () async {
      final future = engine.onGetString('Password (max 4 chars):', 0, 0, 4);

      engine.submitInputPrompt('ABCDEFG');
      final result = await future;

      expect(result, equals('ABCD'));
      expect(engine.activeInputPrompt, isNull);
    });

    test('onGetString completes with null on cancelInputPrompt', () async {
      final future = engine.onGetString('Enter code:', 0, 0, 10);

      expect(engine.activeInputPrompt, isNotNull);
      engine.cancelInputPrompt();

      final result = await future;
      expect(result, isNull);
      expect(engine.activeInputPrompt, isNull);
    });

    test('onGetNum creates numeric activeInputPrompt and completes with integer on submit', () async {
      final future = engine.onGetNum('Place your bet:');

      expect(engine.activeInputPrompt, isNotNull);
      expect(engine.activeInputPrompt!.type, equals(AgiInputPromptType.number));
      expect(engine.activeInputPrompt!.prompt, equals('Place your bet:'));

      engine.submitInputPrompt('50');
      final result = await future;

      expect(result, equals(50));
      expect(engine.activeInputPrompt, isNull);
    });

    test('onGetNum clamps numeric values to 0 - 255', () async {
      final future1 = engine.onGetNum('Large number:');
      engine.submitInputPrompt('1000');
      expect(await future1, equals(255));

      final future2 = engine.onGetNum('Negative number:');
      engine.submitInputPrompt('-50');
      expect(await future2, equals(0));

      final future3 = engine.onGetNum('Invalid string:');
      engine.submitInputPrompt('not_a_number');
      expect(await future3, equals(0));
    });

    test('onGetNum completes with null on cancelInputPrompt', () async {
      final future = engine.onGetNum('Enter magic code:');

      engine.cancelInputPrompt();
      final result = await future;

      expect(result, isNull);
      expect(engine.activeInputPrompt, isNull);
    });

    test('onParse tokenizes string and updates said matcher inputs and memory flags', () {
      final dict = AgiDictionary();
      dict.addWord('look', 10);
      dict.addWord('mirror', 100);

      final customEngine = AgiGameEngine(memory: memory, dictionary: dict);

      // Submit command through onParse
      customEngine.onParse('look mirror');

      expect(customEngine.memory.getFlag(2), isTrue); // have.input = 1
      expect(customEngine.memory.getFlag(4), isFalse); // said.accepted = 0
      expect(customEngine.checkSaid([10, 100]), isTrue);
      expect(customEngine.memory.getFlag(4), isTrue); // said.accepted = 1

      customEngine.dispose();
    });

    test('wordToString resolves primary word from engine dictionary', () {
      final dict = AgiDictionary();
      dict.addWord('open', 30);
      dict.addWord('unlock', 30); // synonym

      final customEngine = AgiGameEngine(dictionary: dict);
      expect(customEngine.wordToString(30), equals('open'));
      expect(customEngine.wordToString(999), isNull);

      customEngine.dispose();
    });

    test('getView returns null when resourceLoader is absent', () {
      expect(engine.getView(1), isNull);
    });

    test('formatMessage expands placeholders inside prompts', () {
      memory.setVar(5, 42);
      memory.setString(1, 'Gwydion');

      engine.onGetString('Hello %s1, your score is %v5.', 0, 0, 30);
      expect(engine.activeInputPrompt!.prompt, equals('Hello Gwydion, your score is 42.'));

      engine.cancelInputPrompt();
    });
  });

  group('InputPromptDialog Widget Tests', () {
    testWidgets('renders string prompt dialog with message, input field, and buttons', (WidgetTester tester) async {
      String? submittedValue;
      bool cancelled = false;

      final promptState = AgiInputPromptState(
        type: AgiInputPromptType.string,
        prompt: 'What is your quest?',
        maxLen: 30,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputPromptDialog(
              promptState: promptState,
              onSubmit: (val) => submittedValue = val,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      // Verify UI structure
      expect(find.text('SIERRA AGI INPUT PROMPT'), findsOneWidget);
      expect(find.text('What is your quest?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Submit (Enter)'), findsOneWidget);
      expect(find.text('Cancel (Esc)'), findsOneWidget);

      // Enter text
      await tester.enterText(find.byType(TextField), 'To seek the Holy Grail');
      await tester.pump();

      // Tap Submit button
      await tester.tap(find.text('Submit (Enter)'));
      await tester.pump();

      expect(submittedValue, equals('To seek the Holy Grail'));
      expect(cancelled, isFalse);
    });

    testWidgets('submits text when Enter key is pressed in TextField', (WidgetTester tester) async {
      String? submittedValue;

      final promptState = AgiInputPromptState(
        type: AgiInputPromptType.string,
        prompt: 'Enter character name:',
        maxLen: 15,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputPromptDialog(
              promptState: promptState,
              onSubmit: (val) => submittedValue = val,
              onCancel: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Larry Laffer');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedValue, equals('Larry Laffer'));
    });

    testWidgets('cancels dialog when Cancel button is tapped', (WidgetTester tester) async {
      bool cancelled = false;

      final promptState = AgiInputPromptState(
        type: AgiInputPromptType.string,
        prompt: 'Secret code:',
        maxLen: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputPromptDialog(
              promptState: promptState,
              onSubmit: (_) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Cancel (Esc)'));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('cancels dialog when Escape key is pressed', (WidgetTester tester) async {
      bool cancelled = false;

      final promptState = AgiInputPromptState(
        type: AgiInputPromptType.string,
        prompt: 'Password:',
        maxLen: 10,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputPromptDialog(
              promptState: promptState,
              onSubmit: (_) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('renders numeric prompt dialog with numeric header and hint', (WidgetTester tester) async {
      String? submittedValue;

      final promptState = AgiInputPromptState(
        type: AgiInputPromptType.number,
        prompt: 'How much gold to bet?',
        maxLen: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputPromptDialog(
              promptState: promptState,
              onSubmit: (val) => submittedValue = val,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('SIERRA AGI NUMERIC INPUT'), findsOneWidget);
      expect(find.text('How much gold to bet?'), findsOneWidget);
      expect(find.text('Enter number (0 - 255)...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '200');
      await tester.tap(find.text('Submit (Enter)'));
      await tester.pump();

      expect(submittedValue, equals('200'));
    });
  });
}
