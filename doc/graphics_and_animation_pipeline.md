# Sierra AGI Graphics & Animation Pipeline Architecture

## 1. Overview & Problem Definition

In classic Sierra AGI (1984–1989), the interpreter ran on DOS, Apple IIGS, and Amiga platforms using a single-threaded synchronous loop:
1. Poll player input.
2. Update object motion vectors and cel animation counters.
3. Execute `LOGIC 0` and called room scripts.
4. Erase old object bounding boxes from the 320x200 16-color backbuffer.
5. Draw new object cels into the backbuffer.
6. Blit updated rects directly to the hardware display buffer.
7. Delay for `Var[10]` ticks (typically 50ms for 20 Hz "Normal" speed).

In modern Flutter / GPU engines, **raw pixel bytes cannot be drawn directly by the GPU `Canvas` without first being uploaded as GPU textures (`ui.Image`)**. Because Flutter's texture upload mechanism (`ui.decodeImageFromPixels`) is asynchronous, a naive implementation creates a race condition between the 20 Hz logic coordinator and the 60/120 Hz render pipeline:

- **Cel Flashing / Dropped Frames**: When an actor switched to a new loop (e.g. turning West) or a script drew an object, if the texture was not yet in GPU memory, the renderer skipped drawing the actor for that frame.
- **Ungated Cel Cycling**: While the asynchronous GPU upload for cel 0 was in flight, the 20 Hz logic loop continued ticking and advanced the actor's cel index (0 -> 1 -> 2). By the time the texture was ready, cel 0 was never displayed to the user, making animations appear to flash, pop, or teleport.
- **Directional Desynchronization**: Keypress handlers that immediately triggered UI repaints before updating the actor's loop rendered 1 frame of the actor moving in the new direction while still facing the old direction.

---

## 2. Solution Architecture

### 2.1 Per-Room Dynamic View Texture Atlas (`ViewTextureAtlas` & `ViewAtlasManager`)

Rather than maintaining hundreds of individual `ui.Image` cel textures and decoding them on demand, the engine bundles all cels for active room views into a single compact GPU texture atlas:

```
+-------------------------------------------------------------+
| ViewTextureAtlas (e.g. 256x256 RGBA)                        |
|                                                             |
| +----------------+ +----------------+ +------------------+  |
| | View 0 Loop 0  | | View 0 Loop 2  | | View 0 Loop 3    |  |
| | (Ego East)     | | (Ego South)    | | (Ego North)      |  |
| +----------------+ +----------------+ +------------------+  |
|                                                             |
| +----------------+ +----------------+                        |
| | View 1 Loop 0  | | View 2 Loop 0  |                        |
| | (NPC / Object) | | (Door / Prop)  |                        |
| +----------------+ +----------------+                        |
+-------------------------------------------------------------+
```

1. **Lightweight Scope**: Only Ego and views loaded by the room's logic via `load.view` are packaged in the atlas. Unused views from prior rooms are freed upon room transition (`changeRoom`).
2. **Re-Entrant Build Loop**: `ViewAtlasManager.prepareAtlasAsync()` uses a `do { ... } while (_isDirty)` loop. When multiple `load.view` calls occur in rapid succession during room startup, the manager automatically folds all views into the build without dropping dirty state.
3. **Dynamic Side-Atlases**: If a LOGIC script loads additional views mid-room, secondary side-atlases are compiled without invalidating the primary atlas.

---

### 2.2 Horizontal Draw Transforms for Mirrored Loops

In Sierra AGI, West-facing walk loops are mirrored copies of East-facing loops. 

Instead of allocating duplicate pixels in the texture atlas, `ViewAtlasBuilder` shares the unmirrored cel's `sourceRect` for both loops. When drawing a mirrored cel, `ViewTextureAtlas.drawCel()` applies a scale transform (`scaleX: -2.0`) to flip the sprite horizontally on the fly:

```dart
canvas.save();
canvas.translate(position.dx + (entry.width * 2.0), position.dy);
canvas.scale(-2.0, 1.0);
canvas.drawImageRect(image!, entry.sourceRect, destRect, paint);
canvas.restore();
```

This cuts texture memory by up to 50% for standard 4-loop character views.

---

### 2.3 Gated Animation Accounting (Zero-Drop Guarantee)

In `AgiGameEngine._advanceObjectCel(AnimatedObject obj)`:
- The engine checks whether the current cel is resident in the GPU atlas (`atlasManager.containsCel(obj.view, obj.loop, obj.cel)`).
- If a newly loaded view or cel is still in the middle of a GPU upload, the engine **holds** the animation counter in place and does not advance `obj.cel`.
- Once the texture is uploaded and rendered, standard animation cycling resumes. Every cel in every loop is guaranteed to be presented on screen.

