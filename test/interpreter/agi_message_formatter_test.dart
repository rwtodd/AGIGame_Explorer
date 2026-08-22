import 'dart:typed_data';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/agi_message_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgiMessageFormatter', () {
    test('expands %v with optional zero padding', () {
      final memory = AgiMemory();
      memory.setVar(6, 42);
      memory.setVar(14, 7);

      expect(
        AgiMessageFormatter.format('Score: %v6', memory: memory),
        'Score: 42',
      );
      expect(
        AgiMessageFormatter.format('Padded: %v14|3', memory: memory),
        'Padded: 007',
      );
    });

    test('expands %m from the current script instead of echoing %mN', () {
      final memory = AgiMemory();
      final script = AgiLogicScript(
        bytecodes: Uint8List(0),
        messages: const ['ignored', 'Star Generator'],
      );

      expect(
        AgiMessageFormatter.format(
          'See %m2',
          memory: memory,
          currentScript: script,
        ),
        'See Star Generator',
      );
      expect(
        AgiMessageFormatter.format('See %m2', memory: memory),
        'See ',
      );
    });

    test('expands nested %s and escapes', () {
      final memory = AgiMemory();
      memory.setString(1, r'Hero \%v1');

      expect(
        AgiMessageFormatter.format(r'Hello %s1!', memory: memory),
        r'Hello Hero %v1!',
      );
    });
  });
}
