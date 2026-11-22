import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/dictionary.dart';

/// Parser for AGI WORDS.TOK vocabulary file.
class WordsParser {
  const WordsParser._();

  /// Builds an [AgiDictionary] from the raw bytes of WORDS.TOK.
  static AgiDictionary parse(Uint8List data) {
    if (data.length < 2) {
      throw const AgiException('WORDS.TOK file is too short.');
    }

    final dictionary = AgiDictionary();
    final buffer = <int>[];

    try {
      final startOffset = (data[0] << 8) | data[1];
      if (startOffset > data.length) {
        throw const CorruptResourceException(
          'Malformed WORDS.TOK: start offset is beyond the end of the file.',
        );
      }
      var idx = startOffset;

      while (idx < data.length) {
        final toSkip = data[idx++];
        if (toSkip > buffer.length) {
          throw const AgiException('Malformed WORDS.TOK: prefix length exceeds previous word.');
        }

        if (toSkip < buffer.length) {
          buffer.removeRange(toSkip, buffer.length);
        }

        if (idx >= data.length) {
          // Legal terminator: real Sierra WORDS.TOK files (and the
          // reference parser) end the word list with a lone trailing
          // prefix byte and no suffix/group after it.
          break;
        }

        int nextByte;
        do {
          if (idx >= data.length) {
            throw const AgiException('Unexpected EOF while reading word suffix in WORDS.TOK.');
          }
          nextByte = data[idx++];
          final charCode = (nextByte ^ 0x7F) & 0x7F;
          buffer.add(charCode);
        } while ((nextByte & 0x80) == 0 && idx < data.length);

        if ((nextByte & 0x80) == 0) {
          throw const CorruptResourceException(
            'Malformed WORDS.TOK: unexpected EOF before suffix terminator.',
          );
        }

        if (idx + 1 >= data.length) {
          throw const CorruptResourceException(
            'Malformed WORDS.TOK: unexpected EOF before 2-byte group number.',
          );
        }

        final groupNumber = (data[idx] << 8) | data[idx + 1];
        idx += 2;

        final word = String.fromCharCodes(buffer);
        dictionary.addWord(word, groupNumber);
      }

      return dictionary;
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Error parsing WORDS.TOK: $e', e);
    }
  }
}
