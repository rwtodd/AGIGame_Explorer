# Sierra AGI Motion, Collision & Water Physics Architecture

## 1. Overview & Core Concepts

In Sierra On-Line's Adventure Game Interpreter (AGI v2 & v3), actor movement and environment interactions are driven by the 160x168 **Priority Buffer** (`PriorityBuffer`), the actor's cel dimensions, and per-cycle physics constraints.

The priority buffer contains two 4-bit nibbles per pixel:
- **Visual Priority (Upper Nibble / Priority 4–15)**: Determines depth sorting against 3D picture geometry.
- **Control / Physics Lines (Priority 0–3)**:
  - **Priority 0 (Black)**: Unconditional barrier. No object may ever enter or cross priority 0.
  - **Priority 1 (Blue)**: Conditional barrier (`block`). Respected unless `ignore.blocks` is active.
  - **Priority 2 (Green)**: Alarm / Trigger line. Sets `Flag 3` (`VM_FLAG_EGO_TOUCHED_P2`) when touched by Ego.
  - **Priority 3 (Cyan)**: Water surface. Controls swimming, wading, and drowning states via `Flag 0` (`VM_FLAG_EGO_WATER`).

---

## 2. Water Surface Detection & Flag 0 Lifecycle

### 2.1 The Baseline Rule (`CMOBJSBR.ASM` / `checks.cpp`)
In Sierra's original assembly (`CMOBJSBR.ASM:CanBHere`) and ScummVM (`checks.cpp:checkPriority`):
- When Ego is walking, `Flag 0` is set to `true` **if and only if all pixels across Ego's baseline** are on priority 3 (water).
- If any baseline pixel is on land (priority > 3), `Flag 0` remains `false`.
- This ensures that an actor walking along a shoreline or path adjacent to water does not trigger water scripts prematurely.

```
       Land (Pri 4)             Shoreline        Water (Pri 3)
+------------------------+-------------------+--------------------+
|                        |                   |                    |
|       [ Ego Cel ]      |    [ Ego Cel ]    |     [ Ego Cel ]    |
|       Baseline: 4 4    |    Baseline: 4 3  |     Baseline: 3 3  |
|       Flag 0 = FALSE   |    Flag 0 = FALSE |     Flag 0 = TRUE  |
+------------------------+-------------------+--------------------+
```

### 2.2 Surface Mode Control (`object.on.water` / `object.on.land`)
AGI scripts dictate surface constraints using opcodes:
- `object.on.water(o)` (opcode 88): Sets `PRICTRL1` (`fOnWater`). The actor **must** be entirely on water.
- `object.on.land(o)` (opcode 89): Sets `PRICTRL2` (`fOnLand`). The actor **must not** be entirely on water.
- `object.on.anything(o)` (opcode 90): Clears both constraints.

### 2.3 Per-Cycle Constraint Reset (`ANIMATE.C:182` / `view.cpp:684`)
A critical detail in Sierra's engine is that `object.on.water` and `object.on.land` applied to Ego are **temporary transitional constraints**:
```c
/* Clear the 'must be on water or land' bits for ego */
ego->control &= ~(PRICTRL1 | PRICTRL2);
```
At the end of each animation cycle (after updating motion and checking priority), the engine resets `ego.onWater = false` and `ego.onLand = false`. 

**Why this is required**:
If `ego.onLand` remained active indefinitely while walking on land, Ego would be permanently barred from stepping into water to swim. Conversely, if `ego.onWater` remained active indefinitely while swimming, Ego would be blocked from stepping onto islands or beaches to return to land.

---

## 3. Sprite Transitions & Position Correction (`posShuffle` / `fixPosition`)

