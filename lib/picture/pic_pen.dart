import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';

/// Base class for all AGI picture pens (rectangles and circles).
abstract class PicPen {
  /// Size class (0 to 7).
  int _size = 0;

  int get size => _size;

  /// Sets the pen size class (0 to 7).
  set size(int sz) {
    if (sz < 0 || sz > 7) {
      throw ArgumentError.value(sz, 'size', 'Pen size must be between 0 and 7');
    }
    _size = sz;
  }

  /// Width of the pen in native pixels.
  int get width => _size + 1;

  /// Height of the pen in native pixels.
  int get height => _size * 2 + 1;

  /// Vertical offset of the pen's center point.
  int get verticalOffset => _size;

  /// Horizontal offset of the pen's center point.
  int get horizontalOffset => (_size + 1) ~/ 2;

  /// Number of pixels to skip from the left edge on [row].
  int pixelsToSkip(int row);

  /// Number of pixels to plot on [row].
  int pixelsToPlot(int row);

  /// Draws this pen shape centered at `(x, y)` onto the given [plotPoint] callback.
  void drawAt(
    void Function(int x, int y) plotPoint,
    int x,
    int y,
    PenPattern pattern,
  ) {
    const picWidth = AgiDisplay.nativeWidth; // 160
    const picHeight = AgiDisplay.pictureHeight; // 168

    final numRows = height;
    final numCols = width;

    // Step 1: Calculate and clamp top-left bounding box so it fits on screen
    int left = x - horizontalOffset;
    if (left < 0) {
      left = 0;
    } else if (left + numCols >= picWidth) {
      left = picWidth - numCols;
    }

    int top = y - verticalOffset;
    if (top < 0) {
      top = 0;
    } else if (top + numRows >= picHeight) {
      top = picHeight - numRows;
    }

    // Step 2: Iterate over the shape rows and columns
    final iterator = pattern.createIterator();
    for (int row = 0; row < numRows; row++) {
      final skipped = pixelsToSkip(row);
      final count = skipped + pixelsToPlot(row);
      for (int col = skipped; col < count; col++) {
        if (iterator.moveNext() && iterator.current) {
          plotPoint(left + col, top + row);
        }
      }
    }
  }
}

/// A rectangular pen shape.
class RectanglePen extends PicPen {
  @override
  int pixelsToSkip(int row) => 0;

  @override
  int pixelsToPlot(int row) => size + 1;
}

/// A circular pen shape using Sierra's rasterization skip/plot tables.
class CirclePen extends PicPen {
  static const List<List<int>> skips = [
    [0], // size 0 (width 1)
    [0, 0, 0], // size 1 (width 2)
    [1, 0, 0, 0, 1], // size 2 (width 3)
    [1, 1, 0, 0, 0, 1, 1], // size 3 (width 4)
    [2, 1, 0, 0, 0, 0, 0, 1, 2], // size 4 (width 5)
    [2, 1, 1, 1, 0, 0, 0, 1, 1, 1, 2], // size 5 (width 6)
    [2, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 2], // size 6 (width 7)
    [3, 2, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 2, 3], // size 7 (width 8)
  ];

  static const List<List<int>> plots = [
    [1], // size 0 (width 1)
    [2, 2, 2], // size 1 (width 2)
    [1, 3, 3, 3, 1], // size 2 (width 3)
    [2, 2, 4, 4, 4, 2, 2], // size 3 (width 4)
    [1, 3, 5, 5, 5, 5, 5, 3, 1], // size 4 (width 5)
    [2, 4, 4, 4, 6, 6, 6, 4, 4, 4, 2], // size 5 (width 6)
    [3, 5, 5, 5, 7, 7, 7, 7, 7, 5, 5, 5, 3], // size 6 (width 7)
    [2, 4, 6, 6, 6, 8, 8, 8, 8, 8, 6, 6, 6, 4, 2], // size 7 (width 8)
  ];

  @override
  int pixelsToSkip(int row) => skips[size][row];

  @override
  int pixelsToPlot(int row) => plots[size][row];
}

/// AGI V3 circular pen variation (size 1 circle pen only plots row 1).
class V3CirclePen extends CirclePen {
  @override
  int pixelsToPlot(int row) {
    if (size == 1 && row != 1) return 0;
    return super.pixelsToPlot(row);
  }
}
