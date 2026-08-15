import 'dart:ui';

/// Standard 16-color EGA palette used by Sierra AGI games.
class EgaColors {
  const EgaColors._();

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

  static const List<int> argbValues = [
    0xFF000000,
    0xFF0000AA,
    0xFF00AA00,
    0xFF00AAAA,
    0xFFAA0000,
    0xFFAA00AA,
    0xFFAA5500,
    0xFFAAAAAA,
    0xFF555555,
    0xFF5555FF,
    0xFF55FF55,
    0xFF55FFFF,
    0xFFFF5555,
    0xFFFF55FF,
    0xFFFFFF55,
    0xFFFFFFFF,
  ];

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

  /// Priority bands count (0 to 14 depth priority levels, 15 is reserved).
  static const int priorityBands = 15;
}
