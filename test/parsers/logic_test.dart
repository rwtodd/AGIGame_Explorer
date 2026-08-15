import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';
import 'package:flutter_agigame/loader/parsers/logic_parser.dart';

void main() {
  group('LogicParser', () {
    test('parses script without messages (header only)', () {
      // Offset to messages is 0 (relative textOffset = 2), but total length is 2
      final raw = Uint8List.fromList([0x00, 0x00]);
      final script = LogicParser.parse(raw);

      expect(script.bytecodes.length, 0);
      expect(script.messageCount, 0);
      expect(script.getMessage(1), '');
    });

    test('parses bytecodes and unencrypted messages', () {
      // Bytecodes: [0x01, 0x00, 0x00] (return, etc.) -> length 3
      // Text offset = 3 (LE 0x0003 -> bytecodes from index 2 to 2+3=5)
      // Text section at index 5:
      // msgCount = 2
      // endOffset = 16 (0x10, 0x00)
      // ptr0 -> 7 (0x07, 0x00) -> textOffset(5) + 7 = 12
      // ptr1 -> 12 (0x0C, 0x00) -> textOffset(5) + 12 = 17
      // at index 12: "Hello\0"
      // at index 17: "World\0"

      final builder = BytesBuilder();
      // 16-bit LE text offset = 3
      builder.add([0x03, 0x00]);
      // Bytecodes (3 bytes)
      builder.add([0x0C, 0x01, 0x00]); // set(%f1), return
      // Message header at textOffset (index 5)
      builder.add([0x02]); // 2 messages
      builder.add([0x14, 0x00]); // end offset
      // Pointer table (2 * 2 bytes = 4 bytes)
      // Message 1 at textOffset + 6 + 1
      builder.add([0x06, 0x00]);
      // Message 2 at textOffset + 12 + 1
      builder.add([0x0C, 0x00]);
      // String 1 at textOffset + 7: "Hello\0" (6 bytes)
      builder.add(ascii.encode('Hello\x00'));
      // String 2 at textOffset + 13: "World\0" (6 bytes)
      builder.add(ascii.encode('World\x00'));

      final raw = builder.toBytes();
      final script = LogicParser.parse(raw);

      expect(script.bytecodes, equals(Uint8List.fromList([0x0C, 0x01, 0x00])));
      expect(script.messageCount, 2);
      expect(script.getMessage(1), 'Hello');
      expect(script.getMessage(2), 'World');
      expect(script.getMessage(3), ''); // Out of range
      expect(script.getMessage(0), ''); // 1-based indexing
    });

    test('parses and decrypts Avis Durgan XOR encrypted messages in AGIv2', () {
      final builder = BytesBuilder();
      // 16-bit LE text offset = 2
      builder.add([0x02, 0x00]);
      // Bytecode: [0x00] (return), [0x00]
      builder.add([0x00, 0x00]);
      // Message section at index 4:
      builder.add([0x01]); // 1 message
      builder.add([0x14, 0x00]); // end offset (5 bytes header + table + 15 bytes string)
      // Pointer for msg 1 at textOffset + 4 + 1
      builder.add([0x04, 0x00]);

      // Message string: "Secret Message\0"
      final plainMsg = ascii.encode('Secret Message\x00');
      final encryptedMsg = Uint8List.fromList(plainMsg);
      CryptoUtils.decodeInPlace(encryptedMsg, key: CryptoUtils.avisDurganKey);
      builder.add(encryptedMsg);

      final raw = builder.toBytes();
      final script = LogicParser.parse(raw, isEncrypted: true);

      expect(script.messageCount, 1);
      expect(script.getMessage(1), 'Secret Message');
    });

    test('throws AgiException on truncated header', () {
      expect(() => LogicParser.parse(Uint8List.fromList([0x01])), throwsA(isA<AgiException>()));
    });
  });
}
