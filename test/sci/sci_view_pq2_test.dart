import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/view/sci_view_parser.dart';

void main() {
  group('Police Quest 2 VIEW integration', () {
    test('parses view 0 (ego) loops, shared mirror, and native 320 sizes', () {
      final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      final data = vm.getResource(SciResourceType.view, 0);
      final view = SciViewParser.parse(data, viewNumber: 0);

      expect(view.loopCount, 4);
      expect(view.pixelScaleX, 1);
      expect(view.mirrorBits, 0x2);
      expect(view.flags, 0);
      expect(view.paletteOffset, 0);

      expect(view.getLoop(0)!.celCount, 10);
      expect(view.getLoop(1)!.celCount, 10);
      expect(view.getLoop(1)!.isMirrorLoop, isTrue);

      final cel0 = view.getCel(0, 0)!;
      expect(cel0.width, 19);
      expect(cel0.height, 43);
      expect(cel0.transparentColor, 2);
      expect(cel0.isMirrored, isFalse);
      expect(cel0.rawPixels, isNotNull);
      expect(cel0.rawPixels!.length, 19 * 43);

      final mirror = view.getCel(1, 0)!;
      expect(mirror.isMirrored, isTrue);
      expect(mirror.mirrorLoop, 0);
      expect(mirror.width, 19);
      expect(mirror.height, 43);
      expect(view.resolveSourceCel(1, 0), same(cel0));
    });

    test('parses all PQ2 views without crashing', () {
      final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      final entries = vm.resourceMap.entriesForType(SciResourceType.view);
      expect(entries.length, 207);

      var parsed = 0;
      var mirroredLoops = 0;
      var emptyStubs = 0;
      for (final entry in entries) {
        final data = vm.getResourceById(entry.id);
        final view = SciViewParser.parse(data, viewNumber: entry.id.number);
        expect(view.pixelScaleX, 1, reason: 'view ${entry.id.number}');
        if (view.loopCount == 0) {
          emptyStubs++;
        }
        for (final loop in view.loops) {
          if (loop.isMirrorLoop) mirroredLoops++;
          for (var c = 0; c < loop.celCount; c++) {
            final cel = loop.getCel(c)!;
            expect(cel.width, greaterThan(0));
            expect(cel.height, greaterThan(0));
            if (!cel.isMirrored) {
              expect(cel.rawPixels, isNotNull);
              expect(cel.rawPixels!.length, cel.width * cel.height);
            }
          }
        }
        parsed++;
      }
      expect(parsed, 207);
      expect(mirroredLoops, greaterThan(0));
      expect(emptyStubs, 1); // view 140 is an 8-byte loopCount=0 stub
    });
  });
}
