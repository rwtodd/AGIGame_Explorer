import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/parsers/view_parser.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
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
      expect(atlas.containsCel(10, 0, 0), equals(atlas.getEntry(10, 0, 0) != null));
      expect(atlas.containsCel(10, 9, 0), isFalse);
      expect(atlas.getEntry(10, 9, 0), isNull);

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

    test('computes unique packed integer keys for (view, loop, cel)', () {
      final key1 = AtlasCelEntry.computeKey(1, 0, 0);
      final key2 = AtlasCelEntry.computeKey(1, 0, 1);
      final key3 = AtlasCelEntry.computeKey(1, 1, 0);
      final key4 = AtlasCelEntry.computeKey(2, 0, 0);

      expect(key1, equals((1 << 16) | (0 << 8) | 0));
      expect(key2, equals((1 << 16) | (0 << 8) | 1));
      expect(key3, equals((1 << 16) | (1 << 8) | 0));
      expect(key4, equals((2 << 16) | (0 << 8) | 0));

      final keys = {key1, key2, key3, key4};
      expect(keys.length, equals(4));
    });

    test('drawEntry paints a resolved cel without a second map lookup', () async {
      final view = ViewParser.parse(
        createSimpleViewData(loopCount: 1, celCount: 1, width: 4, height: 4),
        viewNumber: 5,
      );
      final builder = ViewAtlasBuilder();
      builder.addView(view);
      final atlas = await builder.buildAsync();
      expect(atlas.image, isNotNull);

      final entry = atlas.getEntry(5, 0, 0);
      expect(entry, isNotNull);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      atlas.drawEntry(canvas, entry!, position: const Offset(10, 10));

      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      expect(image.width, equals(32));
      expect(image.height, equals(32));
    });

    test('AgiActorSprite.draw uses a pre-resolved celEntry and ignores it in equality', () async {
      final view = ViewParser.parse(
        createSimpleViewData(loopCount: 1, celCount: 1, width: 4, height: 4),
        viewNumber: 5,
      );
      final builder = ViewAtlasBuilder();
      builder.addView(view);
      final atlas = await builder.buildAsync();
      final entry = atlas.getEntry(5, 0, 0)!;

      final withEntry = AgiActorSprite(
        priority: 9,
        baselineY: 100,
        position: const Offset(8, 8),
        viewNumber: 5,
        atlas: atlas,
        celEntry: entry,
      );
      final withoutEntry = AgiActorSprite(
        priority: 9,
        baselineY: 100,
        position: const Offset(8, 8),
        viewNumber: 5,
        atlas: atlas,
      );
      expect(withEntry, equals(withoutEntry));

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      withEntry.draw(canvas, Paint());

      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      expect(image.width, equals(32));
    });

    test('throws AgiException when rendering without image or missing cel', () {
      final atlas = ViewTextureAtlas(
        width: 16,
        height: 16,
        rgbaPixels: Uint8List(16 * 16 * 4),
        entries: const {},
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

  group('ViewAtlasManager', () {
    test('registers views and builds primary atlas asynchronously', () async {
      final manager = ViewAtlasManager();
      bool updateNotified = false;
      manager.onAtlasUpdated = () => updateNotified = true;

      final view1 = ViewParser.parse(
        createSimpleViewData(loopCount: 2, celCount: 2, width: 8, height: 8),
        viewNumber: 1,
      );
      final view2 = ViewParser.parse(
        createSimpleViewData(loopCount: 1, celCount: 1, width: 16, height: 16),
        viewNumber: 2,
      );

      manager.registerViews([view1, view2]);
      expect(manager.registeredViews.length, equals(2));

      final atlas = await manager.prepareAtlasAsync();
      expect(atlas.hasImage, isTrue);
      expect(updateNotified, isTrue);
      expect(manager.containsCel(1, 0, 0), isTrue);
      expect(manager.containsCel(2, 0, 0), isTrue);
      expect(manager.containsCel(99, 0, 0), isFalse);

      final hit = manager.lookupCel(1, 0, 0);
      expect(hit, isNotNull);
      expect(hit!.atlas, same(manager.primaryAtlas));
      expect(hit.entry, same(manager.primaryAtlas!.getEntry(1, 0, 0)));
      expect(manager.getAtlasForCel(1, 0, 0), same(hit.atlas));
      expect(manager.lookupCel(99, 0, 0), isNull);

      manager.dispose();
      expect(manager.registeredViews.isEmpty, isTrue);
      expect(manager.primaryAtlas, isNull);
    });

    test('creates side-atlas for dynamically loaded views', () async {
      final manager = ViewAtlasManager();
      final view1 = ViewParser.parse(
        createSimpleViewData(loopCount: 1, celCount: 1, width: 8, height: 8),
        viewNumber: 1,
      );
      manager.registerView(view1);
      await manager.prepareAtlasAsync();

      // View 3 loaded mid-room
      final view3 = ViewParser.parse(
        createSimpleViewData(loopCount: 2, celCount: 1, width: 10, height: 10),
        viewNumber: 3,
      );
      final sideAtlas = await manager.ensureSideAtlasAsync(view3);
      expect(sideAtlas.hasImage, isTrue);

      final foundAtlas = manager.getAtlasForCel(3, 0, 0);
      expect(foundAtlas, equals(sideAtlas));

      final sideHit = manager.lookupCel(3, 0, 0);
      expect(sideHit, isNotNull);
      expect(sideHit!.atlas, same(sideAtlas));
      expect(sideHit.entry, same(sideAtlas.getEntry(3, 0, 0)));

      manager.dispose();
    });
  });
}
