import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/parser/agi_said_matcher.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';

/// Represents an extracted `said(...)` pattern from an AGI logic script.
class ExtractedSaidCommand {
  /// The logic script number where this said statement was found (e.g. 0 for Logic 0, or room number).
  final int scriptNumber;

  /// The raw word group IDs from the bytecode.
  final List<int> wordGroupIds;

  /// The canonical human-readable phrase (e.g. "look screen", "take key").
  final String canonicalPhrase;

  /// All synonyms for each word slot.
  final List<List<String>> wordSynonyms;

  const ExtractedSaidCommand({
    required this.scriptNumber,
    required this.wordGroupIds,
    required this.canonicalPhrase,
    this.wordSynonyms = const [],
  });

  /// Default upper bound on generated candidate phrases per command.
  static const int defaultMaxCandidates = 20;

  /// Generates clean candidate phrases for semantic matching
  /// using the Cartesian product of deduplicated word synonyms.
  List<String> generateCandidatePhrases({int maxCandidates = defaultMaxCandidates}) {
    if (wordSynonyms.isEmpty) return [canonicalPhrase];

    final canonicalTokens = canonicalPhrase.split(' ');
    final slots = <List<String>>[];

    for (var i = 0; i < wordSynonyms.length; i++) {
      final synList = wordSynonyms[i];
      final valid = synList
          .where((w) =>
              w != '<any>' &&
              w != '<rol>' &&
              !w.startsWith('word_') &&
              !AgiSaidExtractor.isDemotedWord(w) &&
              w.trim().isNotEmpty)
          .toList();

      if (i < canonicalTokens.length) {
        final canon = canonicalTokens[i].trim();
        if (canon.isNotEmpty && canon != 'anyword' && canon != 'rol') {
          if (!valid.contains(canon)) {
            valid.insert(0, canon);
          }
        }
      }

      slots.add(valid.isEmpty ? const [''] : valid);
    }

    List<String> combinations = [''];
    for (final slot in slots) {
      final next = <String>[];
      for (final prefix in combinations) {
        for (final word in slot) {
          final s = word.isEmpty
              ? prefix
              : (prefix.isEmpty ? word : '$prefix $word');
          next.add(s.trim());
          if (next.length >= maxCandidates * 2) break;
        }
        if (next.length >= maxCandidates * 2) break;
      }
      combinations = next;
    }
    var results = combinations.where((c) => c.isNotEmpty).toSet().toList();
    if (results.isEmpty) {
      return [canonicalPhrase];
    }
    results.remove(canonicalPhrase);
    results.insert(0, canonicalPhrase);
    if (results.length > maxCandidates) {
      results = results.sublist(0, maxCandidates);
    }
    return results;
  }

  /// Formats this command for LLM prompts, including distinctive alternative synonyms.
  /// Example: "look wizard (synonyms: manannan, magician, sorcerer)"
  String toPromptDescription() {
    if (wordSynonyms.isEmpty) return canonicalPhrase;

    final altWords = <String>{};
    final canonicalTokens = canonicalPhrase.split(' ');

    for (final synList in wordSynonyms) {
      for (final syn in synList) {
        if (syn != '<any>' &&
            syn != '<rol>' &&
            !syn.startsWith('word_') &&
            !canonicalTokens.contains(syn) &&
            syn.length > 1) {
          altWords.add(syn);
        }
      }
    }

    if (altWords.isEmpty) return canonicalPhrase;
    // Cap at top 6 most relevant alternative synonyms to keep prompt compact
    final preview = altWords.take(6).join(', ');
    return '$canonicalPhrase (synonyms: $preview)';
  }

  @override
  String toString() => '$canonicalPhrase ($wordGroupIds) [Logic $scriptNumber]';
}

/// Utility for extracting and canonicalizing `said(...)` statements from AGI logic scripts.
class AgiSaidExtractor {
  final InstructionDecoder decoder;
  final Map<int, List<ExtractedSaidCommand>> _scriptCache = {};

  AgiSaidExtractor({double version = 2.917})
      : decoder = InstructionDecoder(version: version);

  /// Clears the cached extracted said commands.
  void clearCache() => _scriptCache.clear();

  /// Previously extracted commands for [scriptNumber], if any.
  List<ExtractedSaidCommand>? peekScript(int scriptNumber) =>
      _scriptCache[scriptNumber];

