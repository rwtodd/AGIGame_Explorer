import 'dart:collection';

/// Vocabulary dictionary extracted from WORDS.TOK.
class AgiDictionary {
  final Map<String, int> _wordToId = {};
  final Map<int, List<String>> _idToWords = {};

  AgiDictionary();

  /// Associates [word] with word group [id].
  ///
  /// If [word] was previously assigned to a different group, it is removed
  /// from that group's list so the two maps stay consistent. Re-adding a
  /// word to the group it already belongs to is a no-op (no duplicates).
  void addWord(String word, int id) {
    final previousId = _wordToId[word];
    if (previousId == id) {
      return;
    }
    if (previousId != null) {
      final previousGroup = _idToWords[previousId];
      if (previousGroup != null) {
        previousGroup.remove(word);
        if (previousGroup.isEmpty) {
          _idToWords.remove(previousId);
        }
      }
    }
    _wordToId[word] = id;
    final group = _idToWords.putIfAbsent(id, () => []);
    if (!group.contains(word)) {
      group.add(word);
    }
  }

  /// Returns the word group ID for [word], or -1 if unrecognized.
  int wordToId(String word) => _wordToId[word.toLowerCase()] ?? -1;

  /// Returns all synonyms associated with word group [id].
  ///
  /// The returned list is an unmodifiable view of the internal group list:
  /// mutation throws [UnsupportedError]; it always reflects the current
  /// group contents.
  List<String> idToWords(int id) {
    final words = _idToWords[id];
    if (words == null) return const [];
    return UnmodifiableListView(words);
  }

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
  ///
  /// The incoming list is copied; later mutation by the caller does not
  /// affect the dictionary.
  void setDeduplicatedWords(int id, List<String> words) {
    _deduplicatedWords[id] = List<String>.from(words);
  }

  /// Returns semantically deduplicated synonyms for word group [id],
  /// or falls back to [idToWords] if not yet deduplicated.
  ///
  /// The returned list is an unmodifiable view.
  List<String> idToDeduplicatedWords(int id) {
    final words = _deduplicatedWords[id];
    if (words == null) return idToWords(id);
    return UnmodifiableListView(words);
  }

  /// Read-only view of all deduplicated word groups.
  ///
  /// Both the map and the per-group lists are unmodifiable; mutations throw
  /// [UnsupportedError].
  Map<int, List<String>> get deduplicatedWords => Map.unmodifiable(
        _deduplicatedWords.map(
          (id, words) => MapEntry(id, UnmodifiableListView(words)),
        ),
      );

  /// Loads pre-computed deduplicated word groups into this dictionary.
  ///
  /// The incoming map and lists are copied; later mutation by the caller
  /// does not affect the dictionary.
  void loadDeduplicatedWords(Map<int, List<String>> groups) {
    _deduplicatedWords.clear();
    groups.forEach((id, words) {
      _deduplicatedWords[id] = List<String>.from(words);
    });
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
