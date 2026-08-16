import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('AgiResourceLoader logic loading', () {
    test('loads and parses King\'s Quest 2 LOGIC 30 with extended ASCII bytes', () {
      const kq2Path = 'reference_games/kings-quest-2';
      if (!Directory(kq2Path).existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Path);
      final script30 = loader.loadLogic(30);

      expect(script30.messageCount, 27);
      expect(
        script30.getMessage(1),
        'You are in a grove of giant trees. A sign appears to be attached to the back of one of the trees.',
      );
      // Messages 4, 6, 8, etc. contain extended byte 0xFF
      expect(script30.getMessage(4), contains('Hear ye! Hear ye!'));
      expect(script30.getMessage(6), contains('Sierra is pleased to announce:'));
      expect(script30.getMessage(8), contains('SPACE QUEST:'));
      expect(script30.getMessage(16), contains("KING'S QUEST ]I[:"));
      // Verify final message does not have un-decrypted trailing artifacts
      expect(
        script30.getMessage(27),
        "King Graham scratches his head in puzzlement at this confusing message. It doesn't appear to be a part of his quest.",
      );
    });
  });
}
