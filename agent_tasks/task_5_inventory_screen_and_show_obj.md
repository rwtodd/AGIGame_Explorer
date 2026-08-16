# Task: Interactive Inventory Screen & `show.obj` Item Viewer

## Objective
Implement the full interactive inventory dialog (`status()` / TAB) and item inspection modal (`show.obj`) in `lib/ui/` and `lib/engine/` with comprehensive widget and unit tests.

## Files to Create/Update
- `lib/ui/widgets/inventory_dialog.dart` (Full inventory dialog with item list & keyboard navigation)
- `lib/ui/widgets/object_inspection_dialog.dart` (Item modal displaying name, description, and sprite cel)
- `lib/engine/agi_game_engine.dart` (Hook `status()` and `show.obj` callbacks)
- `test/ui/inventory_dialog_test.dart` (Widget & unit tests)

## Key Concepts & Specifications

1. **`status()` (Opcode 124) / Inventory Screen**:
   - Triggered when script calls `status()` or player presses `TAB` or types `"inventory"`.
   - Filters all items where `memory.itemRooms[itemNumber] == 0` (carried in inventory).
   - If player has no items, displays `"You are carrying nothing."`
   - If player has items, displays modal dialog listing all carried inventory item names in clean EGA styled grid/list.
   - Allows keyboard navigation (Up/Down arrow keys) and mouse hover/click.
   - Actions available:
     - **Inspect / Look (`Enter` or double click)**: Opens `show.obj` dialog for the selected item.
     - **Close / Cancel (`ESC` or Space or click)**: Dismisses inventory screen and resumes game loop.

2. **`show.obj(i)` (Opcode 129) & `show.obj.v(%v)` (Opcode 162)**:
   - Displays a dedicated item modal box:
     - Item name (from `AgiObject.name`).
     - Item sprite preview: Resolves corresponding VIEW resource using `ObjectViewResolver` (or `gameLoader.loadView`) and renders the cel centered with transparency.
     - Description text if available.
     - Pressing Enter, Space, or clicking closes the modal.

3. **`AgiInterpreterDelegate` & `AgiGameEngine` Hooks**:
   - `void onStatus()`: Pauses game tick timer and opens `InventoryDialog`.
   - `void onShowObj(int objectNumber)`: Pauses game tick timer and opens `ObjectInspectionDialog`.

## Verification
- Run `flutter test test/ui/inventory_dialog_test.dart`
- Run `dart analyze`
