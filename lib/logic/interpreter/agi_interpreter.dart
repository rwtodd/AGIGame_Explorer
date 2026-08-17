import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';

/// Call stack frame for nested LOGIC scripts (via `call` / `call.v`).
class AgiCallFrame {
  final AgiLogicScript script;
  final int scriptNumber;
  int ip;

  AgiCallFrame({
    required this.script,
    required this.scriptNumber,
    this.ip = 0,
  });
}

/// Execution status returned by interpreter step methods.
enum InterpreterStatus {
  running,
  yielded,
  completed,
  error,
}

/// High-performance Sierra AGI LOGIC bytecode interpreter VM.
class AgiLogicInterpreter {
  final AgiMemory memory;
  final List<AnimatedObject> animatedObjects;
  AgiInterpreterDelegate delegate;
  final double version;
  math.Random rng;

  final List<AgiCallFrame> callStack = [];
  bool isHalted = false;
  bool _newRoomRequested = false;
  AgiLogicScript? _rootScript;
  int _rootScriptNumber = 0;

  /// Gets the currently loaded root script (usually Logic 0).
  AgiLogicScript? get rootScript => _rootScript;

  AgiLogicInterpreter({
    AgiMemory? memory,
    List<AnimatedObject>? animatedObjects,
    AgiInterpreterDelegate? delegate,
    this.version = 2.917,
    int? randomSeed,
    int maxAnimatedObjects = 64,
  })  : memory = memory ?? AgiMemory(),
        animatedObjects = animatedObjects ??
            List.generate(maxAnimatedObjects, (i) => AnimatedObject(number: i)),
        delegate = delegate ?? DefaultAgiInterpreterDelegate(),
        rng = randomSeed != null ? math.Random(randomSeed) : math.Random();

  /// Gets the currently active call stack frame.
  AgiCallFrame? get currentFrame => callStack.isNotEmpty ? callStack.last : null;

  /// Gets the currently executing script.
  AgiLogicScript? get currentScript => currentFrame?.script;

  /// Gets current instruction pointer of active frame.
  int get ip => currentFrame?.ip ?? 0;

  set ip(int value) {
    if (currentFrame != null) {
      currentFrame!.ip = value;
    }
  }

  /// Pushes a new script onto the call stack and begins execution from [startIp].
  void pushScript(AgiLogicScript script, {int scriptNumber = 0, int startIp = 0}) {
    callStack.add(
      AgiCallFrame(
        script: script,
        scriptNumber: scriptNumber,
        ip: startIp,
      ),
    );
    isHalted = false;
  }

  /// Clears call stack and loads root logic (usually Logic 0).
  void loadRootScript(AgiLogicScript script, {int scriptNumber = 0}) {
    _rootScript = script;
    _rootScriptNumber = scriptNumber;
    _pendingYield = false;
    _pendingInputCallback = null;
    callStack.clear();
    pushScript(script, scriptNumber: scriptNumber, startIp: memory.getScanStart(scriptNumber));
  }

  /// Retrieves animated object [which], throwing [AgiException] if out of bounds.
  AnimatedObject getObj(int which) {
    if (which < 0 || which >= animatedObjects.length) {
      throw AgiException('Animated object index $which is out of range (max ${animatedObjects.length - 1}).');
    }
    return animatedObjects[which];
  }

  /// Executes a single interpreter scan cycle (from scan start until root script returns or halts).
  ///
  /// Implements Sierra's rescan loop: when `new.room()` executes, `LOGIC 0` is
  /// automatically rescanned in the same tick cycle with the new room active.
  InterpreterStatus executeCycle() {
    if (hasPendingYield) return InterpreterStatus.yielded;
    if (_rootScript == null && currentFrame == null) return InterpreterStatus.completed;

    int rescanCount = 0;
    const maxRescans = 10;

    while (rescanCount < maxRescans) {
      if (callStack.isEmpty && _rootScript != null) {
        pushScript(_rootScript!, scriptNumber: _rootScriptNumber, startIp: memory.getScanStart(_rootScriptNumber));
      }

      // Reset scan start for current cycle
      ip = memory.getScanStart(_rootScriptNumber);
      isHalted = false;
      _newRoomRequested = false;

      while (!isHalted && callStack.isNotEmpty && !_newRoomRequested) {
        final status = stepInstruction();
        if (status != InterpreterStatus.running && !_newRoomRequested) {
          return status;
        }
      }

      if (_newRoomRequested) {
        rescanCount++;
        // If onNewRoom was executed, re-push root script if callStack is empty and rescan LOGIC 0
        if (callStack.isEmpty && _rootScript != null) {
          pushScript(_rootScript!, scriptNumber: _rootScriptNumber, startIp: memory.getScanStart(_rootScriptNumber));
        }
        continue;
      }

      break;
    }

    return InterpreterStatus.completed;
  }

  void Function(String?)? _pendingInputCallback;
  bool _pendingYield = false;

  /// Returns true if the interpreter is currently yielded waiting for modal dialog or player input.
  bool get hasPendingYield => _pendingYield || _pendingInputCallback != null;

  /// Returns true if the interpreter is currently yielded waiting for player input.
  bool get hasPendingInput => _pendingInputCallback != null;

  /// Resumes interpreter execution after a yielded input prompt (`get.string` or `get.num`) or modal dialog.
  InterpreterStatus resume([String? value]) {
    _pendingYield = false;
    if (_pendingInputCallback != null) {
      final cb = _pendingInputCallback!;
      _pendingInputCallback = null;
      cb(value);
    }

    int rescanCount = 0;
    const maxRescans = 10;

    while (rescanCount < maxRescans) {
      while (!isHalted && callStack.isNotEmpty && !_newRoomRequested) {
        final status = stepInstruction();
        if (status != InterpreterStatus.running && !_newRoomRequested) {
          return status;
        }
      }

      if (_newRoomRequested) {
        rescanCount++;
        if (callStack.isEmpty && _rootScript != null) {
          pushScript(_rootScript!, scriptNumber: _rootScriptNumber, startIp: memory.getScanStart(_rootScriptNumber));
        }
        continue;
      }

      break;
    }

    return InterpreterStatus.completed;
  }

