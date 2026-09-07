import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/sci/font/sci_font.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

SciFont _createTestFont() {
  final glyphs = List<SciFontGlyph?>.filled(128, null);
  // Character 'A' = 65, 8x8 bitmap
  glyphs[65] = SciFontGlyph(
    charCode: 65,
    width: 8,
    height: 8,
    charOffset: 0,
    rawBitmap: Uint8List.fromList([0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00]),
  );
  // Space ' ' = 32, 4x8 bitmap
  glyphs[32] = SciFontGlyph(
    charCode: 32,
    width: 4,
    height: 8,
    charOffset: 8,
    rawBitmap: Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
  );

  return SciFont(
    fontNumber: 0,
    formatFlag: 0,
    fontHeight: 8,
    numChars: 128,
    glyphs: glyphs,
  );
}

void main() {
  final testFont = _createTestFont();

  group('SciWindowOverlay & Controls', () {
    test('SciTextControl properties and rendering', () {
      final control = SciTextControl(
        rect: const Rect.fromLTWH(10, 10, 100, 20),
        text: 'A A',
        font: testFont,
        colorPen: 0,
        align: TextAlign.center,
      );

      expect(control.rect, equals(const Rect.fromLTWH(10, 10, 100, 20)));
      expect(control.text, equals('A A'));
      expect(control.colorPen, equals(0));
      expect(control.align, equals(TextAlign.center));

      // Verify paint execution with PictureRecorder
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      control.paint(canvas, windowTopLeft: const Offset(50, 50));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('SciButtonControl pressed vs unpressed state and focus', () {
      final buttonNormal = SciButtonControl(
        rect: const Rect.fromLTWH(20, 40, 60, 16),
        text: 'A',
        font: testFont,
        isPressed: false,
        isFocused: true,
      );

      final buttonPressed = SciButtonControl(
        rect: const Rect.fromLTWH(20, 40, 60, 16),
        text: 'A',
        font: testFont,
        isPressed: true,
        isFocused: false,
      );

      expect(buttonNormal.isPressed, isFalse);
      expect(buttonNormal.isFocused, isTrue);
      expect(buttonPressed.isPressed, isTrue);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      buttonNormal.paint(canvas, windowTopLeft: const Offset(10, 10));
      buttonPressed.paint(canvas, windowTopLeft: const Offset(10, 10));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('SciIconControl handles direct image and empty view safely', () {
      const icon = SciIconControl(
        rect: Rect.fromLTWH(5, 5, 24, 24),
        loopNumber: 0,
        celNumber: 1,
      );

      expect(icon.loopNumber, equals(0));
      expect(icon.celNumber, equals(1));
      expect(icon.directImage, isNull);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      icon.paint(canvas, windowTopLeft: const Offset(20, 20));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('SciWindowOverlay layout, borders, drop shadow, and child controls', () {
      final textCtrl = SciTextControl(
        rect: const Rect.fromLTWH(10, 20, 180, 20),
        text: 'A',
        font: testFont,
      );
      final okBtn = SciButtonControl(
        rect: const Rect.fromLTWH(30, 50, 50, 16),
        text: 'A',
        font: testFont,
        isFocused: true,
      );
      final cancelBtn = SciButtonControl(
        rect: const Rect.fromLTWH(120, 50, 50, 16),
        text: 'A',
        font: testFont,
      );

      final window = SciWindowOverlay(
        id: 1,
        rect: const Rect.fromLTWH(60, 60, 200, 80),
        priority: 15,
        title: 'A',
        font: testFont,
        colorBack: 15, // White
        colorPen: 0,   // Black
        hasDropShadow: true,
        controls: [textCtrl, okBtn, cancelBtn],
      );

      expect(window.id, equals(1));
      expect(window.rect, equals(const Rect.fromLTWH(60, 60, 200, 80)));
      expect(window.priority, equals(15));
      expect(window.title, equals('A'));
      expect(window.controls.length, equals(3));

      // Paint complete window overlay
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      window.paint(canvas);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('SciWindowOverlay equality and hashCode', () {
      const w1 = SciWindowOverlay(
        id: 1,
        rect: Rect.fromLTWH(10, 10, 100, 100),
        priority: 10,
        title: 'Dialog',
      );
      const w2 = SciWindowOverlay(
        id: 1,
        rect: Rect.fromLTWH(10, 10, 100, 100),
        priority: 10,
        title: 'Dialog',
      );
      const wDiff = SciWindowOverlay(
        id: 2,
        rect: Rect.fromLTWH(10, 10, 100, 100),
        priority: 10,
        title: 'Dialog',
      );

      expect(w1, equals(w2));
      expect(w1.hashCode, equals(w2.hashCode));
      expect(w1, isNot(equals(wDiff)));
    });
  });
}
