import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_agigame/ui/shaders/priority_sprite_shader.dart';

/// Diff report: total differing bytes plus sample diffs.
class _DiffReport {
  final int diffBytes;
  final List<String> diffs;
  _DiffReport(this.diffBytes, this.diffs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Synthetic fixture constants.
  const playW = 8;
  const playH = 4;
  const priorities = [4, 9, 10, 11, 15, 10, 9, 4];
  const actorPri = 10;
  const bg = [16, 24, 40, 255];

  // Cel occupies image x 2..5, y 0..1 in an 8x2 atlas-like sprite image.
  const srcRect = Rect.fromLTWH(2.0, 0.0, 4.0, 2.0);
  const dstRect = Rect.fromLTWH(1.0, 1.0, 4.0, 2.0);
  const playfieldSize = Size(8.0, 4.0);

  // Distinct opaque color per cel texel (cx, cy) within the 4x2 cel.
  // Transparent texel at (cx: 1, cy: 0).
  List<int> celColor(int cx, int cy) {
    if (cx == 1 && cy == 0) return [0, 0, 0, 0];
    return [40 + cx * 50, 30 + cy * 90, 60 + cx * 20 + cy * 30, 255];
  }

  Future<ui.Image> buildPriorityImage() async {
    final bytes = Uint8List(playW * playH * 4);
    for (var y = 0; y < playH; y++) {
      for (var x = 0; x < playW; x++) {
        final i = (y * playW + x) * 4;
        bytes[i] = priorities[x] * 17;
        bytes[i + 1] = 0;
        bytes[i + 2] = 0;
        bytes[i + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, playW, playH, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img));
    return completer.future;
  }

  // Step priority for exact-boundary cases (f)-(h): column left of dstRect
  // (px 0) is 15 (> actorPri) so an off-by-one floor to the neighbour
  // wrongly discards the sprite's first column; inside dstRect is 4.
  List<int> stepPriorities() => const [15, 4, 4, 4, 4, 4, 4, 4];

  Future<ui.Image> buildStepPriorityImage() async {
    final step = stepPriorities();
    final bytes = Uint8List(playW * playH * 4);
    for (var y = 0; y < playH; y++) {
      for (var x = 0; x < playW; x++) {
        final i = (y * playW + x) * 4;
        bytes[i] = step[x] * 17;
        bytes[i + 1] = 0;
        bytes[i + 2] = 0;
        bytes[i + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, playW, playH, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img));
    return completer.future;
  }

  // Expected playfield pixel under [stepPriorities].
  List<int> expectedStepPlayfieldPixel(int px, int py) {
    final step = stepPriorities();
    final lx = px - 1;
    final ly = py - 1;
    final inDst = lx >= 0 && lx < 4 && ly >= 0 && ly < 2;
    if (!inDst) return bg;
    final c = celColor(lx, ly);
    if (c[3] == 0) return bg;
    if (step[px] > actorPri) return bg;
    return c;
  }

  Future<ui.Image> buildSpriteImage() async {
    const w = 8;
    const h = 2;
    final bytes = Uint8List(w * h * 4);
    // Fill atlas with junk so only the src rect's colors are correct.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        bytes[i] = 255;
        bytes[i + 1] = 255;
        bytes[i + 2] = 255;
        bytes[i + 3] = 255;
      }
    }
    for (var cy = 0; cy < 2; cy++) {
      for (var cx = 0; cx < 4; cx++) {
        final x = 2 + cx;
        final y = cy;
        final i = (y * w + x) * 4;
        final c = celColor(cx, cy);
        bytes[i] = c[0];
        bytes[i + 1] = c[1];
        bytes[i + 2] = c[2];
        bytes[i + 3] = c[3];
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, w, h, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img));
    return completer.future;
  }

  // Expected playfield-space pixel per the spec rule:
  // sprite texel iff alpha > 0 AND priAt <= actorPri, else bg.
  List<int> expectedPlayfieldPixel(int px, int py, {bool flipX = false}) {
    final lx = px - 1;
    final ly = py - 1;
    final inDst = lx >= 0 && lx < 4 && ly >= 0 && ly < 2;
    if (!inDst) return bg;
    var cx = lx;
    if (flipX) cx = 3 - cx;
    final c = celColor(cx, ly);
    if (c[3] == 0) return bg;
    if (priorities[px] > actorPri) return bg;
    return c;
  }

  Future<Uint8List> render({
    required ui.Image sprite,
    required ui.Image priority,
    required ui.FragmentShader shader,
    double scale = 1.0,
    bool flipX = false,
    Offset translateOffset = Offset.zero,
    required int imgW,
    required int imgH,
    Rect? srcRectOverride,
    Rect? dstRectOverride,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = Color.fromRGBO(bg[0], bg[1], bg[2], 1.0);
    final hasShake = translateOffset != Offset.zero;
    if (hasShake) {
      // Screen shake: bg covers the full image in untranslated space so
      // columns the shaken playfield does not reach stay bg.
      canvas.drawRect(
        Rect.fromLTWH(0.0, 0.0, imgW.toDouble(), imgH.toDouble()),
        bgPaint,
      );
      canvas.translate(translateOffset.dx, translateOffset.dy);
    }
    canvas.scale(scale);
    if (!hasShake) {
      canvas.drawRect(
        const Rect.fromLTWH(0.0, 0.0, 8.0, 4.0),
        bgPaint,
      );
    }
    drawPrioritySprite(
      canvas,
      shader,
      spriteImage: sprite,
      priorityImage: priority,
      srcRectPx: srcRectOverride ?? srcRect,
      dstRect: dstRectOverride ?? dstRect,
      playfieldSize: playfieldSize,
      actorPriority: actorPri,
      flipX: flipX,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(imgW, imgH);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  ui.FragmentShader? newShader(ui.FragmentProgram? program) {
    if (program == null) return null;
    return program.fragmentShader();
  }

  // Compare rendered bytes against the oracle; fail with first differing
  // pixel (x, y, expected, actual) and differing byte count.
  void compareBytes(
    Uint8List rendered,
    int imgW,
    int imgH,
    List<int> Function(int px, int py) oracleAt,
    double scale,
  ) {
    var diffBytes = 0;
    String? firstDiff;
    for (var py = 0; py < playH; py++) {
      for (var px = 0; px < playW; px++) {
        // Sample device pixel: exact pixel at scale 1, block center at
        // scale 3.
        final dx = scale == 1.0 ? px : (px * scale.toInt() + 1);
        final dy = scale == 1.0 ? py : (py * scale.toInt() + 1);
        final i = (dy * imgW + dx) * 4;
        final expected = oracleAt(px, py);
        final actual = [rendered[i], rendered[i + 1], rendered[i + 2], rendered[i + 3]];
        for (var c = 0; c < 4; c++) {
          if (actual[c] != expected[c]) diffBytes++;
        }
        if (firstDiff == null &&
            (actual[0] != expected[0] ||
                actual[1] != expected[1] ||
                actual[2] != expected[2] ||
                actual[3] != expected[3])) {
          firstDiff =
              'pixel ($px,$py) device($dx,$dy) expected=$expected actual=$actual';
        }
      }
    }
    expect(
      diffBytes,
      0,
      reason:
          '$diffBytes differing bytes; first differing pixel: $firstDiff',
    );
  }

  // Byte-compare output pixels at [points] against [oracleAtOutput]
  // (device coords) and return the differing-byte count plus up to 5 sample
  // diffs. Never asserts, so callers can skip-with-finding before asserting.
  _DiffReport computeDiffs(
    Uint8List rendered,
    int imgW,
    List<int> Function(int dx, int dy) oracleAtOutput,
    List<(int, int)> points,
  ) {
    var diffBytes = 0;
    final diffs = <String>[];
    for (final (dx, dy) in points) {
      final i = (dy * imgW + dx) * 4;
      final expected = oracleAtOutput(dx, dy);
      final actual = [rendered[i], rendered[i + 1], rendered[i + 2], rendered[i + 3]];
      for (var c = 0; c < 4; c++) {
        if (actual[c] != expected[c]) diffBytes++;
      }
      if (diffs.length < 5 &&
          (actual[0] != expected[0] ||
              actual[1] != expected[1] ||
              actual[2] != expected[2] ||
              actual[3] != expected[3])) {
        diffs.add('pixel ($dx,$dy) expected=$expected actual=$actual');
      }
    }
    return _DiffReport(diffBytes, diffs);
  }

  setUp(() {
    PrioritySpriteLoader.resetForTesting();
  });

  group('priority_sprite shader spike', () {
    test('loader initializes', () async {
      final program = await PrioritySpriteLoader.initialize();
      if (program == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      expect(PrioritySpriteLoader.isReady, isTrue);
    });

    test('(a) scale 1 priority masking with equality win', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildPriorityImage();
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: 1.0,
        imgW: playW,
        imgH: playH,
      );
      compareBytes(
        bytes,
        playW,
        playH,
        (px, py) => expectedPlayfieldPixel(px, py),
        1.0,
      );
    });

    test('(b) scale 3 block-center comparison', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildPriorityImage();
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: 3.0,
        imgW: playW * 3,
        imgH: playH * 3,
      );
      compareBytes(
        bytes,
        playW * 3,
        playH * 3,
        (px, py) => expectedPlayfieldPixel(px, py),
        3.0,
      );
    });

    test('(c) flipX at scale 1', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildPriorityImage();
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: 1.0,
        flipX: true,
        imgW: playW,
        imgH: playH,
      );
      compareBytes(
        bytes,
        playW,
        playH,
        (px, py) => expectedPlayfieldPixel(px, py, flipX: true),
        1.0,
      );
    });

    test('(d) fractional scale 2.5 - every output pixel', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildPriorityImage();
      const outW = 20;
      const outH = 10;
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: 2.5,
        imgW: outW,
        imgH: outH,
      );
      // Interior pixels must match the oracle exactly. Pixels straddling
      // the scaled dstRect boundary (device x 2.5..12.5, y 2.5..7.5) are
      // coverage-blended by the rasterizer's AA — the same edge behaviour
      // scaled drawImage exhibits today — so those may only be blends of
      // the colours meeting at that edge, never a wrong priority decision.
      const ex0 = 2.5, ex1 = 12.5, ey0 = 2.5, ey1 = 7.5;
      var interiorDiffs = 0;
      var boundaryDiffs = 0;
      final violations = <String>[];
      for (var dy = 0; dy < outH; dy++) {
        for (var dx = 0; dx < outW; dx++) {
          final px = ((dx + 0.5) / 2.5).floor();
          final py = ((dy + 0.5) / 2.5).floor();
          final expected = expectedPlayfieldPixel(px, py);
          final i = (dy * outW + dx) * 4;
          final actual = [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]];
          var same = true;
          for (var c = 0; c < 4; c++) {
            if (actual[c] != expected[c]) same = false;
          }
          if (same) continue;
          final cx = dx + 0.5, cy = dy + 0.5;
          final nearEdge = (cx - ex0).abs() <= 0.51 ||
              (cx - ex1).abs() <= 0.51 ||
              (cy - ey0).abs() <= 0.51 ||
              (cy - ey1).abs() <= 0.51;
          if (!nearEdge) {
            interiorDiffs++;
            violations.add('interior pixel ($dx,$dy) expected=$expected actual=$actual');
            continue;
          }
          boundaryDiffs++;
          final candidates = <List<int>>[
            expected,
            bg,
            for (final (ox, oy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
              if (px + ox >= 0 && px + ox < playW && py + oy >= 0 && py + oy < playH)
                expectedPlayfieldPixel(px + ox, py + oy),
          ];
          for (var c = 0; c < 4; c++) {
            final lo = candidates.map((k) => k[c]).reduce((a, b) => a < b ? a : b);
            final hi = candidates.map((k) => k[c]).reduce((a, b) => a > b ? a : b);
            if (actual[c] < lo - 1 || actual[c] > hi + 1) {
              violations.add('non-blend boundary pixel ($dx,$dy) c$c expected=$expected actual=$actual');
            }
          }
        }
      }
      expect(interiorDiffs, 0, reason: violations.join('; '));
      expect(violations, isEmpty);
      // AA boundary blends may vary by renderer; only their confinement matters.
      expect(boundaryDiffs, lessThanOrEqualTo(16));
    });

