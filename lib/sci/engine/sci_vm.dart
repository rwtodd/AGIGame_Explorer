// SCI0 PMachine Virtual Machine and Execution Engine.

import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_opcodes.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

/// Observer interface for debugging UIs, breakpoints, disassemblers, and monitoring VM state.
abstract class SciVmObserver {
  void onInstructionStep(SciVM vm, SciExecStack frame, SciInstruction instr);
  void onKernelCall(int kernelId, String name, int argc, List<SciReg> argv, SciReg result);
  void onSendSelector(SciReg target, int selectorId, String selectorName, int argc, List<SciReg> argv);
  void onPropertyAccess(SciObject obj, int selectorId, String selectorName, SciReg oldValue, SciReg? newValue);
  void onScriptLoaded(int scriptNr, int segmentId);
}

/// Base adapter for [SciVmObserver] allowing selective callback overrides.
class SciVmBaseObserver implements SciVmObserver {
  final void Function(SciVM vm, SciExecStack frame, SciInstruction instr)? onInstruction;
  final void Function(int kernelId, String name, int argc, List<SciReg> argv, SciReg result)? onKernel;
  final void Function(SciReg target, int selectorId, String selectorName, int argc, List<SciReg> argv)? onSend;
  final void Function(SciObject obj, int selectorId, String selectorName, SciReg oldValue, SciReg? newValue)? onProperty;
  final void Function(int scriptNr, int segmentId)? onScript;

  SciVmBaseObserver({
    this.onInstruction,
    this.onKernel,
    this.onSend,
    this.onProperty,
    this.onScript,
  });

  @override
  void onInstructionStep(SciVM vm, SciExecStack frame, SciInstruction instr) {
    onInstruction?.call(vm, frame, instr);
  }

  @override
  void onKernelCall(int kernelId, String name, int argc, List<SciReg> argv, SciReg result) {
    onKernel?.call(kernelId, name, argc, argv, result);
  }

  @override
  void onSendSelector(SciReg target, int selectorId, String selectorName, int argc, List<SciReg> argv) {
    onSend?.call(target, selectorId, selectorName, argc, argv);
  }

  @override
  void onPropertyAccess(SciObject obj, int selectorId, String selectorName, SciReg oldValue, SciReg? newValue) {
    onProperty?.call(obj, selectorId, selectorName, oldValue, newValue);
  }

  @override
  void onScriptLoaded(int scriptNr, int segmentId) {
    onScript?.call(scriptNr, segmentId);
  }
}

/// Sierra SCI PMachine Virtual Machine.
class SciVM {
  final SciSegManager segManager;
  final SciKernel kernel;
  final SciSelectors selectors;
  SciVolumeManager? volumeManager;

  // --- Registers (canonical Sierra PMachine names) ---
  // ignore: non_constant_identifier_names
  SciReg r_acc = SciReg.nullReg;
  SciReg get acc => r_acc;
  set acc(SciReg v) => r_acc = v;
  // ignore: non_constant_identifier_names
  SciReg r_prev = SciReg.nullReg;
  SciReg get prev => r_prev;
  set prev(SciReg v) => r_prev = v;
  // ignore: non_constant_identifier_names
  int r_rest = 0;

  // --- Stacks ---
  final List<SciReg> stack = [];
  final List<SciExecStack> executionStack = [];
  int executionStackBase = 0;

  // --- Execution State ---
  int stepCounter = 0;
  bool abortScriptProcessing = false;
  bool yieldOnAnimate = false;
  bool yieldRequested = false;
  bool captureDebugLogs = false;

  // --- Debugger & Monitoring Hooks ---
  final List<SciVmObserver> observers = [];
  final Set<int> pcBreakpoints = {};
  final Set<String> kernelBreakpoints = {};
  final Set<int> selectorBreakpoints = {};

  SciVM({
    required this.segManager,
    required this.kernel,
    required this.selectors,
    this.volumeManager,
  }) {
    segManager.volumeManager ??= volumeManager;
    kernel.selectors = selectors;
    kernel.volumeManager ??= volumeManager;
  }

