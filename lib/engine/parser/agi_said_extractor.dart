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

  @override
  String toString() => '$canonicalPhrase ($wordGroupIds) [Logic $scriptNumber]';
}

/// Utility for extracting and canonicalizing `said(...)` statements from AGI logic scripts.
class AgiSaidExtractor {
  final InstructionDecoder decoder;

  AgiSaidExtractor({double version = 2.917})
      : decoder = InstructionDecoder(version: version);

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

  /// Extracts all [ExtractedSaidCommand]s from [script].
  List<ExtractedSaidCommand> extractFromScript({
    required AgiLogicScript script,
    required AgiDictionary dictionary,
    int scriptNumber = 0,
  }) {
    if (script.bytecodes.isEmpty) return const [];

    CompoundInstruction root;
    try {
      root = decoder.decode(script.bytecodes);
    } catch (_) {
      // Fallback: raw bytecode scanner if disassembler encounters partial or corrupted tail opcodes
      return _extractFromRawBytecode(
        byteCode: script.bytecodes,
        dictionary: dictionary,
        scriptNumber: scriptNumber,
      );
    }

    final saidNodes = findSaidInstructions(root);
    final results = <ExtractedSaidCommand>[];
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
          // Take the primary/first synonym
          words.add(list.first);
        } else {
          words.add('word_$id');
        }
      }
    }
    return words.join(' ').trim();
  }
}
