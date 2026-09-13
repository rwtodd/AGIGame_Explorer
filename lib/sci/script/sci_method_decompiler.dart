// High-level Sierra Script Language (.SC style) method and bytecode decompiler for SCI0.

import 'dart:math';
import 'package:flutter_agigame/sci/engine/sci_opcodes.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

// ============================================================================
// AST / Expression Model
// ============================================================================

/// Base interface for all decompiled expressions.
abstract class SciExpr {
  const SciExpr();

  /// Formats this expression as Sierra Script (.SC Lisp-style) code.
  String format();

  @override
  String toString() => format();
}

/// A literal number, hex value, or boolean.
class SciLiteralExpr extends SciExpr {
  final int value;
  final String? nameHint;

  const SciLiteralExpr(this.value, [this.nameHint]);

  @override
  String format() {
    if (nameHint != null) return nameHint!;
    if (value >= 0 && value <= 9) return '$value';
    if (value < 0 && value >= -9) return '$value';
    if (value == 0) return '0';
    if (value == 1) return '1';
    if (value > 9999 || value < -9999) {
      return '0x${value.toRadixString(16)}';
    }
    return '$value';
  }
}

/// A string literal.
class SciStringExpr extends SciExpr {
  final String text;

  const SciStringExpr(this.text);

  @override
  String format() {
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }
}

/// A parsed Said specification expression, e.g. `'look/door'`.
class SciSaidExpr extends SciExpr {
  final String saidPattern;
  final int offset;

  const SciSaidExpr(this.saidPattern, [this.offset = 0]);

  @override
  String format() => "'$saidPattern'";
}

/// A variable reference (global, local, temp, or param).
class SciVarExpr extends SciExpr {
  final SciVarType type;
  final int index;
  final String? customName;

  const SciVarExpr(this.type, this.index, [this.customName]);

  @override
  String format() {
    if (customName != null) return customName!;
    switch (type) {
      case SciVarType.global:
        return 'g$index';
      case SciVarType.local:
        return 'local$index';
      case SciVarType.temp:
        return 'temp$index';
      case SciVarType.param:
        return 'param$index';
    }
  }
}

/// An indexed variable access, e.g. `[varName + offset]`.
class SciIndexedVarExpr extends SciExpr {
  final SciVarType type;
  final int baseIndex;
  final SciExpr offsetExpr;

  const SciIndexedVarExpr(this.type, this.baseIndex, this.offsetExpr);

  @override
  String format() {
    final varName = SciVarExpr(type, baseIndex).format();
    return '[$varName + ${offsetExpr.format()}]';
  }
}

/// Property access on the current object (`pToa`/`pTos`).
class SciPropExpr extends SciExpr {
  final String propName;

  const SciPropExpr(this.propName);

  @override
  String format() => propName;
}

/// Address-of variable expression (`lea`), e.g. `@string`.
class SciLeaExpr extends SciExpr {
  final SciExpr target;

  const SciLeaExpr(this.target);

  @override
  String format() => '@${target.format()}';
}

/// Self reference (`self`).
class SciSelfExpr extends SciExpr {
  const SciSelfExpr();

  @override
  String format() => 'self';
}

/// Super reference (`super`).
class SciSuperExpr extends SciExpr {
  final String? superClassName;

  const SciSuperExpr([this.superClassName]);

  @override
  String format() => superClassName != null ? 'super' : 'super';
}

/// Class reference.
class SciClassExpr extends SciExpr {
  final String className;

  const SciClassExpr(this.className);

  @override
  String format() => className;
}

/// Object reference (e.g. `ego`, `theSound`).
class SciObjectExpr extends SciExpr {
  final String objectName;

  const SciObjectExpr(this.objectName);

  @override
  String format() => objectName;
}

/// Unary operations: `(not expr)`, `(- expr)`, `(~ expr)`.
class SciUnaryExpr extends SciExpr {
  final String op;
  final SciExpr operand;

  const SciUnaryExpr(this.op, this.operand);

  @override
  String format() => '($op ${operand.format()})';
}

/// Binary operations: `(+ a b)`, `(- a b)`, `(== a b)`, etc.
class SciBinaryExpr extends SciExpr {
  final String op;
  final SciExpr left;
  final SciExpr right;

  const SciBinaryExpr(this.op, this.left, this.right);

  @override
  String format() => '($op ${left.format()} ${right.format()})';
}

/// Increment / Decrement expressions: `(++ var)` or `(-- var)`.
class SciIncDecExpr extends SciExpr {
  final String op;
  final SciExpr target;

  const SciIncDecExpr(this.op, this.target);

  @override
  String format() => '($op ${target.format()})';
}

/// Kernel call expression: `(KernelName arg0 arg1 ...)`.
class SciKernelCallExpr extends SciExpr {
  final String kernelName;
  final List<SciExpr> args;

  const SciKernelCallExpr(this.kernelName, this.args);

  @override
  String format() {
    if (args.isEmpty) return '($kernelName)';
    final argsStr = args.map((a) => a.format()).join(' ');
    return '($kernelName $argsStr)';
  }
}

/// Procedure call expression: `(procName arg0 arg1 ...)`.
class SciCallExpr extends SciExpr {
  final String procName;
  final List<SciExpr> args;

  const SciCallExpr(this.procName, this.args);