    test('(e) screen shake translate(2,1) then scale 2', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildPriorityImage();
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: 2.0,
        translateOffset: const Offset(2.0, 1.0),
        imgW: playW * 2,
        imgH: playH * 2,
      );
      // Oracle: production shake translates in DEVICE pixels before the
      // painter's inner scale (_GamePlayfieldPainter), so translate(2,1)
      // then scale(2) shifts the scene by (1, 0.5) playfield pixels; at
      // 2x2 block centers that samples as a (1,0) playfield shift. This
      // passing exact match proves fragCoord accounts for the translate.
      final report = computeDiffs(
        bytes,
        playW * 2,
        (dx, dy) {
          final bx = (dx - 1) ~/ 2;
          final by = (dy - 1) ~/ 2;
          final sx = bx - 1;
          final sy = by;
          if (sx < 0 || sy < 0 || sx >= playW || sy >= playH) return bg;
          return expectedPlayfieldPixel(sx, sy);
        },
        <(int, int)>[
          for (var by = 0; by < playH; by++)
            for (var bx = 0; bx < playW; bx++) (bx * 2 + 1, by * 2 + 1),
        ],
      );
      expect(report.diffBytes, 0, reason: report.diffs.join('; '));
    });

    // Exact-boundary helper for (f)-(h): compares EVERY device pixel
    // against the spec oracle px=floor((dx+0.5)/scale).
    Future<void> checkExactBoundary(double scale) async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildStepPriorityImage();
      final imgW = (playW * scale).round();
      final imgH = (playH * scale).round();
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: scale,
        imgW: imgW,
        imgH: imgH,
      );
      // Scaled dstRect in device coords; coverage is the geometric
      // overlap of device pixel [dx,dx+1)x[dy,dy+1) with it.
      final dstDx0 = dstRect.left * scale;
      final dstDy0 = dstRect.top * scale;
      final dstDx1 = (dstRect.left + dstRect.width) * scale;
      final dstDy1 = (dstRect.top + dstRect.height) * scale;
      var diffPixels = 0;
      var diffBytes = 0;
      var naiveDiffPixels = 0;
      var naiveDiffBytes = 0;
      final diffs = <String>[];
      for (var dy = 0; dy < imgH; dy++) {
        for (var dx = 0; dx < imgW; dx++) {
          final px = ((dx + 0.5) / scale).floor();
          final py = ((dy + 0.5) / scale).floor();
          if (px < 0 || py < 0 || px >= playW || py >= playH) continue;
          final sprite = expectedStepPlayfieldPixel(px, py);
          final i = (dy * imgW + dx) * 4;
          final actual = [
            bytes[i],
            bytes[i + 1],
            bytes[i + 2],
            bytes[i + 3]
          ];
          // Naive comparison (sprite vs bg, no coverage) recorded for the
          // before/after report.
          {
            var naivePixelDiff = 0;
            for (var c = 0; c < 4; c++) {
              if (actual[c] != sprite[c]) naivePixelDiff++;
            }
            if (naivePixelDiff > 0) {
              naiveDiffPixels++;
              naiveDiffBytes += naivePixelDiff;
            }
          }
          // Coverage-aware expectation: a spec-transparent fragment leaves
          // bg (coverage-independent); a spec-sprite fragment is blended
          // over bg by geometric coverage. Fully covered (cov==1) pixels
          // must match the sprite bytes exactly; straddlers must match the
          // blend to +/-1 rounding, so a discarded first column (pure bg)
          // still fails. This is strictly tighter than case (d)'s blend
          // range, which admits pure bg as a valid blend.
          final ox0 = dx > dstDx0 ? dx : dstDx0;
          final ox1 = dx + 1 < dstDx1 ? dx + 1 : dstDx1;
          final oy0 = dy > dstDy0 ? dy : dstDy0;
          final oy1 = dy + 1 < dstDy1 ? dy + 1 : dstDy1;
          var covX = ox1 - ox0;
          if (covX < 0) covX = 0.0;
          var covY = oy1 - oy0;
          if (covY < 0) covY = 0.0;
          final cov = covX * covY;
          final isSprite =
              sprite[3] != 0 && (sprite[0] != bg[0] || sprite[1] != bg[1] || sprite[2] != bg[2]);
          final List<int> expected =
              isSprite ? [for (var c = 0; c < 4; c++) (bg[c] * (1 - cov) + sprite[c] * cov).round()] : bg;
          var pixelDiff = 0;
          for (var c = 0; c < 4; c++) {
            if ((actual[c] - expected[c]).abs() > 1) pixelDiff++;
          }
          if (pixelDiff > 0) {
            diffPixels++;
            diffBytes += pixelDiff;
            if (diffs.length < 60) {
              diffs.add(
                  'device($dx,$dy) playfield($px,$py) cov=$cov expected=$expected actual=$actual');
            }
          }
        }
      }
      debugPrint(
          'scale=$scale img=${imgW}x$imgH diffPixels=$diffPixels diffBytes=$diffBytes naiveDiffPixels=$naiveDiffPixels naiveDiffBytes=$naiveDiffBytes');
      for (final d in diffs) {
        debugPrint('  $d');
      }
      // With the expanded, AA-off rect the shader's floored playfield
      // pixel decides coverage, so EVERY device pixel must match the
      // naive spec oracle exactly — no coverage blends remain. (The
      // coverage-aware counters above stay as diagnostics in the log.)
      expect(naiveDiffPixels, 0,
          reason:
              'scale=$scale naiveDiffPixels=$naiveDiffPixels naiveDiffBytes=$naiveDiffBytes coverageDiffs=$diffPixels: ${diffs.join('; ')}');
      expect(naiveDiffBytes, 0);
    }

    test('(f) exact boundary scale 6.5 left edge', () async {
      await checkExactBoundary(6.5);
    });

    test('(g) exact boundary scale 3.25 interior step', () async {
      await checkExactBoundary(3.25);
    });

    test('(h) exact boundary scale 5.5 left edge', () async {
      await checkExactBoundary(5.5);
    });

    // (i) Continuous 2x horizontal upscale at scale 3.25: a 2-texel-wide
    // source drawn into a 4-playfield-px dst (the AGI src:dst shape).
    // Every device pixel must match the center-sampled oracle exactly:
    // playfield columns 1,2 select source texel 0 and columns 3,4 select
    // source texel 1 (each texel covers exactly 2 playfield columns),
    // under the step priority (column 0 blocks, so an off-by-one read
    // of the neighbour discards the first column).
    test('(i) scale 3.25 src 2px into 4px dst, step priority', () async {
      final program = await PrioritySpriteLoader.initialize();
      final shader = newShader(program);
      if (shader == null) {
        markTestSkipped('FragmentProgram failed to load; see log');
        return;
      }
      final sprite = await buildSpriteImage();
      final priority = await buildStepPriorityImage();
      const scale = 3.25;
      const imgW = 26; // 8 * 3.25
      const imgH = 13; // 4 * 3.25
      final bytes = await render(
        sprite: sprite,
        priority: priority,
        shader: shader,
        scale: scale,
        imgW: imgW,
        imgH: imgH,
        srcRectOverride: const Rect.fromLTWH(2.0, 0.0, 2.0, 2.0),
        dstRectOverride: const Rect.fromLTWH(1.0, 1.0, 4.0, 2.0),
      );
      final step = stepPriorities();
      final diffs = <String>[];
      var diffPixels = 0;
      var diffBytes = 0;
      for (var dy = 0; dy < imgH; dy++) {
        for (var dx = 0; dx < imgW; dx++) {
          final px = ((dx + 0.5) / scale).floor();
          final py = ((dy + 0.5) / scale).floor();
          final lx = px - 1;
          final ly = py - 1;
          List<int> expected;
          if (lx < 0 || lx >= 4 || ly < 0 || ly >= 2) {
            expected = bg;
          } else {
            // Center-sampled continuous mapping: local center lx+0.5
            // maps to source offset 0.5*(lx+0.5), whose texel is
            // lx~/2 -- texels 0,0,1,1 across the four columns.
            final c = celColor(lx ~/ 2, ly);
            expected = (c[3] == 0 || step[px] > actorPri) ? bg : c;
          }
          final i = (dy * imgW + dx) * 4;
          final actual = [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]];
          var pixelDiff = 0;
          for (var c = 0; c < 4; c++) {
            if (actual[c] != expected[c]) pixelDiff++;
          }
          if (pixelDiff > 0) {
            diffPixels++;
            diffBytes += pixelDiff;
            if (diffs.length < 20) {
              diffs.add('device($dx,$dy) playfield($px,$py) expected=$expected actual=$actual');
            }
          }
        }
      }
      debugPrint('scale=$scale 2px-into-4px diffPixels=$diffPixels diffBytes=$diffBytes');
      for (final d in diffs) {
        debugPrint('  $d');
      }
      expect(diffPixels, 0, reason: '2px-into-4px diffPixels=$diffPixels: ${diffs.join('; ')}');
      expect(diffBytes, 0);
    });
  });
}
