import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('AgiResourceLoader Logic Cache Tests', () {
    test('loadLogic returns identical cached instance on second call', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) {
        markTestSkipped('KQ2 reference game not present');
        return;
      }

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final logic0First = loader.loadLogic(0);
      final logic0Second = loader.loadLogic(0);

      expect(identical(logic0First, logic0Second), isTrue,
          reason: 'loadLogic(0) should return the exact cached AgiLogicScript instance');

      final logic1First = loader.loadLogic(1);
      final logic1Second = loader.loadLogic(1);
      expect(identical(logic1First, logic1Second), isTrue);
      expect(identical(logic0First, logic1First), isFalse);

      loader.close();
    });
  });
}
