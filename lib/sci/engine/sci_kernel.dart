import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';
import 'package:flutter_agigame/sci/view/sci_view.dart';
import 'package:flutter_agigame/sci/view/sci_view_parser.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

typedef SciKernelFunc = SciReg Function(SciVM vm, int argc, List<SciReg> argv);

/// Represents an input event in the SCI engine event queue.
class SciInputEvent {
  int type;
  int message;
  int modifiers;
  int x;
  int y;

  SciInputEvent({
    required this.type,
    required this.message,
    this.modifiers = 0,
    this.x = 0,
    this.y = 0,
  });
}

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

  SciSelectors? _selectors;
  SciSelectors get selectors => _selectors ??= SciSelectors();
  set selectors(SciSelectors s) => _selectors = s;

  SciVolumeManager? volumeManager;
  final Map<int, SciView> _viewCache = {};
  final Map<String, ui.Image> _celImages = {};

  SciPic? currentPic;
  final Uint8List priorityBands = Uint8List(200);
  int priorityBandCount = 14;
  int priorityTop = 42;
  int priorityBottom = 190;

  final List<SciInputEvent> eventQueue = [];
  int mouseX = 0;
  int mouseY = 0;

  List<PlayfieldActorSprite> currentSprites = [];

  // --- External Callbacks for UI & Graphics Engine (Stage 10 Hooks) ---
  void Function(int picNum, int showStyle)? onDrawPic;
  void Function(SciReg castList)? onAnimate;
  void Function(List<PlayfieldActorSprite> sprites)? onSpritesUpdated;
  void Function()? onShow;
  void Function(int windowId, int top, int left, int bottom, int right)? onNewWindow;
  void Function(int windowId)? onDisposeWindow;
  void Function(int kernelId, String name, int argc, List<SciReg> argv, SciReg result)?
      onKernelExecuted;

  int currentPort = 0;
  int picNotValid = 0;

  SciKernel() {
    initPriorityBands();
    _registerAll();
  }

  void _register(int id, String name, SciKernelFunc func) {
    _entries[id] = SciKernelEntry(id, name, func);
  }

  void registerKernel(int id, String name, SciKernelFunc func) {
    _register(id, name, func);
  }

  final List<String> recentCallLogs = [];

  String getKernelName(int id) => _entries[id]?.name ?? 'k_0x${id.toRadixString(16)}';

  SciReg call(SciVM vm, int kernelId, int argc, List<SciReg> argv) {
    final entry = _entries[kernelId];
    SciReg result;
    if (entry != null) {
      result = entry.function(vm, argc, argv);
    } else {
      // Unimplemented stub returns 0
      debugPrint('[SciKernel] Unimplemented kernel 0x${kernelId.toRadixString(16)} (${getKernelName(kernelId)}) called with argc=$argc, argv=$argv');
      result = const SciReg.fromInt(0);
    }

    final logLine = '0x${kernelId.toRadixString(16).padLeft(2, "0")} (${getKernelName(kernelId)}) args=[${argv.take(argc).map((a) => a.toString()).join(", ")}] -> ${result.toString()}';
    if (recentCallLogs.length >= 200) {
      recentCallLogs.removeAt(0);
    }
    recentCallLogs.add(logLine);

    onKernelExecuted?.call(kernelId, entry?.name ?? 'unknown', argc, argv, result);
    return result;
  }

  void initPriorityBands({
    List<int>? customBands,
    int bandCount = 14,
    int top = 42,
    int bottom = 190,
  }) {
    if (customBands != null && customBands.length >= 14) {
      int i = 0;
      for (int inx = 0; inx < 14; inx++) {
        final pri = customBands[inx];
        while (i < pri && i < 200) {
          priorityBands[i++] = inx;
        }
      }
      while (i < 200) {
        priorityBands[i++] = 14;
      }
    } else {
      priorityBandCount = bandCount;
      priorityTop = top;
      priorityBottom = bottom;
      final bandSize = ((bottom - top) * 2000) ~/ bandCount;
      for (int y = 0; y < top && y < 200; y++) {
        priorityBands[y] = 0;
      }
      for (int y = top; y < bottom && y < 200; y++) {
        priorityBands[y] = 1 + (((y - top) * 2000) ~/ bandSize);
      }
      for (int y = bottom; y < 200; y++) {
        priorityBands[y] = bandCount;
      }
    }
  }

  int coordinateToPriority(int y) {
    if (y < 0) return priorityBands[0];
    if (y >= 200) return priorityBands[199];
    return priorityBands[y];
  }

  SciView? getView(int viewId) {
    if (_viewCache.containsKey(viewId)) return _viewCache[viewId];
    if (volumeManager != null) {
      try {
        final bytes = volumeManager!.getResource(SciResourceType.view, viewId);
        final v = SciViewParser.parse(bytes, viewNumber: viewId);
        _viewCache[viewId] = v;
        return v;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void registerView(int viewId, SciView view) {
    _viewCache[viewId] = view;
  }

  ui.Image? getCelImage(int viewId, int loopNo, int celNo) {
    return _celImages['${viewId}_${loopNo}_$celNo'];
  }

  void cacheCelImage(int viewId, int loopNo, int celNo, ui.Image img) {
    _celImages['${viewId}_${loopNo}_$celNo'] = img;
  }

  int onControl(int screenMask, int left, int top, int right, int bottom) {
    if (currentPic == null) return 0;
    final pic = currentPic!;
    if (left >= right || top >= bottom) return 0;
    final l = left.clamp(0, 320);
    final r = right.clamp(0, 320);
    final t = top.clamp(0, 200);
    final b = bottom.clamp(0, 200);
    int result = 0;
    final isPri = (screenMask & 2) != 0;
    final buf = isPri ? pic.priorityPixels : pic.controlPixels;
    for (int y = t; y < b; y++) {
      final row = y * 320;
      for (int x = l; x < r; x++) {
        result |= 1 << buf[row + x];
      }
    }
    return result;
  }

  void postEvent(SciInputEvent ev) {
    eventQueue.add(ev);
  }

  void postDirectionEvent(int dir) {
    postEvent(SciInputEvent(type: 0x40, message: dir));
  }

  void postKeyEvent(int character, {int modifiers = 0}) {
    postEvent(SciInputEvent(type: 1, message: character, modifiers: modifiers));
  }

  void postMouseEvent(int type, int x, int y) {
    mouseX = x;
    mouseY = y;
    postEvent(SciInputEvent(type: type, message: 0, x: x, y: y));
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
    _register(0x1F, 'MapKeyToDir', _kMapKeyToDir);
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
    // In SCI0: 0x80=view, 0x81=pic, 0x82=script, 0x83=text, 0x84=sound, 0x85=memory, 0x86=vocab, 0x87=font, 0x88=cursor
    if ((resType & 0x7F) == 2 && vm.volumeManager != null) {
      if (vm.volumeManager!.resourceMap.find(SciResourceType.script, resNum) != null) {
        final seg = vm.segManager.instantiateScript(resNum, vm.volumeManager!);
        return SciReg.pointer(seg.segmentId, 0);
      }
    }
    return SciReg.fromInt(resNum);
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

  // --- Graphics & Views ---

  SciReg _kDrawPic(SciVM vm, int argc, List<SciReg> argv) {
    final picNum = argc >= 1 ? argv[0].toUint16() : 0;
    final showStyle = argc >= 2 ? argv[1].toUint16() : 0;
    final vmManager = volumeManager ?? vm.volumeManager;
    if (vmManager != null) {
      try {
        final picBytes = vmManager.getResource(SciResourceType.pic, picNum);
        final pic = SciPicInterpreter.interpret(
          picBytes,
          picNumber: picNum,
          computeSlices: true,
          computeUnditheredSlices: true,
        );
        currentPic = pic;
        if (pic.priorityBands != null) {
          initPriorityBands(customBands: pic.priorityBands);
        } else {
          initPriorityBands();
        }
      } catch (_) {
        // Fallback or ignore corrupt picture
      }
    }
    picNotValid = 1;
    onDrawPic?.call(picNum, showStyle);
    return const SciReg.fromInt(0);
  }

  SciReg _kShow(SciVM vm, int argc, List<SciReg> argv) {
    picNotValid = 0;
    onShow?.call();
    return const SciReg.fromInt(0);
  }

  SciReg _kPicNotValid(SciVM vm, int argc, List<SciReg> argv) {
    if (argc >= 1) {
      picNotValid = argv[0].toUint16();
    }
    return SciReg.fromInt(picNotValid);
  }

  SciReg _kAnimate(SciVM vm, int argc, List<SciReg> argv) {
    final castList = argc >= 1 ? argv[0] : SciReg.nullReg;
    onAnimate?.call(castList);

    if (castList.isNull || castList.offset == 0) {
      if (picNotValid != 0) {
        picNotValid = 0;
        onDrawPic?.call(currentPic?.picNumber ?? 0, 0);
      }
      return const SciReg.fromInt(0);
    }

    // Resolve list: cast can be a list or an object with an elements property
    SciList? list = vm.segManager.lookupList(castList);
    if (list == null) {
      final castObj = vm.segManager.getObject(castList);
      if (castObj != null) {
        final elemReg = castObj.getProp(vm.segManager, selectors.elements);
        list = vm.segManager.lookupList(elemReg);
      }
    }

    if (list == null) {
      if (picNotValid != 0) {
        picNotValid = 0;
        onDrawPic?.call(currentPic?.picNumber ?? 0, 0);
      }
      return const SciReg.fromInt(0);
    }

    final cycle = (argc >= 2) ? argv[1].toUint16() != 0 : true;
    final actors = vm.segManager.listElements(list);

    if (cycle && selectors.doit >= 0) {
      for (final actorReg in actors) {
        final actor = vm.segManager.getObject(actorReg);
        if (actor != null) {
          final signal = actor.getProp(vm.segManager, selectors.signal).toUint16();
          if ((signal & 0x0100) == 0) { // not frozen (kSignalFrozen)
            vm.sendSelector(actor.pos, selectors.doit, []);
          }
        }
      }
    }

    final sprites = <PlayfieldActorSprite>[];
    for (final actorReg in actors) {
      final actor = vm.segManager.getObject(actorReg);
      if (actor == null) continue;

      _kSetNowSeen(vm, 1, [actor.pos]);

      final signal = actor.getProp(vm.segManager, selectors.signal).toUint16();
      final y = actor.getProp(vm.segManager, selectors.y).toSint16();
      int pri;
      if ((signal & 0x0010) == 0) { // dynamic priority
        pri = coordinateToPriority(y);
        actor.setProp(vm.segManager, selectors.priority, SciReg.fromInt(pri));
      } else {
        pri = actor.getProp(vm.segManager, selectors.priority).toUint16();
      }

      if ((signal & 0x0088) != 0) { // hidden (0x0008) or removeView (0x0080)
        continue;
      }

      final viewId = actor.getProp(vm.segManager, selectors.view).toUint16();
      final loopNo = actor.getProp(vm.segManager, selectors.loop).toUint16();
      final celNo = actor.getProp(vm.segManager, selectors.cel).toUint16();
      final x = actor.getProp(vm.segManager, selectors.x).toSint16();
      final z = selectors.z >= 0 ? actor.getProp(vm.segManager, selectors.z).toSint16() : 0;
      final isUpdating = (signal & 0x0001) == 0; // stopUpdate flag

      final v = getView(viewId);
      int w = 16, h = 16, dispX = 0, dispY = 0;
      if (v != null && v.loops.isNotEmpty) {
        final l = v.loops[loopNo % v.loops.length];
        if (l.cels.isNotEmpty) {
          final c = l.cels[celNo % l.cels.length];
          w = c.width;
          h = c.height;
          dispX = c.displaceX;
          dispY = c.displaceY;
        }
      }

      final sprite = PlayfieldActorSprite(
        priority: pri,
        baselineY: y,
        objectNumber: actor.pos.offset,
        isUpdating: isUpdating,
        image: getCelImage(viewId, loopNo, celNo),
        position: ui.Offset(
          (x - (w >> 1)).toDouble(),
          (y - h + 1).toDouble(),
        ),
        viewNumber: viewId,
        loopNumber: loopNo,
        celNumber: celNo,
        scaleX: 1.0,
        scaleY: 1.0,
        displaceX: dispX,
        displaceY: dispY,
        z: z,
      );
      sprites.add(sprite);
    }

    sprites.sort((a, b) => PlayfieldActorSprite.compareDrawOrder(a, b));
    currentSprites = sprites;

    if (picNotValid != 0) {
      picNotValid = 0;
      onDrawPic?.call(currentPic?.picNumber ?? 0, 0);
    }

    onSpritesUpdated?.call(sprites);

    if (vm.yieldOnAnimate) {
      vm.yieldRequested = true;
    }

    return const SciReg.fromInt(0);
  }

  SciReg _kSetNowSeen(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return vm.acc;
    final obj = vm.segManager.getObject(argv[0]);
    if (obj == null) return vm.acc;

    final viewId = obj.getProp(vm.segManager, selectors.view).toUint16();
    var loopNo = obj.getProp(vm.segManager, selectors.loop).toUint16();
    var celNo = obj.getProp(vm.segManager, selectors.cel).toUint16();
    final x = obj.getProp(vm.segManager, selectors.x).toSint16();
    final y = obj.getProp(vm.segManager, selectors.y).toSint16();
    final z = selectors.z >= 0 ? obj.getProp(vm.segManager, selectors.z).toSint16() : 0;

    final v = getView(viewId);
    if (v != null && v.loops.isNotEmpty) {
      loopNo = loopNo % v.loops.length;
      final loop = v.loops[loopNo];
      if (loop.cels.isNotEmpty) {
        celNo = celNo % loop.cels.length;
        final cel = loop.cels[celNo];
        final nsLeft = x + cel.displaceX - (cel.width >> 1);
        final nsRight = nsLeft + cel.width;
        final nsBottom = y + cel.displaceY - z + 1;
        final nsTop = nsBottom - cel.height;

        obj.setProp(vm.segManager, selectors.nsLeft, SciReg.fromInt(nsLeft));
        obj.setProp(vm.segManager, selectors.nsRight, SciReg.fromInt(nsRight));
        obj.setProp(vm.segManager, selectors.nsTop, SciReg.fromInt(nsTop));
        obj.setProp(vm.segManager, selectors.nsBottom, SciReg.fromInt(nsBottom));
      }
    }
    return vm.acc;
  }

  SciReg _kNumLoops(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final view = getView(argv[0].toUint16());
    return SciReg.fromInt(view?.loops.length ?? 0);
  }

  SciReg _kNumCels(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return const SciReg.fromInt(0);
    final view = getView(argv[0].toUint16());
    final loop = argv[1].toUint16();
    if (view != null && loop < view.loops.length) {
      return SciReg.fromInt(view.loops[loop].cels.length);
    }
    return const SciReg.fromInt(0);
  }

  SciReg _kCelWide(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 3) return const SciReg.fromInt(0);
    final view = getView(argv[0].toUint16());
    final loop = argv[1].toUint16();
    final cel = argv[2].toUint16();
    if (view != null && loop < view.loops.length && cel < view.loops[loop].cels.length) {
      return SciReg.fromInt(view.loops[loop].cels[cel].width);
    }
    return const SciReg.fromInt(0);
  }

  SciReg _kCelHigh(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 3) return const SciReg.fromInt(0);
    final view = getView(argv[0].toUint16());
    final loop = argv[1].toUint16();
    final cel = argv[2].toUint16();
    if (view != null && loop < view.loops.length && cel < view.loops[loop].cels.length) {
      return SciReg.fromInt(view.loops[loop].cels[cel].height);
    }
    return const SciReg.fromInt(0);
  }

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
    if (argc < 2) return const SciReg.fromInt(0);
    final mask = argv[0].toUint16();
    final eventObj = vm.segManager.getObject(argv[1]);
    if (eventObj == null) return const SciReg.fromInt(0);

    eventObj.setProp(vm.segManager, selectors.x, SciReg.fromInt(mouseX));
    eventObj.setProp(vm.segManager, selectors.y, SciReg.fromInt(mouseY));
    if (selectors.claimed >= 0) {
      eventObj.setProp(vm.segManager, selectors.claimed, const SciReg.fromInt(0));
    }

    int foundIdx = -1;
    for (int i = 0; i < eventQueue.length; i++) {
      if ((eventQueue[i].type & mask) != 0) {
        foundIdx = i;
        break;
      }
    }

    final typeSel = vm.selectors.findSelector('type') ?? 83;
    final messageSel = vm.selectors.findSelector('message') ?? 84;
    final modifiersSel = vm.selectors.findSelector('modifiers') ?? 85;

    if (foundIdx >= 0) {
      final ev = eventQueue.removeAt(foundIdx);
      eventObj.setProp(vm.segManager, typeSel, SciReg.fromInt(ev.type));
      eventObj.setProp(vm.segManager, messageSel, SciReg.fromInt(ev.message));
      eventObj.setProp(vm.segManager, modifiersSel, SciReg.fromInt(ev.modifiers));
      eventObj.setProp(vm.segManager, selectors.x, SciReg.fromInt(ev.x));
      eventObj.setProp(vm.segManager, selectors.y, SciReg.fromInt(ev.y));
      return const SciReg.fromInt(1);
    } else {
      eventObj.setProp(vm.segManager, typeSel, const SciReg.fromInt(0));
      eventObj.setProp(vm.segManager, messageSel, const SciReg.fromInt(0));
      eventObj.setProp(vm.segManager, modifiersSel, const SciReg.fromInt(0));
      return const SciReg.fromInt(0);
    }
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

  final Stopwatch _playTimeStopwatch = Stopwatch()..start();

  SciReg _kGetTime(SciVM vm, int argc, List<SciReg> argv) {
    final mode = argc >= 1 ? argv[0].toUint16() : 0;
    switch (mode) {
      case 0: // KGETTIME_TICKS (approx 60 Hz)
        final ticks = (_playTimeStopwatch.elapsedMilliseconds * 60) ~/ 1000;
        return SciReg.fromInt(ticks & 0x7FFF);
      case 1: // KGETTIME_TIME_12HOUR: (hour << 12) | (min << 6) | sec
        final now = DateTime.now();
        final hour = (now.hour % 12 == 0) ? 12 : (now.hour % 12);
        return SciReg.fromInt(((hour << 12) | (now.minute << 6) | now.second) & 0xFFFF);
      case 2: // KGETTIME_TIME_24HOUR: (hour << 11) | (min << 5) | (sec >> 1)
        final now = DateTime.now();
        return SciReg.fromInt(((now.hour << 11) | (now.minute << 5) | (now.second >> 1)) & 0xFFFF);
      case 3: // KGETTIME_DATE: (year << 9) | (month << 5) | day
        final now = DateTime.now();
        final year = (now.year >= 1980 ? now.year - 1980 : 8) & 0x7F;
        return SciReg.fromInt(((year << 9) | (now.month << 5) | now.day) & 0xFFFF);
      default:
        final ticks = (_playTimeStopwatch.elapsedMilliseconds * 60) ~/ 1000;
        return SciReg.fromInt(ticks & 0x7FFF);
    }
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

  SciReg _kBaseSetter(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return vm.acc;
    final obj = vm.segManager.getObject(argv[0]);
    if (obj == null) return vm.acc;

    final y = obj.getProp(vm.segManager, selectors.y).toSint16();
    final yStep = obj.getProp(vm.segManager, selectors.yStep).toSint16();
    final nsLeft = obj.getProp(vm.segManager, selectors.nsLeft).toSint16();
    final nsRight = obj.getProp(vm.segManager, selectors.nsRight).toSint16();

    final brBottom = y + 1;
    final brTop = brBottom - yStep;

    obj.setProp(vm.segManager, selectors.brLeft, SciReg.fromInt(nsLeft));
    obj.setProp(vm.segManager, selectors.brRight, SciReg.fromInt(nsRight));
    obj.setProp(vm.segManager, selectors.brTop, SciReg.fromInt(brTop));
    obj.setProp(vm.segManager, selectors.brBottom, SciReg.fromInt(brBottom));
    return vm.acc;
  }

  SciReg _kDirLoop(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 2) return vm.acc;
    final obj = vm.segManager.getObject(argv[0]);
    if (obj == null) return vm.acc;
    final angle = argv[1].toUint16();

    final signal = obj.getProp(vm.segManager, selectors.signal).toUint16();
    if ((signal & 0x0800) != 0) { // kSignalDoesntTurn
      return vm.acc;
    }

    int useLoop = -1;
    if (angle > 315 || angle < 45) {
      useLoop = 3; // North
    } else if (angle > 135 && angle < 225) {
      useLoop = 2; // South
    }
    if (useLoop == -1) {
      if (angle >= 180) {
        useLoop = 1; // West
      } else {
        useLoop = 0; // East
      }
    } else {
      final viewId = obj.getProp(vm.segManager, selectors.view).toUint16();
      final v = getView(viewId);
      if (v == null || v.loops.length < 4) {
        return vm.acc;
      }
    }

    obj.setProp(vm.segManager, selectors.loop, SciReg.fromInt(useLoop));
    return vm.acc;
  }

  SciReg _kCanBeHere(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final obj = vm.segManager.getObject(argv[0]);
    if (obj == null) return const SciReg.fromInt(0);

    final brLeft = obj.getProp(vm.segManager, selectors.brLeft).toSint16();
    final brTop = obj.getProp(vm.segManager, selectors.brTop).toSint16();
    final brRight = obj.getProp(vm.segManager, selectors.brRight).toSint16();
    final brBottom = obj.getProp(vm.segManager, selectors.brBottom).toSint16();
    final illegalBits = obj.getProp(vm.segManager, selectors.illegalBits).toUint16();
    final signal = obj.getProp(vm.segManager, selectors.signal).toUint16();

    final hitControl = onControl(4, brLeft, brTop, brRight, brBottom);
    if ((hitControl & illegalBits) != 0) {
      return const SciReg.fromInt(0);
    }

    // If ignore actor or remove view is set, don't check actor collisions
    if ((signal & 0x4080) == 0 && argc >= 2) {
      SciList? list = vm.segManager.lookupList(argv[1]);
      if (list == null) {
        final listObj = vm.segManager.getObject(argv[1]);
        if (listObj != null) {
          final elemReg = listObj.getProp(vm.segManager, selectors.elements);
          list = vm.segManager.lookupList(elemReg);
        }
      }
      if (list != null) {
        for (final otherReg in vm.segManager.listElements(list)) {
          if (otherReg == obj.pos) continue;
          final other = vm.segManager.getObject(otherReg);
          if (other == null) continue;
          final otherSignal = other.getProp(vm.segManager, selectors.signal).toUint16();
          if ((otherSignal & 0x4088) != 0) continue; // ignore actor / hidden / removeView

          final oLeft = other.getProp(vm.segManager, selectors.brLeft).toSint16();
          final oTop = other.getProp(vm.segManager, selectors.brTop).toSint16();
          final oRight = other.getProp(vm.segManager, selectors.brRight).toSint16();
          final oBottom = other.getProp(vm.segManager, selectors.brBottom).toSint16();

          if (oRight > brLeft && oLeft < brRight && oBottom > brTop && oTop < brBottom) {
            return const SciReg.fromInt(0); // Blocked by actor
          }
        }
      }
    }

    return const SciReg.fromInt(1); // Can be here!
  }

  SciReg _kOnControl(SciVM vm, int argc, List<SciReg> argv) {
    int screenMask = 4; // default CONTROL
    int argBase = 0;
    if (argc == 2 || argc == 4) {
      screenMask = 4;
      argBase = 0;
    } else if (argc >= 3) {
      screenMask = argv[0].toUint16();
      argBase = 1;
    }
    int left = argv[argBase].toSint16();
    int top = argv[argBase + 1].toSint16();
    int right = (argc > 3) ? argv[argBase + 2].toSint16() : left + 1;
    int bottom = (argc > 3) ? argv[argBase + 3].toSint16() : top + 1;
    return SciReg.fromInt(onControl(screenMask, left, top, right, bottom));
  }

  SciReg _kCoordPri(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return const SciReg.fromInt(0);
    final y = argv[0].toSint16();
    return SciReg.fromInt(coordinateToPriority(y));
  }

  SciReg _kMapKeyToDir(SciVM vm, int argc, List<SciReg> argv) {
    if (argc < 1) return vm.acc;
    final eventObj = vm.segManager.getObject(argv[0]);
    if (eventObj == null) return vm.acc;

    final typeSel = vm.selectors.findSelector('type') ?? 83;
    final messageSel = vm.selectors.findSelector('message') ?? 84;

    final type = eventObj.getProp(vm.segManager, typeSel).toUint16();
    if (type == 1) { // kSciEventKeyDown
      final msg = eventObj.getProp(vm.segManager, messageSel).toUint16();
      int? dir;
      switch (msg) {
        case 0x4700: dir = 8; break; // Home (Up-Left)
        case 0x4800: dir = 1; break; // Up
        case 0x4900: dir = 2; break; // PgUp (Up-Right)
        case 0x4B00: dir = 7; break; // Left
        case 0x4C00: dir = 0; break; // Center (Stop)
        case 0x4D00: dir = 3; break; // Right
        case 0x4F00: dir = 6; break; // End (Down-Left)
        case 0x5000: dir = 5; break; // Down
        case 0x5100: dir = 4; break; // PgDown (Down-Right)
      }
      if (dir != null) {
        eventObj.setProp(vm.segManager, typeSel, const SciReg.fromInt(0x40)); // kSciEventDirection16
        eventObj.setProp(vm.segManager, messageSel, SciReg.fromInt(dir));
        return const SciReg.fromInt(1);
      }
      return const SciReg.fromInt(0);
    }
    return vm.acc;
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
