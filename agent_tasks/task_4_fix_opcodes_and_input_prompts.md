# Task: Fix View-Querying Opcodes & Input Prompts

## Objective
Implement real VIEW-querying logic for `last.cel` and `number.of.loops`, add interactive string/number input prompts (`get.string`, `get.num`), and implement string parsing opcodes (`word.to.string`, `parse`) in `lib/logic/interpreter/` and `lib/engine/`.

## Files to Create/Update
- `lib/logic/interpreter/agi_interpreter.dart`
- `lib/logic/interpreter/agi_interpreter_delegate.dart`
- `lib/ui/widgets/input_prompt_dialog.dart` (Dialog for `get.string` and `get.num`)
- `lib/engine/agi_game_engine.dart` (Delegate implementation for input prompts and view resolution)
- `test/interpreter/view_query_opcodes_test.dart` (Unit tests)
- `test/engine/input_prompts_test.dart` (Unit & widget tests)

## Key Concepts & Specifications

1. **`last.cel(o, %v)` (Opcode 49)**:
   - Queries the active `AgiView` resource for object `o.view`.
   - Looks up `o.loop` in the view: `final celCount = view.loops[o.loop].cels.length`.
   - Sets variable `%v = celCount - 1`.
   - If view is not loaded or loop is out of range, safely defaults to `o.cel`.

2. **`number.of.loops(o, %v)` (Opcode 53)**:
   - Queries the active `AgiView` resource for object `o.view`.
   - Sets variable `%v = view.loops.length`.
   - Safely defaults to `1` if view is not available.

3. **`get.string(s, m, row, col, maxLen)` (Opcode 115)**:
   - Prompts player with message `m` at position `(row, col)` or modal text input dialog.
   - Max input length clamped to `maxLen`.
   - On submit, stores text into `memory.setString(s, text)`.

4. **`get.num(m, %v)` (Opcode 118)**:
   - Prompts player with message `m` asking for numeric input (e.g. gambling bets in *LSL1*, magic spells in *KQ3*).
   - On submit, stores integer value into `memory.setVar(v, number.clamp(0, 255))`.

5. **`word.to.string(w, s)` (Opcode 116) & `parse(s)` (Opcode 117)**:
   - `word.to.string(w, s)`: Converts vocabulary word group ID `w` into its primary text string and assigns to string register `s`.
   - `parse(s)`: Tokenizes string register `s` through `AgiTextParser` and sets `AgiSaidMatcher` inputs as if typed by user.

6. **`AgiInterpreterDelegate` Extensions**:
   - Add `AgiView? getView(int viewNumber)`
   - Add `Future<String?> onGetString(String prompt, int row, int col, int maxLen)`
   - Add `Future<int?> onGetNum(String prompt)`

## Verification
- Run `flutter test test/interpreter/view_query_opcodes_test.dart test/engine/input_prompts_test.dart`
- Run `dart analyze`
