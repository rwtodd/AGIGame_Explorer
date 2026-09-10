import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/domain/sierra_game_session.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Interactive Game Engine for Sierra SCI0 titles (e.g. Police Quest 2, QFG2).
///
/// Implements [SierraGameSession] for direct rendering in [GameScreen] alongside AGI.
class SciGameEngine extends ChangeNotifier implements SierraGameSession {
  final SciVolumeManager volumeManager;
  late final SciSegManager segManager;
  late final SciKernel kernel;
  late final SciSelectors selectors;
  late final SciVM vm;
  final ViewAtlasManager atlasManager = ViewAtlasManager();

  Timer? _tickTimer;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isDisposed = false;
  @override
  double speedHz;
  int _cycleCount = 0;
  SciReg? _gameObj;
  bool _started = false;

  List<String> get recentKernelLogs => kernel.recentCallLogs.toList();

  String _statusLine = '';
  final String _promptLine = '';

  @override
  DisplayProfile get displayProfile => DisplayProfile.sci0;

  @override
  SierraPicture? get currentPic => kernel.currentPic;

  @override
  Map<int, PictureSlice>? get pictureSlices => kernel.currentPic?.slices;

  @override
  List<PlayfieldActorSprite> get actors => kernel.currentSprites;

  @override
  List<SciWindowOverlay> get sciWindows =>
      kernel.windowManager.toOverlays(fontResolver: kernel.getFont);

  @override
  SierraCursor? get mouseCursor => null;

  @override
  ui.Offset? get mouseCursorPosition =>
      ui.Offset(kernel.mouseX.toDouble(), kernel.mouseY.toDouble());

  @override
  bool get showMouseCursor => false;

  @override
  String get statusLine => kernel.currentStatusLine ?? _statusLine;

  @override
  String get promptLine => _promptLine;

  @override
  bool get isPaused => _isPaused;

  @override
  bool get isInputEnabled {
    final s996Seg = segManager.scriptToSegment[996];
    if (s996Seg != null) {
      final s996 = segManager.loadedScripts[s996Seg];
      final user = s996?.objects.values.firstWhere(
        (o) => o.nameString == 'User',
        orElse: () => SciObject(pos: SciReg.nullReg, variables: const []),
      );
      if (user != null && user.variables.isNotEmpty) {
        final canInputSel = selectors.findSelector('canInput');
        if (canInputSel != null) {
          final idx = user.locateVarSelector(segManager, canInputSel);
          if (idx >= 0 && idx < user.variables.length) {
            return user.variables[idx].toUint16() != 0;
          }
        }
      }
    }
    return true;
  }

  @override
  double get shakeOffsetX => 0.0;

  @override
  double get shakeOffsetY => 0.0;

  int get cycleCount => _cycleCount;
  bool get isRunning => _isRunning;

  SciGameEngine({
    required this.volumeManager,
    SciSegManager? segManager,
    SciKernel? kernel,
    SciSelectors? selectors,
    this.speedHz = 20.0,
  }) {
    this.segManager = segManager ?? SciSegManager();
    this.kernel = kernel ?? SciKernel();
    this.selectors = selectors ?? SciSelectors();
    vm = SciVM(
      segManager: this.segManager,
      kernel: this.kernel,
      selectors: this.selectors,
      volumeManager: volumeManager,
    );
    this.kernel.volumeManager = volumeManager;
    this.kernel.selectors = this.selectors;
    this.segManager.volumeManager = volumeManager;
    this.kernel.onRestartGameRequested ??= () => restartGame();
    this.kernel.onDrawStatus = (text) {
      _statusLine = text;
      notifyListeners();
    };
    this.kernel.onWindowsChanged = () {
      notifyListeners();
    };
  }

