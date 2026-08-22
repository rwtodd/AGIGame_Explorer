import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Space Quest 1 Room 65 Star Generator Keypad', () {
    test('renders playfield text on base layer so detonation banner sprites draw over keypad dots', () async {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/space-quest-1');
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Enter Room 65
      engine.onNewRoom(65);
      await engine.tick();

      // Verify dots are in textScreenBuffer at row 6, col 16
      final row6 = List.generate(40, (c) => engine.textScreenBuffer.getCell(6, c).char).join('');
      expect(row6.contains('........'), isTrue);

      // Verify bottom message "F6 to Select Key" on row 24
      final row24 = List.generate(40, (c) => engine.textScreenBuffer.getCell(24, c).char).join('');
      expect(row24.contains('F6 to Select Key'), isTrue);

      // Verify AgiPicturePainter draws playfield text beneath actors
      final recordedOps = <String>[];
      final testCanvas = _MockCanvas(recordedOps);

      final testImage = await createTestImage(width: 32, height: 16);
      final painter = AgiPicturePainter(
        picture: engine.currentPic,
        actors: [
          AgiActorSprite(
            objectNumber: 2,
            position: const Offset(50, 46),
            baselineY: 46,
            priority: 4,
            image: testImage,
          ),
        ],
        textScreenBuffer: engine.textScreenBuffer,
        renderMode: AgiPictureRenderMode.flatVisual,
        flatVisualImage: testImage,
      );

      painter.paint(testCanvas, const Size(320, 200));

      final flatPicIdx = recordedOps.indexWhere((op) => op.contains('Offset(0.0, 0.0)'));
      final playfieldTextIdx = recordedOps.indexWhere((op) => op.contains('translate(128.0, 48.0)'));
      final actorIdx = recordedOps.indexWhere((op) => op.contains('Offset(50.0, 46.0)'));
      final nonPlayfieldTextIdx = recordedOps.indexWhere((op) => op.contains('192.0'));

      expect(flatPicIdx, isNonNegative, reason: 'Flat picture must be drawn');
      expect(playfieldTextIdx, isNonNegative, reason: 'Row 6 dots must be drawn');
      expect(actorIdx, isNonNegative, reason: 'Actor sprite must be drawn');
      expect(nonPlayfieldTextIdx, isNonNegative, reason: 'Row 24 bottom prompt must be drawn');

      // Playfield text is drawn before the actor
      expect(playfieldTextIdx, lessThan(actorIdx),
          reason: 'Playfield text (keypad dots) must be drawn before actor sprites so sprites overlay them');
      // Actor is drawn before non-playfield text (status bar / bottom prompt)
      expect(actorIdx, lessThan(nonPlayfieldTextIdx),
          reason: 'Non-playfield UI text (e.g. row 24 prompt) floats over full playfield');
    });

    test('detonation banner sprites moving across Row 6 erase keypad dots from textScreenBuffer', () async {
      final loader = AgiResourceLoader.fromDirectorySync('reference_games/space-quest-1');
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      // Enter Room 65
      engine.onNewRoom(65);
      await engine.tick();

      // Verify dots are in textScreenBuffer initially at row 6
      var row6 = List.generate(40, (c) => engine.textScreenBuffer.getCell(6, c).char).join('');
      expect(row6.contains('........'), isTrue);

      // Simulate entering code 6858 by setting detonation flag 31 and variables as SQ1 logic 65 does
      engine.memory.setVar(144, 10);
      engine.memory.setVar(145, 255);
      engine.memory.setFlag(31);

      // Run ONE engine tick where start.update(%o2..%o4) and reposition.to execute
      await engine.tick();

      // Verify that all dots are erased immediately on the first tick!
      row6 = List.generate(40, (c) => engine.textScreenBuffer.getCell(6, c).char).join('');
      expect(row6.contains('.'), isFalse,
          reason: 'Keypad dots must be erased immediately when start.update/reposition executes');
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
    ops.add('drawImage at $offset (actor)');
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

