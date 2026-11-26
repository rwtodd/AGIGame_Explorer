import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import 'package:flutter_agigame/ui/shaders/priority_sprite_shader.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

import '../support/reference_games.dart';

/// Regression test for the SQ1 Room 65 arrow (view 245) boundary-texel
/// divergence: at the fractional badge scale 2.7188x3.2625 the
/// compositedSlices path drew actor dst edges with AA coverage
/// (Paint.isAntiAlias defaults to true) while shaderComposited drew the
/// crisp floored coverage, so the red arrow's pink outline / black
/// drop-shadow differed pixel-for-pixel. Both modes must now agree
/// exactly, at badge size and at native 320x200.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQ1 pic 65 view 245 arrow: slices vs shader parity at badge size', () async {
    if (skipIfReferenceGameMissing('space-quest-1')) return;
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final loader = AgiResourceLoader.fromDirectorySync('reference_games/space-quest-1');
    final pic = loader.loadPic(65);
    pic.ensureSlices();
    final view = loader.loadView(245);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;

    // Atlas exactly as AgiGameEngine builds it: ViewAtlasManager with the
    // view registered, cel resolved by lookupCel.
    final atlasManager = ViewAtlasManager()..registerView(view);
    final atlas = await atlasManager.prepareAtlasAsync();
    final hit = atlasManager.lookupCel(245, 0, 0);
    expect(hit, isNotNull, reason: 'atlas missing view 245 loop 0 cel 0');

    // Actor built exactly as AgiGameEngine.actors does for object 0:
    // renderX = 106 * 2 = 212, renderY = 82 - celHeight(18) + 1 = 65,
    // priority 14 fixed -> baselineY = top of band 14 = 156,
    // scaleX defaults to 2.0 (AGI doubling).
    final actor = PlayfieldActorSprite(
      priority: 14,
      baselineY: 156,
      objectNumber: 0,
      isUpdating: false,
      position: const Offset(212.0, 65.0),
      viewNumber: 245,
      loopNumber: 0,
      celNumber: 0,
      atlas: atlas,
      celEntry: hit!.entry,
    );

    PlayfieldPainter painter(AgiPictureRenderMode mode) => PlayfieldPainter(
          picture: pic,
          actors: [actor],
          renderMode: mode,
          flatVisualImage: flat,
          priorityTextureImage: priorityTexture,
          prioritySpriteShader: shader,
        );

    Future<Uint8List> renderAt(PlayfieldPainter p, Size size) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      p.paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.ceil(), size.height.ceil());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    const size = Size(870, 652.5);
    const width = 870;
    const height = 653;
    final slicesBytes = await renderAt(painter(AgiPictureRenderMode.compositedSlices), size);
    final shaderBytes = await renderAt(painter(AgiPictureRenderMode.shaderComposited), size);

    var diffPixels = 0;
    final samples = <String>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (slicesBytes[i] != shaderBytes[i] ||
            slicesBytes[i + 1] != shaderBytes[i + 1] ||
            slicesBytes[i + 2] != shaderBytes[i + 2] ||
            slicesBytes[i + 3] != shaderBytes[i + 3]) {
          diffPixels++;
          if (samples.length < 10) {
            samples.add('($x,$y) slices=[${slicesBytes[i]},${slicesBytes[i + 1]},${slicesBytes[i + 2]}] '
                'shader=[${shaderBytes[i]},${shaderBytes[i + 1]},${shaderBytes[i + 2]}]');
          }
        }
      }
    }
    // ignore: avoid_print
    print('SQ1 arrow badge size 870x653 diffPixels=$diffPixels');
    expect(diffPixels, 0, reason: 'badge-size diffs: ${samples.join('; ')}');

    // Sample-compare at playfield-pixel block centers over the actor bbox
    // (playfield x 212..237, y 65..82) with zero tolerance. Device pixel =
    // nearest the playfield pixel center, including the default
    // playfieldRow = 1 vertical translate.
    final scaleX = 870 / 320.0;
    final scaleY = 652.5 / 200.0;
    var blockDiffs = 0;
    final blockSamples = <String>[];
    for (var py = 65; py < 83; py++) {
      for (var px = 212; px < 238; px++) {
        final dx = ((px + 0.5) * scaleX).floor();
        final dy = ((py + 8.5) * scaleY).floor();
        final i = (dy * width + dx) * 4;
        if (slicesBytes[i] != shaderBytes[i] ||
            slicesBytes[i + 1] != shaderBytes[i + 1] ||
            slicesBytes[i + 2] != shaderBytes[i + 2] ||
            slicesBytes[i + 3] != shaderBytes[i + 3]) {
          blockDiffs++;
          if (blockSamples.length < 10) {
            blockSamples.add('playfield ($px,$py) device ($dx,$dy) '
                'slices=[${slicesBytes[i]},${slicesBytes[i + 1]},${slicesBytes[i + 2]}] '
                'shader=[${shaderBytes[i]},${shaderBytes[i + 1]},${shaderBytes[i + 2]}]');
          }
        }
      }
    }
    expect(blockDiffs, 0, reason: 'block-center diffs: ${blockSamples.join('; ')}');

    // Native 320x200 both modes must also agree (actors layer content).
    Future<Uint8List> renderNative(PlayfieldPainter p) => renderAt(p, const Size(320, 200));
    final nativeSlices = await renderNative(painter(AgiPictureRenderMode.compositedSlices));
    final nativeShader = await renderNative(painter(AgiPictureRenderMode.shaderComposited));
    var nativeDiffs = 0;
    for (var i = 0; i < nativeSlices.length; i++) {
      if (nativeSlices[i] != nativeShader[i]) nativeDiffs++;
    }
    // ignore: avoid_print
    print('SQ1 arrow native 320x200 diffBytes=$nativeDiffs');
    expect(nativeDiffs, 0);
  });
}