  /// Loads classes, selectors, vocabulary, and script 0. SCI start is always `(Game play:)`.
  /// [startingRoom] is a debug warp reserved for later; boot still uses play:.
  void initializeGame({int startingRoom = 0}) {
    final vocab996Bytes = volumeManager.getResource(SciResourceType.vocab, 996);
    segManager.loadClassTable(vocab996Bytes);

    final vocab997Bytes = volumeManager.getResource(SciResourceType.vocab, 997);
    selectors.loadVocab997(vocab997Bytes);

    final vocab0Entry = volumeManager.resourceMap.findById(const SciResourceId(SciResourceType.vocab, 0));
    if (vocab0Entry != null) {
      final vocab0Bytes = volumeManager.getResource(SciResourceType.vocab, 0);
      final vocab = SciVocab();
      vocab.loadVocab000(vocab0Bytes);
      kernel.vocab = vocab;
    }

    final script0 = segManager.instantiateScript(0, volumeManager);
    final gameObjOffset = script0.exports[0];
    final game = script0.getObject(gameObjOffset);
    if (game != null) {
      _gameObj = game.pos;
      _statusLine = game.nameString ?? 'Sierra SCI0';
    }

    vm.yieldOnAnimate = true;
  }

  @override
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _isPaused = false;

    // Trigger initial frame / boot if not started
    if (!_started && _gameObj != null) {
      _started = true;
      try {
        vm.sendSelector(_gameObj!, selectors.play, []);
      } catch (e, st) {
        if (kernel.verboseLogging) {
          debugPrint('[SciEngine] ERROR during boot: $e\n$st');
        }
      }
      notifyListeners();
    }

