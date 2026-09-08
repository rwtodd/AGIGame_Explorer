import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';

void main() {
  group('SciScriptParser Unit Tests', () {
    test('Parses synthetic script blocks', () {
      final bb = BytesBuilder();

      // Block 7: Exports (count = 2, exports: [0x100, 0x200])
      // blockType: 7 (2 bytes), blockSize: 10 (2 bytes), count: 2 (2 bytes), 0x100 (2 bytes), 0x200 (2 bytes)
      bb.add([0x07, 0x00, 0x0A, 0x00, 0x02, 0x00, 0x00, 0x01, 0x00, 0x02]);

      // Block 10: LocalVars (count = 3, values: [10, 20, 30])
      // blockType: 10 (2 bytes), blockSize: 10 (2 bytes), values: 10, 20, 30 (6 bytes)
      bb.add([0x0A, 0x00, 0x0A, 0x00, 0x0A, 0x00, 0x14, 0x00, 0x1E, 0x00]);

      // Block 8: Relocation Pointers (count = 1, pointer at localsOffset + 2)
      // localsOffset was at byte 14 (10 bytes export block + 4 bytes header of block 10)
      // reloc offset = 14 + 2 = 16 (relocates locals[1])
      // blockType: 8 (2 bytes), blockSize: 8 (2 bytes), count: 1 (2 bytes), reloc: 16 (2 bytes)
      bb.add([0x08, 0x00, 0x08, 0x00, 0x01, 0x00, 0x10, 0x00]);

      // Block 0: Terminator
      bb.add([0x00, 0x00, 0x00, 0x00]);

      final parser = const SciScriptParser();
      final script = parser.parse(1, bb.toBytes(), 1);

      expect(script.scriptNumber, 1);
      expect(script.segmentId, 1);
      expect(script.exports, [0x100, 0x200]);
      expect(script.locals.length, 3);
      expect(script.locals[0].isNumber, isTrue);
      expect(script.locals[0].toSint16(), 10);
      // locals[1] was relocated to segment 1!
      expect(script.locals[1].isPointer, isTrue);
      expect(script.locals[1].segment, 1);
      expect(script.locals[1].offset, 20);
      expect(script.locals[2].isNumber, isTrue);
      expect(script.locals[2].toSint16(), 30);
    });

    test('Parses synthetic class block and method dictionary', () {
      // Let's create the method block starting at objectPosition + 8:
      final block = BytesBuilder();
      block.add([0x06, 0x00]); // blockType 6
      block.add([32, 0]); // blockSize = 32
      block.add([0x34, 0x12]); // magic
      block.add([0x00, 0x00]); // locals
      block.add([0x0A, 0x00]); // funcArea = 10 -> method block at objectPos + 8
      block.add([0x04, 0x00]); // selectorCount = 4
      // objectPosition (12):
      block.add([0x05, 0x00]); // species = 5
      block.add([0x00, 0x00]); // superClass = 0
      block.add([0x00, 0x80]); // info = 0x8000
      block.add([0x00, 0x00]); // name = 0
      // Method block at 12 + 8 = 20:
      block.add([0x01, 0x00]); // methodCount = 1
      block.add([0x57, 0x00]); // selector = 87 (init)
      block.add([0x00, 0x00]); // zero terminator
      block.add([0x50, 0x00]); // codeOffset = 0x50
      // Terminator block:
      block.add([0x00, 0x00, 0x00, 0x00]);

      final parser = const SciScriptParser();
      final script = parser.parse(2, block.toBytes(), 2);
      expect(script.objects.length, 1);

      final obj = script.objects.values.first;
      expect(obj.isClass, isTrue);
      expect(obj.species.toUint16(), 5);
      expect(obj.methodCount, 1);
      expect(obj.methods[87], 0x50);
    });
  });

  group('Police Quest 2 Real Script 0 Inspection', () {
    test('Parses PQ2 Script 0 successfully', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        return; // Skip if reference game not present
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final script0Bytes = volumeMgr.getResource(SciResourceType.script, 0);

      final parser = const SciScriptParser();
      final script = parser.parse(0, script0Bytes, 1);

      expect(script.scriptNumber, 0);
      expect(script.exports.isNotEmpty, isTrue);
      expect(script.exports.length, 23);

      // Export 0 should be the PQ Game object
      final gameObjOffset = script.exports[0];
      final gameObj = script.getObject(gameObjOffset);
      expect(gameObj, isNotNull);
      expect(gameObj!.nameString, 'PQ');
      expect(gameObj.species.toUint16(), 49); // Species 49 = Game
      expect(gameObj.isClass, isFalse); // Instance of Game
      expect(gameObj.methodCount, 8);
      expect(gameObj.methods.containsKey(87), isTrue); // init:
      expect(gameObj.methods.containsKey(60), isTrue); // doit:
      expect(gameObj.methods.containsKey(111), isTrue); // handleEvent:
    });
  });
}