  @override
  String format() {
    if (args.isEmpty) return '($procName)';
    final argsStr = args.map((a) => a.format()).join(' ');
    return '($procName $argsStr)';
  }
}

/// A message inside a send packet (e.g. `setMotion: MoveTo 100 150` or `init:`).
class SciSendMessage {
  final String selector;
  final List<SciExpr> args;
  final bool isPropertyGet;

  const SciSendMessage({
    required this.selector,
    this.args = const [],
    this.isPropertyGet = false,
  });

  String format() {
    if (isPropertyGet) {
      return '$selector?';
    }
    if (args.isEmpty) {
      return '$selector:';
    }
    final argsStr = args.map((a) => a.format()).join(' ');
    return '$selector: $argsStr';
  }
}

/// Send / Method call expression: `(receiver sel1: arg1 sel2: arg2)`.
class SciSendExpr extends SciExpr {
  final SciExpr target;
  final List<SciSendMessage> messages;

  const SciSendExpr(this.target, this.messages);

  @override
  String format() {
    final targetStr = target.format();
    if (messages.isEmpty) return '($targetStr)';
    if (messages.length == 1) {
      return '($targetStr ${messages.first.format()})';
    }
    final sb = StringBuffer('($targetStr\n');
    for (final m in messages) {
      sb.writeln('    ${m.format()}');
    }
    sb.write('  )');
    return sb.toString();
  }
}

/// Assignment expression: `(= target value)`.
class SciAssignExpr extends SciExpr {
  final SciExpr target;
  final SciExpr value;

  const SciAssignExpr(this.target, this.value);

  @override
  String format() => '(= ${target.format()} ${value.format()})';
}

/// Raw opcode fallback for unhandled or exotic instructions.
class SciRawInstrExpr extends SciExpr {
  final String mnemonic;
  final List<String> operands;

  const SciRawInstrExpr(this.mnemonic, this.operands);

  @override
  String format() =>
      operands.isEmpty ? '[$mnemonic]' : '[$mnemonic ${operands.join(", ")}]';
}

// ============================================================================
// Statements Model
// ============================================================================

/// Base interface for decompiled statements.
abstract class SciStatement {
  const SciStatement();

  void emit(StringBuffer sb, String indent);
}

/// Standalone expression statement, e.g. `(theSound play:)` or `(= x 5)`.
class SciExprStatement extends SciStatement {
  final SciExpr expr;

  const SciExprStatement(this.expr);

  @override
  void emit(StringBuffer sb, String indent) {
    sb.writeln('$indent${expr.format()}');
  }
}

/// Return statement: `(return)` or `(return expr)`.
class SciReturnStatement extends SciStatement {
  final SciExpr? value;

  const SciReturnStatement([this.value]);

  @override
  void emit(StringBuffer sb, String indent) {
    if (value == null || (value is SciLiteralExpr && (value as SciLiteralExpr).value == 0)) {
      sb.writeln('$indent(return)');
    } else {
      sb.writeln('$indent(return ${value!.format()})');
    }
  }
}

/// If / If-Else conditional statement.
class SciIfStatement extends SciStatement {
  final SciExpr condition;
  final List<SciStatement> thenBody;
  final List<SciStatement>? elseBody;

  const SciIfStatement({
    required this.condition,
    required this.thenBody,
    this.elseBody,
  });

  @override
  void emit(StringBuffer sb, String indent) {
    sb.writeln('$indent(if ${condition.format()}');
    for (final stmt in thenBody) {
      stmt.emit(sb, '$indent  ');
    }
    if (elseBody != null && elseBody!.isNotEmpty) {
      sb.writeln('$indent) else (');
      for (final stmt in elseBody!) {
        stmt.emit(sb, '$indent  ');
      }
    }
    sb.writeln('$indent)');
  }
}

/// While loop statement.
class SciWhileStatement extends SciStatement {
  final SciExpr condition;
  final List<SciStatement> body;

  const SciWhileStatement({
    required this.condition,
    required this.body,
  });

  @override
  void emit(StringBuffer sb, String indent) {
    sb.writeln('$indent(while ${condition.format()}');
    for (final stmt in body) {
      stmt.emit(sb, '$indent  ');
    }
    sb.writeln('$indent)');
  }
}

/// Branch / Goto statement: `(goto label)` or `(if condition (goto label))`.
class SciGotoStatement extends SciStatement {
  final String label;
  final SciExpr? condition;

  const SciGotoStatement(this.label, [this.condition]);

  @override
  void emit(StringBuffer sb, String indent) {
    if (condition != null) {
      sb.writeln('$indent(if ${condition!.format()} (goto $label))');
    } else {
      sb.writeln('$indent(goto $label)');
    }
  }
}

/// Label declaration, e.g. `code_01a4:`.
class SciLabelStatement extends SciStatement {
  final String label;

  const SciLabelStatement(this.label);

  @override
  void emit(StringBuffer sb, String indent) {
    sb.writeln('$indent$label:');
  }
}

// ============================================================================
// Decompiler Implementation
// ============================================================================

/// Decoded bytecode instruction with script offset.
class _DecodedInstr {
  final int offset;
  final SciInstruction instr;

  const _DecodedInstr(this.offset, this.instr);

