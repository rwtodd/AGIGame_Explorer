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
        case SciSaidOp.amp:
          return '&';
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

  /// Returns the decomposed sentence-part clauses (Verb, Direct Object, Indirect Object).
  List<SciSaidClause> get clauses => SciSaidMatcher.parseSpecClauses(tokens);

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

/// A decomposed positional slot / clause in a Said specification:
/// Slot 0: Verb / Action clause
/// Slot 1: Direct Object clause
/// Slot 2: Indirect Object clause
class SciSaidClause {
  final bool isPresent;
  final bool isOptional;
  final bool isNone;
  final List<SciSaidToken> tokens;

  const SciSaidClause({
    required this.isPresent,
    required this.isOptional,
    required this.isNone,
    required this.tokens,
  });

  const SciSaidClause.omitted()
      : isPresent = false,
        isOptional = false,
        isNone = false,
        tokens = const [];

  @override
  String toString() {
    if (!isPresent) return '<omitted>';
    final s = tokens.map((t) => t.toString()).join();
    return isOptional ? '[$s]' : s;
  }
}

/// Evaluates player sentences against Sierra SCI0 `Said` specifications.
class SciSaidMatcher {
  /// Global AI hook invoked when standard matching fails or when AI mode is active.
  static SciSaidAiHook? aiHook;