  /// Stores [commands] so later submits do not reload the logic resource.
  List<ExtractedSaidCommand> rememberScript(
    int scriptNumber,
    List<ExtractedSaidCommand> commands,
  ) {
    _scriptCache[scriptNumber] = commands;
    return commands;
  }

  /// Number of scripts currently cached in memory.
  int get cachedScriptCount => _scriptCache.length;

  /// Recursively walks a [LogicInstruction] node to find all [SaidInstruction] instances.
  List<SaidInstruction> findSaidInstructions(LogicInstruction node) {
    final results = <SaidInstruction>[];
    _collectSaid(node, results);
    return results;
  }

  void _collectSaid(LogicInstruction node, List<SaidInstruction> results) {
    if (node is SaidInstruction) {
      results.add(node);
    } else if (node is CompoundInstruction) {
      for (final child in node.instructions) {
        _collectSaid(child, results);
      }
    } else if (node is IfInstruction) {
      _collectSaid(node.condition, results);
      _collectSaid(node.thenBlock, results);
      if (node.elseBlock != null) {
        _collectSaid(node.elseBlock!, results);
      }
    } else if (node is UnlessGotoInstruction) {
      _collectSaid(node.condition, results);
    } else if (node is OrInstruction) {
      _collectSaid(node.condition, results);
    } else if (node is NotInstruction) {
      _collectSaid(node.inner, results);
    }
  }

  /// Extracts all [ExtractedSaidCommand]s from [script], caching results per [scriptNumber].
  List<ExtractedSaidCommand> extractFromScript({
    required AgiLogicScript script,
    required AgiDictionary dictionary,
    int scriptNumber = 0,
  }) {
    if (script.bytecodes.isEmpty) {
      return rememberScript(scriptNumber, const []);
    }

    final cached = _scriptCache[scriptNumber];
    if (cached != null) {
      return cached;
    }

    List<ExtractedSaidCommand> results;
    try {
      final root = decoder.decode(script.bytecodes);
      final saidNodes = findSaidInstructions(root);
      results = <ExtractedSaidCommand>[];
      final seenPhrases = <String>{};

      for (final said in saidNodes) {
        final phrase = formatWordGroupIds(said.wordGroupIds, dictionary);
        if (phrase.isNotEmpty && !seenPhrases.contains(phrase)) {
          seenPhrases.add(phrase);
          final synonyms = said.wordGroupIds.map((id) {
            if (id == AgiSaidMatcher.anyWord) return ['<any>'];
            if (id == AgiSaidMatcher.restOfLine) return ['<rol>'];
            return dictionary.idToDeduplicatedWords(id);
          }).toList();

          results.add(
            ExtractedSaidCommand(
              scriptNumber: scriptNumber,
              wordGroupIds: said.wordGroupIds,
              canonicalPhrase: phrase,
              wordSynonyms: synonyms,
            ),
          );
        }
      }
    } catch (_) {
      // Fallback: raw bytecode scanner if disassembler encounters partial or corrupted tail opcodes
      results = _extractFromRawBytecode(
        byteCode: script.bytecodes,
        dictionary: dictionary,
        scriptNumber: scriptNumber,
      );
    }

    _scriptCache[scriptNumber] = results;
    return results;
  }

  /// Extracts said commands from room logic, additional active overlay logics, and Logic 0.
  List<ExtractedSaidCommand> extractActiveRoomCommands({
    required AgiLogicScript? logic0,
    required AgiLogicScript? roomLogic,
    Iterable<AgiLogicScript> additionalLogics = const [],
    required AgiDictionary dictionary,
    int roomNumber = 0,
  }) {
    final combined = <ExtractedSaidCommand>[];
    final seen = <String>{};

    // 1. Primary room-specific commands
    if (roomLogic != null) {
      final roomCommands = extractFromScript(
        script: roomLogic,
        dictionary: dictionary,
        scriptNumber: roomNumber,
      );
      for (final cmd in roomCommands) {
        if (seen.add(cmd.canonicalPhrase)) {
          combined.add(cmd);
        }
      }
    }

    // 2. Additional active logics (e.g. dynamic overlay logics, NPCs)
    for (final extra in additionalLogics) {
      if (extra.logicNumber == roomNumber || extra.logicNumber == 0) continue;
      final extraCommands = extractFromScript(
        script: extra,
        dictionary: dictionary,
        scriptNumber: extra.logicNumber ?? 0,
      );
      for (final cmd in extraCommands) {
        if (seen.add(cmd.canonicalPhrase)) {
          combined.add(cmd);
        }
      }
    }

    // 3. Global Logic 0 commands (fallback priority)
    if (logic0 != null) {
      final globalCommands = extractFromScript(
        script: logic0,
        dictionary: dictionary,
        scriptNumber: 0,
      );
      for (final cmd in globalCommands) {
        if (seen.add(cmd.canonicalPhrase)) {
          combined.add(cmd);
        }
      }
    }

    return combined;
  }

