// High-level Sierra Script Language (.SC style) decompiler for SCI0.

import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_method_decompiler.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

/// Structured listing of an instantiated [SciScript] in Sierra Script (.SC)
/// format with decompiled method and procedure bodies.
class SciDecompiler {
  final SciDisassemblyContext context;

  const SciDecompiler(this.context);

  SciScript get script => context.script;

  /// Builds a formatted Sierra Script (.SC) outline of the script.
  String decompileScript() {
    final sb = StringBuffer();

    // 1. Script Banner
    sb.writeln(';;; Sierra SCI0 script decompiled listing');
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
    final procOffsets = script.procedureOffsets;
    for (var i = 0; i < procOffsets.length; i++) {
      final procOffset = procOffsets[i];
      if (procOffset < 0 || procOffset >= script.bytes.length) continue;

      final expIdx = script.exports.indexOf(procOffset);
      final procName = expIdx >= 0
          ? 'export_$expIdx'
          : 'proc_0x${procOffset.toRadixString(16)}';

      final methodDecompiler = SciMethodDecompiler(context);
      final header = methodDecompiler.buildProcedureHeader(
        procName: procName,
        procOffset: procOffset,
        indent: '',
      );
      sb.writeln(header);
      final body = methodDecompiler.decompile(
        startPc: procOffset,
        indent: '  ',
      );
      sb.write(body);
      sb.writeln(')');
      sb.writeln();
    }

    // 5. Classes & Objects (Instances)
    final sortedObjects = script.objects.values.toList()
      ..sort((a, b) => a.pos.offset.compareTo(b.pos.offset));

    for (final obj in sortedObjects) {
      _decompileObject(obj, sb);
      sb.writeln();
    }

    return sb.toString();
  }

  /// Decompiles an individual Object or Class definition.
  void _decompileObject(SciObject obj, StringBuffer sb) {
    final keyword = obj.isClass ? 'class' : 'instance';
    final name = obj.nameString ?? 'obj_0x${obj.pos.offset.toRadixString(16)}';

    final superName = context.resolveSuperName(obj.superClass);

    sb.writeln('($keyword $name of $superName  ; at 0x${obj.pos.offset.toRadixString(16)}');

    // Properties block
    if (obj.variables.isNotEmpty) {
      sb.writeln('  (properties');
      for (var i = 0; i < obj.variables.length; i++) {
        final val = obj.variables[i];
        final propName = _getPropertyName(obj, i);

        // Value formatting
        String valStr;
        String? note;

        if (propName == 'name') {
          valStr = '"${obj.nameString ?? ""}"';
        } else if (propName == 'species') {
          valStr = '${val.toUint16()}';
          final clsName = context.resolveClassName(val.toUint16());
          if (clsName != 'Class_${val.toUint16()}') {
            note = clsName;
          }
        } else if (propName == 'superClass') {
          valStr = '${val.toUint16()}';
          note = superName;
        } else if (propName == '-info-') {
          valStr = '0x${val.toUint16().toRadixString(16)}';
        } else if (val.isPointer) {
          final targetObj = context.resolveObjectName(val.offset, val.segment);
          if (targetObj != null) {
            valStr = targetObj;
          } else if (context.isSaidOffset(val.offset)) {
            final saidStr = context.resolveSaidString(val.offset);
            valStr = "'$saidStr'";
          } else {
            final str = context.resolveString(val.offset);
            if (str != null && str.isNotEmpty) {
              valStr = '"$str"';
            } else {
              valStr = 'ptr_0x${val.offset.toRadixString(16)}';
            }
          }
        } else {
          valStr = '${val.toUint16()}';
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
      final methodOffset = m.value;
      final selName = context.resolveSelectorName(m.key);
      final methodDecompiler = SciMethodDecompiler(
        context,
        currentObject: obj,
        methodName: '$name::$selName',
      );
      final header = methodDecompiler.buildMethodHeader(
        selectorId: m.key,
        methodOffset: methodOffset,
        indent: '  ',
      );
      sb.writeln();
      sb.writeln(header);
      final body = methodDecompiler.decompile(
        startPc: methodOffset,
        indent: '    ',
      );
      sb.write(body);
      sb.writeln('  )');
    }

    sb.writeln(')');
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
