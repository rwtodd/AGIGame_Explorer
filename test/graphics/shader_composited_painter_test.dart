import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';
import 'package:flutter_agigame/ui/shaders/priority_sprite_shader.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

import '../support/reference_games.dart';

Future<ui.Image> _decodeSolidImage(int width, int height, List<int> rgba) async {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = rgba[0];
    bytes[i * 4 + 1] = rgba[1];
    bytes[i * 4 + 2] = rgba[2];
    bytes[i * 4 + 3] = rgba[3];
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888,
      (img) => completer.complete(img));
  return completer.future;
}

AgiPic _buildPic() {
  final visual = Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight);
  visual.fillRange(0, visual.length, 1);
  final priority = PriorityBuffer();
  // Vertical full-height stripe: native x 78..81 -> rendered x 156..163.
  // Full-height so the AGI playfieldRow*8 translate (default playfieldRow=1)
  // samples the same priority in the shader's device-pixel UV as the
  // slice path uses at playfield rows, keeping the two renders comparable.
  for (var y = 0; y < AgiPic.nativeHeight; y++) {
    for (var x = 78; x <= 81; x++) {
      priority.setPriorityAt(x, y, 15);
    }
  }
  final slices = PictureSlicer.slice(visualPixels: visual, priorityBuffer: priority);
  return AgiPic(visualPixels: visual, priorityBuffer: priority, slices: slices);
}

/// Solid image with one optional fully-transparent texel at [holeAt].
Future<ui.Image> _decodePatternImage(
    int width, int height, List<int> rgba, {Offset? holeAt}) async {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    bytes[i * 4] = rgba[0];
    bytes[i * 4 + 1] = rgba[1];
    bytes[i * 4 + 2] = rgba[2];
    bytes[i * 4 + 3] = rgba[3];
  }
  if (holeAt != null) {
    // Fully-zero texel (RGB=0, A=0): a valid premultiplied transparent pixel,
    // as in real sprite atlases. RGB!=0 with A=0 is invalid premultiplied
    // data and the two raster paths round it differently.
    final i = (holeAt.dy.toInt() * width + holeAt.dx.toInt()) * 4;
    bytes[i + 0] = 0;
    bytes[i + 1] = 0;
    bytes[i + 2] = 0;
    bytes[i + 3] = 0;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888,
      (img) => completer.complete(img));
  return completer.future;
}

/// Byte-level comparison of two 320x200 rawRgba buffers.
/// Returns the count of differing bytes and descriptions of the first
/// 5 differing pixels (x, y, slices RGBA, shader RGBA).
(int, List<String>) _compareBytes(Uint8List a, Uint8List b) {
  var diffBytes = 0;
  final diffs = <String>[];
  for (var y = 0; y < 200; y++) {
    for (var x = 0; x < 320; x++) {
      final i = (y * 320 + x) * 4;
      final same = a[i] == b[i] &&
          a[i + 1] == b[i + 1] &&
          a[i + 2] == b[i + 2] &&
          a[i + 3] == b[i + 3];
      if (!same) {
        for (var c = 0; c < 4; c++) {
          if (a[i + c] != b[i + c]) diffBytes++;
        }
        if (diffs.length < 5) {
          diffs.add('pixel ($x,$y) slices=[${a[i]},${a[i + 1]},${a[i + 2]},${a[i + 3]}] '
              'shader=[${b[i]},${b[i + 1]},${b[i + 2]},${b[i + 3]}]');
        }
      }
    }
  }
  return (diffBytes, diffs);
}

void _expectParity(Uint8List slicesBytes, Uint8List shaderBytes, String label) {
  final (diffBytes, diffs) = _compareBytes(slicesBytes, shaderBytes);
  expect(diffBytes, 0,
      reason: '$label: $diffBytes differing bytes; first diffs: ${diffs.join('; ')}');
}

Future<(Uint8List bytes, int width, int height)> _renderAtSize(
    PlayfieldPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final width = size.width.toInt();
  final height = size.height.toInt();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (data!.buffer.asUint8List(), width, height);
}

/// Spec oracle for the horizontal-band scene (scene A) at playfield pixel
/// (px, py), py in 0..167 (rendered row py+8 with default playfieldRow=1).
/// Flat: native y<60 blue (EGA 1), 60<=y<120 green (EGA 2), else magenta (5).
/// img15 (cyan, opaque) covers px 100..111, py 56..67 and is fully visible.
/// img10 (green) covers px 20..31, py 116..127 but is visible only where the
/// picture priority is 10 (py 116..119); py 120..127 is pri 15 and hides it.
/// (Its hole at local (5,5) lands at py 121, inside the hidden part.)
/// img4 (orange) covers px 200..211, py 140..151 at priority 4 inside the
/// pri-15 region and is fully hidden.
List<int> _bandOracle(int px, int py) {
  const blue = [0, 0, 0xAA, 255];
  const green = [0, 0xAA, 0, 255];
  const magenta = [0xAA, 0, 0xAA, 255];
  final flat = py < 60 ? blue : (py < 120 ? green : magenta);
  if (px >= 100 && px <= 111 && py >= 56 && py <= 67) {
    return const [0, 255, 255, 255];
  }
  if (px >= 20 && px <= 31 && py >= 116 && py <= 119) {
    return const [0, 255, 0, 255];
  }
  return flat;
}

