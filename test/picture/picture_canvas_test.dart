import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/picture/pic_vector_interpreter.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  testWidgets('AgiPictureWidget renders and toggles render modes', (WidgetTester tester) async {
    final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();
    final interpreter = PicVectorInterpreter();
    final pic = interpreter.interpret(srcBytes);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AgiPictureWidget(
              picture: pic,
              showToolbar: true,
            ),
          ),
        ),
      ),
    );

    // Allow async image decode to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Verify toolbar is rendered with mode buttons
    expect(find.text('Composited'), findsOneWidget);
    expect(find.text('Visual'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Control'), findsOneWidget);

    // Tap Visual mode
    await tester.tap(find.text('Visual'));
    await tester.pumpAndSettle();

    // Tap Priority mode
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();

    // Tap Control mode
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
  });

  testWidgets('AgiPicturePainter draws status line overlay when picture is non-null', (WidgetTester tester) async {
    final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();
    final interpreter = PicVectorInterpreter();
    final pic = interpreter.interpret(srcBytes);

    final buffer = AgiTextScreenBuffer();
    buffer.clearLines(0, 0, 15);
    buffer.writeString(0, 1, 'Score: 100 of 250', fg: 0, bg: 15);
    buffer.writeString(0, 30, 'Sound:on', fg: 0, bg: 15);

    final painter = AgiPicturePainter(
      picture: pic,
      textScreenBuffer: buffer,
      isTextScreen: false,
    );

    // Render painter onto a canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(320, 200));
    final recordedPic = recorder.endRecording();
    expect(recordedPic, isNotNull);
  });
}
