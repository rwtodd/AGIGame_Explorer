import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';

void main() {
  group('SciDisassembler Unit Tests', () {
    test('Disassembles synthetic bytecode sequence with jumps and kernel calls', () {
      final bb = BytesBuilder();

      // Block 6: Class (Species 10, name pointer 0)
      bb.add([0x06, 0x00]); // blockType 6
      bb.add([32, 0]); // blockSize = 32
      bb.add([0x34, 0x12]); // magic
      bb.add([0x00, 0x00]); // locals
      bb.add([0x0A, 0x00]); // funcArea = 10 -> method block at objectPos + 8
      bb.add([0x04, 0x00]); // selectorCount = 4
      // objectPosition (12):
      bb.add([0x0A, 0x00]); // species = 10
      bb.add([0x00, 0x00]); // superClass = 0
      bb.add([0x00, 0x80]); // info = 0x8000
      bb.add([0x00, 0x00]); // name = 0
      // Method block at 12 + 8 = 20:
      bb.add([0x01, 0x00]); // methodCount = 1
      bb.add([0x87, 0x00]); // selector = 135 (init)
      bb.add([0x00, 0x00]); // zero terminator
      bb.add([0x30, 0x00]); // codeOffset = 0x30 (byte 48)

      // Pad up to offset 48 (0x30):
      final padLen = 48 - (bb.length);
      bb.add(List.filled(padLen, 0));

      // Code at offset 0x30:
      // 1. pushi 1 (extOpcode 0x38 -> opcode 0x1C (28), word: 1)
      bb.add([0x38, 0x01, 0x00]);
      // 2. callk DrawPic 2 (extOpcode 0x42 -> opcode 0x21 (33), word kId 0x08, byte argc 0x02)
      bb.add([0x42, 0x08, 0x00, 0x02]);
      // 3. bnt +3 bytes (extOpcode 0x2F -> opcode 0x17, sbyte +3)
      bb.add([0x2F, 0x03]);
      // 4. push0 (extOpcode 0x76 -> opcode 0x3B (59))
      bb.add([0x76]);
      // 5. ret (extOpcode 0x48 -> opcode 0x24 (36))
      bb.add([0x48]);
      // Target of bnt (jump past ret):
      // 6. push1 (extOpcode 0x78 -> opcode 0x3C (60))
      bb.add([0x78]);
      // 7. ret (extOpcode 0x48 -> opcode 0x24 (36))
      bb.add([0x48]);

      // Terminator block:
      bb.add([0x00, 0x00, 0x00, 0x00]);

      final parser = const SciScriptParser();
      final script = parser.parse(100, bb.toBytes(), 1);

      final kernel = SciKernel();
      final selectors = SciSelectors();
      final ctx = SciDisassemblyContext(
        script: script,
        kernel: kernel,
        selectors: selectors,
      );

      final disassembler = SciDisassembler(ctx);
      final lines = disassembler.disassembleScript();

      expect(lines.isNotEmpty, isTrue);

      // Verify labels and instructions
      final codeLines = lines.where((l) => !l.isLabel).toList();
      expect(codeLines.length, 7);

      // Verify instruction mnemonics
      expect(codeLines[0].mnemonic, 'pushi');
      expect(codeLines[1].mnemonic, 'callk');
      expect(codeLines[1].operands[0], 'DrawPic');
      expect(codeLines[1].operands[1], '2');

      // Verify branch target tracking (bt target extends past first ret)
      expect(codeLines[2].mnemonic, 'bt');
      expect(codeLines[2].targetAddress, isNotNull);

      expect(codeLines[3].mnemonic, 'push0');
      expect(codeLines[4].mnemonic, 'ret');
      expect(codeLines[5].mnemonic, 'push1');
      expect(codeLines[6].mnemonic, 'ret');
    });

    test('Disassembles real PQ2 Script 0 with symbols', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference directory missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segMan = SciSegManager();
      final kernel = SciKernel();
      final selectors = SciSelectors();

      // Load vocabs
      final v996 = volumeMgr.getResource(SciResourceType.vocab, 996);
      segMan.loadClassTable(v996);

      final v997 = volumeMgr.getResource(SciResourceType.vocab, 997);
      selectors.loadVocab997(v997);

      final script0 = segMan.instantiateScript(0, volumeMgr);

      final ctx = SciDisassemblyContext(
        script: script0,
        selectors: selectors,
        segManager: segMan,
        kernel: kernel,
      );

      final disassembler = SciDisassembler(ctx);
      final lines = disassembler.disassembleScript();

      expect(lines.isNotEmpty, isTrue);
      expect(lines.length > 50, isTrue);

      // Verify that PQ Game object has been disassembled with methods
      final gameObj = script0.getObject(script0.exports[0]);
      expect(gameObj, isNotNull);
      expect(gameObj!.nameString, 'PQ');

      // Verify that kernel calls are resolved by name
      final kernelLines = lines.where((l) => l.mnemonic == 'callk').toList();
      expect(kernelLines.isNotEmpty, isTrue);
      expect(kernelLines.any((l) => l.operands.isNotEmpty && l.operands[0] != 'k_0x0'), isTrue);
    });
  });
}