  void addObserver(SciVmObserver observer) => observers.add(observer);
  void removeObserver(SciVmObserver observer) => observers.remove(observer);

  void push(SciReg reg) => stack.add(reg);

  SciReg pop() {
    if (stack.isEmpty) return SciReg.nullReg;
    return stack.removeLast();
  }

  SciReg peek() {
    if (stack.isEmpty) return SciReg.nullReg;
    return stack.last;
  }

  /// Sends a selector message to an object: `(targetObj selector: args...)`.
  void sendSelector(SciReg targetObj, int selectorId, List<SciReg> args) {
    // Push selector ID, argc, and args onto stack
    final frameBase = stack.length;
    stack.add(SciReg.fromInt(selectorId));
    stack.add(SciReg.fromInt(args.length));
    stack.addAll(args);

    _dispatchSend(targetObj, targetObj, frameBase, stack.length - frameBase);
  }

  /// Invokes a method on an object or performs property read/write across the message sequence.
  void _dispatchSend(SciReg targetObj, SciReg workObj, int argBase, int frameSize) {
    var curArg = argBase;
    while (curArg < argBase + frameSize && !abortScriptProcessing && !yieldRequested) {
      if (curArg + 1 >= stack.length) {
        break;
      }
      final selectorId = stack[curArg].toUint16();
      final argc = stack[curArg + 1].toUint16();
      if (curArg + 2 + argc > stack.length) {
        break;
      }
      final argv = stack.sublist(curArg + 2, curArg + 2 + argc);

      for (final obs in observers) {
        obs.onSendSelector(targetObj, selectorId, selectors.getSelectorName(selectorId), argc, argv);
      }

      final obj = segManager.getObject(workObj);
      if (obj == null) {
        curArg += 2 + argc;
        continue;
      }

      // 1. Check if selector resolves to a variable property
      final varIdx = obj.locateVarSelector(segManager, selectorId);
      if (varIdx >= 0 && varIdx < obj.variables.length) {
        if (argc == 0) {
          // Property Read: r_acc = property
          final oldVal = obj.variables[varIdx];
          r_acc = oldVal;
          for (final obs in observers) {
            obs.onPropertyAccess(obj, selectorId, selectors.getSelectorName(selectorId), oldVal, null);
          }
        } else {
          // Property Write: property = arg0
          final oldVal = obj.variables[varIdx];
          final newVal = argv[0];
          obj.variables[varIdx] = newVal;
          r_acc = newVal;
          for (final obs in observers) {
            obs.onPropertyAccess(obj, selectorId, selectors.getSelectorName(selectorId), oldVal, newVal);
          }
        }
        curArg += 2 + argc;
        continue;
      }

      // 2. Check if selector resolves to a method
      final methodInfo = obj.lookupMethod(segManager, selectorId);
      if (methodInfo != null) {
        final (methodObj, codeOffset) = methodInfo;
        final segId = methodObj.pos.segment;
        final scr = segManager.loadedScripts[segId];
        final localSeg = scr?.segmentId ?? segId;

        final isLastSelector = (curArg + 2 + argc >= argBase + frameSize);
        final xframe = SciExecStack(
          objp: targetObj,
          pc: SciReg.pointer(segId, codeOffset),
          localSegment: localSeg,
          sp: isLastSelector ? argBase : stack.length,
          fp: stack.length,
          argc: argc,
          argp: curArg + 1,
          selector: selectorId,
          type: SciExecStackType.call,
        );

        executionStack.add(xframe);
        runVm();
        if (yieldRequested) {
          break;
        }
        curArg += 2 + argc;
        continue;
      }

      // Unknown selector
      curArg += 2 + argc;
    }
  }