/// Samples every playfield-pixel block center of a fractional render and
/// expects the exact oracle RGBA there. The device pixel sampled is the
/// one nearest the block (playfield pixel) center: rendered coords of the
/// center are (px+0.5, py+8+0.5), scaled by (w/320, h/200).
void _expectBlockCentersExact(
    Uint8List bytes, int width, int height, String label) {
  final scaleX = width / 320.0;
  final scaleY = height / 200.0;
  var checked = 0;
  final diffs = <String>[];
  for (var py = 0; py < 168; py++) {
    for (var px = 0; px < 320; px++) {
      final dx = ((px + 0.5) * scaleX).floor();
      final dy = ((py + 8.5) * scaleY).floor();
      final i = (dy * width + dx) * 4;
      final actual = [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]];
      checked++;
      if (diffs.length < 5) {
        final want = _bandOracle(px, py);
        if (actual[0] != want[0] ||
            actual[1] != want[1] ||
            actual[2] != want[2] ||
            actual[3] != want[3]) {
          diffs.add('pixel ($px,$py) device ($dx,$dy) '
              'got [${actual.join(',')}] want [${want.join(',')}]');
        }
      }
    }
  }
  expect(diffs, isEmpty,
      reason: '$label: block-center mismatches (checked $checked samples); '
          'first diffs: ${diffs.join('; ')}');
}

