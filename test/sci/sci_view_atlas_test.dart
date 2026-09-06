import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/view/sci_view_parser.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import 'sci_view_parser_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewTextureAtlas with SCI0 views', () {
    test('packs native 320-space cels and shares the source rect for mirrors', () {
      final view = SciViewParser.parse(
        createSciEgaViewData(
          loopCount: 2,
          mirrorBits: 0x2,
          width: 8,
          height: 4,
        ),
        viewNumber: 10,
      );

      final builder = ViewAtlasBuilder(padding: 1);
      builder.addView(view);
      final atlas = builder.buildSync();

      expect(atlas.containsCel(10, 0, 0), isTrue);
      expect(atlas.containsCel(10, 1, 0), isTrue);

      final entry0 = atlas.getEntry(10, 0, 0)!;
      final entry1 = atlas.getEntry(10, 1, 0)!;
      expect(entry0.isMirrored, isFalse);
      expect(entry1.isMirrored, isTrue);
      expect(entry1.sourceRect, equals(entry0.sourceRect));
      expect(entry1.sourceLoop, 0);
      expect(entry0.width, 8);
      expect(entry0.height, 4);
    });
  });
}
