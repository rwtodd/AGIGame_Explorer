import 'dart:typed_data';
import 'package:flutter_agigame/domain/sierra_view.dart';

/// An SCI0 EGA VIEW cel. Native pixels are already 320-space (no X doubling).
class SciViewCel extends SierraViewCel {
  @override
  final int width;
  @override
  final int height;
  @override
  final int transparentColor;
  @override
  final bool isMirrored;
  @override
  final int mirrorLoop;
  @override
  final Uint8List? rawPixels;
  @override
  final int displaceX;
  @override
  final int displaceY;

  const SciViewCel({
    required this.width,
    required this.height,
    required this.transparentColor,
    this.isMirrored = false,
    this.mirrorLoop = 0,
    this.rawPixels,
    this.displaceX = 0,
    this.displaceY = 0,
  });

  factory SciViewCel.forward({
    required int width,
    required int height,
    required int transparentColor,
    required Uint8List rawPixels,
    int displaceX = 0,
    int displaceY = 0,
  }) {
    return SciViewCel(
      width: width,
      height: height,
      transparentColor: transparentColor,
      isMirrored: false,
      mirrorLoop: 0,
      rawPixels: rawPixels,
      displaceX: displaceX,
      displaceY: displaceY,
    );
  }

  factory SciViewCel.mirrored({
    required int width,
    required int height,
    required int transparentColor,
    required int mirrorLoop,
    int displaceX = 0,
    int displaceY = 0,
  }) {
    return SciViewCel(
      width: width,
      height: height,
      transparentColor: transparentColor,
      isMirrored: true,
      mirrorLoop: mirrorLoop,
      rawPixels: null,
      displaceX: displaceX,
      displaceY: displaceY,
    );
  }

  @override
  String toString() =>
      'SciViewCel(${width}x$height, trans: $transparentColor, dx: $displaceX, dy: $displaceY, '
      'mirrored: $isMirrored${isMirrored ? ' from loop $mirrorLoop' : ''})';
}

/// An SCI0 animation loop.
class SciViewLoop extends SierraViewLoop {
  @override
  final int loopNumber;
  @override
  final List<SciViewCel> cels;

  /// True when the view header `mirrorBits` flag is set for this loop.
  final bool isMirrorLoop;

  const SciViewLoop({
    required this.loopNumber,
    required this.cels,
    this.isMirrorLoop = false,
  });

  @override
  SciViewCel? getCel(int index) {
    if (index >= 0 && index < cels.length) {
      return cels[index];
    }
    return null;
  }

  @override
  String toString() =>
      'SciViewLoop(#$loopNumber, cels: ${cels.length}, mirrored: $isMirrorLoop, maxDim: ${maxWidth}x$maxHeight)';
}

/// A Sierra SCI0 / SCI1-EGA VIEW resource (`kViewEga`).
class SciView extends SierraView {
  @override
  final int viewNumber;
  @override
  final String? description;
  @override
  final List<SciViewLoop> loops;

  /// Header flags. Bit 0x40 = uncompressed (VGA-only in ScummVM; EGA always RLE).
  /// Bit 0x80 = VGA view stored in an EGA game (rejected by the EGA parser).
  final int flags;

  /// Bit N set means loop N is a horizontal mirror of another loop that shares
  /// its loop-directory offset.
  final int mirrorBits;

  /// Header version word. `1` is SCI1.1 (`kViewVga11`) and is rejected here.
  final int version;

  /// Palette offset. Ignored for true SCI0 EGA; SCI1 EGA / QFG2 mapping is later.
  final int paletteOffset;

  const SciView({
    required this.viewNumber,
    this.description,
    required this.loops,
    this.flags = 0,
    this.mirrorBits = 0,
    this.version = 0,
    this.paletteOffset = 0,
  });

  @override
  int get pixelScaleX => 1;

  @override
  bool get isSci => true;

  @override
  SciViewLoop? getLoop(int index) {
    if (index >= 0 && index < loops.length) {
      return loops[index];
    }
    return null;
  }

  @override
  SciViewCel? getCel(int loopIndex, int celIndex) {
    final loop = getLoop(loopIndex);
    return loop?.getCel(celIndex);
  }

  @override
  SciViewCel? resolveSourceCel(int loopIndex, int celIndex) {
    final cel = getCel(loopIndex, celIndex);
    if (cel == null) return null;
    if (!cel.isMirrored) return cel;
    return getCel(cel.mirrorLoop, celIndex);
  }

  @override
  String toString() =>
      'SciView(#$viewNumber, loops: ${loops.length}, totalCels: $totalCelsCount, '
      'mirrorBits: 0x${mirrorBits.toRadixString(16)})';
}