  /// Extracts all unique word group IDs tested by `said(...)` (0x0E) opcodes in [byteCode].
  static Set<int> extractSaidWordGroupIds(List<int> byteCode) {
    final wordIds = <int>{};
    var i = 0;
    while (i < byteCode.length) {
      if (byteCode[i] == 0x0E && i + 1 < byteCode.length) {
        final count = byteCode[i + 1];
        if (count > 0 && count <= 10 && i + 1 + (count * 2) <= byteCode.length) {
          for (var w = 0; w < count; w++) {
            final offset = i + 2 + (w * 2);
            final wordId = byteCode[offset] | (byteCode[offset + 1] << 8);
            if (wordId > 1 && wordId < 9999) {
              wordIds.add(wordId);
            }
          }
          i += 2 + (count * 2);
          continue;
        }
      }
      i++;
    }
    return wordIds;
  }

  /// Fallback scanner that scans raw bytecode for opcode 0x0E (said test).
  List<ExtractedSaidCommand> _extractFromRawBytecode({
    required List<int> byteCode,
    required AgiDictionary dictionary,
    required int scriptNumber,
  }) {
    final results = <ExtractedSaidCommand>[];
    final seenPhrases = <String>{};
    var i = 0;

    while (i < byteCode.length) {
      // 0x0E is said opcode
      if (byteCode[i] == 0x0E && i + 1 < byteCode.length) {
        final count = byteCode[i + 1];
        if (count > 0 && count <= 10 && i + 1 + (count * 2) <= byteCode.length) {
          final wordIds = <int>[];
          var valid = true;
          for (var w = 0; w < count; w++) {
            final offset = i + 2 + (w * 2);
            final wordId = byteCode[offset] | (byteCode[offset + 1] << 8);
            if (wordId == 0) {
              valid = false;
              break;
            }
            wordIds.add(wordId);
          }

          if (valid && wordIds.isNotEmpty) {
            final phrase = formatWordGroupIds(wordIds, dictionary);
            if (phrase.isNotEmpty && seenPhrases.add(phrase)) {
              final synonyms = wordIds.map((id) {
                if (id == AgiSaidMatcher.anyWord) return ['<any>'];
                if (id == AgiSaidMatcher.restOfLine) return ['<rol>'];
                return dictionary.idToDeduplicatedWords(id);
              }).toList();
              results.add(
                ExtractedSaidCommand(
                  scriptNumber: scriptNumber,
                  wordGroupIds: wordIds,
                  canonicalPhrase: phrase,
                  wordSynonyms: synonyms,
                ),
              );
            }
          }
        }
      }
      i++;
    }

    return results;
  }