    final intervalMs = (1000.0 / speedHz).round();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      tick();
    });
  }

  @override
  void setSpeedHz(double speed) {
    speedHz = speed;
    if (_tickTimer != null && !_isPaused) {
      _tickTimer?.cancel();
      final intervalMs = (1000.0 / speedHz).round();
      _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        tick();
      });
    }
    notifyListeners();
  }

  @override
  void pause() {
    _isPaused = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    notifyListeners();
  }

  @override
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    final intervalMs = (1000.0 / speedHz).round();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      tick();
    });
    notifyListeners();
  }

  @override
  void restartGame({int startingRoom = 0}) {
    final wasPaused = _isPaused;
    _isPaused = true;
    _tickTimer?.cancel();
    _tickTimer = null;

    _cycleCount = 0;
    _started = false;

    atlasManager.clear();
    segManager.reset();
    vm.reset();
    kernel.reset();

    kernel.gameIsRestarting = 1;

    initializeGame(startingRoom: startingRoom);

    _isRunning = true;
    _started = true;
    _isPaused = false;

    if (_gameObj != null) {
      try {
        vm.sendSelector(_gameObj!, selectors.play, []);
      } catch (e, st) {
        if (kernel.verboseLogging) {
          debugPrint('[SciEngine] ERROR during restart boot: $e\n$st');
        }
      }
    }

    final intervalMs = (1000.0 / speedHz).round();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      tick();
    });

    if (wasPaused) {
      pause();
    } else {
      notifyListeners();
    }
  }

  @override
  void tick() {
    if (_isPaused || _isDisposed) return;
    _cycleCount++;
    _pumpVm();
    notifyListeners();
  }

  /// SCI0 `g11` is `currentRoom` (PQ2 snapshot / LSL2 `GAME.SH`).
  static const int _globalCurrentRoom = 11;

  int get _currentRoom {
    if (segManager.globals.length > _globalCurrentRoom) {
      return segManager.globals[_globalCurrentRoom].toUint16();
    }
    return 0;
  }

  /// Runs the VM until Animate yields.
  ///
  /// Extra-pump of `Wait(0)` is **PQ2/LSL2-specific**: those titles use room 99
  /// as a 1-second speed test (`RM099.SC`). LSL3 uses room 290; other SCI0
  /// games may use another room or none. After leaving 99, PQ2 keeps speed 0
  /// for the intro — one cycle per engine tick so it can animate. See
  /// `doc/sci0_deferred_cleanup.md`.
  void _pumpVm() {
    if (vm.executionStack.isEmpty || vm.abortScriptProcessing) return;
    final sliceEnd = DateTime.now().add(const Duration(milliseconds: 12));
    try {
      do {
        vm.yieldRequested = false;
        vm.runVm(100000, 0);
        if (!vm.yieldRequested) break;
        if (kernel.lastWaitTicks > 0) break;
        if (_currentRoom != 99) break;
      } while (!vm.abortScriptProcessing &&
          vm.executionStack.isNotEmpty &&
          DateTime.now().isBefore(sliceEnd));
    } catch (e, st) {
      if (kernel.verboseLogging) {
        debugPrint('[SciEngine] ERROR in tick: $e\n$st');
      }
    }
  }

  @override
  void handleDirection(int direction) {
    kernel.postDirectionEvent(direction);
  }

  @override
  void handleKeyPress(
    int? rawKeyCode, {
    int ascii = 0,
    bool shift = false,
    bool ctrl = false,
    bool alt = false,
  }) {
    if (rawKeyCode == null) return;
    final modifiers = (shift ? 1 : 0) | (ctrl ? 2 : 0) | (alt ? 4 : 0);
    kernel.postKeyEvent(ascii != 0 ? ascii : rawKeyCode, modifiers: modifiers);
  }

  @override
  void handleMouseClick(ui.Offset playfieldPos) {
    kernel.postMouseEvent(1, playfieldPos.dx.round(), playfieldPos.dy.round());
  }

  @override
  void submitCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;

    kernel.activeCycleSaidSpecs.clear();

    // Allocate an event object
    final eventReg = SciReg.pointer(SciSegManager.cloneSegmentId, 9999);
    final eventObj = SciObject(
      pos: eventReg,
      variables: List<SciReg>.filled(16, const SciReg.fromInt(0)),
    );
    segManager.clones[9999] = eventObj;

    final typeSel = selectors.type >= 0 ? selectors.type : (selectors.findSelector('type') ?? 83);
    final claimedSel = selectors.claimed >= 0 ? selectors.claimed : (selectors.findSelector('claimed') ?? 76);
    final messageSel = selectors.message >= 0 ? selectors.message : (selectors.findSelector('message') ?? 84);
    final modifiersSel = selectors.modifiers >= 0 ? selectors.modifiers : (selectors.findSelector('modifiers') ?? 85);

    eventObj.baseVars.addAll([typeSel, messageSel, modifiersSel, claimedSel]);
    eventObj.setProp(segManager, typeSel, const SciReg.fromInt(128)); // saidEvent
    eventObj.setProp(segManager, claimedSel, const SciReg.fromInt(0));

    final strReg = segManager.allocString(trimmed);

    // Run Parse
    final parseRes = kernel.call(vm, 0x24, 2, [strReg, eventReg]);
    if (parseRes.toUint16() == 0) {
      notifyListeners();
      return;
    }

    // Try dispatching through User.said first if User is present
    var dispatched = false;
    final s996Seg = segManager.scriptToSegment[996];
    if (s996Seg != null) {
      final s996 = segManager.loadedScripts[s996Seg];
      final user = s996?.objects.values.firstWhere(
        (o) => o.nameString == 'User',
        orElse: () => SciObject(pos: SciReg.nullReg, variables: const []),
      );
      if (user != null && !user.pos.isNull) {
        final saidSel = selectors.findSelector('said') ?? 75;
        try {
          vm.sendSelector(user.pos, saidSel, [eventReg]);
          dispatched = true;
        } catch (_) {}
      }
    }

    // If User was not available, or event was not claimed, dispatch directly to curRoom
    final claimed = eventObj.getProp(segManager, claimedSel).toUint16() != 0;
    if (!dispatched || !claimed) {
      if (segManager.globals.length > 1 && !segManager.globals[1].isNull) {
        final curRoom = segManager.globals[1];
        try {
          vm.sendSelector(curRoom, selectors.handleEvent, [eventReg]);
        } catch (_) {}
      }
    }

    // If still not claimed, call prsErr on theGame if available
    final finalClaimed = eventObj.getProp(segManager, claimedSel).toUint16() != 0;
    if (!finalClaimed && segManager.globals.isNotEmpty && !segManager.globals[0].isNull) {
      final theGame = segManager.globals[0];
      final prsErrSel = selectors.findSelector('prsErr');
      if (prsErrSel != null) {
        try {
          vm.sendSelector(theGame, prsErrSel, [eventReg]);
        } catch (_) {}
      }
    }

    notifyListeners();
  }

  /// Exports a comprehensive snapshot of the SCI engine state as a Map.
  Map<String, dynamic> exportState({String? label}) {
    return {
      'engine': 'SCI0',
      'label': label ?? 'Diagnostic State Snapshot',
      'timestamp': DateTime.now().toIso8601String(),
      'cycleCount': _cycleCount,
      'speedHz': speedHz,
      'isPaused': _isPaused,
      'currentPic': kernel.currentPic?.picNumber,
      'pictureSlices': pictureSlices?.length ?? 0,
      'actors': actors.map((a) => {
        'view': a.viewNumber,
        'loop': a.loopNumber,
        'cel': a.celNumber,
        'x': a.position.dx.round(),
        'y': a.position.dy.round(),
        'priority': a.priority,
        'baselineY': a.baselineY,
        'objectNumber': a.objectNumber,
        'isUpdating': a.isUpdating,
        'width': a.celEntry?.width ?? 0,
        'height': a.celEntry?.height ?? 0,
      }).toList(),
      'vm': {
        'acc': {
          'segment': vm.acc.segment,
          'offset': vm.acc.offset,
          'u16': vm.acc.toUint16(),
          's16': vm.acc.toSint16(),
          'display': vm.acc.toString(),
        },
        'prev': {
          'segment': vm.prev.segment,
          'offset': vm.prev.offset,
          'u16': vm.prev.toUint16(),
          's16': vm.prev.toSint16(),
          'display': vm.prev.toString(),
        },
        'stackDepth': vm.stack.length,
        'stack': vm.stack.map((r) => r.toString()).toList(),
        'executionStackDepth': vm.executionStack.length,
        'executionStack': vm.executionStack.reversed.map((f) {
          final scr = segManager.loadedScripts[f.pc.segment];
          final scrNum = scr?.scriptNumber ?? f.pc.segment;
          final selName = f.selector >= 0 ? selectors.getSelectorName(f.selector) : '-';
          return {
            'type': f.type.name,
            'script': scrNum,
            'segment': f.pc.segment,
            'pc': '0x${f.pc.offset.toRadixString(16).padLeft(4, '0')}',
            'selector': '${f.selector} ($selName)',
            'argc': f.argc,
            'fp': f.fp,
            'sp': f.sp,
          };
        }).toList(),
      },
      'globals': {
        for (var i = 0; i < segManager.globals.length; i++)
          if (!segManager.globals[i].isNull)
            'g$i': segManager.globals[i].toString()
      },
      'loadedScripts': segManager.loadedScripts.values.map((s) => {
        'scriptNumber': s.scriptNumber,
        'segmentId': s.segmentId,
        'localsCount': s.locals.length,
        'objectsCount': s.objects.length,
        'exportsCount': s.exports.length,
      }).toList(),
      'lists': {
        for (final entry in segManager.lists.entries)
          '0x${entry.key.toRadixString(16)}': {
            'count': entry.value.count,
            'first': entry.value.first.toString(),
            'last': entry.value.last.toString(),
          }
      },
      'nodesCount': segManager.nodes.length,
      'clonesCount': segManager.clones.length,
      'recentKernelLogs': kernel.recentCallLogs.toList(),
      'parser': {
        'lastInput': kernel.lastParsedRaw,
        'lastParsedWords': kernel.lastParsedWords.map((w) => w.toString()).toList(),
        'lastUnknownWord': kernel.lastUnknownWord,
        'activeCycleSaidSpecs': kernel.activeCycleSaidSpecs
            .take(30)
            .map((s) => s.toSaidString(kernel.vocab))
            .toList(),
      },
    };
  }

  /// Exports the engine state formatted as a JSON string.
  String exportStateJson({bool pretty = true, String? label}) {
    final state = exportState(label: label);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(state);
    }
    return jsonEncode(state);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    atlasManager.dispose();
    kernel.dispose();
    super.dispose();
  }
}