### 3.1 The Wide Sprite Shoreline Problem
When Ego enters water (e.g. in *King's Quest 2* Room 8 ocean or Room 9 lake):
1. Ego's walking sprite (e.g. View 0, width 6) steps fully into water (`x=22..27`).
2. `Flag 0` becomes `true`.
3. Game logic executes:
   ```agi
   object.on.water(ego)
   set.view(ego, 104)   // Wide splash/wading animation (width 19)
   stop.motion(ego)
   ```
4. Because View 104 is 19 pixels wide, Ego's bounding box at `x=22` extends from `x=22` to `x=40`.
   - `x=22..27` is water (priority 3).
   - `x=28..40` is beach (priority 4).
5. If the engine stopped checking position because Ego was stationary (`direction == 0`), Ego would remain stuck straddling the beach with `Flag 0` evaluating to `false`. Typing `swim` would fail with *"You need to be in the water in order to swim."*

### 3.2 Spiral Search Position Correction (`FINDPOSN.C` / `checks.cpp`)
In ScummVM (`checks.cpp:updatePosition`) and Sierra AGI (`MOVEOBJS.C:MoveObjs`):
- Every active, updating object is checked every cycle against priority and collision rules, even when stationary (`dx == 0, dy == 0`).
- If an object violates collision or its active `fOnWater` / `fOnLand` constraint, the engine invokes `posShuffle(obj)` (`FindPosn` / `fixPosition`).
- `posShuffle` performs a spiral outward search:
  1. West (`x--`)
  2. South (`y++`)
  3. East (`x++`)
  4. North (`y--`)
- When Ego switches to the wide splash cel (View 104) with `onWater` active, `posShuffle` automatically shifts Ego westward from `x=22` to `x=10`, placing the entire 19-pixel sprite in priority 3 water.
- At `(10, 70)`, `Flag 0` is naturally evaluated as `true` under the standard baseline rule without any game-specific view hardcoding.

---

## 4. Cross-Room Transitions & Flag 0 Hand-off (`NEWROOM.C`)

### 4.1 Cross-Room State Inspection
In games such as *King's Quest 1* (e.g. swimming North from Room 37 swamp into Room 44 dry woodcutter cabin):
- The dry room's initialization logic checks whether Ego entered from water in the previous room:
  ```agi
  if (isset(%f5)) {
      load.pic(%v0)
      draw.pic(%v0)
      discard.pic(%v0)
      if (equaln(%v1, 37) && isset(%f0)) {
          set.view(%o0, 0)   // Return to walking view
          reset(%f98)        // Clear swimming flag
          assignn(%v94, 0)   // Return to walking mode
      }
      draw(%o0)
      show.pic
  }
  ```
- In Sierra AGI (`NEWROOM.C`), `NewRoom(n)` sets `Set(INITLOGS)` (`Flag 5 = true`) but **never resets `Flag 0`**.
- Similarly, `draw.pic` (`PICTURE.C:DrawPic`) only renders background pixels and vectors; it does **not** evaluate priority buffer flags or execute `posShuffle` in the middle of executing a room script's initialization code.
- This guarantees that `Flag 0` from the prior room remains intact during the initial `Flag 5` scan until the first full animation cycle completes.

---

## 5. Summary of Architecture Rules

| State / Operation | Mechanism | Reference |
| :--- | :--- | :--- |
| **Flag 0 Evaluation** | Baseline `x` to `x + width - 1` must all be Priority 3. | `CMOBJSBR.ASM:103-125`, `checks.cpp:127-166` |
| **Flag 3 Evaluation** | Any baseline pixel touches Priority 2. | `CMOBJSBR.ASM:135`, `checks.cpp:144-165` |
| **Room Transitions** | `new.room` sets `%f5 = 1` and preserves `%f0` for new room script inspection. | `NEWROOM.C:113`, `new_room.c:120` |
| **Picture Drawing** | `draw.pic` / `show.pic` do not prematurely mutate actor flags or positions. | `PICTURE.C:140-154` |
| **Water / Land Flags** | Reset at the conclusion of each animation frame. | `ANIMATE.C:180-183`, `view.cpp:684` |
| **Reposition Shuffling** | `posShuffle` runs whenever an updating object violates constraints. | `FINDPOSN.C:45-80`, `checks.cpp:301-349` |
| **Reposition Skipping** | Setting `reposThisCycle` skips motion on that tick. | `MOVEOBJS.C:66-71`, `obj_motion.c:130` |

