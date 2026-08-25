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

    test('loads and correctly decrypts uncompressed LOGIC 97 and 131 in AGI v3 (KQ4)', () {
      const kq4Path = 'reference_games/kings-quest-4-agi';
      if (!Directory(kq4Path).existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq4Path);

      // Uncompressed Logic 97 (Darkness falls cutscene)
      final script97 = loader.loadLogic(97);
      expect(script97.messageCount, 1);
      expect(script97.getMessage(1), 'Like a heavy blanket, darkness enfolds you.');

      // Uncompressed Logic 131 (Morning timeout cutscene)
      final script131 = loader.loadLogic(131);
      expect(script131.messageCount, 1);
      expect(
        script131.getMessage(1),
        "Oh, oh, Rosella! Morning has come! It appears as if you're stuck marrying ol' Edgar.",
      );

      // LZW-compressed Logic 0 (Plaintext messages)
      final script0 = loader.loadLogic(0);
      expect(script0.messageCount, greaterThan(100));
      expect(script0.getMessage(1), contains("King's Quest IV"));
      expect(script0.getMessage(2), 'Not now!  Only one golden egg per day.');
    });
  });
}