  /// Calls an exported public function of a script.
  void executeMethod(int scriptNr, int pubfunct, List<SciReg> args) {
    final argp = stack.length;
    push(SciReg.fromInt(args.length));
    for (final a in args) {
      push(a);
    }
    final frame = _createExportCallFrame(scriptNr, pubfunct, args.length, argp, SciReg.nullReg);
    if (frame != null) {
      executionStack.add(frame);
      runVm();
    }
  }

  SciExecStack? _createExportCallFrame(int scriptNr, int pubfunct, int argc, int argp, SciReg objp) {
    var seg = segManager.scriptToSegment[scriptNr];
    SciScript? scr;
    if (seg != null) {
      scr = segManager.loadedScripts[seg];
    }
    if (scr == null && volumeManager != null) {
      scr = segManager.instantiateScript(scriptNr, volumeManager!);
      seg = scr.segmentId;
    }

    if (scr == null) return null;
    final exportAddr = scr.getExportOffset(pubfunct);
    if (exportAddr == null) return null;

    return SciExecStack(
      objp: objp,
      pc: SciReg.pointer(scr.segmentId, exportAddr),
      localSegment: scr.segmentId,
      sp: stack.length,
      fp: stack.length,
      argc: argc,
      argp: argp,
      script: scriptNr,
      pubfunct: pubfunct,
      type: SciExecStackType.call,
    );
  }

  final ListQueue<String> recentInstructions = ListQueue<String>();
  static const int _instructionLogCap = 30;

