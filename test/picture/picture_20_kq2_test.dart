import 'dart:io';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Verify KQ2 Picture 20 conditional barrier pixels are rendered', () {
    final kq2Dir = Directory('reference_games/kings-quest-2');
    if (!kq2Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
    if (!loader.presentPicNumbers.contains(20)) return;

    final pic = loader.loadPic(20);
    expect(pic, isNotNull);

    // Count conditional barrier (priority 1) pixels in Picture 20
    var condBarrierPixels = 0;
    for (int y = 0; y < 168; y++) {
      for (int x = 0; x < 160; x++) {
        if (pic.priorityAtPixel(x, y) == 1) {
          condBarrierPixels++;
        }
      }
    }

    // Antique shop in KQ2 Pic 20 has walls drawn with Priority 1
    expect(condBarrierPixels, greaterThan(100),
        reason: 'Picture 20 must have conditional barrier pixels for antique shop walls');
  });
}
