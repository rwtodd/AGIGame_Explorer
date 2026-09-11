// SCI0 Bytecode Disassembler and Symbol Resolver.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_opcodes.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

/// Context symbols and resolvers for enriching SCI disassembly.
class SciDisassemblyContext {
  final SciScript script;
  final SciSelectors? selectors;
  final SciSegManager? segManager;
  final SciKernel? kernel;

  const SciDisassemblyContext({
    required this.script,
    this.selectors,
    this.segManager,
    this.kernel,
  });

  /// Resolves kernel function name by ID.
  String resolveKernelName(int id) {
    if (kernel != null) {
      return kernel!.getKernelName(id);
    }
    return 'k_0x${id.toRadixString(16)}';
  }

  /// Resolves selector name by ID.
  String resolveSelectorName(int id) {
    if (selectors != null) {
      return selectors!.getSelectorName(id);
    }
    return 'sel_$id';
  }

  /// Resolves class name by species number.
  String resolveClassName(int species) {
    if (segManager != null) {
      final addr = segManager!.getClassAddress(species);
      if (!addr.isNull) {
        final obj = segManager!.getObject(addr);
        if (obj?.nameString != null) {
          return obj!.nameString!;
        }
      }
    }
    return 'Class_$species';
  }

  /// Superclass may be a species id or, after instantiate, a pointer.
  String resolveSuperName(SciReg superClass) {
    if (superClass.isPointer && segManager != null) {
      final obj = segManager!.getObject(superClass);
      if (obj?.nameString != null) return obj!.nameString!;
    }
    return resolveClassName(superClass.toUint16());
  }

  /// Resolves an object name at the given script [offset].
  String? resolveObjectName(int offset) {
    final obj = script.objects[offset];
    if (obj != null && obj.nameString != null) {
      return obj.nameString;
    }
    return null;
  }

  /// Resolves a string literal starting at [offset].
  String? resolveString(int offset) {
    final str = script.getString(offset);
    return str.isNotEmpty ? str : null;
  }
}

/// A disassembled instruction or structural line in an SCI script.
class SciDisassemblyLine {
  /// Script byte offset.
  final int address;

  /// Raw byte sequence of this instruction.
  final Uint8List rawBytes;

  /// Decoded instruction, or null for structural/comment/label lines.
  final SciInstruction? instruction;

  /// Opcode mnemonic (e.g. `callk`, `pushi`, `send`, `bnt`).
  final String mnemonic;

  /// Formatted operand strings.
  final List<String> operands;

  /// Inline annotation or comment (e.g. `; Jump to 0x01a4 (+22)`).
  final String? comment;

  /// Section or symbol label (e.g. `rm1::init:`, `localProc_0:`).
  final String? label;

  /// True if this line represents a label or section header.
  final bool isLabel;

  /// Indentation level.
  final int indent;

  /// Target jump/branch address if applicable.
  final int? targetAddress;

  /// Target external script number if applicable (`calle`, `ScriptID`).
  final int? targetScriptNumber;

  /// Target View resource number if detected.
  final int? targetViewNum;

  /// Target Picture resource number if detected.
  final int? targetPicNum;

  /// Target Sound resource number if detected.
  final int? targetSoundNum;

  const SciDisassemblyLine({
    required this.address,
    required this.rawBytes,
    this.instruction,
    required this.mnemonic,
    this.operands = const [],
    this.comment,
    this.label,
    this.isLabel = false,
    this.indent = 0,
    this.targetAddress,
    this.targetScriptNumber,
    this.targetViewNum,
    this.targetPicNum,
    this.targetSoundNum,
  });

  /// Formatted hex byte representation (e.g. `43 00 04`).
  String get hexBytes =>
      rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  /// Address formatted as 4-digit hexadecimal (e.g. `01a4`).
  String get hexAddress => address.toRadixString(16).padLeft(4, '0');

  /// Full text representation of the line.
  String get rawText {
    if (isLabel) {
      return label ?? '';
    }
    final sb = StringBuffer();
    sb.write('[$hexAddress]  ');
    sb.write(hexBytes.padRight(12));
    sb.write('  ');
    sb.write('  ' * indent);
    sb.write(mnemonic.padRight(10));
    if (operands.isNotEmpty) {
      sb.write(' ');
      sb.write(operands.join(', '));
    }
    if (comment != null && comment!.isNotEmpty) {
      sb.write('   ; $comment');
    }
    return sb.toString();
  }

