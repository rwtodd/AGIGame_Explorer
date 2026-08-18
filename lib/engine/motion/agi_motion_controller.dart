import 'dart:math' as math;
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';

/// Function signature for looking up loaded [AgiView] resources.
typedef AgiViewProvider = AgiView? Function(int viewNumber);

/// Coordinates sprite motion, collision detection, and animation cycling for Sierra AGI.
class AgiMotionController {
  /// Standard direction deltas for (dx, dy) indexed by direction code (0..8).
  ///
  /// - 0: Stopped (0, 0)
  /// - 1: North (0, -1)
  /// - 2: North-East (1, -1)
  /// - 3: East (1, 0)
  /// - 4: South-East (1, 1)
  /// - 5: South (0, 1)
  /// - 6: South-West (-1, 1)
  /// - 7: West (-1, 0)
  /// - 8: North-West (-1, -1)
  static const List<math.Point<int>> directionDeltas = [
    math.Point(0, 0), // 0: Stopped
    math.Point(0, -1), // 1: North
    math.Point(1, -1), // 2: North-East
    math.Point(1, 0), // 3: East
    math.Point(1, 1), // 4: South-East
    math.Point(0, 1), // 5: South
    math.Point(-1, 1), // 6: South-West
    math.Point(-1, 0), // 7: West
    math.Point(-1, -1), // 8: North-West
  ];

  /// List of animated objects in the game (slot 0 is Ego).
  final List<AnimatedObject> objects;

  /// Interpreter runtime memory registers, variables, and flags.
  final AgiMemory memory;

  /// The active priority buffer.
  final PriorityBuffer priorityBuffer;

  /// The collision detector.
  final CollisionDetector collisionDetector;

  /// Optional provider or map to resolve [AgiView] resources for objects.
  AgiViewProvider? viewProvider;

  /// Cached views map.
  final Map<int, AgiView> loadedViews;

  /// Random number generator for wander and AI movement.
  math.Random rng;

  /// Step count tracker for wander motion before randomly picking a new direction.
  final Map<int, int> _wanderStepCounts = {};

  AgiMotionController({
    List<AnimatedObject>? objects,
    AgiMemory? memory,
    PriorityBuffer? priorityBuffer,
    CollisionDetector? collisionDetector,
    this.viewProvider,
    Map<int, AgiView>? loadedViews,
    int? randomSeed,
  })  : objects = objects ??
            List.generate(64, (i) => AnimatedObject(number: i)),
        memory = memory ?? AgiMemory(),
        priorityBuffer = priorityBuffer ?? PriorityBuffer(),
        collisionDetector = collisionDetector ??
            CollisionDetector(priorityBuffer: priorityBuffer),
        loadedViews = loadedViews ?? {},
        rng = randomSeed != null ? math.Random(randomSeed) : math.Random() {
    this.memory.flagGetterHook ??= (flag) {
      if (flag == 1) {
        return isEgoObscured();
      }
      return null;
    };
  }

  /// Gets Ego (player character, slot 0).
  AnimatedObject get ego => objects[0];

  /// Gets the [AgiView] for a given [viewNumber].
  AgiView? getView(int viewNumber) {
    if (loadedViews.containsKey(viewNumber)) {
      return loadedViews[viewNumber];
    }
    if (viewProvider != null) {
      final v = viewProvider!(viewNumber);
      if (v != null) {
        loadedViews[viewNumber] = v;
        return v;
      }
    }
    return null;
  }

  /// Resolves the current cel dimensions (width, height) for [obj].
  (int width, int height) getObjectDimensions(AnimatedObject obj) {
    final view = getView(obj.view);
    if (view != null) {
      final loop = view.getLoop(obj.loop);
      if (loop != null) {
        final cel = loop.getCel(obj.cel);
        if (cel != null) {
          return (cel.width, cel.height);
        }
      }
    }
    return (1, 1);
  }