```dart
void _advanceObjectCel(AnimatedObject obj) {
  // Gate animation cycling: hold cel until current cel is GPU-resident
  if (!atlasManager.containsCel(obj.view, obj.loop, obj.cel)) {
    return;
  }
  final celCount = obj.getCelCount();
  if (celCount <= 1) return;
  // Advance cycle mode (normal, reverse, end_of_loop, reverse_loop)...
}
```

---

### 2.4 Directional Keypress Loop Synchronization

When the player presses a directional key (e.g. Left / West), `setEgoDirection()` immediately calculates the target loop via `_updateLoopForDirection(ego)` before notifying the UI:

```dart
void setEgoDirection(int direction, {bool toggleIfSame = true}) {
  if (!_isUserControl) return;
  if (toggleIfSame && direction != 0 && ego.direction == direction) {
    ego.direction = 0;
  } else {
    ego.direction = direction.clamp(0, 8);
  }
  memory.setVar(6, ego.direction);
  if (ego.direction != 0) {
    ego.isCycling = true;
    ego.isAnimated = true;
    if (!ego.fixedLoop) {
      _updateLoopForDirection(ego); // Instant loop sync
    }
  } else {
    ego.isCycling = false;
  }
  notifyListeners();
}
```

This eliminates the single-frame lag where Ego moved with the old facing direction before the next 20 Hz tick.

---

### 2.5 Pre-Bucketed 16-Layer Compositor Sorting

In `AgiPicturePainter._paintCompositedSlices`:
- AGI uses 16 depth layers (priorities 0..15).
- Rather than running 16 `.where((a) => a.priority == p).toList()..sort(...)` queries per frame (which generated over 1,000 allocations/sec), actors are sorted into fixed priority buckets once per repaint:

```dart
final bucketedActors = List<List<AgiActorSprite>>.generate(16, (_) => []);
for (final actor in actors) {
  final pri = actor.priority.clamp(0, 15);
  bucketedActors[pri].add(actor);
}
for (var p = 0; p < 16; p++) {
  final layerActors = bucketedActors[p];
  if (layerActors.length > 1) {
    layerActors.sort((a, b) => a.baselineY.compareTo(b.baselineY));
  }
  // Draw background slice p, then layerActors...
}
```

---

### 2.6 Synchronous Picture & Logic Lifecycle with Immediate Raw Pixel Fallback

1. **Synchronous Dart Bytecode & Resource Parsing**:
   - Dart bytecode VM execution (`executeCycle()`, `resume()`, `stepInstruction()`) is completely synchronous at native speed.
   - Resource loading (`loadPic(n)`, `loadView(n)`, `loadLogic(n)`) immediately parses vector opcodes and creates in-memory visual buffers and priority buffers synchronously on the CPU without awaiting microtask queues.

2. **Immediate Raw CPU Cel Drawing Fallback**:
   - `AgiActorSprite` retains `rawCel` and `parentView` references.
   - When Flutter renders a frame before the asynchronous GPU texture atlas (`ui.Image`) has finished uploading to VRAM, the painter falls back to `_drawRawCel(Canvas)`: drawing the 16-color EGA bitmap synchronously via direct rectangle batches.
   - As a result, no actor or sprite is ever dropped or rendered invisible while texture atlases are in flight.

---

### 2.7 Strict Room Entry Lifecycle (`currentPic = null` until `draw.pic`)

- In authentic Sierra AGI (and NAGI reference `new_room.c`), entering a room via `new.room(n)` or `changeRoom(n)` sets `currentPic = null`.
- Preemptively loading a room picture before the room's script runs `draw.pic(n)` violates script sequencing (such as in Space Quest 2 Room 6, where the introductory dialog message displays over an unpopulated throne room before `draw.pic` and actor heads/hands are drawn).
- By maintaining `currentPic = null` until the script explicitly executes `draw.pic(n)`, the visual playfield accurately mirrors Sierra's authentic render sequencing.

---

## 3. Verification Guidelines

When modifying graphics or engine motion code, verify the following test suites:

```bash
# 1. Texture atlas packing, mirroring, and async manager tests
flutter test test/ui/view_texture_atlas_test.dart

# 2. Complete UI and widget render tests
flutter test test/ui/

# 3. Motion, loop selection, and cel animation cycling tests
flutter test test/engine/motion_test.dart test/engine/ego_animation_test.dart

# 4. Reference game boot and room lifecycle tests
flutter test test/engine/game_startup_test.dart test/engine/sq2_vohaul_capture_test.dart

# 5. Full static analysis
dart analyze
```