  int get opcode => instr.opcode;
  List<int> get operands => instr.operands;
  int get length => instr.length;
}

/// Decompiles bytecode sequences into Sierra Script Language (.SC) AST & formatting.
class SciMethodDecompiler {
  final SciDisassemblyContext context;
  final SciObject? currentObject;
  final String? methodName;

  SciMethodDecompiler(
    this.context, {
    this.currentObject,
    this.methodName,
  });

  /// Decompiles the code sequence starting at [startPc] into a formatted string.
  String decompile({
    required int startPc,
    String indent = '  ',
    int maxInstructions = 2500,
  }) {
    final instructions = _decodeSequence(startPc, maxInstructions);
    if (instructions.isEmpty) {
      return '$indent(return)\n';
    }

    final statements = _decompileInstructions(instructions, startPc);

    final sb = StringBuffer();
    for (final stmt in statements) {
      stmt.emit(sb, indent);
    }
    return sb.toString();
  }

  /// Builds a high-level method signature, detecting temp and parameter counts.
  /// E.g.: `(method (handleEvent event &tmp temp0 temp1)  ; at 0x060c`
  String buildMethodHeader({
    required int selectorId,
    required int methodOffset,
    String indent = '  ',
  }) {
    final selName = context.resolveSelectorName(selectorId);
    final instructions = _decodeSequence(methodOffset, 200);

    // 1. Detect temporary variables from initial `link N`
    var tempCount = 0;
    if (instructions.isNotEmpty && instructions.first.opcode == 0x1F) {
      tempCount = instructions.first.operands.isNotEmpty
          ? instructions.first.operands[0]
          : 0;
    }

    // 2. Detect max accessed parameter index (param1, param2, ...)
    var maxParam = 0;
    for (final di in instructions) {
      // lap (0x43) or lsp (0x47)
      if ((di.opcode == 0x43 || di.opcode == 0x47) && di.operands.isNotEmpty) {
        final pIdx = di.operands[0];
        if (pIdx > maxParam) maxParam = pIdx;
      }
    }

    // 3. Build parameter names list
    final params = <String>[];
    for (var i = 1; i <= maxParam; i++) {
      params.add(_suggestParamName(selName, i, maxParam));
    }

    final paramStr = params.isNotEmpty ? ' ${params.join(" ")}' : '';

    // 4. Build temp variables string
    String tempStr = '';
    if (tempCount > 0) {
      if (tempCount <= 6) {
        final tList = List.generate(tempCount, (i) => 'temp$i').join(' ');
        tempStr = ' &tmp $tList';
      } else {
        tempStr = ' &tmp temp0 temp1 [temp2 $tempCount]';
      }
    }

    return '$indent(method ($selName$paramStr$tempStr)  ; at 0x${methodOffset.toRadixString(16)}';
  }

  /// Builds a high-level procedure signature.
  /// E.g.: `(procedure (export_0 param1 &tmp temp0)  ; at 0x01a4`
  String buildProcedureHeader({
    required String procName,
    required int procOffset,
    String indent = '',
  }) {
    final instructions = _decodeSequence(procOffset, 200);

    var tempCount = 0;
    if (instructions.isNotEmpty && instructions.first.opcode == 0x1F) {
      tempCount = instructions.first.operands.isNotEmpty
          ? instructions.first.operands[0]
          : 0;
    }

    var maxParam = 0;
    for (final di in instructions) {
      if ((di.opcode == 0x43 || di.opcode == 0x47) && di.operands.isNotEmpty) {
        final pIdx = di.operands[0];
        if (pIdx > maxParam) maxParam = pIdx;
      }
    }

    final params = <String>[];
    for (var i = 1; i <= maxParam; i++) {
      params.add('param$i');
    }

    final paramStr = params.isNotEmpty ? ' ${params.join(" ")}' : '';
    String tempStr = '';
    if (tempCount > 0) {
      if (tempCount <= 6) {
        final tList = List.generate(tempCount, (i) => 'temp$i').join(' ');
        tempStr = ' &tmp $tList';
      } else {
        tempStr = ' &tmp temp0 temp1 [temp2 $tempCount]';
      }
    }

    return '$indent(procedure ($procName$paramStr$tempStr)  ; at 0x${procOffset.toRadixString(16)}';
  }

  String _suggestParamName(String selName, int index, int totalParams) {
    if (selName == 'handleEvent' && index == 1) return 'event';
    if (selName == 'changeState' && index == 1) return 'newState';
    if (selName == 'cue' && index == 1) return 'param1';
    if (selName == 'saidMe' && index == 1) return 'event';
    if (selName == 'doit' && index == 1) return 'whom';
    if (selName == 'ownedBy' && index == 1) return 'whom';
    if (selName == 'setMotion' && index == 1) return 'theMover';
    return 'param$index';
  }

