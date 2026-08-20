import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';

/// Represents an individual cel (frame) within a VIEW loop.
class AgiViewCel {
  final int width;
  final int height;
  final int transparentColor;
  final bool isMirrored;
  final int mirrorLoop;
  final Uint8List? rawPixels;

  const AgiViewCel({
    required this.width,
    required this.height,
    required this.transparentColor,
    this.isMirrored = false,
    this.mirrorLoop = 0,
    this.rawPixels,
  });

  /// Factory for a forward (unmirrored) cel with direct pixel data.
  factory AgiViewCel.forward({
    required int width,
    required int height,
    required int transparentColor,
    required Uint8List rawPixels,
  }) {
    return AgiViewCel(
      width: width,
      height: height,
      transparentColor: transparentColor,
      isMirrored: false,
      mirrorLoop: 0,
      rawPixels: rawPixels,
    );
  }

  /// Factory for a mirrored cel referencing a source loop.
  factory AgiViewCel.mirrored({
    required int width,
    required int height,
    required int transparentColor,
    required int mirrorLoop,
  }) {
    return AgiViewCel(
      width: width,
      height: height,
      transparentColor: transparentColor,
      isMirrored: true,
      mirrorLoop: mirrorLoop,
      rawPixels: null,
    );
  }

  /// Resolves the actual un-flipped pixel buffer (from this cel or its source cel if mirrored).
  Uint8List getUnflippedPixels({AgiView? parentView, int celIndex = 0}) {
    if (!isMirrored) {
      if (rawPixels == null) {
        throw const AgiException('Forward cel is missing raw pixel data.');
      }
      return rawPixels!;
    }

    if (parentView == null) {
      throw const AgiException('Parent view required to resolve mirrored cel pixels.');
    }

    if (mirrorLoop < 0 || mirrorLoop >= parentView.loops.length) {
      throw AgiException('Invalid mirror loop index: $mirrorLoop');
    }

    final sourceLoop = parentView.loops[mirrorLoop];
    if (celIndex < 0 || celIndex >= sourceLoop.cels.length) {
      throw AgiException('Invalid cel index $celIndex in mirror loop $mirrorLoop');
    }

    final sourceCel = sourceLoop.cels[celIndex];
    return sourceCel.getUnflippedPixels(parentView: parentView, celIndex: celIndex);
  }

  /// Resolves the final pixels for this cel. If mirrored, returns horizontally flipped pixels.
  Uint8List getPixels({AgiView? parentView, int celIndex = 0}) {
    final unflipped = getUnflippedPixels(parentView: parentView, celIndex: celIndex);
    if (!isMirrored) {
      return unflipped;
    }

    // Horizontally flip the pixel buffer
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
  /// [scaleX] and [scaleY] allow integer pixel scaling (e.g. 2x horizontal scaling for AGI 160->320 aspect ratio).
  Uint8List toRgba({
    AgiView? parentView,
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

  @override
  String toString() =>
      'AgiViewCel(${width}x$height, trans: $transparentColor, mirrored: $isMirrored${isMirrored ? ' from loop $mirrorLoop' : ''})';
}

/// Represents an animation loop containing multiple cels.
class AgiViewLoop {
  final int loopNumber;
  final List<AgiViewCel> cels;

  const AgiViewLoop({
    required this.loopNumber,
    required this.cels,
  });

  int get celCount => cels.length;

  /// Maximum height among all cels in this loop.
  int get maxHeight =>
      cels.isEmpty ? 0 : cels.map((c) => c.height).reduce((a, b) => a > b ? a : b);

  /// Maximum width among all cels in this loop.
  int get maxWidth =>
      cels.isEmpty ? 0 : cels.map((c) => c.width).reduce((a, b) => a > b ? a : b);

  AgiViewCel? getCel(int index) {
    if (index >= 0 && index < cels.length) {
      return cels[index];
    }
    return null;
  }

  @override
  String toString() => 'AgiViewLoop(#$loopNumber, cels: ${cels.length}, maxDim: ${maxWidth}x$maxHeight)';
}

/// Represents a Sierra AGI VIEW resource.
class AgiView {
  final int viewNumber;
  final String? description;
  final List<AgiViewLoop> loops;

  const AgiView({
    required this.viewNumber,
    this.description,
    required this.loops,
  });

  int get loopCount => loops.length;

  int get totalCelsCount => loops.fold(0, (sum, loop) => sum + loop.celCount);

  AgiViewLoop? getLoop(int index) {
    if (index >= 0 && index < loops.length) {
      return loops[index];
    }
    return null;
  }

  AgiViewCel? getCel(int loopIndex, int celIndex) {
    final loop = getLoop(loopIndex);
    return loop?.getCel(celIndex);
  }

  /// Resolves the actual unmirrored source cel for a given (loop, cel) pair.
  AgiViewCel? resolveSourceCel(int loopIndex, int celIndex) {
    final cel = getCel(loopIndex, celIndex);
    if (cel == null) return null;
    if (!cel.isMirrored) return cel;
    return getCel(cel.mirrorLoop, celIndex);
  }

  @override
  String toString() =>
      'AgiView(#$viewNumber, loops: ${loops.length}, totalCels: $totalCelsCount, desc: ${description != null ? '"$description"' : 'none'})';
}
