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
    if (script.bytecodes.isEmpty) return const [];

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
            return dictionary.idToWords(id);
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

  /// Extracts said commands from both Logic 0 (global) and the active room logic.
  List<ExtractedSaidCommand> extractActiveRoomCommands({
    required AgiLogicScript? logic0,
    required AgiLogicScript? roomLogic,
    required AgiDictionary dictionary,
    int roomNumber = 0,
  }) {
    final combined = <ExtractedSaidCommand>[];
    final seen = <String>{};

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
              results.add(
                ExtractedSaidCommand(
                  scriptNumber: scriptNumber,
                  wordGroupIds: wordIds,
                  canonicalPhrase: phrase,
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
  static const List<String> _preferredAgiWords = [
    // Core Actions / Verbs
    'look', 'take', 'get', 'talk', 'ask', 'give', 'open', 'close',
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
    'switch', 'lever', 'rock', 'stone', 'tree', 'flower', 'water',
    'food', 'meat', 'bread', 'potion', 'bottle', 'cup', 'glass',
    'gold', 'coin', 'purse', 'money', 'treasure', 'diamond', 'gem',
    'ring', 'sword', 'knife', 'dagger', 'rope', 'ladder', 'stairs',
    'window', 'wall', 'floor', 'ceiling', 'bed', 'table', 'chair',
    'desk', 'mirror', 'clock', 'candle', 'torch', 'lamp', 'fire',
    'girl', 'woman', 'man', 'boy', 'guard', 'king', 'queen', 'prince',
    'princess', 'cat', 'dog', 'bird', 'eagle', 'dragon', 'snake',
    'horse', 'donkey', 'chicken', 'fish', 'mermaid', 'monster', 'bear',
  ];

  /// Picks the most natural canonical word from a list of synonyms.
  static String chooseCanonicalWord(List<String> synonyms) {
    if (synonyms.isEmpty) return '';
    if (synonyms.length == 1) return synonyms.first;

    // Check preferred word list in order
    for (final pref in _preferredAgiWords) {
      if (synonyms.contains(pref)) {
        return pref;
      }
    }

    // Prefer standard single-word tokens without punctuation/spaces
    final singleWords = synonyms.where((w) => !w.contains(' ') && !w.contains('-')).toList();
    if (singleWords.isNotEmpty) {
      // Pick shortest single word (often most direct: "box", "key", etc.)
      singleWords.sort((a, b) => a.length.compareTo(b.length));
      return singleWords.first;
    }

    return synonyms.first;
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