  /// Resolves cel count for current loop of [obj].
  int getCelCount(AnimatedObject obj) {
    final view = getView(obj.view);
    if (view != null) {
      final loop = view.getLoop(obj.loop);
      if (loop != null && loop.celCount > 0) {
        return loop.celCount;
      }
    }
    return 1;
  }

  /// Resolves loop count for view of [obj].
  int getLoopCount(AnimatedObject obj) {
    final view = getView(obj.view);
    if (view != null && view.loopCount > 0) {
      return view.loopCount;
    }
    return 1;
  }

  /// Executes one complete interpreter tick/cycle of motion physics,
  /// collision resolution, and animation cycling.
  void tick() {
    // 1. Advance Cel Animation for all cycling objects
    _updateAnimationCycling();

    // 2. Process Motion & Collision for all active objects
    _updateMotionAndCollisions();

    // 3. Update Ego special flags and status registers
    _updateEgoFlags();
  }

  /// Step 1: Advance animation cycling timers and cels.
  void _updateAnimationCycling() {
    for (final obj in objects) {
      if (!obj.isAnimated || !obj.isDrawn || !obj.isUpdating || !obj.isCycling) {
        continue;
      }

      obj.cycleTimer--;
      if (obj.cycleTimer <= 0) {
        obj.cycleTimer = obj.cycleTime > 0 ? obj.cycleTime : 1;
        _advanceCel(obj);
      }
    }
  }

