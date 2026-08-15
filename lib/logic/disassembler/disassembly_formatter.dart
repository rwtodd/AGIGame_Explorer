import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';

/// Context options and symbols used for enriching disassembly output.
class DisassemblyContext {
  final AgiLogicScript? script;
  final AgiDictionary? dictionary;
  final List<AgiObject>? objects;
  final AgiMemory? memory;

  const DisassemblyContext({
    this.script,
    this.dictionary,
    this.objects,
    this.memory,
  });
}

/// Formatter that turns disassembled AGI logic instructions into clean,
/// structured, indented text with rich inline comments and annotations.
class DisassemblyFormatter {
  final DisassemblyContext context;

  const DisassemblyFormatter({this.context = const DisassemblyContext()});

  /// Formats the complete script into a string.
  /// If [includeMessages] is true, the message table is prepended at the top.
  String formatScript(
    AgiLogicScript script, {
    double version = 2.917,
    bool includeMessages = true,
  }) {
    final sb = StringBuffer();
    final effectiveCtx = DisassemblyContext(
      script: script,
      dictionary: context.dictionary,
      objects: context.objects,
      memory: context.memory,
    );

    if (includeMessages && script.messageCount > 0) {
      sb.writeln('[ MESSAGES: ~~~~~~~~~~~~~~~~~~~~~~~~~~');
      for (var i = 1; i <= script.messageCount; i++) {
        sb.writeln('  %m$i: "${script.getMessage(i)}"');
      }
      sb.writeln();
    }

    sb.writeln('[ SCRIPT: ~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
    final decoder = InstructionDecoder(version: version);
    final ast = decoder.decode(script.bytecodes);
    formatInstruction(ast, sb, 0, '', effectiveCtx);

    return sb.toString();
  }

  /// Formats an instruction AST node into [sb] with [indent] and [baseAddress].
  void formatInstruction(
    LogicInstruction instruction,
    StringBuffer sb,
    int baseAddress,
    String indent, [
    DisassemblyContext? ctx,
  ]) {
    final c = ctx ?? context;
    switch (instruction) {
      case CompoundInstruction compound:
        var curAddr = baseAddress;
        for (final child in compound.instructions) {
          formatInstruction(child, sb, curAddr, indent, c);
          curAddr += child.length;
        }

      case BasicInstruction basic:
        _formatBasic(basic, sb, baseAddress, indent, c);

      case SaidInstruction said:
        _formatSaid(said, sb, baseAddress, indent, c);

      case IfInstruction ifIns:
        _formatIf(ifIns, sb, baseAddress, indent, c);

      case UnlessGotoInstruction unlessIns:
        _formatUnless(unlessIns, sb, baseAddress, indent, c);

      case GotoInstruction gotoIns:
        _formatGoto(gotoIns, sb, baseAddress, indent);

      case OrInstruction orIns:
        _formatOr(orIns, sb, baseAddress, indent, c);

      case NotInstruction notIns:
        _formatNot(notIns, sb, baseAddress, indent, c);
    }
  }

  void _formatBasic(
    BasicInstruction basic,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    final addr = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.write('$addr: $indent${basic.name}');

    final extraComments = <String>[];
    final extraIndent = indent.isEmpty ? '' : ' ' * indent.length;

    if (basic.args.isNotEmpty) {
      sb.write('(');
      for (var i = 0; i < basic.args.length; i++) {
        if (i > 0) sb.write(', ');
        final argType = basic.getArgType(i);
        final val = basic.args[i];
        sb.write('${argType.prefix}$val');

        // Context annotations
        switch (argType) {
          case AgiArgType.msg:
            final msgText = c.script?.getMessage(val);
            if (msgText != null && msgText.isNotEmpty) {
              extraComments.add('      $extraIndent[ MSG %m$val: "$msgText"');
            }

          case AgiArgType.flg:
            final flgDesc = c.memory?.getFlagDisplayName(val) ?? AgiMemory.defaultFlagDescriptions[val];
            if (flgDesc != null) {
              extraComments.add('      $extraIndent[ FLAG %f$val: $flgDesc');
            }

          case AgiArgType.variable:
            final varDesc = c.memory?.getVarDisplayName(val) ?? AgiMemory.defaultVarDescriptions[val];
            if (varDesc != null) {
              extraComments.add('      $extraIndent[ VAR %v$val: $varDesc');
            }

          case AgiArgType.inv:
            if (c.objects != null && val < c.objects!.length) {
              extraComments.add('      $extraIndent[ INVENTORY %i$val: "${c.objects![val].name}"');
            }

          default:
            break;
        }
      }
      sb.write(')');
    }
    sb.writeln();

    for (final comment in extraComments) {
      sb.writeln(comment);
    }
  }

  void _formatSaid(
    SaidInstruction said,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    final addr = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.write('$addr: ${indent}said(');

    final extraComments = <String>[];
    final extraIndent = indent.isEmpty ? '' : ' ' * indent.length;

    for (var i = 0; i < said.wordGroupIds.length; i++) {
      if (i > 0) sb.write(', ');
      final wordId = said.wordGroupIds[i];
      sb.write('%w$wordId');

      if (c.dictionary != null) {
        final words = c.dictionary!.idToWords(wordId);
        if (words.isNotEmpty) {
          final wordList = words.map((w) => '<$w>').join(' ');
          extraComments.add('      $extraIndent[ WORD %w$wordId: $wordList');
        }
      }
    }
    sb.writeln(')');

    for (final comment in extraComments) {
      sb.writeln(comment);
    }
  }

  void _formatIf(
    IfInstruction ifIns,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$addr: ${indent}IF-AND (');

    cur += 1; // 0xFF
    final childIndent = '$indent    ';
    formatInstruction(ifIns.condition, sb, cur, childIndent, c);
    cur += ifIns.condition.length;

    final closeAddr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$closeAddr: $indent) {');
    cur += 3; // closing 0xFF + 2 bytes jump length

    formatInstruction(ifIns.thenBlock, sb, cur, childIndent, c);
    cur += ifIns.thenBlock.length;

    if (ifIns.elseBlock != null) {
      final elseAddr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
      sb.writeln('$elseAddr: $indent} else {');
      cur += 3; // 0xFE + 2 bytes jump length
      formatInstruction(ifIns.elseBlock!, sb, cur, childIndent, c);
      sb.writeln('      $indent}');
    } else {
      sb.writeln('      $indent}');
    }
  }

  void _formatUnless(
    UnlessGotoInstruction unlessIns,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$addr: ${indent}UNLESS (');

    cur += 1;
    final childIndent = '$indent    ';
    formatInstruction(unlessIns.condition, sb, cur, childIndent, c);
    cur += unlessIns.condition.length;

    final targetHex = unlessIns.targetAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    final jumpAddr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$jumpAddr: $indent) GOTO(0x$targetHex)');
  }

  void _formatGoto(
    GotoInstruction gotoIns,
    StringBuffer sb,
    int baseAddress,
    String indent,
  ) {
    final addr = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    final targetHex = gotoIns.targetAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$addr: ${indent}GOTO(0x$targetHex)');
  }

  void _formatOr(
    OrInstruction orIns,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$addr: ${indent}OR (');

    cur += 1; // 0xFC
    formatInstruction(orIns.condition, sb, cur, '$indent    ', c);
    cur += orIns.condition.length;

    final closeAddr = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    sb.writeln('$closeAddr: $indent)');
  }

  void _formatNot(
    NotInstruction notIns,
    StringBuffer sb,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    formatInstruction(notIns.inner, sb, baseAddress + 1, '${indent}NOT ', c);
  }
}
