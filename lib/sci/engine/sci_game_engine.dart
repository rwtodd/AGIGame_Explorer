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
  SierraCursor? get mouseCursor => kernel.currentCursor;

  @override
  ui.Offset? get mouseCursorPosition =>
      ui.Offset(kernel.mouseX.toDouble(), kernel.mouseY.toDouble());

  @override
  bool get showMouseCursor => kernel.cursorVisible;

  @override
  List<SciWindowOverlay> get sciWindows {
    final font = kernel.getFont(0);
    final windows = kernel.windowManager.toOverlays(fontResolver: kernel.getFont);
    final hud = kernel.menuBar.toOverlay(font: font);
    final drop = kernel.menuBar.dropdownOverlay(font: font);
    return [
      ?hud,
      ?drop,
      ...windows,
    ];
  }

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
    final vocab900Entry = volumeManager.resourceMap.findById(const SciResourceId(SciResourceType.vocab, 900));
    if (vocab900Entry != null) {
      try {
        kernel.vocab900 = volumeManager.getResource(SciResourceType.vocab, 900);
      } catch (_) {}
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
    _waitZeroPumpUntil = null;

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

  /// Extra-pump of `Wait(0)` for ~2s of wall clock after the first unthrottled
  /// wait (speed test). After that, even if scripts leave speed at 0 (PQ2 intro),
  /// we run one cycle per host tick. Independent of room number (LSL3 uses 290).
  DateTime? _waitZeroPumpUntil;

  void _pumpVm() {
    if (vm.executionStack.isEmpty || vm.abortScriptProcessing) return;
    final extraPump = kernel.lastWaitTicks == 0 &&
        (_waitZeroPumpUntil == null ||
            !DateTime.now().isAfter(_waitZeroPumpUntil!));
    final sliceEnd = DateTime.now().add(
      Duration(milliseconds: extraPump ? 40 : 12),
    );
    try {
      do {
        vm.yieldRequested = false;
        vm.runVm(100000, 0);
        if (!vm.yieldRequested) break;
        if (kernel.lastWaitTicks > 0) break;
        _waitZeroPumpUntil ??= DateTime.now().add(const Duration(seconds: 2));
        if (DateTime.now().isAfter(_waitZeroPumpUntil!)) break;
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
  void handleMouseMove(ui.Offset playfieldPos) {
    kernel.mouseX = playfieldPos.dx.round();
    kernel.mouseY = playfieldPos.dy.round();
  }

  @override
  void handleMouseClick(ui.Offset playfieldPos) {
    final x = playfieldPos.dx.round();
    final y = playfieldPos.dy.round();
    kernel.mouseX = x;
    kernel.mouseY = y;
    _hitTestWindows(x, y);
    kernel.postMouseEvent(SciEventType.mousePress, x, y);
  }

  void _hitTestWindows(int x, int y) {
    for (final wnd in kernel.windowManager.windowStack.reversed) {
      final origin = ui.Offset(
        wnd.dims.left + wnd.contentOffset.dx,
        wnd.dims.top + wnd.contentOffset.dy,
      );
      final local = ui.Offset(x - origin.dx, y - origin.dy);
      for (final control in wnd.controls.reversed) {
        if (!control.hitTest(local)) continue;
        if (control is SciButtonControl) {
          wnd.setControl(
            identityHashCode(control),
            SciButtonControl(
              rect: control.rect,
              text: control.text,
              isPressed: true,
              isFocused: true,
              colorPen: control.colorPen,
              colorBack: control.colorBack,
              font: control.font,
            ),
          );
          notifyListeners();
        }
        return;
      }
    }
  }

  @override
  void submitCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;

    kernel.activeCycleSaidSpecs.clear();

    final typeSel = selectors.type >= 0 ? selectors.type : (selectors.findSelector('type') ?? 83);
    final claimedSel = selectors.claimed >= 0 ? selectors.claimed : (selectors.findSelector('claimed') ?? 76);
    final messageSel = selectors.message >= 0 ? selectors.message : (selectors.findSelector('message') ?? 84);
    final modifiersSel = selectors.modifiers >= 0 ? selectors.modifiers : (selectors.findSelector('modifiers') ?? 85);

    final eventTemplate = SciObject(
      pos: SciReg.nullReg,
      variables: List<SciReg>.filled(16, const SciReg.fromInt(0)),
      baseVars: [typeSel, messageSel, modifiersSel, claimedSel],
    );
    final eventObj = segManager.cloneObject(eventTemplate);
    final eventReg = eventObj.pos;
    eventObj.setProp(segManager, typeSel, const SciReg.fromInt(128)); // saidEvent
    eventObj.setProp(segManager, claimedSel, const SciReg.fromInt(0));

    final strReg = segManager.allocString(trimmed);
    try {
      final parseRes = kernel.call(vm, 0x24, 2, [strReg, eventReg]);
      if (parseRes.toUint16() == 0) {
        notifyListeners();
        return;
      }

      var dispatched = false;
      final s996Seg = segManager.scriptToSegment[996];
      if (s996Seg != null) {
        final s996 = segManager.loadedScripts[s996Seg];
        SciObject? user;
        if (s996 != null) {
          for (final o in s996.objects.values) {
            if (o.nameString == 'User') {
              user = o;
              break;
            }
          }
        }
        if (user != null && !user.pos.isNull) {
          final saidSel = selectors.findSelector('said');
          if (saidSel != null) {
            try {
              vm.sendSelector(user.pos, saidSel, [eventReg]);
              dispatched = true;
            } catch (_) {}
          }
        }
      }

      final claimed = eventObj.getProp(segManager, claimedSel).toUint16() != 0;
      if (!dispatched || !claimed) {
        if (segManager.globals.length > 1 && !segManager.globals[1].isNull) {
          final curRoom = segManager.globals[1];
          try {
            vm.sendSelector(curRoom, selectors.handleEvent, [eventReg]);
          } catch (_) {}
        }
      }

      final finalClaimed = eventObj.getProp(segManager, claimedSel).toUint16() != 0;
      if (!finalClaimed && segManager.globals.isNotEmpty && !segManager.globals[0].isNull) {
        final theGame = segManager.globals[0];
        final pragmaFailSel = selectors.pragmaFail >= 0
            ? selectors.pragmaFail
            : selectors.findSelector('pragmaFail');
        if (pragmaFailSel != null) {
          try {
            vm.sendSelector(theGame, pragmaFailSel, [strReg]);
          } catch (_) {}
        }
      }

      notifyListeners();
    } finally {
      if (kernel.parserEvent == eventReg) kernel.parserEvent = null;
      segManager.disposeClone(eventReg);
    }
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
