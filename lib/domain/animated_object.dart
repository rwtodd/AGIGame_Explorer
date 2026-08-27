import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/priority_table.dart';

/// Represents the state of an animated sprite/object slot in the Sierra AGI engine.
/// Slot 0 is always reserved for the player character (Ego).
class AnimatedObject {
  final int number;

  int x = 0;
  int y = 0;
  int prevX = 0;
  int prevY = 0;

  int view = 0;
  int loop = 0;
  int cel = 0;

  int priority = 0;
  bool fixedPriority = false;
  bool fixedLoop = false;

  int direction = 0;
  int stepSize = 1;
  int stepTime = 1;
  int stepTimer = 1;

  int cycleTime = 1;
  int cycleTimer = 1;

  bool isAnimated = false;
  bool isDrawn = false;
  bool isUpdating = true;
  bool isCycling = true;

  /// Cycle mode: 0 = normal, 1 = reverse, 2 = end_of_loop, 3 = reverse_loop.
  int cycleMode = 0;
  int? endOfLoopFlag;

  /// Motion mode: 0 = normal/stopped, 1 = wander, 2 = follow_ego, 3 = move_to.
  int motionType = 0;
  int targetX = 0;
  int targetY = 0;
  int stepDistance = 1;
  /// Original [stepSize] to restore when a `move.obj` finishes (Sierra `oldStep`).
  int oldStepSize = 1;
  int? targetFlag;

  bool ignoreHorizon = false;
  bool ignoreBlocks = false;
  bool ignoreObjects = false;

  /// Object priority/surface constraints set by `object.on.water` and `object.on.land`.
  bool onWater = false;
  bool onLand = false;

  /// Sierra `REPOS` (`ANIOBJ.control` bit 0x0400): skip this cycle's step after
  /// `SetCel` / `reposition` moved the sprite. Cleared in [MoveObjs].
  bool reposThisCycle = false;

  /// Cached [AgiView] reference for high-performance physics and cel lookups.
  AgiView? cachedView;
  int cachedViewNumber = -1;

  AnimatedObject({required this.number});

  /// Updates the cached view reference for this object.
  void updateCachedView(AgiView? v) {
    cachedView = v;
    cachedViewNumber = v?.viewNumber ?? -1;
  }

  /// Returns the number of loops in the current cached view (defaults to 4 if unavailable).
  int getLoopCount() => cachedView?.loopCount ?? 4;

  /// Returns the number of cels in [targetLoop] or current [loop] (defaults to 4 if unavailable).
  int getCelCount([int? targetLoop]) {
    final l = targetLoop ?? loop;
    return cachedView?.getLoop(l)?.celCount ?? 4;
  }

  /// Returns the width in native AGI units of [targetCel] in [targetLoop] (defaults to 12 if unavailable).
  int getCelWidth([int? targetLoop, int? targetCel, AgiView? fallbackView]) {
    final v = cachedView ?? fallbackView;
    final l = targetLoop ?? loop;
    final loopObj = v?.getLoop(l);
    var c = targetCel ?? cel;
    if (loopObj != null && loopObj.celCount > 0 && c >= loopObj.celCount) {
      c = 0;
    }
    final w = loopObj?.getCel(c)?.width;
    if (w != null && w > 0) return w;
    return (v != null) ? 12 : 4;
  }

  /// Returns the height in native AGI units of [targetCel] in [targetLoop] (defaults to 36 if unavailable).
  int getCelHeight([int? targetLoop, int? targetCel, AgiView? fallbackView]) {
    final v = cachedView ?? fallbackView;
    final l = targetLoop ?? loop;
    final loopObj = v?.getLoop(l);
    var c = targetCel ?? cel;
    if (loopObj != null && loopObj.celCount > 0 && c >= loopObj.celCount) {
      c = 0;
    }
    final h = loopObj?.getCel(c)?.height;
    if (h != null && h > 0) return h;
    return (v != null) ? 36 : 4;
  }

  /// Optional reference to the active game engine's priority table.
  AgiPriorityTable? priorityTable;

  /// Calculates priority band (4..14) based on base-Y position if priority is automatic (0).
  int get effectivePriority {
    if (fixedPriority && priority > 0) {
      return priority;
    }
    if (priorityTable != null) {
      return priorityTable!.priorityFromY(y);
    }
    return calculatePriorityForY(y);
  }

