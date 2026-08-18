import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:flutter_agigame/engine/controllers/agi_controller_manager.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:flutter_agigame/engine/parser/agi_said_matcher.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

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

  int? get x => col;
  int? get y => row;

  const AgiDialogState({
    required this.message,
    this.row,
    this.col,
    this.width,
    this.isModal = true,
    this.dismissCompleter,
    this.autoCloseHalfSeconds,
    this.autoCloseTicks,
  });
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
  final AgiSoundPlayer? soundPlayer;
  final AgiMemory memory;
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
  Timer? _gameLoopTimer;
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
  int horizon = CollisionDetector.defaultHorizon;
  AgiBlockArea? activeBlock;

  final AgiDictionary? _customDictionary;

  /// Manages keyboard shortcut and function key mappings (`set.key`).
  final AgiControllerManager controllerManager = AgiControllerManager();

  /// Manages AGI menu bar and dropdown hierarchy.
  final AgiMenuManager menuManager = AgiMenuManager();

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
    this.soundPlayer,
    AgiDictionary? dictionary,
    AgiMemory? memory,
    List<AnimatedObject>? animatedObjects,
    List<AgiObject>? objects,
    this._speedHz = 20.0,
    int? randomSeed,
    int maxAnimatedObjects = 64,
  })  : _customDictionary = dictionary,
        memory = memory ?? AgiMemory(),
        animatedObjects = animatedObjects ??
            List.generate(maxAnimatedObjects, (i) => AnimatedObject(number: i)),
        _customObjects = objects,
        _rng = randomSeed != null ? math.Random(randomSeed) : math.Random() {
    if (soundPlayer != null) {
      soundPlayer!.onFinished = _onSoundFinished;
    }

    interpreter = AgiLogicInterpreter(
      memory: this.memory,
      animatedObjects: this.animatedObjects,
      delegate: this,
      randomSeed: randomSeed,
      maxAnimatedObjects: maxAnimatedObjects,
    );

    // Initial default state: Sound ON by default
    this.memory.setFlag(9);
  }

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
  void closeInventory([int? selectedObjectNumber]) {
    _isInventoryOpen = false;
    if (memory.getFlag(13)) {
      final selected = selectedObjectNumber ?? 255;
      memory.setVar(25, selected);
    }
    if (interpreter.hasPendingInput) {
      final status = interpreter.resumeWithInput(selectedObjectNumber != null ? '$selectedObjectNumber' : null);
      if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
    }
    notifyListeners();
  }

  /// Opens the object inspection modal for [objectNumber] and pauses game tick updates.
  void inspectObject(int objectNumber) {
    onShowObj(objectNumber);
  }

  /// Closes the object inspection modal.
  void closeObjectInspection() {
    _inspectingObjectNumber = null;
    if (interpreter.hasPendingInput) {
      final status = interpreter.resumeWithInput(null);
      if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
    }
    notifyListeners();
  }

  /// Starts the game loop timer.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _isPaused = false;
    _scheduleLoop();
    notifyListeners();
  }

  /// Pauses the game loop and sound playback.
  void pause() {
    _isPaused = true;
    soundPlayer?.pause();
    notifyListeners();
  }

  /// Resumes a paused game loop and sound playback.
  void resume() {
    _isPaused = false;
    soundPlayer?.resume();
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
    if (_isRunning) {
      _gameLoopTimer?.cancel();
      _scheduleLoop();
    }
    notifyListeners();
  }

  /// Stops game loop.
  void stop() {
    _isRunning = false;
    _isPaused = false;
    _gameLoopTimer?.cancel();
    _gameLoopTimer = null;
    notifyListeners();
  }

  void _scheduleLoop() {
    _gameLoopTimer?.cancel();
    final intervalMs = (_speedHz > 0) ? (1000.0 / _speedHz).round() : 50;
    _gameLoopTimer = Timer.periodic(
      Duration(milliseconds: intervalMs.clamp(1, 1000)),
      (_) {
        if (_isRunning &&
            !_isPaused &&
            !(activeDialog?.isModal ?? false) &&
            activeInputPrompt == null &&
            !_isInventoryOpen &&
            _inspectingObjectNumber == null &&
            !isMenuOpen) {
          tick();
        }
      },
    );
  }

  /// Initializes game with authentic Sierra AGI opening registers, loading root LOGIC 0
  /// and running the initial bootstrap scan.
  void initializeGame({int startingRoom = 0}) {
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

    // Run initial bootstrap scan (LOGIC 0 room 0 startup which calls new.room(introRoom))
    if (interpreter.currentFrame != null) {
      try {
        interpreter.executeCycle();
      } catch (e) {
        _lastError = 'Interpreter error during game initialization: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    // Post-Scan: clear first-cycle room init flags
    memory.resetFlag(5); // init.log reset after startup scan
    memory.resetFlag(6); // restart.in.progress reset
    memory.resetFlag(12); // restore.in.progress reset

    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);

    notifyListeners();
  }

  /// Executes exactly one full 20 Hz AGI cycle.
  void tick() {
    _cycleCount++;

    // ----------------------------------------------------
    // Phase 1: Input handling
    // ----------------------------------------------------
    // Update Ego direction variable (%v6)
    memory.setVar(6, ego.direction);

    // ----------------------------------------------------
    // Phase 2: Motion & Cel Animation Physics
    // ----------------------------------------------------
    _updateMotionAndAnimation();

    // ----------------------------------------------------
    // Phase 3: LOGIC 0 Scan Cycle Execution
    // ----------------------------------------------------
    if (interpreter.rootScript != null || interpreter.currentFrame != null) {
      try {
        final status = interpreter.executeCycle();
        if (status == InterpreterStatus.yielded) {
          notifyListeners();
          return;
        }
      } catch (e) {
        _lastError = 'Interpreter error in cycle $_cycleCount: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    // Synchronize Ego motion direction from %v6 (var[EGODIR]) per Sierra MAIN.C:102
    if (_isUserControl && ego.motionType == 0) {
      ego.direction = memory.getVar(6);
      if (ego.direction != 0) {
        ego.isCycling = true;
      }
    }

    // ----------------------------------------------------
    // Post-Scan: Clock update & transient flags cleanup
    // ----------------------------------------------------
    _performPostScanCleanup();
    notifyListeners();
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
        if (_isRunning) {
          _scheduleLoop();
        }
      }
    }

    // Auto-capture room transition checkpoint on completion of new room first scan (%f5)
    if (memory.getFlag(5)) {
      _recordRoomTransitionCheckpoint();
    }

    // Reset transient per-cycle flags and parsed input tokens
    memory.resetFlag(1); // Ego completely obscured reset
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

  /// Sets Ego's motion direction (0..8) and synchronizes Variable 6.
  /// If [toggleIfSame] is true and Ego is already moving in [direction] (and [direction] != 0),
  /// Ego stops (direction 0).
  void setEgoDirection(int direction, {bool toggleIfSame = true}) {
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
    } else {
      ego.isCycling = false;
    }
    notifyListeners();
  }

  /// Active sound output mode.
  AgiSoundMode get soundMode => _soundMode;

  /// Active synthesizer DSP configuration.
  SynthesizerConfig get synthesizerConfig => _synthesizerConfig;

  /// Whether sound is actively enabled and outputting audio.
  bool get isSoundOn => _soundMode != AgiSoundMode.off && memory.getFlag(9);

  /// Sets the active sound playback mode ([AgiSoundMode]).
  void setSoundMode(AgiSoundMode mode) {
    _soundMode = mode;
    switch (mode) {
      case AgiSoundMode.off:
        memory.resetFlag(9); // %f9 = sound off
        soundPlayer?.stop();
        break;
      case AgiSoundMode.ibmPc:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 1); // %v22 = 1 voice
        _synthesizerConfig = _synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.ibmPcSingleChannel,
          enableReverb: false,
        );
        break;
      case AgiSoundMode.pcJr:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 3); // %v22 = 3 voices
        _synthesizerConfig = _synthesizerConfig.copyWith(
          mode: PcmPlaybackMode.tandy3VoiceNoise,
          enableReverb: false,
        );
        break;
      case AgiSoundMode.enhanced:
        memory.setFlag(9); // %f9 = sound on
        memory.setVar(22, 3); // %v22 = 3 voices
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

  /// Submits player text command, tokenizes against dictionary, and raises Flag 2 (`have.input`).
  void submitCommand(String input) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return;

    _lastSubmittedCommand = cleanInput;
    _parsedWordIds = tokenizeCommand(cleanInput);

    // Flag 2: have.input = 1
    memory.setFlag(2);
    // Flag 4: said.accepted = 0
    memory.resetFlag(4);

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

  /// Formats Sierra AGI message formatting placeholders (%v, %w, %s, %m, %g, %o) and escapes (\).
  String formatMessage(String text) {
    if (!text.contains('%') && !text.contains('\\')) return text;

    final sb = StringBuffer();
    int i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == '\\') {
        i++;
        if (i < text.length) {
          sb.write(text[i]);
          i++;
        }
      } else if (ch == '%' && i + 1 < text.length) {
        i++;
        final type = text[i];
        i++;
        if (type == 'v' || type == 'w' || type == 's' || type == 'm' || type == 'g' || type == 'o' || type == '0') {
          final numBuf = StringBuffer();
          while (i < text.length && text.codeUnitAt(i) >= 48 && text.codeUnitAt(i) <= 57) {
            numBuf.write(text[i]);
            i++;
          }
          final num = int.tryParse(numBuf.toString()) ?? 0;
          int? pad;
          if (type == 'v' && i < text.length && text[i] == '|') {
            i++;
            final padBuf = StringBuffer();
            while (i < text.length && text.codeUnitAt(i) >= 48 && text.codeUnitAt(i) <= 57) {
              padBuf.write(text[i]);
              i++;
            }
            pad = int.tryParse(padBuf.toString());
          }

          switch (type) {
            case 'v':
              final val = memory.getVar(num);
              var str = val.toString();
              if (pad != null && pad > str.length) {
                str = str.padLeft(pad, '0');
              }
              sb.write(str);
              break;

            case 'w':
              if (num >= 1 && num <= _inputWords.length) {
                sb.write(_inputWords[num - 1]);
              }
              break;

            case 's':
              sb.write(formatMessage(memory.getString(num)));
              break;

            case 'm':
              final msg = interpreter.currentFrame?.script.getMessage(num) ?? '';
              sb.write(formatMessage(msg));
              break;

            case 'g':
              final logic0 = resourceLoader?.loadLogic(0);
              final msg = logic0?.getMessage(num) ?? '';
              sb.write(formatMessage(msg));
              break;

            case 'o':
            case '0':
              final objIdx = memory.getVar(num);
              if (resourceLoader != null && objIdx >= 0 && objIdx < resourceLoader!.initialObjects.length) {
                sb.write(resourceLoader!.initialObjects[objIdx].name);
              }
              break;
          }
        } else {
          sb.write('%');
          sb.write(type);
        }
      } else {
        sb.write(ch);
        i++;
      }
    }
    return sb.toString();
  }

  /// Dismisses active modal dialog box and resumes gameplay.
  void dismissDialog() {
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    _dialogAutoCloseTicks = null;

    final dialog = activeDialog;
    if (dialog != null) {
      dialog.dismissCompleter?.complete();
      activeDialog = null;
      if (interpreter.hasPendingYield) {
        final status = interpreter.resume();
        if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
          _performPostScanCleanup();
        }
      }
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
  void submitInputPrompt(String value) {
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
      final status = interpreter.resumeWithInput(resultValue);
      if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
        _performPostScanCleanup();
      }
      notifyListeners();
    }
  }

  /// Cancels the current active input prompt without submitting a value and resumes interpreter.
  void cancelInputPrompt() {
    final prompt = activeInputPrompt;
    if (prompt != null) {
      if (prompt.type == AgiInputPromptType.string) {
        prompt.stringCompleter?.complete(null);
      } else {
        prompt.numCompleter?.complete(null);
      }
      activeInputPrompt = null;
      final status = interpreter.resumeWithInput(null);
      if (status == InterpreterStatus.completed && interpreter.callStack.isEmpty) {
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
          return a.effectiveSortY.compareTo(b.effectiveSortY);
        });

      for (final obj in sortedObjects) {
        if (obj.view == 0 && obj.number != 0) continue;
        try {
          final viewRes = loader.loadView(obj.view);
          final cel = viewRes.getCel(obj.loop, obj.cel);
          if (cel == null) continue;

          final celPixels = cel.getPixels(parentView: viewRes, celIndex: obj.cel);
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
      if (!obj.isAnimated || !obj.isDrawn || !obj.isUpdating) {
        continue;
      }

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
    if (egoObj.priority == 15) {
      memory.resetFlag(0);
      memory.resetFlag(3);
      return;
    }
    int objWidth = 4;
    if (resourceLoader != null) {
      try {
        final v = resourceLoader!.loadView(egoObj.view);
        final cel = v.getCel(egoObj.loop, egoObj.cel);
        if (cel != null) {
          objWidth = cel.width;
        }
      } catch (_) {}
    }

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

    // Flag 1: EGO completely obscured
    var allObscured = true;
    for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
      if (bx >= 0 && bx < 160 && egoObj.y >= 0 && egoObj.y < 168) {
        final effPri = priBuf.effectivePriorityAt(bx, egoObj.y);
        if (effPri >= egoObj.effectivePriority) {
          allObscured = false;
          break;
        }
      } else {
        allObscured = false;
        break;
      }
    }
    if (allObscured) {
      memory.setFlag(1);
    } else {
      memory.resetFlag(1);
    }
  }

  void _updateLoopForDirection(AnimatedObject obj) {
    if (obj.direction == 0) return;

    final viewRes = (resourceLoader != null) ? resourceLoader!.loadView(obj.view) : null;
    final loopCount = viewRes?.loopCount ?? 4;
    final oldLoop = obj.loop;

    switch (obj.direction) {
      case 1: // North
        if (loopCount >= 4) obj.loop = 3;
        break;
      case 2: // North-East
      case 3: // East
      case 4: // South-East
        if (loopCount >= 1) obj.loop = 0;
        break;
      case 5: // South
        if (loopCount >= 3) obj.loop = 2;
        break;
      case 6: // South-West
      case 7: // West
      case 8: // North-West
        if (loopCount >= 2) obj.loop = 1;
        break;
    }

    if (obj.loop != oldLoop && viewRes != null) {
      final loopRes = viewRes.getLoop(obj.loop);
      if (loopRes != null && loopRes.celCount > 0 && obj.cel >= loopRes.celCount) {
        obj.cel = 0;
      }
    }
  }

  void _updateObjectPosition(AnimatedObject obj, PriorityBuffer? priBuf) {
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
        final diffX = egoObj.x - obj.x;
        final diffY = egoObj.y - obj.y;
        final step = obj.stepDistance > 0 ? obj.stepDistance : obj.stepSize;
        if (diffX.abs() <= step && diffY.abs() <= step) {
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
          final dirX = diffX > 0 ? 1 : (diffX < 0 ? -1 : 0);
          final dirY = diffY > 0 ? 1 : (diffY < 0 ? -1 : 0);
          obj.direction = _vectorToDirection(dirX, dirY);
        }
        break;

      case 3: // move_to
        final diffX = obj.targetX - obj.x;
        final diffY = obj.targetY - obj.y;
        if (diffX == 0 && diffY == 0) {
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
          final dirX = diffX > 0 ? 1 : (diffX < 0 ? -1 : 0);
          final dirY = diffY > 0 ? 1 : (diffY < 0 ? -1 : 0);
          obj.direction = _vectorToDirection(dirX, dirY);
        }
        break;

      default: // normal
        break;
    }

    final delta = _directionToVector(obj.direction);
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
    int objWidth = 4;
    if (resourceLoader != null) {
      try {
        final v = resourceLoader!.loadView(obj.view);
        final cel = v.getCel(obj.loop, obj.cel);
        if (cel != null) {
          objWidth = cel.width;
        }
      } catch (_) {}
    }

    // Screen boundary clamping
    const minX = 0;
    final maxX = (160 - objWidth).clamp(0, 159);
    final minY = obj.ignoreHorizon ? 0 : horizon;
    const maxY = 167;

    var clampedX = targetX.clamp(minX, maxX);
    var clampedY = targetY.clamp(minY, maxY);

    // Border collision triggers for variables %v2 (Ego) and %v4/%v5 (other objects)
    int border = 0;
    if (targetY <= minY) {
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
      // In Sierra AGI (MOVEOBJS.C line 122):
      // If the object was on a 'moveobj', set the move as finished (EndMoveObj)
      if (obj.motionType == 3 || obj.motionType == 2) {
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
      }
    }

    // Script block area check
    if (!obj.ignoreBlocks && activeBlock != null && activeBlock!.overlapsBaseline(clampedX, clampedY, objWidth)) {
      if (obj.motionType == 1) {
        obj.direction = _rng.nextInt(9);
      } else if (obj.number == 0 && obj.motionType == 0) {
        obj.direction = 0;
        memory.setVar(6, 0);
        obj.isCycling = false;
      }
      return;
    }

    // Priority buffer collision check (priority 15 represents sky/background and bypasses ground barriers)
    if (priBuf != null && obj.priority != 15) {
      var isBlocked = false;
      for (int bx = clampedX; bx < clampedX + objWidth; bx++) {
        if (!priBuf.isWalkable(bx, clampedY, allowConditional: obj.ignoreBlocks)) {
          isBlocked = true;
          break;
        }
      }

      if (isBlocked) {
        if (obj.motionType == 1) {
          obj.direction = _rng.nextInt(9);
        } else if (obj.number == 0 && obj.motionType == 0) {
          obj.direction = 0;
          memory.setVar(6, 0);
          obj.isCycling = false;
        }
        return;
      }
    }

    // Object-to-object collision check (baseline intersection & crossing per Sierra COLLIDE.C)
    if (!obj.ignoreObjects) {
      for (final other in animatedObjects) {
        if (other.number == obj.number) continue;
        if (!other.isDrawn || !other.isAnimated || other.ignoreObjects) continue;
        if (obj.motionType == 2 && other.number == 0) continue;

        int otherWidth = 4;
        if (resourceLoader != null) {
          try {
            final v = resourceLoader!.loadView(other.view);
            final cel = v.getCel(other.loop, other.cel);
            if (cel != null) {
              otherWidth = cel.width;
            }
          } catch (_) {}
        }

        final aLeft = clampedX;
        final aRight = clampedX + objWidth - 1;
        final bLeft = other.x;
        final bRight = other.x + otherWidth - 1;

        if (aRight >= bLeft && aLeft <= bRight) {
          if (clampedY == other.y ||
              (clampedY > other.y && obj.prevY < other.prevY) ||
              (clampedY < other.y && obj.prevY > other.prevY)) {
            if (obj.motionType == 1) {
              obj.direction = _rng.nextInt(9);
            } else if (obj.number == 0 && obj.motionType == 0) {
              obj.direction = 0;
              memory.setVar(6, 0);
              obj.isCycling = false;
            }
            return;
          }
        }
      }
    }

    obj.prevX = obj.x;
    obj.prevY = obj.y;
    obj.x = clampedX;
    obj.y = clampedY;

    if (obj.motionType == 3) {
      if (obj.x == obj.targetX && obj.y == obj.targetY) {
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
      }
    }
  }

  void _advanceObjectCel(AnimatedObject obj) {
    int celCount = 4;
    if (resourceLoader != null) {
      try {
        final v = resourceLoader!.loadView(obj.view);
        final loop = v.getLoop(obj.loop);
        if (loop != null && loop.celCount > 0) {
          celCount = loop.celCount;
        }
      } catch (_) {}
    }

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
  }

  static (int, int) _directionToVector(int dir) {
    switch (dir) {
      case 1:
        return (0, -1);
      case 2:
        return (1, -1);
      case 3:
        return (1, 0);
      case 4:
        return (1, 1);
      case 5:
        return (0, 1);
      case 6:
        return (-1, 1);
      case 7:
        return (-1, 0);
      case 8:
        return (-1, -1);
      default:
        return (0, 0);
    }
  }

  static int _vectorToDirection(int dx, int dy) {
    if (dx == 0 && dy < 0) return 1;
    if (dx > 0 && dy < 0) return 2;
    if (dx > 0 && dy == 0) return 3;
    if (dx > 0 && dy > 0) return 4;
    if (dx == 0 && dy > 0) return 5;
    if (dx < 0 && dy > 0) return 6;
    if (dx < 0 && dy == 0) return 7;
    if (dx < 0 && dy < 0) return 8;
    return 0;
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
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
    _isTextScreen = false;
    _isUserControl = true;
    // Update variable 16 with current Ego view (matching Sierra NEWROOM.C var[CURRENT_EGO] = ego->view)
    memory.setVar(16, ego.view);

    // Unload non-Ego animated objects and reset Ego per-room state
    ego.resetForNewRoom();
    for (int i = 1; i < animatedObjects.length; i++) {
      animatedObjects[i].reset();
    }

    // Load new room picture if available
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(roomNumber)) {
      currentPic = resourceLoader!.loadPic(roomNumber);
      currentPic?.preloadGpuTextures();
    }

    // Load root room logic (LOGIC 0) for rescan
    _loadedLogicNumbers.clear();
    _loadedLogicNumbers.add(0);
    _loadedLogicNumbers.add(roomNumber);
    if (resourceLoader != null && resourceLoader!.presentLogicNumbers.contains(0)) {
      final logic0 = resourceLoader!.loadLogic(0);
      interpreter.loadRootScript(logic0, scriptNumber: 0);
    }

    notifyListeners();
  }

  /// Reloads room picture and root logic (LOGIC 0) after state restoration
  /// without resetting or wiping restored animated objects.
  void reloadRoomForRestore(int roomNumber) {
    onStopSound();
    horizon = CollisionDetector.defaultHorizon;
    activeBlock = null;
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    _isTextScreen = false;

    // Load room picture if available
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(roomNumber)) {
      currentPic = resourceLoader!.loadPic(roomNumber);
      currentPic?.preloadGpuTextures();
    }

    // Load root room logic (LOGIC 0) for execution scan
    _loadedLogicNumbers.clear();
    _loadedLogicNumbers.add(0);
    _loadedLogicNumbers.add(roomNumber);
    if (resourceLoader != null && resourceLoader!.presentLogicNumbers.contains(0)) {
      final logic0 = resourceLoader!.loadLogic(0);
      interpreter.loadRootScript(logic0, scriptNumber: 0);
    }

    notifyListeners();
  }

  void _repositionEgoForBorder(int border) {
    int egoWidth = 4;
    if (resourceLoader != null) {
      try {
        final v = resourceLoader!.loadView(ego.view);
        final cel = v.getCel(ego.loop, ego.cel);
        if (cel != null) {
          egoWidth = cel.width;
        }
      } catch (_) {}
    }

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
    if (resourceLoader != null && resourceLoader!.presentViewNumbers.contains(viewNumber)) {
      try {
        return resourceLoader!.loadView(viewNumber);
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
    submitCommand(input);
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
  void onPrint(String message, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    _showDialog(
      message: message,
      isModal: isModal,
      timeoutHalfSeconds: timeoutHalfSeconds,
    );
  }

  @override
  void onPrintAt(String message, int row, int col, int width, {bool isModal = true, int timeoutHalfSeconds = 0}) {
    _showDialog(
      message: message,
      row: row,
      col: col,
      width: width,
      isModal: isModal,
      timeoutHalfSeconds: timeoutHalfSeconds,
    );
  }

  void _showDialog({
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
    activeDialog = AgiDialogState(
      message: formatMessage(message),
      row: row,
      col: col,
      width: width,
      isModal: isModal,
      dismissCompleter: completer,
      autoCloseHalfSeconds: timeoutHalfSeconds > 0 ? timeoutHalfSeconds : null,
      autoCloseTicks: timeoutHalfSeconds > 0 ? timeoutHalfSeconds * 10 : null,
    );

    if (timeoutHalfSeconds > 0) {
      _dialogAutoCloseTicks = timeoutHalfSeconds * 10;
      final ms = timeoutHalfSeconds * 500;
      _dialogAutoCloseTimer = Timer(Duration(milliseconds: ms), () {
        dismissDialog();
      });
    } else {
      _dialogAutoCloseTicks = null;
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

  @override
  void onDraw(AnimatedObject obj) {
    if (!obj.ignoreHorizon && obj.y <= horizon) {
      obj.y = horizon + 1;
      obj.prevY = obj.y;
    }
  }

  @override
  void onSetHorizon(int horizon) {
    this.horizon = horizon;
    for (final obj in animatedObjects) {
      if (!obj.ignoreHorizon && obj.y <= horizon) {
        obj.y = horizon + 1;
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
  void onShakeScreen(int count) {
    _shakeCount = count;
    _shakeTicksRemaining = (count * 8).clamp(8, 40);
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

    // If sound is disabled or muted, complete flag immediately without playing
    if (!memory.getFlag(9) || _soundMode == AgiSoundMode.off) {
      memory.setFlag(completionFlag);
      return;
    }

    if (soundPlayer != null && resourceLoader != null) {
      if (resourceLoader!.presentSoundNumbers.contains(soundNumber)) {
        final snd = resourceLoader!.loadSound(soundNumber);
        if (!snd.isEmpty && snd.length > 0) {
          _activeSoundEndFlag = completionFlag;
          soundPlayer!.play(snd, config: _synthesizerConfig).catchError((_) {
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
    soundPlayer?.stop();
  }

  @override
  void onLoadPic(int picNumber) {
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(picNumber)) {
      resourceLoader!.loadRawPic(picNumber);
    }
  }

  @override
  void onDrawPic(int picNumber) {
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(picNumber)) {
      currentPic = resourceLoader!.loadPic(picNumber);
      currentPic?.preloadGpuTextures();
      _displayedTexts.clear();
      textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
      _statusLineNeedsRedraw = true;
      updateStatusLine(force: true);
      notifyListeners();
    }
  }

  @override
  void onShowPic() {
    currentPic?.preloadGpuTextures();
    _displayedTexts.clear();
    textScreenBuffer.clear(fg: _textFgColor, bg: _textBgColor);
    _statusLineNeedsRedraw = true;
    updateStatusLine(force: true);
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
      resourceLoader!.loadView(viewNumber);
    }
  }

  @override
  void onDiscardView(int viewNumber) {
    // View caches can be purged if needed
  }

  @override
  void onAddToPic(int view, int loop, int cel, int x, int y, int pri, int boxPri) {
    if (resourceLoader == null || currentPic == null) return;

    try {
      final viewRes = resourceLoader!.loadView(view);
      final celRes = viewRes.getCel(loop, cel);
      if (celRes == null) return;

      final pixels = celRes.getPixels(parentView: viewRes, celIndex: cel);
      final cw = celRes.width;
      final ch = celRes.height;
      final startY = y - ch + 1;

      final effectivePri = pri > 0 ? pri : 4;

      // Burn pixels into visual buffer and priority buffer respecting background priority
      for (int cy = 0; cy < ch; cy++) {
        final py = startY + cy;
        if (py < 0 || py >= AgiPic.nativeHeight) continue;

        for (int cx = 0; cx < cw; cx++) {
          final px = x + cx;
          if (px < 0 || px >= AgiPic.nativeWidth) continue;

          final colorIndex = pixels[cy * cw + cx] & 0x0F;
          if (colorIndex != celRes.transparentColor) {
            final bgPri = currentPic!.priorityBuffer.priorityAt(px, py);
            // In Sierra AGI: sprite pixels are only drawn if sprite priority >= background priority.
            // If background priority > sprite priority, the background is in front of the sprite!
            if (effectivePri >= bgPri) {
              currentPic!.visualPixels[py * AgiPic.nativeWidth + px] = colorIndex;
              if (pri > 0) {
                currentPic!.priorityBuffer.setPriorityAt(px, py, pri);
              }
            }
          }
        }
      }

      // If boxPri > 0, burn solid priority bar at base
      if (boxPri > 0 && y >= 0 && y < AgiPic.nativeHeight) {
        for (int bx = x; bx < x + cw; bx++) {
          if (bx >= 0 && bx < AgiPic.nativeWidth) {
            currentPic!.priorityBuffer.setPriorityAt(bx, y, boxPri);
          }
        }
      }

      // Re-slice picture with updated buffers
      final newSlices = PictureSlicer.slice(
        visualPixels: currentPic!.visualPixels,
        priorityBuffer: currentPic!.priorityBuffer,
      );
      currentPic!.slices.clear();
      currentPic!.slices.addAll(newSlices);
      currentPic!.preloadGpuTextures();
    } catch (e) {
      if (kDebugMode) {
        print('Error executing add.to.pic: $e');
      }
    }
  }

  @override
  void onStatus() {
    _isInventoryOpen = true;
    notifyListeners();
  }

  @override
  void onShowObj(int objNumber) {
    _inspectingObjectNumber = objNumber;
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
    controllerManager.triggerController(controllerCode, memory);
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

  @override
  void dispose() {
    _dialogAutoCloseTimer?.cancel();
    _dialogAutoCloseTimer = null;
    onStopSound();
    stop();
    super.dispose();
  }
}
