// Sierra SCI0 Said bytecode parser and pattern matcher.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';

/// Pluggable AI semantic matcher hook (for Gemini natural language intent matching).
typedef SciSaidAiHook = bool Function(
  SciSaidSpec spec,
  String rawInput,
  List<SciVocabWord> parsedWords,
);

/// Said bytecode operators.
class SciSaidOp {
  static const int comma = 0xF0; // OR operator
  static const int amp = 0xF1; // AND operator
  static const int slash = 0xF2; // Clause separator
  static const int parenOpen = 0xF3; // Group open
  static const int parenClose = 0xF4; // Group close
  static const int bracketOpen = 0xF5; // Optional open
  static const int bracketClose = 0xF6; // Optional close
  static const int hash = 0xF7; // Debug
  static const int lt = 0xF8; // Qualifier / preposition ('<')
  static const int gt = 0xF9; // Non-claiming match ('>')
  static const int term = 0xFF; // Terminator

  static const int wordNone = 0x0FFE; // 4094, '!*' (nothing)
  static const int wordAny = 0x0FFF; // 4095, '*' (anyword)
}

/// An individual token inside a compiled Said spec.
class SciSaidToken {
  final int? operator;
  final int? wordGroup;

  bool get isOperator => operator != null;
  bool get isWord => wordGroup != null;

  const SciSaidToken.op(int this.operator) : wordGroup = null;
  const SciSaidToken.word(int this.wordGroup) : operator = null;

  @override
  String toString() {
    if (isOperator) {
      switch (operator) {
        case SciSaidOp.comma:
          return ',';
        case SciSaidOp.slash:
          return '/';
        case SciSaidOp.parenOpen:
          return '(';
        case SciSaidOp.parenClose:
          return ')';
        case SciSaidOp.bracketOpen:
          return '[';
        case SciSaidOp.bracketClose:
          return ']';
        case SciSaidOp.lt:
          return '<';
        case SciSaidOp.gt:
          return '>';
        case SciSaidOp.term:
          return 'TERM';
        default:
          return '0x${operator!.toRadixString(16)}';
      }
    }
    if (wordGroup == SciSaidOp.wordNone) return '!*';
    if (wordGroup == SciSaidOp.wordAny) return '*';
    return '$wordGroup';
  }
}

/// A parsed Sierra SCI0 `Said` bytecode specification.
class SciSaidSpec {
  final Uint8List rawBytes;
  final List<SciSaidToken> tokens;
  final bool isNonClaiming;

  SciSaidSpec({
    required this.rawBytes,
    required this.tokens,
    required this.isNonClaiming,
  });

  /// Decodes raw Said bytecode from [data] starting at [offset].
  factory SciSaidSpec.fromBytes(Uint8List data, [int offset = 0]) {
    final tokens = <SciSaidToken>[];
    var isNonClaiming = false;
    var p = offset;

    while (p < data.length) {
      final b = data[p++];
      if (b >= 0xF0) {
        if (b == SciSaidOp.term) {
          tokens.add(const SciSaidToken.op(SciSaidOp.term));
          break;
        }
        if (b == SciSaidOp.gt) {
          isNonClaiming = true;
          tokens.add(const SciSaidToken.op(SciSaidOp.gt));
          continue;
        }
        tokens.add(SciSaidToken.op(b));
      } else {
        // Big-endian 16-bit word group ID
        if (p >= data.length) break;
        final b1 = data[p++];
        final group = (b << 8) | b1;
        tokens.add(SciSaidToken.word(group));
      }
    }

    final specBytes = data.sublist(offset, p);
    return SciSaidSpec(
      rawBytes: specBytes,
      tokens: tokens,
      isNonClaiming: isNonClaiming,
    );
  }

  /// Decompiles the Said spec into a human-readable and LLM-friendly string,
  /// e.g. `look/door`, `open/compartment<glove`, or `[open]/door`.
  String toSaidString(SciVocab? vocab) {
    final sb = StringBuffer();

    for (final token in tokens) {
      if (token.operator == SciSaidOp.term || token.operator == SciSaidOp.gt) {
        continue;
      }
      if (token.isOperator) {
        sb.write(token.toString());
      } else if (token.isWord) {
        final g = token.wordGroup!;
        if (vocab != null) {
          sb.write(vocab.getWordGroupText(g));
        } else {
          sb.write(token.toString());
        }
      }
    }

    return sb.toString();
  }

  @override
  String toString() => toSaidString(null);
}

/// Evaluates player sentences against Sierra SCI0 `Said` specifications.
class SciSaidMatcher {
  /// Global AI hook invoked when standard matching fails or when AI mode is active.
  static SciSaidAiHook? aiHook;

