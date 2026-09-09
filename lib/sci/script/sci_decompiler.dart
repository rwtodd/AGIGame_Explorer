// High-level Sierra Script Language (.SC style) decompiler for SCI0.

import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

/// Decompiler that reconstructs structured Sierra Script Language (.SC)
/// representation from an instantiated [SciScript].
class SciDecompiler {
  final SciDisassemblyContext context;

  const SciDecompiler(this.context);

  SciScript get script => context.script;

  /// Decompiles the entire script into a formatted Sierra Script (.SC) string.
  String decompileScript() {
    final sb = StringBuffer();

    // 1. Script Banner
    sb.writeln(';;; Sierra SCI0 Decompiled Script');
    sb.writeln(';;; Script: ${script.scriptNumber} (Size: ${script.size} bytes)');
    sb.writeln();
    sb.writeln('(script ${script.scriptNumber})');
    sb.writeln();

    // 2. Exports block
    if (script.exports.isNotEmpty) {
      sb.writeln('(exports');
      for (var i = 0; i < script.exports.length; i++) {
        final offset = script.exports[i];
        final obj = script.objects[offset];
        final name = obj?.nameString ?? 'proc_0x${offset.toRadixString(16)}';
        sb.writeln('  $i $name  ; at 0x${offset.toRadixString(16)}');
      }
      sb.writeln(')');
      sb.writeln();
    }

    // 3. Local variables
    if (script.locals.isNotEmpty) {
      sb.writeln('(local');
      for (var i = 0; i < script.locals.length; i++) {
        final val = script.locals[i];
        final comment = val.isPointer ? '  ; ptr [${val.segment}:${val.offset}]' : '';
        sb.writeln('  local$i = ${val.toUint16()}$comment');
      }
      sb.writeln(')');
      sb.writeln();
    }

    // 4. Standalone Procedures
    final disasm = SciDisassembler(context);
    final procOffsets = script.procedureOffsets;
    for (var i = 0; i < procOffsets.length; i++) {
      final procOffset = procOffsets[i];
      if (procOffset < 0 || procOffset >= script.bytes.length) continue;

      final expIdx = script.exports.indexOf(procOffset);
      final procName = expIdx >= 0
          ? 'export_$expIdx'
          : 'proc_0x${procOffset.toRadixString(16)}';

      sb.writeln('(procedure ($procName)');
      final lines = disasm.disassembleCodeSequence(procOffset, name: procName);
      _formatInstructionBody(lines, sb, indent: '  ');
      sb.writeln(')');
      sb.writeln();
    }

    // 5. Classes & Objects (Instances)
    final sortedObjects = script.objects.values.toList()
      ..sort((a, b) => a.pos.offset.compareTo(b.pos.offset));

    for (final obj in sortedObjects) {
      _decompileObject(obj, sb, disasm);
      sb.writeln();
    }

    return sb.toString();
  }

  /// Decompiles an individual Object or Class definition.
  void _decompileObject(SciObject obj, StringBuffer sb, SciDisassembler disasm) {
    final keyword = obj.isClass ? 'class' : 'instance';
    final name = obj.nameString ?? 'obj_0x${obj.pos.offset.toRadixString(16)}';

    // SuperClass resolution
    final superSpecies = obj.superClass.toUint16();
    final superName = context.resolveClassName(superSpecies);

    sb.writeln('($keyword $name of $superName  ; at 0x${obj.pos.offset.toRadixString(16)}');

    // Properties block
    if (obj.variables.isNotEmpty) {
      sb.writeln('  (properties');
      for (var i = 0; i < obj.variables.length; i++) {
        final val = obj.variables[i];
        final propName = _getPropertyName(obj, i);

        // Value formatting
        String valStr = '${val.toUint16()}';
        String? note;

        if (propName == 'name') {
          valStr = '"${obj.nameString ?? ""}"';
        } else if (val.isPointer) {
          final targetObj = context.resolveObjectName(val.offset);
          if (targetObj != null) {
            valStr = targetObj;
          } else {
            final str = context.resolveString(val.offset);
            if (str != null && str.isNotEmpty) {
              valStr = '"$str"';
            } else {
              valStr = 'ptr_0x${val.offset.toRadixString(16)}';
            }
          }
        } else if (propName == 'superClass') {
          note = superName;
        }

        final comment = note != null ? '  ; $note' : '';
        sb.writeln('    $propName $valStr$comment');
      }
      sb.writeln('  )');
    }

    // Methods
    final sortedMethods = obj.methods.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final m in sortedMethods) {
      final selName = context.resolveSelectorName(m.key);
      final methodOffset = m.value;
      sb.writeln();
      sb.writeln('  (method ($selName)  ; at 0x${methodOffset.toRadixString(16)}');
      final lines = disasm.disassembleCodeSequence(
        methodOffset,
        name: '$name::$selName',
        currentObject: obj,
      );
      _formatInstructionBody(lines, sb, indent: '    ');
      sb.writeln('  )');
    }

    sb.writeln(')');
  }

  /// Formats instruction lines inside a method or procedure body.
  void _formatInstructionBody(
    List<SciDisassemblyLine> lines,
    StringBuffer sb, {
    required String indent,
  }) {
    for (final l in lines) {
      if (l.isLabel) {
        sb.writeln('$indent${l.label}');
        continue;
      }

      final opStr = l.operands.isNotEmpty ? ' ${l.operands.join(", ")}' : '';
      final commentStr = l.comment != null ? '  ; ${l.comment}' : '';
      sb.writeln('$indent  [${l.hexAddress}] ${l.mnemonic}$opStr$commentStr');
    }
  }

  /// Resolves the property name for property variable at [index].
  String _getPropertyName(SciObject obj, int index) {
    if (index < obj.baseVars.length) {
      final selId = obj.baseVars[index];
      return context.resolveSelectorName(selId);
    }
    // Fallback standard property indices
    switch (index) {
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
        return 'prop_$index';
    }
  }
}
