import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AgiPicturePainter paints text overlay with non-zero background without freezing', (tester) async {
    final buffer = AgiTextScreenBuffer();
    // Clear line 0 with white background (color 15) - exactly what status bar / KQ3 clock does
    buffer.clearLines(0, 0, 15);
    buffer.writeString(0, 1, 'Score: 0 of 210', fg: 0, bg: 15);
    buffer.writeString(0, 25, 'Time: 00:00:00', fg: 0, bg: 15);

    final painter = AgiPicturePainter(
      textScreenBuffer: buffer,
      isTextScreen: false,
    );

    // Render painter onto a canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(320, 200));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
  });
}