  /// Executes PMachine bytecode until the current execution stack frame returns
  /// or [maxSteps] instructions have executed.
  void runVm([int maxSteps = 1000000, int targetDepth = -1]) {
    if (executionStack.isEmpty) return;

    final baseDepth = targetDepth >= 0 ? targetDepth : executionStack.length - 1;
    var steps = 0;

    while (executionStack.length > baseDepth && steps < maxSteps && !abortScriptProcessing) {
      if (yieldRequested) {
        break;
      }
      steps++;
      stepCounter++;

      final frame = executionStack.last;
      final scr = segManager.loadedScripts[frame.pc.segment];
      if (scr == null || frame.pc.offset >= scr.bytes.length) {
        executionStack.pop();
        break;
      }

      // Check PC breakpoint
      if (pcBreakpoints.contains(frame.pc.offset)) {
        break;
      }

      final instr = decodeInstruction(scr.bytes, frame.pc.offset);
      if (captureDebugLogs) {
        if (recentInstructions.length >= _instructionLogCap) {
          recentInstructions.removeFirst();
        }
        recentInstructions.addLast(
          '${frame.pc.segment}:${frame.pc.offset.toRadixString(16)} ${instr.name} ${instr.operands}',
        );
      }
      frame.pc = frame.pc + instr.length;

      if (observers.isNotEmpty) {
        for (final obs in observers) {
          obs.onInstructionStep(this, frame, instr);
        }
      }

      final opcode = instr.opcode;
      final opparams = instr.operands;

      switch (opcode) {
        case 0x00: // bnot
          r_acc = SciReg.fromInt((~r_acc.toUint16()) & 0xFFFF);
          break;

        case 0x01: // add
          r_acc = pop() + r_acc;
          break;

        case 0x02: // sub
          r_acc = pop() - r_acc;
          break;

        case 0x03: // mul
          r_acc = pop() * r_acc;
          break;

        case 0x04: // div
          r_acc = pop() ~/ r_acc;
          break;

        case 0x05: // mod
          r_acc = pop() % r_acc;
          break;

        case 0x06: // shr
          r_acc = pop() >> r_acc;
          break;

        case 0x07: // shl
          r_acc = pop() << r_acc;
          break;

        case 0x08: // xor
          r_acc = pop() ^ r_acc;
          break;

        case 0x09: // and
          r_acc = pop() & r_acc;
          break;

        case 0x0A: // or
          r_acc = pop() | r_acc;
          break;

        case 0x0B: // neg
          r_acc = -r_acc;
          break;

        case 0x0C: // not
          r_acc = SciReg.fromInt(r_acc.isNull ? 1 : 0);
          break;

        case 0x0D: // eq?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() == r_acc ? 1 : 0);
          break;

        case 0x0E: // ne?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() != r_acc ? 1 : 0);
          break;

        case 0x0F: // gt?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() > r_acc ? 1 : 0);
          break;

        case 0x10: // ge?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() >= r_acc ? 1 : 0);
          break;

        case 0x11: // lt?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() < r_acc ? 1 : 0);
          break;

        case 0x12: // le?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop() <= r_acc ? 1 : 0);
          break;

        case 0x13: // ugt?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop().gtU(r_acc) ? 1 : 0);
          break;

        case 0x14: // uge?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop().geU(r_acc) ? 1 : 0);
          break;

        case 0x15: // ult?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop().ltU(r_acc) ? 1 : 0);
          break;

        case 0x16: // ule?
          r_prev = r_acc;
          r_acc = SciReg.fromInt(pop().leU(r_acc) ? 1 : 0);
          break;

        case 0x17: // bt (branch if true)
          if (!r_acc.isNull) {
            frame.pc = frame.pc + opparams[0];
          }
          break;

        case 0x18: // bnt (branch if not true)
          if (r_acc.isNull) {
            frame.pc = frame.pc + opparams[0];
          }
          break;

        case 0x19: // jmp
          frame.pc = frame.pc + opparams[0];
          break;

        case 0x1A: // ldi (load immediate)
          r_acc = SciReg.fromInt(opparams[0]);
          break;

        case 0x1B: // push
          push(r_acc);
          break;

        case 0x1C: // pushi
          push(SciReg.fromInt(opparams[0]));
          break;

        case 0x1D: // toss
          pop();
          break;

        case 0x1E: // dup
          push(peek());
          break;

        case 0x1F: // link (alloc temps)
          final tempCount = opparams[0];
          frame.tempCount = tempCount;
          frame.fp = stack.length;
          for (var i = 0; i < tempCount; i++) {
            push(SciReg.uninitialized);
          }
          break;

        case 0x20: // call (local subroutine)
          final callOffset = frame.pc.offset + opparams[0];
          final rest = r_rest;
          final callArgc = (opparams[1] >> 1) + rest;
          final totalCount = callArgc + 1;
          final callBase = stack.length - totalCount;
          r_rest = 0;
          if (callBase >= 0) {
            final finalArgc = stack[callBase].toUint16() + rest;
            stack[callBase] = SciReg.fromInt(finalArgc);
            frame.sp = callBase;
            executionStack.add(
              SciExecStack(
                objp: frame.objp,
                pc: SciReg.pointer(frame.pc.segment, callOffset),
                localSegment: frame.localSegment,
                sp: callBase,
                fp: stack.length,
                argc: finalArgc,
                argp: callBase,
                type: SciExecStackType.call,
              ),
            );
          }
          break;

        case 0x21: // callk (kernel call)
          final kernelNr = opparams[0];
          final callkArgc = (opparams[1] >> 1) + r_rest;
          r_rest = 0;
          final argv = List<SciReg>.filled(callkArgc, SciReg.nullReg);
          for (var i = callkArgc - 1; i >= 0; i--) {
            argv[i] = pop();
          }
          pop(); // argc word

          final res = kernel.call(this, kernelNr, callkArgc, argv);
          r_acc = res;
          if (observers.isNotEmpty) {
            for (final obs in observers) {
              obs.onKernelCall(kernelNr, kernel.getKernelName(kernelNr), callkArgc, argv, res);
            }
          }
          break;

        case 0x22: // callb (call base script 0)
          final pubfunct = opparams[0];
          final rest = r_rest;
          final callbArgc = (opparams[1] >> 1) + rest;
          final totalCount = callbArgc + 1;
          final callBase = stack.length - totalCount;
          r_rest = 0;
          if (callBase >= 0) {
            final finalArgc = stack[callBase].toUint16() + rest;
            stack[callBase] = SciReg.fromInt(finalArgc);
            frame.sp = callBase;
            final subFrame = _createExportCallFrame(0, pubfunct, finalArgc, callBase, frame.objp);
            if (subFrame != null) {
              subFrame.sp = callBase;
              executionStack.add(subFrame);
            } else {
              stack.length = callBase;
            }
          }
          break;

        case 0x23: // calle (call external script)
          final scriptNr = opparams[0];
          final pubfunct = opparams[1];
          final rest = r_rest;
          final calleArgc = (opparams[2] >> 1) + rest;
          final totalCount = calleArgc + 1;
          final callBase = stack.length - totalCount;
          r_rest = 0;
          if (callBase >= 0) {
            final finalArgc = stack[callBase].toUint16() + rest;
            stack[callBase] = SciReg.fromInt(finalArgc);
            frame.sp = callBase;
            final subFrame = _createExportCallFrame(scriptNr, pubfunct, finalArgc, callBase, frame.objp);
            if (subFrame != null) {
              subFrame.sp = callBase;
              executionStack.add(subFrame);
            } else {
              stack.length = callBase;
            }
          }
          break;

        case 0x24: // ret
          if (frame.sp <= stack.length) {
            stack.length = frame.sp;
          }
          executionStack.pop();
          if (executionStack.length <= baseDepth) {
            return;
          }
          break;

        case 0x25: // send
          final sendArgc = (opparams[0] >> 1) + r_rest;
          final sendBase = stack.length - sendArgc;
          _foldRestIntoSendArgc(sendBase);
          r_rest = 0;
          _dispatchSend(r_acc, r_acc, sendBase, sendArgc);
          if (yieldRequested) break;
          if (sendBase >= 0 && sendBase <= stack.length) {
            stack.length = sendBase;
          }
          break;

        case 0x28: // class
          final classNr = opparams[0];
          r_acc = segManager.getClassAddress(classNr, volumeManager: volumeManager);
          break;

        case 0x2A: // self
          final selfArgc = (opparams[0] >> 1) + r_rest;
          final selfBase = stack.length - selfArgc;
          _foldRestIntoSendArgc(selfBase);
          r_rest = 0;
          _dispatchSend(frame.objp, frame.objp, selfBase, selfArgc);
          if (yieldRequested) break;
          if (selfBase >= 0 && selfBase <= stack.length) {
            stack.length = selfBase;
          }
          break;

        case 0x2B: // super
          final classNr = opparams[0];
          final superArgc = (opparams[1] >> 1) + r_rest;
          final superBase = stack.length - superArgc;
          _foldRestIntoSendArgc(superBase);
          r_rest = 0;
          final superAddr = segManager.getClassAddress(classNr, volumeManager: volumeManager);
          _dispatchSend(frame.objp, superAddr, superBase, superArgc);
          if (yieldRequested) break;
          if (superBase >= 0 && superBase <= stack.length) {
            stack.length = superBase;
          }
          break;

        case 0x2C: // &rest
          // Pushes all or part of the parameter variable list on the stack.
          // Index 0 is argc, so normally this is called as &rest 1 to forward all arguments.
          final firstArg = opparams[0];
          r_rest = max(0, frame.argc - firstArg + 1);
          for (var i = firstArg; i <= frame.argc; i++) {
            push(_readVar(frame, SciVarType.param, i));
          }
          break;

        case 0x2D: // lea (load effective address)
          final leaType = (opparams[0] >> 1) & 0x03;
          final varIdx = opparams[1] + (((opparams[0] >> 1) & 0x08) != 0 ? r_acc.toSint16() : 0);
          r_acc = _getVarAddress(frame, SciVarType.fromId(leaType), varIdx);
          break;

        case 0x2E: // selfID
          r_acc = frame.objp;
          break;

        case 0x30: // pprev
          push(r_prev);
          break;

        case 0x31: // pToa
          r_acc = _readObjProp(frame.objp, opparams[0]);
          break;

        case 0x32: // aTop
          _writeObjProp(frame.objp, opparams[0], r_acc);
          break;

        case 0x33: // pTos
          push(_readObjProp(frame.objp, opparams[0]));
          break;

        case 0x34: // sTop
          _writeObjProp(frame.objp, opparams[0], pop());
          break;

        case 0x35: // ipToa
          final vIncA = _readObjProp(frame.objp, opparams[0]) + 1;
          _writeObjProp(frame.objp, opparams[0], vIncA);
          r_acc = vIncA;
          break;

        case 0x36: // dpToa
          final vDecA = _readObjProp(frame.objp, opparams[0]) - 1;
          _writeObjProp(frame.objp, opparams[0], vDecA);
          r_acc = vDecA;
          break;

        case 0x37: // ipTos
          final vIncS = _readObjProp(frame.objp, opparams[0]) + 1;
          _writeObjProp(frame.objp, opparams[0], vIncS);
          push(vIncS);
          break;

        case 0x38: // dpTos
          final vDecS = _readObjProp(frame.objp, opparams[0]) - 1;
          _writeObjProp(frame.objp, opparams[0], vDecS);
          push(vDecS);
          break;

        case 0x39: // lofsa
          r_acc = SciReg.pointer(frame.pc.segment, frame.pc.offset + opparams[0]);
          break;

        case 0x3A: // lofss
          push(SciReg.pointer(frame.pc.segment, frame.pc.offset + opparams[0]));
          break;

        case 0x3B: // push0
          push(const SciReg.fromInt(0));
          break;

        case 0x3C: // push1
          push(const SciReg.fromInt(1));
          break;

        case 0x3D: // push2
          push(const SciReg.fromInt(2));
          break;

        case 0x3E: // pushSelf
          push(frame.objp);
          break;

        case 0x3F: // line (debug)
          break;

        // --- 0x40..0x7F: Variable Operations Grid ---
        default:
          if (opcode >= 0x40 && opcode <= 0x7F) {
            _executeVariableOpcode(frame, opcode, opparams[0]);
          } else {
            debugPrint(
              '[SciVM] Unhandled opcode 0x${opcode.toRadixString(16)} (${getOpcodeName(opcode)}) '
              'at pc=0x${frame.pc.offset.toRadixString(16)} in script '
              '${segManager.loadedScripts[frame.pc.segment]?.scriptNumber}',
            );
          }
          break;
      }
    }
  }

