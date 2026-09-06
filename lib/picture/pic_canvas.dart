import 'dart:typed_data';

import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';
import 'package:flutter_agigame/picture/pic_pen.dart';
import 'package:flutter_agigame/picture/pic_rasterizer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// Mutable 160x168 visual/priority raster used by both the full AGI interpreter
/// and vector-step replay. Counterpart of [SciPicCanvas].
class AgiPicCanvas {
  final bool isV3;
  final Uint8List visualBuffer;
  final PriorityBuffer priorityBuffer;
  int picColor = -1;
  int priColor = -1;

  late final RectanglePen rectanglePen;
  late final PicPen circlePen;
  late PicPen currentPen;
  late SplatterPattern splatterPattern;
  late PenPattern currentPattern;

  AgiPicCanvas({required this.isV3})
      : visualBuffer = Uint8List(AgiDisplay.nativeWidth * AgiDisplay.pictureHeight),
        priorityBuffer = PriorityBuffer() {
    visualBuffer.fillRange(0, visualBuffer.length, 15);
    rectanglePen = RectanglePen()..size = 0;
    circlePen = (isV3 ? V3CirclePen() : CirclePen())..size = 0;
    currentPen = rectanglePen;
    splatterPattern = SplatterPattern();
    currentPattern = SolidPenPattern.instance;
  }

  static int clipX(int x) => x < 0
      ? 0
      : (x >= AgiDisplay.nativeWidth ? AgiDisplay.nativeWidth - 1 : x);

  static int clipY(int y) => y < 0
      ? 0
      : (y >= AgiDisplay.pictureHeight ? AgiDisplay.pictureHeight - 1 : y);

  void plotPoint(int x, int y) {
    if (x < 0 ||
        x >= AgiDisplay.nativeWidth ||
        y < 0 ||
        y >= AgiDisplay.pictureHeight) {
      return;
    }
    final idx = y * AgiDisplay.nativeWidth + x;
    if (picColor != -1) {
      visualBuffer[idx] = picColor;
    }
    if (priColor != -1) {
      priorityBuffer.pixels[idx] = priColor;
    }
  }

  void drawLine(int x1, int y1, int x2, int y2) {
    PicRasterizer.drawLine(x1, y1, x2, y2, plotPoint);
  }

  void fill(int startX, int startY) {
    PicRasterizer.scanlineFill(
      startX: startX,
      startY: startY,
      visualBuffer: visualBuffer,
      priorityBuffer: priorityBuffer,
      picColor: picColor,
      priColor: priColor,
      plotPoint: plotPoint,
    );
  }

  void plotPen(int x, int y) {
    currentPen.drawAt(plotPoint, x, y, currentPattern);
  }

  /// [copyBuffers] is false when the canvas is discarded after interpret, so
  /// [AgiPic] can take ownership of the backing stores.
  AgiPic toAgiPic({bool computeSlices = true, bool copyBuffers = true}) {
    final slices = computeSlices
        ? PictureSlicer.slice(
            visualPixels: visualBuffer,
            priorityBuffer: priorityBuffer,
          )
        : <int, PictureSlice>{};

    return AgiPic(
      visualPixels: copyBuffers ? Uint8List.fromList(visualBuffer) : visualBuffer,
      priorityBuffer: copyBuffers ? priorityBuffer.clone() : priorityBuffer,
      slices: slices,
    );
  }
}
