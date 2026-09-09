import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_opcodes.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

class TestVmObserver implements SciVmObserver {
  final List<String> instructionSteps = [];
  final List<String> kernelCalls = [];
  final List<String> sends = [];
  final List<String> propertyAccesses = [];

  @override
  void onInstructionStep(SciVM vm, SciExecStack frame, SciInstruction instr) {
    instructionSteps.add('${instr.name} (${instr.operands.join(", ")})');
  }

  @override
  void onKernelCall(int kernelId, String name, int argc, List<SciReg> argv, SciReg result) {
    kernelCalls.add('$name(argc: $argc) -> $result');
  }

  @override
  void onSendSelector(SciReg target, int selectorId, String selectorName, int argc, List<SciReg> argv) {
    sends.add('send $selectorName to $target');
  }

  @override
  void onPropertyAccess(SciObject obj, int selectorId, String selectorName, SciReg oldValue, SciReg? newValue) {
    propertyAccesses.add('$selectorName: $oldValue -> $newValue');
  }

  @override
  void onScriptLoaded(int scriptNr, int segmentId) {}
}

void main() {
  group('SciOpcode Instruction Decoder Tests', () {
    test('Decodes opcodes with byte and word modes', () {
      // 0x01 = add (extOpcode: 0x02, opcode: 1)
      final addCode = Uint8List.fromList([0x02]);
      final addInstr = decodeInstruction(addCode, 0);
      expect(addInstr.opcode, 1);
      expect(addInstr.name, 'add');
      expect(addInstr.length, 1);

      // 0x1A = ldi (extOpcode: 0x35 byte mode, operand: 42)
      final ldiByteCode = Uint8List.fromList([0x35, 42]);
      final ldiByteInstr = decodeInstruction(ldiByteCode, 0);
      expect(ldiByteInstr.opcode, 0x1A);
      expect(ldiByteInstr.isByteMode, isTrue);
      expect(ldiByteInstr.operands, [42]);
      expect(ldiByteInstr.length, 2);

      // 0x1A = ldi (extOpcode: 0x34 word mode, operand: 0x1234)
      final ldiWordCode = Uint8List.fromList([0x34, 0x34, 0x12]);
      final ldiWordInstr = decodeInstruction(ldiWordCode, 0);
      expect(ldiWordInstr.opcode, 0x1A);
      expect(ldiWordInstr.isByteMode, isFalse);
      expect(ldiWordInstr.operands, [0x1234]);
      expect(ldiWordInstr.length, 3);

      // 0x21 = callk (extOpcode: 0x43 byte mode, operands: kernel 8 (DrawPic), 2 args)
      final callkCode = Uint8List.fromList([0x43, 0x08, 0x04]);
      final callkInstr = decodeInstruction(callkCode, 0);
      expect(callkInstr.opcode, 0x21);
      expect(callkInstr.name, 'callk');
      expect(callkInstr.operands, [8, 4]);
      expect(callkInstr.length, 3);
    });
  });

  group('SciVM Execution Engine Tests', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciSelectors selectors;
    late SciVM vm;

    setUp(() {
      segMan = SciSegManager();
      kernel = SciKernel();
      selectors = SciSelectors();
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
    });

    test('Arithmetic execution (10 + 20 = 30)', () {
      // Bytecode:
      // ldi 10 (0x35, 10)
      // push   (0x36)
      // ldi 20 (0x35, 20)
      // add    (0x02)
      // ret    (0x48)
      final code = Uint8List.fromList([
        0x35, 10,
        0x36,
        0x35, 20,
        0x02,
        0x48,
      ]);

      final script = SciScript(
        scriptNumber: 100,
        segmentId: 1,
        bytes: code,
      );
      segMan.loadedScripts[1] = script;

      final frame = SciExecStack(
        objp: SciReg.nullReg,
        pc: const SciReg.pointer(1, 0),
        localSegment: 1,
        sp: 0,
        fp: 0,
      );
      vm.executionStack.add(frame);
      vm.runVm();

      expect(vm.r_acc.toSint16(), 30);
    });

    test('Comparisons and conditional branches (bt / bnt)', () {
      // if (5 < 10) r_acc = 100 else r_acc = 200
      // ldi 5    (0x35, 5)
      // push     (0x36)
      // ldi 10   (0x35, 10)
      // lt?      (0x22)
      // bnt +5   (0x31, 5) -> jump to else
      // ldi 100  (0x35, 100)
      // jmp +3   (0x33, 3)
      // ldi 200  (0x35, 200)
      // ret      (0x48)
      final code = Uint8List.fromList([
        0x35, 5,       // pc=0: ldi 5
        0x36,          // pc=2: push
        0x35, 10,      // pc=3: ldi 10
        0x22,          // pc=5: lt? -> POP (5) < acc (10) -> acc = 1
        0x31, 5,       // pc=6: bnt +5 (not taken because acc is 1)
        0x35, 100,     // pc=8: ldi 100
        0x33, 3,       // pc=10: jmp +3 -> jump to ret
        0x35, 200,     // pc=12: ldi 200 (else)
        0x48,          // pc=14: ret
      ]);

      final script = SciScript(
        scriptNumber: 101,
        segmentId: 1,
        bytes: code,
      );
      segMan.loadedScripts[1] = script;

      final frame = SciExecStack(
        objp: SciReg.nullReg,
        pc: const SciReg.pointer(1, 0),
        localSegment: 1,
        sp: 0,
        fp: 0,
      );
      vm.executionStack.add(frame);
      vm.runVm();

      expect(vm.r_acc.toSint16(), 100);
    });

    test('Variable load, store and increment grid', () {
      // Global variable test:
      // ldi 42   (0x35, 42)
      // sag 0    (0xA1, 0)
      // +ag 0    (0xC1, 0) -> acc = 43
      // ret      (0x48)
      final code = Uint8List.fromList([
        0x35, 42,
        0xA1, 0,
        0xC1, 0,
        0x48,
      ]);

      final script = SciScript(
        scriptNumber: 102,
        segmentId: 1,
        bytes: code,
      );
      segMan.loadedScripts[1] = script;

      final frame = SciExecStack(
        objp: SciReg.nullReg,
        pc: const SciReg.pointer(1, 0),
        localSegment: 1,
        sp: 0,
        fp: 0,
      );
      vm.executionStack.add(frame);
      vm.runVm();

      expect(vm.r_acc.toSint16(), 43);
      expect(segMan.globals[0].toSint16(), 43);
    });

    test('Message sending and observer callbacks', () {
      final observer = TestVmObserver();
      vm.addObserver(observer);

      // Create a test object with an 'init' method (selector 87)
      // Method bytecode: ldi 999, ret
      final methodCode = Uint8List.fromList([
        0x34, 0xE7, 0x03, // ldi 999 (0x03E7)
        0x48,             // ret
      ]);

      final script = SciScript(
        scriptNumber: 103,
        segmentId: 2,
        bytes: methodCode,
      );
      segMan.loadedScripts[2] = script;

      final obj = SciObject(
        pos: const SciReg.pointer(2, 0x10),
        variables: [const SciReg.fromInt(1), const SciReg.fromInt(0), const SciReg.fromInt(0), const SciReg.fromInt(0)],
        methods: {87: 0},
        nameString: 'TestObj',
      );
      script.objects[0x10] = obj;

      // Send (TestObj init:)
      vm.sendSelector(obj.pos, 87, []);

      expect(vm.r_acc.toSint16(), 999);
      expect(observer.sends.isNotEmpty, isTrue);
      expect(observer.instructionSteps.isNotEmpty, isTrue);
    });

    test('call restores the stack to the pre-argument base', () {
      // pushi 99, pushi 0 (argc), call +0, ret
      final code = Uint8List.fromList([
        0x39, 99,
        0x39, 0,
        0x41, 0, 0,
        0x48,
      ]);
      final script = SciScript(scriptNumber: 104, segmentId: 1, bytes: code);
      segMan.loadedScripts[1] = script;
      vm.executionStack.add(
        SciExecStack(
          objp: SciReg.nullReg,
          pc: const SciReg.pointer(1, 0),
          localSegment: 1,
          sp: 0,
          fp: 0,
        ),
      );
      vm.runVm();
      expect(vm.stack.length, 1);
      expect(vm.stack.first.toSint16(), 99);
    });
  });
}
