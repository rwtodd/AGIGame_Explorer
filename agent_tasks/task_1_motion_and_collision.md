# Task: Object Motion, Collision & Animation Physics

## Objective
Implement the AGI sprite motion, collision detection, and animation cycling engine in `lib/engine/motion/` with complete unit tests.

## Files to Create/Update
- `lib/engine/motion/agi_motion_controller.dart` (Motion coordinator)
- `lib/engine/motion/collision_detector.dart` (Priority/Control screen barrier collision)
- `test/engine/motion_test.dart` (Unit test suite)
- `test/engine/collision_test.dart` (Collision test suite)

## Key Concepts & Specifications (Reference: `Features_Roadmap.md` & Sierra AGI Specs)
1. **Direction Codes (0–8)**:
   - 0 = Stopped
   - 1 = North (0, -1)
   - 2 = North-East (1, -1)
   - 3 = East (1, 0)
   - 4 = South-East (1, 1)
   - 5 = South (0, 1)
   - 6 = South-West (-1, 1)
   - 7 = West (-1, 0)
   - 8 = North-West (-1, -1)

2. **Motion Types on `AnimatedObject` (`lib/domain/animated_object.dart`)**:
   - `normal`: Follows current `motionDirection` set by player or script.
   - `wander`: Randomly changes direction when hitting obstacles or after random steps.
   - `followEgo`: Moves towards Ego (Object 0) by computing shortest directional vector.
   - `moveObj`: Moves towards target `(targetX, targetY)` with `stepSize`. When target is reached, stops motion, sets `direction = 0`, and raises `targetFlag` in `AgiMemory`.

3. **Collision Detection with `PriorityBuffer` (`lib/domain/priority_buffer.dart`)**:
   - An object's base position is `(x, y)` with width `w` and height `h`.
   - The baseline test spans from `(x, y)` to `(x + w - 1, y)`.
   - Unless `ignore.blocks` is set, pixels with priority value `0` (unconditional barrier) block movement.
   - If `observe.blocks` is active, conditional barriers (priority `1`) also block.
   - Screen boundaries:
     - X clamped between 0 and `160 - width`.
     - Y clamped between horizon (usually 36, unless `ignore.horizon` is set) and `167`.
     - Crossing screen edges updates `AgiMemory.variables[2]` (`edge_obj_hit`) and `variables[4]` (`edge_ego_hit`):
       - Edge 1 = Top (Horizon)
       - Edge 2 = Right (`x + w >= 160`)
       - Edge 3 = Bottom (`y >= 167`)
       - Edge 4 = Left (`x <= 0`)

4. **Cel Animation Cycling**:
   - `cycleTime` and `cycleTimer`: Advance `currentCel = (currentCel + 1) % celCount` when timer expires.
   - `stepTime` and `stepTimer`: Move position by `stepSize` when timer expires.
   - Loop selection: Automatically chooses loop corresponding to motion direction (e.g. Loop 0 = Right/East, Loop 1 = Left/West, Loop 2 = South, Loop 3 = North, if `fixedLoop` is false).

## Verification
- Run `flutter test test/engine/motion_test.dart test/engine/collision_test.dart`
- Run `dart analyze`