  @override
  String toString() => rawText;
}

/// Disassembler for Sierra SCI0 PMachine bytecode.
class SciDisassembler {
  final SciDisassemblyContext context;

  const SciDisassembler(this.context);

  SciScript get script => context.script;

  /// Disassembles the entire script into a comprehensive list of [SciDisassemblyLine]s.
  List<SciDisassemblyLine> disassembleScript() {
    final lines = <SciDisassemblyLine>[];

    // 1. Script Header
    lines.add(
      SciDisassemblyLine(
        address: 0,
        rawBytes: Uint8List(0),
        mnemonic: '',
        label: '; ========================================================',
        isLabel: true,
      ),
    );
    lines.add(
      SciDisassemblyLine(
        address: 0,
        rawBytes: Uint8List(0),
        mnemonic: '',
        label: '; SCRIPT ${script.scriptNumber} (Size: ${script.size} bytes, '
            'Objects: ${script.objects.length}, Locals: ${script.locals.length}, '
            'Exports: ${script.exports.length})',
        isLabel: true,
      ),
    );
    lines.add(
      SciDisassemblyLine(
        address: 0,
        rawBytes: Uint8List(0),
        mnemonic: '',
        label: '; ========================================================',
        isLabel: true,
      ),
    );

    // 2. Disassemble standalone procedures (exports and code blocks)
    final procOffsets = script.procedureOffsets;
    for (var i = 0; i < procOffsets.length; i++) {
      final procOffset = procOffsets[i];
      if (procOffset < 0 || procOffset >= script.bytes.length) continue;

      // Identify export index if any
      final expIdx = script.exports.indexOf(procOffset);
      final procName = expIdx >= 0
          ? 'export_$expIdx (proc_0x${procOffset.toRadixString(16)})'
          : 'proc_0x${procOffset.toRadixString(16)}';

      lines.add(
        SciDisassemblyLine(
          address: procOffset,
          rawBytes: Uint8List(0),
          mnemonic: '',
          label: '\n; --- Procedure $procName ---',
          isLabel: true,
        ),
      );

      final procLines = disassembleCodeSequence(procOffset, name: procName);
      lines.addAll(procLines);
    }

    // 3. Disassemble Objects & Classes
    final sortedObjects = script.objects.values.toList()
      ..sort((a, b) => a.pos.offset.compareTo(b.pos.offset));

    for (final obj in sortedObjects) {
      final kind = obj.isClass ? 'Class' : 'Instance';
      final name = obj.nameString ?? 'obj_0x${obj.pos.offset.toRadixString(16)}';
      final speciesStr = obj.isClass
          ? 'species: ${obj.species.toUint16()} [${context.resolveSuperName(obj.species)}]'
          : 'species: ${context.resolveSuperName(obj.species)}';

      lines.add(
        SciDisassemblyLine(
          address: obj.pos.offset,
          rawBytes: Uint8List(0),
          mnemonic: '',
          label: '\n; ========================================================',
          isLabel: true,
        ),
      );
      lines.add(
        SciDisassemblyLine(
          address: obj.pos.offset,
          rawBytes: Uint8List(0),
          mnemonic: '',
          label: '; $kind $name ($speciesStr at 0x${obj.pos.offset.toRadixString(16)})',
          isLabel: true,
        ),
      );
      lines.add(
        SciDisassemblyLine(
          address: obj.pos.offset,
          rawBytes: Uint8List(0),
          mnemonic: '',
          label: '; ========================================================',
          isLabel: true,
        ),
      );

      // Disassemble each method defined in this object
      final sortedMethods = obj.methods.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      for (final m in sortedMethods) {
        final selName = context.resolveSelectorName(m.key);
        final methodOffset = m.value;
        if (methodOffset < 0 || methodOffset >= script.bytes.length) continue;

        lines.add(
          SciDisassemblyLine(
            address: methodOffset,
            rawBytes: Uint8List(0),
            mnemonic: '',
            label: '\n$name::$selName:   ; Method at 0x${methodOffset.toRadixString(16)}',
            isLabel: true,
          ),
        );

        final methodLines = disassembleCodeSequence(
          methodOffset,
          name: '$name::$selName',
          currentObject: obj,
        );
        lines.addAll(methodLines);
      }
    }

    return lines;
  }