  /// Advances cel index based on `obj.cycleMode`.
  void _advanceCel(AnimatedObject obj) {
    final celCount = getCelCount(obj);
    if (celCount <= 1) return;

    switch (obj.cycleMode) {
      case 0: // normal: forward looping
        obj.cel = (obj.cel + 1) % celCount;
        break;

      case 1: // reverse: backward looping
        obj.cel = (obj.cel - 1 + celCount) % celCount;
        break;

      case 2: // end_of_loop: forward until last cel then stop
        if (obj.cel < celCount - 1) {
          obj.cel++;
        }
        if (obj.cel >= celCount - 1) {
          obj.isCycling = false;
          obj.cycleMode = 0;
          obj.direction = 0;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
            obj.endOfLoopFlag = null;
          }
        }
        break;

      case 3: // reverse_loop: backward until cel 0 then stop
        if (obj.cel > 0) {
          obj.cel--;
        }
        if (obj.cel <= 0) {
          obj.isCycling = false;
          obj.cycleMode = 0;
          obj.direction = 0;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
            obj.endOfLoopFlag = null;
          }
        }
        break;
    }
  }

  /// Step 2: Process motion mode dispatch and collision handling.
  void _updateMotionAndCollisions() {
    for (final obj in objects) {
      if (!obj.isAnimated || !obj.isDrawn || !obj.isUpdating) {
        continue;
      }

      // Save previous position
      obj.prevX = obj.x;
      obj.prevY = obj.y;

      // Handle motion timer countdown
      obj.stepTimer--;
      if (obj.stepTimer > 0) {
        continue;
      }
      obj.stepTimer = obj.stepTime > 0 ? obj.stepTime : 1;

      // Update motion mode
      switch (obj.motionType) {
        case 0: // normal motion
          _stepNormalMotion(obj);
          break;

        case 1: // wander motion
          _stepWanderMotion(obj);
          break;

        case 2: // follow_ego motion
          _stepFollowEgoMotion(obj);
          break;

        case 3: // move_obj motion
          _stepMoveObjMotion(obj);
          break;
      }

      // Automatically select loop from direction if fixedLoop is false
      _updateObjectLoop(obj);
    }
  }

  /// Normal motion follows current `obj.direction` with `obj.stepSize`.
  void _stepNormalMotion(AnimatedObject obj) {
    if (obj.direction == 0) return;

    final delta = directionDeltas[obj.direction.clamp(0, 8)];
    final step = obj.stepSize > 0 ? obj.stepSize : 1;
    final (width, height) = getObjectDimensions(obj);

    final newX = obj.x + (delta.x * step);
    final newY = obj.y + (delta.y * step);

    // Test for obstacle collision
    final blocked = collisionDetector.isPositionBlocked(
      obj: obj,
      x: newX,
      y: newY,
      width: width,
      height: height,
      otherObjects: objects,
    );

    if (blocked) {
      // For diagonal motion, attempt sliding along single axes
      var moved = false;
      if (delta.x != 0 && delta.y != 0) {
        // Try horizontal only
        final xOnlyBlocked = collisionDetector.isPositionBlocked(
          obj: obj,
          x: newX,
          y: obj.y,
          width: width,
          height: height,
          otherObjects: objects,
        );
        if (!xOnlyBlocked) {
          obj.x = newX;
          moved = true;
        } else {
          // Try vertical only
          final yOnlyBlocked = collisionDetector.isPositionBlocked(
            obj: obj,
            x: obj.x,
            y: newY,
            width: width,
            height: height,
            otherObjects: objects,
          );
          if (!yOnlyBlocked) {
            obj.y = newY;
            moved = true;
          }
        }
      }

      if (!moved) {
        // Stopped by collision
        obj.direction = 0;
        if (obj.number == 0) {
          memory.setVar(6, 0);
        }
      }
    } else {
      obj.x = newX;
      obj.y = newY;
    }

    // Process border edge triggers & clamp
    collisionDetector.processBorderHit(
      obj: obj,
      memory: memory,
      width: width,
    );

    final (clampedX, clampedY) = collisionDetector.clampToScreenBounds(
      obj: obj,
      x: obj.x,
      y: obj.y,
      width: width,
    );
    obj.x = clampedX;
    obj.y = clampedY;
  }

  /// Wander motion randomly picks directions and changes when blocked.
  void _stepWanderMotion(AnimatedObject obj) {
    var stepsLeft = _wanderStepCounts[obj.number] ?? 0;
    stepsLeft--;

    if (stepsLeft <= 0 || obj.direction == 0) {
      // Pick random direction (0..8 or 1..8)
      obj.direction = rng.nextInt(9);
      // Pick random number of steps (e.g. 6 to 30)
      stepsLeft = 6 + rng.nextInt(25);
      _wanderStepCounts[obj.number] = stepsLeft;
    } else {
      _wanderStepCounts[obj.number] = stepsLeft;
    }

    if (obj.direction == 0) return;

    final (width, height) = getObjectDimensions(obj);
    final delta = directionDeltas[obj.direction.clamp(0, 8)];
    final step = obj.stepSize > 0 ? obj.stepSize : 1;

    final newX = obj.x + (delta.x * step);
    final newY = obj.y + (delta.y * step);

    final blocked = collisionDetector.isPositionBlocked(
      obj: obj,
      x: newX,
      y: newY,
      width: width,
      height: height,
      otherObjects: objects,
    );

    if (blocked) {
      // Pick a new direction immediately when blocked
      obj.direction = 1 + rng.nextInt(8);
      _wanderStepCounts[obj.number] = 4 + rng.nextInt(15);
    } else {
      obj.x = newX;
      obj.y = newY;
    }

    collisionDetector.processBorderHit(
      obj: obj,
      memory: memory,
      width: width,
    );

    final (clampedX, clampedY) = collisionDetector.clampToScreenBounds(
      obj: obj,
      x: obj.x,
      y: obj.y,
      width: width,
    );
    obj.x = clampedX;
    obj.y = clampedY;
  }

  /// Follow Ego motion calculates direction towards Object 0.
  void _stepFollowEgoMotion(AnimatedObject obj) {
    final step = obj.stepDistance > 0 ? obj.stepDistance : obj.stepSize;
    final (width, height) = getObjectDimensions(obj);

    final egoObj = ego;
    final dx = egoObj.x - obj.x;
    final dy = egoObj.y - obj.y;

    // Check if already reached Ego
    if (dx.abs() <= step && dy.abs() <= step) {
      obj.direction = 0;
      obj.motionType = 0;
      if (obj.targetFlag != null) {
        memory.setFlag(obj.targetFlag!);
      }
      return;
    }

    // Determine direction code towards Ego
    final dir = computeDirectionTowards(obj.x, obj.y, egoObj.x, egoObj.y);
    obj.direction = dir;

    if (dir == 0) return;

    final delta = directionDeltas[dir];
    final newX = obj.x + (delta.x * step);
    final newY = obj.y + (delta.y * step);

    // Filter out Ego from obstacles since Ego is the pursuit target
    final obstacleList = objects.where((o) => o.number != 0 && o.number != obj.number).toList();

    final blocked = collisionDetector.isPositionBlocked(
      obj: obj,
      x: newX,
      y: newY,
      width: width,
      height: height,
      otherObjects: obstacleList,
    );

    if (!blocked) {
      obj.x = newX;
      obj.y = newY;
    }

    // Check if reached Ego after step
    final remDx = (egoObj.x - obj.x).abs();
    final remDy = (egoObj.y - obj.y).abs();
    if (remDx <= step && remDy <= step) {
      obj.direction = 0;
      obj.motionType = 0;
      if (obj.targetFlag != null) {
        memory.setFlag(obj.targetFlag!);
      }
    }

    collisionDetector.processBorderHit(
      obj: obj,
      memory: memory,
      width: width,
    );

    final (clampedX, clampedY) = collisionDetector.clampToScreenBounds(
      obj: obj,
      x: obj.x,
      y: obj.y,
      width: width,
    );
    obj.x = clampedX;
    obj.y = clampedY;
  }

  /// Move Obj moves towards `(targetX, targetY)` with `stepDistance`.
  void _stepMoveObjMotion(AnimatedObject obj) {
    final step = obj.stepDistance > 0 ? obj.stepDistance : obj.stepSize;
    final (width, height) = getObjectDimensions(obj);

    final diffX = obj.targetX - obj.x;
    final diffY = obj.targetY - obj.y;

    if (diffX == 0 && diffY == 0) {
      // Reached destination
      obj.direction = 0;
      obj.motionType = 0;
      if (obj.targetFlag != null) {
        memory.setFlag(obj.targetFlag!);
      }
      return;
    }

    int stepX = 0;
    if (diffX > 0) {
      stepX = math.min(step, diffX);
    } else if (diffX < 0) {
      stepX = math.max(-step, diffX);
    }

    int stepY = 0;
    if (diffY > 0) {
      stepY = math.min(step, diffY);
    } else if (diffY < 0) {
      stepY = math.max(-step, diffY);
    }

    final dir = computeDirectionFromDelta(stepX, stepY);
    obj.direction = dir;

    final newX = obj.x + stepX;
    final newY = obj.y + stepY;

    final blocked = collisionDetector.isPositionBlocked(
      obj: obj,
      x: newX,
      y: newY,
      width: width,
      height: height,
      otherObjects: objects,
    );

    if (!blocked) {
      obj.x = newX;
      obj.y = newY;
    } else {
      collisionDetector.posShuffle(
        obj: obj,
        width: width,
        height: height,
        otherObjects: objects,
      );
    }

    final edge = collisionDetector.processBorderHit(
      obj: obj,
      memory: memory,
      width: width,
    );

    final (clampedX, clampedY) = collisionDetector.clampToScreenBounds(
      obj: obj,
      x: obj.x,
      y: obj.y,
      width: width,
    );
    obj.x = clampedX;
    obj.y = clampedY;

    if (edge != AgiBorderEdge.none || (obj.x == obj.targetX && obj.y == obj.targetY)) {
      obj.direction = 0;
      obj.motionType = 0;
      if (obj.targetFlag != null) {
        memory.setFlag(obj.targetFlag!);
        obj.targetFlag = null;
      }
      if (obj.number == 0) {
        memory.setVar(6, 0);
      }
    }
  }

  /// Automatically updates `obj.loop` based on motion direction if `!obj.fixedLoop`.
  void _updateObjectLoop(AnimatedObject obj) {
    if (obj.fixedLoop || obj.direction == 0) {
      return;
    }

    final loopCount = getLoopCount(obj);
    final newLoop = selectLoopForDirection(obj.direction, loopCount, obj.loop);
    if (newLoop != obj.loop) {
      obj.loop = newLoop;
      // Clamp cel to valid range in new loop
      final celCount = getCelCount(obj);
      if (obj.cel >= celCount) {
        obj.cel = 0;
      }
    }
  }

  /// Maps a direction code (0..8) to a view loop index.
  ///
  /// - For 4+ loops: Loop 0 = East (2, 3, 4), Loop 1 = West (6, 7, 8), Loop 2 = South (5), Loop 3 = North (1).
  /// - For 2-3 loops: Loop 0 = East, Loop 1 = West.
  static int selectLoopForDirection(int direction, int loopCount, int currentLoop) {
    if (loopCount >= 4) {
      switch (direction) {
        case 1: // North
          return 3;
        case 2: // North-East
        case 3: // East
        case 4: // South-East
          return 0;
        case 5: // South
          return 2;
        case 6: // South-West
        case 7: // West
        case 8: // North-West
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
          return currentLoop;
      }
    }
    return 0;
  }

  /// Computes AGI direction code (0..8) from `(fromX, fromY)` to `(toX, toY)`.
  static int computeDirectionTowards(int fromX, int fromY, int toX, int toY) {
    final dx = toX - fromX;
    final dy = toY - fromY;
    return computeDirectionFromDelta(dx, dy);
  }

  /// Computes AGI direction code (0..8) from a displacement vector `(dx, dy)`.
  static int computeDirectionFromDelta(int dx, int dy) {
    if (dx == 0 && dy == 0) return 0;

    final absDx = dx.abs();
    final absDy = dy.abs();

    // Check threshold for pure cardinal vs diagonal motion
    if (absDx >= absDy * 2) {
      // Predominantly horizontal
      return dx > 0 ? 3 : 7;
    } else if (absDy >= absDx * 2) {
      // Predominantly vertical
      return dy > 0 ? 5 : 1;
    } else {
      // Diagonal
      if (dx > 0 && dy < 0) return 2; // North-East
      if (dx > 0 && dy > 0) return 4; // South-East
      if (dx < 0 && dy > 0) return 6; // South-West
      if (dx < 0 && dy < 0) return 8; // North-West
    }

    return 0;
  }

  /// Step 3: Updates Ego special registers and flags in `memory`.
  void _updateEgoFlags() {
    final egoObj = ego;
    final (width, _) = getObjectDimensions(egoObj);

    // Sync variable 6 (Direction of Ego motion)
    memory.setVar(6, egoObj.direction);

    // Flag 0: EGO on water surface (pri 3)
    final onWater = collisionDetector.isWaterAtBaseline(
      x: egoObj.x,
      y: egoObj.y,
      width: width,
      onWater: egoObj.onWater,
    );
    if (onWater) {
      memory.setFlag(0);
    } else {
      memory.resetFlag(0);
    }

    // Flag 3: EGO touched signal pixel (pri 2 or 0)
    final onSignal = collisionDetector.isSignalAtBaseline(
      x: egoObj.x,
      y: egoObj.y,
      width: width,
    );
    if (onSignal) {
      memory.setFlag(3);
    } else {
      memory.resetFlag(3);
    }
  }

  /// Evaluates whether Ego (%o0) is completely obscured by higher priority background elements.
  /// Evaluated lazily on-demand when Flag 1 is queried.
  bool isEgoObscured() {
    final egoObj = ego;
    if (!egoObj.isDrawn || !egoObj.isAnimated) {
      return true;
    }

    final priBuf = priorityBuffer;
    final view = egoObj.cachedView ??
        (viewProvider != null ? viewProvider!(egoObj.view) : loadedViews[egoObj.view]);
    final cel = view?.getCel(egoObj.loop, egoObj.cel);
    final egoPri = egoObj.effectivePriority;

    if (cel != null) {
      final width = cel.width;
      final height = cel.height;
      final clearKey = cel.transparentColor;
      final topY = egoObj.y - height + 1;

      try {
        final pixels = cel.getUnflippedPixels(parentView: view);
        for (int r = 0; r < height; r++) {
          final py = topY + r;
          if (py < 0 || py >= CollisionDetector.screenHeight) continue;

          for (int c = 0; c < width; c++) {
            final px = egoObj.x + (cel.isMirrored ? (width - 1 - c) : c);
            if (px < 0 || px >= CollisionDetector.screenWidth) continue;

            final pixelColor = pixels[r * width + c];
            if (pixelColor != clearKey) {
              final effPri = priBuf.effectivePriorityAt(px, py);
              if (effPri <= egoPri) {
                // Found at least one visible Ego pixel!
                return false;
              }
            }
          }
        }
        // No visible pixels found across all cel pixels
        return true;
      } catch (_) {
        // Fallback to baseline check
      }
    }

    // Fallback if cel pixel data is unavailable: check baseline
    final width = egoObj.getCelWidth(null, null, view);
    return collisionDetector.isObscured(
      x: egoObj.x,
      y: egoObj.y,
      width: width,
      actorPriority: egoPri,
    );
  }

  /// Helper to command an object to move in a normal direction.
  void setDirection(int objNumber, int direction) {
    if (objNumber >= 0 && objNumber < objects.length) {
      final obj = objects[objNumber];
      obj.direction = direction.clamp(0, 8);
      obj.motionType = 0;
      if (objNumber == 0) {
        memory.setVar(6, obj.direction);
      }
    }
  }

  /// Helper to initiate `move.obj` motion on [objNumber].
  void moveObject(
    int objNumber,
    int targetX,
    int targetY,
    int stepDistance,
    int? targetFlag,
  ) {
    if (objNumber >= 0 && objNumber < objects.length) {
      final obj = objects[objNumber];
      obj.motionType = 3;
      obj.targetX = targetX;
      obj.targetY = targetY;
      obj.stepDistance = stepDistance > 0 ? stepDistance : 1;
      if (stepDistance > 0) {
        obj.stepSize = stepDistance;
      }
      obj.targetFlag = targetFlag;
      if (targetFlag != null) {
        memory.resetFlag(targetFlag);
      }
    }
  }

  /// Helper to initiate `follow.ego` motion on [objNumber].
  void followEgo(int objNumber, int stepDistance, int? targetFlag) {
    if (objNumber >= 0 && objNumber < objects.length) {
      final obj = objects[objNumber];
      obj.motionType = 2;
      obj.stepDistance = stepDistance > 0 ? stepDistance : 1;
      obj.targetFlag = targetFlag;
      if (targetFlag != null) {
        memory.resetFlag(targetFlag);
      }
    }
  }

  /// Helper to initiate `wander` motion on [objNumber].
  void wander(int objNumber) {
    if (objNumber >= 0 && objNumber < objects.length) {
      final obj = objects[objNumber];
      obj.motionType = 1;
      _wanderStepCounts[objNumber] = 0;
    }
  }

  /// Helper to stop motion on [objNumber].
  void stopMotion(int objNumber) {
    if (objNumber >= 0 && objNumber < objects.length) {
      final obj = objects[objNumber];
      obj.direction = 0;
      obj.motionType = 0;
      if (objNumber == 0) {
        memory.setVar(6, 0);
      }
    }
  }

  /// Sets the current room horizon.
  void setHorizon(int horizon) {
    collisionDetector.horizon = horizon;
  }

  /// Sets a rectangular block barrier.
  void block(int x1, int y1, int x2, int y2) {
    collisionDetector.setBlock(x1, y1, x2, y2);
  }

  /// Removes active block barrier.
  void unblock() {
    collisionDetector.unblock();
  }
}
