/// Argument types for AGI logic bytecode instructions.
enum AgiArgType {
  unk(0, ''),
  num(1, ''),
  obj(2, '%o'),
  ctl(3, '%c'),
  variable(4, '%v'),
  inv(5, '%i'),
  tok(6, '%t'),
  flg(7, '%f'),
  str(8, '%s'),
  msg(9, '%m'),
  wrd(10, '%w');

  final int id;
  final String prefix;
  const AgiArgType(this.id, this.prefix);

  static AgiArgType fromId(int id) {
    return AgiArgType.values.firstWhere(
      (t) => t.id == id,
      orElse: () => AgiArgType.unk,
    );
  }
}

/// Abstract base class for all disassembled AGI logic instructions (AST nodes).
abstract class LogicInstruction {
  /// The byte length of this instruction in the bytecode stream.
  int get length;

  /// Byte offset where this instruction begins in the script bytecode.
  int offset = 0;
}

/// Basic instruction opcode with fixed or version-determined arguments.
class BasicInstruction extends LogicInstruction {
  final int opcode;
  final String name;
  final int numArgs;
  final int argTypesBitmask;
  final List<int> args;

  BasicInstruction({
    required this.opcode,
    required this.name,
    required this.numArgs,
    required this.argTypesBitmask,
    this.args = const [],
  });

  /// Creates an unbound template of this basic instruction.
  BasicInstruction.template(this.name, this.numArgs, this.argTypesBitmask)
      : opcode = 0,
        args = const [];

  /// Returns a copy bound to specific runtime [opcode], [args], and [offset].
  BasicInstruction bind({
    required int opcode,
    required List<int> args,
    required int offset,
  }) {
    final ins = BasicInstruction(
      opcode: opcode,
      name: name,
      numArgs: numArgs,
      argTypesBitmask: argTypesBitmask,
      args: args,
    );
    ins.offset = offset;
    return ins;
  }

  @override
  int get length => numArgs + 1;

  /// Returns the argument type for argument index [which] (0-indexed).
  AgiArgType getArgType(int which) {
    final typeId = (argTypesBitmask >> (which * 4)) & 0x0F;
    return AgiArgType.fromId(typeId);
  }
}

/// Said test instruction: `said(w1, w2, ...)`.
class SaidInstruction extends LogicInstruction {
  final List<int> wordGroupIds;

  SaidInstruction(this.wordGroupIds);

  @override
  int get length => (wordGroupIds.length * 2) + 2; // 1 opcode + 1 count + 2 bytes per word
}

/// Structured IF-THEN / IF-THEN-ELSE instruction block (0xFF).
class IfInstruction extends LogicInstruction {
  final LogicInstruction condition;
  final LogicInstruction thenBlock;
  final LogicInstruction? elseBlock;

  IfInstruction({
    required this.condition,
    required this.thenBlock,
    this.elseBlock,
  });

  @override
  int get length {
    // 0xFF (condition) 0xFF (jump_len 2 bytes) (thenBlock)
    // plus optional ELSE (0xFE jump_len 2 bytes) (elseBlock)
    return 4 +
        condition.length +
        thenBlock.length +
        (elseBlock != null ? (3 + elseBlock!.length) : 0);
  }
}

/// UNLESS (test) GOTO(target) instruction block when structured IF nesting breaks.
class UnlessGotoInstruction extends LogicInstruction {
  final LogicInstruction condition;
  final int relativeJump;
  final int targetAddress;

  UnlessGotoInstruction({
    required this.condition,
    required this.relativeJump,
    required this.targetAddress,
  });

  @override
  int get length => 4 + condition.length; // 0xFF + condition + 0xFF + 2 bytes jump
}

/// GOTO instruction (0xFE).
class GotoInstruction extends LogicInstruction {
  final int relativeTarget;
  final int targetAddress;

  GotoInstruction({
    required this.relativeTarget,
    required this.targetAddress,
  });

  @override
  int get length => 3; // 0xFE + 2 bytes signed LE offset
}

/// Logical OR of tests (0xFC ... 0xFC).
class OrInstruction extends LogicInstruction {
  final LogicInstruction condition;

  OrInstruction(this.condition);

  @override
  int get length => condition.length + 2; // 0xFC + condition + 0xFC
}

/// Logical NOT of a test (0xFD).
class NotInstruction extends LogicInstruction {
  final LogicInstruction inner;

  NotInstruction(this.inner);

  @override
  int get length => inner.length + 1; // 0xFD + inner test
}

/// Container for a sequence of disassembled instructions.
class CompoundInstruction extends LogicInstruction {
  final List<LogicInstruction> instructions;

  CompoundInstruction([List<LogicInstruction>? list])
      : instructions = list ?? [];

  void add(LogicInstruction instruction) {
    instructions.add(instruction);
  }

  @override
  int get length => instructions.fold(0, (sum, i) => sum + i.length);

  /// Reduces a single-element compound instruction to its sole child.
  LogicInstruction compress() {
    return instructions.length == 1 ? instructions.first : this;
  }
}
