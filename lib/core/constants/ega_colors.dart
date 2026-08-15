import 'dart:ui';

/// Standard 16-color EGA palette used by Sierra AGI games.
class EgaColors {
  const EgaColors._();

  /// Standard EGA Flutter [Color] values (0 to 15).
  static const List<Color> palette = [
    Color(0xFF000000), // 0: Black
    Color(0xFF0000AA), // 1: Blue
    Color(0xFF00AA00), // 2: Green
    Color(0xFF00AAAA), // 3: Cyan
    Color(0xFFAA0000), // 4: Red
    Color(0xFFAA00AA), // 5: Magenta
    Color(0xFFAA5500), // 6: Brown
    Color(0xFFAAAAAA), // 7: Light Gray
    Color(0xFF555555), // 8: Dark Gray
    Color(0xFF5555FF), // 9: Light Blue
    Color(0xFF55FF55), // 10: Light Green
    Color(0xFF55FFFF), // 11: Light Cyan
    Color(0xFFFF5555), // 12: Light Red
    Color(0xFFFF55FF), // 13: Light Magenta
    Color(0xFFFFFF55), // 14: Yellow
    Color(0xFFFFFFFF), // 15: White
  ];

  /// Standard EGA ARGB 32-bit integers.
  static const List<int> argbValues = [
    0xFF000000, // 0: Black
    0xFF0000AA, // 1: Blue
    0xFF00AA00, // 2: Green
    0xFF00AAAA, // 3: Cyan
    0xFFAA0000, // 4: Red
    0xFFAA00AA, // 5: Magenta
    0xFFAA5500, // 6: Brown
    0xFFAAAAAA, // 7: Light Gray
    0xFF555555, // 8: Dark Gray
    0xFF5555FF, // 9: Light Blue
    0xFF55FF55, // 10: Light Green
    0xFF55FFFF, // 11: Light Cyan
    0xFFFF5555, // 12: Light Red
    0xFFFF55FF, // 13: Light Magenta
    0xFFFFFF55, // 14: Yellow
    0xFFFFFFFF, // 15: White
  ];

  /// Standard EGA RGBA byte tuples (Red, Green, Blue, Alpha=255) for direct buffer blitting.
  static const List<List<int>> rgbaBytes = [
    [0x00, 0x00, 0x00, 0xFF], // 0: Black
    [0x00, 0x00, 0xAA, 0xFF], // 1: Blue
    [0x00, 0xAA, 0x00, 0xFF], // 2: Green
    [0x00, 0xAA, 0xAA, 0xFF], // 3: Cyan
    [0xAA, 0x00, 0x00, 0xFF], // 4: Red
    [0xAA, 0x00, 0xAA, 0xFF], // 5: Magenta
    [0xAA, 0x55, 0x00, 0xFF], // 6: Brown
    [0xAA, 0xAA, 0xAA, 0xFF], // 7: Light Gray
    [0x55, 0x55, 0x55, 0xFF], // 8: Dark Gray
    [0x55, 0x55, 0xFF, 0xFF], // 9: Light Blue
    [0x55, 0xFF, 0x55, 0xFF], // 10: Light Green
    [0x55, 0xFF, 0xFF, 0xFF], // 11: Light Cyan
    [0xFF, 0x55, 0x55, 0xFF], // 12: Light Red
    [0xFF, 0x55, 0xFF, 0xFF], // 13: Light Magenta
    [0xFF, 0xFF, 0x55, 0xFF], // 14: Yellow
    [0xFF, 0xFF, 0xFF, 0xFF], // 15: White
  ];

  /// 32-bit RGBA packed values in little-endian order (0xAABBGGRR) for fast 32-bit writes into byte buffers.
  static const List<int> rgbaPacked = [
    0xFF000000, // 0: Black
    0xFFAA0000, // 1: Blue (B=AA, G=00, R=00, A=FF)
    0xFF00AA00, // 2: Green
    0xFFAAAA00, // 3: Cyan
    0xFF0000AA, // 4: Red (R=AA)
    0xFFAA00AA, // 5: Magenta
    0xFF0055AA, // 6: Brown
    0xFFAAAAAA, // 7: Light Gray
    0xFF555555, // 8: Dark Gray
    0xFFFF5555, // 9: Light Blue
    0xFF55FF55, // 10: Light Green
    0xFFFFFF55, // 11: Light Cyan
    0xFF5555FF, // 12: Light Red
    0xFFFF55FF, // 13: Light Magenta
    0xFF55FFFF, // 14: Yellow
    0xFFFFFFFF, // 15: White
  ];

  /// Control line debug colors:
  /// - 0: Trigger line (Cyan / Blue-green)
  /// - 1: Conditional barrier (Yellow)
  /// - 2: Unconditional barrier (Red)
  /// - 3: Water barrier (Blue)
  static const List<List<int>> controlRgbaBytes = [
    [0x00, 0xAA, 0xAA, 0xFF], // 0: Trigger (Cyan)
    [0xFF, 0xFF, 0x55, 0xFF], // 1: Conditional (Yellow)
    [0xFF, 0x55, 0x55, 0xFF], // 2: Unconditional (Red)
    [0x00, 0x00, 0xAA, 0xFF], // 3: Water (Blue)
  ];

  /// Gets a [Color] by EGA palette index (0..15).
  static Color getColor(int index) {
    if (index >= 0 && index < palette.length) {
      return palette[index];
    }
    return palette[0];
  }
}

/// AGI display resolution constants.
class AgiDisplay {
  const AgiDisplay._();

  /// Standard AGI native picture width (160 horizontal units).
  static const int nativeWidth = 160;

  /// Native AGI picture height (168 lines for playfield).
  static const int pictureHeight = 168;

  /// Native AGI total screen height (168 playfield + 32 status/input lines = 200).
  static const int screenHeight = 200;

  /// Pixel-doubled horizontal width (320x200 4:3 standard aspect ratio).
  static const int renderedWidth = 320;
  static const int renderedHeight = 200;

  /// Priority bands count (0 to 14 depth priority levels, 15 is base background).
  static const int priorityBands = 15;
}
