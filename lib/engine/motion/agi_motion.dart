import 'dart:math' as math;

/// Shared AGI motion tables: direction vectors (0..8) and view-loop mapping.
///
/// Live stepping, collision, and cycling live on [AgiGameEngine]. This is not
/// a second physics loop.
class AgiMotion {
  /// Direction deltas indexed by AGI direction code (0..8).
  ///
  /// 0 stop, 1 N, 2 NE, 3 E, 4 SE, 5 S, 6 SW, 7 W, 8 NW.
  static const List<math.Point<int>> directionDeltas = [
    math.Point(0, 0),
    math.Point(0, -1),
    math.Point(1, -1),
    math.Point(1, 0),
    math.Point(1, 1),
    math.Point(0, 1),
    math.Point(-1, 1),
    math.Point(-1, 0),
    math.Point(-1, -1),
  ];

  /// `(dx, dy)` for direction [dir] (0..8).
  static (int dx, int dy) delta(int dir) {
    final p = directionDeltas[dir.clamp(0, 8)];
    return (p.x, p.y);
  }

  /// AGI direction 0..8 from a unit step `(dx, dy)` in {-1, 0, 1}.
  static int directionFromDelta(int dx, int dy) {
    if (dx == 0 && dy < 0) return 1;
    if (dx > 0 && dy < 0) return 2;
    if (dx > 0 && dy == 0) return 3;
    if (dx > 0 && dy > 0) return 4;
    if (dx == 0 && dy > 0) return 5;
    if (dx < 0 && dy > 0) return 6;
    if (dx < 0 && dy == 0) return 7;
    if (dx < 0 && dy < 0) return 8;
    return 0;
  }

  /// Maps a direction code (0..8) to a view loop index.
  ///
  /// - 4+ loops: 0 = East (2, 3, 4), 1 = West (6, 7, 8), 2 = South (5), 3 = North (1).
  /// - 2-3 loops: 0 = East, 1 = West; North/South/Stopped keep [currentLoop].
  static int selectLoopForDirection(int direction, int loopCount, int currentLoop) {
    if (loopCount >= 4) {
      switch (direction) {
        case 1:
          return 3;
        case 2:
        case 3:
        case 4:
          return 0;
        case 5:
          return 2;
        case 6:
        case 7:
        case 8:
          return 1;
        default:
          return currentLoop;
      }
    } else if (loopCount >= 2) {
      switch (direction) {
        case 2:
        case 3:
        case 4:
          return 0;
        case 6:
        case 7:
        case 8:
          return 1;
        default:
          return (currentLoop >= 0 && currentLoop < 2) ? currentLoop : 0;
      }
    }
    return 0;
  }
}
