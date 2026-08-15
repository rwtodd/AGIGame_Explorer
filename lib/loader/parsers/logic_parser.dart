import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';
import 'package:flutter_agigame/domain/logic_script.dart';

/// Parser for Sierra AGI LOGIC resources (v2 and v3).
class LogicParser {
  const LogicParser._();

  /// Parses a raw LOGIC resource byte array into an [AgiLogicScript].
  ///
  /// - In AGIv2 games, the message strings section is encrypted with the "Avis Durgan" key.
  /// - In AGIv3 games, resources are decompressed via LZW and messages are unencrypted.
  static AgiLogicScript parse(
    Uint8List data, {
    bool isEncrypted = false,
    List<int>? key,
    int? logicNumber,
  }) {
    if (data.length < 2) {
      throw const AgiException('LOGIC resource is too short to contain a valid header.');
    }

    // 16-bit LE offset to the message section
    final textOffset = (data[0] | (data[1] << 8)) + 2;
    final codeEnd = math.min(textOffset, data.length);
    final bytecodes = data.sublist(2, codeEnd);

    // If there is no message section or it's past the end of the resource
    if (textOffset >= data.length) {
      return AgiLogicScript(
        bytecodes: bytecodes,
        messages: const [],
        logicNumber: logicNumber,
      );
    }

    final numMessages = data[textOffset] & 0xFF;
    final tableStart = textOffset + 3;

    // Work on a mutable copy of the buffer so decryption doesn't mutate source data
    final buffer = Uint8List.fromList(data);

    if (isEncrypted && numMessages > 0) {
      // In AGIv2 format, strings start right after the 16-bit pointer table
      final stringsStart = tableStart + (numMessages * 2);
      if (stringsStart < buffer.length) {
        int endOffset = buffer.length;
        if (textOffset + 2 < buffer.length) {
          final declaredEnd = (buffer[textOffset + 1] | (buffer[textOffset + 2] << 8));
          if (declaredEnd > 0 && textOffset + declaredEnd <= buffer.length) {
            endOffset = textOffset + declaredEnd;
          }
        }
        CryptoUtils.decodeInPlace(
          buffer,
          key: key ?? CryptoUtils.avisDurganKey,
          start: stringsStart,
          end: endOffset,
        );
      }
    }

    final messages = <String>[];
    for (var i = 0; i < numMessages; i++) {
      final ptrIndex = tableStart + (i * 2);
      if (ptrIndex + 1 >= buffer.length) {
        messages.add('');
        continue;
      }

      final relOffset = buffer[ptrIndex] | (buffer[ptrIndex + 1] << 8);
      if (relOffset == 0) {
        messages.add('');
      } else {
        final strPos = textOffset + relOffset + 1;
        final msg = CryptoUtils.asciizString(buffer, strPos);
        messages.add(msg);
      }
    }

    return AgiLogicScript(
      bytecodes: bytecodes,
      messages: messages,
      logicNumber: logicNumber,
    );
  }
}
