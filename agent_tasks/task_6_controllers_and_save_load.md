# Task: Controller Keys & Save/Load/Restart Game State System

## Objective
Implement keyboard controller / function key mapping (`set.key`, F1–F10, TAB, ESC) and full game state serialization for save, restore, and restart (`save.game`, `restore.game`, `restart.game`) in `lib/engine/` and `lib/ui/` with complete unit & widget tests.

## Files to Create/Update
- `lib/engine/state/game_state_serializer.dart` (JSON-based `.sav` save state serializer/deserializer)
- `lib/engine/controllers/agi_controller_manager.dart` (Key to controller mapping for `set.key` and `controller(c)` test)
- `lib/ui/widgets/save_load_dialog.dart` (Interactive Save & Restore slot manager modal)
- `lib/engine/agi_game_engine.dart` (Hook controller key events and save/load/restart actions)
- `test/engine/save_load_test.dart` (Unit tests for serialization/deserialization)
- `test/engine/controller_manager_test.dart` (Unit tests for controller mappings)

## Key Concepts & Specifications

1. **`set.key(scancode, ascii, ctlCode)` (Opcode 121) & `controller(c)` (Test Opcode 12)**:
   - Scripts configure keyboard shortcuts using `set.key`:
     - Standard mappings in Sierra games:
       - `F1`: Help (often Controller 1)
       - `F2`: Toggle Sound (often Controller 2)
       - `F3`: Retype Last Line (often Controller 3)
       - `F5`: Save Game (often Controller 5)
       - `F7`: Restore Game (often Controller 7)
       - `F9`: Restart Game (often Controller 9)
       - `TAB` / `F10`: Status / Inventory (often Controller 10)
       - `ESC`: Menu Bar
   - When a physical key or shortcut is pressed:
     - The corresponding controller flag is raised in `memory.controllers[ctlCode] = true`.
     - Test opcode `controller(c)` evaluates to `true` during the cycle (and is reset at the end of the cycle).

2. **Save & Restore State Serialization (`GameStateSerializer`)**:
   - `save.game()` (Opcode 125) & `restore.game()` (Opcode 126):
     - Saves/loads full game state snapshots to JSON files (e.g. `slot_0.sav`, `slot_1.sav` in game directory or App Documents):
       - `version`: Game engine version string
       - `currentRoom`: `memory.getVar(0)`
       - `previousRoom`: `memory.getVar(1)`
       - `variables`: List of all 256 byte values
       - `flags`: Set/List of all 256 boolean values
       - `strings`: Map of all string registers 0..23
       - `itemRooms`: Map of all inventory item locations
       - `score`: `memory.getVar(3)`
       - `animatedObjects`: State of all animated objects (position `x, y`, `view`, `loop`, `cel`, `priority`, `direction`, `motionType`, `isDrawn`, `isAnimated`, flags)
       - `scoreMax`: Maximum possible score if known
       - `timestamp`: Date/time of save
       - `description`: Player-provided save slot label (e.g. `"In front of castle"`)

3. **Save / Restore Dialog (`SaveLoadDialog`)**:
   - Modal dialog listing save slots (Slots 1–12) with custom names and timestamps.
   - In Save mode: Allows typing a description for the selected slot and saving.
   - In Restore mode: Allows picking an existing slot and restoring state.
   - On successful restore: Reloads room PICTURE, redraws active views, reloads room LOGIC, sets Flag 5 (`new_room = 1`), and resumes.

4. **`restart.game()` (Opcode 128)**:
   - Displays confirmation dialog `"Are you sure you want to restart the game? (Y/N)"`.
   - On confirmation: Resets memory (variables, flags, strings, inventory to initial game objects), reloads Logic 0 and starting room, and restarts cycle.

## Verification
- Run `flutter test test/engine/save_load_test.dart test/engine/controller_manager_test.dart`
- Run `dart analyze`
