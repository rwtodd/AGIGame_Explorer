import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KQ2 Room 3 Mailbox Interaction', () {
    test('Ego near mailbox opens mailbox, sees goodies, and takes goodies', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(3);

      // Position Ego right in front of the mailbox (mailbox is at x=9, y=110)
      final ego = engine.ego;
      ego.x = 13;
      ego.y = 121;

      // Allow room initialization cycles
      for (var i = 0; i < 5; i++) {
        engine.tick();
      }

      final mailbox = engine.animatedObjects[3];
      expect(mailbox.cel, equals(0), reason: 'Mailbox should start closed');
      expect(engine.memory.getFlag(54), isFalse, reason: 'Flag 54 (mailbox open) should start false');

      // Command: "open mailbox"
      engine.submitCommand('open mailbox');
      engine.tick();

      expect(mailbox.isUpdating, isTrue, reason: 'Mailbox should start updating for opening animation');

      // Tick until end.of.loop animation finishes opening mailbox (cel 0 -> 1 -> 2 -> 3)
      for (var i = 0; i < 10; i++) {
        engine.tick();
      }

      expect(mailbox.cel, equals(3), reason: 'Mailbox cel should reach 3 (fully open)');
      expect(engine.memory.getFlag(54), isTrue, reason: 'Flag 54 (mailbox open) should now be set');
      expect(engine.activeDialog?.message, contains('basket of goodies'),
          reason: 'Opening mailbox should show popup about basket of goodies');

      // Clear dialog
      engine.dismissDialog();

      // Command: "look in mailbox"
      engine.submitCommand('look in mailbox');
      engine.tick();

      expect(engine.activeDialog?.message, contains('basket of goodies'),
          reason: 'Looking in open mailbox should report basket of goodies');

      engine.dismissDialog();

      // Command: "take basket" (or "take goodies")
      engine.submitCommand('take basket');
      engine.tick();

      expect(engine.memory.getFlag(57), isTrue, reason: 'Flag 57 (basket taken) should be set');
      expect(engine.memory.itemRooms[63], equals(255), reason: 'Ego should now possess basket (item 63)');
      expect(engine.activeDialog?.message, contains('OK.'));
    });

    test('Ego far away from mailbox gets "You are too far away." and mailbox does not open', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(3);

      // Position Ego far away from mailbox (x=100, y=120)
      final ego = engine.ego;
      ego.x = 100;
      ego.y = 120;

      for (var i = 0; i < 5; i++) {
        engine.tick();
      }

      final mailbox = engine.animatedObjects[3];
      expect(mailbox.cel, equals(0));

      engine.submitCommand('open mailbox');
      engine.tick();

      expect(engine.activeDialog?.message, contains('too far away'),
          reason: 'Being far away should trigger "You are too far away." popup');
      expect(mailbox.cel, equals(0), reason: 'Mailbox should NOT open');
    });
  });
}