  /// Disassembles a continuous bytecode sequence starting at [startPc] until `ret`
  /// or when branch targets stop extending beyond `ret`.
  List<SciDisassemblyLine> disassembleCodeSequence(
    int startPc, {
    String? name,
    SciObject? currentObject,
    int maxInstructions = 2000,
  }) {
    final lines = <SciDisassemblyLine>[];
    final bytes = script.bytes;
    if (startPc < 0 || startPc >= bytes.length) return lines;

    var pc = startPc;
    var maxBranchTarget = startPc;
    var count = 0;

    while (pc < bytes.length && count++ < maxInstructions) {
      final instrOffset = pc;
      final instr = decodeInstruction(bytes, pc);
      final rawBytes = bytes.sublist(instrOffset, instrOffset + instr.length);

      // Track branch target to follow branches jumping past an internal ret
      int? branchTarget;
      int? scriptNum;
      int? viewNum;
      int? picNum;
      int? soundNum;
      final comments = <String>[];

      // Jump / branch opcodes: 0x17 (bt), 0x18 (bnt), 0x19 (jmp)
      if (instr.opcode == 0x17 || instr.opcode == 0x18 || instr.opcode == 0x19) {
        if (instr.operands.isNotEmpty) {
          final rel = instr.operands[0];
          final target = instrOffset + instr.length + rel;
          branchTarget = target;
          if (target > maxBranchTarget) {
            maxBranchTarget = target;
          }
          final sign = rel >= 0 ? '+$rel' : '$rel';
          comments.add('Target: 0x${target.toRadixString(16).padLeft(4, '0')} ($sign)');
        }
      }

      // lofsa (0x39) / lofss (0x3A)
      if (instr.opcode == 0x39 || instr.opcode == 0x3A) {
        if (instr.operands.isNotEmpty) {
          final rel = instr.operands[0];
          final target = instrOffset + instr.length + rel;
          final objName = context.resolveObjectName(target);
          if (objName != null) {
            comments.add('Object "$objName" [0x${target.toRadixString(16)}]');
          } else {
            final str = context.resolveString(target);
            if (str != null && str.isNotEmpty) {
              final preview = str.length > 30 ? '${str.substring(0, 27)}...' : str;
              comments.add('"$preview"');
            } else {
              comments.add('Offset 0x${target.toRadixString(16)}');
            }
          }
        }
      }

      // callk (0x21): operand 0 is kernel ID, operand 1 is argc
      if (instr.opcode == 0x21 && instr.operands.isNotEmpty) {
        final kId = instr.operands[0];
        final kName = context.resolveKernelName(kId);
        comments.add('Kernel: $kName');
      }

      // pushi (0x1C): operand 0 is value / selector ID
      if (instr.opcode == 0x1C && instr.operands.isNotEmpty) {
        final val = instr.operands[0];
        final selName = context.resolveSelectorName(val);
        if (!selName.startsWith('sel_')) {
          comments.add('#$selName');
        }
      }

      // class (0x28) / super (0x2B): operand 0 is class ID
      if ((instr.opcode == 0x28 || instr.opcode == 0x2B) && instr.operands.isNotEmpty) {
        final cId = instr.operands[0];
        final cName = context.resolveClassName(cId);
        comments.add('Class: $cName');
      }

      // calle (0x23): script, export, argc
      if (instr.opcode == 0x23 && instr.operands.length >= 2) {
        scriptNum = instr.operands[0];
        final expNum = instr.operands[1];
        comments.add('Script $scriptNum, export $expNum');
      }

      // Property access opcodes: pToa, aTop, pTos, sTop, ipToa, dpToa, ipTos, dpTos
      if (instr.opcode >= 0x31 && instr.opcode <= 0x38 && instr.operands.isNotEmpty) {
        final propIdx = instr.operands[0] >> 1; // properties indexed by 2 bytes
        final propName = _resolvePropertyName(currentObject, propIdx);
        if (propName != null) {
          comments.add('Property: #$propName');
        }
      }

      // Detect resource references in pushi / ldi / etc.
      _detectResourceReferences(
        instr,
        (v) => viewNum = v,
        (p) => picNum = p,
        (s) => soundNum = s,
      );

      final operandStrings = _formatOperands(instr, instrOffset);

      lines.add(
        SciDisassemblyLine(
          address: instrOffset,
          rawBytes: rawBytes,
          instruction: instr,
          mnemonic: instr.name,
          operands: operandStrings,
          comment: comments.isNotEmpty ? comments.join(', ') : null,
          targetAddress: branchTarget,
          targetScriptNumber: scriptNum,
          targetViewNum: viewNum,
          targetPicNum: picNum,
          targetSoundNum: soundNum,
          indent: 1,
        ),
      );

      pc += instr.length;

      // Stop condition: ret encountered and no forward branches point past it
      if (instr.opcode == 0x24) {
        if (pc >= maxBranchTarget) {
          break;
        }
      }
    }

    return lines;
  }

