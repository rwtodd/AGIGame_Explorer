import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';

/// Decoder for Sierra AGI Logic bytecode instructions (v2 and v3).
class InstructionDecoder {
  final double version;

  late final BasicInstruction code134Quit;
  late final BasicInstruction code151PrintAt;
  late final BasicInstruction code152PrintAtV;
  late final BasicInstruction code176Unknown;

  InstructionDecoder({this.version = 2.917}) {
    code134Quit = BasicInstruction.template('quit', (version < 2.090) ? 0 : 1, 0x1);
    code151PrintAt = BasicInstruction.template(
      'print.at',
      (version < 2.401) ? 3 : 4,
      (version < 2.401) ? 0x119 : 0x1119,
    );
    code152PrintAtV = BasicInstruction.template(
      'print.at.v',
      (version < 2.401) ? 3 : 4,
      (version < 2.401) ? 0x114 : 0x1114,
    );
    code176Unknown = BasicInstruction.template(
      'unknown176',
      (version == 3.002086) ? 1 : 0,
      0x0,
    );
  }

  /// Disassembles the full [byteCode] sequence from [start] to [end].
  CompoundInstruction decode(Uint8List byteCode, [int start = 0, int? end]) {
    final stop = end ?? byteCode.length;
    final compound = CompoundInstruction();
    var cur = start;

    try {
      while (cur < stop) {
        final ins = decodeOne(byteCode, cur, stop);
        compound.add(ins);
        cur += ins.length;
      }
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Error decoding bytecode at offset 0x${cur.toRadixString(16).padLeft(4, '0')}: $e');
    }

    return compound;
  }

  /// Decodes a single top-level action or structured block starting at [start].
  LogicInstruction decodeOne(Uint8List byteCode, int start, int end) {
    if (start >= end) {
      throw const AgiException('Unexpected end of bytecode while reading opcode.');
    }

    final opcode = byteCode[start];
    return switch (opcode) {
      0xFE => decodeGotoStatement(byteCode, start, end),
      0xFF => decodeIfStatement(byteCode, start, end),
      _ => decodeAction(opcode, byteCode, start, end),
    };
  }

  /// Decodes an action instruction (opcode 0..181).
  BasicInstruction decodeAction(int opcode, Uint8List byteCode, int start, int end) {
    final template = lookupActionTemplate(opcode);
    final numArgs = template.numArgs;

    if (start + numArgs >= end) {
      throw AgiException('Bytecode truncated while reading args for action ${template.name} (opcode $opcode)');
    }

    final args = <int>[];
    for (var i = 0; i < numArgs; i++) {
      args.add(byteCode[start + 1 + i]);
    }

    return template.bind(
      opcode: opcode,
      args: args,
      offset: start,
    );
  }

  /// Decodes a GOTO statement (0xFE).
  GotoInstruction decodeGotoStatement(Uint8List byteCode, int start, int end) {
    if (start + 2 >= end) {
      throw const AgiException('Bytecode truncated while reading GOTO offset.');
    }
    // Signed 16-bit little-endian relative jump offset
    var rawOffset = byteCode[start + 1] | (byteCode[start + 2] << 8);
    if (rawOffset >= 0x8000) rawOffset -= 0x10000;

    final targetAddress = start + rawOffset + 3;
    final gotoIns = GotoInstruction(
      relativeTarget: rawOffset,
      targetAddress: targetAddress,
    );
    gotoIns.offset = start;
    return gotoIns;
  }

