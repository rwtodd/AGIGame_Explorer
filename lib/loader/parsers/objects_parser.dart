import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';

/// Parsed results from the OBJECT file.
class ParsedObjects {
  final List<AgiObject> objects;
  final int maxAnimated;

  const ParsedObjects({
    required this.objects,
    required this.maxAnimated,
  });
}

/// Parser for Sierra AGI OBJECT file.
class ObjectsParser {
  const ObjectsParser._();

  /// Parses the OBJECT file [data]. If [isEncrypted] is true, attempts decryption with [key];
  /// safely falls back if decryption or raw bytes yield invalid headers.
  static ParsedObjects parse(
    Uint8List data, {
    bool isEncrypted = false,
    List<int>? key,
  }) {
    if (data.length < 3) {
      throw const AgiException('OBJECT file is too short.');
    }

    final keyToUse = (key != null && key.isNotEmpty) ? key : CryptoUtils.avisDurganKey;

    bool isValid(Uint8List b) {
      final ws = 3 + (b[0] | (b[1] << 8));
      return ws <= b.length && (ws % 3 == 0) && ws >= 3;
    }

    Uint8List bytes;
    if (isEncrypted) {
      final dec = CryptoUtils.decodeInPlace(Uint8List.fromList(data), key: keyToUse);
      if (isValid(dec)) {
        bytes = dec;
      } else if (isValid(data)) {
        bytes = Uint8List.fromList(data);
      } else {
        bytes = dec;
      }
    } else {
      if (isValid(data)) {
        bytes = Uint8List.fromList(data);
      } else {
        final dec = CryptoUtils.decodeInPlace(Uint8List.fromList(data), key: keyToUse);
        if (isValid(dec)) {
          bytes = dec;
        } else {
          bytes = Uint8List.fromList(data);
        }
      }
    }

    final wordsStart = 3 + (bytes[0] | (bytes[1] << 8));
    if ((wordsStart % 3) != 0) {
      throw const AgiException('Malformed game objects header: word start offset is unaligned.');
    }

    final maxAnimated = bytes[2];
    final objects = <AgiObject>[];

    for (var i = 3; i < wordsStart; i += 3) {
      if (i + 2 >= bytes.length) {
        throw const AgiException('Truncated object entries in OBJECT file.');
      }
      final nameOffset = 3 + (bytes[i] | (bytes[i + 1] << 8));
      final startingRoom = bytes[i + 2];
      final name = CryptoUtils.asciizString(bytes, nameOffset);
      objects.add(AgiObject(name: name, startingRoom: startingRoom));
    }

    return ParsedObjects(
      objects: objects,
      maxAnimated: maxAnimated,
    );
  }
}
