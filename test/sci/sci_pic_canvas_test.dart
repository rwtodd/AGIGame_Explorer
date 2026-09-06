import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  testWidgets('AgiPictureWidget loads and switches between dithered and undithered images for SciPic', (tester) async {
    // 0xF0 33 (0x19: c1 = 1 Blue, c2 = 9 Light Blue), line from (10, 10) to (30, 10)
    final data = Uint8List.fromList([
      0xF0, 33,
      0xF6,
      0x00, 10, 10,
      0x00, 30, 10,
      0xFF,
    ]);

    final pic = SciPicInterpreter.interpret(data, portTop: 0);

    // Initial state: flatVisual (dithered)
    final modeNotifier = ValueNotifier<AgiPictureRenderMode>(AgiPictureRenderMode.flatVisual);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<AgiPictureRenderMode>(
            valueListenable: modeNotifier,
            builder: (context, mode, _) {
              return AgiPictureWidget(
                picture: pic,
                renderMode: mode,
              );
            },
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    // Verify CustomPaint with AgiPicturePainter in flatVisual mode
    final customPaintFinder = find.byType(CustomPaint);
    expect(customPaintFinder, findsWidgets);

    AgiPicturePainter getPainter() {
      for (final element in customPaintFinder.evaluate()) {
        final cp = element.widget as CustomPaint;
        if (cp.painter is AgiPicturePainter) {
          return cp.painter as AgiPicturePainter;
        }
      }
      throw StateError('AgiPicturePainter not found');
    }

    final ditheredPainter = getPainter();
    expect(ditheredPainter.renderMode, AgiPictureRenderMode.flatVisual);
    final ditheredImage = ditheredPainter.flatVisualImage;
    expect(ditheredImage, isNotNull);

    // Switch to unditheredVisual mode
    modeNotifier.value = AgiPictureRenderMode.unditheredVisual;
    await tester.pump();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final unditheredPainter = getPainter();
    expect(unditheredPainter.renderMode, AgiPictureRenderMode.unditheredVisual);
    final unditheredImage = unditheredPainter.flatVisualImage;
    expect(unditheredImage, isNotNull);

    // The two images MUST be different instances (dithered 16-color vs undithered 40-color blended)
    expect(identical(ditheredImage, unditheredImage), isFalse);

    // Switch back to flatVisual mode and verify it returns to dithered image
    modeNotifier.value = AgiPictureRenderMode.flatVisual;
    await tester.pump();

    final backPainter = getPainter();
    expect(identical(backPainter.flatVisualImage, ditheredImage), isTrue);
  });
}
