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

  /// Returns true if the point `(x, y)` lies strictly within this block area.
  /// Matching Sierra AGI `InBlock`: `ox > ulx && ox < lrx && oy > uly && oy < lry`.
  bool contains(int x, int y) {
    return x > left && x < right && y > top && y < bottom;
  }

  /// Returns true if moving from `(fromX, fromY)` to `(toX, toY)` crosses the block boundary.
  /// In authentic Sierra AGI, an object can move freely inside or outside the block,
  /// but cannot cross the boundary between inside and outside.
  bool crossesBoundary(int fromX, int fromY, int toX, int toY) {
    final fromIn = contains(fromX, fromY);
    final toIn = contains(toX, toY);
    return fromIn != toIn;
  }

  /// Returns true if the baseline segment `(x, y)` to `(x + width - 1, y)` overlaps this block.
  bool overlapsBaseline(int x, int y, int width) {
    if (y <= top || y >= bottom) return false;
    final baseLeft = x;
    final baseRight = x + width - 1;
    return baseRight > left && baseLeft < right;
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
  /// - Priority 1 (Conditional Barrier) blocks movement UNLESS [ignoreBlocks] is true.
  bool isBaselineBlocked({
    required int x,
    required int y,
    required int width,
    bool ignoreBlocks = false,
  }) {
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

  /// Shifts an object in an expanding counter-clockwise spiral until it rests
  /// in a valid, walkable screen position (matching Sierra AGI `obj_pos_shuffle`).
  void posShuffle({
    required AnimatedObject obj,
    required int width,
    required int height,
    List<AnimatedObject>? otherObjects,
  }) {
    if (obj.y <= horizon && !obj.ignoreHorizon) {
      obj.y = horizon + 1;
      obj.prevY = obj.y;
    }

    if (!isPositionBlocked(
      obj: obj,
      x: obj.x,
      y: obj.y,
      width: width,
      height: height,
      otherObjects: otherObjects,
    )) {
      return;
    }

    var shiftDir = 0;
    var shiftCount = 1;
    var shiftSize = 1;

    for (int iter = 0; iter < 500; iter++) {
      switch (shiftDir) {
        case 0: // left
          obj.x--;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 1;
            shiftCount = shiftSize;
          }
          break;
        case 1: // down
          obj.y++;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 2;
            shiftSize++;
            shiftCount = shiftSize;
          }
          break;
        case 2: // right
          obj.x++;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 3;
            shiftCount = shiftSize;
          }
          break;
        case 3: // up
          obj.y--;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 0;
            shiftSize++;
            shiftCount = shiftSize;
          }
          break;
      }

      if (!isPositionBlocked(
        obj: obj,
        x: obj.x,
        y: obj.y,
        width: width,
        height: height,
        otherObjects: otherObjects,
      )) {
        obj.prevX = obj.x;
        obj.prevY = obj.y;
        return;
      }
    }
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

    // Script block boundary crossing check
    if (!obj.ignoreBlocks && activeBlock != null) {
      if (activeBlock!.crossesBoundary(obj.x, obj.y, x, y)) {
        return true;
      }
    }

    // Baseline barrier collision check
    // Per Sierra AGI & ScummVM specification: priority 15 (0x0F) represents sky/background,
    // which bypasses ground control line barriers (priority 0, 1, water).
    if (obj.priority != 15) {
      if (isBaselineBlocked(
        x: x,
        y: y,
        width: effectiveWidth,
        ignoreBlocks: obj.ignoreBlocks,
      )) {
        return true;
      }
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
    final bW = math.max(1, bWidth);

    // Baseline collision test (AGI actor collision is strictly baseline intersection & crossing)
    final aLeft = ax;
    final aRight = ax + aW - 1;
    final bLeft = bx;
    final bRight = bx + bW - 1;

    if (aRight >= bLeft && aLeft <= bRight) {
      if (ay == by) return true;
      if (ay > by && a.prevY < b.prevY) return true;
      if (ay < by && a.prevY > b.prevY) return true;
    }

    return false;
  }

  /// Checks if `(x, y)` has hit any screen border (top, right, bottom, left).
  ///
  /// Returns border code:
  /// - 0: None
  /// - 1: Top (`y <= horizon` or sprite top goes above screen top)
  /// - 2: Right (`x + width >= 160`)
  /// - 3: Bottom (`y >= 167`)
  /// - 4: Left (`x <= 0`)
  int checkBorderHit({
    required int x,
    required int y,
    required int width,
    int height = 1,
    bool ignoreHorizon = false,
  }) {
    final effectiveWidth = math.max(1, width);
    final effectiveHeight = math.max(1, height);
    final minScreenY = effectiveHeight - 1;
    final topLimit = ignoreHorizon ? minScreenY : math.max(horizon, minScreenY);

    if (y <= topLimit || (y - effectiveHeight < -1)) return AgiBorderEdge.top;
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
    int? height,
  }) {
    final edge = checkBorderHit(
      x: obj.x,
      y: obj.y,
      width: width,
      height: height ?? obj.getCelHeight(),
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
    int? height,
  }) {
    final effectiveWidth = math.max(1, width);
    final effectiveHeight = math.max(1, height ?? obj.getCelHeight());
    final minX = 0;
    final maxX = screenWidth - effectiveWidth;
    final minScreenY = math.max(0, effectiveHeight - 1);
    final minY = obj.ignoreHorizon ? minScreenY : math.max(horizon, minScreenY);
    const maxY = maxActorY;

    final clampedX = x.clamp(minX, maxX);
    final clampedY = y.clamp(minY, maxY);
    return (clampedX, clampedY);
  }

  /// Checks if the object's baseline is on water (priority 3).
  ///
  /// In Sierra AGI:
  /// - When not yet on water, every pixel along baseline must be priority 3 to enter water.
  /// - When [onWater] is true (`object.on.water`), Ego remains on water as long as water is present under the sprite.
  bool isWaterAtBaseline({
    required int x,
    required int y,
    required int width,
    bool onWater = false,
  }) {
    final effectiveWidth = math.max(1, width);
    if (onWater) {
      for (var i = 0; i < effectiveWidth; i++) {
        final px = x + i;
        if (px >= 0 && px < screenWidth && y >= 0 && y < screenHeight) {
          if (priorityBuffer.priorityAt(px, y) == 3) {
            return true;
          }
        }
      }
      return false;
    }

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
        // If effective screen priority <= actor priority, actor is in front of or level with background (visible)
        if (effPri <= actorPriority) {
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
