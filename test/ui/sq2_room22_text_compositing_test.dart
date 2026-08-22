import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Space Quest 2 Room 22 Scenery vs Text Compositing', () {
    test('renders text at priority matching underlying scenery so foreground rocks do not occlude prompt', () async {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/space-quest-2');
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Enter Room 22
      engine.onNewRoom(22);
      await engine.tick();

      // Set prompt "F6 to release grip on rope" at row 21, col 5
      engine.textScreenBuffer.writeString(21, 5, 'F6 to release grip on rope', fg: 15, bg: 0);

      final recordedOps = <String>[];
      final testCanvas = _MockCanvas(recordedOps);

      // Verify the underlying picture priority at row 21, col 5 (x=20, y=160)
      final pri = engine.currentPic?.priorityBuffer.priorityAt(20, 160) ?? 4;
      expect(pri, greaterThanOrEqualTo(4));

      // Give the picture cached slices
      final pic = engine.currentPic!;
      await pic.preloadGpuTextures();

      final painter = AgiPicturePainter(
        picture: pic,
        actors: const [],
        textScreenBuffer: engine.textScreenBuffer,
        renderMode: AgiPictureRenderMode.compositedSlices,
      );

      painter.paint(testCanvas, const Size(320, 200));

      // Check that the text is drawn in its matching priority band AFTER slice `pri` is drawn
      // Find the index of slice 5 (the rock)
      final slice5Idx = recordedOps.indexOf('drawImage at Offset(0.0, 0.0)', recordedOps.indexOf('drawImage at Offset(0.0, 0.0)') + 1);
      // Find the text run for "F6 to " at col 5 (x = 40.0, y = 168.0)
      final f6TextIdx = recordedOps.indexWhere((op) => op.contains('translate(40.0, 168.0)'));

      expect(slice5Idx, isNonNegative, reason: 'Slice 5 (foreground rock) must be drawn');
      expect(f6TextIdx, isNonNegative, reason: '"F6 to " text must be drawn');
      expect(f6TextIdx, greaterThan(slice5Idx),
          reason: '"F6 to " text sits on priority 5 rock and must be drawn after Slice 5 so the rock does not occlude it');
    });
  });
}

Future<ui.Image> createTestImage({int width = 32, int height = 16}) {
  final completer = Completer<ui.Image>();
  final pixels = Uint8List(width * height * 4);
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (image) {
    completer.complete(image);
  });
  return completer.future;
}

class _MockCanvas implements Canvas {
  final List<String> ops;
  _MockCanvas(this.ops);

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {
    ops.add('drawImage at $offset');
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    ops.add('drawParagraph at $offset');
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    ops.add('drawRect: $rect');
  }

  @override
  void save() => ops.add('save');

  @override
  void restore() => ops.add('restore');

  @override
  void translate(double dx, double dy) => ops.add('translate($dx, $dy)');

  @override
  void scale(double sx, [double? sy]) => ops.add('scale($sx, $sy)');

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {
    ops.add('clipRect: $rect');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.positionalArguments.isNotEmpty) {
      final firstArg = invocation.positionalArguments.first;
      if (firstArg is TextPainter) {
        ops.add('text:${firstArg.text?.toPlainText()}');
      }
    }
    return null;
  }
}
