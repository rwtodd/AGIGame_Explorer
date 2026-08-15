# Task: Text Parser, Tokenizer & `said()` Matcher

## Objective
Implement user text input tokenization, dictionary filtering, and script `said(...)` pattern matching in `lib/engine/parser/` with full unit testing.

## Files to Create/Update
- `lib/engine/parser/agi_text_parser.dart` (Tokenization, contraction expansion, group lookup)
- `lib/engine/parser/agi_said_matcher.dart` (Pattern matcher for `said()` opcodes)
- `test/engine/parser_test.dart` (Unit tests for parser and matcher)

## Key Concepts & Specifications (Reference: `Features_Roadmap.md` & Sierra AGI Specs)
1. **Input Normalization**:
   - Converts text to lowercase, trims whitespace.
   - Replaces punctuation (periods, commas, semicolons, exclamation marks, question marks) with spaces.
   - Normalizes common English contractions (e.g., `"don't"` -> `"dont"`, `"can't"` -> `"cant"`, `"it's"` -> `"its"`, `"i'm"` -> `"im"`).

2. **Dictionary Group Lookup (`AgiDictionary` from `lib/domain/dictionary.dart`)**:
   - For each word, query `dictionary.wordToId(word)`.
   - **Ignored Words (Group 0)**: Words like "a", "the", "at", "to", "in" have group ID 0. These MUST be filtered out from the final `parsedWordIds` list.
   - **Unknown Words**: If `wordToId(word) == -1`, mark as unknown word and provide error message (e.g. `"I don't understand '<word>'"`).
   - If all words are recognized and non-zero, set `List<int> parsedWordIds`.

3. **`said(...)` Opcode Matching**:
   - Script opcode `said(int count, List<int> wordGroupIds)` checks if the user's parsed word IDs match the expected group IDs.
   - **Special Wildcard IDs**:
     - `9999` (`ANYWORD` / `_ANY`): Matches any single word in this position.
     - `9998` (`ROL` / `_ROL` - Rest of Line): Matches zero or more remaining words in the input.
   - **Standard Matching Rule**:
     - Exact count & group match: Every expected group ID matches `parsedWordIds[i]`.
     - Once matched, the matcher records that the phrase was accepted (setting Flag 4 `said.accepted = 1`).
     - Flag 2 (`have.input`) indicates a command was entered this cycle and is reset at the end of the cycle if not accepted.

4. **Integration with `AgiInterpreterDelegate`**:
   - Connect to `bool checkSaid(List<int> wordGroupIds)` on `AgiInterpreterDelegate` so the running `AgiLogicInterpreter` calls this matcher.

## Verification
- Run `flutter test test/engine/parser_test.dart`
- Run `dart analyze`
