import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';

void main() {
  group('Police Quest 2 Picture Integration Tests', () {
    test('interprets Pic 1 and Pic 2 without error', () {
      final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      final pic1 = vm.findResource(SciResourceType.pic, 1);
      expect(pic1, isNotNull);

      final data1 = vm.getResourceById(pic1!.id);
      final sciPic1 = SciPicInterpreter.interpret(data1, picNumber: 1);

      expect(sciPic1.visualPixels.length, 320 * 200);
      expect(sciPic1.priorityPixels.length, 320 * 200);
      expect(sciPic1.controlPixels.length, 320 * 200);
      expect(sciPic1.slices.length, 16);
      sciPic1.ensureSlices(undithered: true);
      expect(sciPic1.unditheredSlices.length, 16);
      expect(sciPic1.activeSlices.isNotEmpty, isTrue);

      final pic2 = vm.findResource(SciResourceType.pic, 2);
      expect(pic2, isNotNull);
      final data2 = vm.getResourceById(pic2!.id);
      final sciPic2 = SciPicInterpreter.interpret(data2, picNumber: 2);
      expect(sciPic2.slices.length, 16);
      expect(sciPic2.activeSlices.isNotEmpty, isTrue);
    });

    test('interprets all 78 PQ2 pictures with 0 crashes', () {
      final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      final pics = vm.resourceMap.entriesForType(SciResourceType.pic);
      expect(pics.length, 78);

      int interpreted = 0;
      for (final p in pics) {
        final data = vm.getResourceById(p.id);
        final pic = SciPicInterpreter.interpret(data, picNumber: p.id.number);
        expect(pic.slices.length, 16);
        expect(pic.visualPixels.length, 320 * 200);
        interpreted++;
      }
      expect(interpreted, 78);
    });
  });
}
