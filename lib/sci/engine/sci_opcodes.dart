// PMachine instruction opcodes and operand decoding for SCI0.

import 'dart:typed_data';

/// Operand types used in the SCI PMachine base opcode format table.
enum SciOperandType {
  none,
  byte,
  sbyte,
  word,
  sword,
  variable,
  svariable,
  offset,
  srelative,
  end,
  invalid,
}

/// Decoded PMachine instruction.
class SciInstruction {
  final int opcode;
  final int extOpcode;
  final List<int> operands;
  final int length;

  const SciInstruction(
    this.opcode,
    this.extOpcode,
    this.operands,
    this.length,
  );

  /// True if the 1-bit width flag was set (byte operand mode).
  bool get isByteMode => (extOpcode & 1) != 0;

  String get name => getOpcodeName(opcode);

  @override
  String toString() =>
      '$name (${isByteMode ? "b" : "w"}) ${operands.map((op) => '0x${op.toRadixString(16)}').join(', ')}';
}

/// Base format table mapping each of the 128 PMachine opcodes to its operand types.
const List<List<SciOperandType>> sciBaseOpcodeFormats = [
  // 00 - 03 / bnot, add, sub, mul
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  // 04 - 07 / div, mod, shr, shl
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  // 08 - 0B / xor, and, or, neg
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  // 0C - 0F / not, eq, ne, gt
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  // 10 - 13 / ge, lt, le, ugt
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  // 14 - 17 / uge, ult, ule, bt
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.srelative],
  // 18 - 1B / bnt, jmp, ldi, push
  [SciOperandType.srelative],
  [SciOperandType.srelative],
  [SciOperandType.svariable],
  [SciOperandType.none],
  // 1C - 1F / pushi, toss, dup, link
  [SciOperandType.svariable],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.variable],
  // 20 - 23 / call, callk, callb, calle
  [SciOperandType.srelative, SciOperandType.byte],
  [SciOperandType.variable, SciOperandType.byte],
  [SciOperandType.variable, SciOperandType.byte],
  [SciOperandType.variable, SciOperandType.svariable, SciOperandType.byte],
  // 24 - 27 / ret, send, dummy, dummy
  [SciOperandType.end],
  [SciOperandType.byte],
  [SciOperandType.invalid],
  [SciOperandType.invalid],
  // 28 - 2B / class, dummy, self, super
  [SciOperandType.variable],
  [SciOperandType.invalid],
  [SciOperandType.byte],
  [SciOperandType.variable, SciOperandType.byte],
  // 2C - 2F / rest, lea, selfID, dummy
  [SciOperandType.svariable],
  [SciOperandType.svariable, SciOperandType.variable],
  [SciOperandType.none],
  [SciOperandType.invalid],
  // 30 - 33 / pprev, pToa, aTop, pTos
  [SciOperandType.none],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 34 - 37 / sTop, ipToa, dpToa, ipTos
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 38 - 3B / dpTos, lofsa, lofss, push0
  [SciOperandType.variable],
  [SciOperandType.srelative],
  [SciOperandType.srelative],
  [SciOperandType.none],
  // 3C - 3F / push1, push2, pushSelf, line
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.none],
  [SciOperandType.word],
  // ------------------------------------------------------------------------
  // 40 - 43 / lag, lal, lat, lap
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 44 - 47 / lsg, lsl, lst, lsp
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 48 - 4B / lagi, lali, lati, lapi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 4C - 4F / lsgi, lsli, lsti, lspi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // ------------------------------------------------------------------------
  // 50 - 53 / sag, sal, sat, sap
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 54 - 57 / ssg, ssl, sst, ssp
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 58 - 5B / sagi, sali, sati, sapi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 5C - 5F / ssgi, ssli, ssti, sspi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // ------------------------------------------------------------------------
  // 60 - 63 / plusag, plusal, plusat, plusap
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 64 - 67 / plussg, plussl, plusst, plussp
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 68 - 6B / plusagi, plusali, plusati, plusapi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 6C - 6F / plussgi, plussli, plussti, plusspi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // ------------------------------------------------------------------------
  // 70 - 73 / minusag, minusal, minusat, minusap
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 74 - 77 / minussg, minussl, minusst, minussp
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 78 - 7B / minusagi, minusali, minusati, minusapi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  // 7C - 7F / minussgi, minussli, minussti, minusspi
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
  [SciOperandType.variable],
];