  /// Evaluates whether [parsedWords] match the [spec].
  ///
  /// [vocab] is used for synonym resolution and word group translations.
  /// [rawInput] is provided for AI semantic hooks.
  static bool match(
    SciSaidSpec spec,
    List<SciVocabWord> parsedWords, {
    SciVocab? vocab,
    String? rawInput,
  }) {
    // 1. Try standard pattern matching
    final standardMatch = _matchInternal(spec, parsedWords, vocab);
    if (standardMatch) return true;

    // 2. If standard match failed and an AI hook is attached, let AI evaluate semantic intent
    if (aiHook != null && rawInput != null && rawInput.trim().isNotEmpty) {
      try {
        if (aiHook!(spec, rawInput, parsedWords)) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Internal clause-based matcher for SCI0 Said specs.
  static bool _matchInternal(
    SciSaidSpec spec,
    List<SciVocabWord> inputWords,
    SciVocab? vocab,
  ) {
    if (inputWords.isEmpty) {
      // Empty input only matches if spec is empty or all optional
      return _specMatchesEmpty(spec);
    }

    // Split Said tokens into clauses divided by '/'
    final clauses = <List<SciSaidToken>>[];
    var currentClause = <SciSaidToken>[];

    for (final token in spec.tokens) {
      if (token.operator == SciSaidOp.term) break;
      if (token.operator == SciSaidOp.slash) {
        clauses.add(currentClause);
        currentClause = <SciSaidToken>[];
      } else if (token.operator != SciSaidOp.gt) {
        currentClause.add(token);
      }
    }
    clauses.add(currentClause);

    // Organize input words into semantic clauses (Action, DirectObj, IndirectObj)
    final inputClauses = _partitionInput(inputWords);

    // If input has more clauses than spec, no match
    if (inputClauses.length > clauses.length) {
      return false;
    }

    // Match each clause
    for (int i = 0; i < clauses.length; i++) {
      final specClause = clauses[i];
      final inputClause = i < inputClauses.length ? inputClauses[i] : <SciVocabWord>[];

      final matched = _matchClause(specClause, inputClause, vocab);
      if (!matched) return false;
    }

    return true;
  }

  /// Checks if a Said spec accepts an empty input sentence.
  static bool _specMatchesEmpty(SciSaidSpec spec) {
    // If empty or only brackets / wordNone
    var insideBracket = false;
    for (final t in spec.tokens) {
      if (t.operator == SciSaidOp.term) break;
      if (t.operator == SciSaidOp.bracketOpen) insideBracket = true;
      if (t.operator == SciSaidOp.bracketClose) insideBracket = false;
      if (t.isWord && !insideBracket && t.wordGroup != SciSaidOp.wordNone) {
        return false;
      }
    }
    return true;
  }

  /// Matches a single clause (e.g. `look,examine` or `compartment<glove` or `[open]`)
  /// against the input words in that clause.
  static bool _matchClause(
    List<SciSaidToken> specClause,
    List<SciVocabWord> inputWords,
    SciVocab? vocab,
  ) {
    // If input is empty: matches if clause is optional [ ... ] or specifies !* (wordNone)
    if (inputWords.isEmpty) {
      if (specClause.isEmpty) return true;
      if (_clauseIsOptional(specClause)) return true;
      if (specClause.any((t) => t.wordGroup == SciSaidOp.wordNone)) return true;
      return false;
    }

    // If spec specifies !* (none), it must NOT have input words
    if (specClause.any((t) => t.wordGroup == SciSaidOp.wordNone && !_isInsideOptional(specClause, t))) {
      return false;
    }

    // Split clause into alternatives separated by comma (',')
    final alternatives = _splitAlternatives(specClause);

    for (final alt in alternatives) {
      if (_matchAlternative(alt, inputWords, vocab)) {
        return true;
      }
    }

    return false;
  }

  /// Matches one alternative branch within a clause against input words.
  static bool _matchAlternative(
    List<SciSaidToken> altTokens,
    List<SciVocabWord> inputWords,
    SciVocab? vocab,
  ) {
    var isOptional = false;
    final requiredGroups = <int>[];
    final optionalGroups = <int>[];
    final qualifiers = <int, List<int>>{};
    int? currentTarget;

    for (int i = 0; i < altTokens.length; i++) {
      final t = altTokens[i];
      if (t.operator == SciSaidOp.bracketOpen) {
        isOptional = true;
      } else if (t.operator == SciSaidOp.bracketClose) {
        isOptional = false;
      } else if (t.operator == SciSaidOp.lt) {
        // Preposition qualifier following a noun: target < qualifier
        if (currentTarget != null && i + 1 < altTokens.length) {
          final next = altTokens[i + 1];
          if (next.isWord) {
            qualifiers.putIfAbsent(currentTarget, () => []).add(next.wordGroup!);
            i++;
          }
        }
      } else if (t.isWord) {
        currentTarget = t.wordGroup!;
        if (isOptional) {
          optionalGroups.add(t.wordGroup!);
        } else {
          requiredGroups.add(t.wordGroup!);
        }
      }
    }

    final inputGroups = inputWords.map((w) => vocab?.resolveGroup(w.group) ?? w.group).toSet();

    // If there are required words, at least one must match, or ANYWORD
    if (requiredGroups.isNotEmpty) {
      var found = false;
      for (final req in requiredGroups) {
        final resolvedReq = vocab?.resolveGroup(req) ?? req;
        if (resolvedReq == SciSaidOp.wordAny || inputGroups.contains(resolvedReq)) {
          // Check qualifiers if any
          final reqQuals = qualifiers[req];
          if (reqQuals != null && reqQuals.isNotEmpty) {
            final hasQual = reqQuals.any((q) =>
                q == SciSaidOp.wordAny || inputGroups.contains(vocab?.resolveGroup(q) ?? q));
            if (hasQual) found = true;
          } else {
            found = true;
          }
        }
      }
      if (!found) return false;
    }

    return true;
  }

  /// Partitions input sentence into up to 3 clauses:
  /// Clause 0: Action / Verb
  /// Clause 1: Direct Object
  /// Clause 2: Indirect Object / Target
  static List<List<SciVocabWord>> _partitionInput(List<SciVocabWord> inputWords) {
    if (inputWords.isEmpty) return [];

    final clauses = <List<SciVocabWord>>[];
    final clause0 = <SciVocabWord>[];
    final clause1 = <SciVocabWord>[];
    final clause2 = <SciVocabWord>[];

    int stage = 0;

    for (final word in inputWords) {
      // Noise / article words can be skipped
      if (word.wordClass == SciVocab.classArticle) continue;

      if (stage == 0) {
        clause0.add(word);
        // If word is a verb or first word, advance to direct object stage
        if ((word.wordClass & (SciVocab.classIndicativeVerb | SciVocab.classImperativeVerb)) != 0 ||
            clause0.isNotEmpty) {
          stage = 1;
        }
      } else if (stage == 1) {
        // If word is preposition, advance to indirect object
        if ((word.wordClass & SciVocab.classPreposition) != 0 && clause1.isNotEmpty) {
          stage = 2;
          clause2.add(word);
        } else {
          clause1.add(word);
        }
      } else {
        clause2.add(word);
      }
    }

    if (clause0.isNotEmpty) clauses.add(clause0);
    if (clause1.isNotEmpty) clauses.add(clause1);
    if (clause2.isNotEmpty) clauses.add(clause2);

    return clauses.isEmpty ? [inputWords] : clauses;
  }

  /// Splits tokens in a clause by comma (',').
  static List<List<SciSaidToken>> _splitAlternatives(List<SciSaidToken> clause) {
    final list = <List<SciSaidToken>>[];
    var current = <SciSaidToken>[];

    int parenDepth = 0;
    int bracketDepth = 0;

    for (final t in clause) {
      if (t.operator == SciSaidOp.parenOpen) parenDepth++;
      if (t.operator == SciSaidOp.parenClose) parenDepth--;
      if (t.operator == SciSaidOp.bracketOpen) bracketDepth++;
      if (t.operator == SciSaidOp.bracketClose) bracketDepth--;

      if (t.operator == SciSaidOp.comma && parenDepth == 0 && bracketDepth == 0) {
        list.add(current);
        current = <SciSaidToken>[];
      } else {
        current.add(t);
      }
    }
    list.add(current);
    return list;
  }

  static bool _clauseIsOptional(List<SciSaidToken> clause) {
    return clause.isNotEmpty &&
        clause.first.operator == SciSaidOp.bracketOpen &&
        clause.last.operator == SciSaidOp.bracketClose;
  }

  static bool _isInsideOptional(List<SciSaidToken> clause, SciSaidToken target) {
    var inOpt = false;
    for (final t in clause) {
      if (t.operator == SciSaidOp.bracketOpen) inOpt = true;
      if (t.operator == SciSaidOp.bracketClose) inOpt = false;
      if (identical(t, target) || (t.wordGroup == target.wordGroup && t.operator == target.operator)) {
        return inOpt;
      }
    }
    return false;
  }
}