  void _executeVariableOpcode(SciExecStack frame, int opcode, int varParam) {
    final varType = SciVarType.fromId(opcode & 0x03);
    final isIndexed = (opcode & 0x08) != 0;
    final varIndex = varParam + (isIndexed ? r_acc.toSint16() : 0);

    // 0x40-0x4F: Load
    if (opcode <= 0x4F) {
      final val = _readVar(frame, varType, varIndex);
      if ((opcode & 0x04) == 0) {
        r_acc = val; // load to acc
      } else {
        push(val); // load to stack
      }
      return;
    }

    // 0x50-0x5F: Store
    if (opcode <= 0x5F) {
      if ((opcode & 0x04) == 0) {
        // sag / sagi
        if (isIndexed) r_acc = pop();
        _writeVar(frame, varType, varIndex, r_acc);
      } else {
        // ssg / ssgi
        _writeVar(frame, varType, varIndex, pop());
      }
      return;
    }

    // 0x60-0x6F: Increment (+)
    if (opcode <= 0x6F) {
      final oldVal = _readVar(frame, varType, varIndex);
      final newVal = oldVal + 1;
      _writeVar(frame, varType, varIndex, newVal);
      if ((opcode & 0x04) == 0) {
        r_acc = newVal;
      } else {
        push(newVal);
      }
      return;
    }

    // 0x70-0x7F: Decrement (-)
    if (opcode <= 0x7F) {
      final oldVal = _readVar(frame, varType, varIndex);
      final newVal = oldVal - 1;
      _writeVar(frame, varType, varIndex, newVal);
      if ((opcode & 0x04) == 0) {
        r_acc = newVal;
      } else {
        push(newVal);
      }
      return;
    }
  }