  /// Decodes raw bytecode instructions for a method or procedure.
  List<_DecodedInstr> _decodeSequence(int startPc, int maxInstructions) {
    final list = <_DecodedInstr>[];
    final bytes = context.script.bytes;
    if (startPc < 0 || startPc >= bytes.length) return list;

    var pc = startPc;
    var maxBranchTarget = startPc;
    var count = 0;

    while (pc < bytes.length && count++ < maxInstructions) {
      final instrOffset = pc;
      final instr = decodeInstruction(bytes, pc);
      list.add(_DecodedInstr(instrOffset, instr));

      // Track branch targets
      if (instr.opcode == 0x17 || instr.opcode == 0x18 || instr.opcode == 0x19) {
        if (instr.operands.isNotEmpty) {
          final rel = instr.operands[0];
          final target = instrOffset + instr.length + rel;
          if (target > maxBranchTarget) {
            maxBranchTarget = target;
          }
        }
      }

      pc += instr.length;

      // Stop condition: ret encountered and no forward branches point to or past it
      if (instr.opcode == 0x24) {
        if (pc > maxBranchTarget) {
          break;
        }
      }
    }

    return list;
  }

  /// Decompiles decoded instructions into statements, reconstructing control flow.
  List<SciStatement> _decompileInstructions(
    List<_DecodedInstr> instructions,
    int startPc,
  ) {
    // Map addresses to instruction index
    final offsetToIndex = <int, int>{};
    for (var i = 0; i < instructions.length; i++) {
      offsetToIndex[instructions[i].offset] = i;
    }

    // Collect all branch targets to identify labels
    final branchTargets = <int>{};
    for (final di in instructions) {
      if (di.opcode == 0x17 || di.opcode == 0x18 || di.opcode == 0x19) {
        if (di.operands.isNotEmpty) {
          final target = di.offset + di.length + di.operands[0];
          if (offsetToIndex.containsKey(target)) {
            branchTargets.add(target);
          }
        }
      }
    }

    return _decompileRange(
      instructions,
      0,
      instructions.length,
      offsetToIndex,
      branchTargets,
      const {},
    );
  }

  /// Decompiles an instruction slice [startIdx, endIdx), reconstructing structured
  /// control flow (if, if-else, while) or falling back to labeled gotos.
  List<SciStatement> _decompileRange(
    List<_DecodedInstr> instructions,
    int startIdx,
    int endIdx,
    Map<int, int> offsetToIndex,
    Set<int> branchTargets,
    Set<int> structuredTargets,
  ) {
    final statements = <SciStatement>[];
    final stack = <SciExpr>[];
    SciExpr? acc;
    SciExpr? prev;

    var i = startIdx;

    while (i < endIdx) {
      final di = instructions[i];
      final currentOffset = di.offset;

      // Check if currentOffset is an unstructured branch target label
      if (branchTargets.contains(currentOffset) &&
          !structuredTargets.contains(currentOffset)) {
        // Commit any pending expression before starting new block
        _commitPendingAcc(acc, statements);
        acc = null;
        statements.add(SciLabelStatement('code_0x${currentOffset.toRadixString(16)}'));
      }

      // 1. Skip initial `link`
      if (di.opcode == 0x1F && i == 0) {
        i++;
        continue;
      }

      // 2. Check for while loop: backward jump at the end of loop pointing back to this offset
      final loopInfo = _detectWhileLoop(instructions, i, endIdx, offsetToIndex);
      if (loopInfo != null) {
        _commitPendingAcc(acc, statements);
        acc = null;

        // Decompile condition
        final condSlice = _decompileLinearSlice(
          instructions,
          loopInfo.condStart,
          loopInfo.condEnd,
        );

        final loopCond = condSlice.acc ?? const SciLiteralExpr(1);

        // Decompile body
        final loopStructuredTargets = Set<int>.from(structuredTargets)
          ..add(loopInfo.loopStartOffset)
          ..add(loopInfo.exitOffset);

        final bodyStatements = _decompileRange(
          instructions,
          loopInfo.bodyStart,
          loopInfo.bodyEnd,
          offsetToIndex,
          branchTargets,
          loopStructuredTargets,
        );

        statements.add(SciWhileStatement(condition: loopCond, body: bodyStatements));
        i = loopInfo.nextIndex;
        continue;
      }

      // 3. Check for conditional branch: bnt (0x18) or bt (0x17)
      if (di.opcode == 0x18 || di.opcode == 0x17) {
        final isBnt = di.opcode == 0x18;
        final rel = di.operands[0];
        final targetOffset = di.offset + di.length + rel;
        final targetIdx = offsetToIndex[targetOffset];

        final condition = acc ?? const SciLiteralExpr(1);
        final effectiveCond = isBnt ? condition : SciUnaryExpr('not', condition);
        acc = null;

        if (targetIdx != null && targetIdx > i && targetIdx <= endIdx) {
          // Check if this is an if-else: instruction just before targetIdx is unconditional jmp forward
          final elseCandidateIdx = targetIdx - 1;
          final isIfElse = elseCandidateIdx > i &&
              instructions[elseCandidateIdx].opcode == 0x19 &&
              instructions[elseCandidateIdx].operands.isNotEmpty;

          if (isIfElse) {
            final jmpRel = instructions[elseCandidateIdx].operands[0];
            final elseExitOffset = instructions[elseCandidateIdx].offset +
                instructions[elseCandidateIdx].length +
                jmpRel;
            final elseExitIdx = offsetToIndex[elseExitOffset];

            if (elseExitIdx != null && elseExitIdx > targetIdx && elseExitIdx <= endIdx) {
              // Structured if-else!
              final updatedTargets = Set<int>.from(structuredTargets)
                ..add(targetOffset)
                ..add(elseExitOffset);

              final thenBody = _decompileRange(
                instructions,
                i + 1,
                elseCandidateIdx,
                offsetToIndex,
                branchTargets,
                updatedTargets,
              );

              final elseBody = _decompileRange(
                instructions,
                targetIdx,
                elseExitIdx,
                offsetToIndex,
                branchTargets,
                updatedTargets,
              );

              statements.add(
                SciIfStatement(
                  condition: effectiveCond,
                  thenBody: thenBody,
                  elseBody: elseBody,
                ),
              );

              i = elseExitIdx;
              continue;
            }
          }

          // Simple structured if (no else)
          final updatedTargets = Set<int>.from(structuredTargets)..add(targetOffset);
          final thenBody = _decompileRange(
            instructions,
            i + 1,
            targetIdx,
            offsetToIndex,
            branchTargets,
            updatedTargets,
          );

          statements.add(
            SciIfStatement(
              condition: effectiveCond,
              thenBody: thenBody,
            ),
          );

          i = targetIdx;
          continue;
        } else {
          // Irregular branch / goto
          statements.add(
            SciGotoStatement('code_0x${targetOffset.toRadixString(16)}', effectiveCond),
          );
          i++;
          continue;
        }
      }

      // 4. Unconditional jump (0x19)
      if (di.opcode == 0x19) {
        final rel = di.operands[0];
        final targetOffset = di.offset + di.length + rel;
        _commitPendingAcc(acc, statements);
        acc = null;
        statements.add(
          SciGotoStatement('code_0x${targetOffset.toRadixString(16)}'),
        );
        i++;
        continue;
      }

      // 5. Ret (0x24)
      if (di.opcode == 0x24) {
        if (acc != null && !_isStatementExpr(acc)) {
          statements.add(SciReturnStatement(acc));
          acc = null;
        } else {
          _commitPendingAcc(acc, statements);
          acc = null;
          if (i < instructions.length - 1) {
            statements.add(const SciReturnStatement());
          }
        }
        i++;
        continue;
      }

      // 6. Regular linear instruction execution: update stack, acc, prev, statements
      final nextInstr = (i + 1 < instructions.length) ? instructions[i + 1] : null;
      final step = _executeLinearStep(di, stack, acc, prev, nextInstr);
      acc = step.acc;
      prev = step.prev;

      if (step.emittedStatement != null) {
        statements.add(step.emittedStatement!);
      }

      i++;
    }

    _commitPendingAcc(acc, statements);
    return statements;
  }

