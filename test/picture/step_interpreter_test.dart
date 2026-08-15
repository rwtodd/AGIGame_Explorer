import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/picture/pic_step_interpreter.dart';
import 'package:flutter_agigame/picture/pic_vector_interpreter.dart';

void main() {
  group('PicStepInterpreter Tests', () {
    test('step interpreter decodes vector opcodes and matches full interpreter at final step', () {
      final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();
      final expectedPic = File('test/fixtures/picbytes.bin').readAsBytesSync();
      final expectedPri = File('test/fixtures/pribytes.bin').readAsBytesSync();

      final fullInterpreter = PicVectorInterpreter(isV3: false);
      final fullPic = fullInterpreter.interpret(srcBytes);

      expect(fullPic.visualPixels, equals(expectedPic));
      expect(fullPic.priorityBuffer.pixels, equals(expectedPri));

      final stepInterpreter = PicStepInterpreter(srcBytes, isV3: false);
      expect(stepInterpreter.totalSteps, greaterThan(0));

      // At step 0, visual buffer is all white (15) and priority is 4
      final step0Pic = stepInterpreter.renderUpToStep(0);
      expect(step0Pic.visualPixels.every((p) => p == 15), isTrue);
      expect(step0Pic.priorityBuffer.pixels.every((p) => p == 4), isTrue);

      // At final step, rendered pic matches fullPic
      final finalPic = stepInterpreter.renderUpToStep(stepInterpreter.totalSteps);
      expect(finalPic.visualPixels, equals(expectedPic));
      expect(finalPic.priorityBuffer.pixels, equals(expectedPri));
    });
  });
}