  /// Decodes an IF structure (0xFF).
  LogicInstruction decodeIfStatement(Uint8List byteCode, int start, int end) {
    final ifStart = start;
    var cur = start + 1; // skip leading 0xFF

    // 1. Decode test stream up to closing 0xFF
    final testStream = decodeTestStream(0xFF, byteCode, cur, end);
    cur += testStream.length + 1; // skip test stream + closing 0xFF

    if (cur + 1 >= end) {
      throw const AgiException('Bytecode truncated while reading THEN jump length.');
    }

    final thenLen = byteCode[cur] | (byteCode[cur + 1] << 8);
    var thenEnd = cur + thenLen + 2;

    if (thenEnd > end) {
      // Not enough room for structured THEN block; recover as UNLESS (cond) GOTO(addr)
      final unlessIns = UnlessGotoInstruction(
        condition: testStream,
        relativeJump: thenLen,
        targetAddress: cur + 2 + thenLen,
      );
      unlessIns.offset = ifStart;
      return unlessIns;
    }

    cur += 2; // skip then length bytes

    // 2. Check for trailing GOTO (0xFE) indicating an ELSE branch
    var elseEnd = -1;
    if (thenLen > 3 && byteCode[thenEnd - 3] == 0xFE) {
      var elseLen = byteCode[thenEnd - 2] | (byteCode[thenEnd - 1] << 8);
      if (elseLen >= 0x8000) elseLen -= 0x10000;
      elseEnd = thenEnd + elseLen;

      if (elseLen > 0 && elseEnd <= end) {
        thenEnd -= 3; // exclude GOTO jump bytes from THEN block
      } else {
        elseEnd = -1; // jump is backward or invalid for ELSE
      }
    }

    // 3. Decode THEN and optional ELSE child instructions
    final thenInstructions = decode(byteCode, cur, thenEnd);
    CompoundInstruction? elseInstructions;
    if (elseEnd > 0) {
      elseInstructions = decode(byteCode, thenEnd + 3, elseEnd);
    }

    final ifIns = IfInstruction(
      condition: testStream,
      thenBlock: thenInstructions.compress(),
      elseBlock: elseInstructions?.compress(),
    );
    ifIns.offset = ifStart;
    return ifIns;
  }

  /// Decodes a stream of test instructions up to delimiter [delim] (usually 0xFF or 0xFC).
  LogicInstruction decodeTestStream(int delim, Uint8List byteCode, int start, int end) {
    final tests = CompoundInstruction();
    var cur = start;

    while (cur < end) {
      final bc = byteCode[cur];
      if (bc == delim) {
        break;
      }
      final decoded = decodeSimpleTest(bc, byteCode, cur, end);
      tests.add(decoded);
      cur += decoded.length;
    }

    return tests.compress();
  }

  /// Decodes a single test instruction (opcode 1..18, 0xFC OR, 0xFD NOT).
  LogicInstruction decodeSimpleTest(int testCode, Uint8List byteCode, int start, int end) {
    return switch (testCode) {
      0x0E => decodeSaidTest(byteCode, start, end),
      0xFC => decodeOrTest(byteCode, start, end),
      0xFD => decodeNotTest(byteCode, start, end),
      _ => decodeBasicTest(testCode, byteCode, start, end),
    };
  }

  /// Decodes a basic test opcode.
  BasicInstruction decodeBasicTest(int testCode, Uint8List byteCode, int start, int end) {
    final template = lookupTestTemplate(testCode);
    final numArgs = template.numArgs;

    if (start + numArgs >= end) {
      throw AgiException('Bytecode truncated while reading test ${template.name} (opcode $testCode)');
    }

    final args = <int>[];
    for (var i = 0; i < numArgs; i++) {
      args.add(byteCode[start + 1 + i]);
    }

    return template.bind(
      opcode: testCode,
      args: args,
      offset: start,
    );
  }

  /// Decodes `said(...)` test opcode (0x0E).
  SaidInstruction decodeSaidTest(Uint8List byteCode, int start, int end) {
    if (start + 1 >= end) {
      throw const AgiException('Truncated said() test header.');
    }
    final count = byteCode[start + 1];
    var cur = start + 2;

    if (cur + (count * 2) > end) {
      throw AgiException('Truncated said() test word list (expected $count words).');
    }

    final wordGroupIds = <int>[];
    for (var i = 0; i < count; i++) {
      final wordId = byteCode[cur] | (byteCode[cur + 1] << 8);
      wordGroupIds.add(wordId);
      cur += 2;
    }

    final said = SaidInstruction(wordGroupIds);
    said.offset = start;
    return said;
  }

