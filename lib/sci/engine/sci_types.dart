// Core VM types and registers for the Sierra SCI PMachine.

/// Represents a 32-bit register in the Sierra SCI PMachine.
///
/// Composed of a 16-bit [segment] and a 16-bit [offset].
/// When [segment] is 0, the register holds an immediate 16-bit integer (signed or unsigned).
/// When [segment] is > 0, the register is a pointer to an entity in [SciSegManager]
/// (e.g. script object, string, list, node, clone).
class SciReg {
  final int segment;
  final int offset;

  const SciReg(this.segment, this.offset);

  /// Creates a register representing an immediate 16-bit integer (segment 0).
  const SciReg.fromInt(int value)
      : segment = 0,
        offset = value & 0xFFFF;

  /// Creates a register representing a pointer.
  const SciReg.pointer(int segment, int offset)
      : segment = segment & 0xFFFF,
        offset = offset & 0xFFFF;

  /// Standard null pointer (0000:0000).
  static const SciReg nullReg = SciReg(0, 0);

  /// Sentinel for uninitialized variables (FFFF:0000).
  static const SciReg uninitialized = SciReg(0xFFFF, 0);

  /// True if both segment and offset are 0.
  bool get isNull => segment == 0 && offset == 0;

  /// True if this register holds an immediate number (segment == 0).
  bool get isNumber => segment == 0;

  /// True if this register holds a pointer into memory (segment > 0 and not uninitialized).
  bool get isPointer => segment != 0 && segment != 0xFFFF;

  /// True if this register has been initialized.
  bool get isInitialized => segment != 0xFFFF;

  /// Converts offset to an unsigned 16-bit integer (0..65535).
  int toUint16() => offset & 0xFFFF;

  /// Converts offset to a signed 16-bit integer (-32768..32767).
  int toSint16() {
    final v = offset & 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  // --- Arithmetic operators ---

  SciReg operator +(dynamic other) {
    final int addend = other is SciReg ? other.toSint16() : (other as int);
    return SciReg(segment, (offset + addend) & 0xFFFF);
  }

  SciReg operator -(dynamic other) {
    if (other is SciReg) {
      if (isNumber && other.isNumber) {
        return SciReg.fromInt((toSint16() - other.toSint16()) & 0xFFFF);
      }
      // Pointer difference or offset decrement
      return SciReg(segment, (offset - other.toSint16()) & 0xFFFF);
    }
    final int subtrahend = other as int;
    return SciReg(segment, (offset - subtrahend) & 0xFFFF);
  }

  SciReg operator *(dynamic other) {
    final int factor = other is SciReg ? other.toSint16() : (other as int);
    return SciReg(segment, (toSint16() * factor) & 0xFFFF);
  }

  SciReg operator ~/(dynamic other) {
    final int divisor = other is SciReg ? other.toSint16() : (other as int);
    if (divisor == 0) return const SciReg.fromInt(0);
    return SciReg(segment, (toSint16() ~/ divisor) & 0xFFFF);
  }

  SciReg operator %(dynamic other) {
    final int divisor = other is SciReg ? other.toSint16() : (other as int);
    if (divisor == 0) return const SciReg.fromInt(0);
    return SciReg(segment, (toSint16() % divisor) & 0xFFFF);
  }

  SciReg operator &(dynamic other) {
    final int mask = other is SciReg ? other.toUint16() : (other as int);
    return SciReg(segment, (offset & mask) & 0xFFFF);
  }

  SciReg operator |(dynamic other) {
    final int mask = other is SciReg ? other.toUint16() : (other as int);
    return SciReg(segment, (offset | mask) & 0xFFFF);
  }

  SciReg operator ^(dynamic other) {
    final int mask = other is SciReg ? other.toUint16() : (other as int);
    return SciReg(segment, (offset ^ mask) & 0xFFFF);
  }

  SciReg operator <<(dynamic other) {
    final int shift = other is SciReg ? other.toUint16() : (other as int);
    return SciReg(segment, (offset << (shift & 0x0F)) & 0xFFFF);
  }

  SciReg operator >>(dynamic other) {
    final int shift = other is SciReg ? other.toUint16() : (other as int);
    return SciReg(segment, (toUint16() >> (shift & 0x0F)) & 0xFFFF);
  }

  SciReg operator ~() => SciReg(segment, (~offset) & 0xFFFF);

  SciReg operator -() => SciReg(segment, (-toSint16()) & 0xFFFF);

  // --- Signed Comparisons ---

  bool operator <(SciReg other) {
    if (segment != other.segment) return segment < other.segment;
    return toSint16() < other.toSint16();
  }

  bool operator <=(SciReg other) {
    if (segment != other.segment) return segment <= other.segment;
    return toSint16() <= other.toSint16();
  }

  bool operator >(SciReg other) {
    if (segment != other.segment) return segment > other.segment;
    return toSint16() > other.toSint16();
  }

  bool operator >=(SciReg other) {
    if (segment != other.segment) return segment >= other.segment;
    return toSint16() >= other.toSint16();
  }

  // --- Unsigned Comparisons ---

  bool ltU(SciReg other) {
    if (segment != other.segment) return segment < other.segment;
    return toUint16() < other.toUint16();
  }

  bool leU(SciReg other) {
    if (segment != other.segment) return segment <= other.segment;
    return toUint16() <= other.toUint16();
  }

  bool gtU(SciReg other) {
    if (segment != other.segment) return segment > other.segment;
    return toUint16() > other.toUint16();
  }

  bool geU(SciReg other) {
    if (segment != other.segment) return segment >= other.segment;
    return toUint16() >= other.toUint16();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SciReg && other.segment == segment && other.offset == offset;
  }

  @override
  int get hashCode => (segment << 16) | (offset & 0xFFFF);

  @override
  String toString() {
    if (isNumber) {
      final signed = toSint16();
      final unsigned = toUint16();
      if (signed < 0) {
        return '$signed (0x${unsigned.toRadixString(16).padLeft(4, '0')})';
      }
      return '0x${unsigned.toRadixString(16).padLeft(4, '0')} ($signed)';
    }
    return '${segment.toRadixString(16).padLeft(4, '0')}:${offset.toRadixString(16).padLeft(4, '0')}';
  }
}

/// Variable classes in the SCI PMachine bytecode grid.
enum SciVarType {
  global(0),
  local(1),
  temp(2),
  param(3);

  final int id;
  const SciVarType(this.id);

  static SciVarType fromId(int id) {
    switch (id & 0x03) {
      case 0:
        return SciVarType.global;
      case 1:
        return SciVarType.local;
      case 2:
        return SciVarType.temp;
      case 3:
      default:
        return SciVarType.param;
    }
  }
}

/// Execution call stack frame type.
enum SciExecStackType {
  call,
  varSelector,
  kernel,
}

/// A frame on the PMachine execution call stack.
class SciExecStack {
  SciReg objp;
  SciReg pc;
  int localSegment;
  int sp;
  int fp;
  int argp;
  int argc;
  int tempCount;
  SciExecStackType type;
  int selector;
  int script;
  int pubfunct;
  int varIndex;

  SciExecStack({
    required this.objp,
    required this.pc,
    required this.localSegment,
    required this.sp,
    required this.fp,
    this.argp = 0,
    this.argc = 0,
    this.tempCount = 0,
    this.type = SciExecStackType.call,
    this.selector = 0,
    this.script = 0,
    this.pubfunct = 0,
    this.varIndex = 0,
  });

  @override
  String toString() =>
      'SciExecStack($type, obj: $objp, pc: $pc, script: $script, sel: $selector, sp: $sp, fp: $fp, argc: $argc)';
}