/// Decodes the PMachine instruction at [pc] in [code].
SciInstruction decodeInstruction(Uint8List code, int pc) {
  var offset = pc;
  final extOpcode = code[offset++];
  final opcode = extOpcode >> 1;
  final widthBit = extOpcode & 1;

  final operands = <int>[];
  if (opcode < sciBaseOpcodeFormats.length) {
    final formats = sciBaseOpcodeFormats[opcode];
    for (final fmt in formats) {
      if (fmt == SciOperandType.none ||
          fmt == SciOperandType.end ||
          fmt == SciOperandType.invalid) {
        break;
      }

      switch (fmt) {
        case SciOperandType.byte:
          operands.add(code[offset++]);
          break;

        case SciOperandType.sbyte:
          final b = code[offset++];
          operands.add(b >= 0x80 ? b - 0x100 : b);
          break;

        case SciOperandType.word:
          final w = code[offset] | (code[offset + 1] << 8);
          offset += 2;
          operands.add(w);
          break;

        case SciOperandType.sword:
          final w = code[offset] | (code[offset + 1] << 8);
          offset += 2;
          operands.add(w >= 0x8000 ? w - 0x10000 : w);
          break;

        case SciOperandType.variable:
        case SciOperandType.offset:
          if (widthBit != 0) {
            operands.add(code[offset++]);
          } else {
            final w = code[offset] | (code[offset + 1] << 8);
            offset += 2;
            operands.add(w);
          }
          break;

        case SciOperandType.svariable:
        case SciOperandType.srelative:
          if (widthBit != 0) {
            final b = code[offset++];
            operands.add(b >= 0x80 ? b - 0x100 : b);
          } else {
            final w = code[offset] | (code[offset + 1] << 8);
            offset += 2;
            operands.add(w >= 0x8000 ? w - 0x10000 : w);
          }
          break;

        default:
          break;
      }
    }
  }

  // Special handling for pushSelf / op_file debug opcode
  if (opcode == 0x3E && widthBit != 0) {
    while (offset < code.length && code[offset++] != 0) {}
  }

  return SciInstruction(opcode, extOpcode, operands, offset - pc);
}

/// Human-readable PMachine opcode names.
const List<String> sciOpcodeNames = [
  /* 0x00 */ "bnot", "add", "sub", "mul", "div", "mod", "shr", "shl",
  /* 0x08 */ "xor", "and", "or", "neg", "not", "eq?", "ne?", "gt?",
  /* 0x10 */ "ge?", "lt?", "le?", "ugt?", "uge?", "ult?", "ule?", "bt",
  /* 0x18 */ "bnt", "jmp", "ldi", "push", "pushi", "toss", "dup", "link",
  /* 0x20 */ "call", "callk", "callb", "calle", "ret", "send", "dummy26", "dummy27",
  /* 0x28 */ "class", "dummy29", "self", "super", "&rest", "lea", "selfID", "dummy2f",
  /* 0x30 */ "pprev", "pToa", "aTop", "pTos", "sTop", "ipToa", "dpToa", "ipTos",
  /* 0x38 */ "dpTos", "lofsa", "lofss", "push0", "push1", "push2", "pushSelf", "line",
  /* 0x40 */ "lag", "lal", "lat", "lap", "lsg", "lsl", "lst", "lsp",
  /* 0x48 */ "lagi", "lali", "lati", "lapi", "lsgi", "lsli", "lsti", "lspi",
  /* 0x50 */ "sag", "sal", "sat", "sap", "ssg", "ssl", "sst", "ssp",
  /* 0x58 */ "sagi", "sali", "sati", "sapi", "ssgi", "ssli", "ssti", "sspi",
  /* 0x60 */ "+ag", "+al", "+at", "+ap", "+sg", "+sl", "+st", "+sp",
  /* 0x68 */ "+agi", "+ali", "+ati", "+api", "+sgi", "+sli", "+sti", "+spi",
  /* 0x70 */ "-ag", "-al", "-at", "-ap", "-sg", "-sl", "-st", "-sp",
  /* 0x78 */ "-agi", "-ali", "-ati", "-api", "-sgi", "-sli", "-sti", "-spi"
];

String getOpcodeName(int opcode) {
  if (opcode >= 0 && opcode < sciOpcodeNames.length) {
    return sciOpcodeNames[opcode];
  }
  return 'op_0x${opcode.toRadixString(16)}';
}