  /// Resumes interpreter execution after a yielded input prompt (`get.string` or `get.num`).
  InterpreterStatus resumeWithInput(String? value) => resume(value);

  /// Executes exactly one bytecode instruction from the active script frame.
  InterpreterStatus stepInstruction() {
    final frame = currentFrame;
    if (frame == null || isHalted) {
      return InterpreterStatus.completed;
    }

    final code = frame.script.bytecodes;
    if (frame.ip < 0 || frame.ip >= code.length) {
      // Script reached end without explicit return -> pop frame
      callStack.removeLast();
      return callStack.isEmpty ? InterpreterStatus.completed : InterpreterStatus.running;
    }

    final opcode = code[frame.ip];
    switch (opcode) {
      case 0xFE: // GOTO
        _execGoto(code, frame);
        return InterpreterStatus.running;

      case 0xFF: // IF
        _execIf(code, frame);
        return InterpreterStatus.running;

      default:
        return _execAction(opcode, code, frame);
    }
  }

  void _execGoto(Uint8List code, AgiCallFrame frame) {
    if (frame.ip + 2 >= code.length) {
      throw const AgiException('Truncated GOTO instruction.');
    }
    var target = code[frame.ip + 1] | (code[frame.ip + 2] << 8);
    if (target >= 0x8000) target -= 0x10000;
    frame.ip += target + 3;
  }

  void _skipTestInstruction(Uint8List code, AgiCallFrame frame) {
    if (frame.ip >= code.length) return;
    final op = code[frame.ip];
    switch (op) {
      case 0x01: // equaln
      case 0x02: // equalv
      case 0x03: // lessn
      case 0x04: // lessv
      case 0x05: // greatern
      case 0x06: // greaterv
      case 0x0A: // obj.in.room
      case 0x0F: // compare.strings
        frame.ip += 3;
        break;

      case 0x07: // isset
      case 0x08: // issetv
      case 0x09: // has
      case 0x0C: // controller
        frame.ip += 2;
        break;

      case 0x0B: // posn
      case 0x10: // obj.in.box
      case 0x11: // center.posn
      case 0x12: // right.posn
        frame.ip += 6;
        break;

      case 0x0D: // have.key
      case 0x13:
        frame.ip += 1;
        break;

      case 0x0E: // said(count, w1, w2, ...)
        final count = code[frame.ip + 1];
        frame.ip += 2 + count * 2;
        break;

      case 0xFC: // OR block
        frame.ip++; // skip opening 0xFC
        while (frame.ip < code.length && code[frame.ip] != 0xFC) {
          _skipTestInstruction(code, frame);
        }
        if (frame.ip < code.length) {
          frame.ip++; // skip closing 0xFC
        }
        break;

      case 0xFD: // NOT
        frame.ip++; // skip 0xFD
        _skipTestInstruction(code, frame);
        break;

      default:
        frame.ip++;
        break;
    }
  }

  void _skipTestsUntil(Uint8List code, AgiCallFrame frame, int terminator) {
    while (frame.ip < code.length && code[frame.ip] != terminator) {
      _skipTestInstruction(code, frame);
    }
  }

  void _execIf(Uint8List code, AgiCallFrame frame) {
    frame.ip++; // skip opening 0xFF
    var conditionPassed = true;

    // Evaluate test stream until closing 0xFF with short-circuit evaluation
    while (frame.ip < code.length && code[frame.ip] != 0xFF) {
      final result = _evalTestSection(code, frame);
      if (!result) {
        // Short-circuit: in AND mode, once a test fails, skip remaining tests until 0xFF
        conditionPassed = false;
        _skipTestsUntil(code, frame, 0xFF);
        break;
      }
    }

    if (frame.ip >= code.length) {
      throw const AgiException('Unclosed IF statement: missing closing 0xFF.');
    }
    frame.ip++; // skip closing 0xFF

    if (frame.ip + 1 >= code.length) {
      throw const AgiException('Truncated IF branch jump length.');
    }

    final jumpLen = code[frame.ip] | (code[frame.ip + 1] << 8);

    if (conditionPassed) {
      // IF condition is TRUE: skip past the 2-byte jump offset and execute THEN body
      frame.ip += 2;
    } else {
      // IF condition is FALSE: jump over the THEN block (relative jump)
      frame.ip += jumpLen + 2;
    }
  }