  SciReg _readVar(SciExecStack frame, SciVarType type, int index) {
    switch (type) {
      case SciVarType.global:
        if (index >= 0 && index < segManager.globals.length) {
          return segManager.globals[index];
        }
        return SciReg.nullReg;

      case SciVarType.local:
        final scr = segManager.loadedScripts[frame.localSegment];
        if (scr != null && index >= 0 && index < scr.locals.length) {
          return scr.locals[index];
        }
        return SciReg.nullReg;

      case SciVarType.temp:
        final stackIdx = frame.fp + index;
        if (stackIdx >= 0 && stackIdx < stack.length) {
          return stack[stackIdx];
        }
        return SciReg.nullReg;

      case SciVarType.param:
        // Parameters are indexed from argp: param[0] is argc, param[1] is 1st arg, etc.
        final paramIdx = frame.argp + index;
        if (paramIdx >= 0 && paramIdx < stack.length) {
          return stack[paramIdx];
        }
        return SciReg.nullReg;
    }
  }

  void _writeVar(SciExecStack frame, SciVarType type, int index, SciReg val) {
    switch (type) {
      case SciVarType.global:
        if (index >= 0) {
          while (segManager.globals.length <= index) {
            segManager.globals.add(SciReg.nullReg);
          }
          segManager.globals[index] = val;
        }
        break;

      case SciVarType.local:
        final scr = segManager.loadedScripts[frame.localSegment];
        if (scr != null && index >= 0 && index < scr.locals.length) {
          scr.locals[index] = val;
        }
        break;

      case SciVarType.temp:
        final stackIdx = frame.fp + index;
        if (stackIdx >= 0 && stackIdx < stack.length) {
          stack[stackIdx] = val;
        }
        break;

      case SciVarType.param:
        final paramIdx = frame.argp + index;
        if (paramIdx >= 0 && paramIdx < stack.length) {
          stack[paramIdx] = val;
        }
        break;
    }
  }

