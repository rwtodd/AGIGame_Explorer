import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

/// Evaluates script `said(...)` test commands against parsed user input.
///
/// In Sierra AGI:
/// - `said(count, w1, w2, ...)` tests if the player's input matches the word group IDs.
/// - Special wildcard `9999` (`ANYWORD` / `_ANY`) matches any single word token.
/// - Special wildcard `9998` (`ROL` / `_ROL` - Rest of Line) matches 0 or more remaining words.
/// - When a match occurs, Flag 4 (`said.accepted`) is set to 1.
/// - If Flag 2 (`have.input`) is 0 or Flag 4 is already 1, `said()` returns false.
class AgiSaidMatcher {
  /// Special wildcard ID matching any single word token.
  static const int anyWord = 9999;

  /// Special wildcard ID matching zero or more remaining words.
  static const int restOfLine = 9998;

  /// Optional reference to engine memory for flag/var synchronization.
  final AgiMemory? memory;

  List<int>? _currentWordIds;
  bool _hasInput = false;
  bool _saidAccepted = false;

  AgiSaidMatcher({this.memory});

  /// Whether user input was entered this cycle and is available to match (AGI Flag 2).
  bool get hasInput => memory != null ? memory!.getFlag(2) : _hasInput;

  /// Whether a `said(...)` test has already matched and accepted this cycle's input (AGI Flag 4).
  bool get saidAccepted => memory != null ? memory!.getFlag(4) : _saidAccepted;

  /// The active non-zero word group IDs for the current cycle.
  List<int> get currentWordIds => _currentWordIds ?? const [];

  /// Sets the active input word group IDs for the cycle (sets Flag 2, resets Flag 4).
  void setInput(List<int> wordGroupIds) {
    _currentWordIds = List.unmodifiable(wordGroupIds);
    _hasInput = true;
    _saidAccepted = false;
    if (memory != null) {
      memory!.setFlag(2); // have.input = 1
      memory!.resetFlag(4); // said.accepted = 0
    }
  }

  /// Convenience helper to set input from an [AgiParseResult].
  ///
  /// If [result] failed due to an unknown word, resets Flag 2 and sets Variable 9
  /// to the 1-based index of the unrecognized word in [memory].
  void setInputFromResult(AgiParseResult result) {
    if (result.isSuccess && result.wordGroupIds.isNotEmpty) {
      setInput(result.wordGroupIds);
    } else {
      clearInput();
      if (result.unknownWordIndex != null && memory != null) {
        memory!.setVar(9, result.unknownWordIndex!); // v9 = unrecognized word index
      }
    }
  }

  /// Clears the input state (called at the end of an interpreter cycle).
  void clearInput() {
    _currentWordIds = null;
    _hasInput = false;
    _saidAccepted = false;
    if (memory != null) {
      memory!.resetFlag(2); // have.input = 0
      memory!.resetFlag(4); // said.accepted = 0
    }
  }

  /// Evaluates a `said(...)` opcode pattern against the current user input.
  ///
  /// Returns `true` if `hasInput` is true, `saidAccepted` is false, and [pattern]
  /// matches `currentWordIds`. When returning `true`, marks `saidAccepted` as true
  /// and sets Flag 4 in [memory].
  bool checkSaid(List<int> pattern) {
    if (!hasInput || saidAccepted) {
      return false;
    }

    final words = _currentWordIds ?? const [];
    if (matchWords(pattern, words)) {
      _saidAccepted = true;
      if (memory != null) {
        memory!.setFlag(4); // said.accepted = 1
      }
      return true;
    }

    return false;
  }

  /// Pure pattern matching function that tests whether [pattern] matches [userWords].
  ///
  /// Handles:
  /// - Exact word group ID matches
  /// - `9999` ([anyWord]): matches any single word at this position
  /// - `9998` ([restOfLine]): matches zero or more words up to end of input
  static bool matchWords(List<int> pattern, List<int> userWords) {
    return _matchHelper(pattern, 0, userWords, 0);
  }

  static bool _matchHelper(
    List<int> pattern,
    int pIdx,
    List<int> input,
    int iIdx,
  ) {
    // Both exhausted -> match
    if (pIdx == pattern.length) {
      return iIdx == input.length;
    }

    final p = pattern[pIdx];

    if (p == restOfLine) {
      // ROL at end of pattern consumes all remaining input words (0 or more)
      if (pIdx == pattern.length - 1) {
        return true;
      }
      // ROL followed by more pattern words: try all partition lengths
      for (var k = iIdx; k <= input.length; k++) {
        if (_matchHelper(pattern, pIdx + 1, input, k)) {
          return true;
        }
      }
      return false;
    }

    // Pattern still expects words, but input is exhausted
    if (iIdx >= input.length) {
      return false;
    }

    // Match exact word or ANYWORD wildcard
    if (p == anyWord || p == input[iIdx]) {
      return _matchHelper(pattern, pIdx + 1, input, iIdx + 1);
    }

    return false;
  }
}

/// An [AgiInterpreterDelegate] implementation wired to an [AgiSaidMatcher].
class SaidMatchingInterpreterDelegate extends DefaultAgiInterpreterDelegate {
  final AgiSaidMatcher matcher;
  final AgiDictionary? _dictionary;

  SaidMatchingInterpreterDelegate(this.matcher, [this._dictionary]);

  @override
  AgiDictionary? get dictionary => _dictionary;

  @override
  bool checkSaid(List<int> wordGroupIds) => matcher.checkSaid(wordGroupIds);

  @override
  void onParse(String input) {
    if (_dictionary != null) {
      final parser = AgiTextParser(_dictionary);
      final result = parser.parse(input);
      matcher.setInputFromResult(result);
    }
  }
}
