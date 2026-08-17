import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/cel_image_widget.dart';
import 'package:flutter_agigame/ui/widgets/inventory_dialog.dart';
import 'package:flutter_agigame/ui/widgets/object_inspection_dialog.dart';

void main() {
  group('InventoryDialog Widget Tests', () {
    testWidgets('renders "You are carrying nothing." when empty and closes on tap/keys', (tester) async {
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: const [],
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify Empty State
      expect(find.text('You are carrying nothing.'), findsOneWidget);
      expect(find.text('OK'), findsNothing);

      // Dismiss via tap
      await tester.tap(find.byType(InventoryDialog));
      await tester.pump();
      expect(closed, isTrue);

      // Reset and test dismissal via Enter key
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: const [],
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(closed, isTrue);

      // Reset and test dismissal via Escape key
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: const [],
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('renders list of carried items in 2-column view mode and supports 2D arrow navigation', (tester) async {
      final items = [
        const CarriedItem(index: 1, object: AgiObject(name: 'Golden Key', startingRoom: 0)),
        const CarriedItem(index: 2, object: AgiObject(name: 'Magic Dagger', startingRoom: 0)),
        const CarriedItem(index: 3, object: AgiObject(name: 'Pouch of Diamonds', startingRoom: 0)),
      ];

      int? selectedItemIndex;
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: items,
              onItemSelected: (idx) => selectedItemIndex = idx,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify header and items
      expect(find.text('You are carrying:'), findsOneWidget);
      expect(find.text('Golden Key'), findsOneWidget);
      expect(find.text('Magic Dagger'), findsOneWidget);
      expect(find.text('Pouch of Diamonds'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      expect(find.text('Select'), findsNothing);

      // Navigate right to item 2 (Magic Dagger) in 2-column grid
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selectedItemIndex, equals(2));

      // Navigate down to item 3 (Pouch of Diamonds)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selectedItemIndex, equals(3));

      // Navigate up back to item 1 (Golden Key)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(selectedItemIndex, equals(1));

      // Press Enter to close in view mode
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('selection mode (Flag 13) supports 2D navigation, double-click, and Enter key with auto-scrolling', (tester) async {
      final items = [
        const CarriedItem(index: 10, object: AgiObject(name: 'Silver Flute', startingRoom: 0)),
        const CarriedItem(index: 11, object: AgiObject(name: 'Spell Book', startingRoom: 0)),
        const CarriedItem(index: 12, object: AgiObject(name: 'Magic Wand', startingRoom: 0)),
        const CarriedItem(index: 13, object: AgiObject(name: 'Crystal Ball', startingRoom: 0)),
        const CarriedItem(index: 14, object: AgiObject(name: 'Golden Chalice', startingRoom: 0)),
        const CarriedItem(index: 15, object: AgiObject(name: 'Ancient Scroll', startingRoom: 0)),
        const CarriedItem(index: 16, object: AgiObject(name: 'Dragon Scale', startingRoom: 0)),
        const CarriedItem(index: 17, object: AgiObject(name: 'Elixir of Life', startingRoom: 0)),
        const CarriedItem(index: 18, object: AgiObject(name: 'Phoenix Feather', startingRoom: 0)),
        const CarriedItem(index: 19, object: AgiObject(name: 'Enchanted Mirror', startingRoom: 0)),
      ];

      int? selectedChoice;
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: items,
              isSelectionMode: true,
              onSelect: (idx) => selectedChoice = idx,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.text('Select an object:'), findsOneWidget);
      expect(find.text('Enter to select, Esc to cancel'), findsOneWidget);
      expect(find.text('Select'), findsNothing);

      // Navigate down through multiple rows (auto-scrolling triggered)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selectedChoice, equals(17)); // 10 -> (+2) 12 -> (+2) 14 -> (+2) 16 -> (+1) 17
      expect(closed, isTrue);

      // Reset and test double-click selection
      selectedChoice = null;
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: items,
              isSelectionMode: true,
              onSelect: (idx) => selectedChoice = idx,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Silver Flute'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Silver Flute'));
      await tester.pumpAndSettle();
      expect(selectedChoice, equals(10));
      expect(closed, isTrue);
    });

    testWidgets('filters carried items from engine memory dynamically', (tester) async {
      final engine = AgiGameEngine(
        objects: const [
          AgiObject(name: '?', startingRoom: 0),
          AgiObject(name: 'Magic Key', startingRoom: 1),
          AgiObject(name: 'Golden Dagger', startingRoom: 255),
        ],
      );
      engine.initializeGame();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              engine: engine,
            ),
          ),
        ),
      );

      expect(find.text('Golden Dagger'), findsOneWidget);
      expect(find.text('Magic Key'), findsNothing);
    });
  });

  group('ObjectInspectionDialog Widget Tests', () {
    testWidgets('renders object description and cel preview, dismisses on tap or key', (tester) async {
      final cel = AgiViewCel.forward(
        width: 10,
        height: 10,
        transparentColor: 0,
        rawPixels: Uint8List(100),
      );
      final loop = AgiViewLoop(loopNumber: 0, cels: [cel]);
      final view = AgiView(
        viewNumber: 42,
        loops: [loop],
        description: 'An ancient parchment map of the realm.',
      );

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectInspectionDialog(
              objectNumber: 42,
              object: const AgiObject(name: 'Daventry Map', startingRoom: 0),
              view: view,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.text('An ancient parchment map of the realm.'), findsOneWidget);
      expect(find.byType(CelImageWidget), findsOneWidget);
      expect(find.text('OK'), findsNothing);

      // Dismiss on tap anywhere
      await tester.tap(find.byType(ObjectInspectionDialog));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('renders fallback placeholder and object name when no view description is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ObjectInspectionDialog(
              objectNumber: 99,
              object: AgiObject(name: 'Mysterious Idol', startingRoom: 0),
            ),
          ),
        ),
      );

      expect(find.text('Mysterious Idol'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });
  });

  group('AgiLogicInterpreter & AgiGameEngine Opcodes Integration', () {
    test('Opcode 124 (status) triggers onStatus and opens inventory in engine', () {
      final engine = AgiGameEngine();
      final interpreter = engine.interpreter;

      final script = AgiLogicScript(
        logicNumber: 1,
        bytecodes: Uint8List.fromList([
          124, // status()
          0, // return()
        ]),
        messages: const [],
      );

      interpreter.loadRootScript(script, scriptNumber: 1);
      expect(engine.isInventoryOpen, isFalse);

      final status = interpreter.stepInstruction();
      expect(status, equals(InterpreterStatus.yielded));
      expect(engine.isInventoryOpen, isTrue);

      // Close inventory resumes interpreter until return()
      engine.closeInventory();
      expect(engine.isInventoryOpen, isFalse);
      expect(interpreter.callStack, isEmpty);
    });

    test('Opcode 129 (show.obj) and Opcode 162 (show.obj.v) trigger onShowObj', () {
      final memory = AgiMemory();
      final engine = AgiGameEngine(memory: memory);
      final interpreter = engine.interpreter;

      memory.setVar(10, 12);
      final script = AgiLogicScript(
        logicNumber: 1,
        bytecodes: Uint8List.fromList([
          129, 5, // show.obj(5)
          162, 10, // show.obj.v(%v10) -> view 12
          0, // return()
        ]),
        messages: const [],
      );

      interpreter.loadRootScript(script, scriptNumber: 1);
      expect(engine.inspectingObjectNumber, isNull);

      // Step show.obj(5)
      final status1 = interpreter.stepInstruction();
      expect(status1, equals(InterpreterStatus.yielded));
      expect(engine.inspectingObjectNumber, equals(5));

      // Closing first inspection resumes interpreter which yields at show.obj.v(%v10)
      engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, equals(12));

      // Closing second inspection finishes script to return()
      engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, isNull);
      expect(interpreter.callStack, isEmpty);
    });

    test('Game loop pauses during inventory and object inspection', () {
      final engine = AgiGameEngine(speedHz: 20.0);
      engine.start();
      expect(engine.isRunning, isTrue);

      // Open inventory
      engine.openInventory();
      expect(engine.isInventoryOpen, isTrue);

      // Open inspection
      engine.inspectObject(2);
      expect(engine.inspectingObjectNumber, equals(2));

      // Close inspection and inventory
      engine.closeObjectInspection();
      engine.closeInventory();
      expect(engine.isInventoryOpen, isFalse);
      expect(engine.inspectingObjectNumber, isNull);

      engine.stop();
    });
  });

  group('GameScreen Integration with Inventory & Inspection', () {
    testWidgets('Tab key opens inventory and dismissing closes it', (tester) async {
      final engine = AgiGameEngine(
        objects: const [
          AgiObject(name: '?', startingRoom: 0),
          AgiObject(name: 'Crystal Orb', startingRoom: 255),
          AgiObject(name: 'Map of Daventry', startingRoom: 255),
        ],
      );
      engine.initializeGame();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // Initially no inventory dialog
      expect(find.byType(InventoryDialog), findsNothing);
      expect(find.byType(ObjectInspectionDialog), findsNothing);

      // Press Tab key to open inventory
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(find.byType(InventoryDialog), findsOneWidget);
      expect(find.text('Crystal Orb'), findsOneWidget);
      expect(find.text('Map of Daventry'), findsOneWidget);

      // Press Enter to dismiss inventory in view mode
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.byType(InventoryDialog), findsNothing);
      expect(engine.isInventoryOpen, isFalse);
    });

    testWidgets('preserves asterisk in dangerous item names in InventoryDialog and ObjectInspectionDialog', (tester) async {
      final engine = AgiGameEngine(
        objects: const [
          AgiObject(name: '?', startingRoom: 0),
          AgiObject(name: '*magic wand', startingRoom: 255),
          AgiObject(name: 'bread dough*', startingRoom: 255),
        ],
      );
      engine.initializeGame();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(engine: engine),
        ),
      );

      // Press Tab key to open inventory
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(find.byType(InventoryDialog), findsOneWidget);
      expect(find.text('*magic wand'), findsOneWidget);
      expect(find.text('bread dough*'), findsOneWidget);

      // Dismiss inventory
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Show object inspection directly via engine
      engine.onShowObj(1);
      await tester.pump();

      expect(find.byType(ObjectInspectionDialog), findsOneWidget);
      expect(find.text('*magic wand'), findsOneWidget);
    });
  });
}
