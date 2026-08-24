import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/menu/agi_menu.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/domain/priority_table.dart';
import 'package:flutter_agigame/engine/controllers/agi_controller_manager.dart';
import 'package:flutter_agigame/engine/motion/agi_motion.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/agi_message_formatter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:flutter_agigame/engine/parser/agi_said_matcher.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';

/// Available audio output modes for [AgiGameEngine].
enum AgiSoundMode {
  /// Sound muted (Flag %f9 = false).
  off,

  /// Authentic 1-Channel IBM PC Speaker square wave (%v22 = 1).
  ibmPc,

  /// Authentic 3-Voice Tone + Noise PCjr / Tandy 1000 emulation (%v22 = 3).
  pcJr,

  /// Modern synthesizer with custom waveforms & reverb DSP (%v22 = 3).
  enhanced,
}

/// Represents the type of user input requested by an input prompt dialog.
enum AgiInputPromptType {
  string,
  number,
}

/// Represents active modal string/number prompt dialog state (`get.string`, `get.num`).
class AgiInputPromptState {
  final AgiInputPromptType type;
  final String prompt;
  final int? row;
  final int? col;
  final int maxLen;
  String currentText;
  final Completer<String?>? stringCompleter;
  final Completer<int?>? numCompleter;

  AgiInputPromptState({
    required this.type,
    required this.prompt,
    this.row,
    this.col,
    this.maxLen = 40,
    this.currentText = '',
    this.stringCompleter,
    this.numCompleter,
  });
}

/// Represents active modal or positional dialog box state.
class AgiDialogState {
  final String message;
  final int? row;
  final int? col;
  final int? width;
  final bool isModal;
  final Completer<void>? dismissCompleter;
  final int? autoCloseHalfSeconds;
  final int? autoCloseTicks;
  final DateTime createdAt;

  int? get x => col;
  int? get y => row;

