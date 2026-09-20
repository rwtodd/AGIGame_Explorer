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

  final Map<int, List<String>> _deduplicatedWords = {};

  /// Whether this dictionary's synonym groups have been semantically deduplicated.
  bool isDeduplicated = false;

  /// Stores the semantically deduplicated synonym list for word group [id].
  void setDeduplicatedWords(int id, List<String> words) {
    _deduplicatedWords[id] = words;
  }

  /// Returns semantically deduplicated synonyms for word group [id],
  /// or falls back to [idToWords] if not yet deduplicated.
  List<String> idToDeduplicatedWords(int id) =>
      _deduplicatedWords[id] ?? idToWords(id);

  /// Read-only view of all deduplicated word groups.
  Map<int, List<String>> get deduplicatedWords =>
      Map.unmodifiable(_deduplicatedWords);

  /// Loads pre-computed deduplicated word groups into this dictionary.
  void loadDeduplicatedWords(Map<int, List<String>> groups) {
    _deduplicatedWords.clear();
    _deduplicatedWords.addAll(groups);
    isDeduplicated = true;
  }

  /// Clears any cached deduplicated word groups.
  void clearDeduplicatedWords() {
    _deduplicatedWords.clear();
    isDeduplicated = false;
  }

  /// Total count of unique word group IDs.
  int get groupCount => _idToWords.length;
}