  bool _evalTestSection(Uint8List code, AgiCallFrame frame) {
    if (frame.ip >= code.length) {
      throw const AgiException('Truncated test condition.');
    }

    final curVal = code[frame.ip];
    switch (curVal) {
      case 0x01: // equaln(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v) == n;

      case 0x02: // equalv(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v1) == memory.getVar(v2);

      case 0x03: // lessn(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v) < n;

      case 0x04: // lessv(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v1) < memory.getVar(v2);

      case 0x05: // greatern(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v) > n;

      case 0x06: // greaterv(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getVar(v1) > memory.getVar(v2);

      case 0x07: // isset(%f)
        final f = code[frame.ip + 1];
        frame.ip += 2;
        return memory.getFlag(f);

      case 0x08: // issetv(%v)
        final v = code[frame.ip + 1];
        frame.ip += 2;
        return memory.getFlag(memory.getVar(v));

      case 0x09: // has(%i)
        final i = code[frame.ip + 1];
        frame.ip += 2;
        final room = memory.itemRooms[i];
        return room == 255; // 255 = Ego is carrying item

      case 0x0A: // obj.in.room(%i, %v)
        final i = code[frame.ip + 1];
        final v = code[frame.ip + 2];
        frame.ip += 3;
        final room = memory.itemRooms[i] ?? 0xFF;
        return room == memory.getVar(v);

      case 0x0B: // posn(%o, x1, y1, x2, y2)
        final o = code[frame.ip + 1];
        final x1 = code[frame.ip + 2];
        final y1 = code[frame.ip + 3];
        final x2 = code[frame.ip + 4];
        final y2 = code[frame.ip + 5];
        frame.ip += 6;
        final obj = getObj(o);
        return obj.x >= x1 && obj.x <= x2 && obj.y >= y1 && obj.y <= y2;

      case 0x0C: // controller(%c)
        final c = code[frame.ip + 1];
        frame.ip += 2;
        return memory.getController(c);

      case 0x0D: // have.key()
        frame.ip++;
        return delegate.haveKey();

      case 0x0E: // said(count, w1, w2, ...)
        final count = code[frame.ip + 1];
        var cur = frame.ip + 2;
        final words = <int>[];
        for (var i = 0; i < count; i++) {
          words.add(code[cur] | (code[cur + 1] << 8));
          cur += 2;
        }
        frame.ip = cur;
        return delegate.checkSaid(words);

      case 0x0F: // compare.strings(%s1, %s2)
        final s1 = code[frame.ip + 1];
        final s2 = code[frame.ip + 2];
        frame.ip += 3;
        return memory.getString(s1).trim().toLowerCase() ==
            memory.getString(s2).trim().toLowerCase();

      case 0x10: // obj.in.box(%o, x1, y1, x2, y2)
      case 0x11: // center.posn(%o, x1, y1, x2, y2)
      case 0x12: // right.posn(%o, x1, y1, x2, y2)
        final o = code[frame.ip + 1];
        final x1 = code[frame.ip + 2];
        final y1 = code[frame.ip + 3];
        final x2 = code[frame.ip + 4];
        final y2 = code[frame.ip + 5];
        frame.ip += 6;
        final obj = getObj(o);
        return obj.x >= x1 && obj.x <= x2 && obj.y >= y1 && obj.y <= y2;

      case 0xFC: // OR (...)
        frame.ip++; // skip opening 0xFC
        var orPassed = false;
        while (frame.ip < code.length && code[frame.ip] != 0xFC) {
          final res = _evalTestSection(code, frame);
          if (res) {
            // Short-circuit: in OR mode, once a test succeeds, skip remaining tests until 0xFC
            orPassed = true;
            _skipTestsUntil(code, frame, 0xFC);
            break;
          }
        }
        if (frame.ip >= code.length) {
          throw const AgiException('Unclosed OR test section: missing closing 0xFC.');
        }
        frame.ip++; // skip closing 0xFC
        return orPassed;

      case 0xFD: // NOT (...)
        frame.ip++;
        return !_evalTestSection(code, frame);

      default:
        throw AgiException('Unknown test opcode 0x${curVal.toRadixString(16).padLeft(2, '0')} ($curVal)');
    }
  }

