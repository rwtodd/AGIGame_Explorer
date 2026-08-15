import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