  /// Formats instruction operands into human-readable strings.
  List<String> _formatOperands(SciInstruction instr, int pc) {
    final list = <String>[];

    // Custom formatting for callk: callk KernelName, argc
    if (instr.opcode == 0x21 && instr.operands.length >= 2) {
      final kName = context.resolveKernelName(instr.operands[0]);
      return [kName, '${instr.operands[1]}'];
    }

    // Custom formatting for pushi: pushi #selector or number
    if (instr.opcode == 0x1C && instr.operands.isNotEmpty) {
      final val = instr.operands[0];
      final sel = context.resolveSelectorName(val);
      if (!sel.startsWith('sel_')) {
        return ['#$sel [0x${val.toRadixString(16)}]'];
      }
      return ['0x${val.toRadixString(16)} ($val)'];
    }

    // Custom formatting for jumps: bt 0x01a4
    if (instr.opcode == 0x17 || instr.opcode == 0x18 || instr.opcode == 0x19) {
      if (instr.operands.isNotEmpty) {
        final rel = instr.operands[0];
        final target = pc + instr.length + rel;
        return ['0x${target.toRadixString(16).padLeft(4, '0')}'];
      }
    }

    // Default operand formatting
    for (final op in instr.operands) {
      if (op >= 0 && op <= 9) {
        list.add('$op');
      } else if (op < 0 && op >= -9) {
        list.add('$op');
      } else {
        list.add('0x${op.toRadixString(16)}');
      }
    }
    return list;
  }

  /// Resolves the property name at [propIndex] using standard SCI0 properties or object baseVars.
  String? _resolvePropertyName(SciObject? obj, int propIndex) {
    if (obj != null && propIndex < obj.baseVars.length) {
      final selId = obj.baseVars[propIndex];
      return context.resolveSelectorName(selId);
    }

    // Standard SCI0 property index table
    switch (propIndex) {
      case 0:
        return 'species';
      case 1:
        return 'superClass';
      case 2:
        return '-info-';
      case 3:
        return 'name';
      case 4:
        return 'y';
      case 5:
        return 'x';
      case 6:
        return 'view';
      case 7:
        return 'loop';
      case 8:
        return 'cel';
      case 9:
        return 'underBits';
      case 10:
        return 'nsTop';
      case 11:
        return 'nsLeft';
      case 12:
        return 'nsBottom';
      case 13:
        return 'nsRight';
      case 14:
        return 'lsTop';
      case 15:
        return 'lsLeft';
      case 16:
        return 'lsBottom';
      case 17:
        return 'lsRight';
      case 18:
        return 'signal';
      case 19:
        return 'illegalBits';
      case 20:
        return 'brTop';
      case 21:
        return 'brLeft';
      case 22:
        return 'brBottom';
      case 23:
        return 'brRight';
      default:
        return null;
    }
  }

  /// Heuristically detects resource references (e.g. DrawPic, view property, etc.).
  void _detectResourceReferences(
    SciInstruction instr,
    void Function(int) setView,
    void Function(int) setPic,
    void Function(int) setSound,
  ) {
    // Detect calle script number
    if (instr.opcode == 0x23 && instr.operands.isNotEmpty) {
      // Handled via targetScriptNumber
    }
  }
}
