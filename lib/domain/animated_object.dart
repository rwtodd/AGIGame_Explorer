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
  int? targetFlag;

  bool ignoreHorizon = false;
  bool ignoreBlocks = false;
  bool ignoreObjects = false;

  AnimatedObject({required this.number});

  /// Calculates priority band (4..14) based on base-Y position if priority is automatic (0).
  int get effectivePriority {
    if (fixedPriority && priority > 0) {
      return priority;
    }
    return calculatePriorityForY(y);
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
    targetFlag = null;
    ignoreHorizon = false;
    ignoreBlocks = false;
    ignoreObjects = false;
  }
}
