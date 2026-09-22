import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_game_state_serializer.dart';
import 'package:flutter_agigame/sci/engine/sci_game_state_snapshot.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/widgets/save_load_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SCI0 Save and Restore Tests', () {
    late Directory tempDir;
    late SciGameEngine engine;
    bool hasPq2 = false;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sci_save_load_test_');
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (pq2Dir.existsSync()) {
        hasPq2 = true;
        engine = SciGameEngine(
          volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
        );
        engine.saveDirectory = tempDir;
        engine.initializeGame();
      }
    });

    tearDown(() async {
      if (hasPq2) {
        engine.dispose();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('parseMetadata infers 80x50 SCI thumbnails that omit dimensions', () {
      final pixels = Uint8List(80 * 50 * 4);
      final json = jsonEncode({
        'description': 'In the car',
        'currentRoom': 33,
        'thumbnail': base64Encode(pixels),
      });
      final info = SciGameStateSerializer.parseMetadata(json, slot: 2);
      expect(info.exists, isTrue);
      expect(info.thumbnailWidth, 80);
      expect(info.thumbnailHeight, 50);
      expect(info.thumbnailRgba!.length, pixels.length);
    });

    test('SciGameStateSnapshot serializes and restores complete engine state', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      // Drive engine up to room 33
      engine.restartGame();
      for (var t = 0; t < 100; t++) {
        engine.tick();
        if (engine.segManager.globals[11].toUint16() == 33) break;
      }
      expect(engine.segManager.globals[11].toUint16(), 33);

      // Mutate state with distinguishable values
      engine.segManager.globals[15] = SciReg.fromInt(42); // Score
      final testHunk = engine.segManager.allocHunk(16);
      final hunkBytes = engine.segManager.getHunk(testHunk)!;
      hunkBytes[0] = 0xAA;
      hunkBytes[1] = 0xBB;

      // Capture snapshot
      final snapshot = SciGameStateSnapshot.capture(
        engine,
        label: 'Bonds in Room 33',
      );
      expect(snapshot.label, 'Bonds in Room 33');
      expect(snapshot.roomNumber, 33);
      expect(snapshot.score, 42);
      expect(snapshot.version, '1.0');

      // Convert to JSON and back
      final json = snapshot.toJson();
      final restoredSnapshot = SciGameStateSnapshot.fromJson(json);
      expect(restoredSnapshot.label, 'Bonds in Room 33');
      expect(restoredSnapshot.roomNumber, 33);
      expect(restoredSnapshot.score, 42);

      // Mutate engine state away from saved state
      engine.segManager.globals[11] = SciReg.fromInt(99);
      engine.segManager.globals[15] = SciReg.fromInt(0);
      hunkBytes[0] = 0x00;

      // Diagnostic
      // print('Snapshot scripts: ${restoredSnapshot.scripts.map((s) => s.scriptNumber).toList()}');
      // print('Snapshot globals length: ${restoredSnapshot.globals.length}');

      // Restore snapshot
      restoredSnapshot.restore(engine);

      // print('Engine globals length after restore: ${engine.segManager.globals.length}');

      // Verify restored values
      expect(engine.segManager.globals.length, greaterThan(15));
      expect(engine.segManager.globals[11].toUint16(), 33);
      expect(engine.segManager.globals[15].toUint16(), 42);
      expect(engine.score, 42);
      expect(engine.currentRoom, 33);

      final recheckedHunk = engine.segManager.getHunk(testHunk);
      expect(recheckedHunk, isNotNull);
      expect(recheckedHunk![0], 0xAA);
      expect(recheckedHunk[1], 0xBB);
    });

    test('SciGameStateSerializer manages slots on disk', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      engine.restartGame();
      for (var t = 0; t < 50; t++) {
        engine.tick();
      }
      engine.segManager.globals[15] = SciReg.fromInt(18);

      // 1. Initial list: all slots empty
      var slots = SciGameStateSerializer.listSlotsSync(
        directory: tempDir,
        maxSlots: 12,
      );
      expect(slots.length, 12);
      expect(slots.every((s) => !s.exists), isTrue);

      // 2. Save slot 1 and slot 3
      final file1 = SciGameStateSerializer.saveToSlotSync(
        engine,
        1,
        description: 'PQ2 Slot 1',
        directory: tempDir,
      );
      expect(file1.existsSync(), isTrue);

      final file3 = SciGameStateSerializer.saveToSlotSync(
        engine,
        3,
        description: 'PQ2 Slot 3',
        directory: tempDir,
      );
      expect(file3.existsSync(), isTrue);

      // 3. List slots again
      slots = SciGameStateSerializer.listSlotsSync(
        directory: tempDir,
        maxSlots: 12,
      );
      expect(slots[0].exists, isTrue);
      expect(slots[0].description, 'PQ2 Slot 1');
      expect(slots[0].score, 18);

      expect(slots[1].exists, isFalse);

      expect(slots[2].exists, isTrue);
      expect(slots[2].description, 'PQ2 Slot 3');
      expect(slots[2].score, 18);

      // 4. Inspect single slot info
      final info1 = SciGameStateSerializer.getSlotInfoSync(1, directory: tempDir);
      expect(info1, isNotNull);
      expect(info1!.exists, isTrue);
      expect(info1.description, 'PQ2 Slot 1');

      final emptyInfo = SciGameStateSerializer.getSlotInfoSync(2, directory: tempDir);
      expect(emptyInfo, isNull);

      // 5. Restore from slot 1
      engine.segManager.globals[15] = SciReg.fromInt(0);
      final restored = SciGameStateSerializer.restoreFromSlotSync(
        engine,
        1,
        directory: tempDir,
      );
      expect(restored, isTrue);
      expect(engine.segManager.globals[15].toUint16(), 18);

      // 6. Delete slot 1
      final deleted = SciGameStateSerializer.deleteSlotSync(1, directory: tempDir);
      expect(deleted, isTrue);
      expect(file1.existsSync(), isFalse);

      final infoAfterDelete = SciGameStateSerializer.getSlotInfoSync(1, directory: tempDir);
      expect(infoAfterDelete, isNull);
    });

    testWidgets('SaveLoadDialog UI works polymorphically with SciGameEngine', (tester) async {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      engine.restartGame();
      for (var t = 0; t < 50; t++) {
        engine.tick();
      }
      engine.segManager.globals[15] = SciReg.fromInt(25);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SaveLoadDialog.showSave(context, engine, directory: tempDir),
                child: const Text('Open SCI Save Dialog'),
              ),
            ),
          ),
        ),
      );

      expect(engine.isPaused, isFalse);

      // Open Save Dialog
      await tester.tap(find.text('Open SCI Save Dialog'));
      await tester.pumpAndSettle();

      expect(engine.isPaused, isTrue);
      expect(find.text('SAVE GAME STATE'), findsOneWidget);
      expect(find.text('Save Game'), findsOneWidget);

      // Enter save description
      final descField = find.byType(TextField);
      expect(descField, findsOneWidget);
      await tester.enterText(descField, 'SCI PQ2 Save');
      await tester.pump();

      // Click Save Game
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Game'));
      await tester.pumpAndSettle();

      // Dialog dismissed and engine unpaused
      expect(find.text('SAVE GAME STATE'), findsNothing);
      expect(engine.isPaused, isFalse);

      engine.pause(); // Clean up periodic timer for widget tester

      // Verify file written to tempDir
      final file = File('${tempDir.path}/slot_1.sav');
      expect(file.existsSync(), isTrue);

      final slotInfo = engine.listSaveSlots(directory: tempDir).first;
      expect(slotInfo.exists, isTrue);
      expect(slotInfo.description, 'SCI PQ2 Save');
      expect(slotInfo.score, 25);
    });

    test('SciKernel opcodes handle CheckSaveGame, GetSaveFiles, and RestoreGame', () {
      if (!hasPq2) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }

      engine.restartGame();
      for (var t = 0; t < 50; t++) {
        engine.tick();
      }
      engine.segManager.globals[15] = SciReg.fromInt(35);

      // Save slots 1 and 4
      engine.saveGameStateSync(slot: 1, description: 'Kernel Save 1', directory: tempDir);
      engine.saveGameStateSync(slot: 4, description: 'Kernel Save 4', directory: tempDir);

      final dummyGame = engine.gameObjForRestore ?? const SciReg.pointer(1, 0);

      // 1. CheckSaveGame (0x69)
      // Slot 1 (virtual 101) exists -> returns 1
      final res1 = engine.kernel.call(engine.vm, 0x69, 2, [dummyGame, SciReg.fromInt(101)]);
      expect(res1.toUint16(), 1);

      // Slot 2 (virtual 102) does not exist -> returns 0 (nullReg)
      final res2 = engine.kernel.call(engine.vm, 0x69, 2, [dummyGame, SciReg.fromInt(102)]);
      expect(res2.isNull, isTrue);

      // 2. GetSaveFiles (0x61)
      final namesPtr = engine.segManager.allocHunk(500);
      final slotsPtr = engine.segManager.allocHunk(30);

      final totalFiles = engine.kernel.call(engine.vm, 0x61, 3, [dummyGame, namesPtr, slotsPtr]);
      expect(totalFiles.toUint16(), 2);

      // Slot IDs
      expect(engine.segManager.readWord(slotsPtr, 0).toUint16(), 101);
      expect(engine.segManager.readWord(slotsPtr, 1).toUint16(), 104);

      // Slot descriptions
      expect(engine.segManager.getString(namesPtr), 'Kernel Save 1');
      final name2Ptr = SciReg.pointer(namesPtr.segment, namesPtr.offset + 36);
      expect(engine.segManager.getString(name2Ptr), 'Kernel Save 4');

      // 3. RestoreGame (0x2E)
      engine.segManager.globals[15] = SciReg.fromInt(0);
      final restoreRes = engine.kernel.call(engine.vm, 0x2E, 2, [dummyGame, SciReg.fromInt(101)]);
      expect(restoreRes.isNull, isTrue); // Returns 0 / null on success
      expect(engine.segManager.globals[15].toUint16(), 35);
    });
  });
}
