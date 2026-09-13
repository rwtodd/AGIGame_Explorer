import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_method_decompiler.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';

void main() {
  group('SciMethodDecompiler Synthetic Unit Tests', () {
    test('Decompiles super call: (super init:)', () {
      final bb = BytesBuilder();
      // Block 6: Class (Species 1, name pointer 0)
      bb.add([0x06, 0x00]); // blockType 6
      bb.add([32, 0]); // blockSize
      bb.add([0x34, 0x12]); // magic
      bb.add([0x00, 0x00]); // locals
      bb.add([0x0A, 0x00]); // funcArea
      bb.add([0x04, 0x00]); // selectorCount
      bb.add([0x01, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00]); // objPos
      bb.add([0x01, 0x00, 0x57, 0x00, 0x00, 0x00, 0x30, 0x00]); // method init at 0x30

      final padLen = 48 - bb.length;
      bb.add(List.filled(padLen, 0));

      // Code at 0x30:
      // 1. pushi 0x57 (#init)
      bb.add([0x38, 0x57, 0x00]);
      // 2. push0
      bb.add([0x76]);
      // 3. super 1, 4 (super Game, 4 bytes)
      bb.add([0x57, 0x01, 0x04]);
      // 4. ret
      bb.add([0x48]);

      // Terminator block:
      bb.add([0x00, 0x00, 0x00, 0x00]);

      final parser = const SciScriptParser();
      final script = parser.parse(10, bb.toBytes(), 1);

      final kernel = SciKernel();
      final selectors = SciSelectors();
      selectors.registerSelector('init', 0x57);

      final ctx = SciDisassemblyContext(
        script: script,
        kernel: kernel,
        selectors: selectors,
      );

      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x30);

      expect(decompiled.contains('(super init:)'), isTrue);
    });

    test('Decompiles kernel call: (DrawPic 100 0)', () {
      final bb = BytesBuilder();
      bb.add([0x00, 0x00, 0x00, 0x00]); // Terminator block at 0
      // Pad to 16:
      bb.add(List.filled(16 - bb.length, 0));

      // Code at 0x10:
      // 1. pushi 2 (argc)
      bb.add([0x39, 0x02]);
      // 2. pushi 100 (arg0: pic 100)
      bb.add([0x39, 0x64]);
      // 3. push0 (arg1: animation 0)
      bb.add([0x76]);
      // 4. callk DrawPic 4 (kId = 8, argcBytes = 4)
      bb.add([0x42, 0x08, 0x00, 0x04]);
      // 5. ret
      bb.add([0x48]);

      final parser = const SciScriptParser();
      final script = parser.parse(10, bb.toBytes(), 1);

      final kernel = SciKernel();
      final ctx = SciDisassemblyContext(
        script: script,
        kernel: kernel,
      );

      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x10);

      expect(decompiled.contains('(DrawPic 100 0)'), isTrue);
    });

    test('Decompiles nested binary arithmetic: (= temp2 (+ temp0 (* temp1 2)))', () {
      final bb = BytesBuilder();
      bb.add([0x00, 0x00, 0x00, 0x00]);
      bb.add(List.filled(16 - bb.length, 0));

      // Code at 0x10:
      // 1. lat 0
      bb.add([0x85, 0x00]);
      // 2. push
      bb.add([0x36]);
      // 3. lat 1
      bb.add([0x85, 0x01]);
      // 4. push
      bb.add([0x36]);
      // 5. ldi 2
      bb.add([0x35, 0x02]);
      // 6. mul (temp1 * 2)
      bb.add([0x06]);
      // 7. add (temp0 + (temp1 * 2))
      bb.add([0x02]);
      // 8. sat 2 (temp2 = result)
      bb.add([0xa5, 0x02]);
      // 9. ret
      bb.add([0x48]);

      final parser = const SciScriptParser();
      final script = parser.parse(10, bb.toBytes(), 1);

      final ctx = SciDisassemblyContext(script: script);
      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x10);

      expect(decompiled.contains('(= temp2 (+ temp0 (* temp1 2)))'), isTrue);
    });

    test('Decompiles structured if conditional: (if temp0 (= g0 1))', () {
      final bb = BytesBuilder();
      bb.add([0x00, 0x00, 0x00, 0x00]);
      bb.add(List.filled(16 - bb.length, 0));

      // Code at 0x10:
      // 1. lat 0 (temp0)
      bb.add([0x85, 0x00]); // 2 bytes
      // 2. bnt +6 (to offset 0x10 + 2 + 2 + 6 = 0x1A)
      bb.add([0x31, 0x06]); // 2 bytes
      // Then body at 0x14:
      // 3. ldi 1
      bb.add([0x35, 0x01]); // 2 bytes
      // 4. sag 0 (g0 = 1)
      bb.add([0xa1, 0x00]); // 2 bytes
      // Target at 0x18: wait, offset 0x10 + 2(lat) + 2(bnt) + 2(ldi) + 2(sag) = 0x18!
      // So bnt rel is +4 bytes!
      // Let's adjust bytes carefully:
      // [0x10] lat 0 (2 bytes)
      // [0x12] bnt +4 (2 bytes: extOpcode 0x31 (bnt byte mode), operand 0x04)
      // [0x14] ldi 1 (2 bytes: 0x35, 0x01)
      // [0x16] sag 0 (2 bytes: 0xa1, 0x00)
      // [0x18] ret (1 byte: 0x48)

      final bbFixed = BytesBuilder();
      bbFixed.add([0x00, 0x00, 0x00, 0x00]);
      bbFixed.add(List.filled(16 - bbFixed.length, 0));
      bbFixed.add([0x85, 0x00]); // [0x10] lat 0
      bbFixed.add([0x31, 0x04]); // [0x12] bnt +4 -> 0x12 + 2 + 4 = 0x18
      bbFixed.add([0x35, 0x01]); // [0x14] ldi 1
      bbFixed.add([0xa1, 0x00]); // [0x16] sag 0
      bbFixed.add([0x48]);       // [0x18] ret

      final parser = const SciScriptParser();
      final script = parser.parse(10, bbFixed.toBytes(), 1);

      final ctx = SciDisassemblyContext(script: script);
      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x10);

      expect(decompiled.contains('(if temp0'), isTrue);
      expect(decompiled.contains('(= g0 1)'), isTrue);
    });

    test('Decompiles structured while loop: (while temp0 (= g0 1))', () {
      final bb = BytesBuilder();
      bb.add([0x00, 0x00, 0x00, 0x00]);
      bb.add(List.filled(16 - bb.length, 0));

      // [0x10] lat 0 (2 bytes: 0x85, 0x00)
      bb.add([0x85, 0x00]);
      // [0x12] bnt +6 (2 bytes: 0x31, 0x06 -> target 0x12 + 2 + 6 = 0x1A)
      bb.add([0x31, 0x06]);
      // [0x14] ldi 1 (2 bytes: 0x35, 0x01)
      bb.add([0x35, 0x01]);
      // [0x16] sag 0 (2 bytes: 0xa1, 0x00)
      bb.add([0xa1, 0x00]);
      // [0x18] jmp -10 (2 bytes: 0x33, 0xf6 -> target 0x18 + 2 - 10 = 0x10)
      bb.add([0x33, 0xF6]);
      // [0x1A] ret (1 byte: 0x48)
      bb.add([0x48]);

      final parser = const SciScriptParser();
      final script = parser.parse(10, bb.toBytes(), 1);

      final ctx = SciDisassemblyContext(script: script);
      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x10);

      expect(decompiled.contains('(while temp0'), isTrue);
      expect(decompiled.contains('(= g0 1)'), isTrue);
    });

    test('Decompiles multi-message cascading send: (theSound loop: 1 play:)', () {
      final bb = BytesBuilder();
      bb.add([0x00, 0x00, 0x00, 0x00]);
      bb.add(List.filled(16 - bb.length, 0));

      // Code at 0x10:
      // Send packet: 5 words = 10 bytes (0x0a)
      // 1. pushi #loop (0x07)
      bb.add([0x39, 0x07]);
      // 2. push1 (argc = 1)
      bb.add([0x78]);
      // 3. push1 (arg0 = 1)
      bb.add([0x78]);
      // 4. pushi #play (0x20)
      bb.add([0x39, 0x20]);
      // 5. push0 (argc = 0)
      bb.add([0x76]);
      // Receiver: lat 0 (theSound in temp0)
      bb.add([0x85, 0x00]);
      // send 10
      bb.add([0x4b, 0x0a]);
      // ret
      bb.add([0x48]);

      final parser = const SciScriptParser();
      final script = parser.parse(10, bb.toBytes(), 1);

      final selectors = SciSelectors();
      selectors.registerSelector('loop', 0x07);
      selectors.registerSelector('play', 0x20);

      final ctx = SciDisassemblyContext(
        script: script,
        selectors: selectors,
      );
      final decompiler = SciMethodDecompiler(ctx);
      final decompiled = decompiler.decompile(startPc: 0x10);

      expect(decompiled.contains('(temp0'), isTrue);
      expect(decompiled.contains('loop: 1'), isTrue);
      expect(decompiled.contains('play:'), isTrue);
    });
  });

  group('SciMethodDecompiler Real Game Tests (Police Quest 2)', () {
    test('Decompiles PQ2 Script 0 methods into readable Sierra Script code', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference directory missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segMan = SciSegManager();
      final kernel = SciKernel();
      final selectors = SciSelectors();

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

      final decompiler = SciMethodDecompiler(ctx);

      // Find PQ object
      final pqObj = script0.objects.values.firstWhere((o) => o.nameString == 'PQ');
      final initOffset = pqObj.methods[selectors.findSelector('init')!]!;

      final initDecompiled = decompiler.decompile(startPc: initOffset);
      expect(initDecompiled.isNotEmpty, isTrue);
      // Verify that super init is reconstructed cleanly
      expect(initDecompiled.contains('(super init:)'), isTrue);
      // Verify that raw mnemonics like "pushi #init", "super 0x31, 4" do not appear as statements
      expect(initDecompiled.contains('pushi'), isFalse);
      expect(initDecompiled.contains('callk'), isFalse);
      expect(initDecompiled.contains('send'), isFalse);

      // Verify handleEvent method on PQ
      final handleEventOffset = pqObj.methods[selectors.findSelector('handleEvent')!]!;
      final handleEventDecompiled = decompiler.decompile(startPc: handleEventOffset);
      final firstLines = handleEventDecompiled.split('\n').take(15).join('\n');
      // ignore: avoid_print
      print('handleEventDecompiled first 15 lines:\n$firstLines');
      expect(handleEventDecompiled.contains('(super handleEvent:'), isTrue);

      // Verify statusCode::doit calls Format
      final statusObj = script0.objects.values.firstWhere((o) => o.nameString == 'statusCode');
      final doitOffset = statusObj.methods[selectors.findSelector('doit')!]!;
      final doitDecompiled = decompiler.decompile(startPc: doitOffset);
      expect(doitDecompiled.contains('(Format'), isTrue);
    });
  });
}
