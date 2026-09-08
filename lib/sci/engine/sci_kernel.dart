// SCI0 Kernel function dispatch table and implementations.

import 'dart:math';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';

typedef SciKernelFunc = SciReg Function(SciVM vm, int argc, List<SciReg> argv);

/// Kernel function entry in dispatch table.
class SciKernelEntry {
  final int id;
  final String name;
  final SciKernelFunc function;

  const SciKernelEntry(this.id, this.name, this.function);
}

/// SCI0 Kernel Function Dispatcher.
class SciKernel {
  final Map<int, SciKernelEntry> _entries = {};
  final Random _random = Random();

  // --- External Callbacks for UI & Graphics Engine (Stage 10 Hooks) ---
  void Function(int picNum, int showStyle)? onDrawPic;
  void Function(SciReg castList)? onAnimate;
  void Function(int windowId, int top, int left, int bottom, int right)? onNewWindow;
  void Function(int windowId)? onDisposeWindow;
  void Function(int kernelId, String name, int argc, List<SciReg> argv, SciReg result)?
      onKernelExecuted;

  int currentPort = 0;
  int picNotValid = 0;

  SciKernel() {
    _registerAll();
  }

  void _register(int id, String name, SciKernelFunc func) {
    _entries[id] = SciKernelEntry(id, name, func);
  }

  String getKernelName(int id) => _entries[id]?.name ?? 'k_0x${id.toRadixString(16)}';

  SciReg call(SciVM vm, int kernelId, int argc, List<SciReg> argv) {
    final entry = _entries[kernelId];
    SciReg result;
    if (entry != null) {
      result = entry.function(vm, argc, argv);
    } else {
      // Unimplemented stub returns 0
      result = const SciReg.fromInt(0);
    }

    onKernelExecuted?.call(kernelId, entry?.name ?? 'unknown', argc, argv, result);
    return result;
  }

