import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

/// Core rasterization routines for Sierra AGI picture drawing.
///
/// Implements Bresenham line drawing and non-allocating scanline stack flood fills.
class PicRasterizer {
  const PicRasterizer._();

  /// Draws a line between (x1, y1) and (x2, y2) using Bresenham's algorithm.
  static void drawLine(
    int x1,
    int y1,
    int x2,
    int y2,
    void Function(int x, int y) plotPoint,
  ) {
    int height = y2 - y1;
    int width = x2 - x1;
    int addY = 1;
    int addX = 1;
    if (height < 0) {
      addY = -1;
      height = -height;
    }
    if (width < 0) {
      addX = -1;
      width = -width;
    }

    int i = width;
    int threshold = width;
    int errX = 0;
    int errY = width ~/ 2;
    if (height > width) {
      i = height;
      threshold = height;
      errX = height ~/ 2;
      errY = 0;
    }
    int x = x1;
    int y = y1;
    plotPoint(x, y);
    while (i-- > 0) {
      errY += height;
      if (errY >= threshold) {
        errY -= threshold;
        y += addY;
      }
      errX += width;
      if (errX >= threshold) {
        errX -= threshold;
        x += addX;
      }
      plotPoint(x, y);
    }
  }

  /// Performs a non-allocating scanline stack flood fill from (startX, startY).
  static void scanlineFill({
    required int startX,
    required int startY,
    required Uint8List visualBuffer,
    required PriorityBuffer priorityBuffer,
    required int picColor,
    required int priColor,
    required void Function(int x, int y) plotPoint,
  }) {
    Uint8List rasterCheck;
    int searchingFor;

    if (picColor != 15 && picColor != -1) {
      rasterCheck = visualBuffer;
      searchingFor = 15;
    } else if (picColor == -1 && priColor != -1 && priColor != 4) {
      rasterCheck = priorityBuffer.pixels;
      searchingFor = 4;
    } else {
      return; // Nothing to do
    }

    const width = AgiDisplay.nativeWidth; // 160
    const height = AgiDisplay.pictureHeight; // 168

    if (startX < 0 || startX >= width || startY < 0 || startY >= height) {
      return;
    }

    final startIndex = startY * width + startX;
    if (rasterCheck[startIndex] != searchingFor) return;

    // Use a flat integer stack (SMI) to avoid heap object allocations
    final stack = <int>[];
    stack.add((startY << 8) | startX);

    while (stack.isNotEmpty) {
      final packed = stack.removeLast();
      final py = packed >> 8;
      final px = packed & 0xFF;

      final rowOffset = py * width;
      if (rasterCheck[rowOffset + px] != searchingFor) continue;

      // Scan left to find the start of the contiguous span
      var left = px;
      while (left > 0 && rasterCheck[rowOffset + (left - 1)] == searchingFor) {
        left--;
      }

      // Scan right, plotting pixels and checking spans above and below
      var right = left;
      bool spanAbove = false;
      bool spanBelow = false;

      while (right < width && rasterCheck[rowOffset + right] == searchingFor) {
        plotPoint(right, py);

        // Check pixel above
        if (py > 0) {
          final aboveIdx = (py - 1) * width + right;
          if (rasterCheck[aboveIdx] == searchingFor) {
            if (!spanAbove) {
              stack.add(((py - 1) << 8) | right);
              spanAbove = true;
            }
          } else {
            spanAbove = false;
          }
        }

        // Check pixel below
        if (py < height - 1) {
          final belowIdx = (py + 1) * width + right;
          if (rasterCheck[belowIdx] == searchingFor) {
            if (!spanBelow) {
              stack.add(((py + 1) << 8) | right);
              spanBelow = true;
            }
          } else {
            spanBelow = false;
          }
        }

        right++;
      }
    }
  }
}
