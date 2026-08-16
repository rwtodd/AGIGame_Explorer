import 'dart:math' as math;
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

/// Represents a rectangular block barrier defined by AGI `block(x1, y1, x2, y2)`.
class AgiBlockArea {
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  const AgiBlockArea({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  /// The normalized left boundary.
  int get left => math.min(x1, x2);

  /// The normalized right boundary.
  int get right => math.max(x1, x2);

  /// The normalized top boundary.
  int get top => math.min(y1, y2);

  /// The normalized bottom boundary.
  int get bottom => math.max(y1, y2);

  /// Returns true if the point `(x, y)` lies within this block area.
  bool contains(int x, int y) {
    return x >= left && x <= right && y >= top && y <= bottom;
  }

  /// Returns true if the baseline segment `(x, y)` to `(x + width - 1, y)` overlaps this block.
  bool overlapsBaseline(int x, int y, int width) {
    if (y < top || y > bottom) return false;
    final baseLeft = x;
    final baseRight = x + width - 1;
    return baseRight >= left && baseLeft <= right;
  }
}

/// Border edge constants used for AGI variables 2 and 5.
class AgiBorderEdge {
  const AgiBorderEdge._();

  static const int none = 0;
  static const int top = 1; // Horizon or screen top
  static const int right = 2; // Right border (x + w >= 160)
  static const int bottom = 3; // Bottom border (y >= 167)
  static const int left = 4; // Left border (x <= 0)
}

/// Collision detection engine for Sierra AGI.
///
/// Evaluates priority buffer control lines, screen boundaries, horizon barriers,
/// script block regions, and object-to-object collisions.
class CollisionDetector {
  /// Default AGI horizon Y coordinate.
  static const int defaultHorizon = 36;

  /// Standard AGI screen native width.
  static const int screenWidth = PriorityBuffer.width; // 160

  /// Standard AGI screen playable picture height.
  static const int screenHeight = PriorityBuffer.height; // 168

  /// Maximum Y coordinate for actors (167 in 0-indexed 168-height screen).
  static const int maxActorY = 167;

  /// The active priority buffer.
  final PriorityBuffer priorityBuffer;

  /// The current room horizon line Y (default 36).
  int horizon;

  /// Active script block region set by `block(x1, y1, x2, y2)`, or null if none.
  AgiBlockArea? activeBlock;

  /// Whether conditional barriers (priority value 1) block movement.
  bool observeBlocks;

  CollisionDetector({
    PriorityBuffer? priorityBuffer,
    this.horizon = defaultHorizon,
    this.activeBlock,
    this.observeBlocks = false,
  }) : priorityBuffer = priorityBuffer ?? PriorityBuffer();

  /// Sets an active rectangular block area.
  void setBlock(int x1, int y1, int x2, int y2) {
    activeBlock = AgiBlockArea(x1: x1, y1: y1, x2: x2, y2: y2);
  }

  /// Removes the active block area.
  void unblock() {
    activeBlock = null;
  }

  /// Checks if any pixel along the baseline `(x, y)` to `(x + width - 1, y)` is blocked
  /// by control lines or script block areas.
  ///
  /// Following Sierra AGI specification:
  /// - Priority 0 (Unconditional Barrier) ALWAYS blocks movement, even when [ignoreBlocks] is active.
  /// - Priority 1 (Conditional Barrier) and script [activeBlock] areas block movement UNLESS [ignoreBlocks] is true.
  bool isBaselineBlocked({
    required int x,
    required int y,
    required int width,
    bool ignoreBlocks = false,
  }) {
    // Check script block area (ignored if ignoreBlocks is active)
    if (!ignoreBlocks && activeBlock != null && activeBlock!.overlapsBaseline(x, y, width)) {
      return true;
    }

    // Check priority buffer pixels along baseline
    final effectiveWidth = math.max(1, width);
    for (var i = 0; i < effectiveWidth; i++) {
      final px = x + i;
      if (px < 0 || px >= screenWidth || y < 0 || y >= screenHeight) {
        continue;
      }

      final pri = priorityBuffer.priorityAt(px, y);

      // Priority 0 is unconditional barrier (always blocks)
      if (pri == 0) return true;

      // Priority 1 is conditional barrier (blocks unless ignoreBlocks is true)
      if (pri == 1 && !ignoreBlocks) return true;
    }

    return false;
  }

  /// Checks whether an object at `(x, y)` would collide with screen boundaries,
  /// horizon, priority buffer control lines, or active block regions.
  bool isPositionBlocked({
    required AnimatedObject obj,
    required int x,
    required int y,
    required int width,
    required int height,
    List<AnimatedObject>? otherObjects,
  }) {
    final effectiveWidth = math.max(1, width);

    // Screen boundary check
    if (x < 0 || x + effectiveWidth > screenWidth) return true;
    if (y > maxActorY) return true;

    final minAllowedY = obj.ignoreHorizon ? 0 : horizon;
    if (y < minAllowedY) return true;

    // Baseline barrier collision check
    if (isBaselineBlocked(
      x: x,
      y: y,
      width: effectiveWidth,
      ignoreBlocks: obj.ignoreBlocks,
    )) {
      return true;
    }

    // Object-to-object collision check
    if (!obj.ignoreObjects && otherObjects != null) {
      for (final other in otherObjects) {
        if (other.number == obj.number) continue;
        if (!other.isDrawn || !other.isAnimated || other.ignoreObjects) continue;

        if (checkObjectCollision(
          obj,
          x,
          y,
          effectiveWidth,
          height,
          other,
          other.x,
          other.y,
          other.stepSize, // fallback dimension if view cel is not known
          other.stepSize,
        )) {
          return true;
        }
      }
    }

    return false;
  }

  /// Tests collision between two objects given their bounding boxes and baselines.
  bool checkObjectCollision(
    AnimatedObject a,
    int ax,
    int ay,
    int aWidth,
    int aHeight,
    AnimatedObject b,
    int bx,
    int by,
    int bWidth,
    int bHeight,
  ) {
    if (a.ignoreObjects || b.ignoreObjects) return false;

    final aW = math.max(1, aWidth);
    final aH = math.max(1, aHeight);
    final bW = math.max(1, bWidth);
    final bH = math.max(1, bHeight);

    // Baseline collision test (AGI actor collision is primarily baseline intersection)
    final aLeft = ax;
    final aRight = ax + aW - 1;
    final bLeft = bx;
    final bRight = bx + bW - 1;

    // Same baseline Y row (or overlapping base lines)
    if (ay == by && aRight >= bLeft && aLeft <= bRight) {
      return true;
    }

    // 2D bounding box intersection (bottom-anchored sprites)
    final aTop = ay - aH + 1;
    final aBottom = ay;
    final bTop = by - bH + 1;
    final bBottom = by;

    return aRight >= bLeft &&
        aLeft <= bRight &&
        aBottom >= bTop &&
        aTop <= bBottom;
  }

  /// Checks if an object at `(x, y)` touches or crosses any screen border.
  ///
  /// Returns one of [AgiBorderEdge]:
  /// - 0: None
  /// - 1: Top (Horizon or screen top)
  /// - 2: Right (`x + width >= 160`)
  /// - 3: Bottom (`y >= 167`)
  /// - 4: Left (`x <= 0`)
  int checkBorderHit({
    required int x,
    required int y,
    required int width,
    bool ignoreHorizon = false,
  }) {
    final effectiveWidth = math.max(1, width);

    // Check borders according to AGI priority: Top, Right, Bottom, Left
    final topLimit = ignoreHorizon ? 0 : horizon;
    if (y <= topLimit) return AgiBorderEdge.top;
    if (x + effectiveWidth >= screenWidth) return AgiBorderEdge.right;
    if (y >= maxActorY) return AgiBorderEdge.bottom;
    if (x <= 0) return AgiBorderEdge.left;

    return AgiBorderEdge.none;
  }

  /// Updates edge variables in [memory] for [obj] when it reaches/touches a border.
  ///
  /// For Ego (Object 0): updates `variables[2]` (`edge_ego_hit`).
  /// For NPC objects: updates `variables[4]` (`edge_obj_hit`) and `variables[5]` (`edge_code`).
  int processBorderHit({
    required AnimatedObject obj,
    required AgiMemory memory,
    required int width,
  }) {
    final edge = checkBorderHit(
      x: obj.x,
      y: obj.y,
      width: width,
      ignoreHorizon: obj.ignoreHorizon,
    );

    if (edge != AgiBorderEdge.none) {
      if (obj.number == 0) {
        memory.setVar(2, edge);
      } else {
        memory.setVar(4, obj.number);
        memory.setVar(5, edge);
      }
    }

    return edge;
  }

  /// Clamps `(x, y)` to valid screen and horizon boundaries for [obj].
  (int x, int y) clampToScreenBounds({
    required AnimatedObject obj,
    required int x,
    required int y,
    required int width,
  }) {
    final effectiveWidth = math.max(1, width);
    final minX = 0;
    final maxX = screenWidth - effectiveWidth;
    final minY = obj.ignoreHorizon ? 0 : horizon;
    const maxY = maxActorY;

    final clampedX = x.clamp(minX, maxX);
    final clampedY = y.clamp(minY, maxY);
    return (clampedX, clampedY);
  }

  /// Checks if the object's baseline is entirely on water (priority 3).
  ///
  /// In Sierra AGI, Flag 0 (ONWATER) is set only when every pixel along
  /// the actor's baseline is on priority 3.
  bool isWaterAtBaseline({
    required int x,
    required int y,
    required int width,
  }) {
    final effectiveWidth = math.max(1, width);
    for (var i = 0; i < effectiveWidth; i++) {
      final px = x + i;
      if (px < 0 || px >= screenWidth || y < 0 || y >= screenHeight) {
        return false;
      }
      if (priorityBuffer.priorityAt(px, y) != 3) {
        return false;
      }
    }
    return true;
  }

  /// Checks if the object's baseline touches a special trigger/alarm pixel (priority 2).
  ///
  /// In Sierra AGI, Flag 3 (HITSPEC) is set when any pixel along
  /// the actor's baseline touches priority 2.
  bool isSignalAtBaseline({
    required int x,
    required int y,
    required int width,
  }) {
    final effectiveWidth = math.max(1, width);
    for (var i = 0; i < effectiveWidth; i++) {
      final px = x + i;
      if (px >= 0 && px < screenWidth && y >= 0 && y < screenHeight) {
        final pri = priorityBuffer.priorityAt(px, y);
        if (pri == 2) {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks if the object is completely obscured behind higher visual depth bands.
  bool isObscured({
    required int x,
    required int y,
    required int width,
    required int actorPriority,
  }) {
    final effectiveWidth = math.max(1, width);
    var allObscured = true;

    for (var i = 0; i < effectiveWidth; i++) {
      final px = x + i;
      if (px >= 0 && px < screenWidth && y >= 0 && y < screenHeight) {
        final effPri = priorityBuffer.effectivePriorityAt(px, y);
        // If effective screen priority is less than actor priority (i.e. actor is behind obstacle)
        if (effPri >= actorPriority) {
          allObscured = false;
          break;
        }
      } else {
        allObscured = false;
        break;
      }
    }

    return allObscured;
  }
}
