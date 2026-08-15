import 'package:flutter_agigame/domain/dictionary.dart';

/// Structured result of parsing user text input.
class AgiParseResult {
  /// The original raw input typed by the user before normalization.
  final String rawInput;

  /// The normalized and punctuation-stripped string.
  final String normalizedInput;

  /// Whether all input words were recognized in the dictionary.
  final bool isSuccess;

  /// The non-zero word group IDs (ignoring Group 0 noise words).
  final List<int> wordGroupIds;

  /// All tokenized words from the normalized input.
  final List<String> originalTokens;

  /// The tokenized words corresponding to non-zero word group IDs.
  final List<String> filteredTokens;

  /// The first unrecognized word encountered, or null if all were recognized.
  final String? unknownWord;

  /// 1-based index of the unrecognized word in the input tokens (sets AGI Var 9).
  final int? unknownWordIndex;

  /// Human-readable error message if parsing failed, otherwise null.
  final String? errorMessage;

  const AgiParseResult({
    required this.rawInput,
    required this.normalizedInput,
    required this.isSuccess,
    this.wordGroupIds = const [],
    this.originalTokens = const [],
    this.filteredTokens = const [],
    this.unknownWord,
    this.unknownWordIndex,
    this.errorMessage,
  });

  /// Creates a successful parse result.
  factory AgiParseResult.success({
    required String rawInput,
    required String normalizedInput,
    required List<int> wordGroupIds,
    required List<String> originalTokens,
    required List<String> filteredTokens,
  }) {
    return AgiParseResult(
      rawInput: rawInput,
      normalizedInput: normalizedInput,
      isSuccess: true,
      wordGroupIds: List.unmodifiable(wordGroupIds),
      originalTokens: List.unmodifiable(originalTokens),
      filteredTokens: List.unmodifiable(filteredTokens),
    );
  }

  /// Creates a failed parse result for an unrecognized word.
  factory AgiParseResult.unknownWord({
    required String rawInput,
    required String normalizedInput,
    required List<String> originalTokens,
    required String unknownWord,
    required int unknownWordIndex,
    String? customMessage,
  }) {
    return AgiParseResult(
      rawInput: rawInput,
      normalizedInput: normalizedInput,
      isSuccess: false,
      originalTokens: List.unmodifiable(originalTokens),
      unknownWord: unknownWord,
      unknownWordIndex: unknownWordIndex,
      errorMessage: customMessage ?? "I don't understand '$unknownWord'",
    );
  }

  /// Creates an empty result for empty or whitespace-only input.
  factory AgiParseResult.empty({String rawInput = ''}) {
    return AgiParseResult(
      rawInput: rawInput,
      normalizedInput: '',
      isSuccess: true,
      wordGroupIds: const [],
      originalTokens: const [],
      filteredTokens: const [],
    );
  }

  @override
  String toString() {
    if (!isSuccess) {
      return 'AgiParseResult.failed(unknown: "$unknownWord" at index $unknownWordIndex, error: "$errorMessage")';
    }
    return 'AgiParseResult.success(groups: $wordGroupIds, words: $filteredTokens)';
  }
}

/// Tokenizes and parses user text input against an AGI vocabulary dictionary (`WORDS.TOK`).
class AgiTextParser {
  /// The vocabulary dictionary.
  final AgiDictionary dictionary;

  /// Common English contractions mapped to unpunctuated forms matching WORDS.TOK.
  static const Map<String, String> commonContractions = {
    "don't": 'dont',
    "can't": 'cant',
    "won't": 'wont',
    "didn't": 'didnt',
    "isn't": 'isnt',
    "aren't": 'arent',
    "wasn't": 'wasnt',
    "weren't": 'werent',
    "hasn't": 'hasnt',
    "haven't": 'havent',
    "hadn't": 'hadnt',
    "couldn't": 'couldnt',
    "shouldn't": 'shouldnt',
    "wouldn't": 'wouldnt',
    "it's": 'its',
    "that's": 'thats',
    "what's": 'whats',
    "where's": 'wheres',
    "who's": 'whos',
    "how's": 'hows',
    "let's": 'lets',
    "i'm": 'im',
    "you're": 'youre',
    "he's": 'hes',
    "she's": 'shes',
    "they're": 'theyre',
    "we're": 'were',
    "i've": 'ive',
    "you've": 'youve',
    "we've": 'weve',
    "they've": 'theyve',
    "i'll": 'ill',
    "you'll": 'youll',
    "he'll": 'hell',
    "she'll": 'shell',
    "we'll": 'well',
    "they'll": 'theyll',
    "i'd": 'id',
    "you'd": 'youd',
    "he'd": 'hed',
    "she'd": 'shed',
    "we'd": 'wed',
    "they'd": 'theyd',
  };

  AgiTextParser(this.dictionary);

  /// Normalizes user text:
  /// - Converts to lowercase
  /// - Expands / normalizes contractions (e.g. "don't" -> "dont")
  /// - Removes apostrophes inside words
  /// - Replaces punctuation (. , ; : ! ? " ' ` [ ] ( ) { } / \ _ -) with spaces
  /// - Collapses multiple spaces and trims leading/trailing whitespace
  String normalize(String input) {
    if (input.trim().isEmpty) return '';

    var text = input.toLowerCase();

    // Expand known contractions first
    commonContractions.forEach((contraction, replacement) {
      text = text.replaceAll(contraction, replacement);
    });

    // Remove any remaining apostrophes inside words (e.g. "rock'n'roll" -> "rocknroll")
    text = text.replaceAll("'", '');
    text = text.replaceAll('`', '');
    text = text.replaceAll('’', '');

    // Replace punctuation with spaces
    // Sierra AGI treats standard punctuation as word separators
    text = text.replaceAll(RegExp(r'[.,;:!?"\(\)\[\]\{\}\/\\_\-\+=<>@#$%^&*~|]'), ' ');

    // Collapse whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  /// Splits normalized input into word tokens.
  List<String> tokenize(String input) {
    final normalized = normalize(input);
    if (normalized.isEmpty) return const [];
    return normalized.split(' ');
  }

  /// Parses user command string against the dictionary:
  /// 1. Normalizes and tokenizes the input text.
  /// 2. Looks up each word in [dictionary].
  /// 3. Filters out Group 0 (ignored noise words such as "a", "the", "to", "in").
  /// 4. If any word is unknown (ID == -1), returns an [AgiParseResult] failure.
  /// 5. Otherwise returns an [AgiParseResult] success with the list of non-zero word group IDs.
  AgiParseResult parse(String input) {
    final rawInput = input;
    final normalized = normalize(input);

    if (normalized.isEmpty) {
      return AgiParseResult.empty(rawInput: rawInput);
    }

    final tokens = normalized.split(' ');
    final wordGroupIds = <int>[];
    final filteredTokens = <String>[];

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final wordId = dictionary.wordToId(token);

      if (wordId == -1) {
        // Unknown word encountered (1-based index)
        return AgiParseResult.unknownWord(
          rawInput: rawInput,
          normalizedInput: normalized,
          originalTokens: tokens,
          unknownWord: token,
          unknownWordIndex: i + 1,
        );
      }

      // Group 0 = ignored / noise words (e.g., "a", "the", "at", "to", "in")
      if (wordId > 0) {
        wordGroupIds.add(wordId);
        filteredTokens.add(token);
      }
    }

    return AgiParseResult.success(
      rawInput: rawInput,
      normalizedInput: normalized,
      wordGroupIds: wordGroupIds,
      originalTokens: tokens,
      filteredTokens: filteredTokens,
    );
  }
}