  void _registerAll() {
    // 0x00..0x07: Lifecycle & Objects
    _register(0x00, 'Load', _kLoad);
    _register(0x01, 'UnLoad', _kUnload);
    _register(0x02, 'ScriptID', _kScriptID);
    _register(0x03, 'DisposeScript', _kDisposeScript);
    _register(0x04, 'Clone', _kClone);
    _register(0x05, 'DisposeClone', _kDisposeClone);
    _register(0x06, 'IsObject', _kIsObject);
    _register(0x07, 'RespondsTo', _kRespondsTo);

    // 0x08..0x12: Graphics & Views
    _register(0x08, 'DrawPic', _kDrawPic);
    _register(0x09, 'Show', _kShow);
    _register(0x0A, 'PicNotValid', _kPicNotValid);
    _register(0x0B, 'Animate', _kAnimate);
    _register(0x0C, 'SetNowSeen', _kSetNowSeen);
    _register(0x0D, 'NumLoops', _kNumLoops);
    _register(0x0E, 'NumCels', _kNumCels);
    _register(0x0F, 'CelWide', _kCelWide);
    _register(0x10, 'CelHigh', _kCelHigh);
    _register(0x11, 'DrawCel', _kDrawCel);
    _register(0x12, 'AddToPic', _kAddToPic);

    // 0x13..0x16: Windows & Ports
    _register(0x13, 'NewWindow', _kNewWindow);
    _register(0x14, 'GetPort', _kGetPort);
    _register(0x15, 'SetPort', _kSetPort);
    _register(0x16, 'DisposeWindow', _kDisposeWindow);

    // 0x17..0x1B: Controls & Display
    _register(0x17, 'DrawControl', _kStub);
    _register(0x18, 'HiliteControl', _kStub);
    _register(0x19, 'EditControl', _kStub);
    _register(0x1A, 'TextSize', _kTextSize);
    _register(0x1B, 'Display', _kDisplay);

    // 0x1C..0x23: Events, Coordinates, Menu
    _register(0x1C, 'GetEvent', _kGetEvent);
    _register(0x1D, 'GlobalToLocal', _kStub);
    _register(0x1E, 'LocalToGlobal', _kStub);
    _register(0x1F, 'MapKeyToDir', _kStub);
    _register(0x20, 'DrawMenuBar', _kStub);
    _register(0x21, 'MenuSelect', _kStub);
    _register(0x22, 'AddMenu', _kStub);
    _register(0x23, 'DrawStatus', _kStub);

    // 0x24..0x28: Parser, Mouse, Cursor
    _register(0x24, 'Parse', _kParse);
    _register(0x25, 'Said', _kSaid);
    _register(0x26, 'SetSynonyms', _kStub);
    _register(0x27, 'HaveMouse', _kHaveMouse);
    _register(0x28, 'SetCursor', _kStub);

    // 0x29..0x2C: SCI0 FileIO
    _register(0x29, 'FOpen', _kStub);
    _register(0x2A, 'FPuts', _kStub);
    _register(0x2B, 'FGets', _kStub);
    _register(0x2C, 'FClose', _kStub);

    // 0x2D..0x31: Game state & Sound
    _register(0x2D, 'SaveGame', _kStub);
    _register(0x2E, 'RestoreGame', _kStub);
    _register(0x2F, 'RestartGame', _kStub);
    _register(0x30, 'GameIsRestarting', _kStub);
    _register(0x31, 'DoSound', _kStub);

    // 0x32..0x3F: Doubly-Linked Lists
    _register(0x32, 'NewList', _kNewList);
    _register(0x33, 'DisposeList', _kDisposeList);
    _register(0x34, 'NewNode', _kNewNode);
    _register(0x35, 'FirstNode', _kFirstNode);
    _register(0x36, 'LastNode', _kLastNode);
    _register(0x37, 'EmptyList', _kEmptyList);
    _register(0x38, 'NextNode', _kNextNode);
    _register(0x39, 'PrevNode', _kPrevNode);
    _register(0x3A, 'NodeValue', _kNodeValue);
    _register(0x3B, 'AddAfter', _kAddAfter);
    _register(0x3C, 'AddToFront', _kAddToFront);
    _register(0x3D, 'AddToEnd', _kAddToEnd);
    _register(0x3E, 'FindKey', _kFindKey);
    _register(0x3F, 'DeleteKey', _kDeleteKey);

    // 0x40..0x46: Math & Timing
    _register(0x40, 'Random', _kRandom);
    _register(0x41, 'Abs', _kAbs);
    _register(0x42, 'Sqrt', _kSqrt);
    _register(0x43, 'GetAngle', _kGetAngle);
    _register(0x44, 'GetDistance', _kGetDistance);
    _register(0x45, 'Wait', _kWait);
    _register(0x46, 'GetTime', _kGetTime);

    // 0x47..0x4E: Strings
    _register(0x47, 'StrEnd', _kStrEnd);
    _register(0x48, 'StrCat', _kStrCat);
    _register(0x49, 'StrCmp', _kStrCmp);
    _register(0x4A, 'StrLen', _kStrLen);
    _register(0x4B, 'StrCpy', _kStrCpy);
    _register(0x4C, 'Format', _kFormat);
    _register(0x4D, 'GetFarText', _kGetFarText);
    _register(0x4E, 'ReadNumber', _kReadNumber);

    // 0x4F..0x55: Motion & Physics
    _register(0x4F, 'BaseSetter', _kBaseSetter);
    _register(0x50, 'DirLoop', _kDirLoop);
    _register(0x51, 'CanBeHere', _kCanBeHere);
    _register(0x52, 'OnControl', _kOnControl);
    _register(0x53, 'InitBresen', _kStub);
    _register(0x54, 'DoBresen', _kStub);
    _register(0x55, 'DoAvoider', _kStub);

    // 0x56..0x67: Debugging & System
    _register(0x56, 'SetJump', _kStub);
    _register(0x57, 'SetDebug', _kStub);
    _register(0x58, 'InspectObj', _kStub);
    _register(0x59, 'ShowSends', _kStub);
    _register(0x5A, 'ShowObjs', _kStub);
    _register(0x5B, 'ShowFree', _kStub);
    _register(0x5C, 'MemoryInfo', _kStub);
    _register(0x5D, 'StackUsage', _kStub);
    _register(0x5E, 'Profiler', _kStub);
    _register(0x5F, 'GetMenu', _kStub);
    _register(0x60, 'SetMenu', _kStub);
    _register(0x61, 'GetSaveFiles', _kStub);
    _register(0x62, 'GetCWD', _kStub);
    _register(0x63, 'CheckFreeSpace', _kStub);
    _register(0x64, 'ValidPath', _kStub);
    _register(0x65, 'CoordPri', _kCoordPri);
    _register(0x66, 'StrAt', _kStrAt);
    _register(0x67, 'DeviceInfo', _kStub);
    _register(0x68, 'GetSaveDir', _kStub);
    _register(0x69, 'CheckSaveGame', _kStub);
    _register(0x6A, 'ShakeScreen', _kStub);
    _register(0x6B, 'FlushResources', _kStub);

    // 0x6C..0x71: Math & Graph
    _register(0x6C, 'SinMult', _kSinMult);
    _register(0x6D, 'CosMult', _kCosMult);
    _register(0x6E, 'SinDiv', _kSinDiv);
    _register(0x6F, 'CosDiv', _kCosDiv);
    _register(0x70, 'Graph', _kStub);
    _register(0x71, 'Joystick', _kStub);
  }