  /// Evaluates whether [parsedWords] match the [spec].
  ///
  /// [vocab] is used for synonym resolution and word group translations.
  /// [rawInput] is provided for AI semantic hooks.
  /// [aiHookOverride] allows scoping an AI semantic matcher hook to an engine instance.
  static bool match(
    SciSaidSpec spec,
    List<SciVocabWord> parsedWords, {
    SciVocab? vocab,
    String? rawInput,
    SciSaidAiHook? aiHookOverride,
  }) {
    // 1. Try standard pattern matching
    final standardMatch = _matchInternal(spec, parsedWords, vocab);
    if (standardMatch) return true;

    // 2. If standard match failed and an AI hook is attached, let AI evaluate semantic intent
    final hook = aiHookOverride ?? aiHook;
    if (hook != null && rawInput != null && rawInput.trim().isNotEmpty) {
      try {
        if (hook(spec, rawInput, parsedWords)) {
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
    final specSlots = parseSpecClauses(spec.tokens);
    final inputSlots = _partitionInput(inputWords);

    // Slot 0 (Verb / Action)
    final slot0 = specSlots[0];
    if (slot0.isPresent) {
      if (inputSlots.verb.isEmpty) {
        if (!slot0.isOptional && !slot0.isNone) return false;
      } else {
        if (slot0.isNone) return false;
        if (!_matchClause(slot0.tokens, inputSlots.verb, vocab)) return false;
      }
    } else {
      // Omitted verb in sub-Said matches any input verb or empty verb
    }

    // Slot 1 (Direct Object)
    final slot1 = specSlots[1];
    if (slot1.isPresent) {
      if (inputSlots.direct.isEmpty) {
        if (!slot1.isOptional && !slot1.isNone) return false;
      } else {
        if (slot1.isNone) return false;
        if (!_matchClause(slot1.tokens, inputSlots.direct, vocab)) return false;
      }
    } else {
      if (inputSlots.direct.isNotEmpty && !spec.isNonClaiming) {
        return false;
      }
    }

    // Slot 2 (Indirect Object)
    final slot2 = specSlots[2];
    if (slot2.isPresent) {
      if (inputSlots.indirect.isEmpty) {
        if (!slot2.isOptional && !slot2.isNone) return false;
      } else {
        if (slot2.isNone) return false;
        if (!_matchClause(slot2.tokens, inputSlots.indirect, vocab)) return false;
      }
    } else {
      if (inputSlots.indirect.isNotEmpty && !spec.isNonClaiming) {
        return false;
      }
    }

    return true;
  }

  /// Parses compiled Said tokens into 3 sentence-part slots:
  /// Slot 0: Verb / Action clause
  /// Slot 1: Direct Object clause
  /// Slot 2: Indirect Object clause
  static List<SciSaidClause> parseSpecClauses(List<SciSaidToken> allTokens) {
    final tokens = allTokens
        .where((t) => t.operator != SciSaidOp.term && t.operator != SciSaidOp.gt)
        .toList();

    if (tokens.isEmpty) {
      return const [
        SciSaidClause.omitted(),
        SciSaidClause.omitted(),
        SciSaidClause.omitted(),
      ];
    }

    int p = 0;

    // Slot 0 (verb) is omitted if the spec starts with '/' or '[' followed by '/'
    final slot0Omitted = tokens[p].operator == SciSaidOp.slash ||
        (tokens[p].operator == SciSaidOp.bracketOpen &&
            p + 1 < tokens.length &&
            tokens[p + 1].operator == SciSaidOp.slash);

    SciSaidClause slot0;
    if (slot0Omitted) {
      slot0 = const SciSaidClause.omitted();
    } else {
      final slot0Tokens = <SciSaidToken>[];
      while (p < tokens.length) {
        if (tokens[p].operator == SciSaidOp.slash) break;
        if (tokens[p].operator == SciSaidOp.bracketOpen &&
            p + 1 < tokens.length &&
            tokens[p + 1].operator == SciSaidOp.slash) {
          break;
        }
        slot0Tokens.add(tokens[p]);
        p++;
      }
      slot0 = _buildClause(slot0Tokens);
    }

    // Slot 1 (Direct Object)
    SciSaidClause slot1;
    if (p < tokens.length) {
      bool isOpt = false;
      if (tokens[p].operator == SciSaidOp.bracketOpen &&
          p + 1 < tokens.length &&
          tokens[p + 1].operator == SciSaidOp.slash) {
        isOpt = true;
        p += 2; // skip '[' and '/'
      } else if (tokens[p].operator == SciSaidOp.slash) {
        p += 1; // skip '/'
      }

      final slot1Tokens = <SciSaidToken>[];
      int bracketDepth = isOpt ? 1 : 0;

      while (p < tokens.length) {
        if (bracketDepth <= (isOpt ? 1 : 0)) {
          if (tokens[p].operator == SciSaidOp.slash) break;
          if (tokens[p].operator == SciSaidOp.bracketOpen &&
              p + 1 < tokens.length &&
              tokens[p + 1].operator == SciSaidOp.slash) {
            break;
          }
        }

        if (tokens[p].operator == SciSaidOp.bracketOpen) {
          bracketDepth++;
          slot1Tokens.add(tokens[p]);
        } else if (tokens[p].operator == SciSaidOp.bracketClose) {
          bracketDepth--;
          if (isOpt && bracketDepth == 0) {
            p++; // consume matching ']'
            break;
          }
          slot1Tokens.add(tokens[p]);
        } else {
          slot1Tokens.add(tokens[p]);
        }
        p++;
      }

      slot1 = _buildClause(slot1Tokens, forcedOptional: isOpt);
    } else {
      slot1 = const SciSaidClause.omitted();
    }

    // Slot 2 (Indirect Object)
    SciSaidClause slot2;
    if (p < tokens.length) {
      bool isOpt = false;
      if (tokens[p].operator == SciSaidOp.bracketOpen &&
          p + 1 < tokens.length &&
          tokens[p + 1].operator == SciSaidOp.slash) {
        isOpt = true;
        p += 2;
      } else if (tokens[p].operator == SciSaidOp.slash) {
        p += 1;
      }

      final slot2Tokens = <SciSaidToken>[];
      int bracketDepth = isOpt ? 1 : 0;

      while (p < tokens.length) {
        if (tokens[p].operator == SciSaidOp.bracketOpen) {
          bracketDepth++;
          slot2Tokens.add(tokens[p]);
        } else if (tokens[p].operator == SciSaidOp.bracketClose) {
          bracketDepth--;
          if (isOpt && bracketDepth == 0) {
            p++;
            break;
          }
          slot2Tokens.add(tokens[p]);
        } else {
          slot2Tokens.add(tokens[p]);
        }
        p++;
      }

      slot2 = _buildClause(slot2Tokens, forcedOptional: isOpt);
    } else {
      slot2 = const SciSaidClause.omitted();
    }

    // Consume any leftover closing brackets (e.g. in nested [/door[/keyhole]])
    while (p < tokens.length && tokens[p].operator == SciSaidOp.bracketClose) {
      p++;
    }

    return [slot0, slot1, slot2];
  }

  static SciSaidClause _buildClause(
    List<SciSaidToken> tokens, {
    bool forcedOptional = false,
  }) {
    if (tokens.isEmpty && !forcedOptional) {
      return const SciSaidClause.omitted();
    }

    var cleanTokens = List<SciSaidToken>.from(tokens);
    var isOpt = forcedOptional;

    if (!isOpt &&
        cleanTokens.length >= 2 &&
        cleanTokens.first.operator == SciSaidOp.bracketOpen &&
        cleanTokens.last.operator == SciSaidOp.bracketClose) {
      var depth = 0;
      var wrapsAll = true;
      for (int i = 0; i < cleanTokens.length - 1; i++) {
        if (cleanTokens[i].operator == SciSaidOp.bracketOpen) depth++;
        if (cleanTokens[i].operator == SciSaidOp.bracketClose) depth--;
        if (depth == 0) {
          wrapsAll = false;
          break;
        }
      }
      if (wrapsAll) {
        isOpt = true;
        cleanTokens = cleanTokens.sublist(1, cleanTokens.length - 1);
      }
    }

    final isNone = cleanTokens.any((t) => t.wordGroup == SciSaidOp.wordNone) &&
        !cleanTokens.any((t) => t.isWord && t.wordGroup != SciSaidOp.wordNone && t.wordGroup != SciSaidOp.wordAny);

    return SciSaidClause(
      isPresent: true,
      isOptional: isOpt,
      isNone: isNone,
      tokens: cleanTokens,
    );
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
  ///
  /// `&` is AND: every conjunct must match. `,` is OR and is split before
  /// this is called.
  static bool _matchAlternative(
    List<SciSaidToken> altTokens,
    List<SciVocabWord> inputWords,
    SciVocab? vocab,
  ) {
    final andParts = <List<SciSaidToken>>[];
    var current = <SciSaidToken>[];
    var parenDepth = 0;
    for (final t in altTokens) {
      if (t.operator == SciSaidOp.parenOpen) parenDepth++;
      if (t.operator == SciSaidOp.parenClose) parenDepth--;
      if (t.operator == SciSaidOp.amp && parenDepth == 0) {
        andParts.add(current);
        current = <SciSaidToken>[];
      } else {
        current.add(t);
      }
    }
    andParts.add(current);

    for (final part in andParts) {
      if (!_matchAndPart(part, inputWords, vocab)) return false;
    }
    return true;
  }

  static int _resolved(int group, SciVocab? vocab) =>
      vocab?.resolveGroup(group) ?? group;

  static bool _groupInInput(int group, Set<int> inputGroups, SciVocab? vocab) {
    final resolved = _resolved(group, vocab);
    return resolved == SciSaidOp.wordAny || inputGroups.contains(resolved);
  }

  static bool _matchAndPart(
    List<SciSaidToken> tokens,
    List<SciVocabWord> inputWords,
    SciVocab? vocab,
  ) {
    var isOptional = false;
    final requiredGroups = <int>[];
    final optionalGroups = <int>[];
    final qualifiers = <int, List<int>>{};
    final optionalQualifiers = <int, List<int>>{};
    int? currentTarget;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.operator == SciSaidOp.bracketOpen) {
        isOptional = true;
      } else if (t.operator == SciSaidOp.bracketClose) {
        isOptional = false;
      } else if (t.operator == SciSaidOp.lt) {
        final target = currentTarget ?? SciSaidOp.wordAny;
        if (i + 1 < tokens.length) {
          final next = tokens[i + 1];
          if (next.isWord) {
            final dest = isOptional ? optionalQualifiers : qualifiers;
            dest.putIfAbsent(target, () => []).add(next.wordGroup!);
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

    final inputGroups =
        inputWords.map((w) => _resolved(w.group, vocab)).toSet();

    if (requiredGroups.isNotEmpty) {
      var found = false;
      for (final req in requiredGroups) {
        if (_groupInInput(req, inputGroups, vocab)) {
          final reqQuals = qualifiers[req];
          if (reqQuals != null && reqQuals.isNotEmpty) {
            if (reqQuals.any((q) => _groupInInput(q, inputGroups, vocab))) {
              found = true;
            }
          } else {
            found = true;
          }
        }
      }
      if (!found) return false;
    } else if (qualifiers.isNotEmpty) {
      // Qualifier without explicit target word in clause (e.g. `<behind`):
      for (final quals in qualifiers.values) {
        if (!quals.any((q) => _groupInInput(q, inputGroups, vocab))) {
          return false;
        }
      }
    } else if (inputWords.isNotEmpty) {
      // Optional-only clause: leftover words must belong to the optional set.
      if (optionalGroups.isEmpty) return false;
      final allowed = <int>{
        for (final g in optionalGroups) _resolved(g, vocab),
        SciSaidOp.wordAny,
      };
      if (!inputGroups.every(allowed.contains)) return false;
    }

    return true;
  }

  /// Partitions input sentence into 3 positional slots:
  /// Slot 0: Action / Verb (including phrasal verb prepositions like 'look in')
  /// Slot 1: Direct Object
  /// Slot 2: Indirect Object / Target
  static _InputSlots _partitionInput(List<SciVocabWord> inputWords) {
    if (inputWords.isEmpty) {
      return const _InputSlots(verb: [], direct: [], indirect: []);
    }

    final meaningful = inputWords
        .where((w) => w.wordClass != SciVocab.classArticle)
        .toList();

    if (meaningful.isEmpty) {
      return const _InputSlots(verb: [], direct: [], indirect: []);
    }

    final verb = <SciVocabWord>[];
    final direct = <SciVocabWord>[];
    final indirect = <SciVocabWord>[];

    int p = 0;

    final first = meaningful[0];
    final isVerb = (first.wordClass &
            (SciVocab.classIndicativeVerb | SciVocab.classImperativeVerb)) !=
        0;

    if (isVerb) {
      verb.add(first);
      p = 1;
      // If the next word is a preposition immediately following the verb (e.g. 'look in', 'turn on', 'look under'),
      // attach it to the verb phrase as part of the phrasal verb/qualifier (provided another word follows).
      if (p < meaningful.length &&
          (meaningful[p].wordClass & SciVocab.classPreposition) != 0 &&
          p + 1 < meaningful.length) {
        verb.add(meaningful[p]);
        p++;
      }
    }

    int stage = 1;
    while (p < meaningful.length) {
      final w = meaningful[p];
      if (stage == 1) {
        if ((w.wordClass & SciVocab.classPreposition) != 0 && direct.isNotEmpty) {
          stage = 2;
          indirect.add(w);
        } else {
          direct.add(w);
        }
      } else {
        indirect.add(w);
      }
      p++;
    }

    return _InputSlots(verb: verb, direct: direct, indirect: indirect);
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

class _InputSlots {
  final List<SciVocabWord> verb;
  final List<SciVocabWord> direct;
  final List<SciVocabWord> indirect;

  const _InputSlots({
    required this.verb,
    required this.direct,
    required this.indirect,
  });
}