  InterpreterStatus _execAction(int opcode, Uint8List code, AgiCallFrame frame) {
    switch (opcode) {
      case 0: // return
        callStack.removeLast();
        break;

      case 1: // increment(%v)
        memory.incrementVar(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 2: // decrement(%v)
        memory.decrementVar(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 3: // assignn(%v, n)
        memory.setVar(code[frame.ip + 1], code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 4: // assignv(%v1, %v2)
        memory.setVar(code[frame.ip + 1], memory.getVar(code[frame.ip + 2]));
        frame.ip += 3;
        break;

      case 5: // addn(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        memory.setVar(v, memory.getVar(v) + n);
        frame.ip += 3;
        break;

      case 6: // addv(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        memory.setVar(v1, memory.getVar(v1) + memory.getVar(v2));
        frame.ip += 3;
        break;

      case 7: // subn(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        memory.setVar(v, memory.getVar(v) - n);
        frame.ip += 3;
        break;

      case 8: // subv(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        memory.setVar(v1, memory.getVar(v1) - memory.getVar(v2));
        frame.ip += 3;
        break;

      case 9: // lindirectv(%v1, %v2)
        final v1 = memory.getVar(code[frame.ip + 1]);
        final val = memory.getVar(code[frame.ip + 2]);
        memory.setVar(v1, val);
        frame.ip += 3;
        break;

      case 10: // rindirect(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = memory.getVar(code[frame.ip + 2]);
        memory.setVar(v1, memory.getVar(v2));
        frame.ip += 3;
        break;

      case 11: // lindirectn(%v, n)
        final v = memory.getVar(code[frame.ip + 1]);
        final n = code[frame.ip + 2];
        memory.setVar(v, n);
        frame.ip += 3;
        break;

      case 12: // set(%f)
        memory.setFlag(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 13: // reset(%f)
        memory.resetFlag(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 14: // toggle(%f)
        memory.toggleFlag(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 15: // set.v(%v)
        memory.setFlag(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 16: // reset.v(%v)
        memory.resetFlag(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 17: // toggle.v(%v)
        memory.toggleFlag(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 18: // new.room(n)
        final room = code[frame.ip + 1];
        frame.ip += 2;
        _doNewRoom(room);
        break;

      case 19: // new.room.v(%v)
        final room = memory.getVar(code[frame.ip + 1]);
        frame.ip += 2;
        _doNewRoom(room);
        break;

      case 20: // load.logics(n)
        delegate.loadLogic(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 21: // load.logics.v(%v)
        delegate.loadLogic(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 22: // call(n)
        final num = code[frame.ip + 1];
        frame.ip += 2;
        _doCall(num);
        break;

      case 23: // call.v(%v)
        final num = memory.getVar(code[frame.ip + 1]);
        frame.ip += 2;
        if (num != 0) _doCall(num);
        break;

      case 24: // load.pic(%v)
        delegate.onLoadPic(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 25: // draw.pic(%v)
        delegate.onDrawPic(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 26: // show.pic()
        delegate.onShowPic();
        frame.ip++;
        break;

      case 27: // discard.pic(%v)
        delegate.onDiscardPic(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 28: // overlay.pic(%v)
        delegate.onOverlayPic(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 29: // show.pri.screen()
        delegate.onShowPriScreen();
        frame.ip++;
        break;

      case 30: // load.view(n)
        delegate.onLoadView(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 31: // load.view.v(%v)
        delegate.onLoadView(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 32: // discard.view(n)
        delegate.onDiscardView(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 33: // animate.obj(o)
        final obj = getObj(code[frame.ip + 1]);
        if (!obj.isAnimated) {
          obj.isAnimated = true;
          obj.isUpdating = true;
          obj.isCycling = true;
          obj.motionType = 0;
          obj.cycleMode = 0;
          obj.direction = 0;
          obj.ignoreBlocks = false;
          obj.ignoreHorizon = false;
          obj.ignoreObjects = false;
          obj.fixedPriority = false;
          obj.fixedLoop = false;
        }
        frame.ip += 2;
        break;

      case 34: // unanimate.all()
        for (final o in animatedObjects) {
          o.isAnimated = false;
          o.isDrawn = false;
        }
        frame.ip++;
        break;

      case 35: // draw(o)
        final obj = getObj(code[frame.ip + 1]);
        obj.isDrawn = true;
        obj.isAnimated = true;
        delegate.onDraw(obj);
        frame.ip += 2;
        break;

      case 36: // erase(o)
        getObj(code[frame.ip + 1]).isDrawn = false;
        frame.ip += 2;
        break;

      case 37: // position(o, x, y)
        final o = getObj(code[frame.ip + 1]);
        o.x = code[frame.ip + 2];
        o.y = code[frame.ip + 3];
        o.prevX = o.x;
        o.prevY = o.y;
        if (o.isDrawn) {
          delegate.onDraw(o);
        }
        frame.ip += 4;
        break;

      case 38: // position.v(o, %vx, %vy)
        final o = getObj(code[frame.ip + 1]);
        o.x = memory.getVar(code[frame.ip + 2]);
        o.y = memory.getVar(code[frame.ip + 3]);
        o.prevX = o.x;
        o.prevY = o.y;
        if (o.isDrawn) {
          delegate.onDraw(o);
        }
        frame.ip += 4;
        break;

      case 39: // get.posn(o, %vx, %vy)
        final o = getObj(code[frame.ip + 1]);
        memory.setVar(code[frame.ip + 2], o.x);
        memory.setVar(code[frame.ip + 3], o.y);
        frame.ip += 4;
        break;

      case 40: // reposition(o, %vdx, %vdy)
        final o = getObj(code[frame.ip + 1]);
        var dx = memory.getVar(code[frame.ip + 2]);
        if (dx >= 128) dx -= 256;
        var dy = memory.getVar(code[frame.ip + 3]);
        if (dy >= 128) dy -= 256;
        o.x = (o.x + dx).clamp(0, 159);
        o.y = (o.y + dy).clamp(0, 167);
        o.prevX = o.x;
        o.prevY = o.y;
        if (o.isDrawn) {
          delegate.onDraw(o);
        }
        frame.ip += 4;
        break;

      case 41: // set.view(o, v)
        final objV41 = getObj(code[frame.ip + 1]);
        final newV41 = code[frame.ip + 2];
        if (objV41.view != newV41) {
          objV41.view = newV41;
          objV41.loop = 0;
          objV41.cel = 0;
        }
        if (objV41.number == 0) {
          memory.setVar(16, newV41);
        }
        frame.ip += 3;
        break;

      case 42: // set.view.v(o, %v)
        final objV42 = getObj(code[frame.ip + 1]);
        final newV42 = memory.getVar(code[frame.ip + 2]);
        if (objV42.view != newV42) {
          objV42.view = newV42;
          objV42.loop = 0;
          objV42.cel = 0;
        }
        if (objV42.number == 0) {
          memory.setVar(16, newV42);
        }
        frame.ip += 3;
        break;

      case 43: // set.loop(o, l)
        getObj(code[frame.ip + 1]).loop = code[frame.ip + 2];
        frame.ip += 3;
        break;

      case 44: // set.loop.v(o, %v)
        getObj(code[frame.ip + 1]).loop = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 45: // fix.loop(o)
        getObj(code[frame.ip + 1]).fixedLoop = true;
        frame.ip += 2;
        break;

      case 46: // release.loop(o)
        getObj(code[frame.ip + 1]).fixedLoop = false;
        frame.ip += 2;
        break;

      case 47: // set.cel(o, c)
        getObj(code[frame.ip + 1]).cel = code[frame.ip + 2];
        frame.ip += 3;
        break;

      case 48: // set.cel.v(o, %v)
        getObj(code[frame.ip + 1]).cel = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 49: // last.cel(o, %v)
        final obj = getObj(code[frame.ip + 1]);
        final view = delegate.getView(obj.view);
        final loop = view?.getLoop(obj.loop);
        if (loop != null && loop.celCount > 0) {
          memory.setVar(code[frame.ip + 2], loop.celCount - 1);
        } else {
          memory.setVar(code[frame.ip + 2], obj.cel);
        }
        frame.ip += 3;
        break;

      case 50: // current.cel(o, %v)
        memory.setVar(code[frame.ip + 2], getObj(code[frame.ip + 1]).cel);
        frame.ip += 3;
        break;

      case 51: // current.loop(o, %v)
        memory.setVar(code[frame.ip + 2], getObj(code[frame.ip + 1]).loop);
        frame.ip += 3;
        break;

      case 52: // current.view(o, %v)
        memory.setVar(code[frame.ip + 2], getObj(code[frame.ip + 1]).view);
        frame.ip += 3;
        break;

      case 53: // number.of.loops(o, %v)
        final obj = getObj(code[frame.ip + 1]);
        final view = delegate.getView(obj.view);
        memory.setVar(code[frame.ip + 2], view?.loopCount ?? 1);
        frame.ip += 3;
        break;

      case 54: // set.priority(o, p)
        final o = getObj(code[frame.ip + 1]);
        o.priority = code[frame.ip + 2];
        o.fixedPriority = true;
        frame.ip += 3;
        break;

      case 55: // set.priority.v(o, %v)
        final o = getObj(code[frame.ip + 1]);
        o.priority = memory.getVar(code[frame.ip + 2]);
        o.fixedPriority = true;
        frame.ip += 3;
        break;

      case 56: // release.priority(o)
        getObj(code[frame.ip + 1]).fixedPriority = false;
        frame.ip += 2;
        break;

      case 57: // get.priority(o, %v)
        memory.setVar(code[frame.ip + 2], getObj(code[frame.ip + 1]).effectivePriority);
        frame.ip += 3;
        break;

      case 58: // stop.update(o)
        getObj(code[frame.ip + 1]).isUpdating = false;
        frame.ip += 2;
        break;

      case 59: // start.update(o)
        getObj(code[frame.ip + 1]).isUpdating = true;
        frame.ip += 2;
        break;

      case 60: // force.update(o)
        frame.ip += 2;
        break;

      case 61: // ignore.horizon(o)
        getObj(code[frame.ip + 1]).ignoreHorizon = true;
        frame.ip += 2;
        break;

      case 62: // observe.horizon(o)
        getObj(code[frame.ip + 1]).ignoreHorizon = false;
        frame.ip += 2;
        break;

      case 63: // set.horizon(n)
        delegate.onSetHorizon(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 64: // object.on.water(o)
        final o64 = getObj(code[frame.ip + 1]);
        o64.onWater = true;
        o64.onLand = false;
        frame.ip += 2;
        break;

      case 65: // object.on.land(o)
        final o65 = getObj(code[frame.ip + 1]);
        o65.onLand = true;
        o65.onWater = false;
        frame.ip += 2;
        break;

      case 66: // object.on.anything(o)
        final o66 = getObj(code[frame.ip + 1]);
        o66.onWater = false;
        o66.onLand = false;
        frame.ip += 2;
        break;

      case 67: // ignore.objs(o)
        getObj(code[frame.ip + 1]).ignoreObjects = true;
        frame.ip += 2;
        break;

      case 68: // observe.objs(o)
        getObj(code[frame.ip + 1]).ignoreObjects = false;
        frame.ip += 2;
        break;

      case 69: // distance(o1, o2, %v)
        final o1 = getObj(code[frame.ip + 1]);
        final o2 = getObj(code[frame.ip + 2]);
        final dist = (o1.x - o2.x).abs() + (o1.y - o2.y).abs();
        memory.setVar(code[frame.ip + 3], dist.clamp(0, 255));
        frame.ip += 4;
        break;

      case 70: // stop.cycling(o)
        getObj(code[frame.ip + 1]).isCycling = false;
        frame.ip += 2;
        break;

      case 71: // start.cycling(o)
        getObj(code[frame.ip + 1]).isCycling = true;
        frame.ip += 2;
        break;

      case 72: // normal.cycle(o)
        final o = getObj(code[frame.ip + 1]);
        o.cycleMode = 0;
        o.isCycling = true;
        frame.ip += 2;
        break;

      case 73: // end.of.loop(o, f)
        final o = getObj(code[frame.ip + 1]);
        final flagNum = code[frame.ip + 2];
        o.cycleMode = 2;
        o.endOfLoopFlag = flagNum;
        o.isCycling = true;
        memory.resetFlag(flagNum);
        frame.ip += 3;
        break;

      case 74: // reverse.cycle(o)
        final o = getObj(code[frame.ip + 1]);
        o.cycleMode = 1;
        o.isCycling = true;
        frame.ip += 2;
        break;

      case 75: // reverse.loop(o, f)
        final o = getObj(code[frame.ip + 1]);
        final flagNum = code[frame.ip + 2];
        o.cycleMode = 3;
        o.endOfLoopFlag = flagNum;
        o.isCycling = true;
        memory.resetFlag(flagNum);
        frame.ip += 3;
        break;

      case 76: // cycle.time(o, %v)
        getObj(code[frame.ip + 1]).cycleTime = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 77: // stop.motion(o)
        final objNum77 = code[frame.ip + 1];
        final o = getObj(objNum77);
        o.direction = 0;
        o.motionType = 0;
        if (objNum77 == 0) {
          memory.setVar(6, 0);
          delegate.onUserControl(false);
        }
        frame.ip += 2;
        break;

      case 78: // start.motion(o)
        final objNum78 = code[frame.ip + 1];
        getObj(objNum78).motionType = 0;
        if (objNum78 == 0) {
          memory.setVar(6, 0);
          delegate.onUserControl(true);
        }
        frame.ip += 2;
        break;

      case 79: // step.size(o, %v)
        getObj(code[frame.ip + 1]).stepSize = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 80: // step.time(o, %v)
        getObj(code[frame.ip + 1]).stepTime = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 81: // move.obj(o, x, y, step, f)
        final objNum81 = code[frame.ip + 1];
        final o = getObj(objNum81);
        o.motionType = 3;
        o.targetX = code[frame.ip + 2];
        o.targetY = code[frame.ip + 3];
        final step81 = code[frame.ip + 4];
        o.stepDistance = step81;
        if (step81 != 0) {
          o.stepSize = step81;
        }
        final targetFlag81 = code[frame.ip + 5];
        o.targetFlag = targetFlag81;
        memory.resetFlag(targetFlag81);
        if (objNum81 == 0) {
          if (o.x == o.targetX && o.y == o.targetY) {
            o.motionType = 0;
            o.direction = 0;
            memory.setVar(6, 0);
            memory.setFlag(targetFlag81);
            o.targetFlag = null;
            delegate.onUserControl(true);
          } else {
            delegate.onUserControl(false);
          }
        }
        frame.ip += 6;
        break;

      case 82: // move.obj.v(o, %vx, %vy, step, f)
        final objNum82 = code[frame.ip + 1];
        final o = getObj(objNum82);
        o.motionType = 3;
        o.targetX = memory.getVar(code[frame.ip + 2]);
        o.targetY = memory.getVar(code[frame.ip + 3]);
        final step82 = memory.getVar(code[frame.ip + 4]);
        o.stepDistance = step82;
        if (step82 != 0) {
          o.stepSize = step82;
        }
        final targetFlag82 = code[frame.ip + 5];
        o.targetFlag = targetFlag82;
        memory.resetFlag(targetFlag82);
        if (objNum82 == 0) {
          if (o.x == o.targetX && o.y == o.targetY) {
            o.motionType = 0;
            o.direction = 0;
            memory.setVar(6, 0);
            memory.setFlag(targetFlag82);
            o.targetFlag = null;
            delegate.onUserControl(true);
          } else {
            delegate.onUserControl(false);
          }
        }
        frame.ip += 6;
        break;

      case 83: // follow.ego(o, step, f)
        final objNum83 = code[frame.ip + 1];
        final o = getObj(objNum83);
        o.motionType = 2;
        o.stepDistance = code[frame.ip + 2];
        final targetFlag83 = code[frame.ip + 3];
        o.targetFlag = targetFlag83;
        memory.resetFlag(targetFlag83);
        if (objNum83 == 0) {
          delegate.onUserControl(false);
        }
        frame.ip += 4;
        break;

      case 84: // wander(o)
        final objNum84 = code[frame.ip + 1];
        getObj(objNum84).motionType = 1;
        if (objNum84 == 0) {
          delegate.onUserControl(false);
        }
        frame.ip += 2;
        break;

      case 85: // normal.motion(o)
        final objNum85 = code[frame.ip + 1];
        getObj(objNum85).motionType = 0;
        if (objNum85 == 0) {
          delegate.onUserControl(true);
        }
        frame.ip += 2;
        break;

      case 86: // set.dir(o, %v)
        getObj(code[frame.ip + 1]).direction = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 87: // get.dir(o, %v)
        memory.setVar(code[frame.ip + 2], getObj(code[frame.ip + 1]).direction);
        frame.ip += 3;
        break;

      case 88: // ignore.blocks(o)
        getObj(code[frame.ip + 1]).ignoreBlocks = true;
        frame.ip += 2;
        break;

      case 89: // observe.blocks(o)
        getObj(code[frame.ip + 1]).ignoreBlocks = false;
        frame.ip += 2;
        break;

      case 90: // block(x1, y1, x2, y2)
        delegate.onBlock(
          code[frame.ip + 1],
          code[frame.ip + 2],
          code[frame.ip + 3],
          code[frame.ip + 4],
        );
        frame.ip += 5;
        break;

      case 91: // unblock()
        delegate.onUnblock();
        frame.ip++;
        break;

      case 92: // get(i)
        memory.itemRooms[code[frame.ip + 1]] = 255;
        frame.ip += 2;
        break;

      case 93: // get.v(%v)
        memory.itemRooms[memory.getVar(code[frame.ip + 1])] = 255;
        frame.ip += 2;
        break;

      case 94: // drop(i)
        memory.itemRooms[code[frame.ip + 1]] = 0;
        frame.ip += 2;
        break;

      case 95: // put(i, %v)
        memory.itemRooms[code[frame.ip + 1]] = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 96: // put.v(%v1, %v2)
        memory.itemRooms[memory.getVar(code[frame.ip + 1])] = memory.getVar(code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 97: // get.room.v(%v1, %v2)
        final item = memory.getVar(code[frame.ip + 1]);
        memory.setVar(code[frame.ip + 2], memory.itemRooms[item] ?? 0xFF);
        frame.ip += 3;
        break;

      case 98: // load.sound(n)
        frame.ip += 2;
        break;

      case 99: // sound(n, f)
        delegate.onSound(code[frame.ip + 1], code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 100: // stop.sound()
        delegate.onStopSound();
        frame.ip++;
        break;

      case 101: // print(m)
        final m = code[frame.ip + 1];
        frame.ip += 2;
        final leaveWin = memory.getFlag(15);
        if (leaveWin) {
          memory.resetFlag(15);
          delegate.onPrint(frame.script.getMessage(m), isModal: false);
        } else {
          final timeout = memory.getVar(21);
          memory.setVar(21, 0);
          delegate.onPrint(frame.script.getMessage(m), isModal: true, timeoutHalfSeconds: timeout);
          _pendingYield = true;
          return InterpreterStatus.yielded;
        }
        break;

      case 102: // print.v(%v)
        final v = code[frame.ip + 1];
        final msgNum = memory.getVar(v);
        frame.ip += 2;
        final leaveWin = memory.getFlag(15);
        if (leaveWin) {
          memory.resetFlag(15);
          delegate.onPrint(frame.script.getMessage(msgNum), isModal: false);
        } else {
          final timeout = memory.getVar(21);
          memory.setVar(21, 0);
          delegate.onPrint(frame.script.getMessage(msgNum), isModal: true, timeoutHalfSeconds: timeout);
          _pendingYield = true;
          return InterpreterStatus.yielded;
        }
        break;

      case 103: // display(row, col, m)
        delegate.onDisplay(
          code[frame.ip + 1],
          code[frame.ip + 2],
          frame.script.getMessage(code[frame.ip + 3]),
        );
        frame.ip += 4;
        break;

      case 104: // display.v(%vr, %vc, %vm)
        delegate.onDisplay(
          memory.getVar(code[frame.ip + 1]),
          memory.getVar(code[frame.ip + 2]),
          frame.script.getMessage(memory.getVar(code[frame.ip + 3])),
        );
        frame.ip += 4;
        break;

      case 105: // clear.lines(top, bottom, color)
        delegate.onClearLines(code[frame.ip + 1], code[frame.ip + 2], code[frame.ip + 3]);
        frame.ip += 4;
        break;

      case 106: // text.screen()
        delegate.onTextScreen();
        frame.ip++;
        break;

      case 107: // graphics()
        delegate.onGraphics();
        frame.ip++;
        break;

      case 108: // set.cursor.char(m)
        frame.ip += 2;
        break;

      case 109: // set.text.attribute(fg, bg)
        delegate.onSetTextAttribute(code[frame.ip + 1], code[frame.ip + 2]);
        frame.ip += 3;
        break;

      case 110: // shake.screen(n)
        delegate.onShakeScreen(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 111: // configure.screen(playTop, inputLine, statusLine)
        delegate.onConfigureScreen(
          code[frame.ip + 1],
          code[frame.ip + 2],
          code[frame.ip + 3],
        );
        frame.ip += 4;
        break;

      case 112: // status.line.on()
        delegate.onStatusLine(true);
        frame.ip++;
        break;

      case 113: // status.line.off()
        delegate.onStatusLine(false);
        frame.ip++;
        break;

      case 114: // set.string(s, m)
        memory.setString(code[frame.ip + 1], frame.script.getMessage(code[frame.ip + 2]));
        frame.ip += 3;
        break;

      case 115: // get.string(s, m, row, col, maxLen)
        final s = code[frame.ip + 1];
        final m = code[frame.ip + 2];
        final row = code[frame.ip + 3];
        final col = code[frame.ip + 4];
        final maxLen = code[frame.ip + 5];
        final prompt = frame.script.getMessage(m);
        frame.ip += 6;
        _pendingInputCallback = (value) {
          if (value != null) {
            final clamped = maxLen > 0 && value.length > maxLen ? value.substring(0, maxLen) : value;
            memory.setString(s, clamped);
          }
        };
        delegate.onGetString(prompt, row, col, maxLen);
        return InterpreterStatus.yielded;

      case 116: // word.to.string(w, s)
        final w = code[frame.ip + 1];
        final s = code[frame.ip + 2];
        final word = delegate.wordToString(w) ?? (delegate.dictionary?.idToWords(w).firstOrNull ?? '');
        memory.setString(s, word);
        frame.ip += 3;
        break;

      case 117: // parse(s)
        final s = code[frame.ip + 1];
        final str = memory.getString(s);
        delegate.onParse(str);
        frame.ip += 2;
        break;

      case 118: // get.num(m, %v)
        final m = code[frame.ip + 1];
        final v = code[frame.ip + 2];
        final prompt = frame.script.getMessage(m);
        frame.ip += 3;
        _pendingInputCallback = (value) {
          if (value != null) {
            final num = int.tryParse(value) ?? 0;
            memory.setVar(v, num.clamp(0, 255));
          }
        };
        delegate.onGetNum(prompt);
        return InterpreterStatus.yielded;

      case 119: // prevent.input()
        delegate.onInputMode(false);
        frame.ip++;
        break;

      case 120: // accept.input()
        delegate.onInputMode(true);
        frame.ip++;
        break;

      case 121: // set.key(ascii_low, scancode_high, ctl)
        delegate.onSetKey(
          code[frame.ip + 2], // scancode (high byte)
          code[frame.ip + 1], // ascii (low byte)
          code[frame.ip + 3], // controller code
        );
        frame.ip += 4;
        break;

      case 122: // add.to.pic(view, loop, cel, x, y, pri, boxPri)
        delegate.onAddToPic(
          code[frame.ip + 1],
          code[frame.ip + 2],
          code[frame.ip + 3],
          code[frame.ip + 4],
          code[frame.ip + 5],
          code[frame.ip + 6],
          code[frame.ip + 7],
        );
        frame.ip += 8;
        break;

      case 123: // add.to.pic.v(%vv, %vl, %vc, %vx, %vy, %vp, %vb)
        delegate.onAddToPic(
          memory.getVar(code[frame.ip + 1]),
          memory.getVar(code[frame.ip + 2]),
          memory.getVar(code[frame.ip + 3]),
          memory.getVar(code[frame.ip + 4]),
          memory.getVar(code[frame.ip + 5]),
          memory.getVar(code[frame.ip + 6]),
          memory.getVar(code[frame.ip + 7]),
        );
        frame.ip += 8;
        break;

      case 124: // status()
        delegate.onStatus();
        frame.ip++;
        break;

      case 125: // save.game()
        delegate.onSaveGame();
        frame.ip++;
        break;

      case 126: // restore.game()
        delegate.onRestoreGame();
        frame.ip++;
        break;

      case 127: // init.disk()
        frame.ip++;
        break;

      case 128: // restart.game()
        delegate.onRestartGame();
        frame.ip++;
        break;

      case 129: // show.obj(i)
        delegate.onShowObj(code[frame.ip + 1]);
        frame.ip += 2;
        break;

      case 130: // random(lower, upper, %v)
        final lower = code[frame.ip + 1];
        final upper = code[frame.ip + 2];
        final v = code[frame.ip + 3];
        final val = lower <= upper ? (lower + rng.nextInt(upper - lower + 1)) : lower;
        memory.setVar(v, val);
        frame.ip += 4;
        break;

      case 131: // program.control()
        delegate.onUserControl(false);
        frame.ip++;
        break;

      case 132: // player.control()
        final egoObj = getObj(0);
        egoObj.motionType = 0;
        egoObj.isCycling = true;
        egoObj.isUpdating = true;
        egoObj.isAnimated = true;
        delegate.onUserControl(true);
        frame.ip++;
        break;

      case 133: // obj.status.v(%v)
        frame.ip += 2;
        break;

      case 134: // quit
        final numArgs = (version < 2.090) ? 0 : 1;
        frame.ip += 1 + numArgs;
        delegate.onQuit();
        isHalted = true;
        break;

      case 135: // show.mem()
        frame.ip++;
        break;

      case 136: // pause()
        delegate.onPause();
        frame.ip++;
        break;

      case 137: // echo.line()
        frame.ip++;
        break;

      case 138: // cancel.line()
        frame.ip++;
        break;

      case 139: // init.joy()
        frame.ip++;
        break;

      case 140: // toggle.monitor()
        frame.ip++;
        break;

      case 141: // version()
        frame.ip++;
        break;

      case 142: // script.size(n)
        frame.ip += 2;
        break;

      case 143: // set.game.id(m)
        frame.ip += 2;
        break;

      case 144: // log(m)
        delegate.onLog(frame.script.getMessage(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 145: // set.scan.start()
        memory.setScanStart(frame.scriptNumber, frame.ip + 1);
        frame.ip++;
        break;

      case 146: // reset.scan.start()
        memory.resetScanStart(frame.scriptNumber);
        frame.ip++;
        break;

      case 147: // reposition.to(o, x, y)
        final o = getObj(code[frame.ip + 1]);
        o.x = code[frame.ip + 2];
        o.y = code[frame.ip + 3];
        frame.ip += 4;
        break;

      case 148: // reposition.to.v(o, %vx, %vy)
        final o = getObj(code[frame.ip + 1]);
        o.x = memory.getVar(code[frame.ip + 2]);
        o.y = memory.getVar(code[frame.ip + 3]);
        frame.ip += 4;
        break;

      case 149: // trace.on()
        frame.ip++;
        break;

      case 150: // trace.info(n, n, n)
        frame.ip += 4;
        break;

      case 151: // print.at(m, x, y, width)
        final numArgs = (version < 2.401) ? 3 : 4;
        final m = code[frame.ip + 1];
        final x = code[frame.ip + 2];
        final y = code[frame.ip + 3];
        final w = numArgs == 4 ? code[frame.ip + 4] : 0;
        frame.ip += 1 + numArgs;
        final leaveWin = memory.getFlag(15);
        if (leaveWin) {
          memory.resetFlag(15);
          delegate.onPrintAt(frame.script.getMessage(m), x, y, w, isModal: false);
        } else {
          final timeout = memory.getVar(21);
          memory.setVar(21, 0);
          delegate.onPrintAt(frame.script.getMessage(m), x, y, w, isModal: true, timeoutHalfSeconds: timeout);
          _pendingYield = true;
          return InterpreterStatus.yielded;
        }
        break;

      case 152: // print.at.v(%vm, x, y, width)
        final numArgs = (version < 2.401) ? 3 : 4;
        final msgNum = memory.getVar(code[frame.ip + 1]);
        final x = code[frame.ip + 2];
        final y = code[frame.ip + 3];
        final w = numArgs == 4 ? code[frame.ip + 4] : 0;
        frame.ip += 1 + numArgs;
        final leaveWin = memory.getFlag(15);
        if (leaveWin) {
          memory.resetFlag(15);
          delegate.onPrintAt(frame.script.getMessage(msgNum), x, y, w, isModal: false);
        } else {
          final timeout = memory.getVar(21);
          memory.setVar(21, 0);
          delegate.onPrintAt(frame.script.getMessage(msgNum), x, y, w, isModal: true, timeoutHalfSeconds: timeout);
          _pendingYield = true;
          return InterpreterStatus.yielded;
        }
        break;

      case 153: // discard.view.v(%v)
        delegate.onDiscardView(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 154: // clear.text.rect(top, left, bottom, right, color)
        delegate.onClearTextRect(
          code[frame.ip + 1],
          code[frame.ip + 2],
          code[frame.ip + 3],
          code[frame.ip + 4],
          code[frame.ip + 5],
        );
        frame.ip += 6;
        break;

      case 155: // set.upper.left(x, y)
        frame.ip += 3;
        break;

      case 156: // set.menu(m)
        frame.ip += 2;
        break;

      case 157: // set.menu.item(m, ctl)
        frame.ip += 3;
        break;

      case 158: // submit.menu()
        frame.ip++;
        break;

      case 159: // enable.item(ctl)
        frame.ip += 2;
        break;

      case 160: // disable.item(ctl)
        frame.ip += 2;
        break;

      case 161: // menu.input()
        frame.ip++;
        break;

      case 162: // show.obj.v(%v)
        delegate.onShowObj(memory.getVar(code[frame.ip + 1]));
        frame.ip += 2;
        break;

      case 163: // open.dialogue()
        frame.ip++;
        break;

      case 164: // close.dialogue()
        frame.ip++;
        break;

      case 165: // mul.n(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        memory.setVar(v, memory.getVar(v) * n);
        frame.ip += 3;
        break;

      case 166: // mul.v(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = code[frame.ip + 2];
        memory.setVar(v1, memory.getVar(v1) * memory.getVar(v2));
        frame.ip += 3;
        break;

      case 167: // div.n(%v, n)
        final v = code[frame.ip + 1];
        final n = code[frame.ip + 2];
        if (n != 0) {
          memory.setVar(v, memory.getVar(v) ~/ n);
        }
        frame.ip += 3;
        break;

      case 168: // div.v(%v1, %v2)
        final v1 = code[frame.ip + 1];
        final v2 = memory.getVar(code[frame.ip + 2]);
        if (v2 != 0) {
          memory.setVar(v1, memory.getVar(v1) ~/ v2);
        }
        frame.ip += 3;
        break;

      case 169: // close.window()
        delegate.onCloseWindow();
        frame.ip++;
        break;

      default:
        // Handle unknown instructions by skipping their length or throwing
        if (opcode >= 170 && opcode <= 181) {
          final numArgs = switch (opcode) {
            170 || 174 || 175 || 177 => 1,
            179 => 4,
            180 => 2,
            176 => (version == 3.002086) ? 1 : 0,
            _ => 0,
          };
          frame.ip += 1 + numArgs;
        } else {
          throw AgiException('Unknown action opcode 0x${opcode.toRadixString(16).padLeft(2, '0')} ($opcode)');
        }
    }
    return InterpreterStatus.running;
  }

  void _doNewRoom(int room) {
    memory.setVar(1, memory.getVar(0)); // %v1 = previous room (%v0)
    memory.setVar(0, room); // %v0 = new room
    memory.setFlag(5); // %f5 = new room first execution
    memory.resetFlag(0); // %f0 = on water
    memory.resetFlag(1); // %f1 = obscured
    memory.resetFlag(2); // %f2 = input entered
    memory.resetFlag(3); // %f3 = signal touched
    memory.resetFlag(4); // %f4 = said accepted
    callStack.clear(); // unroll call stack
    memory.clearNonZeroScanStarts();
    _newRoomRequested = true;
    delegate.onNewRoom(room);
  }

  void _doCall(int scriptNum) {
    final subScript = delegate.loadLogic(scriptNum);
    if (subScript != null) {
      pushScript(subScript, scriptNumber: scriptNum, startIp: memory.getScanStart(scriptNum));
    }
  }
}