  SciReg _getVarAddress(SciExecStack frame, SciVarType type, int index) {
    // Returns immediate index or segment reference
    switch (type) {
      case SciVarType.global:
        return SciReg.pointer(1, index * 2);
      case SciVarType.local:
        return SciReg.pointer(frame.localSegment, index * 2);
      case SciVarType.temp:
        return SciReg.pointer(SciSegManager.listSegmentId, (frame.fp + index) * 2);
      case SciVarType.param:
        return SciReg.pointer(SciSegManager.listSegmentId, (frame.argp + index) * 2);
    }
  }

  /// ScummVM `op_send`/`op_self`/`op_super`: rest args are already on the stack,
  /// but the argc word at `sendBase+1` still has the pre-rest count.
  void _foldRestIntoSendArgc(int sendBase) {
    if (r_rest == 0) return;
    if (sendBase + 1 >= 0 && sendBase + 1 < stack.length) {
      stack[sendBase + 1] = SciReg.fromInt(stack[sendBase + 1].toUint16() + r_rest);
    }
  }

  SciReg _readObjProp(SciReg objAddr, int propIndex) {
    final obj = segManager.getObject(objAddr);
    if (obj == null) return SciReg.nullReg;
    // In SCI0 bytecode, property indices for pToa/aTop are in word offsets (index >> 1)
    final idx = propIndex >> 1;
    if (idx >= 0 && idx < obj.variables.length) {
      return obj.variables[idx];
    }
    return SciReg.nullReg;
  }

  void _writeObjProp(SciReg objAddr, int propIndex, SciReg val) {
    final obj = segManager.getObject(objAddr);
    if (obj == null) return;
    final idx = propIndex >> 1;
    if (idx >= 0 && idx < obj.variables.length) {
      obj.variables[idx] = val;
    }
  }
}

extension _ListPop<T> on List<T> {
  T? pop() {
    if (isEmpty) return null;
    return removeLast();
  }
}