  /// Decodes `OR(...)` test block (0xFC).
  OrInstruction decodeOrTest(Uint8List byteCode, int start, int end) {
    final orCondition = decodeTestStream(0xFC, byteCode, start + 1, end);
    final orIns = OrInstruction(orCondition);
    orIns.offset = start;
    return orIns;
  }

  /// Decodes `NOT(...)` test wrapper (0xFD).
  NotInstruction decodeNotTest(Uint8List byteCode, int start, int end) {
    if (start + 1 >= end) {
      throw const AgiException('Truncated NOT test condition.');
    }
    final nextCode = byteCode[start + 1];
    final inner = decodeSimpleTest(nextCode, byteCode, start + 1, end);
    final notIns = NotInstruction(inner);
    notIns.offset = start;
    return notIns;
  }

  /// Looks up test instruction metadata template.
  BasicInstruction lookupTestTemplate(int opcode) {
    if (opcode < 0 || opcode >= testTemplates.length) {
      throw AgiException('Unknown test opcode 0x${opcode.toRadixString(16).padLeft(2, '0')} ($opcode)');
    }
    if (opcode == 0x0E) {
      throw const AgiException('SAID opcode 0x0E requires decodeSaidTest.');
    }
    return testTemplates[opcode];
  }

  /// Looks up action instruction metadata template.
  BasicInstruction lookupActionTemplate(int opcode) {
    return switch (opcode) {
      134 => code134Quit,
      151 => code151PrintAt,
      152 => code152PrintAtV,
      176 => code176Unknown,
      _ => () {
          if (opcode < 0 || opcode >= actionTemplates.length) {
            throw AgiException('Unknown action opcode 0x${opcode.toRadixString(16).padLeft(2, '0')} ($opcode)');
          }
          return actionTemplates[opcode];
        }(),
    };
  }

  /// Test opcode templates table (0..18).
  static final List<BasicInstruction> testTemplates = [
    BasicInstruction.template('UNKNOWN', 0, 0x0), // 0
    BasicInstruction.template('equaln', 2, 0x14), // 1
    BasicInstruction.template('equalv', 2, 0x44), // 2
    BasicInstruction.template('lessn', 2, 0x14), // 3
    BasicInstruction.template('lessv', 2, 0x44), // 4
    BasicInstruction.template('greatern', 2, 0x14), // 5
    BasicInstruction.template('greaterv', 2, 0x44), // 6
    BasicInstruction.template('isset', 1, 0x7), // 7
    BasicInstruction.template('issetv', 1, 0x4), // 8
    BasicInstruction.template('has', 1, 0x5), // 9
    BasicInstruction.template('obj.in.room', 2, 0x45), // 10
    BasicInstruction.template('posn', 5, 0x11112), // 11
    BasicInstruction.template('controller', 1, 0x3), // 12
    BasicInstruction.template('have.key', 0, 0x0), // 13
    BasicInstruction.template('said', 0, 0x0), // 14 (handled separately)
    BasicInstruction.template('compare.strings', 2, 0x88), // 15
    BasicInstruction.template('obj.in.box', 5, 0x11112), // 16
    BasicInstruction.template('center.posn', 5, 0x11112), // 17
    BasicInstruction.template('right.posn', 5, 0x11112), // 18
  ];

