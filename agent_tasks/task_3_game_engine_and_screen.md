# Task: AgiGameEngine & Live Game Playfield Screen

## Objective
Implement the main `AgiGameEngine` 20 Hz cycle coordinator and the interactive `GameScreen` / `GamePlayfieldWidget` that renders room scenes with active sprites, status bar, text command prompt, and dialog popup boxes.

## Files to Create/Update
- `lib/engine/agi_game_engine.dart` (Main game cycle driver and state machine)
- `lib/ui/screens/game/game_screen.dart` (Game view screen with status bar, canvas, prompt, dialogs)
- `lib/ui/widgets/game_playfield_widget.dart` (Composite canvas for 16 priority slices + active sprites)
- `lib/ui/widgets/dialog_box_widget.dart` (Retro EGA message popup for `print`/`display`)
- `test/engine/game_engine_test.dart` (Unit and engine cycle tests)
- `test/ui/game_screen_test.dart` (Widget tests for the game screen)

## Key Concepts & Specifications (Reference: `Features_Roadmap.md` & Sierra AGI Specs)
1. **Game Cycle (20 ticks/sec = 50ms per tick)**:
   - Phase 1: Accept input (keyboard directions, parsed text command).
   - Phase 2: Update motion & cel animations (via `AgiMotionController`).
   - Phase 3: Execute `LOGIC 0` scan cycle with `AgiLogicInterpreter`.
   - Phase 4: Prepare render frame (composite active sprites & background slices).
   - Cycle cleanup: Clear transient flags (Flag 1 `f1=0`, Flag 2 `have.input=0`, Flag 4 `said.accepted=0`).

2. **Room Transitions (`new.room` / `new.room.v`)**:
   - Save Ego's state / position according to border crossed.
   - Unload room-specific logic scripts and dynamic sprites.
   - Load new room PICTURE (`loadPic`), decode priority/visual buffers, compute 16 depth slices.
   - Load new room LOGIC script (`loadLogic`).
   - Set Flag 5 (`new_room = 1`) and Variable 1 (`current_room = roomNumber`).
   - Run initial scan of `LOGIC 0` and room LOGIC to initialize room objects and backdrop views (`add.to.pic`).

3. **Playfield Compositor (`GamePlayfieldWidget`)**:
   - 160x168 playfield aspect-ratio corrected (scaled to 320x200 4:3).
   - Renders 16 depth slices of background (`PictureSlicer`).
   - In each priority layer, renders active `AnimatedObject`s whose priority matches that layer.
   - Renders sprites using `ViewTextureAtlas` / `AgiView` cels with nearest-neighbor filtering.

4. **UI Overlays**:
   - **Top Status Bar**: Line 0 shows `"Score: X of Y   Sound: ON"`.
   - **Bottom Command Prompt**: Line 22–24 shows `>` text input field with blinking cursor and arrow key history.
   - **Modal Dialog Box**: Displays text for `print(msg)` with classic white/gray EGA border and "Press Enter or Space" dismissal.

5. **Interpreter Delegate Integration**:
   - Implement `AgiInterpreterDelegate`:
     - `onNewRoom`: Triggers room transition.
     - `onPrint` / `onPrintAt` / `onDisplay`: Displays dialog box / on-screen text.
     - `onSound`: Triggers sound playback via `AgiSoundPlayer`.
     - `onAddToPic`: Burns static sprite into background visual and priority buffers.
     - `checkSaid`: Queries `AgiSaidMatcher`.

## Verification
- Run `flutter test test/engine/game_engine_test.dart test/ui/game_screen_test.dart`
- Run `dart analyze`