  AgiDialogState({
    required this.message,
    this.row,
    this.col,
    this.width,
    this.isModal = true,
    this.dismissCompleter,
    this.autoCloseHalfSeconds,
    this.autoCloseTicks,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Represents non-modal text displayed on the 40x25 character grid (e.g. from display/display.v).
class AgiDisplayText {
  final int row;
  final int col;
  final String message;

  const AgiDisplayText({
    required this.row,
    required this.col,
    required this.message,
  });
}

/// Core Sierra AGI Game Engine and Cycle Coordinator.
///
/// Drives the classic 20 Hz (configurable) execution loop:
/// - Phase 1: Accepts player inputs (keyboard direction & parsed text command line)
/// - Phase 2: Updates animated sprite motion & cel animations with barrier collision detection
/// - Phase 3: Executes `LOGIC 0` scan cycle with [AgiLogicInterpreter]
/// - Phase 4: Prepares rendered frame for Impeller priority slicing compositor
/// - Post-Scan: Resets transient flags (Flag 1, Flag 2, Flag 4) and updates game clocks
class AgiGameEngine extends ChangeNotifier implements AgiInterpreterDelegate {
  final AgiResourceLoader? resourceLoader;
  /// Player instance for AGI sound synthesis and PCM playback.
  final AgiSoundPlayer soundPlayer;
  final bool _ownsSoundPlayer;
  final AgiMemory memory;
  final AgiPriorityTable priorityTable;
  final List<AnimatedObject> animatedObjects;
  final List<AgiObject>? _customObjects;
  late final AgiLogicInterpreter interpreter;

  AgiPic? currentPic;
  AgiDialogState? activeDialog;
  AgiInputPromptState? activeInputPrompt;

  bool _isRunning = false;
  bool _isPaused = false;
  bool _isInventoryOpen = false;
  int? _inspectingObjectNumber;
  double _speedHz;
  int _lastSynchronizedDelay = 2;
  int _loopGeneration = 0;
  Timer? _dialogAutoCloseTimer;
  int? _dialogAutoCloseTicks;
  double shakeOffsetX = 0.0;
  double shakeOffsetY = 0.0;
  int _shakeTicksRemaining = 0;
  int _shakeCount = 0;
  int get shakeCount => _shakeCount;

  int _cycleCount = 0;
  int _clockTicks = 0;
  List<int> _parsedWordIds = [];
  List<String> _inputWords = [];
  String? _lastSubmittedCommand;
  String? _lastError;
  bool _keyPressedThisCycle = false;
  bool _isStatusLineEnabled = false;
  bool _isInputEnabled = true;
  bool _isUserControl = true;
  final List<AgiDisplayText> _displayedTexts = [];
  final AgiTextScreenBuffer textScreenBuffer = AgiTextScreenBuffer();
  bool _isTextScreen = false;
  int _textFgColor = 15;
  int _textBgColor = 0;
  final math.Random _rng;
  int? _activeSoundEndFlag;
  AgiSoundMode _soundMode = AgiSoundMode.pcJr;
  SynthesizerConfig _synthesizerConfig = const SynthesizerConfig();
  @override
  int horizon = CollisionDetector.defaultHorizon;
  AgiBlockArea? activeBlock;
  final List<AgiAddToPicEntry> _addToPicCalls = [];

  /// Active list of `add.to.pic` background modifications in the current room.
  List<AgiAddToPicEntry> get addToPicCalls => List.unmodifiable(_addToPicCalls);

  final AgiDictionary? _customDictionary;

  /// Manages keyboard shortcut and function key mappings (`set.key`).
  final AgiControllerManager controllerManager = AgiControllerManager();

  /// Manages AGI menu bar and dropdown hierarchy.
  final AgiMenuManager menuManager = AgiMenuManager();

  /// Manages runtime view texture atlases for smooth, zero-flicker sprite rendering.
  final ViewAtlasManager atlasManager = ViewAtlasManager();

  /// Map of views currently loaded in memory for this room/session.
  final Map<int, AgiView> _loadedViews = {};

  Map<int, AgiView> get loadedViews => Map.unmodifiable(_loadedViews);

  int? _lastStatusScore;
  int? _lastStatusMaxScore;
  bool? _lastStatusSoundOn;
  bool _statusLineNeedsRedraw = true;

  /// Optional override directory for saving and loading `.sav` game slots.
  Directory? saveDirectory;

  /// Callback triggered when `save.game()` opcode executes.
  VoidCallback? onSaveGameRequested;

  /// Callback triggered when `restore.game()` opcode executes.
  VoidCallback? onRestoreGameRequested;

  /// Callback triggered when `restart.game()` opcode executes.
  VoidCallback? onRestartGameRequested;

  AgiGameEngine({
    this.resourceLoader,
    AgiSoundPlayer? soundPlayer,
    AgiDictionary? dictionary,
    AgiPriorityTable? priorityTable,
    AgiMemory? memory,
    List<AnimatedObject>? animatedObjects,
    List<AgiObject>? objects,
    this._speedHz = 20.0,
    int? randomSeed,
    int maxAnimatedObjects = 64,
  })  : soundPlayer = soundPlayer ?? AgiSoundPlayer(),
        _ownsSoundPlayer = soundPlayer == null,
        _customDictionary = dictionary,
        priorityTable = priorityTable ?? AgiPriorityTable(),
        memory = memory ?? AgiMemory(),
        animatedObjects = animatedObjects ??
            List.generate(maxAnimatedObjects, (i) => AnimatedObject(number: i)),
        _customObjects = objects,
        _rng = randomSeed != null ? math.Random(randomSeed) : math.Random() {
    for (final obj in this.animatedObjects) {
      obj.priorityTable = this.priorityTable;
    }
    this.soundPlayer.onFinished = _onSoundFinished;

    interpreter = AgiLogicInterpreter(
      memory: this.memory,
      animatedObjects: this.animatedObjects,
      delegate: this,
      randomSeed: randomSeed,
      maxAnimatedObjects: maxAnimatedObjects,
    );

    // Initial default state: Sound ON by default
    this.memory.setFlag(9);

    // Dynamic flag hook for on-demand pixel-accurate Flag 1 (Ego obscured) with per-tick cache
    this.memory.flagGetterHook = (flag) {
      if (flag == 1) {
        _cachedFlag1Obscured ??= isEgoObscured();
        return _cachedFlag1Obscured!;
      }
      return null;
    };
  }

  bool? _cachedFlag1Obscured;

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isInventoryOpen => _isInventoryOpen;
  int? get inspectingObjectNumber => _inspectingObjectNumber;
  int _playfieldRow = 1;
  int _inputRow = 23;
  int _statusRow = 0;

  double get speedHz => _speedHz;
  int get cycleCount => _cycleCount;
  List<int> get parsedWordIds => List.unmodifiable(_parsedWordIds);
  String? get lastSubmittedCommand => _lastSubmittedCommand;
  String? get lastError => _lastError;
  bool get isStatusLineEnabled => _isStatusLineEnabled;
  bool get isInputEnabled => _isInputEnabled;
  set isInputEnabled(bool enabled) => onInputMode(enabled);
  bool get isUserControl => _isUserControl;
  set isUserControl(bool enabled) => onUserControl(enabled);
  List<String> get inputWords => List.unmodifiable(_inputWords);
  List<AgiDisplayText> get displayedTexts => List.unmodifiable(_displayedTexts);
  bool get isTextScreen => _isTextScreen;
  int get textFgColor => _textFgColor;
  int get textBgColor => _textBgColor;
  int get playfieldRow => _playfieldRow;
  int get inputRow => _inputRow;
  int get statusRow => _statusRow;
  int get currentRoom => memory.getVar(0);
  int get score => memory.getVar(3);
  int get maxScore => memory.getVar(7);
  bool get isMenuOpen => menuManager.isOpen;
  AnimatedObject get ego => animatedObjects[0];

  final Set<int> _loadedLogicNumbers = <int>{0};

  /// Set of all logic script numbers currently loaded or invoked during this room cycle.
  Set<int> get loadedLogicNumbers => Set.unmodifiable(_loadedLogicNumbers);

  /// All game objects defined for this game.
  List<AgiObject> get objects =>
      _customObjects ?? resourceLoader?.initialObjects ?? const [];

  /// Returns the subset of items currently carried by the player (room 255 in memory).
  List<CarriedItem> getCarriedItems() {
    final all = objects;
    final carried = <CarriedItem>[];
    for (int i = 0; i < all.length; i++) {
      final obj = all[i];
      if (obj.name == '?' || obj.name.trim().isEmpty) continue;
      final room = memory.itemRooms[i] ?? obj.startingRoom;
      if (room == 255) {
        carried.add(CarriedItem(index: i, object: obj));
      }
    }
    return carried;
  }

  /// Opens the interactive inventory dialog and pauses game tick updates.
  void openInventory() {
    onStatus();
  }

  /// Closes the interactive inventory dialog and resumes game loop ticks.
  FutureOr<void> closeInventory([int? selectedObjectNumber]) {
    _isInventoryOpen = false;
    if (memory.getFlag(13)) {
      final selected = selectedObjectNumber ?? 255;
      memory.setVar(25, selected);
    }
    if (interpreter.hasPendingInput) {
      final res = interpreter.resumeWithInput(selectedObjectNumber != null ? '$selectedObjectNumber' : null);
      if (res is Future<InterpreterStatus>) {
        return res.then((status) {
          if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
            _performPostScanCleanup();
          }
          notifyListeners();
        });
      }
      if (res == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
    }
    notifyListeners();
  }

  /// Opens the object inspection modal for [objectNumber] and pauses game tick updates.
  void inspectObject(int objectNumber) {
    onShowObj(objectNumber);
  }

  /// Closes the object inspection view and resumes game loop ticks.
  FutureOr<void> closeObjectInspection() {
    _inspectingObjectNumber = null;
    if (interpreter.hasPendingYield) {
      final res = interpreter.resume();
      if (res is Future<InterpreterStatus>) {
        return res.then((status) {
          if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
            _performPostScanCleanup();
          }
          notifyListeners();
        });
      }
      if (res == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
    }
    notifyListeners();
  }

  /// Starts the self-rescheduling game loop.
  void start() {
    if (_isRunning && !_isPaused) return;
    _isRunning = true;
    _isPaused = false;
    _loopGeneration++;
    _runLoop(_loopGeneration);
    notifyListeners();
  }

  /// Pauses the game loop and sound playback.
  void pause() {
    _isPaused = true;
    soundPlayer.pause();
    notifyListeners();
  }

  /// Resumes a paused game loop and sound playback.
  void resume() {
    _isPaused = false;
    soundPlayer.resume();
    notifyListeners();
  }

  /// Maps Sierra AGI Variable 10 (animation delay in ticks) to execution frequency in Hertz.
  static double delayToHz(int delay) {
    switch (delay) {
      case 0:
        return 60.0; // Fastest: 60 Hz (~16.7ms / tick)
      case 1:
        return 30.0; // Fast: 30 Hz (~33.3ms / tick)
      case 2:
        return 20.0; // Normal: 20 Hz (50ms / tick)
      case 3:
        return 10.0; // Slow: 10 Hz (100ms / tick)
      default:
        final ms = (delay * 35).clamp(16, 1000);
        return 1000.0 / ms;
    }
  }

  /// Maps execution frequency in Hertz to Sierra AGI Variable 10 (animation delay).
  static int hzToDelay(double hz) {
    if (hz >= 45.0) return 0; // Fastest (60 Hz)
    if (hz >= 25.0) return 1; // Fast (30 Hz)
    if (hz >= 15.0) return 2; // Normal (20 Hz)
    if (hz >= 8.0) return 3; // Slow (10 Hz)
    final ms = (1000.0 / hz).round();
    return (ms / 35.0).round().clamp(0, 255);
  }

  /// Updates execution loop frequency in Hertz (default 10 Hz / 20 Hz = 50-100ms per tick).
  void setSpeedHz(double hz) {
    if (hz <= 0) return;
    _speedHz = hz;
    final delay = hzToDelay(hz);
    _lastSynchronizedDelay = delay;
    memory.setVar(10, delay);
    notifyListeners();
  }

  /// Stops game loop.
  void stop() {
    _isRunning = false;
    _isPaused = false;
    _loopGeneration++;
    notifyListeners();
  }

  /// Self-rescheduling single-threaded game loop.
  /// Guarantees sequential tick execution with zero timer drift or concurrency races.
  Future<void> _runLoop(int generation) async {
    while (_isRunning && _loopGeneration == generation) {
      if (!_isPaused &&
          !(activeDialog?.isModal ?? false) &&
          activeInputPrompt == null &&
          !_isInventoryOpen &&
          _inspectingObjectNumber == null &&
          !isMenuOpen &&
          !interpreter.hasPendingYield &&
          !interpreter.isExecuting) {
        final frameStart = DateTime.now();

        await tick();

        if (!_isRunning || _loopGeneration != generation) break;

        final targetIntervalMs = (_speedHz > 0) ? (1000.0 / _speedHz).round() : 50;
        final elapsedMs = DateTime.now().difference(frameStart).inMilliseconds;
        final remainingMs = targetIntervalMs - elapsedMs;

        if (remainingMs > 0) {
          await Future.delayed(Duration(milliseconds: remainingMs));
        } else {
          // Yield to event loop so input events and microtasks process smoothly
          await Future.delayed(Duration.zero);
        }
      } else {
        // Paused or in modal state: sleep briefly to avoid busy-wait
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  /// Initializes game with authentic Sierra AGI opening registers, loading root LOGIC 0
  /// and running the initial bootstrap scan.
  FutureOr<void> initializeGame({int startingRoom = 0}) {
    memory.reset();
    menuManager.reset();
    _isStatusLineEnabled = false;

    // Authentic Sierra AGI system variable defaults
    memory.setVar(0, 0); // %v0 = current.room (0 on boot)
    memory.setVar(1, 0); // %v1 = previous.room (0 on boot)
    memory.setVar(8, 10); // %v8 = free heap space in 4KB pages
    memory.setVar(10, 2); // %v10 = anim.delay: 2 = Normal speed (10 Hz)
    _lastSynchronizedDelay = 2;
    _speedHz = delayToHz(2);
    memory.setVar(20, 0); // %v20 = machine.type: 0 = IBM PC / compatibles
    memory.setVar(22, 1); // %v22 = sound voices: 1 = PC speaker
    memory.setVar(24, 41); // %v24 = max input length: MAXINPUT + 1 (40 + 1)
    memory.setVar(26, 0); // %v26 = monitor.type: 0 = EGA / RGB

    // Authentic Sierra AGI system flag defaults
    memory.setFlag(5); // %f5 = init.log / new_room (signals first room execution)
    memory.setFlag(9); // %f9 = sound.on (sound enabled by default)

    for (final obj in animatedObjects) {
      obj.reset();
    }

    if (objects.isNotEmpty) {
      for (int i = 0; i < objects.length; i++) {
        final item = objects[i];
        memory.itemRooms[i] = item.startingRoom;
      }
    }

    if (resourceLoader != null) {
      // Load root logic script (LOGIC 0)
      if (resourceLoader!.presentLogicNumbers.contains(0)) {
        final logic0 = resourceLoader!.loadLogic(0);
        interpreter.loadRootScript(logic0, scriptNumber: 0);
      }
    }

    if (startingRoom != 0) {
      changeRoom(startingRoom);
    }

    void finalizeInit() {
      // Post-Scan: clear first-cycle room init flags
      memory.resetFlag(5); // init.log reset after startup scan
      memory.resetFlag(6); // restart.in.progress reset
      memory.resetFlag(12); // restore.in.progress reset

      _statusLineNeedsRedraw = true;
      updateStatusLine(force: true);

      ego.updateCachedView(getView(ego.view));
      notifyListeners();
    }

    // Run initial bootstrap scan (LOGIC 0 room 0 startup which calls new.room(introRoom))
    if (interpreter.currentFrame != null) {
      try {
        final res = interpreter.executeCycle();
        if (res is Future<InterpreterStatus>) {
          return res.then((_) {
            finalizeInit();
          });
        }
      } catch (e) {
        _lastError = 'Interpreter error during game initialization: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    finalizeInit();
  }

  int? _bufferedEgoDirection;
  bool _bufferedToggleIfSame = true;
  final List<String> _bufferedCommands = [];
  final List<int> _bufferedControllers = [];

  void _drainInputQueue() {
    if (_bufferedEgoDirection != null) {
      final dir = _bufferedEgoDirection!;
      final toggle = _bufferedToggleIfSame;
      _bufferedEgoDirection = null;
      _applyEgoDirection(dir, toggleIfSame: toggle);
    }
    if (_bufferedCommands.isNotEmpty) {
      final cmd = _bufferedCommands.removeAt(0);
      _applyCommand(cmd);
    }
    if (_bufferedControllers.isNotEmpty) {
      final ctls = List<int>.from(_bufferedControllers);
      _bufferedControllers.clear();
      for (final ctl in ctls) {
        controllerManager.triggerController(ctl, memory);
      }
    }
  }

  /// Executes exactly one full 20 Hz AGI cycle.
  FutureOr<void> tick() {
    if (interpreter.isExecuting) return null;
    _cycleCount++;
    _drainInputQueue();

    // ----------------------------------------------------
    // Phase 1: Input handling
    // ----------------------------------------------------
    // Update Ego direction variable (%v6) per Sierra MAIN.C:80-82
    if (!_isUserControl) {
      memory.setVar(6, ego.direction);
    } else {
      ego.direction = memory.getVar(6);
    }

    // ----------------------------------------------------
    // Phase 2: Motion & Cel Animation Physics
    // ----------------------------------------------------
    _updateMotionAndAnimation();

    // ----------------------------------------------------
    // Phase 3: LOGIC 0 Scan Cycle Execution
    // ----------------------------------------------------
    if (interpreter.rootScript != null || interpreter.currentFrame != null) {
      try {
        final res = interpreter.executeCycle();
        if (res is Future<InterpreterStatus>) {
          return res.then((status) {
            _finishTickExecution(status);
          }).catchError((e) {
            _lastError = 'Interpreter error in cycle $_cycleCount: $e';
            if (kDebugMode) {
              print(_lastError);
            }
          });
        } else {
          if (_finishTickExecution(res)) return null;
          return null;
        }
      } catch (e) {
        _lastError = 'Interpreter error in cycle $_cycleCount: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    _finishTickExecution(InterpreterStatus.completed);
  }

  bool _finishTickExecution(InterpreterStatus status) {
    if (status == InterpreterStatus.yielded) {
      notifyListeners();
      return true;
    }

    // Synchronize Ego motion direction from %v6 (var[EGODIR]) per Sierra MAIN.C:102 / ScummVM cycle.cpp:165.
    // Unconditionally sync var[6] back to ego.direction after script execution (for both user and program control).
    // Do not force isCycling off when standing: scripts use start.cycling / end.of.loop
    // on a stationary Ego (KQ2 monastery pray, drowning, etc.). Walk-cycle stop is
    // handled in _applyEgoDirection when the player actually stops.
    if (ego.motionType == 0) {
      ego.direction = memory.getVar(6);
      if (ego.direction != 0) {
        ego.isCycling = true;
      }
    }

    // ----------------------------------------------------
    // Post-Scan: Clock update & transient flags cleanup
    // ----------------------------------------------------
    _performPostScanCleanup();
    return false;
  }

  void _performPostScanCleanup() {
    _updateClock();
    updateStatusLine();

    // Synchronize engine speed from Variable 10 (animation delay in ticks)
    final currentDelay = memory.getVar(10);
    if (currentDelay != _lastSynchronizedDelay) {
      _lastSynchronizedDelay = currentDelay;
      final targetHz = delayToHz(currentDelay);
      if ((_speedHz - targetHz).abs() > 0.01) {
        _speedHz = targetHz;
      }
    }

    // Auto-capture room transition checkpoint on completion of new room first scan (%f5)
    if (memory.getFlag(5)) {
      _recordRoomTransitionCheckpoint();
    }

    // Reset transient per-cycle flags and parsed input tokens
    _cachedFlag1Obscured = null;
    memory.resetFlag(2); // have.input reset
    memory.resetFlag(4); // said.accepted reset
    memory.resetFlag(5); // init.log / new_room first execution reset
    memory.resetFlag(6); // restart.in.progress reset
    memory.resetFlag(12); // restore.in.progress reset
    memory.resetControllers();
    _parsedWordIds.clear();

    // Reset transient edge hit variables and key press state
    memory.setVar(4, 0);
    memory.setVar(5, 0);
    memory.setVar(19, 0);
    _keyPressedThisCycle = false;
    // Decrement modal dialog auto-close ticks if active
    if (_dialogAutoCloseTicks != null && _dialogAutoCloseTicks! > 0) {
      _dialogAutoCloseTicks = _dialogAutoCloseTicks! - 1;
      if (_dialogAutoCloseTicks! <= 0) {
        dismissDialog();
      }
    }

    _updateShake();

    memory.applyPins();

    notifyListeners();
  }

  void _updateShake() {
    if (_shakeTicksRemaining > 0) {
      _shakeTicksRemaining--;
      if (_shakeTicksRemaining % 2 == 0) {
        shakeOffsetY = (_shakeTicksRemaining % 4 == 0) ? -3.0 : 3.0;
        shakeOffsetX = (_shakeTicksRemaining % 3 == 0) ? 2.0 : -2.0;
      } else {
        shakeOffsetY = 0.0;
        shakeOffsetX = 0.0;
      }
    } else {
      shakeOffsetX = 0.0;
      shakeOffsetY = 0.0;
    }
  }

  void _applyEgoDirection(int direction, {bool toggleIfSame = true}) {
    if (!_isUserControl) {
      return; // Ignore player direction commands when under program.control()
    }
    if (toggleIfSame && direction != 0 && ego.direction == direction) {
      ego.direction = 0;
    } else {
      ego.direction = direction.clamp(0, 8);
    }
    memory.setVar(6, ego.direction);
    if (ego.direction != 0) {
      ego.isCycling = true;
      ego.isAnimated = true;
      if (!ego.fixedLoop) {
        _updateLoopForDirection(ego);
      }
    } else if (ego.cycleMode != 2 && ego.cycleMode != 3) {
      ego.isCycling = false;
    }
  }

  /// Sets Ego's motion direction (0..8) and synchronizes Variable 6.
  /// If [toggleIfSame] is true and Ego is already moving in [direction] (and [direction] != 0),
  /// Ego stops (direction 0).
  void setEgoDirection(int direction, {bool toggleIfSame = true}) {
    if (_isRunning) {
      _bufferedEgoDirection = direction;
      _bufferedToggleIfSame = toggleIfSame;
    } else {
      _applyEgoDirection(direction, toggleIfSame: toggleIfSame);
    }
    notifyListeners();
  }

  /// Active sound output mode.
  AgiSoundMode get soundMode => _soundMode;

  /// Active synthesizer DSP configuration.
  SynthesizerConfig get synthesizerConfig => _synthesizerConfig;

  /// Whether sound is actively enabled and outputting audio.
  bool get isSoundOn => _soundMode != AgiSoundMode.off && memory.getFlag(9);

  /// Sets sound enable flag (Flag 9) and updates audio engine.
  void setSoundOn(bool value) {
    if (value) {
      memory.setFlag(9);
      soundPlayer.unmute();
    } else {
      memory.resetFlag(9);
      soundPlayer.mute();
    }
    notifyListeners();
  }

  /// Sets sound output hardware emulation mode.
  void setSoundMode(AgiSoundMode mode) {
    _soundMode = mode;
    switch (mode) {
      case AgiSoundMode.off:
        memory.resetFlag(9); // %f9 = sound off
        soundPlayer.mute();
        break;
      case AgiSoundMode.ibmPc:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 1); // %v22 = 1 voice
        soundPlayer.unmute();
        _synthesizerConfig = _synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.ibmPcSingleChannel,
          enableReverb: false,
        );
        break;
      case AgiSoundMode.pcJr:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 3); // %v22 = 3 voices
        soundPlayer.unmute();
        _synthesizerConfig = _synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.tandy3VoiceNoise,
          enableReverb: false,
        );
        break;
      case AgiSoundMode.enhanced:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 3); // %v22 = 3 voices
        soundPlayer.unmute();
        _synthesizerConfig = _synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.enhanced,
          enableReverb: _synthesizerConfig.reverbMix > 0.0,
        );
        break;
    }
    notifyListeners();
  }

  /// Configures synthesizer parameters and updates mode accordingly.
  void setSynthesizerConfig(SynthesizerConfig config) {
    _synthesizerConfig = config;
    if (_soundMode != AgiSoundMode.off) {
      if (config.mode == PcmPlaybackMode.ibmPcSingleChannel) {
        _soundMode = AgiSoundMode.ibmPc;
        memory.setVar(22, 1);
      } else if (config.mode == PcmPlaybackMode.tandy3VoiceNoise) {
        _soundMode = AgiSoundMode.pcJr;
        memory.setVar(22, 3);
      } else {
        _soundMode = AgiSoundMode.enhanced;
        memory.setVar(22, 3);
      }
      memory.setFlag(9);
    }
    notifyListeners();
  }

  /// Toggles game audio sound on/off (%f9) and notifies UI listeners.
  void toggleSound() {
    if (_soundMode == AgiSoundMode.off || !memory.getFlag(9)) {
      setSoundMode(AgiSoundMode.pcJr);
    } else {
      setSoundMode(AgiSoundMode.off);
    }
  }

  /// Sets parsed word group IDs directly for testing matching rules.
  @visibleForTesting
  void setParsedWordIdsForTesting(List<int> wordIds) {
    _parsedWordIds = List<int>.from(wordIds);
    memory.setFlag(2);
    memory.resetFlag(4);
    notifyListeners();
  }

  void _applyCommand(String cleanInput) {
    _lastSubmittedCommand = cleanInput;
    _parsedWordIds = tokenizeCommand(cleanInput);

    // Flag 2: have.input = 1
    memory.setFlag(2);
    // Flag 4: said.accepted = 0
    memory.resetFlag(4);
  }

  /// Submits player text command, tokenizes against dictionary, and raises Flag 2 (`have.input`).
  void submitCommand(String input) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return;

    if (_isRunning) {
      _bufferedCommands.add(cleanInput);
    } else {
      _applyCommand(cleanInput);
    }
    notifyListeners();
  }

  /// Tokenizes a user string into recognized word group IDs using [AgiTextParser].
  List<int> tokenizeCommand(String rawText) {
    final dict = dictionary ?? AgiDictionary();
    final parser = AgiTextParser(dict);
    final result = parser.parse(rawText);

    _inputWords = List<String>.from(result.originalTokens);

    if (!result.isSuccess) {
      _lastError = result.errorMessage;
      memory.setVar(9, result.unknownWordIndex ?? 1);
      return <int>[];
    }

    memory.setVar(9, 0);
    return List<int>.from(result.wordGroupIds);
  }

  /// Formats Sierra AGI message placeholders (`%v`, `%w`, `%s`, `%m`, `%g`, `%o`) and escapes.
  String formatMessage(String text) {
    return AgiMessageFormatter.format(
      text,
      memory: memory,
      loader: resourceLoader,
      inputWords: _inputWords,
      currentScript: interpreter.currentFrame?.script,
    );
  }

  /// Dismisses active modal dialog box and resumes game loop ticks.
  FutureOr<void> dismissDialog() {
    final dialog = activeDialog;
    if (dialog == null) return null;

    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    _dialogAutoCloseTicks = null;

    dialog.dismissCompleter?.complete();
    activeDialog = null;
    if (interpreter.hasPendingYield) {
      final res = interpreter.resume();
      if (res is Future<InterpreterStatus>) {
        return res.then((status) {
          _finishTickExecution(status);
        });
      }
      _finishTickExecution(res);
    } else {
      notifyListeners();
    }
  }

  /// Updates the current interactive prompt text and synchronizes with the on-screen text buffer.
  void updateInputPrompt(String value) {
    final prompt = activeInputPrompt;
    if (prompt == null) return;
    final clamped = (prompt.maxLen > 0 && value.length > prompt.maxLen)
        ? value.substring(0, prompt.maxLen)
        : value;
    prompt.currentText = clamped;

    if (prompt.row != null) {
      final r = prompt.row!;
      final c = (prompt.col ?? 0) + prompt.prompt.length;
      final maxAvailable = (AgiTextScreenBuffer.columns - c).clamp(0, 40);
      final padLen = (prompt.maxLen > 0 ? prompt.maxLen : clamped.length).clamp(clamped.length, maxAvailable);
      textScreenBuffer.writeString(r, c, clamped.padRight(padLen, ' '), fg: _textFgColor, bg: _textBgColor);
    }
    notifyListeners();
  }

  /// Submits the current active input prompt value, completes awaiting future, and resumes interpreter.
  FutureOr<void> submitInputPrompt(String value) {
    final prompt = activeInputPrompt;
    if (prompt != null) {
      String? resultValue;
      if (prompt.type == AgiInputPromptType.string) {
        final clamped = prompt.maxLen > 0 && value.length > prompt.maxLen
            ? value.substring(0, prompt.maxLen)
            : value;
        resultValue = clamped;
        prompt.stringCompleter?.complete(clamped);
      } else {
        final num = (int.tryParse(value) ?? 0).clamp(0, 255);
        resultValue = num.toString();
        prompt.numCompleter?.complete(num);
      }
      activeInputPrompt = null;
      final res = interpreter.resumeWithInput(resultValue);
      if (res is Future<InterpreterStatus>) {
        return res.then((status) {
          if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
            _performPostScanCleanup();
          }
          notifyListeners();
        });
      }
      if (res == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
      notifyListeners();
    }
  }

  /// Cancels the current active input prompt without submitting a value and resumes interpreter.
  FutureOr<void> cancelInputPrompt() {
    final prompt = activeInputPrompt;
    if (prompt != null) {
      if (prompt.type == AgiInputPromptType.string) {
        prompt.stringCompleter?.complete(null);
      } else {
        prompt.numCompleter?.complete(null);
      }
      activeInputPrompt = null;
      final res = interpreter.resumeWithInput(null);
      if (res is Future<InterpreterStatus>) {
        return res.then((status) {
          if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
            _performPostScanCleanup();
          }
          notifyListeners();
        });
      }
      if (res == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // State Checkpoints & Snapshots (Debugging & Save-States)
  // ---------------------------------------------------------------------------

  final List<AgiGameStateSnapshot> _checkpointHistory = [];
  final List<AgiGameStateSnapshot> _roomCheckpoints = [];

  /// Rolling history of in-memory checkpoints taken during gameplay.
  List<AgiGameStateSnapshot> get checkpointHistory =>
      List.unmodifiable(_checkpointHistory);

  /// Rolling history of the last 5 room transition entry points (breadcrumbs).
  List<AgiGameStateSnapshot> get roomCheckpoints =>
      List.unmodifiable(_roomCheckpoints);

  /// Newest manually captured checkpoint (camera button / inspector), if any.
  AgiGameStateSnapshot? get lastManualCheckpoint {
    for (final snap in _checkpointHistory) {
      if (!snap.isRoomTransition) return snap;
    }
    return null;
  }

  /// Newest automatic room-entry checkpoint, if any.
  AgiGameStateSnapshot? get lastRoomCheckpoint =>
      _roomCheckpoints.isEmpty ? null : _roomCheckpoints.first;

  /// Checkpoint used by the sidebar retry button: last manual snapshot,
  /// otherwise the last room-change snapshot.
  AgiGameStateSnapshot? get lastRetryCheckpoint =>
      lastManualCheckpoint ?? lastRoomCheckpoint;

  /// Restores [lastRetryCheckpoint]. Returns `false` when there is nothing to restore.
  bool restoreLastRetryCheckpoint({bool? preservePauseState}) {
    final snap = lastRetryCheckpoint;
    if (snap == null) return false;
    restoreSnapshot(snap, preservePauseState: preservePauseState);
    return true;
  }

  /// Captures a composite 32-bit RGBA thumbnail buffer (default 80x84, aspect-correctable)
  /// of the current game screen, compositing background visual pixels with all active drawn actors.
  Uint8List captureScreenThumbnailRgba({
    int targetWidth = 80,
    int targetHeight = 84,
  }) {
    // 1. Create a 160x168 EGA index composite buffer
    final buffer = Uint8List(AgiPic.nativeWidth * AgiPic.nativeHeight);
    if (currentPic != null && currentPic!.visualPixels.length == buffer.length) {
      buffer.setAll(0, currentPic!.visualPixels);
    }

    // 2. Composite active drawn actors in priority order
    final loader = resourceLoader;
    if (loader != null) {
      final sortedObjects = animatedObjects.where((obj) => obj.isDrawn).toList()
        ..sort((a, b) {
          final priComp = a.effectivePriority.compareTo(b.effectivePriority);
          if (priComp != 0) return priComp;
          if (a.isUpdating != b.isUpdating) {
            return a.isUpdating ? 1 : -1;
          }
          return a.effectiveSortY.compareTo(b.effectiveSortY);
        });

      for (final obj in sortedObjects) {
        try {
          final viewRes = loader.loadView(obj.view);
          final loop = viewRes.getLoop(obj.loop);
          final safeCel = (loop != null && loop.celCount > 0 && obj.cel >= loop.celCount) ? 0 : obj.cel;
          final cel = loop?.getCel(safeCel);
          if (cel == null) continue;

          final celPixels = cel.getPixels(parentView: viewRes, celIndex: safeCel);
          final cw = cel.width;
          final ch = cel.height;
          final startX = obj.x;
          final startY = obj.y - ch + 1;

          for (int cy = 0; cy < ch; cy++) {
            final py = startY + cy;
            if (py < 0 || py >= AgiPic.nativeHeight) continue;

            for (int cx = 0; cx < cw; cx++) {
              final px = startX + cx;
              if (px < 0 || px >= AgiPic.nativeWidth) continue;

              final col = celPixels[cy * cw + cx];
              if (col != cel.transparentColor) {
                buffer[py * AgiPic.nativeWidth + px] = col & 0x0F;
              }
            }
          }
        } catch (_) {}
      }
    }

    // 3. Downsample 160x168 buffer to targetWidth x targetHeight (80x84) RGBA
    final outRgba = Uint8List(targetWidth * targetHeight * 4);
    final scaleX = AgiPic.nativeWidth / targetWidth;
    final scaleY = AgiPic.nativeHeight / targetHeight;

    for (int y = 0; y < targetHeight; y++) {
      final srcY = (y * scaleY).floor().clamp(0, AgiPic.nativeHeight - 1);
      final rowOffset = y * targetWidth * 4;

      for (int x = 0; x < targetWidth; x++) {
        final srcX = (x * scaleX).floor().clamp(0, AgiPic.nativeWidth - 1);
        final colorIndex = buffer[srcY * AgiPic.nativeWidth + srcX] & 0x0F;
        final col = EgaColors.rgbaBytes[colorIndex];

        final outIdx = rowOffset + (x * 4);
        outRgba[outIdx + 0] = col[0];
        outRgba[outIdx + 1] = col[1];
        outRgba[outIdx + 2] = col[2];
        outRgba[outIdx + 3] = 255;
      }
    }

    return outRgba;
  }

  /// Captures a complete serializable snapshot of the current game engine state.
  AgiGameStateSnapshot createSnapshot({
    String label = '',
    bool isRoomTransition = false,
    Uint8List? thumbnailRgba,
  }) {
    return AgiGameStateSnapshot.capture(
      this,
      label: label,
      isRoomTransition: isRoomTransition,
      thumbnailRgba: thumbnailRgba,
    );
  }

  int? _lastTransitionRecordedRoom;
  int? _lastTransitionRecordedCycle;

  /// Restores the game engine to an exact [snapshot] state.
  /// By default, preserves the current pause state at the moment of restoration.
  void restoreSnapshot(AgiGameStateSnapshot snapshot, {bool? preservePauseState}) {
    snapshot.restore(this, preservePauseState: preservePauseState);
    memory.resetFlag(5);
    memory.resetFlag(6);
    memory.setFlag(12);
    _lastTransitionRecordedRoom = snapshot.roomNumber;
    _lastTransitionRecordedCycle = snapshot.cycleCount;
    menuManager.enableAllItems();
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    notifyListeners();
  }

  /// Records a new snapshot into [_checkpointHistory] and returns it.
  AgiGameStateSnapshot recordCheckpoint({
    String label = '',
    bool isRoomTransition = false,
    Uint8List? thumbnailRgba,
  }) {
    final snap = createSnapshot(
      label: label,
      isRoomTransition: isRoomTransition,
      thumbnailRgba: thumbnailRgba,
    );
    _checkpointHistory.insert(0, snap);
    if (isRoomTransition) {
      _roomCheckpoints.insert(0, snap);
      if (_roomCheckpoints.length > 5) {
        final oldRoomSnap = _roomCheckpoints.removeLast();
        _checkpointHistory.remove(oldRoomSnap);
      }
    }
    if (_checkpointHistory.length > 25) {
      _checkpointHistory.removeLast();
    }
    notifyListeners();
    return snap;
  }

  /// Automatically records a checkpoint for the new room entrance.
  void _recordRoomTransitionCheckpoint() {
    final room = currentRoom;
    if (_lastTransitionRecordedRoom == room && _lastTransitionRecordedCycle == _cycleCount) {
      return;
    }
    _lastTransitionRecordedRoom = room;
    _lastTransitionRecordedCycle = _cycleCount;

    final snap = createSnapshot(
      label: '🚪 Room $room Entrance',
      isRoomTransition: true,
    );
    _roomCheckpoints.insert(0, snap);
    _checkpointHistory.insert(0, snap);
    if (_roomCheckpoints.length > 5) {
      final oldRoomSnap = _roomCheckpoints.removeLast();
      _checkpointHistory.remove(oldRoomSnap);
    }
    if (_checkpointHistory.length > 25) {
      _checkpointHistory.removeLast();
    }
  }

  /// Removes a checkpoint from history.
  void removeCheckpoint(int index) {
    if (index >= 0 && index < _checkpointHistory.length) {
      final snap = _checkpointHistory.removeAt(index);
      _roomCheckpoints.remove(snap);
      notifyListeners();
    }
  }

  /// Removes a room transition checkpoint by its index in [_roomCheckpoints].
  void removeRoomCheckpoint(int index) {
    if (index >= 0 && index < _roomCheckpoints.length) {
      final snap = _roomCheckpoints.removeAt(index);
      _checkpointHistory.remove(snap);
      notifyListeners();
    }
  }

  /// Clears all stored checkpoint snapshots.
  void clearCheckpoints() {
    _checkpointHistory.clear();
    _roomCheckpoints.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Motion & Animation Updates
  // ---------------------------------------------------------------------------

  void _updateMotionAndAnimation() {
    final pic = currentPic;
    final priBuf = pic?.priorityBuffer;

    for (final obj in animatedObjects) {
      if (!obj.isAnimated || !obj.isDrawn || (!obj.isUpdating && obj.cycleMode != 2 && obj.cycleMode != 3 && obj.motionType == 0)) {
        continue;
      }

      // Sierra CanBHere: auto-priority is the Y-band, not a leftover set.priority.
      CollisionDetector.syncAutoPriority(obj, obj.y);

      // Auto-assign loop based on motion direction if loop is not fixed
      if (!obj.fixedLoop) {
        _updateLoopForDirection(obj);
      }

      // Step Timer & Position Update
      obj.stepTimer--;
      if (obj.stepTimer <= 0) {
        obj.stepTimer = obj.stepTime > 0 ? obj.stepTime : 1;
        _updateObjectPosition(obj, priBuf);
      }

      // Cel Animation Timer & Cycling
      if (obj.isCycling) {
        obj.cycleTimer--;
        if (obj.cycleTimer <= 0) {
          obj.cycleTimer = obj.cycleTime > 0 ? obj.cycleTime : 1;
          _advanceObjectCel(obj);
        }
      }
    }

    _updateEgoFlags(priBuf);
  }

  void _updateEgoFlags(PriorityBuffer? priBuf) {
    if (priBuf == null) return;
    final egoObj = ego;
    if (!egoObj.isDrawn || !egoObj.isAnimated) {
      memory.resetFlag(0);
      memory.resetFlag(3);
      return;
    }
    final egoPri = egoObj.effectivePriority;
    if (egoPri == 15) {
      memory.resetFlag(0);
      memory.resetFlag(3);
      return;
    }
    final objWidth = egoObj.getCelWidth();

    // Flag 0: EGO on water surface (pri 3)
    var onWater = true;
    if (egoObj.onWater) {
      var anyWater = false;
      for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
        if (bx >= 0 && bx < 160 && egoObj.y >= 0 && egoObj.y < 168 && priBuf.priorityAt(bx, egoObj.y) == 3) {
          anyWater = true;
          break;
        }
      }
      onWater = anyWater;
    } else {
      for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
        if (bx < 0 || bx >= 160 || egoObj.y < 0 || egoObj.y >= 168 || priBuf.priorityAt(bx, egoObj.y) != 3) {
          onWater = false;
          break;
        }
      }
    }
    if (onWater) {
      memory.setFlag(0);
    } else {
      memory.resetFlag(0);
    }

    // Flag 3: EGO touches trigger/alarm line (pri 2)
    var onSignal = false;
    for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
      if (bx >= 0 && bx < 160 && egoObj.y >= 0 && egoObj.y < 168 && priBuf.priorityAt(bx, egoObj.y) == 2) {
        onSignal = true;
        break;
      }
    }
    if (onSignal) {
      memory.setFlag(3);
    } else {
      memory.resetFlag(3);
    }
  }

  /// Evaluates whether Ego (%o0) is completely obscured by higher priority background elements.
  /// Evaluated lazily on-demand when Flag 1 is queried.
  bool isEgoObscured() {
    final egoObj = ego;
    if (!egoObj.isDrawn || !egoObj.isAnimated) {
      return true;
    }

    final priBuf = currentPic?.priorityBuffer;
    if (priBuf == null) {
      return false;
    }

    final view = egoObj.cachedView ?? resourceLoader?.loadView(egoObj.view);
    final cel = view?.getCel(egoObj.loop, egoObj.cel);
    final egoPri = egoObj.effectivePriority;

    if (cel != null) {
      final width = cel.width;
      final height = cel.height;
      final clearKey = cel.transparentColor;
      final topY = egoObj.y - height + 1;

      try {
        final pixels = cel.getUnflippedPixels(parentView: view);
        for (int r = 0; r < height; r++) {
          final py = topY + r;
          if (py < 0 || py >= 168) continue;

          for (int c = 0; c < width; c++) {
            final px = egoObj.x + (cel.isMirrored ? (width - 1 - c) : c);
            if (px < 0 || px >= 160) continue;

            final pixelColor = pixels[r * width + c];
            if (pixelColor != clearKey) {
              final effPri = priBuf.effectivePriorityAt(px, py);
              if (effPri <= egoPri) {
                // Found at least one visible Ego pixel!
                return false;
              }
            }
          }
        }
        // No visible pixels found across all cel pixels
        return true;
      } catch (_) {
        // Fallback to baseline check
      }
    }

    // Fallback if cel pixel data is unavailable: check baseline
    final objWidth = egoObj.getCelWidth(null, null, view);
    for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
      if (bx >= 0 && bx < 160 && egoObj.y >= 0 && egoObj.y < 168) {
        final effPri = priBuf.effectivePriorityAt(bx, egoObj.y);
        if (effPri <= egoPri) {
          return false;
        }
      }
    }
    return true;
  }

  void _updateLoopForDirection(AnimatedObject obj) {
    if (obj.fixedLoop || obj.direction == 0) return;

    final loopCount = obj.getLoopCount();
    final newLoop = AgiMotion.selectLoopForDirection(
      obj.direction,
      loopCount,
      obj.loop,
    );

    if (newLoop != obj.loop) {
      obj.loop = newLoop;
      final celCount = obj.getCelCount();
      if (celCount > 0 && obj.cel >= celCount) {
        obj.cel = 0;
      }
      // Sierra Animate() calls SetLoop → SetCel, which may clamp + REPOS.
      obj.clipCelToScreen(horizon: horizon);
    }
  }

  void _updateObjectPosition(AnimatedObject obj, PriorityBuffer? priBuf) {
    // Sierra MOVEOBJS.C: REPOS means this cycle's step is skipped (SetCel /
    // reposition already moved the sprite). Still FindPosn the new cell.
    if (obj.reposThisCycle) {
      obj.reposThisCycle = false;
      posShuffle(obj);
      return;
    }

    var dx = 0;
    var dy = 0;

    switch (obj.motionType) {
      case 1: // wander
        if (obj.direction == 0 || _rng.nextInt(10) == 0) {
          obj.direction = _rng.nextInt(9);
        }
        break;

      case 2: // follow_ego
        final egoObj = animatedObjects[0];
        // Sierra FOLLOW.C: centers of baselines, MoveDir with endDist.
        final egoMidX = egoObj.x + egoObj.getCelWidth() ~/ 2;
        final objMidX = obj.x + obj.getCelWidth() ~/ 2;
        final endDist = obj.stepDistance > 0 ? obj.stepDistance : obj.stepSize;
        final dx = egoMidX - objMidX;
        final dy = egoObj.y - obj.y;
        if (dx.abs() < endDist && dy.abs() < endDist) {
          obj.direction = 0;
          obj.motionType = 0;
          if (obj.targetFlag != null) {
            memory.setFlag(obj.targetFlag!);
            obj.targetFlag = null;
          }
          if (obj.number == 0) {
            memory.setVar(6, 0);
            _isUserControl = true;
          }
          return;
        } else {
          final dirX = dx.abs() >= endDist ? (dx > 0 ? 1 : -1) : 0;
          final dirY = dy.abs() >= endDist ? (dy > 0 ? 1 : -1) : 0;
          obj.direction = AgiMotion.directionFromDelta(dirX, dirY);
        }
        break;

      case 3: // move_to
        final diffX = obj.targetX - obj.x;
        final diffY = obj.targetY - obj.y;
        if (diffX == 0 && diffY == 0) {
          _completeMoveObj(obj);
          return;
        } else {
          final dirX = diffX > 0 ? 1 : (diffX < 0 ? -1 : 0);
          final dirY = diffY > 0 ? 1 : (diffY < 0 ? -1 : 0);
          obj.direction = AgiMotion.directionFromDelta(dirX, dirY);
        }
        break;

      default: // normal
        break;
    }

    final delta = AgiMotion.delta(obj.direction);
    final step = obj.stepSize > 0 ? obj.stepSize : 1;
    if (obj.motionType == 3) {
      final diffX = obj.targetX - obj.x;
      final diffY = obj.targetY - obj.y;
      dx = delta.$1 * (diffX != 0 ? math.min(step, diffX.abs()) : step);
      dy = delta.$2 * (diffY != 0 ? math.min(step, diffY.abs()) : step);
    } else {
      dx = delta.$1 * step;
      dy = delta.$2 * step;
    }

    if (dx == 0 && dy == 0) return;

    final targetX = obj.x + dx;
    final targetY = obj.y + dy;

    // Determine cel dimensions for bounds & barrier checks
    final objWidth = obj.getCelWidth();
    final objHeight = obj.getCelHeight();

    // Screen boundary clamping
    const minX = 0;
    final maxX = (160 - objWidth).clamp(0, 159);
    final minScreenY = math.max(0, objHeight - 1);
    final minY = obj.ignoreHorizon ? minScreenY : math.max(horizon + 1, minScreenY);
    const maxY = 167;

    var clampedX = targetX.clamp(minX, maxX);
    var clampedY = targetY.clamp(minY, maxY);

    // Border collision triggers for variables %v2 (Ego) and %v4/%v5 (other objects)
    int border = 0;
    if ((!obj.ignoreHorizon && targetY <= horizon) || (targetY - objHeight < -1)) {
      border = 1; // Top (reaching/touching horizon line or screen top)
    } else if (targetX > maxX) {
      border = 2; // Right (moving beyond right boundary)
    } else if (targetY > maxY) {
      border = 3; // Bottom (moving beyond bottom boundary)
    } else if (targetX < minX) {
      border = 4; // Left (moving beyond left boundary)
    }

    if (obj.number == 0) {
      if (border != 0) {
        memory.setVar(2, border);
      }
    } else {
      if (border != 0) {
        memory.setVar(4, obj.number);
        memory.setVar(5, border);
      }
    }

    if (border != 0) {
      // Sierra MOVEOBJS.C: only `move.obj` (MOVETO) completes on a screen
      // edge. `follow.ego` must keep chasing — otherwise an NPC parked
      // off the right edge (SQ1 spider droid at x=164) "catches" Ego
      // from across the room the moment it tries to step back on-screen.
      if (obj.motionType == 3) {
        _completeMoveObj(obj, isBorderHit: true);
      }
    }

    // Script block boundary crossing check (matching Sierra AGI BLOCK.C & ANIMATE.C)
    if (!obj.ignoreBlocks && activeBlock != null && activeBlock!.crossesBoundary(obj.x, obj.y, clampedX, clampedY)) {
      if (obj.motionType == 1) {
        obj.direction = _rng.nextInt(9);
      } else if (obj.number == 0 && obj.motionType == 0) {
        obj.direction = 0;
        memory.setVar(6, 0);
        obj.isCycling = false;
      }
      return;
    }

    var actualTargetX = clampedX;
    var actualTargetY = clampedY;

    // Priority buffer collision (Sierra CanBHere). Auto-priority uses the
    // proposed Y-band so a released priority-15 drop-in still observes walls.
    if (priBuf != null &&
        !CollisionDetector.objectCanBeHere(
          priorityBuffer: priBuf,
          obj: obj,
          x: clampedX,
          y: clampedY,
          width: objWidth,
        )) {
      if (obj.motionType == 3) {
        // Corner-slip assistance for move.obj when a doorway or passage is slightly narrower than sprite alignment
        bool slipped = false;
        if (dx == 0 && dy != 0) {
          for (final nudge in const [-1, 1, -2, 2, -3, 3, -4, 4]) {
            final testX = (obj.x + nudge).clamp(0, 160 - objWidth);
            if (CollisionDetector.objectCanBeHere(
                  priorityBuffer: priBuf,
                  obj: obj,
                  x: testX,
                  y: clampedY,
                  width: objWidth,
                ) &&
                CollisionDetector.objectCanBeHere(
                  priorityBuffer: priBuf,
                  obj: obj,
                  x: testX,
                  y: obj.y,
                  width: objWidth,
                )) {
              actualTargetX = testX;
              slipped = true;
              break;
            }
          }
        } else if (dy == 0 && dx != 0) {
          for (final nudge in const [-1, 1, -2, 2, -3, 3, -4, 4]) {
            final minScreenY = math.max(0, obj.getCelHeight() - 1);
            final minY = obj.ignoreHorizon ? minScreenY : math.max(horizon, minScreenY);
            final testY = (obj.y + nudge).clamp(minY + 1, 167);
            if (CollisionDetector.objectCanBeHere(
                  priorityBuffer: priBuf,
                  obj: obj,
                  x: clampedX,
                  y: testY,
                  width: objWidth,
                ) &&
                CollisionDetector.objectCanBeHere(
                  priorityBuffer: priBuf,
                  obj: obj,
                  x: obj.x,
                  y: testY,
                  width: objWidth,
                )) {
              actualTargetY = testY;
              slipped = true;
              break;
            }
          }
        }
        if (!slipped) {
          posShuffle(obj);
          return;
        }
      } else {
        if (obj.motionType == 1) {
          obj.direction = _rng.nextInt(9);
        } else if (obj.number == 0 && obj.motionType == 0) {
          obj.direction = 0;
          memory.setVar(6, 0);
          obj.isCycling = false;
        }
        posShuffle(obj);
        return;
      }
    }

    // Object-to-object collision check (baseline intersection & crossing per Sierra COLLIDE.C)
    if (!obj.ignoreObjects) {
      for (final other in animatedObjects) {
        if (other.number == obj.number) continue;
        if (!other.isDrawn || !other.isAnimated || other.ignoreObjects) continue;
        if (obj.motionType == 2 && other.number == 0) continue;

        final otherWidth = other.getCelWidth();

        final aLeft = actualTargetX;
        final aRight = actualTargetX + objWidth - 1;
        final bLeft = other.x;
        final bRight = other.x + otherWidth - 1;

        if (aRight >= bLeft && aLeft <= bRight) {
          if (actualTargetY == other.y ||
              (actualTargetY > other.y && obj.prevY < other.prevY) ||
              (actualTargetY < other.y && obj.prevY > other.prevY)) {
            if (obj.motionType == 1) {
              obj.direction = _rng.nextInt(9);
            } else if (obj.number == 0 && obj.motionType == 0) {
              obj.direction = 0;
              memory.setVar(6, 0);
              obj.isCycling = false;
            }
            posShuffle(obj);
            return;
          }
        }
      }
    }

    obj.prevX = obj.x;
    obj.prevY = obj.y;
    obj.x = actualTargetX;
    obj.y = actualTargetY;
    CollisionDetector.syncAutoPriority(obj, obj.y);

    if (obj.motionType == 3) {
      if (obj.x == obj.targetX && obj.y == obj.targetY) {
        _completeMoveObj(obj);
      }
    }
  }

  /// Sierra `obj_cel_update` copies picbuff→screen for the **union** of the
  /// old and new cel rectangles. `display()` glyphs live only on the video
  /// buffer, so that refresh wipes them — SQ1 room 65 `reposition.to(o2, 113, 46)`
  /// from x=0 dirties ~153px and blanks the keypad dots in one shot, before
  /// the banner ever covers them.
  ///
  /// Ordinary 1-pixel steps must NOT do this: walking Ego would eat overlay
  /// `display()` text (SQ2 F6, notices, etc.).
  void _eraseVideoTextInBlitUnion(AnimatedObject obj, int newX, int newY) {
    if (!obj.isDrawn) return;
    final width = obj.getCelWidth();
    final height = obj.getCelHeight();
    if (width <= 0 || height <= 0) return;

    final minX = math.min(obj.x, newX);
    final maxX = math.max(obj.x, newX);
    final minY = math.min(obj.y, newY);
    final maxY = math.max(obj.y, newY);

    final left = minX;
    final right = maxX + width - 1;
    final bottom = maxY;
    final top = minY - height + 1;

    final startCol = (left / 4).floor();
    final endCol = (right / 4).floor();
    final startRow = (top / 8).floor() + _playfieldRow;
    final endRow = (bottom / 8).floor() + _playfieldRow;

    textScreenBuffer.clearTransparentGlyphs(
      row0: startRow,
      col0: startCol,
      row1: endRow,
      col1: endCol,
    );
  }

  void _completeMoveObj(AnimatedObject obj, {bool isBorderHit = false}) {
    obj.endMoveObj();
    if (obj.targetFlag != null) {
      memory.setFlag(obj.targetFlag!);
      obj.targetFlag = null;
    }
    if (obj.number == 0) {
      if (!isBorderHit) {
        obj.direction = 0;
        memory.setVar(6, 0);
      }
      _isUserControl = true;
    } else {
      obj.direction = 0;
    }
  }

  void _advanceObjectCel(AnimatedObject obj) {
    final celCount = obj.getCelCount();
    if (celCount <= 1) return;

    switch (obj.cycleMode) {
      case 0: // normal
        obj.cel = (obj.cel + 1) % celCount;
        break;
      case 1: // reverse
        obj.cel = (obj.cel - 1 + celCount) % celCount;
        break;
      case 2: // end_of_loop
        if (obj.cel < celCount - 1) {
          obj.cel++;
        }
        if (obj.cel >= celCount - 1) {
          obj.isCycling = false;
          obj.cycleMode = 0;
          obj.direction = 0;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
            obj.endOfLoopFlag = null;
          }
        }
        break;
      case 3: // reverse_loop
        if (obj.cel > 0) {
          obj.cel--;
        }
        if (obj.cel <= 0) {
          obj.isCycling = false;
          obj.cycleMode = 0;
          obj.direction = 0;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
            obj.endOfLoopFlag = null;
          }
        }
        break;
    }
    // Sierra ADVANCEL.C calls SetCel, which clamps a cel that hangs off-screen.
    obj.clipCelToScreen(horizon: horizon);
  }