  // --- Default Stub ---
  SciReg _kStub(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  // --- Lifecycle & Objects ---

  SciReg _kLoad(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return SciReg.nullReg;
    final resType = argv[0].toUint16();
    final resNum = argv[1].toUint16();
    // In SCI0, scripts are loaded into memory
    if (resType == 0x81 && vm.volumeManager != null) {
      final seg = vm.segManager.instantiateScript(resNum, vm.volumeManager!);
      return SciReg.pointer(seg.segmentId, 0);
    }
    return SciReg.nullReg;
  }

  SciReg _kUnload(SciVM vm, int argc, List<SciReg> argv) => SciReg.nullReg;

  SciReg _kScriptID(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    final scriptNr = argv[0].toUint16();
    final exportIdx = argc >= 2 ? argv[1].toUint16() : 0;
    if (vm.volumeManager != null) {
      final scr = vm.segManager.instantiateScript(scriptNr, vm.volumeManager!);
      final off = scr.getExportOffset(exportIdx);
      if (off != null) {
        return SciReg.pointer(scr.segmentId, off);
      }
    }
    return SciReg.nullReg;
  }

  SciReg _kDisposeScript(SciVM vm, int argc, List<SciReg> argv) => SciReg.nullReg;

  SciReg _kClone(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    final obj = vm.segManager.getObject(argv[0]);
    if (obj != null) {
      final cloned = vm.segManager.cloneObject(obj);
      return cloned.pos;
    }
    return SciReg.nullReg;
  }

  SciReg _kDisposeClone(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) {
      vm.segManager.disposeClone(argv[0]);
    }
    return SciReg.nullReg;
  }

  SciReg _kIsObject(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final obj = vm.segManager.getObject(argv[0]);
    return SciReg.fromInt(obj != null ? 1 : 0);
  }

  SciReg _kRespondsTo(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final obj = vm.segManager.getObject(argv[0]);
    final selId = argv[1].toUint16();
    if (obj != null) {
      final varIdx = obj.locateVarSelector(vm.segManager, selId);
      if (varIdx >= 0) return const SciReg.fromInt(1);
      final meth = obj.lookupMethod(vm.segManager, selId);
      if (meth != null) return const SciReg.fromInt(1);
    }
    return const SciReg.fromInt(0);
  }

  // --- Graphics Stubs ---

  SciReg _kDrawPic(SciVM vm, int argc, List<SciReg> argv) {
    final picNum = argc >= 1 ? argv[0].toUint16() : 0;
    final showStyle = argc >= 2 ? argv[1].toUint16() : 0;
    onDrawPic?.call(picNum, showStyle);
    return const SciReg.fromInt(0);
  }

  SciReg _kShow(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  SciReg _kPicNotValid(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) {
      picNotValid = argv[0].toUint16();
    }
    return SciReg.fromInt(picNotValid);
  }

  SciReg _kAnimate(SciVM vm, int argc, List<SciReg> argv) {
    final castList = argc >= 1 ? argv[0] : SciReg.nullReg;
    onAnimate?.call(castList);
    return const SciReg.fromInt(0);
  }

