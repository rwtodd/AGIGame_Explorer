import 'dart:typed_data';
import 'package:flutter_agigame/domain/sierra_view.dart';

/// An AGI VIEW cel. Native pixels are 160-wide; the atlas/browser doubles X.
class AgiViewCel extends SierraViewCel {
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

  const AgiViewCel({
    required this.width,
    required this.height,
    required this.transparentColor,
    this.isMirrored = false,
    this.mirrorLoop = 0,
    this.rawPixels,
    this.displaceX = 0,
    this.displaceY = 0,
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

  @override
  String toString() =>
      'AgiViewCel(${width}x$height, trans: $transparentColor, mirrored: $isMirrored${isMirrored ? ' from loop $mirrorLoop' : ''})';
}

/// An AGI animation loop containing multiple cels.
class AgiViewLoop extends SierraViewLoop {
  @override
  final int loopNumber;
  @override
  final List<AgiViewCel> cels;

  const AgiViewLoop({
    required this.loopNumber,
    required this.cels,
  });

  @override
  AgiViewCel? getCel(int index) {
    if (index >= 0 && index < cels.length) {
      return cels[index];
    }
    return null;
  }

  @override
  String toString() =>
      'AgiViewLoop(#$loopNumber, cels: ${cels.length}, maxDim: ${maxWidth}x$maxHeight)';
}

/// A Sierra AGI VIEW resource.
class AgiView extends SierraView {
  @override
  final int viewNumber;
  @override
  final String? description;
  @override
  final List<AgiViewLoop> loops;

  const AgiView({
    required this.viewNumber,
    this.description,
    required this.loops,
  });

  @override
  int get pixelScaleX => 2;

  @override
  bool get isSci => false;

  @override
  AgiViewLoop? getLoop(int index) {
    if (index >= 0 && index < loops.length) {
      return loops[index];
    }
    return null;
  }

  @override
  AgiViewCel? getCel(int loopIndex, int celIndex) {
    final loop = getLoop(loopIndex);
    return loop?.getCel(celIndex);
  }

  @override
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
