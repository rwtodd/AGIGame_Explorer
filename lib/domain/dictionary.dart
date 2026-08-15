/// Vocabulary dictionary extracted from WORDS.TOK.
class AgiDictionary {
  final Map<String, int> _wordToId = {};
  final Map<int, List<String>> _idToWords = {};

  AgiDictionary();

  void addWord(String word, int id) {
    _wordToId[word] = id;
    _idToWords.putIfAbsent(id, () => []).add(word);
  }

  /// Returns the word group ID for [word], or -1 if unrecognized.
  int wordToId(String word) => _wordToId[word.toLowerCase()] ?? -1;

  /// Returns all synonyms associated with word group [id].
  List<String> idToWords(int id) => _idToWords[id] ?? const [];

  /// Set of all recognized words.
  Set<String> get allWords => _wordToId.keys.toSet();

  /// Set of all word group IDs.
  Set<int> get allIds => _idToWords.keys.toSet();

  /// Total count of unique vocabulary words.
  int get wordCount => _wordToId.length;

  /// Total count of unique word group IDs.
  int get groupCount => _idToWords.length;
}