  /// Action opcode templates table (0..181).
  static final List<BasicInstruction> actionTemplates = [
    BasicInstruction.template('return', 0, 0x0), // 0
    BasicInstruction.template('increment', 1, 0x4),
    BasicInstruction.template('decrement', 1, 0x4),
    BasicInstruction.template('assignn', 2, 0x14),
    BasicInstruction.template('assignv', 2, 0x44),
    BasicInstruction.template('addn', 2, 0x14), // 5
    BasicInstruction.template('addv', 2, 0x44),
    BasicInstruction.template('subn', 2, 0x14),
    BasicInstruction.template('subv', 2, 0x44),
    BasicInstruction.template('lindirectv', 2, 0x44),
    BasicInstruction.template('rindirect', 2, 0x44), // 10
    BasicInstruction.template('lindirectn', 2, 0x14),
    BasicInstruction.template('set', 1, 0x7),
    BasicInstruction.template('reset', 1, 0x7),
    BasicInstruction.template('toggle', 1, 0x7),
    BasicInstruction.template('set.v', 1, 0x4), // 15
    BasicInstruction.template('reset.v', 1, 0x4),
    BasicInstruction.template('toggle.v', 1, 0x4),
    BasicInstruction.template('new.room', 1, 0x1),
    BasicInstruction.template('new.room.v', 1, 0x4),
    BasicInstruction.template('load.logics', 1, 0x1), // 20
    BasicInstruction.template('load.logics.v', 1, 0x4),
    BasicInstruction.template('call', 1, 0x1),
    BasicInstruction.template('call.v', 1, 0x4),
    BasicInstruction.template('load.pic', 1, 0x4),
    BasicInstruction.template('draw.pic', 1, 0x4), // 25
    BasicInstruction.template('show.pic', 0, 0x0),
    BasicInstruction.template('discard.pic', 1, 0x4),
    BasicInstruction.template('overlay.pic', 1, 0x4),
    BasicInstruction.template('show.pri.screen', 0, 0x0),
    BasicInstruction.template('load.view', 1, 0x1), // 30
    BasicInstruction.template('load.view.v', 1, 0x4),
    BasicInstruction.template('discard.view', 1, 0x1),
    BasicInstruction.template('animate.obj', 1, 0x2),
    BasicInstruction.template('unanimate.all', 0, 0x0),
    BasicInstruction.template('draw', 1, 0x2), // 35
    BasicInstruction.template('erase', 1, 0x2),
    BasicInstruction.template('position', 3, 0x112),
    BasicInstruction.template('position.v', 3, 0x442),
    BasicInstruction.template('get.posn', 3, 0x442),
    BasicInstruction.template('reposition', 3, 0x442), // 40
    BasicInstruction.template('set.view', 2, 0x12),
    BasicInstruction.template('set.view.v', 2, 0x42),
    BasicInstruction.template('set.loop', 2, 0x12),
    BasicInstruction.template('set.loop.v', 2, 0x42),
    BasicInstruction.template('fix.loop', 1, 0x2), // 45
    BasicInstruction.template('release.loop', 1, 0x2),
    BasicInstruction.template('set.cel', 2, 0x12),
    BasicInstruction.template('set.cel.v', 2, 0x42),
    BasicInstruction.template('last.cel', 2, 0x42),
    BasicInstruction.template('current.cel', 2, 0x42), // 50
    BasicInstruction.template('current.loop', 2, 0x42),
    BasicInstruction.template('current.view', 2, 0x42),
    BasicInstruction.template('number.of.loops', 2, 0x42),
    BasicInstruction.template('set.priority', 2, 0x12),
    BasicInstruction.template('set.priority.v', 2, 0x42), // 55
    BasicInstruction.template('release.priority', 1, 0x2),
    BasicInstruction.template('get.priority', 2, 0x42),
    BasicInstruction.template('stop.update', 1, 0x2),
    BasicInstruction.template('start.update', 1, 0x2),
    BasicInstruction.template('force.update', 1, 0x2), // 60
    BasicInstruction.template('ignore.horizon', 1, 0x2),
    BasicInstruction.template('observe.horizon', 1, 0x2),
    BasicInstruction.template('set.horizon', 1, 0x1),
    BasicInstruction.template('object.on.water', 1, 0x2),
    BasicInstruction.template('object.on.land', 1, 0x2), // 65
    BasicInstruction.template('object.on.anything', 1, 0x2),
    BasicInstruction.template('ignore.objs', 1, 0x2),
    BasicInstruction.template('observe.objs', 1, 0x2),
    BasicInstruction.template('distance', 3, 0x422),
    BasicInstruction.template('stop.cycling', 1, 0x2), // 70
    BasicInstruction.template('start.cycling', 1, 0x2),
    BasicInstruction.template('normal.cycle', 1, 0x2),
    BasicInstruction.template('end.of.loop', 2, 0x72),
    BasicInstruction.template('reverse.cycle', 1, 0x2),
    BasicInstruction.template('reverse.loop', 2, 0x72), // 75
    BasicInstruction.template('cycle.time', 2, 0x42),
    BasicInstruction.template('stop.motion', 1, 0x2),
    BasicInstruction.template('start.motion', 1, 0x2),
    BasicInstruction.template('step.size', 2, 0x42),
    BasicInstruction.template('step.time', 2, 0x42), // 80
    BasicInstruction.template('move.obj', 5, 0x71112),
    BasicInstruction.template('move.obj.v', 5, 0x71442),
    BasicInstruction.template('follow.ego', 3, 0x712),
    BasicInstruction.template('wander', 1, 0x2),
    BasicInstruction.template('normal.motion', 1, 0x2), // 85
    BasicInstruction.template('set.dir', 2, 0x42),
    BasicInstruction.template('get.dir', 2, 0x42),
    BasicInstruction.template('ignore.blocks', 1, 0x2),
    BasicInstruction.template('observe.blocks', 1, 0x2),
    BasicInstruction.template('block', 4, 0x1111), // 90
    BasicInstruction.template('unblock', 0, 0x0),
    BasicInstruction.template('get', 1, 0x5),
    BasicInstruction.template('get.v', 1, 0x4),
    BasicInstruction.template('drop', 1, 0x5),
    BasicInstruction.template('put', 2, 0x45), // 95
    BasicInstruction.template('put.v', 2, 0x44),
    BasicInstruction.template('get.room.v', 2, 0x44),
    BasicInstruction.template('load.sound', 1, 0x1),
    BasicInstruction.template('sound', 2, 0x71),
    BasicInstruction.template('stop.sound', 0, 0x0), // 100
    BasicInstruction.template('print', 1, 0x9),
    BasicInstruction.template('print.v', 1, 0x4),
    BasicInstruction.template('display', 3, 0x911),
    BasicInstruction.template('display.v', 3, 0x444),
    BasicInstruction.template('clear.lines', 3, 0x111), // 105
    BasicInstruction.template('text.screen', 0, 0x0),
    BasicInstruction.template('graphics', 0, 0x0),
    BasicInstruction.template('set.cursor.char', 1, 0x9),
    BasicInstruction.template('set.text.attribute', 2, 0x11),
    BasicInstruction.template('shake.screen', 1, 0x1), // 110
    BasicInstruction.template('configure.screen', 3, 0x111),
    BasicInstruction.template('status.line.on', 0, 0x0),
    BasicInstruction.template('status.line.off', 0, 0x0),
    BasicInstruction.template('set.string', 2, 0x98),
    BasicInstruction.template('get.string', 5, 0x11198), // 115
    BasicInstruction.template('word.to.string', 2, 0x8A),
    BasicInstruction.template('parse', 1, 0x8),
    BasicInstruction.template('get.num', 2, 0x49),
    BasicInstruction.template('prevent.input', 0, 0x0),
    BasicInstruction.template('accept.input', 0, 0x0), // 120
    BasicInstruction.template('set.key', 3, 0x311),
    BasicInstruction.template('add.to.pic', 7, 0x1111111),
    BasicInstruction.template('add.to.pic.v', 7, 0x4444444),
    BasicInstruction.template('status', 0, 0x0),
    BasicInstruction.template('save.game', 0, 0x0), // 125
    BasicInstruction.template('restore.game', 0, 0x0),
    BasicInstruction.template('init.disk', 0, 0x0),
    BasicInstruction.template('restart.game', 0, 0x0),
    BasicInstruction.template('show.obj', 1, 0x1),
    BasicInstruction.template('random', 3, 0x411), // 130
    BasicInstruction.template('program.control', 0, 0x0),
    BasicInstruction.template('player.control', 0, 0x0),
    BasicInstruction.template('obj.status.v', 1, 0x4),
    BasicInstruction.template('quit', 1, 0x1), // 134 (overridden by version)
    BasicInstruction.template('show.mem', 0, 0x0), // 135
    BasicInstruction.template('pause', 0, 0x0),
    BasicInstruction.template('echo.line', 0, 0x0),
    BasicInstruction.template('cancel.line', 0, 0x0),
    BasicInstruction.template('init.joy', 0, 0x0),
    BasicInstruction.template('toggle.monitor', 0, 0x0), // 140
    BasicInstruction.template('version', 0, 0x0),
    BasicInstruction.template('script.size', 1, 0x1),
    BasicInstruction.template('set.game.id', 1, 0x9),
    BasicInstruction.template('log', 1, 0x9),
    BasicInstruction.template('set.scan.start', 0, 0x0), // 145
    BasicInstruction.template('reset.scan.start', 0, 0x0),
    BasicInstruction.template('reposition.to', 3, 0x112),
    BasicInstruction.template('reposition.to.v', 3, 0x442),
    BasicInstruction.template('trace.on', 0, 0x0),
    BasicInstruction.template('trace.info', 3, 0x111), // 150
    BasicInstruction.template('print.at', 4, 0x1119), // 151 (overridden by version)
    BasicInstruction.template('print.at.v', 4, 0x1114), // 152 (overridden by version)
    BasicInstruction.template('discard.view.v', 1, 0x4),
    BasicInstruction.template('clear.text.rect', 5, 0x11111),
    BasicInstruction.template('set.upper.left', 2, 0x00), // 155
    BasicInstruction.template('set.menu', 1, 0x9),
    BasicInstruction.template('set.menu.item', 2, 0x39),
    BasicInstruction.template('submit.menu', 0, 0x0),
    BasicInstruction.template('enable.item', 1, 0x3),
    BasicInstruction.template('disable.item', 1, 0x3), // 160
    BasicInstruction.template('menu.input', 0, 0x0),
    BasicInstruction.template('show.obj.v', 1, 0x4),
    BasicInstruction.template('open.dialogue', 0, 0x0),
    BasicInstruction.template('close.dialogue', 0, 0x0),
    BasicInstruction.template('mul.n', 2, 0x14), // 165
    BasicInstruction.template('mul.v', 2, 0x44),
    BasicInstruction.template('div.n', 2, 0x14),
    BasicInstruction.template('div.v', 2, 0x44),
    BasicInstruction.template('close.window', 0, 0x0),
    BasicInstruction.template('unknown170', 1, 0x0), // 170
    BasicInstruction.template('unknown171', 0, 0x0),
    BasicInstruction.template('unknown172', 0, 0x0),
    BasicInstruction.template('unknown173', 0, 0x0),
    BasicInstruction.template('unknown174', 1, 0x0),
    BasicInstruction.template('unknown175', 1, 0x0), // 175
    BasicInstruction.template('unknown176', 0, 0x0), // 176 (overridden by version)
    BasicInstruction.template('unknown177', 1, 0x0),
    BasicInstruction.template('unknown178', 0, 0x0),
    BasicInstruction.template('unknown179', 4, 0x0000),
    BasicInstruction.template('unknown180', 2, 0x00), // 180
    BasicInstruction.template('unknown181', 0, 0x0),
  ];
}
