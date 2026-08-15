import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';

/// Memory buffer representing the 160x168 (and 320x200 renderable) AGI Priority Screen.
///
/// Priority values in AGI serve dual purposes:
/// - Values 0 to 3 are **Control Lines** (collision barriers, water, script triggers).
/// - Values 4 to 14 are **Depth Priority Bands** (Z-sorting depth planes sloping toward the camera).
/// - Value 15 is **Unconditional Background** (sky, horizon, drawn behind everything).
///
/// When an actor or visual element sits on a control line (< 4), its visual depth
/// is derived by scanning down the column to find the underlying depth band (>= 4).
class PriorityBuffer {
  /// Width in native AGI units (160).
  static const int width = AgiDisplay.nativeWidth;

  /// Height in native AGI units (168).
  static const int height = AgiDisplay.pictureHeight;

  /// Total number of pixels in the 160x168 buffer (26,880 bytes).
  static const int bufferSize = width * height;

  /// Raw byte buffer holding priority values 0 to 15.
  final Uint8List pixels;

  /// Creates a new priority buffer, defaulting all pixels to priority 4 (the standard AGI default).
  PriorityBuffer([Uint8List? initialPixels])
      : pixels = initialPixels ?? Uint8List(bufferSize) {
    if (initialPixels == null) {
      pixels.fillRange(0, bufferSize, 4);
    } else if (initialPixels.length != bufferSize) {
      throw ArgumentError(
        'PriorityBuffer expected $bufferSize bytes, got ${initialPixels.length}',
      );
    }
  }

  /// Creates a copy of this priority buffer.
  PriorityBuffer clone() {
    final copy = Uint8List(bufferSize);
    copy.setAll(0, pixels);
    return PriorityBuffer(copy);
  }

  /// Clears the priority buffer to the default priority 4.
  void clear() {
    pixels.fillRange(0, bufferSize, 4);
  }

  /// Gets the raw priority value (0..15) at index [idx].
  int priorityAtIndex(int idx) {
    if (idx < 0 || idx >= bufferSize) return 4;
    return pixels[idx];
  }

  /// Gets the raw priority value (0..15) at `(x, y)`.
  int priorityAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 4;
    return pixels[y * width + x];
  }

  /// Sets the raw priority value at `(x, y)`.
  void setPriorityAt(int x, int y, int priority) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      pixels[y * width + x] = priority & 0x0F;
    }
  }

  /// Computes the effective depth priority (4..15) at buffer index [idx].
  ///
  /// If the pixel at [idx] is a control line (< 4), we scan downwards along the column
  /// until we find the first underlying depth band (>= 4). If none is found before
  /// reaching the bottom of the screen, 15 (background) is returned.
  int effectivePriorityAtIndex(int idx) {
    if (idx < 0 || idx >= bufferSize) return 4;
    int answer = pixels[idx];
    if (answer >= 4) return answer;

    // Scan down the column
    int current = idx + width;
    while (answer < 4 && current < bufferSize) {
      answer = pixels[current];
      current += width;
    }
    return (answer >= 4) ? answer : 15;
  }

  /// Computes the effective depth priority (4..15) at `(x, y)`.
  int effectivePriorityAt(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 4;
    return effectivePriorityAtIndex(y * width + x);
  }

  /// Checks if `(x, y)` is a trigger control line (priority 0).
  bool isTrigger(int x, int y) => priorityAt(x, y) == 0;

  /// Checks if `(x, y)` is a conditional barrier (priority 1).
  bool isConditionalBarrier(int x, int y) => priorityAt(x, y) == 1;

  /// Checks if `(x, y)` is an unconditional barrier (priority 2).
  bool isUnconditionalBarrier(int x, int y) => priorityAt(x, y) == 2;

  /// Checks if `(x, y)` is a water surface/barrier (priority 3).
  bool isWater(int x, int y) => priorityAt(x, y) == 3;

  /// Checks if `(x, y)` is any control line (0, 1, 2, or 3).
  bool isControlLine(int x, int y) => priorityAt(x, y) < 4;

  /// Standard walkability check: walkable if not blocked by conditional (1) or unconditional (2) barrier.
  bool isWalkable(int x, int y, {bool allowConditional = false}) {
    final p = priorityAt(x, y);
    if (p == 2) return false;
    if (p == 1 && !allowConditional) return false;
    return true;
  }

  /// Renders a color-coded 320x200 RGBA buffer visualizing the depth priority map.
  Uint8List renderPriorityMapRgba() {
    const renderWidth = AgiDisplay.renderedWidth; // 320
    const renderHeight = AgiDisplay.renderedHeight; // 200
    final outBytes = Uint8List(renderWidth * renderHeight * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pri = pixels[y * width + x];
        final col = EgaColors.rgbaBytes[pri];

        // Pixel-doubling: 2 pixels horizontally in 320x200
        final outIdx1 = (y * renderWidth + (x * 2)) * 4;
        final outIdx2 = outIdx1 + 4;

        outBytes[outIdx1 + 0] = col[0];
        outBytes[outIdx1 + 1] = col[1];
        outBytes[outIdx1 + 2] = col[2];
        outBytes[outIdx1 + 3] = col[3];

        outBytes[outIdx2 + 0] = col[0];
        outBytes[outIdx2 + 1] = col[1];
        outBytes[outIdx2 + 2] = col[2];
        outBytes[outIdx2 + 3] = col[3];
      }
    }
    return outBytes;
  }

  /// Renders a color-coded 320x200 RGBA buffer visualizing only the control lines (0..3),
  /// with all non-control pixels remaining transparent.
  Uint8List renderControlMapRgba() {
    const renderWidth = AgiDisplay.renderedWidth; // 320
    const renderHeight = AgiDisplay.renderedHeight; // 200
    final outBytes = Uint8List(renderWidth * renderHeight * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pri = pixels[y * width + x];
        if (pri < 4) {
          final col = EgaColors.controlRgbaBytes[pri];
          final outIdx1 = (y * renderWidth + (x * 2)) * 4;
          final outIdx2 = outIdx1 + 4;

          outBytes[outIdx1 + 0] = col[0];
          outBytes[outIdx1 + 1] = col[1];
          outBytes[outIdx1 + 2] = col[2];
          outBytes[outIdx1 + 3] = col[3];

          outBytes[outIdx2 + 0] = col[0];
          outBytes[outIdx2 + 1] = col[1];
          outBytes[outIdx2 + 2] = col[2];
          outBytes[outIdx2 + 3] = col[3];
        }
      }
    }
    return outBytes;
  }
}
