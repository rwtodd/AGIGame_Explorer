import 'package:flutter_agigame/core/constants/ega_colors.dart';

/// Display resolution, viewport, and priority geometry profile for Sierra engines.
///
/// Encapsulates the visual buffer and priority slicing differences between
/// 160x168 AGI (horizontally doubled, control lines scanned downward) and
/// 320x200 SCI (1:1 display pixels, pure Z-depth, third control buffer).
class DisplayProfile {
  /// Native horizontal resolution before display scaling (AGI: 160, SCI: 320).
  final int nativeWidth;

  /// Native vertical resolution of the picture playfield (AGI: 168, SCI: 200).
  final int nativeHeight;

  /// Composited render target width in display pixels (always 320).
  final int renderedWidth;

  /// Composited render target height in display pixels (always 200).
  final int renderedHeight;

  /// Whether each native horizontal unit expands to 2 display pixels (AGI: true, SCI: false).
  final bool horizontalDouble;

  /// Top row offset of the active picture port (AGI: 8 below status line, SCI: ~10 below menu bar).
  final int picPortTop;

  /// Number of priority bands / depth slices (0..15 = 16 bands for both AGI and SCI0).
  final int priorityBandCount;

  /// Whether priority values < 4 represent control lines that scan downward for depth (AGI: true, SCI: false).
  final bool scanControlLines;

  const DisplayProfile({
    required this.nativeWidth,
    required this.nativeHeight,
    this.renderedWidth = AgiDisplay.renderedWidth,
    this.renderedHeight = AgiDisplay.renderedHeight,
    required this.horizontalDouble,
    this.picPortTop = 0,
    this.priorityBandCount = 16,
    required this.scanControlLines,
  });

  /// Standard Sierra AGI display profile:
  /// - 160x168 native picture playfield
  /// - 320x200 rendered framebuffer (horizontal 2x doubling)
  /// - 8px status line at top
  /// - 16 priority bands (0..15)
  /// - Control lines (< 4) scan downward to find underlying depth band
  static const DisplayProfile agi = DisplayProfile(
    nativeWidth: AgiDisplay.nativeWidth, // 160
    nativeHeight: AgiDisplay.pictureHeight, // 168
    renderedWidth: AgiDisplay.renderedWidth, // 320
    renderedHeight: AgiDisplay.renderedHeight, // 200
    horizontalDouble: true,
    picPortTop: 8,
    priorityBandCount: 16,
    scanControlLines: true,
  );

  /// Standard Sierra SCI0 display profile:
  /// - 320x200 native framebuffer (no horizontal doubling)
  /// - ~10px standard menu bar at top (gameplay pic port rows 10..199)
  /// - 16 priority depth bands (0..15)
  /// - Pure Z-buffer: control lines are kept in a separate 3rd buffer, no downward column scan
  static const DisplayProfile sci0 = DisplayProfile(
    nativeWidth: 320,
    nativeHeight: 200,
    renderedWidth: 320,
    renderedHeight: 200,
    horizontalDouble: false,
    picPortTop: 10,
    priorityBandCount: 16,
    scanControlLines: false,
  );

  /// Full-screen Sierra SCI0 display profile for title screens and cutscenes (e.g. PQ2 intro):
  /// - 320x200 native framebuffer
  /// - 0px menu bar (full 0..199 port)
  /// - 16 priority depth bands (0..15)
  /// - Pure Z-buffer
  static const DisplayProfile sci0FullScreen = DisplayProfile(
    nativeWidth: 320,
    nativeHeight: 200,
    renderedWidth: 320,
    renderedHeight: 200,
    horizontalDouble: false,
    picPortTop: 0,
    priorityBandCount: 16,
    scanControlLines: false,
  );

  DisplayProfile copyWith({
    int? nativeWidth,
    int? nativeHeight,
    int? renderedWidth,
    int? renderedHeight,
    bool? horizontalDouble,
    int? picPortTop,
    int? priorityBandCount,
    bool? scanControlLines,
  }) {
    return DisplayProfile(
      nativeWidth: nativeWidth ?? this.nativeWidth,
      nativeHeight: nativeHeight ?? this.nativeHeight,
      renderedWidth: renderedWidth ?? this.renderedWidth,
      renderedHeight: renderedHeight ?? this.renderedHeight,
      horizontalDouble: horizontalDouble ?? this.horizontalDouble,
      picPortTop: picPortTop ?? this.picPortTop,
      priorityBandCount: priorityBandCount ?? this.priorityBandCount,
      scanControlLines: scanControlLines ?? this.scanControlLines,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayProfile &&
          runtimeType == other.runtimeType &&
          nativeWidth == other.nativeWidth &&
          nativeHeight == other.nativeHeight &&
          renderedWidth == other.renderedWidth &&
          renderedHeight == other.renderedHeight &&
          horizontalDouble == other.horizontalDouble &&
          picPortTop == other.picPortTop &&
          priorityBandCount == other.priorityBandCount &&
          scanControlLines == other.scanControlLines;

  @override
  int get hashCode => Object.hash(
        nativeWidth,
        nativeHeight,
        renderedWidth,
        renderedHeight,
        horizontalDouble,
        picPortTop,
        priorityBandCount,
        scanControlLines,
      );

  @override
  String toString() =>
      'DisplayProfile(${nativeWidth}x$nativeHeight -> ${renderedWidth}x$renderedHeight, '
      '2x: $horizontalDouble, portTop: $picPortTop, priBands: $priorityBandCount, '
      'scanControl: $scanControlLines)';
}