  void _updateClock() {
    _clockTicks++;
    if (_clockTicks >= _speedHz.round().clamp(1, 100)) {
      _clockTicks = 0;
      final sec = (memory.getVar(11) + 1) & 0xFF;
      memory.setVar(11, sec);
      if (sec >= 60) {
        memory.setVar(11, 0);
        final min = (memory.getVar(12) + 1) & 0xFF;
        memory.setVar(12, min);
        if (min >= 60) {
          memory.setVar(12, 0);
          final hr = (memory.getVar(13) + 1) & 0xFF;
          memory.setVar(13, hr);
          if (hr >= 24) {
            memory.setVar(13, 0);
            memory.incrementVar(14); // days
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Room Transition Manager
  // ---------------------------------------------------------------------------

  /// Transitions engine to [roomNumber], adjusting Ego position and loading room scripts.
  void changeRoom(int roomNumber) {
    onStopSound();
    horizon = CollisionDetector.defaultHorizon;
    activeBlock = null;
    _addToPicCalls.clear();
    final currentRoom = memory.getVar(0);
    if (currentRoom != roomNumber) {
      memory.setVar(1, currentRoom); // %v1 = previous room
      memory.setVar(0, roomNumber); // %v0 = current room
    }
    memory.setFlag(5); // %f5 = new room first execution
    memory.resetFlag(0); // %f0 = on water
    memory.resetFlag(1); // %f1 = ego obscured
    memory.resetFlag(3); // %f3 = signal trigger line

    // Reposition Ego based on border crossed (%v2)
    final borderHit = memory.getVar(2);
    _repositionEgoForBorder(borderHit);

    // Reset transient edge hit variables, displayed text, and user control
    memory.setVar(2, 0);
    memory.setVar(4, 0);
    memory.setVar(5, 0);
    memory.setVar(9, 0);
    memory.resetFlag(2);
    memory.resetFlag(4);
    memory.resetControllers();
    _parsedWordIds.clear();
    _inputWords.clear();
    _bufferedCommands.clear();
    _bufferedControllers.clear();
    _bufferedEgoDirection = null;
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);

    // Reset modals, dialogs, timers, and prompts on room transition
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    _dialogAutoCloseTicks = null;
    activeDialog?.dismissCompleter?.complete();
    activeDialog = null;
    activeInputPrompt = null;

    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    _isTextScreen = false;
    _isUserControl = true;
    // Update variable 16 with current Ego view (matching Sierra NEWROOM.C var[CURRENT_EGO] = ego->view)
    memory.setVar(16, ego.view);

    // Unload non-Ego animated objects and reset Ego per-room state
    ego.resetForNewRoom(preserveDirection: borderHit != 0);
    final egoView = _loadedViews[ego.view];
    _loadedViews.clear();
    atlasManager.clear();
    if (egoView != null) {
      _loadedViews[ego.view] = egoView;
      atlasManager.registerView(egoView);
    }
    for (int i = 1; i < animatedObjects.length; i++) {
      animatedObjects[i].reset();
    }

    // Clear room picture until script explicitly draws new room picture via draw.pic
    currentPic?.dispose();
    currentPic = null;

    // Load root room logic (LOGIC 0) for rescan
    _loadedLogicNumbers.clear();
    _loadedLogicNumbers.add(0);
    _loadedLogicNumbers.add(roomNumber);
    if (resourceLoader != null && resourceLoader!.presentLogicNumbers.contains(0)) {
      final logic0 = resourceLoader!.loadLogic(0);
      interpreter.loadRootScript(logic0, scriptNumber: 0);
    }

    ego.updateCachedView(getView(ego.view));
    atlasManager.prepareAtlasAsync();

    notifyListeners();
  }

  /// Reloads room picture and root logic (LOGIC 0) after state restoration
  /// without resetting or wiping restored animated objects.
  void reloadRoomForRestore(
    int roomNumber, {
    int? pictureNumber,
    int? restoredHorizon,
    AgiBlockArea? restoredBlock,
    List<int>? loadedLogics,
    List<AgiAddToPicEntry>? addToPicEntries,
  }) {
    onStopSound();
    horizon = restoredHorizon ?? CollisionDetector.defaultHorizon;
    activeBlock = restoredBlock;
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    _isTextScreen = false;

    _addToPicCalls.clear();
    if (addToPicEntries != null) {
      _addToPicCalls.addAll(addToPicEntries);
    }

    // Reset modals, dialogs, timers, prompts, shake
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    _dialogAutoCloseTicks = null;
    activeDialog = null;
    activeInputPrompt = null;
    _isInventoryOpen = false;
    _inspectingObjectNumber = null;
    shakeOffsetX = 0.0;
    shakeOffsetY = 0.0;
    _shakeTicksRemaining = 0;
    _shakeCount = 0;
    if (isMenuOpen) {
      closeMenu();
    }

    // Reload view resources for all active objects and register them with atlasManager
    _loadedViews.clear();
    atlasManager.clear();
    if (resourceLoader != null) {
      for (final obj in animatedObjects) {
        if ((obj.isDrawn || obj.isAnimated || obj.view > 0) &&
            resourceLoader!.presentViewNumbers.contains(obj.view)) {
          final viewRes = resourceLoader!.loadView(obj.view);
          _loadedViews[obj.view] = viewRes;
          obj.updateCachedView(viewRes);
          atlasManager.registerView(viewRes);
        }
      }
      atlasManager.prepareAtlasAsync();
    }

    // Load room picture if recorded in snapshot; otherwise set currentPic to null (black screen)
    if (pictureNumber != null &&
        resourceLoader != null &&
        resourceLoader!.presentPicNumbers.contains(pictureNumber)) {
      currentPic?.dispose();
      currentPic = resourceLoader!.loadPic(pictureNumber);
      currentPic?.picNumber = pictureNumber;

      // Replay all recorded add.to.pic calls
      for (final call in _addToPicCalls) {
        try {
          _burnAddToPic(call);
        } catch (_) {}
      }

      if (_addToPicCalls.isNotEmpty) {
        final newSlices = PictureSlicer.slice(
          visualPixels: currentPic!.visualPixels,
          priorityBuffer: currentPic!.priorityBuffer,
        );
        for (final oldSlice in currentPic!.slices.values) {
          oldSlice.dispose();
        }
        currentPic!.slices.clear();
        currentPic!.slices.addAll(newSlices);
      }

      currentPic?.preloadGpuTextures();
    } else {
      currentPic?.dispose();
      currentPic = null;
    }

    // Load root room logic (LOGIC 0) and any restored active logics for execution scan
    _loadedLogicNumbers.clear();
    _loadedLogicNumbers.add(0);
    _loadedLogicNumbers.add(roomNumber);
    if (loadedLogics != null) {
      _loadedLogicNumbers.addAll(loadedLogics);
    }

    if (resourceLoader != null) {
      if (resourceLoader!.presentLogicNumbers.contains(0)) {
        final logic0 = resourceLoader!.loadLogic(0);
        interpreter.loadRootScript(logic0, scriptNumber: 0);
      }

      // Preload all active secondary logics if present
      for (final logicNum in _loadedLogicNumbers) {
        if (logicNum != 0 && resourceLoader!.presentLogicNumbers.contains(logicNum)) {
          try {
            resourceLoader!.loadLogic(logicNum);
          } catch (_) {}
        }
      }
    }

    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);

    notifyListeners();
  }

  void _repositionEgoForBorder(int border) {
    final egoWidth = ego.getCelWidth();

    switch (border) {
      case 1: // Top (Horizon) -> place at bottom
        ego.y = 167;
        break;
      case 2: // Right -> place at left
        ego.x = 0;
        break;
      case 3: // Bottom -> place at top (Horizon + 1)
        ego.y = (ego.ignoreHorizon ? 0 : horizon) + 1;
        break;
      case 4: // Left -> place at right
        ego.x = (160 - egoWidth).clamp(0, 159);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // AgiInterpreterDelegate Implementation
  // ---------------------------------------------------------------------------

  @override
  void onNewRoom(int roomNumber) {
    changeRoom(roomNumber);
  }

  @override
  AgiLogicScript? loadLogic(int logicNumber) {
    _loadedLogicNumbers.add(logicNumber);
    if (resourceLoader != null && resourceLoader!.presentLogicNumbers.contains(logicNumber)) {
      return resourceLoader!.loadLogic(logicNumber);
    }
    return null;
  }

  @override
  AgiView? getView(int viewNumber) {
    final cached = _loadedViews[viewNumber];
    if (cached != null) return cached;

    if (resourceLoader != null && resourceLoader!.presentViewNumbers.contains(viewNumber)) {
      try {
        final view = resourceLoader!.loadView(viewNumber);
        _loadedViews[viewNumber] = view;
        atlasManager.registerView(view);
        return view;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  AgiDictionary? get dictionary => resourceLoader?.dictionary ?? _customDictionary;

  @override
  String? wordToString(int wordId) {
    final dict = dictionary;
    if (dict != null) {
      final words = dict.idToWords(wordId);
      if (words.isNotEmpty) return words.first;
    }
    return null;
  }

  @override
  void onParse(String input) {
    final clean = input.trim();
    if (clean.isEmpty) {
      _parsedWordIds.clear();
      _inputWords.clear();
      memory.resetFlag(2);
      memory.resetFlag(4);
      memory.setVar(9, 0);
    } else {
      _applyCommand(clean);
    }
  }

  @override
  Future<String?> onGetString(String prompt, int row, int col, int maxLen) {
    final completer = Completer<String?>();
    final formatted = formatMessage(prompt);
    if (row < AgiTextScreenBuffer.rows && formatted.isNotEmpty) {
      textScreenBuffer.writeString(row, col, formatted, fg: _textFgColor, bg: _textBgColor);
    }
    activeInputPrompt = AgiInputPromptState(
      type: AgiInputPromptType.string,
      prompt: formatted,
      row: row,
      col: col,
      maxLen: maxLen,
      stringCompleter: completer,
    );
    notifyListeners();
    return completer.future;
  }

  @override
  Future<int?> onGetNum(String prompt) {
    final completer = Completer<int?>();
    final formatted = formatMessage(prompt);
    activeInputPrompt = AgiInputPromptState(
      type: AgiInputPromptType.number,
      prompt: formatted,
      maxLen: 3,
      numCompleter: completer,
    );
    notifyListeners();
    return completer.future;
  }

  @override
  FutureOr<void> onPrint(String message, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    return _showDialog(
      message: message,
      isModal: isModal,
      timeoutHalfSeconds: timeoutHalfSeconds,
    );
  }

  @override
  FutureOr<void> onPrintAt(String message, int row, int col, int width, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    return _showDialog(
      message: message,
      row: row,
      col: col,
      width: width,
      isModal: isModal,
      timeoutHalfSeconds: timeoutHalfSeconds,
    );
  }

  FutureOr<void> _showDialog({
    required String message,
    int? row,
    int? col,
    int? width,
    bool isModal = true,
    int timeoutHalfSeconds = 0,
  }) {
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;

    final completer = Completer<void>();
    final autoCloseTicks = timeoutHalfSeconds > 0 ? (timeoutHalfSeconds * (_speedHz / 2)).round() : null;
    activeDialog = AgiDialogState(
      message: formatMessage(message),
      row: row,
      col: col,
      width: width,
      isModal: isModal,
      dismissCompleter: completer,
      autoCloseHalfSeconds: timeoutHalfSeconds > 0 ? timeoutHalfSeconds : null,
      autoCloseTicks: autoCloseTicks,
    );

    if (timeoutHalfSeconds > 0) {
      _dialogAutoCloseTicks = autoCloseTicks;
      final ms = timeoutHalfSeconds * 500;
      _dialogAutoCloseTimer = Timer(Duration(milliseconds: ms), () {
        dismissDialog();
      });
    } else {
      _dialogAutoCloseTicks = null;
    }

    final f1 = currentPic?.preloadGpuTextures();
    final f2 = atlasManager.prepareAtlasAsync();
    if (f1 is Future || f2 is Future) {
      return Future.wait<dynamic>([
        if (f1 is Future) f1,
        if (f2 is Future) f2 as Future,
      ]).then((_) {
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void onCloseWindow() {
    dismissDialog();
  }

  @override
  void onDisplay(int row, int col, String message) {
    final formatted = formatMessage(message);
    _displayedTexts.removeWhere((t) => t.row == row && t.col == col);
    _displayedTexts.add(AgiDisplayText(row: row, col: col, message: formatted));
    textScreenBuffer.writeString(row, col, formatted, fg: _textFgColor, bg: _textBgColor);
    notifyListeners();
  }

  @override
  void onClearLines(int top, int bottom, int color) {
    _displayedTexts.removeWhere((t) => t.row >= top && t.row <= bottom);
    textScreenBuffer.clearLines(top, bottom, color);
    notifyListeners();
  }

  @override
  void onClearTextRect(int top, int left, int bottom, int right, int color) {
    _displayedTexts.removeWhere(
      (t) => t.row >= top && t.row <= bottom && t.col >= left && t.col <= right,
    );
    textScreenBuffer.clearTextRect(top, left, bottom, right, color);
    notifyListeners();
  }

  @override
  void onSetTextAttribute(int fg, int bg) {
    _textFgColor = fg.clamp(0, 15);
    _textBgColor = bg.clamp(0, 15);
    textScreenBuffer.currentFg = _textFgColor;
    textScreenBuffer.currentBg = _textBgColor;
  }

  @override
  void onStatusLine(bool enabled) {
    _isStatusLineEnabled = enabled;
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    notifyListeners();
  }

  /// Shifts an object in an expanding counter-clockwise spiral until it rests
  /// in a valid, walkable screen position (matching Sierra AGI `obj_pos_shuffle`).
  void posShuffle(AnimatedObject obj) {
    final priBuf = currentPic?.priorityBuffer;
    if (priBuf == null) return;

    final objHeight = obj.getCelHeight();
    final minScreenY = math.max(0, objHeight - 1);

    if (!obj.ignoreHorizon && obj.y <= horizon) {
      obj.y = horizon + 1;
      obj.prevY = obj.y;
    } else if (obj.ignoreHorizon && obj.y < minScreenY) {
      obj.y = minScreenY;
      obj.prevY = obj.y;
    }

    bool isWalkablePos(int x, int y) {
      final w = obj.getCelWidth();
      final h = obj.getCelHeight();
      final minWalkY = obj.ignoreHorizon ? math.max(0, h - 1) : math.max(horizon, math.max(0, h - 1));
      if (x < 0 || x + w > 160 || y > 167 || y <= minWalkY || (y - h < -1)) {
        return false;
      }
      if (!CollisionDetector.objectCanBeHere(
        priorityBuffer: priBuf,
        obj: obj,
        x: x,
        y: y,
        width: w,
      )) {
        return false;
      }
      if (!obj.ignoreObjects) {
        for (final other in animatedObjects) {
          if (other.number == obj.number) continue;
          if (!other.isDrawn || !other.isAnimated || other.ignoreObjects) continue;
          if (obj.motionType == 2 && other.number == 0) continue;

          final otherWidth = other.getCelWidth();
          final aLeft = x;
          final aRight = x + w - 1;
          final bLeft = other.x;
          final bRight = other.x + otherWidth - 1;

          if (aRight >= bLeft && aLeft <= bRight) {
            if (y == other.y ||
                (y > other.y && obj.prevY < other.prevY) ||
                (y < other.y && obj.prevY > other.prevY)) {
              return false;
            }
          }
        }
      }
      return true;
    }

    if (isWalkablePos(obj.x, obj.y)) {
      CollisionDetector.syncAutoPriority(obj, obj.y);
      return;
    }

    var shiftDir = 0;
    var shiftCount = 1;
    var shiftSize = 1;

    // Sierra FINDPOSN.C spirals with no iteration cap until GoodPos.
    // 500 steps only reaches a radius of ~11px, which parks a 20px-wide
    // sprite (SQ1 view 46) off the right edge when spawned near x=153.
    for (int iter = 0; iter < 160 * 168; iter++) {
      switch (shiftDir) {
        case 0: // left
          obj.x--;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 1;
            shiftCount = shiftSize;
          }
          break;
        case 1: // down
          obj.y++;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 2;
            shiftSize++;
            shiftCount = shiftSize;
          }
          break;
        case 2: // right
          obj.x++;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 3;
            shiftCount = shiftSize;
          }
          break;
        case 3: // up
          obj.y--;
          shiftCount--;
          if (shiftCount == 0) {
            shiftDir = 0;
            shiftSize++;
            shiftCount = shiftSize;
          }
          break;
      }

      if (isWalkablePos(obj.x, obj.y)) {
        obj.prevX = obj.x;
        obj.prevY = obj.y;
        CollisionDetector.syncAutoPriority(obj, obj.y);
        return;
      }
    }
  }

  @override
  FutureOr<void> onDraw(AnimatedObject obj) {
    final view = getView(obj.view);
    obj.updateCachedView(view);
    final minScreenY = math.max(0, obj.getCelHeight() - 1);
    final minY = obj.ignoreHorizon ? minScreenY : math.max(horizon, minScreenY);
    if (obj.y <= minY) {
      obj.y = minY + 1;
      obj.prevY = obj.y;
    }
    posShuffle(obj);
    if (obj.number == 0) {
      _updateEgoFlags(currentPic?.priorityBuffer);
    }
    if (view != null && !atlasManager.containsView(obj.view)) {
      atlasManager.registerView(view);
      return atlasManager.prepareAtlasAsync();
    }
  }

  @override
  void onStartUpdate(AnimatedObject obj) {}

  @override
  void onErase(AnimatedObject obj) {}

  @override
  void onReposition(AnimatedObject obj, int newX, int newY) {
    _eraseVideoTextInBlitUnion(obj, newX, newY);
    posShuffle(obj);
  }

  @override
  void onMoveObj(AnimatedObject obj, int targetX, int targetY) {}

  @override
  void onSetHorizon(int horizon) {
    this.horizon = horizon;
    for (final obj in animatedObjects) {
      final minScreenY = math.max(0, obj.getCelHeight() - 1);
      final minY = obj.ignoreHorizon ? minScreenY : math.max(horizon, minScreenY);
      if (obj.y <= minY) {
        obj.y = minY + 1;
        obj.prevY = obj.y;
      }
    }
  }

  @override
  void onBlock(int x1, int y1, int x2, int y2) {
    activeBlock = AgiBlockArea(x1: x1, y1: y1, x2: x2, y2: y2);
  }

  @override
  void onUnblock() {
    activeBlock = null;
  }

  @override
  void onSetPriBase(int priorityBase) {
    // Version check: only supported in AGI v3 and late v2 (>= 2.936, == 2.425)
    final isV3 = resourceLoader?.meta.isV3 ?? true;
    final ver = resourceLoader?.meta.version;
    if (!isV3 && (ver != null && ver < 2.936 && ver != 2.425)) {
      return;
    }
    setPriorityBase(priorityBase);
  }

  /// Sets dynamic priority base (Opcode 174 `set.pri.base`) and recalculates auto-priority objects.
  void setPriorityBase(int priorityBase) {
    priorityTable.setPriorityBase(priorityBase);
    for (final obj in animatedObjects) {
      if (!obj.fixedPriority) {
        CollisionDetector.syncAutoPriority(obj, obj.y);
      }
    }
  }

  /// Resets the priority table back to default static AGI bands (base 48).
  void resetPriorityTable() {
    priorityTable.createDefaultTable();
    for (final obj in animatedObjects) {
      if (!obj.fixedPriority) {
        CollisionDetector.syncAutoPriority(obj, obj.y);
      }
    }
  }

  @override
  void onInputMode(bool enabled) {
    _isInputEnabled = enabled;
    notifyListeners();
  }

  @override
  void onUserControl(bool enabled) {
    _isUserControl = enabled;
    notifyListeners();
  }

  @override
  void onTextScreen() {
    _isTextScreen = true;
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    notifyListeners();
  }

  @override
  void onGraphics() {
    _isTextScreen = false;
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    notifyListeners();
  }

  @override
  FutureOr<void> onShakeScreen(int count) async {
    _shakeCount = count;
    final totalSteps = (count * 8).clamp(8, 48);
    for (int step = 0; step < totalSteps; step++) {
      if ((step & 1) == 1) {
        shakeOffsetY = 0.0;
        shakeOffsetX = 0.0;
      } else {
        shakeOffsetY = (step % 4 == 0) ? -3.0 : 3.0;
        shakeOffsetX = (step % 3 == 0) ? 2.0 : -2.0;
      }
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    shakeOffsetX = 0.0;
    shakeOffsetY = 0.0;
    _shakeTicksRemaining = 0;
    notifyListeners();
  }

  @override
  void onConfigureScreen(int playTop, int inputLine, int statusLine) {
    _playfieldRow = playTop;
    _inputRow = inputLine;
    _statusRow = statusLine;
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    notifyListeners();
  }

  @override
  void onSetMenu(String menuName) {
    menuManager.addMenu(menuName);
    notifyListeners();
  }

  @override
  void onSetMenuItem(String itemName, int controllerSlot) {
    menuManager.addMenuItem(itemName, controllerSlot);
    notifyListeners();
  }

  @override
  void onSubmitMenu() {
    menuManager.submit();
    memory.setFlag(14); // Flag 14 = Menu enabled
    notifyListeners();
  }

  @override
  void onEnableItem(int controllerSlot) {
    menuManager.enableItem(controllerSlot);
    notifyListeners();
  }

  @override
  void onDisableItem(int controllerSlot) {
    menuManager.disableItem(controllerSlot);
    notifyListeners();
  }

  @override
  void onMenuInput() {
    if (memory.getFlag(14) && menuManager.isAvailable) {
      openMenu();
    }
  }

  void _onSoundFinished() {
    if (_activeSoundEndFlag != null) {
      memory.setFlag(_activeSoundEndFlag!);
      _activeSoundEndFlag = null;
    }
  }

  @override
  void onSound(int soundNumber, int completionFlag) {
    // If a sound is currently playing, stopping/preempting sets its completion flag
    if (_activeSoundEndFlag != null) {
      memory.setFlag(_activeSoundEndFlag!);
      _activeSoundEndFlag = null;
    }

    // Set the new sound's completion flag to false per AGI specification
    memory.resetFlag(completionFlag);

    final isMuted = !memory.getFlag(9) || _soundMode == AgiSoundMode.off;

    if (resourceLoader != null) {
      if (resourceLoader!.presentSoundNumbers.contains(soundNumber)) {
        final snd = resourceLoader!.loadSound(soundNumber);
        if (!snd.isEmpty && snd.length > 0) {
          _activeSoundEndFlag = completionFlag;
          soundPlayer.play(
            snd,
            config: _synthesizerConfig,
            muted: isMuted,
          ).catchError((_) {
            if (_activeSoundEndFlag == completionFlag) {
              memory.setFlag(completionFlag);
              _activeSoundEndFlag = null;
            }
          });
          return;
        }
      }
    }
    // If sound resource is not present or sound player is unavailable, complete immediately
    memory.setFlag(completionFlag);
  }

  @override
  void onStopSound() {
    if (_activeSoundEndFlag != null) {
      memory.setFlag(_activeSoundEndFlag!);
      _activeSoundEndFlag = null;
    }
    soundPlayer.stop();
  }

  @override
  FutureOr<void> onLoadPic(int picNumber) {
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(picNumber)) {
      resourceLoader!.loadRawPic(picNumber);
    }
  }

  @override
  FutureOr<void> onDrawPic(int picNumber) {
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(picNumber)) {
      currentPic?.dispose();
      currentPic = resourceLoader!.loadPic(picNumber);
      currentPic?.picNumber = picNumber;
      textScreenBuffer.clearLines(_playfieldRow, _playfieldRow + 20, 0);
      _displayedTexts.removeWhere((t) => t.row >= _playfieldRow && t.row <= _playfieldRow + 20);
      for (final obj in animatedObjects) {
        if (obj.isDrawn) {
          posShuffle(obj);
        }
      }
      _updateEgoFlags(currentPic?.priorityBuffer);
      return currentPic?.preloadGpuTextures();
    }
  }

  @override
  FutureOr<void> onShowPic() {
    for (final obj in animatedObjects) {
      if (obj.isDrawn) {
        posShuffle(obj);
      }
    }
    _updateEgoFlags(currentPic?.priorityBuffer);
    final f1 = currentPic?.preloadGpuTextures();
    final f2 = atlasManager.prepareAtlasAsync();
    if (f1 is Future || f2 is Future) {
      return Future.wait<dynamic>([
        if (f1 is Future) f1,
        if (f2 is Future) f2 as Future,
      ]).then((_) {
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void onOverlayPic(int picNumber) {}

  @override
  void onShowPriScreen() {}

  @override
  void onDiscardPic(int picNumber) {
    // Picture caches can be purged if needed
  }

  @override
  void onLoadView(int viewNumber) {
    if (resourceLoader != null && resourceLoader!.presentViewNumbers.contains(viewNumber)) {
      try {
        final view = resourceLoader!.loadView(viewNumber);
        _loadedViews[viewNumber] = view;
        atlasManager.registerView(view);
      } catch (_) {}
    }
  }

  @override
  void onDiscardView(int viewNumber) {
    _loadedViews.remove(viewNumber);
    atlasManager.unregisterView(viewNumber);
  }

  @override
  FutureOr<void> onAddToPic(int view, int loop, int cel, int x, int y, int pri, int boxPri) {
    final entry = AgiAddToPicEntry(
      view: view,
      loop: loop,
      cel: cel,
      x: x,
      y: y,
      priority: pri,
      boxPriority: boxPri,
    );
    _addToPicCalls.add(entry);
    if (resourceLoader == null || currentPic == null) return null;

    try {
      final viewRes = resourceLoader!.loadView(entry.view);
      final celRes = viewRes.getCel(entry.loop, entry.cel);
      if (celRes == null) return null;

      final startY = entry.y - celRes.height + 1;
      final dirtyPriorities = <int>{};
      // Stamp may lower a pixel's priority. Collect bands from the cel
      // rectangle both before and after the burn so leftover opaque texels
      // are cleared from the old slice (painter's algorithm would otherwise
      // keep occluding actors between the two bands).
      _collectEffectivePrioritiesInRect(
        dirtyPriorities,
        x: entry.x,
        y: startY,
        width: celRes.width,
        height: celRes.height,
      );
      _burnAddToPic(entry);
      _collectEffectivePrioritiesInRect(
        dirtyPriorities,
        x: entry.x,
        y: startY,
        width: celRes.width,
        height: celRes.height,
      );
      if (entry.priority > 0) {
        dirtyPriorities.add(entry.priority);
      }
      if (entry.boxPriority > 0) {
        dirtyPriorities.add(entry.boxPriority);
      }

      // Re-slice only the dirty priority levels and re-upload GPU textures
      final futures = <Future<ui.Image>>[];
      for (final pri in dirtyPriorities) {
        final oldSlice = currentPic!.slices[pri];
        oldSlice?.dispose();
        final newSlice = PictureSlicer.sliceSinglePriority(
          visualPixels: currentPic!.visualPixels,
          priorityBuffer: currentPic!.priorityBuffer,
          priority: pri,
        );
        currentPic!.slices[pri] = newSlice;
        if (newSlice.hasVisiblePixels) {
          futures.add(newSlice.toUiImage());
        }
      }

      if (futures.isNotEmpty) {
        return Future.wait(futures).then((_) {});
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error executing add.to.pic: $e');
      }
    }
  }

  void _collectEffectivePrioritiesInRect(
    Set<int> out, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final pic = currentPic;
    if (pic == null) return;
    for (int r = y; r < y + height; r++) {
      if (r < 0 || r >= AgiPic.nativeHeight) continue;
      for (int c = x; c < x + width; c++) {
        if (c < 0 || c >= AgiPic.nativeWidth) continue;
        out.add(pic.priorityBuffer.effectivePriorityAt(c, r));
      }
    }
  }

  void _burnAddToPic(AgiAddToPicEntry entry) {
    if (resourceLoader == null || currentPic == null) return;

    final viewRes = resourceLoader!.loadView(entry.view);
    final celRes = viewRes.getCel(entry.loop, entry.cel);
    if (celRes == null) return;

    final pixels = celRes.getPixels(parentView: viewRes, celIndex: entry.cel);
    final cw = celRes.width;
    final ch = celRes.height;
    final startY = entry.y - ch + 1;

    final effectivePri = entry.priority > 0 ? entry.priority : 4;

    // Burn pixels into visual buffer and priority buffer respecting background priority
    for (int cy = 0; cy < ch; cy++) {
      final py = startY + cy;
      if (py < 0 || py >= AgiPic.nativeHeight) continue;

      for (int cx = 0; cx < cw; cx++) {
        final px = entry.x + cx;
        if (px < 0 || px >= AgiPic.nativeWidth) continue;

        final colorIndex = pixels[cy * cw + cx] & 0x0F;
        if (colorIndex != celRes.transparentColor) {
          final bgPri = currentPic!.priorityBuffer.priorityAt(px, py);
          // In Sierra AGI: sprite pixels are only drawn if sprite priority >= background priority.
          if (effectivePri >= bgPri) {
            currentPic!.visualPixels[py * AgiPic.nativeWidth + px] = colorIndex;
            if (entry.priority > 0) {
              currentPic!.priorityBuffer.setPriorityAt(px, py, entry.priority);
            }
          }
        }
      }
    }

    // If boxPri > 0, burn solid priority bar at base
    if (entry.boxPriority > 0 && entry.y >= 0 && entry.y < AgiPic.nativeHeight) {
      for (int bx = entry.x; bx < entry.x + cw; bx++) {
        if (bx >= 0 && bx < AgiPic.nativeWidth) {
          currentPic!.priorityBuffer.setPriorityAt(bx, entry.y, entry.boxPriority);
        }
      }
    }
  }

  @override
  FutureOr<void> onStatus() {
    _isInventoryOpen = true;
    final f1 = currentPic?.preloadGpuTextures();
    final f2 = atlasManager.prepareAtlasAsync();
    if (f1 is Future || f2 is Future) {
      return Future.wait<dynamic>([
        if (f1 is Future) f1,
        if (f2 is Future) f2 as Future,
      ]).then((_) {
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  FutureOr<void> onShowObj(int objNumber) {
    _inspectingObjectNumber = objNumber;
    final f1 = currentPic?.preloadGpuTextures();
    final f2 = atlasManager.prepareAtlasAsync();
    if (f1 is Future || f2 is Future) {
      return Future.wait<dynamic>([
        if (f1 is Future) f1,
        if (f2 is Future) f2 as Future,
      ]).then((_) {
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void onQuit() {
    stop();
  }

  @override
  void onPause() {
    pause();
  }

  @override
  void onLog(String message) {
    if (kDebugMode) {
      print('[AGI LOG] $message');
    }
  }

  @override
  void onSetKey(int scancode, int ascii, int controllerCode) {
    controllerManager.setKey(scancode, ascii, controllerCode);
  }

  @override
  void onSaveGame() {
    if (onSaveGameRequested != null) {
      onSaveGameRequested!();
    } else {
      saveGameState(slot: 1);
    }
  }

  @override
  void onRestoreGame() {
    if (onRestoreGameRequested != null) {
      onRestoreGameRequested!();
    } else {
      restoreGameState(slot: 1);
    }
  }

  @override
  void onRestartGame() {
    if (onRestartGameRequested != null) {
      onRestartGameRequested!();
    } else {
      restartGame();
    }
  }

  /// Triggers controller action by [controllerCode] (0..49) and notifies listeners.
  void triggerController(int controllerCode) {
    if (_isRunning) {
      _bufferedControllers.add(controllerCode);
    } else {
      controllerManager.triggerController(controllerCode, memory);
    }
    notifyListeners();
  }

  /// Saves current game state to save slot [slot] (1..12).
  Future<File> saveGameState({
    int slot = 1,
    String description = '',
    Directory? directory,
  }) async {
    return GameStateSerializer.saveToSlot(
      this,
      slot,
      description: description,
      directory: directory ?? saveDirectory,
    );
  }

  /// Restores game state from save slot [slot] (1..12).
  Future<bool> restoreGameState({
    int slot = 1,
    Directory? directory,
  }) async {
    final success = await GameStateSerializer.restoreFromSlot(
      this,
      slot,
      directory: directory ?? saveDirectory,
    );
    if (success) {
      menuManager.enableAllItems();
      _statusLineNeedsRedraw = true;
      updateStatusLine(force: true);
      notifyListeners();
    }
    return success;
  }

  /// Restores state from an existing [AgiGameStateSnapshot].
  /// By default, preserves the current pause state at the moment of restoration.
  void restoreFromSnapshot(AgiGameStateSnapshot snapshot, {bool? preservePauseState}) {
    restoreSnapshot(snapshot, preservePauseState: preservePauseState);
  }

  /// Restarts the game, resetting variables, flags, strings, inventory to initial game state,
  /// reloading starting room and root Logic 0, and raising Flag 5, Flag 6, and Flag 11.
  void restartGame({int startingRoom = 0}) {
    memory.reset();

    // System variables
    memory.setVar(0, 0); // %v0 = current.room
    memory.setVar(1, 0); // %v1 = previous.room
    memory.setVar(8, 10); // %v8 = free memory pages
    memory.setVar(20, 0); // %v20 = computer type (IBM PC)
    memory.setVar(22, 1); // %v22 = sound voices
    memory.setVar(24, 41); // %v24 = max input length
    memory.setVar(26, 0); // %v26 = monitor type

    // System flags
    memory.setFlag(5); // %f5 = new room init
    memory.setFlag(6); // %f6 = restart in progress
    memory.setFlag(9); // %f9 = sound on
    memory.setFlag(11); // %f11 = logic 0 first run

    for (final obj in animatedObjects) {
      obj.reset();
    }

    if (resourceLoader != null) {
      // Reload initial inventory object locations
      for (int i = 0; i < resourceLoader!.initialObjects.length; i++) {
        final item = resourceLoader!.initialObjects[i];
        memory.itemRooms[i] = item.startingRoom;
      }

      // Reload root Logic 0
      if (resourceLoader!.presentLogicNumbers.contains(0)) {
        final logic0 = resourceLoader!.loadLogic(0);
        interpreter.loadRootScript(logic0, scriptNumber: 0);
      }
    }

    _cycleCount = 0;
    _clockTicks = 0;
    _parsedWordIds.clear();
    _lastSubmittedCommand = null;
    _displayedTexts.clear();

    if (startingRoom != 0) {
      changeRoom(startingRoom);
    }

    // Run initial startup scan
    if (interpreter.currentFrame != null) {
      try {
        interpreter.executeCycle();
      } catch (e) {
        _lastError = 'Restart error: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    memory.resetFlag(5);
    memory.resetFlag(6);

    menuManager.enableAllItems();
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);

    notifyListeners();
  }

  /// Refreshes the top status line in [textScreenBuffer] when score or sound state changes.
  void updateStatusLine({bool force = false}) {
    if (_isStatusLineEnabled && !menuManager.isOpen) {
      final curScore = score;
      final curMax = maxScore;
      final curSound = isSoundOn;
      if (force ||
          _statusLineNeedsRedraw ||
          curScore != _lastStatusScore ||
          curMax != _lastStatusMaxScore ||
          curSound != _lastStatusSoundOn) {
        _lastStatusScore = curScore;
        _lastStatusMaxScore = curMax;
        _lastStatusSoundOn = curSound;
        _statusLineNeedsRedraw = false;
        textScreenBuffer.clearLines(_statusRow, _statusRow, 15);
        textScreenBuffer.writeString(_statusRow, 1, 'Score: $curScore of $curMax', fg: 0, bg: 15);
        textScreenBuffer.writeString(_statusRow, 30, curSound ? 'Sound:on' : 'Sound:off', fg: 0, bg: 15);
        notifyListeners();
      }
    } else if (!_isStatusLineEnabled) {
      if (_statusLineNeedsRedraw) {
        textScreenBuffer.clearLines(_statusRow, _statusRow, 0);
        _statusLineNeedsRedraw = false;
        notifyListeners();
      }
    }
  }

  /// Opens the interactive menu system if available and enabled (Flag 14).
  void openMenu({int? menuIndex}) {
    if (!menuManager.isAvailable || !memory.getFlag(14)) return;
    menuManager.openMenu(menuIndex: menuIndex);
    notifyListeners();
  }

  /// Closes the interactive menu system and restores the status line.
  void closeMenu() {
    if (!menuManager.isOpen) return;
    menuManager.closeMenu();
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    notifyListeners();
  }

  /// Selects the current or specified menu item and triggers its controller slot.
  void selectMenuItem({int? controllerSlot}) {
    final slot = controllerSlot ?? menuManager.selectCurrentItem();
    if (slot != null) {
      menuManager.closeMenu();
      _statusLineNeedsRedraw = true;
      updateStatusLine(force: true);
      controllerManager.triggerController(slot, memory);
      notifyListeners();
    }
  }

  /// Navigates to the previous menu category.
  void navigateMenuLeft() {
    menuManager.navigateLeft();
    notifyListeners();
  }

  /// Navigates to the next menu category.
  void navigateMenuRight() {
    menuManager.navigateRight();
    notifyListeners();
  }

  /// Navigates to the previous item in the active menu.
  void navigateMenuUp() {
    menuManager.navigateUp();
    notifyListeners();
  }

  /// Navigates to the next item in the active menu.
  void navigateMenuDown() {
    menuManager.navigateDown();
    notifyListeners();
  }

  /// Cancels restart by setting Flag 16.
  void cancelRestart() {
    memory.setFlag(16);
    notifyListeners();
  }

  @override
  bool checkSaid(List<int> wordGroupIds) {
    // In Sierra AGI, said() only matches if user input was entered this cycle (Flag 2)
    // and no previous said() check has claimed/accepted the input (Flag 4).
    if (!memory.getFlag(2) || memory.getFlag(4)) {
      return false;
    }

    if (AgiSaidMatcher.matchWords(wordGroupIds, _parsedWordIds)) {
      memory.setFlag(4); // said.accepted = 1
      return true;
    }

    return false;
  }

  @override
  bool haveKey() => _keyPressedThisCycle;

  /// Registers that a key was pressed by the player.
  void handleKeyPress([int? rawKeyCode]) {
    _keyPressedThisCycle = true;
    if (rawKeyCode != null) {
      memory.setVar(19, rawKeyCode & 0xFF); // %v19: LAST_CHAR
    }
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    onStopSound();
    stop();
    if (_ownsSoundPlayer) {
      soundPlayer.dispose();
    }
    currentPic?.dispose();
    currentPic = null;
    atlasManager.dispose();
    super.dispose();
  }
}
