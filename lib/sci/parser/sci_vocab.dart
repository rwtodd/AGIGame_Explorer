// SCI0 VOCAB.000 parser and vocabulary manager.

import 'dart:typed_data';

/// A single word definition in the SCI0 vocabulary.
class SciVocabWord {
  final String text;
  final int wordClass;
  final int group;

  const SciVocabWord({
    required this.text,
    required this.wordClass,
    required this.group,
  });

  @override
  String toString() =>
      'SciVocabWord("$text", class: 0x${wordClass.toRadixString(16)}, group: $group)';
}

/// Manages parsed `VOCAB.000` entries, word class lookups, and synonym resolution.
class SciVocab {
  // Word classes (bitfield values)
  static const int classPreposition = 0x01;
  static const int classArticle = 0x02;
  static const int classAdjective = 0x04;
  static const int classPronoun = 0x08;
  static const int classNoun = 0x10;
  static const int classIndicativeVerb = 0x20;
  static const int classAdverb = 0x40;
  static const int classImperativeVerb = 0x80;
  static const int classAnyWord = 0xFF;

  // Special magic word groups
  static const int groupNumber = 0x0FFD;
  static const int groupNothing = 0x0FFE; // 4094, '!*'
  static const int groupAnyWord = 0x0FFF; // 4095, '*'

  final Map<String, List<SciVocabWord>> _wordsByText = {};
  final Map<int, List<SciVocabWord>> _wordsByGroup = {};
  final Map<int, int> _synonyms = {};

  bool get isEmpty => _wordsByText.isEmpty;
  int get wordCount => _wordsByText.length;
  int get groupCount => _wordsByGroup.length;

  /// Loads and parses the `VOCAB.000` binary resource bytes.
  void loadVocab000(Uint8List bytes) {
    _wordsByText.clear();
    _wordsByGroup.clear();
    _synonyms.clear();

    if (bytes.length < 26 * 2) return;

    // Seeker starts after 26 16-bit alphabetical jump pointers
    int seeker = 26 * 2;
    String currentWord = '';

    while (seeker < bytes.length) {
      final prefixLen = bytes[seeker++];
      final chars = <int>[];
      int c;

      do {
        if (seeker >= bytes.length) break;
        c = bytes[seeker++];
        chars.add(c & 0x7F);
      } while (c < 0x80);

      if (chars.isEmpty) break;

      final prefix = currentWord.substring(0, prefixLen.clamp(0, currentWord.length));
      currentWord = prefix + String.fromCharCodes(chars);

      if (seeker + 3 > bytes.length) break;

      final b0 = bytes[seeker++];
      final b1 = bytes[seeker++];
      final b2 = bytes[seeker++];

      final wordClass = (b0 << 4) | ((b1 & 0xF0) >> 4);
      final wordGroup = b2 | ((b1 & 0x0F) << 8);

      final entry = SciVocabWord(
        text: currentWord,
        wordClass: wordClass,
        group: wordGroup,
      );

      _wordsByText.putIfAbsent(currentWord, () => []).add(entry);
      _wordsByGroup.putIfAbsent(wordGroup, () => []).add(entry);
    }
  }

  /// Sets a synonym mapping: [replaceantGroup] is replaced by [replacementGroup].
  void setSynonym(int replaceantGroup, int replacementGroup) {
    _synonyms[replaceantGroup] = replacementGroup;
  }

  /// Resolves the effective group number accounting for registered synonyms.
  int resolveGroup(int group) {
    return _synonyms[group] ?? group;
  }

  /// Looks up candidate vocabulary words for a given text token.
  /// Handles case-insensitivity, trailing punctuation stripping, and plural suffixes.
  List<SciVocabWord>? lookup(String rawToken) {
    final cleaned = _cleanToken(rawToken);
    if (cleaned.isEmpty) return null;

    // Direct lookup
    final direct = _wordsByText[cleaned];
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    // Number check
    if (int.tryParse(cleaned) != null) {
      return [
        SciVocabWord(
          text: cleaned,
          wordClass: 0x100,
          group: groupNumber,
        ),
      ];
    }

    // Trailing 's' plural fallback
    if (cleaned.endsWith('s') && cleaned.length > 2) {
      final singular = cleaned.substring(0, cleaned.length - 1);
      final singularWords = _wordsByText[singular];
      if (singularWords != null && singularWords.isNotEmpty) {
        return singularWords;
      }
    }

    return null;
  }

  /// Returns a canonical representative text word for a given group ID.
  String getWordGroupText(int group) {
    final resolved = resolveGroup(group);
    if (resolved == groupNothing) return 'none';
    if (resolved == groupAnyWord) return 'anyword';
    if (resolved == groupNumber) return 'number';

    final words = _wordsByGroup[resolved];
    if (words == null || words.isEmpty) return 'word_$resolved';

    // Prefer word without special symbols and shortest length
    words.sort((a, b) {
      final aSym = a.text.contains(RegExp(r'[^a-zA-Z0-9]')) ? 1 : 0;
      final bSym = b.text.contains(RegExp(r'[^a-zA-Z0-9]')) ? 1 : 0;
      if (aSym != bSym) return aSym.compareTo(bSym);
      return a.text.length.compareTo(b.text.length);
    });

    return words.first.text;
  }

  /// Strips punctuation from word token and lowercases.
  static String _cleanToken(String token) {
    return token
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
  }
}
