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

      // Verify Header and Empty State
      expect(find.text('YOU ARE CARRYING'), findsOneWidget);
      expect(find.text('You are carrying nothing.'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Dismiss via OK button
      await tester.tap(find.text('OK'));
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

    testWidgets('renders list of carried items and navigates with arrow keys', (tester) async {
      final items = [
        const CarriedItem(index: 1, object: AgiObject(name: 'Golden Key', startingRoom: 0)),
        const CarriedItem(index: 2, object: AgiObject(name: 'Magic Dagger', startingRoom: 0)),
        const CarriedItem(index: 3, object: AgiObject(name: 'Pouch of Diamonds', startingRoom: 0)),
      ];

      int? selectedItemIndex;
      int? inspectedItemIndex;
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: items,
              onItemSelected: (idx) => selectedItemIndex = idx,
              onInspect: (idx) => inspectedItemIndex = idx,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify header and items
      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('Golden Key'), findsOneWidget);
      expect(find.text('Magic Dagger'), findsOneWidget);
      expect(find.text('Pouch of Diamonds'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      // Navigate down to item 2 (Magic Dagger)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selectedItemIndex, equals(2));

      // Navigate down to item 3 (Pouch of Diamonds)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selectedItemIndex, equals(3));

      // Navigate up back to item 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(selectedItemIndex, equals(2));

      // Press Enter to inspect item 2
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(inspectedItemIndex, equals(2));

      // Press Escape to close
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('mouse click selection, double-click inspection, and Inspect button', (tester) async {
      final items = [
        const CarriedItem(index: 10, object: AgiObject(name: 'Silver Flute', startingRoom: 0)),
        const CarriedItem(index: 11, object: AgiObject(name: 'Spell Book', startingRoom: 0)),
      ];

      int? selectedItemIndex;
      int? inspectedItemIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(
              items: items,
              onItemSelected: (idx) => selectedItemIndex = idx,
              onInspect: (idx) => inspectedItemIndex = idx,
            ),
          ),
        ),
      );

      // Tap second item to select
      await tester.tap(find.text('Spell Book'));
      await tester.pumpAndSettle();
      expect(selectedItemIndex, equals(11));

      // Tap Inspect button
      final inspectButton = find.widgetWithText(ElevatedButton, 'Inspect');
      expect(inspectButton, findsOneWidget);
      await tester.tap(inspectButton);
      await tester.pump();
      expect(inspectedItemIndex, equals(11));

      // Double-tap first item to inspect directly
      inspectedItemIndex = null;
      await tester.tap(find.text('Silver Flute'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Silver Flute'));
      await tester.pumpAndSettle();
      expect(inspectedItemIndex, equals(10));
    });

    testWidgets('filters carried items from engine memory dynamically', (tester) async {
      final engine = AgiGameEngine(
        objects: const [
          AgiObject(name: '?', startingRoom: 0), // dummy
          AgiObject(name: 'Leather Boots', startingRoom: 255),
          AgiObject(name: 'Brass Lantern', startingRoom: 5), // in room 5
          AgiObject(name: 'Rope', startingRoom: 255),
        ],
      );
      engine.initializeGame();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(engine: engine),
          ),
        ),
      );

      // Initially player has Leather Boots and Rope
      expect(find.text('Leather Boots'), findsOneWidget);
      expect(find.text('Rope'), findsOneWidget);
      expect(find.text('Brass Lantern'), findsNothing);
      expect(find.text('?'), findsNothing);

      // Give player Brass Lantern (room 255) and drop Rope (room 0)
      engine.memory.itemRooms[2] = 255;
      engine.memory.itemRooms[3] = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryDialog(engine: engine),
          ),
        ),
      );

      expect(find.text('Leather Boots'), findsOneWidget);
      expect(find.text('Brass Lantern'), findsOneWidget);
      expect(find.text('Rope'), findsNothing);
    });
  });

  group('ObjectInspectionDialog Widget Tests', () {
    testWidgets('renders object name, description, and cel preview', (tester) async {
      // Create a test view with 1 loop, 1 cel, and description
      final rawPixels = Uint8List(4 * 4);
      rawPixels[0] = 14; // EGA Yellow
      rawPixels[1] = 14;
      rawPixels[4] = 14;
      rawPixels[5] = 14;

      final testView = AgiView(
        viewNumber: 15,
        description: 'A finely crafted key made of solid gold.',
        loops: [
          AgiViewLoop(
            loopNumber: 0,
            cels: [
              AgiViewCel.forward(
                width: 4,
                height: 4,
                transparentColor: 0,
                rawPixels: rawPixels,
              ),
            ],
          ),
        ],
      );

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectInspectionDialog(
              objectNumber: 1,
              object: const AgiObject(name: 'Golden Key', startingRoom: 0),
              view: testView,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify name, index, cel widget, and description
      expect(find.text('GOLDEN KEY'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('A finely crafted key made of solid gold.'), findsOneWidget);
      expect(find.byType(CelImageWidget), findsOneWidget);

      // Dismiss via OK button
      await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
      await tester.pump();
      expect(closed, isTrue);

      // Dismiss via Space key
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectInspectionDialog(
              objectNumber: 1,
              object: const AgiObject(name: 'Golden Key', startingRoom: 0),
              view: testView,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('renders fallback placeholder when no view is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ObjectInspectionDialog(
              objectNumber: 7,
              object: AgiObject(name: 'Mystery Crystal', startingRoom: 0),
            ),
          ),
        ),
      );

      expect(find.text('MYSTERY CRYSTAL'), findsOneWidget);
      expect(find.text('#7'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });
  });

  group('AgiLogicInterpreter & AgiGameEngine Opcodes Integration', () {
    test('Opcode 124 (status) triggers onStatus and opens inventory in engine', () {
      final memory = AgiMemory();
      final engine = AgiGameEngine(memory: memory);
      final interpreter = engine.interpreter;

      // Logic script with opcode 124: status()
      final script = AgiLogicScript(
        logicNumber: 1,
        bytecodes: Uint8List.fromList([
          124, // status()
          0xFF, // return
        ]),
        messages: const [],
      );

      interpreter.loadRootScript(script, scriptNumber: 1);
      expect(engine.isInventoryOpen, isFalse);

      final status = interpreter.stepInstruction();
      expect(status, equals(InterpreterStatus.running));
      expect(engine.isInventoryOpen, isTrue);

      // Close inventory
      engine.closeInventory();
      expect(engine.isInventoryOpen, isFalse);
    });

    test('Opcode 129 (show.obj) and Opcode 162 (show.obj.v) trigger onShowObj', () {
      final memory = AgiMemory();
      final engine = AgiGameEngine(memory: memory);
      final interpreter = engine.interpreter;

      // Logic script: show.obj(5), show.obj.v(%v10)
      memory.setVar(10, 12);
      final script = AgiLogicScript(
        logicNumber: 1,
        bytecodes: Uint8List.fromList([
          129, 5, // show.obj(5)
          162, 10, // show.obj.v(%v10) -> obj 12
          0xFF, // return
        ]),
        messages: const [],
      );

      interpreter.loadRootScript(script, scriptNumber: 1);
      expect(engine.inspectingObjectNumber, isNull);

      // Step show.obj(5)
      interpreter.stepInstruction();
      expect(engine.inspectingObjectNumber, equals(5));

      engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, isNull);

      // Step show.obj.v(%v10)
      interpreter.stepInstruction();
      expect(engine.inspectingObjectNumber, equals(12));

      engine.closeObjectInspection();
      expect(engine.inspectingObjectNumber, isNull);
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
    testWidgets('Tab key opens inventory and inspecting an item opens show.obj modal', (tester) async {
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

      // Press Enter to inspect currently selected item (Crystal Orb)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.byType(ObjectInspectionDialog), findsOneWidget);
      expect(find.text('CRYSTAL ORB'), findsOneWidget);

      // Press Space to dismiss inspection dialog
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // Inspection closed, returned to InventoryDialog
      expect(find.byType(ObjectInspectionDialog), findsNothing);
      expect(find.byType(InventoryDialog), findsOneWidget);

      // Press Escape to dismiss inventory
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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

      // Inspect first item (*magic wand)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.byType(ObjectInspectionDialog), findsOneWidget);
      expect(find.text('*MAGIC WAND'), findsOneWidget);
    });
  });
}