  /// Y used for sprite z-order, matching Sierra OBJLIST.C / ScummVM `sprite.cpp`.
  ///
  /// Automatic-priority objects sort by their actual baseline Y. Fixed-priority
  /// objects sort as the **top** of that priority band (`(P - 5) * 12 + 48` or via priority table),
  /// not their on-screen Y. Otherwise a `stop.update` prop planted lower on the
  /// screen (KQ2 room 48 bridge scenery) paints over Ego even when Ego is in
  /// front of that band.
  int get effectiveSortY {
    if (fixedPriority && priority > 0) {
      if (priorityTable != null) {
        return priorityTable!.priorityToY(priority);
      }
      return calculateSortYForPriority(priority);
    }
    return y;
  }

  /// Maps a fixed priority band back to the blit-sort Y (top of that band).
  static int calculateSortYForPriority(int priority) {
    if (priority <= 4) return 0;
    if (priority >= 15) return 168;
    return (priority - 5) * 12 + 48;
  }

  /// Calculates standard AGI priority band for a given Y coordinate.
  static int calculatePriorityForY(int by) {
    if (by <= 47) return 4;
    if (by <= 59) return 5;
    if (by <= 71) return 6;
    if (by <= 83) return 7;
    if (by <= 95) return 8;
    if (by <= 107) return 9;
    if (by <= 119) return 10;
    if (by <= 131) return 11;
    if (by <= 143) return 12;
    if (by <= 155) return 13;
    return 14;
  }

  /// Resets animated object state.
  void reset() {
    x = 0;
    y = 0;
    prevX = 0;
    prevY = 0;
    view = 0;
    loop = 0;
    cel = 0;
    priority = 0;
    fixedPriority = false;
    fixedLoop = false;
    direction = 0;
    stepSize = 1;
    stepTime = 1;
    stepTimer = 1;
    cycleTime = 1;
    cycleTimer = 1;
    isAnimated = false;
    isDrawn = false;
    isUpdating = true;
    isCycling = true;
    cycleMode = 0;
    endOfLoopFlag = null;
    motionType = 0;
    targetX = 0;
    targetY = 0;
    stepDistance = 1;
    oldStepSize = 1;
    targetFlag = null;
    ignoreHorizon = false;
    ignoreBlocks = false;
    ignoreObjects = false;
    onWater = false;
    onLand = false;
    reposThisCycle = false;
    cachedView = null;
    cachedViewNumber = -1;
  }

  /// Resets per-room motion, timers, and control flags on room transitions
  /// while preserving object coordinates and view assignments (following Sierra NEWROOM.C).
  void resetForNewRoom({bool preserveDirection = false}) {
    priority = 0;
    fixedPriority = false;
    fixedLoop = false;
    if (!preserveDirection) {
      direction = 0;
    }
    stepSize = 1;
    stepTime = 1;
    stepTimer = 1;
    cycleTime = 1;
    cycleTimer = 1;
    isAnimated = false;
    isDrawn = false;
    isUpdating = true;
    isCycling = true;
    cycleMode = 0;
    endOfLoopFlag = null;
    motionType = 0;
    targetX = 0;
    targetY = 0;
    stepDistance = 1;
    oldStepSize = 1;
    targetFlag = null;
    ignoreHorizon = false;
    ignoreBlocks = false;
    ignoreObjects = false;
    onWater = false;
    onLand = false;
    reposThisCycle = false;
  }

  /// Sierra `EndMoveObj`: restore the step size saved by `move.obj`.
  void endMoveObj() {
    if (motionType == 3) {
      stepSize = oldStepSize;
    }
    motionType = 0;
  }

  /// Sierra VIEW.C `SetCel` border clamp after a cel, loop, or view change.
  ///
  /// If the new cel hangs off the right edge, `x` is set to `160 - width`.
  /// If it hangs off the top (`y - height < -1`), `y` is set to `height - 1`,
  /// then bumped to [horizon]+1 unless [ignoreHorizon]. Either clamp sets
  /// [reposThisCycle] so MOVEOBJS.C skips this cycle's step.
  ///
  /// Does nothing when no view is bound (Sierra errors; we cannot measure).
  void clipCelToScreen({int horizon = 36}) {
    if (cachedView == null) return;

    final width = getCelWidth();
    final height = getCelHeight();
    var repos = false;

    if (x + width > 160) {
      x = 160 - width;
      repos = true;
    }

    if (y - height < -1) {
      y = height - 1;
      repos = true;
      if (y <= horizon && !ignoreHorizon) {
        y = horizon + 1;
      }
    }

    if (repos) {
      reposThisCycle = true;
    }
  }
}