Future<Uint8List> _render(PlayfieldPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, const Size(320, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PrioritySpriteLoader.resetForTesting();
  });

  test('shaderComposited matches compositedSlices pixel-for-pixel without text', () async {
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final pic = _buildPic();
    addTearDown(pic.dispose);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;
    expect(flat, isNotNull);
    expect(priorityTexture, isNotNull);

    final spriteImage = await _decodeSolidImage(8, 8, const [255, 0, 255, 255]);
    addTearDown(spriteImage.dispose);

    final actor = PlayfieldActorSprite(
      priority: 10,
      baselineY: 30,
      objectNumber: 1,
      isUpdating: true,
      image: spriteImage,
      position: const Offset(154, 20),
    );

    final slicesPainter = PlayfieldPainter(
      picture: pic,
      actors: [actor],
      renderMode: AgiPictureRenderMode.compositedSlices,
      flatVisualImage: flat,
      priorityTextureImage: priorityTexture,
      prioritySpriteShader: shader,
    );
    final shaderPainter = PlayfieldPainter(
      picture: pic,
      actors: [actor],
      renderMode: AgiPictureRenderMode.shaderComposited,
      flatVisualImage: flat,
      priorityTextureImage: priorityTexture,
      prioritySpriteShader: shader,
    );

    final slicesBytes = await _render(slicesPainter);
    final shaderBytes = await _render(shaderPainter);
    _expectParity(slicesBytes, shaderBytes, 'W2 vertical stripe');
  });

  // Horizontal priority bands in native coords: pri 4 (y<60), pri 10
  // (60<=y<120), pri 15 (y>=120). With the painter's default playfieldRow=1
  // (translate y+8), screen bands are 8..67, 68..127, 128..175.
  AgiPic buildBandPic() {
    final visual = Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight);
    for (var y = 0; y < AgiPic.nativeHeight; y++) {
      final color = y < 60 ? 1 : (y < 120 ? 2 : 5);
      for (var x = 0; x < AgiPic.nativeWidth; x++) {
        visual[y * AgiPic.nativeWidth + x] = color;
      }
    }
    final priority = PriorityBuffer();
    for (var y = 0; y < AgiPic.nativeHeight; y++) {
      final pri = y < 60 ? 4 : (y < 120 ? 10 : 15);
      for (var x = 0; x < AgiPic.nativeWidth; x++) {
        priority.setPriorityAt(x, y, pri);
      }
    }
    final slices = PictureSlicer.slice(visualPixels: visual, priorityBuffer: priority);
    return AgiPic(visualPixels: visual, priorityBuffer: priority, slices: slices);
  }

  test('horizontal priority bands: slices vs shader parity', () async {
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final pic = buildBandPic();
    addTearDown(pic.dispose);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;

    // pri-10 actor (yellow-green, one transparent texel) straddling the
    // native 10/15 boundary: screen y 124..135 crosses screen 128.
    final img10 = await _decodePatternImage(12, 12, const [0, 255, 0, 255],
        holeAt: const Offset(5, 5));
    addTearDown(img10.dispose);
    // pri-15 actor (cyan) straddling the native 4/10 boundary:
    // screen y 64..75 crosses screen 68.
    final img15 = await _decodePatternImage(12, 12, const [0, 255, 255, 255]);
    addTearDown(img15.dispose);
    // pri-4 actor (orange) fully inside the native pri-15 region
    // (screen y 148..159): must be fully behind slice 15.
    final img4 = await _decodePatternImage(12, 12, const [255, 128, 0, 255]);
    addTearDown(img4.dispose);

    final actors = <PlayfieldActorSprite>[
      PlayfieldActorSprite(priority: 10, baselineY: 135, objectNumber: 1, isUpdating: true, image: img10, position: const Offset(20, 116)),
      PlayfieldActorSprite(priority: 15, baselineY: 75, objectNumber: 2, isUpdating: true, image: img15, position: const Offset(100, 56)),
      PlayfieldActorSprite(priority: 4, baselineY: 159, objectNumber: 3, isUpdating: true, image: img4, position: const Offset(200, 140)),
    ];

    final slicesPainter = PlayfieldPainter(
      picture: pic,
      actors: actors,
      renderMode: AgiPictureRenderMode.compositedSlices,
      flatVisualImage: flat,
      priorityTextureImage: priorityTexture,
      prioritySpriteShader: shader,
    );
    final shaderPainter = PlayfieldPainter(
      picture: pic,
      actors: actors,
      renderMode: AgiPictureRenderMode.shaderComposited,
      flatVisualImage: flat,
      priorityTextureImage: priorityTexture,
      prioritySpriteShader: shader,
    );

    final slicesBytes = await _render(slicesPainter);
    final shaderBytes = await _render(shaderPainter);
    _expectParity(slicesBytes, shaderBytes, 'horizontal bands');
  });

  test('playfield text inside pri-4 band with overlapping actor', () async {
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final pic = buildBandPic();
    addTearDown(pic.dispose);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;

    // Text at row 2, col 2: screen rect x 16..32, y 16..24 — fully inside
    // the pri-4 screen band (8..67), so no foreground slice straddles it.
    final textBuf = AgiTextScreenBuffer();
    textBuf.writeString(2, 2, 'HI', fg: 15, bg: 0);

    // pri-10 actor overlapping the text (screen x 10..26, y 18..34).
    final img = await _decodePatternImage(16, 16, const [255, 0, 255, 255],
        holeAt: const Offset(3, 3));
    addTearDown(img.dispose);
    final actors = <PlayfieldActorSprite>[
      PlayfieldActorSprite(priority: 10, baselineY: 33, objectNumber: 1, isUpdating: true, image: img, position: const Offset(10, 10)),
    ];

    PlayfieldPainter painter(AgiPictureRenderMode mode) => PlayfieldPainter(
          picture: pic,
          actors: actors,
          textScreenBuffer: textBuf,
          renderMode: mode,
          flatVisualImage: flat,
          priorityTextureImage: priorityTexture,
          prioritySpriteShader: shader,
        );

    final slicesBytes = await _render(painter(AgiPictureRenderMode.compositedSlices));
    final shaderBytes = await _render(painter(AgiPictureRenderMode.shaderComposited));
    _expectParity(slicesBytes, shaderBytes, 'text in pri-4 band');
  });

  Future<List<PlayfieldActorSprite>> buildBandActors() async {
    final img10 = await _decodePatternImage(12, 12, const [0, 255, 0, 255],
        holeAt: const Offset(5, 5));
    addTearDown(img10.dispose);
    final img15 = await _decodePatternImage(12, 12, const [0, 255, 255, 255]);
    addTearDown(img15.dispose);
    final img4 = await _decodePatternImage(12, 12, const [255, 128, 0, 255]);
    addTearDown(img4.dispose);
    return <PlayfieldActorSprite>[
      PlayfieldActorSprite(priority: 10, baselineY: 135, objectNumber: 1, isUpdating: true, image: img10, position: const Offset(20, 116)),
      PlayfieldActorSprite(priority: 15, baselineY: 75, objectNumber: 2, isUpdating: true, image: img15, position: const Offset(100, 56)),
      PlayfieldActorSprite(priority: 4, baselineY: 159, objectNumber: 3, isUpdating: true, image: img4, position: const Offset(200, 140)),
    ];
  }

  PlayfieldPainter bandPainter(
    AgiPictureRenderMode mode,
    AgiPic pic,
    ui.Image flat,
    ui.Image priorityTexture,
    ui.FragmentShader shader,
    List<PlayfieldActorSprite> actors,
  ) {
    return PlayfieldPainter(
      picture: pic,
      actors: actors,
      renderMode: mode,
      flatVisualImage: flat,
      priorityTextureImage: priorityTexture,
      prioritySpriteShader: shader,
    );
  }

  test('fractional 3.25x (1040x650): block centers exact vs oracle in both modes', () async {
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final pic = buildBandPic();
    addTearDown(pic.dispose);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;
    final actors = await buildBandActors();

    const size = Size(1040, 650);
    final slices = await _renderAtSize(
        bandPainter(AgiPictureRenderMode.compositedSlices, pic, flat, priorityTexture, shader, actors),
        size);
    final composite = await _renderAtSize(
        bandPainter(AgiPictureRenderMode.shaderComposited, pic, flat, priorityTexture, shader, actors),
        size);
    _expectBlockCentersExact(slices.$1, slices.$2, slices.$3, 'slices @1040x650');
    _expectBlockCentersExact(composite.$1, composite.$2, composite.$3, 'shader @1040x650');
  });

  test('fractional ~3.4167x (1093x683): shader block centers exact vs oracle', () async {
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final pic = buildBandPic();
    addTearDown(pic.dispose);
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;
    final actors = await buildBandActors();

    final composite = await _renderAtSize(
        bandPainter(AgiPictureRenderMode.shaderComposited, pic, flat, priorityTexture, shader, actors),
        const Size(1093, 683));
    _expectBlockCentersExact(composite.$1, composite.$2, composite.$3, 'shader @1093x683');
  });

  test('PQ2 pic 1: slices vs shader parity with scanned actor sites', () async {
    if (skipIfReferenceGameMissing('police-quest-2')) return;
    final program = await PrioritySpriteLoader.initialize();
    if (program == null) {
      markTestSkipped('FragmentProgram failed to load; see log');
      return;
    }
    final shader = program.fragmentShader();
    addTearDown(shader.dispose);

    final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    final picRes = vm.findResource(SciResourceType.pic, 1);
    expect(picRes, isNotNull);
    final data = vm.getResourceById(picRes!.id);
    final pic = SciPicInterpreter.interpret(data, picNumber: 1);
    addTearDown(pic.dispose);
    // ignore: avoid_print
    print('PQ2 pic1 activeSlices=${pic.activeSlices.length}');
    await pic.preloadGpuTextures(includeShaderTextures: true);
    final flat = pic.cachedFlatVisualImage!;
    final priorityTexture = pic.cachedPriorityTextureImage!;

    // Scan actual priority pixels for anchor sites.
    Offset? findSite(bool Function(int pri) test) {
      for (var y = 20; y < 180; y++) {
        for (var x = 20; x < 300; x++) {
          final pri = pic.priorityPixels[y * 320 + x] & 0x0F;
          if (test(pri)) return Offset(x.toDouble(), y.toDouble());
        }
      }
      return null;
    }

    final site15 = findSite((p) => p >= 14);
    final site10 = findSite((p) => p >= 8 && p <= 12);
    final site6 = findSite((p) => p <= 5);
    expect(site15, isNotNull, reason: 'no pri>=14 pixel in PQ2 pic1');
    expect(site10, isNotNull, reason: 'no mid pixel in PQ2 pic1');
    expect(site6, isNotNull, reason: 'no pri<=5 pixel in PQ2 pic1');

    Future<PlayfieldActorSprite> actor(
        Offset site, int pri, List<int> rgba, int n) async {
      final img = await _decodePatternImage(12, 12, rgba);
      addTearDown(img.dispose);
      return PlayfieldActorSprite(
        priority: pri,
        baselineY: (site.dy + 6).toInt(),
        objectNumber: n,
        isUpdating: true,
        image: img,
        // SCI: 1:1; scaleX 1.0 since pic is 320 wide already.
        scaleX: 1.0,
        position: Offset(site.dx - 6, site.dy - 6),
      );
    }

    final actors = <PlayfieldActorSprite>[
      await actor(site10!, 10, const [0, 255, 0, 255], 1),
      await actor(site15!, 15, const [0, 255, 255, 255], 2),
      await actor(site6!, 6, const [255, 128, 0, 255], 3),
    ];

    PlayfieldPainter painter(AgiPictureRenderMode mode) => PlayfieldPainter(
          picture: pic,
          actors: actors,
          renderMode: mode,
          flatVisualImage: flat,
          priorityTextureImage: priorityTexture,
          prioritySpriteShader: shader,
        );

    final slicesBytes = await _render(painter(AgiPictureRenderMode.compositedSlices));
    final shaderBytes = await _render(painter(AgiPictureRenderMode.shaderComposited));
    _expectParity(slicesBytes, shaderBytes, 'PQ2 pic1');
  });
}
