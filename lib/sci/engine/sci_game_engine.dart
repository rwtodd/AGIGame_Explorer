import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/domain/sierra_game_session.dart';
import 'package:flutter_agigame/domain/sound.dart';
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
  @override
  final AgiSoundPlayer soundPlayer;
  final bool _ownsSoundPlayer;
  AgiSoundMode _soundMode = AgiSoundMode.pcJr;
  final bool _isSoundOn = true;

  @override
  AgiSoundMode get soundMode => _soundMode;

  @override
  bool get isSoundOn => _soundMode != AgiSoundMode.off && _isSoundOn;

  @override
  SynthesizerConfig get synthesizerConfig => kernel.synthesizerConfig;

  Timer? _tickTimer;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isDisposed = false;
  @override
  double speedHz;
  int _cycleCount = 0;
  int _lastDirection = 0;
  @visibleForTesting
  int get lastDirectionForTest => _lastDirection;
  int _prevRoom = 0;
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
    SciVolumeManager? volumeManager,
    SciSegManager? segManager,
    SciKernel? kernel,
    SciSelectors? selectors,
    AgiSoundPlayer? soundPlayer,
    this.speedHz = 20.0,
  })  : volumeManager = volumeManager ?? SciVolumeManager.empty(),
        soundPlayer = soundPlayer ?? AgiSoundPlayer(),
        _ownsSoundPlayer = soundPlayer == null {
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
    this.kernel.soundPlayer = this.soundPlayer;
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

  @override
  void setSoundMode(AgiSoundMode mode) {
    _soundMode = mode;
    switch (mode) {
      case AgiSoundMode.off:
        kernel.soundMode = PcmPlaybackMode.tandy3VoiceNoise;
        soundPlayer.mute();
        break;
      case AgiSoundMode.ibmPc:
        kernel.soundMode = PcmPlaybackMode.ibmPcSingleChannel;
        kernel.synthesizerConfig = kernel.synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.ibmPcSingleChannel,
          enableReverb: false,
        );
        soundPlayer.unmute();
        break;
      case AgiSoundMode.pcJr:
        kernel.soundMode = PcmPlaybackMode.tandy3VoiceNoise;
        kernel.synthesizerConfig = kernel.synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.tandy3VoiceNoise,
          enableReverb: false,
        );
        soundPlayer.unmute();
        break;
      case AgiSoundMode.enhanced:
        kernel.soundMode = PcmPlaybackMode.enhanced;
        kernel.synthesizerConfig = kernel.synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.enhanced,
          enableReverb: kernel.synthesizerConfig.reverbMix > 0.0,
        );
        soundPlayer.unmute();
        break;
    }
    notifyListeners();
  }

  @override
  void setSynthesizerConfig(SynthesizerConfig config) {
    kernel.synthesizerConfig = config;
    if (_soundMode != AgiSoundMode.off) {
      if (config.mode == PcmPlaybackMode.ibmPcSingleChannel) {
        _soundMode = AgiSoundMode.ibmPc;
        kernel.soundMode = PcmPlaybackMode.ibmPcSingleChannel;
      } else if (config.mode == PcmPlaybackMode.tandy3VoiceNoise) {
        _soundMode = AgiSoundMode.pcJr;
        kernel.soundMode = PcmPlaybackMode.tandy3VoiceNoise;
      } else {
        _soundMode = AgiSoundMode.enhanced;
        kernel.soundMode = PcmPlaybackMode.enhanced;
      }
    }
    notifyListeners();
  }

  /// Loads classes, selectors, vocabulary, and script 0. SCI start is always `(Game play:)`.
  /// [startingRoom] is a debug warp reserved for later; boot still uses play:.
  void initializeGame({int startingRoom = 0}) {
    segManager.isEarlySci0 = volumeManager.isEarlySci0;

    final vocab996Bytes = volumeManager.getResource(SciResourceType.vocab, 996);
    segManager.loadClassTable(vocab996Bytes);

    final vocab997Bytes = volumeManager.getResource(SciResourceType.vocab, 997);
    selectors.loadVocab997(vocab997Bytes, isEarlySci0: volumeManager.isEarlySci0);

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
    if (script0.exports.isNotEmpty) {
      final gameObjOffset = script0.exports[0];
      final game = script0.getObject(gameObjOffset);
      if (game != null) {
        _gameObj = game.pos;
        _statusLine = game.nameString ?? 'Sierra SCI0';
      }
    }
    _syncGameSpeed();

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

  /// SCI0 `g11` is `currentRoom` (PQ2 snapshot / LSL2 `GAME.SH`).
  static const int _globalCurrentRoom = 11;

  int get _currentRoom {
    if (segManager.globals.length > _globalCurrentRoom) {
      return segManager.globals[_globalCurrentRoom].toUint16();
    }
    return 0;
  }

  /// Converts host frequency [speedHz] into Sierra SCI wait ticks (PIT ticks / 60 Hz).
  ///
  /// Sierra SCI0 baseline normal speed is 6 ticks (~100 ms per cycle).
  /// - 60 Hz (Fastest): 1 tick delay (~16.7 ms, ~6x speed)
  /// - 30 Hz (Fast): 3 ticks delay (~50.0 ms, ~2x speed)
  /// - 20 Hz (Normal): 6 ticks delay (~100.0 ms, baseline authentic speed)
  /// - 10 Hz (Slow): 12 ticks delay (~200.0 ms, ~0.5x speed)
  int get currentSciWaitSpeed {
    if (speedHz >= 50.0) return 1;
    if (speedHz >= 25.0) return 3;
    if (speedHz >= 15.0) return 6;
    return 12;
  }

  /// Synchronizes Sierra Game object speed and global speed variables with [speedHz].
  /// Does not override unthrottled speed during active room-99 speed tests.
  void _syncGameSpeed() {
    if (_currentRoom == 99) return;
    final targetSpeed = currentSciWaitSpeed;
    if (_gameObj != null) {
      final speedSel = selectors.findSelector('speed');
      final game = segManager.getObject(_gameObj!);
      if (speedSel != null && game != null) {
        game.setProp(segManager, speedSel, SciReg.fromInt(targetSpeed));
      }
    }
    final g = segManager.globals;
    if (g.length > 3) {
      g[3] = SciReg.fromInt(targetSpeed);
    }
    if (g.length > 18) {
      g[18] = SciReg.fromInt(targetSpeed);
    }
    kernel.lastWaitTicks = min(kernel.lastWaitTicks, targetSpeed);
  }

  @override
  void setSpeedHz(double speed) {
    if (speed <= 0) return;
    speedHz = speed;
    if (_tickTimer != null && !_isPaused) {
      _tickTimer?.cancel();
      final intervalMs = (1000.0 / speedHz).round();
      _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        tick();
      });
    }
    _syncGameSpeed();
    notifyListeners();
  }

  @override
  void pause() {
    _isPaused = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    soundPlayer.pause();
    notifyListeners();
  }

  @override
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    soundPlayer.resume();
    final intervalMs = (1000.0 / speedHz).round();
    _tickTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      tick();
    });
    notifyListeners();
  }

  @override
  void restartGame({int startingRoom = 0}) {
    _isPaused = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    soundPlayer.stop();

    _cycleCount = 0;
    _started = false;
    _lastDirection = 0;
    _prevRoom = 0;

    atlasManager.clear();
    segManager.reset();
    vm.reset();
    kernel.reset();

    kernel.gameIsRestarting = 1;

    initializeGame(startingRoom: startingRoom);
    _syncGameSpeed();

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

    notifyListeners();
  }

  bool _inTick = false;

  @override
  void tick() {
    if (_isPaused || _isDisposed || _inTick) return;
    _inTick = true;
    try {
      _cycleCount++;
      final room = _currentRoom;
      if (room != _prevRoom) {
        _prevRoom = room;
        _lastDirection = 0;
      }
      // Step the 60 Hz PIT from the outside (DOSBox-style). At 20 Hz host
      // this is 3 SCI ticks; the speed test then measures ~60 doits/sec.
      kernel.advanceSciClock(hostHz: speedHz);
      kernel.updateSci0Cues(vm);
      _pumpVm();
      _restorePq2SpeedAfterTest();
      if (_lastDirection != 0 &&
          _isEgoStopped() &&
          !kernel.eventQueue.any((e) => e.type == SciEventType.direction)) {
        _lastDirection = 0;
      }
      notifyListeners();
    } finally {
      _inTick = false;
    }
  }

  /// PQ2 1.002.011 leaves `setSpeed: 0` after the room-99 test on the intro
  /// path (ScummVM patches the script). Restore configured game speed from the host instead.
  void _restorePq2SpeedAfterTest() {
    final g = segManager.globals;
    if (g.length <= 110) return;
    final room = g.length > 11 ? g[11].toUint16() : 0;
    if (room == 0 || room == 99) return;
    if (g[110].toUint16() == 0) return;
    final gSpeed = g.length > 18 ? g[18].toUint16() : 0;
    final gameSpeed = g.length > 3 ? g[3].toUint16() : 0;
    if (gSpeed == 0 || gameSpeed == 0) {
      final targetSpeed = currentSciWaitSpeed;
      if (gameSpeed == 0) g[3] = SciReg.fromInt(targetSpeed);
      if (g.length > 18 && gSpeed == 0) g[18] = SciReg.fromInt(targetSpeed);
      if (_gameObj != null) {
        final speedSel = selectors.findSelector('speed');
        final game = segManager.getObject(_gameObj!);
        if (speedSel != null && game != null) {
          game.setProp(segManager, speedSel, SciReg.fromInt(targetSpeed));
        }
      }
    }
  }

  /// How many Wait(0) Game.play loops fit in one host tick at AT throughput.
  ///
  /// A real 8088/AT does ~20–80 `doit`s in the 1s GetTime window. We do not
  /// patch that test (ScummVM writes `$7fff` into PQ2 g110). Instead each
  /// host tick allows `60/speedHz` unthrottled cycles — 3 at 20 Hz — so
  /// machineSpeed stays AT-class. Wait(n>0) still ends the pump: one frame.
  void _pumpVm() {
    if (vm.executionStack.isEmpty || vm.abortScriptProcessing) return;
    if (kernel.lastWaitTicks > 0 &&
        (kernel.currentSciTicks - kernel.lastWaitTime) < kernel.lastWaitTicks &&
        !kernel.hasPendingInput) {
      return;
    }

    final atBudget = speedHz <= 0 ? 1 : max(1, (60.0 / speedHz).round());
    var wait0Pumps = 0;
    var inputPumps = 0;
    try {
      while (true) {
        vm.yieldRequested = false;
        vm.runVm(100000, 0);
        if (!vm.yieldRequested) break;
        if (kernel.hasPendingInput) {
          inputPumps++;
          if (inputPumps > 64) break;
          continue;
        }
        if (kernel.lastWaitTicks > 0) break;
        wait0Pumps++;
        if (wait0Pumps >= atBudget) break;
      }
    } catch (e, st) {
      if (kernel.verboseLogging) {
        debugPrint('[SciEngine] ERROR in tick: $e\n$st');
      }
    }
  }

  /// Returns true only if Ego object exists and has no active mover.
  bool _isEgoStopped() {
    final g = segManager.globals;
    if (g.isEmpty) return false;
    final egoReg = g[0];
    if (egoReg.toUint16() == 0) return false;
    final egoObj = segManager.getObject(egoReg);
    if (egoObj == null) return false;
    final moverSel = selectors.findSelector('mover');
    if (moverSel == null) return false;
    final moverReg = egoObj.getProp(segManager, moverSel);
    if (moverReg.toUint16() == 0) return true;
    final moverObj = segManager.getObject(moverReg);
    return moverObj == null;
  }

  @override
  void handleDirection(int direction) {
    var dir = direction.clamp(0, 8);
    if (dir != 0 && dir == _lastDirection) {
      dir = 0;
    }
    _lastDirection = dir;
    kernel.postDirectionEvent(dir);
    tick();
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
    // User.doit / Dialog.doit only run when the VM is pumped. Do it now so a
    // typed character opens GetInput and paints in this call, not 1–4 s later.
    tick();
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
    _lastDirection = 0;
    kernel.postMouseEvent(SciEventType.mousePress, x, y);
    tick();
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

    final actualInput = trimmed.startsWith(':') ? trimmed.substring(1).trim() : trimmed;
    if (actualInput.isEmpty) return;

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

    final strReg = segManager.allocString(actualInput);
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

  /// SCI0 flag array is globals 250.. as 16-bit words, bit `0x8000 >> (flag%16)`.
  List<int> _decodeSciFlags() {
    final g = segManager.globals;
    final set = <int>[];
    for (var w = 0; w < 16; w++) {
      final gi = 250 + w;
      if (gi >= g.length) break;
      final bits = g[gi].toUint16();
      if (bits == 0) continue;
      for (var b = 0; b < 16; b++) {
        if ((bits & (0x8000 >> b)) != 0) set.add(w * 16 + b);
      }
    }
    return set;
  }

  Map<String, Object?> _exportControl(SciControlItem c) {
    if (c is SciTextControl) {
      return {'type': 'text', 'text': c.text};
    }
    if (c is SciEditControl) {
      return {'type': 'edit', 'text': c.text, 'cursor': c.cursorPosition};
    }
    if (c is SciButtonControl) {
      return {'type': 'button', 'text': c.text};
    }
    return {'type': c.runtimeType.toString()};
  }

  /// Exports a comprehensive snapshot of the SCI engine state as a Map.
  Map<String, dynamic> exportState({String? label}) {
    final g = segManager.globals;
    int gAt(int i) => i < g.length ? g[i].toUint16() : 0;
    final currentRoom = gAt(11);
    final prevRoom = gAt(12);
    final flagsSet = _decodeSciFlags();
    String bootPath;
    if (prevRoom == 99 && currentRoom == 1 && flagsSet.contains(167)) {
      bootPath = 'restart-skip-intro (Btst 167 → newRoom 1)';
    } else if (prevRoom == 99 && currentRoom == 200) {
      bootPath = 'cold-boot-intro (flag 167 clear → newRoom 200)';
    } else if (currentRoom == 33) {
      bootPath = 'in-car';
    } else {
      bootPath = 'room $currentRoom prev $prevRoom';
    }

    final stack = vm.stack;
    const head = 8;
    const tail = 24;
    final omitted = max(0, stack.length - head - tail);

    return {
      'engine': 'SCI0',
      'label': label ?? 'Diagnostic State Snapshot',
      'timestamp': DateTime.now().toIso8601String(),
      'cycleCount': _cycleCount,
      'speedHz': speedHz,
      'isPaused': _isPaused,
      'bootPath': bootPath,
      'clock': {
        'sciTicks': kernel.currentSciTicks,
        'lastWaitTicks': kernel.lastWaitTicks,
        'waitingForPit': kernel.waitingForPit,
        'gameIsRestarting': kernel.gameIsRestarting,
        'getTimeStreak': kernel.getTimeStreak,
      },
      'rooms': {
        'current': currentRoom,
        'previous': prevRoom,
        'pic': kernel.currentPic?.picNumber,
        'gameSpeed_g3': gAt(3),
        'gSpeed_g18': gAt(18),
        'machineSpeed_g110': gAt(110),
      },
      'flagsSet': flagsSet,
      'windows': kernel.windowManager.windowStack.map((w) {
        return {
          'id': w.id,
          'title': w.title,
          'rect': [w.dims.left, w.dims.top, w.dims.right, w.dims.bottom],
          'controls': w.controls.map(_exportControl).toList(),
        };
      }).toList(),
      'eventQueue': kernel.eventQueue
          .map((e) => {'type': e.type, 'message': e.message})
          .toList(),
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
        'stackDepth': stack.length,
        'stackOmitted': omitted,
        'stackHead': stack.take(head).map((r) => r.toString()).toList(),
        'stackTail': stack.length <= head
            ? const <String>[]
            : stack
                .sublist(omitted > 0 ? stack.length - tail : head)
                .map((r) => r.toString())
                .toList(),
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
        for (var i = 0; i < g.length; i++)
          if (!g[i].isNull)
            'g$i': g[i].toString()
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
  bool get isDisposed => _isDisposed;

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) return;
    super.removeListener(listener);
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    if (_ownsSoundPlayer) {
      soundPlayer.dispose();
    } else {
      soundPlayer.stop();
    }
    atlasManager.dispose();
    kernel.dispose();
    super.dispose();
  }
}
