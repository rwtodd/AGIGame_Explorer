import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

SciCursor _createTestCursor() {
  final pixels = List<SierraCursorPixel>.filled(256, SierraCursorPixel.transparent);
  // Fill top-left 4x4 with black/white/gray/transparent pixels
  pixels[0] = SierraCursorPixel.black;
  pixels[1] = SierraCursorPixel.white;
  pixels[2] = SierraCursorPixel.gray;
  pixels[3] = SierraCursorPixel.transparent;

  return SciCursor(
    cursorNumber: 999,
    hotspotX: 1,
    hotspotY: 1,
    pixels: pixels,
    maskA: Uint8List(32),
    maskB: Uint8List(32),
  );
}

void main() {
  group('PlayfieldPainter & Compositor', () {
    test('renders with SCI0 display profile, actor sprites, window overlay, and mouse cursor', () {
      final testCursor = _createTestCursor();
      const testActor = PlayfieldActorSprite(
        priority: 7,
        baselineY: 120,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(100, 80),
        viewNumber: 5,
        loopNumber: 0,
        celNumber: 0,
        scaleX: 1.0,
        scaleY: 1.0,
        z: 10,
      );
      const testWindow = SciWindowOverlay(
        id: 1,
        rect: Rect.fromLTWH(50, 40, 220, 100),
        priority: 15,
        title: 'SCI Dialog',
      );

      final painter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [testActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(640, 400));
      final pic = recorder.endRecording();
      expect(pic, isNotNull);
    });

    test('shouldRepaint detects differences in actors, windows, cursor, and profile', () {
      final testCursor = _createTestCursor();
      const testActor = PlayfieldActorSprite(
        priority: 7,
        baselineY: 120,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(100, 80),
        viewNumber: 5,
        loopNumber: 0,
        celNumber: 0,
      );
      const testWindow = SciWindowOverlay(
        id: 1,
        rect: Rect.fromLTWH(50, 40, 220, 100),
        priority: 15,
        title: 'SCI Dialog',
      );

      final basePainter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [testActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );

      final samePainter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [testActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );

      // Identical painters should not repaint
      expect(basePainter.shouldRepaint(samePainter), isFalse);

      // Changed actor
      const diffActor = PlayfieldActorSprite(
        priority: 7,
        baselineY: 125,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(100, 85),
        viewNumber: 5,
        loopNumber: 0,
        celNumber: 0,
      );
      final diffActorPainter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [diffActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );
      expect(basePainter.shouldRepaint(diffActorPainter), isTrue);

      // Changed windows
      final diffWindowPainter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [testActor],
        sciWindows: const [],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );
      expect(basePainter.shouldRepaint(diffWindowPainter), isTrue);

      // Changed cursor position
      final diffCursorPainter = PlayfieldPainter(
        displayProfile: DisplayProfile.sci0,
        actors: const [testActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(170, 100),
        showMouseCursor: true,
      );
      expect(basePainter.shouldRepaint(diffCursorPainter), isTrue);

      // Changed display profile
      final diffProfilePainter = PlayfieldPainter(
        displayProfile: DisplayProfile.agi,
        actors: const [testActor],
        sciWindows: const [testWindow],
        mouseCursor: testCursor,
        mouseCursorPosition: const Offset(160, 100),
        showMouseCursor: true,
      );
      expect(basePainter.shouldRepaint(diffProfilePainter), isTrue);
    });
  });
}
