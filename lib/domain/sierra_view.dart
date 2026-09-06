import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';

/// Shared cel (animation frame) for AGI and SCI VIEW resources.
///
/// Pixel buffers are native engine pixels (AGI 160-space, SCI 320-space).
/// Horizontal display doubling is [SierraView.pixelScaleX], not baked in here.
abstract class SierraViewCel {
  const SierraViewCel();

  int get width;
  int get height;
  int get transparentColor;
  bool get isMirrored;
  int get mirrorLoop;
  Uint8List? get rawPixels;

  /// Placement offset from the cel's bottom-center origin. AGI is always 0;
  /// SCI0 stores signed [displaceX] and unsigned [displaceY] on the cel.
  int get displaceX;
  int get displaceY;

  /// Resolves the actual un-flipped pixel buffer (from this cel or its source
  /// cel if mirrored).
  Uint8List getUnflippedPixels({SierraView? parentView, int celIndex = 0}) {
    if (!isMirrored) {
      if (rawPixels == null) {
        throw const AgiException('Forward cel is missing raw pixel data.');
      }
      return rawPixels!;
    }

    if (parentView == null) {
      throw const AgiException('Parent view required to resolve mirrored cel pixels.');
    }

    if (mirrorLoop < 0 || mirrorLoop >= parentView.loopCount) {
      throw AgiException('Invalid mirror loop index: $mirrorLoop');
    }

    final sourceLoop = parentView.getLoop(mirrorLoop);
    if (sourceLoop == null) {
      throw AgiException('Invalid mirror loop index: $mirrorLoop');
    }
    if (celIndex < 0 || celIndex >= sourceLoop.celCount) {
      throw AgiException('Invalid cel index $celIndex in mirror loop $mirrorLoop');
    }

    final sourceCel = sourceLoop.getCel(celIndex);
    if (sourceCel == null) {
      throw AgiException('Invalid cel index $celIndex in mirror loop $mirrorLoop');
    }
    return sourceCel.getUnflippedPixels(parentView: parentView, celIndex: celIndex);
  }

  /// Resolves the final pixels for this cel. If mirrored, returns horizontally
  /// flipped pixels.
  Uint8List getPixels({SierraView? parentView, int celIndex = 0}) {
    final unflipped = getUnflippedPixels(parentView: parentView, celIndex: celIndex);
    if (!isMirrored) {
      return unflipped;
    }

    final flipped = Uint8List(unflipped.length);
    for (var y = 0; y < height; y++) {
      final rowBase = y * width;
      for (var x = 0; x < width; x++) {
        flipped[rowBase + x] = unflipped[rowBase + (width - 1 - x)];
      }
    }
    return flipped;
  }

  /// Converts the cel into a 32-bit RGBA pixel byte array.
  ///
  /// Transparent color pixels receive alpha = 0.
  /// If [flipHorizontal] is true, pixels are horizontally mirrored.
  /// [scaleX] and [scaleY] allow integer pixel scaling (e.g. 2x horizontal
  /// scaling for AGI 160→320 aspect ratio; SCI uses 1).
  Uint8List toRgba({
    SierraView? parentView,
    int celIndex = 0,
    List<Color>? palette,
    bool? flipHorizontal,
    int scaleX = 1,
    int scaleY = 1,
  }) {
    final effectivePalette = palette ?? EgaColors.palette;
    final shouldFlip = flipHorizontal ?? isMirrored;
    final basePixels = getUnflippedPixels(parentView: parentView, celIndex: celIndex);

    final outWidth = width * scaleX;
    final outHeight = height * scaleY;
    final rgba = Uint8List(outWidth * outHeight * 4);

    for (var y = 0; y < height; y++) {
      final srcRowOffset = y * width;
      for (var sy = 0; sy < scaleY; sy++) {
        final dstRowOffset = ((y * scaleY) + sy) * outWidth;
        for (var x = 0; x < width; x++) {
          final srcX = shouldFlip ? (width - 1 - x) : x;
          final colorIdx = basePixels[srcRowOffset + srcX] & 0x0F;

          int r = 0;
          int g = 0;
          int b = 0;
          int a = 0;

          if (colorIdx != transparentColor) {
            if (palette != null) {
              final color = colorIdx < effectivePalette.length
                  ? effectivePalette[colorIdx]
                  : effectivePalette[0];
              r = (color.r * 255.0).round().clamp(0, 255);
              g = (color.g * 255.0).round().clamp(0, 255);
              b = (color.b * 255.0).round().clamp(0, 255);
            } else {
              final col = colorIdx < EgaColors.rgbaBytes.length
                  ? EgaColors.rgbaBytes[colorIdx]
                  : EgaColors.rgbaBytes[0];
              r = col[0];
              g = col[1];
              b = col[2];
            }
            a = 255;
          }

          for (var sx = 0; sx < scaleX; sx++) {
            final dstOffset = (dstRowOffset + (x * scaleX) + sx) * 4;
            rgba[dstOffset] = r;
            rgba[dstOffset + 1] = g;
            rgba[dstOffset + 2] = b;
            rgba[dstOffset + 3] = a;
          }
        }
      }
    }

    return rgba;
  }
}

/// Shared animation loop (a sequence of cels) for AGI and SCI VIEW resources.
abstract class SierraViewLoop {
  const SierraViewLoop();

  int get loopNumber;
  List<SierraViewCel> get cels;

  int get celCount => cels.length;

  int get maxHeight =>
      cels.isEmpty ? 0 : cels.map((c) => c.height).reduce((a, b) => a > b ? a : b);

  int get maxWidth =>
      cels.isEmpty ? 0 : cels.map((c) => c.width).reduce((a, b) => a > b ? a : b);

  SierraViewCel? getCel(int index) {
    if (index >= 0 && index < cels.length) {
      return cels[index];
    }
    return null;
  }
}

/// Shared VIEW resource: loops of cels used for ego, NPCs, props, and icons.
abstract class SierraView {
  const SierraView();

  int get viewNumber;
  String? get description;
  List<SierraViewLoop> get loops;

  /// Native-to-display horizontal scale. AGI cels are 160-wide (2); SCI is 1.
  int get pixelScaleX;

  bool get isSci;

  int get loopCount => loops.length;

  int get totalCelsCount => loops.fold(0, (sum, loop) => sum + loop.celCount);

  SierraViewLoop? getLoop(int index) {
    if (index >= 0 && index < loops.length) {
      return loops[index];
    }
    return null;
  }

  SierraViewCel? getCel(int loopIndex, int celIndex) {
    final loop = getLoop(loopIndex);
    return loop?.getCel(celIndex);
  }

  /// Resolves the actual unmirrored source cel for a given (loop, cel) pair.
  SierraViewCel? resolveSourceCel(int loopIndex, int celIndex) {
    final cel = getCel(loopIndex, celIndex);
    if (cel == null) return null;
    if (!cel.isMirrored) return cel;
    return getCel(cel.mirrorLoop, celIndex);
  }
}
