import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_step_interpreter.dart';

void main() {
  group('SciPicStepInterpreter Synthetic Tests', () {
    test('decodes basic vector drawing steps and matches metadata', () {
      // 0xF0 33 (color 33), 0xF2 7 (pri 7), 0xF6 (long line) from (10,10) to (40,10), 0xFF
      final data = Uint8List.fromList([
        0xF0, 33,
        0xF2, 7,
        0xF6,
        0x00, 10, 10,
        0x00, 40, 10,
        0xFF,
      ]);

      final interpreter = SciPicStepInterpreter(data, portTop: 0);
      expect(interpreter.totalSteps, 4); // F0, F2, line segment, FF

      expect(interpreter.steps[0].opcode, 0xF0);
      expect(interpreter.steps[0].commandName, 'Set Visual Color');

      expect(interpreter.steps[1].opcode, 0xF2);
      expect(interpreter.steps[1].commandName, 'Set Priority Color');

      expect(interpreter.steps[2].opcode, 0xF6);
      expect(interpreter.steps[2].commandName, 'Long Line');
      expect(interpreter.steps[2].description, contains('Line from (10, 10) to (40, 10)'));

      expect(interpreter.steps[3].opcode, 0xFF);
      expect(interpreter.steps[3].commandName, 'End of Picture');

      // Step 0: Blank canvas
      final pic0 = interpreter.renderUpToStep(0);
      expect(pic0.visualPixels[10 * 320 + 20], 15); // white default

      // Step 3 (after line): line drawn
      final pic3 = interpreter.renderUpToStep(3);
      expect(pic3.priorityPixels[10 * 320 + 20], 7);
    });
  });

  group('SciPicStepInterpreter Real Game Parity Tests', () {
    test('renderUpToStep(totalSteps) pixel-matches SciPicInterpreter on PQ2 Pic 1 and Pic 2', () {
      final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');

      for (final picNum in [1, 2]) {
        final res = vm.findResource(SciResourceType.pic, picNum);
        expect(res, isNotNull);
        final raw = vm.getResourceById(res!.id);

        final fullPic = SciPicInterpreter.interpret(raw, picNumber: picNum);
        final stepInterpreter = SciPicStepInterpreter(raw, picNumber: picNum);

        expect(stepInterpreter.totalSteps, greaterThan(100));

        // Initial step 0 has default background
        final step0 = stepInterpreter.renderUpToStep(0);
        expect(step0.visualPixels, isNot(equals(fullPic.visualPixels)));

        // Intermediate step 50 has partial drawing
        final step50 = stepInterpreter.renderUpToStep(50);
        expect(step50.visualPixels, isNot(equals(fullPic.visualPixels)));

        // Final step matches full interpreter pixel-for-pixel
        final stepFinal = stepInterpreter.renderUpToStep(stepInterpreter.totalSteps);

        expect(stepFinal.visualPixels, equals(fullPic.visualPixels));
        expect(stepFinal.priorityPixels, equals(fullPic.priorityPixels));
        expect(stepFinal.controlPixels, equals(fullPic.controlPixels));
        expect(stepFinal.rawColorPairs, equals(fullPic.rawColorPairs));

        // Verify computeSlices and isUndithered options
        final slicedStepPic = stepInterpreter.renderUpToStep(
          stepInterpreter.totalSteps,
          computeSlices: true,
          isUndithered: true,
        );
        expect(slicedStepPic.isUndithered, isTrue);
        expect(slicedStepPic.slices.isNotEmpty, isTrue);
        expect(slicedStepPic.unditheredSlices.isNotEmpty, isTrue);
      }
    });

    test('step replay of a right-edge rect pen matches full interpret', () {
      final data = Uint8List.fromList([
        0xF0, 33,
        0xF9, 0x10,
        0xFA,
        0x10, 0x3F, 10,
        0xFF,
      ]);
      final full = SciPicInterpreter.interpret(data, portTop: 0);
      final stepped = SciPicStepInterpreter(data, portTop: 0)
          .renderUpToStep(1000);
      expect(stepped.visualPixels, equals(full.visualPixels));
    });
  });
}