  SciReg _kSetNowSeen(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kNumLoops(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(4);
  SciReg _kNumCels(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(4);
  SciReg _kCelWide(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(16);
  SciReg _kCelHigh(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(20);
  SciReg _kDrawCel(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kAddToPic(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  // --- Windows ---

  SciReg _kNewWindow(SciVM vm, int argc, List<SciReg> argv) {
    final top = argc >= 1 ? argv[0].toSint16() : 0;
    final left = argc >= 2 ? argv[1].toSint16() : 0;
    final bottom = argc >= 3 ? argv[2].toSint16() : 100;
    final right = argc >= 4 ? argv[3].toSint16() : 200;
    final winId = 1;
    onNewWindow?.call(winId, top, left, bottom, right);
    return SciReg.fromInt(winId);
  }

  SciReg _kGetPort(SciVM vm, int argc, List<SciReg> argv) => SciReg.fromInt(currentPort);
  SciReg _kSetPort(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) currentPort = argv[0].toUint16();
    return const SciReg.fromInt(0);
  }

  SciReg _kDisposeWindow(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) {
      onDisposeWindow?.call(argv[0].toUint16());
    }
    return const SciReg.fromInt(0);
  }

  SciReg _kTextSize(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kDisplay(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  // --- Parser & Events ---

  SciReg _kGetEvent(SciVM vm, int argc, List<SciReg> argv) {
    // Stubs event loop returning no events (type 0)
    if (argc >= 2) {
      final eventObj = vm.segManager.getObject(argv[1]);
      if (eventObj != null) {
        // Clear event type selector
        final typeSel = vm.selectors.findSelector('type') ?? 83;
        final typeIdx = eventObj.locateVarSelector(vm.segManager, typeSel);
        if (typeIdx >= 0) {
          eventObj.variables[typeIdx] = const SciReg.fromInt(0);
        }
      }
    }
    return const SciReg.fromInt(0);
  }

  SciReg _kParse(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kSaid(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kHaveMouse(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(1);

  // --- Lists & Nodes ---

  SciReg _kNewList(SciVM vm, int argc, List<SciReg> argv) => vm.segManager.newList();
  SciReg _kDisposeList(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) vm.segManager.disposeList(argv[0]);
    return SciReg.nullReg;
  }

  SciReg _kNewNode(SciVM vm, int argc, List<SciReg> argv) {
    final val = argc >= 1 ? argv[0] : SciReg.nullReg;
    final key = argc >= 2 ? argv[1] : SciReg.nullReg;
    return vm.segManager.newNode(val, key);
  }

  SciReg _kFirstNode(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return vm.segManager.firstNode(argv[0]);
  }

  SciReg _kLastNode(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return vm.segManager.lastNode(argv[0]);
  }

  SciReg _kEmptyList(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) vm.segManager.emptyList(argv[0]);
    return SciReg.nullReg;
  }

  SciReg _kNextNode(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return vm.segManager.nextNode(argv[0]);
  }

  SciReg _kPrevNode(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return vm.segManager.prevNode(argv[0]);
  }

  SciReg _kNodeValue(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return vm.segManager.nodeValue(argv[0]);
  }

  SciReg _kAddAfter(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 3) vm.segManager.addAfter(argv[0], argv[1], argv[2]);
    return SciReg.nullReg;
  }

  SciReg _kAddToFront(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 2) vm.segManager.addToFront(argv[0], argv[1]);
    return SciReg.nullReg;
  }

  SciReg _kAddToEnd(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 2) vm.segManager.addToEnd(argv[0], argv[1]);
    return SciReg.nullReg;
  }

  SciReg _kFindKey(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return SciReg.nullReg;
    return vm.segManager.findKey(argv[0], argv[1]);
  }

  SciReg _kDeleteKey(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 2) vm.segManager.deleteKey(argv[0], argv[1]);
    return SciReg.nullReg;
  }

  // --- Math & Timing ---

  SciReg _kRandom(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final minVal = argv[0].toSint16();
    final maxVal = argv[1].toSint16();
    if (minVal >= maxVal) return SciReg.fromInt(minVal);
    final val = minVal + _random.nextInt(maxVal - minVal + 1);
    return SciReg.fromInt(val);
  }

  SciReg _kAbs(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    return SciReg.fromInt(argv[0].toSint16().abs());
  }

  SciReg _kSqrt(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final v = argv[0].toSint16();
    return SciReg.fromInt(v > 0 ? sqrt(v).toInt() : 0);
  }

  SciReg _kGetAngle(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 4) return const SciReg.fromInt(0);
    final x1 = argv[0].toSint16();
    final y1 = argv[1].toSint16();
    final x2 = argv[2].toSint16();
    final y2 = argv[3].toSint16();
    final dx = x2 - x1;
    final dy = y2 - y1;
    var angle = (atan2(dx, -dy) * 180 / pi).round();
    if (angle < 0) angle += 360;
    return SciReg.fromInt(angle % 360);
  }

  SciReg _kGetDistance(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 4) return const SciReg.fromInt(0);
    final x1 = argv[0].toSint16();
    final y1 = argv[1].toSint16();
    final x2 = argv[2].toSint16();
    final y2 = argv[3].toSint16();
    final dx = x1 - x2;
    final dy = y1 - y2;
    return SciReg.fromInt(sqrt(dx * dx + dy * dy).round());
  }

  SciReg _kWait(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  SciReg _kGetTime(SciVM vm, int argc, List<SciReg> argv) {
    final mode = argc >= 1 ? argv[0].toUint16() : 0;
    final now = DateTime.now();
    if (mode == 1) {
      // Time in ticks (approx 60 Hz)
      return SciReg.fromInt((now.millisecondsSinceEpoch ~/ 16) & 0xFFFF);
    }
    // Time of day in seconds
    return SciReg.fromInt((now.hour * 3600 + now.minute * 60 + now.second) & 0xFFFF);
  }

  // --- Strings ---

  SciReg _kStrEnd(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return SciReg.nullReg;
    return argv[0];
  }

  SciReg _kStrCat(SciVM vm, int argc, List<SciReg> argv) => argc >= 1 ? argv[0] : SciReg.nullReg;
  SciReg _kStrCmp(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kStrLen(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kStrCpy(SciVM vm, int argc, List<SciReg> argv) => argc >= 1 ? argv[0] : SciReg.nullReg;
  SciReg _kFormat(SciVM vm, int argc, List<SciReg> argv) => argc >= 1 ? argv[0] : SciReg.nullReg;
  SciReg _kGetFarText(SciVM vm, int argc, List<SciReg> argv) => argc >= 3 ? argv[2] : SciReg.nullReg;
  SciReg _kReadNumber(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kStrAt(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  // --- Motion & Priority ---

  SciReg _kBaseSetter(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kDirLoop(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);
  SciReg _kCanBeHere(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(1);
  SciReg _kOnControl(SciVM vm, int argc, List<SciReg> argv) => const SciReg.fromInt(0);

  SciReg _kCoordPri(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final y = argv[0].toSint16();
    // Sierra priority bands: y < 42 is pri 0, then bands of 8..12
    if (y < 42) return const SciReg.fromInt(0);
    var pri = ((y - 42) ~/ 11) + 1;
    if (pri > 15) pri = 15;
    return SciReg.fromInt(pri);
  }

  // --- Trig (fixed-point scaled by 1000) ---

  SciReg _kSinMult(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final angle = argv[0].toSint16();
    final val = argv[1].toSint16();
    return SciReg.fromInt((sin(angle * pi / 180) * val).round());
  }

  SciReg _kCosMult(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final angle = argv[0].toSint16();
    final val = argv[1].toSint16();
    return SciReg.fromInt((cos(angle * pi / 180) * val).round());
  }

  SciReg _kSinDiv(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final angle = argv[0].toSint16();
    final val = argv[1].toSint16();
    final s = sin(angle * pi / 180);
    if (s.abs() < 0.0001) return const SciReg.fromInt(0);
    return SciReg.fromInt((val / s).round());
  }

  SciReg _kCosDiv(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final angle = argv[0].toSint16();
    final val = argv[1].toSint16();
    final c = cos(angle * pi / 180);
    if (c.abs() < 0.0001) return const SciReg.fromInt(0);
    return SciReg.fromInt((val / c).round());
  }
}