  /// List of preferred canonical words in order of display preference.
  static const List<String> preferredAgiWords = [
    // Core Actions / Verbs
    'look', 'take', 'get', 'catch', 'talk', 'ask', 'give', 'open', 'close',
    'use', 'read', 'drop', 'eat', 'drink', 'climb', 'jump', 'kill',
    'push', 'pull', 'unlock', 'lock', 'swim', 'throw', 'wear', 'enter',
    'exit', 'cast', 'fly', 'sit', 'stand', 'pay', 'buy', 'feed', 'pet',
    'show', 'help', 'save', 'restore', 'quit', 'restart', 'pause',
    'examine', 'search', 'listen', 'smell', 'touch', 'feel', 'kiss',
    'hit', 'fight', 'cut', 'break', 'turn', 'move', 'ride', 'drive',
    'board', 'leave', 'sleep', 'wake', 'hide', 'sneak', 'steal', 'bribe',

    // Core Nouns & Entities
    'wizard', 'manannan', 'door', 'key', 'cupboard', 'chest', 'box',
    'book', 'spell', 'wand', 'screen', 'computer', 'ship', 'button',
    'switch', 'lever', 'rock', 'stone', 'boulder', 'tree', 'flower', 'water',
    'ocean', 'sea', 'lake', 'pond', 'beach', 'sand',
    'clam', 'shell', 'clamshell',
    'food', 'meat', 'bread', 'potion', 'bottle', 'cup', 'glass', 'jar',
    'gold', 'coin', 'purse', 'money', 'treasure', 'diamond', 'gem',
    'ring', 'sword', 'knife', 'dagger', 'rope', 'ladder', 'stairs', 'steps',
    'window', 'wall', 'floor', 'ceiling', 'bed', 'table', 'chair',
    'desk', 'mirror', 'clock', 'candle', 'torch', 'lamp', 'fire',
    'hat', 'cap', 'cape', 'cloak', 'pot', 'cauldron', 'casket', 'coffin',
    'rug', 'carpet', 'cave', 'cavern', 'castle', 'palace',
    'girl', 'woman', 'man', 'boy', 'guard', 'king', 'queen', 'prince',
    'princess', 'witch', 'fairy', 'cat', 'dog', 'bird', 'eagle', 'dragon', 'snake',
    'horse', 'donkey', 'chicken', 'fish', 'mermaid', 'monster', 'bear',
  ];

  static final Map<String, int> preferredWordRanks = {
    for (int i = 0; i < preferredAgiWords.length; i++) preferredAgiWords[i]: i,
  };

  /// Set of vulgarities or slurs heavily demoted so they never become prototypes.
  static const Set<String> _demotedWords = {
    'bitch', 'cunt', 'slut', 'whore', 'hose bag', 'sperm burping gutter slut',
    'fuck', 'fucking', 'shit', 'piss', 'ass', 'asshole', 'bastard', 'cock',
    'dick', 'tits', 'boobs', 'fag', 'faggot',
  };

  /// Whether [word] is an obscenity or slur that should be excluded from AI candidate generation.
  static bool isDemotedWord(String word) {
    final clean = word.trim().toLowerCase();
    return _demotedWords.contains(clean);
  }

  /// Returns a sorting rank for [word] to order words for display or clustering.
  /// Lower numbers indicate higher preference / priority.
  static int wordPriority(String word) {
    final clean = word.trim().toLowerCase();
    if (_demotedWords.contains(clean)) {
      return 1000000 + clean.length;
    }
    final prefRank = preferredWordRanks[clean];
    if (prefRank != null) {
      return prefRank;
    }
    // Prefer single-word clean tokens over multi-word phrases or hyphenated words
    if (clean.contains(' ') || clean.contains('-')) {
      return 20000 + clean.length;
    }
    // Clean single word: prioritize shorter words
    return 1000 + clean.length;
  }

  /// Comparator that orders words by [wordPriority], with alphabetical tie-breaking.
  static int compareWordPriority(String a, String b) {
    final pa = wordPriority(a);
    final pb = wordPriority(b);
    if (pa != pb) return pa.compareTo(pb);
    return a.compareTo(b);
  }

  /// Picks the most natural canonical word from a list of synonyms.
  static String chooseCanonicalWord(List<String> synonyms) {
    if (synonyms.isEmpty) return '';
    if (synonyms.length == 1) return synonyms.first;

    final sorted = List<String>.from(synonyms)..sort(compareWordPriority);
    return sorted.first;
  }

  /// Formats word group IDs into a canonical space-separated phrase.
  static String formatWordGroupIds(List<int> wordGroupIds, AgiDictionary dictionary) {
    final words = <String>[];
    for (final id in wordGroupIds) {
      if (id == AgiSaidMatcher.anyWord) {
        words.add('anyword');
      } else if (id == AgiSaidMatcher.restOfLine) {
        // Skip trailing ROL in canonical display phrase unless isolated
        if (words.isEmpty) words.add('rol');
      } else {
        final list = dictionary.idToWords(id);
        if (list.isNotEmpty) {
          words.add(chooseCanonicalWord(list));
        } else {
          words.add('word_$id');
        }
      }
    }
    return words.join(' ').trim();
  }
}
