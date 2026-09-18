import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

void main() {
  group('Conquests of Camelot Dialog Regression Tests', () {
    test('Modal dialog polling GetEvent yields and does not enter a CPU spin loop', () {
      final dir = Directory('reference_games/conquests-of-camelot');
      if (!dir.existsSync()) {
        markTestSkipped('Camelot reference tree missing');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(dir.path),
      );
      engine.initializeGame();
      engine.start();

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }

      // Press Enter to open the prompt / options window
      final sw = Stopwatch()..start();
      engine.handleKeyPress(13, ascii: 13);
      sw.stop();

      // Ensure opening the modal dialog ran quickly and yielded to the host
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(engine.kernel.windowManager.windowStack.isNotEmpty, isTrue);

      // Running subsequent ticks while the dialog is waiting for input must be instantaneous
      for (var t = 0; t < 20; t++) {
        final tickSw = Stopwatch()..start();
        engine.tick();
        tickSw.stop();
        expect(tickSw.elapsedMilliseconds, lessThan(50));
      }

      // Clone table should be small and stable, not leaking towards 65535
      expect(engine.segManager.clones.length, lessThan(32));

      engine.dispose();
    });

    test('Inspect dialog on look command in room 2', () async {
      final dir = Directory('reference_games/conquests-of-camelot');
      if (!dir.existsSync()) {
        markTestSkipped('Camelot reference tree missing');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(dir.path),
      );
      engine.initializeGame();
      engine.start();

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }

      engine.submitCommand('look');

      for (var t = 0; t < 10; t++) {
        engine.tick();
      }

      expect(engine.kernel.windowManager.windowStack.length, equals(1));
      final w = engine.kernel.windowManager.windowStack.first;
      expect(w.controls.first, isA<SciTextControl>());

      // Dismiss Window 2
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }

      // Advance engine to room 2
      final newRoomSel = engine.selectors.findSelector('newRoom')!;
      final curRoomRef = engine.segManager.globals[1];
      engine.vm.sendSelector(curRoomRef, newRoomSel, [const SciReg.fromInt(2)]);
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }
      for (var t = 0; t < 200; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);

      // Open dialogue with "look" in room 2
      engine.submitCommand('look');
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }

      expect(engine.kernel.windowManager.windowStack.length, equals(1));
      final room2Wnd = engine.kernel.windowManager.windowStack.first;
      expect(room2Wnd.style, equals(129));
      final overlays = engine.sciWindows;
      expect(overlays.length, equals(2));
      // Overlay 0 is _picDisplays (background fill + 4 corner cels + border lines) with priority 0
      expect(overlays[0].id, equals(1));
      expect(overlays[0].priority, equals(0));
      expect(overlays[0].controls.length, equals(13));

      // Fill control must have authentic dark gray background (color 8, #555555), not black (0) or colorMask 1 (blue)
      final fill = overlays[0].controls[0] as SciFillControl;
      expect(fill.color, equals(8));

      // 4 corner decoration icons from View 657
      final cornerIcons = overlays[0].controls.whereType<SciIconControl>().toList();
      expect(cornerIcons.length, equals(4));
      for (final icon in cornerIcons) {
        expect(icon.view?.viewNumber, equals(657));
      }

      // Verify painted text pixels are visible
      final overlay = overlays.last;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      overlay.paint(canvas);
      final pic = recorder.endRecording();
      final img = await pic.toImage(320, 200);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = byteData!.buffer.asUint8List();
      var whitePixels = 0;
      var minX = 320, maxX = 0, minY = 200, maxY = 0;
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 320; x++) {
          final idx = (y * 320 + x) * 4;
          final a = bytes[idx + 3];
          if (a != 0) {
            final r = bytes[idx], g = bytes[idx + 1], b = bytes[idx + 2];
            if (r == 255 && g == 255 && b == 255) {
              whitePixels++;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
      }

      expect(whitePixels, greaterThan(500));
      expect(minX, greaterThanOrEqualTo(64));
      expect(maxX, lessThanOrEqualTo(255));
      expect(minY, greaterThanOrEqualTo(108));
      expect(maxY, lessThanOrEqualTo(152));

      // Also verify corner decoration pixels and gray background fill in overlay 0
      final decorRecorder = ui.PictureRecorder();
      final decorCanvas = Canvas(decorRecorder);
      overlays[0].paint(decorCanvas);
      final decorPic = decorRecorder.endRecording();
      final decorImg = await decorPic.toImage(320, 200);
      final decorBytes = (await decorImg.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

      var grayPixels = 0;
      var cornerRedPixels = 0;
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 320; x++) {
          final idx = (y * 320 + x) * 4;
          final r = decorBytes[idx], g = decorBytes[idx + 1], b = decorBytes[idx + 2];
          if (r == 85 && g == 85 && b == 85) {
            grayPixels++;
          } else if (r == 255 && g == 85 && b == 85) {
            cornerRedPixels++;
          }
        }
      }
      expect(grayPixels, greaterThan(1000),
          reason: 'Dialog background fill must render EGA dark gray pixels (#555555)');
      expect(cornerRedPixels, greaterThan(100),
          reason: 'Corner Celtic knots from View 657 must render red accent pixels');

      // Dismiss dialog with Enter key
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);
      expect(engine.sciWindows.isEmpty, isTrue);

      // Verify opening and dismissing a second dialog in the same room also cleans up completely
      engine.submitCommand('look');
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.length, equals(1));
      expect(engine.sciWindows.length, equals(2));

      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);
      expect(engine.sciWindows.isEmpty, isTrue);

      engine.dispose();
    });

    test('Room 4 look dialog renders corner decorations with warrior-king text', () async {
      final dir = Directory('reference_games/conquests-of-camelot');
      if (!dir.existsSync()) {
        markTestSkipped('Camelot reference tree missing');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(dir.path),
      );
      engine.initializeGame();
      engine.start();

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }

      // Dismiss initial dialog if any
      if (engine.kernel.windowManager.windowStack.isNotEmpty) {
        engine.handleKeyPress(13, ascii: 13);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
      }

      // Advance engine to Room 4
      final newRoomSel = engine.selectors.findSelector('newRoom')!;
      final curRoomRef = engine.segManager.globals[1];
      engine.vm.sendSelector(curRoomRef, newRoomSel, [const SciReg.fromInt(4)]);
      for (var t = 0; t < 200; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);

      // Open dialogue with "look" in Room 4
      engine.submitCommand('look');
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }

      expect(engine.kernel.windowManager.windowStack.length, equals(1));
      final room4Wnd = engine.kernel.windowManager.windowStack.first;
      expect(room4Wnd.style, equals(129));
      expect(room4Wnd.controls.first, isA<SciTextControl>());
      final textCtrl = room4Wnd.controls.first as SciTextControl;
      expect(textCtrl.text, contains('warrior-king'));
      expect(textCtrl.text, contains('solitude'));

      final overlays = engine.sciWindows;
      expect(overlays.length, equals(2));

      // Overlay 0 must have 13 controls: 1 fill + 4 corner icons + 8 border lines
      expect(overlays[0].controls.length, equals(13));
      final fill = overlays[0].controls[0] as SciFillControl;
      expect(fill.color, equals(8), reason: 'Authentic EGA dark gray background fill');

      final cornerIcons = overlays[0].controls.whereType<SciIconControl>().toList();
      expect(cornerIcons.length, equals(4));

      // Verify the 4 corners: top-left (51, 105), bottom-left (51, 152), top-right (255, 105), bottom-right (255, 152)
      expect(cornerIcons[0].rect.topLeft, equals(const Offset(51, 105)));
      expect(cornerIcons[1].rect.topLeft, equals(const Offset(51, 152)));
      expect(cornerIcons[2].rect.topLeft, equals(const Offset(255, 105)));
      expect(cornerIcons[3].rect.topLeft, equals(const Offset(255, 152)));

      // Dismiss dialog
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);
      expect(engine.sciWindows.isEmpty, isTrue);

      engine.dispose();
    });

    test('Room 4 change clothes sequence', () async {
      final dir = Directory('reference_games/conquests-of-camelot');
      if (!dir.existsSync()) {
        markTestSkipped('Camelot reference tree missing');
        return;
      }

      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(dir.path),
      );
      engine.initializeGame();
      engine.start();

      for (var t = 0; t < 50; t++) {
        engine.tick();
      }

      // Dismiss initial dialog if any
      if (engine.kernel.windowManager.windowStack.isNotEmpty) {
        engine.handleKeyPress(13, ascii: 13);
        for (var t = 0; t < 10; t++) {
          engine.tick();
        }
      }

      // Advance engine to Room 4
      final newRoomSel = engine.selectors.findSelector('newRoom')!;
      final curRoomRef = engine.segManager.globals[1];
      engine.vm.sendSelector(curRoomRef, newRoomSel, [const SciReg.fromInt(4)]);
      for (var t = 0; t < 200; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);

      // Submit command "change clothes"
      engine.submitCommand('change clothes');
      final s4Seg = engine.segManager.scriptToSegment[4]!;
      final s4 = engine.segManager.loadedScripts[s4Seg]!;
      final clothes = s4.objects[0xf06]!;
      final egoRef = engine.segManager.globals[0];
      final egoObj = engine.segManager.getObject(egoRef)!;

      final viewSel = engine.selectors.findSelector('view')!;
      final loopSel = engine.selectors.findSelector('loop')!;
      final celSel = engine.selectors.findSelector('cel')!;
      final xSel = engine.selectors.findSelector('x')!;
      final ySel = engine.selectors.findSelector('y')!;

      for (var t = 0; t < 350; t++) {
        engine.tick();
        if (engine.kernel.windowManager.windowStack.isNotEmpty) {
          engine.handleKeyPress(13, ascii: 13);
        }
      }

      // At tick 350, suitUp has reached state 14, ego is at (180, 110)
      // Verify door never moved:
      final doorObj = s4.objects.entries.firstWhere((e) => e.value.nameString == 'door').value;
      expect(doorObj.getProp(engine.segManager, xSel).toUint16(), equals(45));
      expect(doorObj.getProp(engine.segManager, ySel).toUint16(), equals(113));
      expect(doorObj.getProp(engine.segManager, loopSel).toUint16(), equals(0));
      expect(doorObj.getProp(engine.segManager, celSel).toUint16(), equals(0));

      // Verify clothes is loop 6, not loop 0 (door)
      expect(clothes.getProp(engine.segManager, loopSel).toUint16(), equals(6));
      expect(clothes.getProp(engine.segManager, celSel).toUint16(), equals(3));
      expect(clothes.getProp(engine.segManager, xSel).toUint16(), equals(50));
      expect(clothes.getProp(engine.segManager, ySel).toUint16(), equals(140));

      // Verify ego is in armor (view 0) at (180, 110)
      expect(egoObj.getProp(engine.segManager, viewSel).toUint16(), equals(0));
      expect(egoObj.getProp(engine.segManager, xSel).toUint16(), equals(180));
      expect(egoObj.getProp(engine.segManager, ySel).toUint16(), equals(110));

      // Verify user input is accepted and works after changing clothes
      engine.submitCommand('look');
      for (var t = 0; t < 20; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isNotEmpty, isTrue);
      final lookWnd = engine.kernel.windowManager.windowStack.first;
      final textCtrl = lookWnd.controls.first as SciTextControl;
      expect(textCtrl.text, contains('warrior-king'));
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
      expect(engine.kernel.windowManager.windowStack.isEmpty, isTrue);

      engine.dispose();
    });
  });
}

