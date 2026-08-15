import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/parsers/view_parser.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import '../parsers/view_parser_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewTextureAtlas & ViewAtlasBuilder', () {
    test('builds atlas and shares source rect for mirrored cels', () {
      final viewData = createSimpleViewData(
        loopCount: 2,
        celCount: 1,
        width: 8,
        height: 8,
        transColor: 0,
        isMirrored: true,
        mirrorLoop: 0,
      );

      final view = ViewParser.parse(viewData, viewNumber: 10);
      final builder = ViewAtlasBuilder(padding: 2);
      builder.addView(view);

      final atlas = builder.buildSync();

      expect(atlas.width, isPositive);
      expect(atlas.height, isPositive);
      expect(atlas.containsCel(10, 0, 0), isTrue);
      expect(atlas.containsCel(10, 1, 0), isTrue);

      final entry0 = atlas.getEntry(10, 0, 0)!;
      final entry1 = atlas.getEntry(10, 1, 0)!;

      expect(entry0.isMirrored, isFalse);
      expect(entry1.isMirrored, isTrue);

      // Crucial: Mirrored cel shares the exact same sourceRect as the unmirrored cel!
      expect(entry1.sourceRect, equals(entry0.sourceRect));
      expect(entry1.sourceLoop, equals(0));
      expect(entry1.sourceCel, equals(0));
    });

    test('packs multiple different views into compact atlas', () {
      final view1 = ViewParser.parse(
        createSimpleViewData(loopCount: 1, celCount: 2, width: 6, height: 10),
        viewNumber: 1,
      );
      final view2 = ViewParser.parse(
        createSimpleViewData(loopCount: 2, celCount: 1, width: 12, height: 16),
        viewNumber: 2,
      );

      final builder = ViewAtlasBuilder(padding: 1);
      builder.addViews([view1, view2]);

      final atlas = builder.buildSync();

      expect(atlas.entries.length, equals(4)); // view 1: 2 cels, view 2: 2 cels
      expect(atlas.containsCel(1, 0, 0), isTrue);
      expect(atlas.containsCel(1, 0, 1), isTrue);
      expect(atlas.containsCel(2, 0, 0), isTrue);
      expect(atlas.containsCel(2, 1, 0), isTrue);

      // Verify no overlapping rectangles for unmirrored cels
      final unmirroredEntries = atlas.allEntries.where((e) => !e.isMirrored).toList();
      for (var i = 0; i < unmirroredEntries.length; i++) {
        for (var j = i + 1; j < unmirroredEntries.length; j++) {
          final r1 = unmirroredEntries[i].sourceRect;
          final r2 = unmirroredEntries[j].sourceRect;
          expect(r1.overlaps(r2), isFalse,
              reason: 'Rectangles $r1 and $r2 should not overlap in atlas');
        }
      }
    });

    test('renders cels to Canvas with normal and mirrored orientations', () async {
      final viewData = createSimpleViewData(
        loopCount: 2,
        celCount: 1,
        width: 4,
        height: 4,
        transColor: 0,
        isMirrored: true,
        mirrorLoop: 0,
      );

      final view = ViewParser.parse(viewData, viewNumber: 5);
      final builder = ViewAtlasBuilder();
      builder.addView(view);

      final atlas = await builder.buildAsync();
      expect(atlas.image, isNotNull);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw forward cel
      atlas.drawCel(
        canvas,
        viewNumber: 5,
        loopNumber: 0,
        celNumber: 0,
        position: const Offset(10, 10),
      );

      // Draw mirrored cel (flipped horizontally)
      atlas.drawCel(
        canvas,
        viewNumber: 5,
        loopNumber: 1,
        celNumber: 0,
        position: const Offset(50, 10),
      );

      // Draw batch sprites
      atlas.drawSprites(canvas, [
        const AtlasSpriteDrawCall(
          viewNumber: 5,
          loopNumber: 0,
          celNumber: 0,
          position: Offset(100, 10),
          scale: 2.0,
        ),
      ]);

      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 100);
      expect(image.width, equals(200));
      expect(image.height, equals(100));
    });

    test('throws AgiException when rendering without image or missing cel', () {
      final atlas = ViewTextureAtlas(
        width: 16,
        height: 16,
        rgbaPixels: Uint8List(16 * 16 * 4),
        entries: {},
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      expect(
        () => atlas.drawCel(
          canvas,
          viewNumber: 99,
          loopNumber: 0,
          celNumber: 0,
          position: Offset.zero,
        ),
        throwsA(isA<AgiException>()),
      );
    });
  });
}