  void _commitPendingAcc(SciExpr? acc, List<SciStatement> statements) {
    if (acc != null && _isSideEffectExpr(acc)) {
      statements.add(SciExprStatement(acc));
    }
  }

  bool _isStatementExpr(SciExpr expr) =>
      expr is SciAssignExpr || expr is SciSendExpr || expr is SciKernelCallExpr;

  bool _isSideEffectExpr(SciExpr expr) =>
      expr is SciSendExpr ||
      expr is SciKernelCallExpr ||
      expr is SciCallExpr ||
      expr is SciIncDecExpr;

  _LinearStepResult _executeLinearStep(
    _DecodedInstr di,
    List<SciExpr> stack,
    SciExpr? acc,
    SciExpr? prev,
    _DecodedInstr? nextInstr,
  ) {
    SciStatement? emitted;
    final opcode = di.opcode;
    final operands = di.operands;

    if (acc != null && _isSideEffectExpr(acc) && !_isAccConsumerOpcode(opcode)) {
      emitted = SciExprStatement(acc);
      acc = null;
    }

    switch (opcode) {
      // --- Arithmetic & Bitwise Ops (pop() op acc) ---
      case 0x00: // bnot
        acc = SciUnaryExpr('~', acc ?? const SciLiteralExpr(0));
        break;
      case 0x01: // add
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('+', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x02: // sub
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('-', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x03: // mul
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('*', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x04: // div
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('/', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x05: // mod
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('mod', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x06: // shr
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('>>', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x07: // shl
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('<<', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x08: // xor
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('^', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x09: // and
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('&', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x0A: // or
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        acc = SciBinaryExpr('|', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x0B: // neg
        acc = SciUnaryExpr('-', acc ?? const SciLiteralExpr(0));
        break;
      case 0x0C: // not
        acc = SciUnaryExpr('not', acc ?? const SciLiteralExpr(0));
        break;
      case 0x0D: // eq?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('==', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x0E: // ne?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('!=', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x0F: // gt?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('>', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x10: // ge?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('>=', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x11: // lt?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('<', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x12: // le?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        acc = SciBinaryExpr('<=', left, acc ?? const SciLiteralExpr(0));
        break;
      case 0x13: // ugt?
      case 0x14: // uge?
      case 0x15: // ult?
      case 0x16: // ule?
        final left = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        prev = acc;
        final opName = opcode == 0x13 ? 'u>' : (opcode == 0x14 ? 'u>=' : (opcode == 0x15 ? 'u<' : 'u<='));
        acc = SciBinaryExpr(opName, left, acc ?? const SciLiteralExpr(0));
        break;

      // --- Immediates & Stack Manipulation ---
      case 0x1A: // ldi
        acc = SciLiteralExpr(operands.isNotEmpty ? operands[0] : 0);
        break;
      case 0x1B: // push
        stack.add(acc ?? const SciLiteralExpr(0));
        acc = null;
        break;
      case 0x1C: // pushi
        final val = operands.isNotEmpty ? operands[0] : 0;
        stack.add(SciLiteralExpr(val));
        break;
      case 0x1D: // toss
        if (stack.isNotEmpty) stack.removeLast();
        break;
      case 0x1E: // dup
        stack.add(stack.isNotEmpty ? stack.last : const SciLiteralExpr(0));
        break;

      // --- Invocations: call, callk, callb, calle ---
      case 0x20: // call (local procedure)
        final rel = operands.isNotEmpty ? operands[0] : 0;
        final callkArgc = operands.length > 1 ? (operands[1] >> 1) : 0;
        final targetOffset = di.offset + di.length + rel;
        final args = _popArgsFromStack(stack, callkArgc);
        final procName = _resolveProcName(targetOffset);
        acc = SciCallExpr(procName, args);
        break;

      case 0x21: // callk (kernel call)
        final kernelNr = operands.isNotEmpty ? operands[0] : 0;
        final callkArgc = operands.length > 1 ? (operands[1] >> 1) : 0;
        final args = _popArgsFromStack(stack, callkArgc);
        final kName = context.resolveKernelName(kernelNr);
        acc = SciKernelCallExpr(kName, args);
        break;

      case 0x22: // callb (base script 0 export)
        final exportNr = operands.isNotEmpty ? operands[0] : 0;
        final callkArgc = operands.length > 1 ? (operands[1] >> 1) : 0;
        final args = _popArgsFromStack(stack, callkArgc);
        acc = SciCallExpr('proc0_$exportNr', args);
        break;

      case 0x23: // calle (external script export)
        final scriptNr = operands.isNotEmpty ? operands[0] : 0;
        final exportNr = operands.length > 1 ? operands[1] : 0;
        final callkArgc = operands.length > 2 ? (operands[2] >> 1) : 0;
        final args = _popArgsFromStack(stack, callkArgc);
        acc = SciCallExpr('(ScriptID $scriptNr $exportNr)', args);
        break;

      // --- Sends: send, self, super ---
      case 0x25: // send
        final sendByteCount = operands.isNotEmpty ? operands[0] : 0;
        final target = acc ?? const SciSelfExpr();
        final messages = _decodeSendMessages(stack, sendByteCount >> 1);
        acc = SciSendExpr(target, messages);
        break;

      case 0x28: // class
        final classNr = operands.isNotEmpty ? operands[0] : 0;
        acc = SciClassExpr(context.resolveClassName(classNr));
        break;

      case 0x2A: // self
        final sendByteCount = operands.isNotEmpty ? operands[0] : 0;
        final messages = _decodeSendMessages(stack, sendByteCount >> 1);
        acc = SciSendExpr(const SciSelfExpr(), messages);
        break;

      case 0x2B: // super
        final classNr = operands.isNotEmpty ? operands[0] : 0;
        final sendByteCount = operands.length > 1 ? operands[1] : 0;
        final superName = context.resolveClassName(classNr);
        final messages = _decodeSendMessages(stack, sendByteCount >> 1);
        acc = SciSendExpr(SciSuperExpr(superName), messages);
        break;

      case 0x2C: // &rest
        final firstArg = operands.isNotEmpty ? operands[0] : 1;
        stack.add(SciLiteralExpr(firstArg, '(&rest $firstArg)'));
        break;

      case 0x2D: // lea (address of)
        final leaType = operands.isNotEmpty ? ((operands[0] >> 1) & 0x03) : 0;
        final varIdx = operands.length > 1 ? operands[1] : 0;
        acc = SciLeaExpr(SciVarExpr(SciVarType.fromId(leaType), varIdx));
        break;

      case 0x2E: // selfID
        acc = const SciSelfExpr();
        break;

      case 0x30: // pprev
        stack.add(prev ?? const SciLiteralExpr(0));
        break;

      // --- Object Properties (pToa, aTop, pTos, sTop, ipToa, ...) ---
      case 0x31: // pToa
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        acc = SciPropExpr(_resolvePropName(propIdx));
        break;

      case 0x32: // aTop
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        final targetProp = SciPropExpr(_resolvePropName(propIdx));
        final val = acc ?? const SciLiteralExpr(0);
        emitted = SciExprStatement(SciAssignExpr(targetProp, val));
        acc = SciAssignExpr(targetProp, val);
        break;

      case 0x33: // pTos
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        stack.add(SciPropExpr(_resolvePropName(propIdx)));
        break;

      case 0x34: // sTop
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        final targetProp = SciPropExpr(_resolvePropName(propIdx));
        final val = stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0);
        emitted = SciExprStatement(SciAssignExpr(targetProp, val));
        break;

      case 0x35: // ipToa (++prop -> acc)
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        acc = SciIncDecExpr('++', SciPropExpr(_resolvePropName(propIdx)));
        break;

      case 0x36: // dpToa (--prop -> acc)
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        acc = SciIncDecExpr('--', SciPropExpr(_resolvePropName(propIdx)));
        break;

      case 0x37: // ipTos (++prop -> stack)
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        stack.add(SciIncDecExpr('++', SciPropExpr(_resolvePropName(propIdx))));
        break;

      case 0x38: // dpTos (--prop -> stack)
        final propIdx = operands.isNotEmpty ? (operands[0] >> 1) : 0;
        stack.add(SciIncDecExpr('--', SciPropExpr(_resolvePropName(propIdx))));
        break;

      // --- Literal Offsets / Constants ---
      case 0x39: // lofsa (load offset to acc)
        final rel = operands.isNotEmpty ? operands[0] : 0;
        final target = di.offset + di.length + rel;
        acc = _resolveOffsetExpr(target);
        break;

      case 0x3A: // lofss (load offset to stack)
        final rel = operands.isNotEmpty ? operands[0] : 0;
        final target = di.offset + di.length + rel;
        stack.add(_resolveOffsetExpr(target));
        break;

      case 0x3B: // push0
        stack.add(const SciLiteralExpr(0));
        break;
      case 0x3C: // push1
        stack.add(const SciLiteralExpr(1));
        break;
      case 0x3D: // push2
        stack.add(const SciLiteralExpr(2));
        break;
      case 0x3E: // pushSelf
        stack.add(const SciSelfExpr());
        break;
      case 0x3F: // line (debug)
        break;

      // --- Variables Grid (0x40 - 0x7F) ---
      default:
        if (opcode >= 0x40 && opcode <= 0x7F) {
          final varType = SciVarType.fromId(opcode & 0x03);
          final isStack = (opcode & 0x04) != 0;
          final isIndexed = (opcode & 0x08) != 0;
          final varIdx = operands.isNotEmpty ? operands[0] : 0;

          // 0x40-0x4F: Load
          if (opcode <= 0x4F) {
            final expr = isIndexed
                ? SciIndexedVarExpr(varType, varIdx, acc ?? const SciLiteralExpr(0))
                : SciVarExpr(varType, varIdx);
            if (isStack) {
              stack.add(expr);
            } else {
              acc = expr;
            }
          }
          // 0x50-0x5F: Store
          else if (opcode <= 0x5F) {
            final targetVar = isIndexed
                ? SciIndexedVarExpr(varType, varIdx, acc ?? const SciLiteralExpr(0))
                : SciVarExpr(varType, varIdx);
            final val = isStack
                ? (stack.isNotEmpty ? stack.removeLast() : const SciLiteralExpr(0))
                : (acc ?? const SciLiteralExpr(0));
            emitted = SciExprStatement(SciAssignExpr(targetVar, val));
            if (!isStack) {
              acc = SciAssignExpr(targetVar, val);
            }
          }
          // 0x60-0x6F: Increment (+)
          else if (opcode <= 0x6F) {
            final targetVar = isIndexed
                ? SciIndexedVarExpr(varType, varIdx, acc ?? const SciLiteralExpr(0))
                : SciVarExpr(varType, varIdx);
            final incExpr = SciIncDecExpr('++', targetVar);
            if (isStack) {
              stack.add(incExpr);
            } else {
              acc = incExpr;
            }
          }
          // 0x70-0x7F: Decrement (-)
          else {
            final targetVar = isIndexed
                ? SciIndexedVarExpr(varType, varIdx, acc ?? const SciLiteralExpr(0))
                : SciVarExpr(varType, varIdx);
            final decExpr = SciIncDecExpr('--', targetVar);
            if (isStack) {
              stack.add(decExpr);
            } else {
              acc = decExpr;
            }
          }
        } else {
          acc = SciRawInstrExpr(di.instr.name, di.operands.map((o) => '$o').toList());
        }
        break;
    }

    return _LinearStepResult(
      acc: acc,
      prev: prev,
      emittedStatement: emitted,
    );
  }

  bool _isAccConsumerOpcode(int opcode) {
    if (opcode == 0x1B) return true; // push
    if (opcode == 0x24) return true; // ret
    if (opcode == 0x17 || opcode == 0x18) return true; // bt, bnt
    if (opcode >= 0x50 && opcode <= 0x53) return true; // sag, sal, sat, sap
    if (opcode == 0x32) return true; // aTop
    if (opcode <= 0x16) return true; // binary / unary math
    if (opcode == 0x25) return true; // send
    return false;
  }

  List<SciExpr> _popArgsFromStack(List<SciExpr> stack, int count) {
    final args = <SciExpr>[];
    for (var i = 0; i < count; i++) {
      if (stack.isNotEmpty) {
        args.insert(0, stack.removeLast());
      } else {
        args.insert(0, const SciLiteralExpr(0));
      }
    }
    if (stack.isNotEmpty) {
      stack.removeLast();
    }
    return args;
  }

  List<SciSendMessage> _decodeSendMessages(List<SciExpr> stack, int wordCount) {
    final messages = <SciSendMessage>[];
    final packet = <SciExpr>[];

    final takeCount = min(wordCount, stack.length);
    for (var i = 0; i < takeCount; i++) {
      packet.insert(0, stack.removeLast());
    }

    var idx = 0;
    while (idx < packet.length) {
      final selExpr = packet[idx++];
      int selId = 0;
      if (selExpr is SciLiteralExpr) {
        selId = selExpr.value;
      }

      final selName = context.resolveSelectorName(selId);

      var numArgs = 0;
      if (idx < packet.length) {
        final argCountExpr = packet[idx++];
        if (argCountExpr is SciLiteralExpr) {
          numArgs = argCountExpr.value;
        }
      }

      final msgArgs = <SciExpr>[];
      for (var a = 0; a < numArgs && idx < packet.length; a++) {
        msgArgs.add(packet[idx++]);
      }

      final isProperty = _isStandardPropertyName(selName);
      messages.add(
        SciSendMessage(
          selector: selName,
          args: msgArgs,
          isPropertyGet: isProperty && numArgs == 0,
        ),
      );
    }

    return messages;
  }

  SciExpr _resolveOffsetExpr(int offset) {
    final objName = context.resolveObjectName(offset);
    if (objName != null) {
      return SciObjectExpr(objName);
    }
    if (context.isSaidOffset(offset)) {
      final saidPattern = context.resolveSaidString(offset) ?? 'said_0x${offset.toRadixString(16)}';
      return SciSaidExpr(saidPattern, offset);
    }
    final str = context.resolveString(offset);
    if (str != null && str.isNotEmpty) {
      return SciStringExpr(str);
    }
    return SciLiteralExpr(offset);
  }

  String _resolveProcName(int offset) {
    final expIdx = context.script.exports.indexOf(offset);
    if (expIdx >= 0) return 'export_$expIdx';
    return 'proc_0x${offset.toRadixString(16)}';
  }

  String _resolvePropName(int propIndex) {
    if (currentObject != null && propIndex < currentObject!.baseVars.length) {
      final selId = currentObject!.baseVars[propIndex];
      return context.resolveSelectorName(selId);
    }
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
        return 'prop_$propIndex';
    }
  }

  bool _isStandardPropertyName(String name) {
    const props = {
      'x', 'y', 'z', 'view', 'loop', 'cel', 'priority', 'signal', 'illegalBits',
      'nsTop', 'nsLeft', 'nsBottom', 'nsRight', 'lsTop', 'lsLeft', 'lsBottom', 'lsRight',
      'brTop', 'brLeft', 'brBottom', 'brRight', 'name', 'type', 'message', 'modifiers',
      'claimed', 'species', 'superClass', 'underBits', 'client', 'state',
    };
    return props.contains(name);
  }

  _LinearSliceResult _decompileLinearSlice(
    List<_DecodedInstr> instructions,
    int startIdx,
    int endIdx,
  ) {
    final stack = <SciExpr>[];
    SciExpr? acc;
    SciExpr? prev;

    for (var i = startIdx; i < endIdx; i++) {
      final di = instructions[i];
      final next = (i + 1 < instructions.length) ? instructions[i + 1] : null;
      final step = _executeLinearStep(di, stack, acc, prev, next);
      acc = step.acc;
      prev = step.prev;
    }

    return _LinearSliceResult(acc: acc, stack: stack);
  }

  _WhileLoopInfo? _detectWhileLoop(
    List<_DecodedInstr> instructions,
    int currentIdx,
    int endIdx,
    Map<int, int> offsetToIndex,
  ) {
    final loopStartOffset = instructions[currentIdx].offset;

    var bntIdx = -1;
    for (var j = currentIdx; j < endIdx; j++) {
      if (instructions[j].opcode == 0x18) {
        bntIdx = j;
        break;
      }
      if (instructions[j].opcode == 0x24 || instructions[j].opcode == 0x19) {
        break;
      }
    }

    if (bntIdx == -1) return null;

    final bntRel = instructions[bntIdx].operands[0];
    final exitOffset = instructions[bntIdx].offset + instructions[bntIdx].length + bntRel;
    final exitIdx = offsetToIndex[exitOffset];

    if (exitIdx == null || exitIdx <= bntIdx || exitIdx > endIdx) {
      return null;
    }

    final jmpIdx = exitIdx - 1;
    if (jmpIdx > bntIdx && instructions[jmpIdx].opcode == 0x19) {
      final jmpRel = instructions[jmpIdx].operands[0];
      final jmpTarget = instructions[jmpIdx].offset + instructions[jmpIdx].length + jmpRel;
      if (jmpTarget == loopStartOffset) {
        return _WhileLoopInfo(
          loopStartOffset: loopStartOffset,
          condStart: currentIdx,
          condEnd: bntIdx,
          bodyStart: bntIdx + 1,
          bodyEnd: jmpIdx,
          exitOffset: exitOffset,
          nextIndex: exitIdx,
        );
      }
    }

    return null;
  }
}

class _LinearStepResult {
  final SciExpr? acc;
  final SciExpr? prev;
  final SciStatement? emittedStatement;

  const _LinearStepResult({
    this.acc,
    this.prev,
    this.emittedStatement,
  });
}

class _LinearSliceResult {
  final SciExpr? acc;
  final List<SciExpr> stack;

  const _LinearSliceResult({
    this.acc,
    this.stack = const [],
  });
}

class _WhileLoopInfo {
  final int loopStartOffset;
  final int condStart;
  final int condEnd;
  final int bodyStart;
  final int bodyEnd;
  final int exitOffset;
  final int nextIndex;

  const _WhileLoopInfo({
    required this.loopStartOffset,
    required this.condStart,
    required this.condEnd,
    required this.bodyStart,
    required this.bodyEnd,
    required this.exitOffset,
    required this.nextIndex,
  });
}
