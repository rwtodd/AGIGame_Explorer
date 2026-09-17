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
      expect(room2Wnd.isTransparent, isTrue);

      final overlays = engine.sciWindows;
      expect(overlays.length, equals(2));
      // Overlay 0 is _picDisplays (background fill + border lines) with priority 0
      expect(overlays[0].id, equals(1));
      expect(overlays[0].priority, equals(0));
      expect(overlays[0].controls.length, equals(9));
      // Overlay 1 is the dialog window with priority 15
      expect(overlays[1].id, equals(3));
      expect(overlays[1].priority, equals(15));
      expect(overlays[1].isTransparent, isTrue);

      // Verify painted text pixels are visible (not occluded by dark blue background)
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
  });
}
