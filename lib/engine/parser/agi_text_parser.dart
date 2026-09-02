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

  static final _punctuationRegex =
      RegExp(r'[.,;:!?"\(\)\[\]\{\}\/\\_\-\+=<>@#$%^&*~|]');
  static final _whitespaceRegex = RegExp(r'\s+');

  /// Normalizes user text:
  /// - Converts to lowercase
  /// - Expands / normalizes contractions (e.g. "don't" -> "dont")
  /// - Removes apostrophes inside words
  /// - Replaces punctuation (. , ; : ! ? " ' ` [ ] ( ) { } / \ _ -) with spaces
  /// - Collapses multiple spaces and trims leading/trailing whitespace
  String normalize(String input) {
    if (input.trim().isEmpty) return '';

    var text = input.toLowerCase();

    // Expand known contractions first if apostrophes are present
    if (text.contains("'") || text.contains('’') || text.contains('`')) {
      commonContractions.forEach((contraction, replacement) {
        text = text.replaceAll(contraction, replacement);
      });

      // Remove any remaining apostrophes inside words (e.g. "rock'n'roll" -> "rocknroll")
      text = text.replaceAll("'", '');
      text = text.replaceAll('`', '');
      text = text.replaceAll('’', '');
    }

    // Replace punctuation with spaces
    // Sierra AGI treats standard punctuation as word separators
    text = text.replaceAll(_punctuationRegex, ' ');

    // Collapse whitespace
    text = text.replaceAll(_whitespaceRegex, ' ').trim();

    return text;
  }

  /// Splits normalized input into word tokens.
  List<String> tokenize(String input) {
    final normalized = normalize(input);
    if (normalized.isEmpty) return const [];
    return normalized.split(' ');
  }

  /// Parses user command string against the dictionary using greedy longest-match tokenization:
  /// 1. Normalizes and tokenizes the input text.
  /// 2. Searches for the longest matching dictionary word/phrase starting at current token index.
  /// 3. Filters out Group 0 (ignored noise words such as "a", "the", "to", "in").
  /// 4. If any token sequence cannot be matched in the dictionary, returns an [AgiParseResult] failure.
  /// 5. Otherwise returns an [AgiParseResult] success with the list of non-zero word group IDs.
  AgiParseResult parse(String input) {
    final rawInput = input;
    final normalized = normalize(input);

    if (normalized.isEmpty) {
      return AgiParseResult.empty(rawInput: rawInput);
    }

    final tokens = normalized.split(' ');
    final wordGroupIds = <int>[];
    final originalTokens = <String>[];
    final filteredTokens = <String>[];

    var i = 0;
    while (i < tokens.length) {
      int matchEnd = -1;
      int matchId = -1;
      String matchPhrase = '';

      // Greedy longest-match: search candidate phrases from longest down to single word
      for (var j = tokens.length; j > i; j--) {
        final candidate = tokens.sublist(i, j).join(' ');
        final id = dictionary.wordToId(candidate);
        if (id != -1) {
          matchEnd = j;
          matchId = id;
          matchPhrase = candidate;
          break;
        }
      }

      if (matchEnd != -1) {
        // Matched a dictionary word or multi-word phrase
        originalTokens.add(matchPhrase);
        if (matchId > 0) {
          wordGroupIds.add(matchId);
          filteredTokens.add(matchPhrase);
        }
        i = matchEnd;
      } else {
        // Unknown word encountered (first unmatched single token)
        final unknownWord = tokens[i];
        final unknownIndex = i + 1; // 1-based index in token stream

        return AgiParseResult.unknownWord(
          rawInput: rawInput,
          normalizedInput: normalized,
          originalTokens: tokens,
          unknownWord: unknownWord,
          unknownWordIndex: unknownIndex,
        );
      }
    }

    return AgiParseResult.success(
      rawInput: rawInput,
      normalizedInput: normalized,
      wordGroupIds: wordGroupIds,
      originalTokens: originalTokens,
      filteredTokens: filteredTokens,
    );
  }
}
