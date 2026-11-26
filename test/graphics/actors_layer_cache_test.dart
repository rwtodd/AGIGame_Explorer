import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

Future<ui.Image> _decodeSolidImage(List<int> rgba) async {
  final bytes = Uint8List(8 * 8 * 4);
  for (var i = 0; i < 8 * 8; i++) {
    bytes[i * 4] = rgba[0];
    bytes[i * 4 + 1] = rgba[1];
    bytes[i * 4 + 2] = rgba[2];
    bytes[i * 4 + 3] = rgba[3];
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, 8, 8, ui.PixelFormat.rgba8888,
      (img) => completer.complete(img));
  return completer.future;
}

Future<Uint8List> _render(PlayfieldPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, const Size(320, 200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actors layer is recorded once across identical paints; a 1px move re-records', () async {
    final pic = AgiPic(
      visualPixels: Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight)
        ..fillRange(0, AgiPic.nativeWidth * AgiPic.nativeHeight, 1),
      priorityBuffer: PriorityBuffer(),
      slices: <int, PictureSlice>{},
    );
    addTearDown(pic.dispose);
    final flat = await pic.toFlatVisualUiImage();
    // pic owns the flat image; pic.dispose() releases it.

    final sprite = await _decodeSolidImage(const [255, 0, 255, 255]);
    addTearDown(sprite.dispose);

    PlayfieldActorSprite actorAt(Offset position) => PlayfieldActorSprite(
          priority: 10,
          baselineY: 30,
          objectNumber: 1,
          isUpdating: true,
          image: sprite,
          position: position,
        );

    final cache = ActorsLayerCache();
    addTearDown(cache.dispose);

    PlayfieldPainter painterFor(PlayfieldActorSprite actor) => PlayfieldPainter(
          picture: pic,
          actors: [actor],
          renderMode: AgiPictureRenderMode.shaderComposited,
          flatVisualImage: flat,
          actorsLayerCache: cache,
        );

    final painter = painterFor(actorAt(const Offset(154, 20)));
    await _render(painter);
    await _render(painterFor(actorAt(const Offset(154, 20))));
    expect(cache.renders, 1);
    expect(painter.debugActorsLayerRenders, 1);

    // Same cache, actor moved by 1px: signature miss -> second recording,
    // which then becomes the cache (a repaint with the new actor reuses it).
    final moved = painterFor(actorAt(const Offset(155, 20)));
    await _render(moved);
    expect(cache.renders, 2);
    await _render(moved);
    expect(cache.renders, 2);
  });

  test('no cache attached: every paint records (local diagnostic)', () async {
    final pic = AgiPic(
      visualPixels: Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight),
      priorityBuffer: PriorityBuffer(),
      slices: <int, PictureSlice>{},
    );
    addTearDown(pic.dispose);
    final flat = await pic.toFlatVisualUiImage();
    // pic owns the flat image; pic.dispose() releases it.
    final sprite = await _decodeSolidImage(const [255, 0, 255, 255]);
    addTearDown(sprite.dispose);

    final painter = PlayfieldPainter(
      picture: pic,
      actors: [
        PlayfieldActorSprite(
          priority: 10,
          baselineY: 30,
          objectNumber: 1,
          image: sprite,
          position: const Offset(154, 20),
        ),
      ],
      renderMode: AgiPictureRenderMode.shaderComposited,
      flatVisualImage: flat,
    );
    await _render(painter);
    await _render(painter);
    expect(painter.debugActorsLayerRenders, 2);
  });

  test('no actors: no recording at all', () async {
    final pic = AgiPic(
      visualPixels: Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight),
      priorityBuffer: PriorityBuffer(),
      slices: <int, PictureSlice>{},
    );
    addTearDown(pic.dispose);
    final flat = await pic.toFlatVisualUiImage();
    // pic owns the flat image; pic.dispose() releases it.

    final cache = ActorsLayerCache();
    addTearDown(cache.dispose);
    final painter = PlayfieldPainter(
      picture: pic,
      actors: const [],
      renderMode: AgiPictureRenderMode.shaderComposited,
      flatVisualImage: flat,
      actorsLayerCache: cache,
    );
    await _render(painter);
    await _render(painter);
    expect(cache.renders, 0);
    expect(painter.debugActorsLayerRenders, 0);
  });
}
