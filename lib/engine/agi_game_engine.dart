import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter.dart';
import 'package:flutter_agigame/logic/interpreter/agi_interpreter_delegate.dart';
import 'package:flutter_agigame/engine/parser/agi_text_parser.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// Represents active modal or positional dialog box state.
class AgiDialogState {
  final String message;
  final int? row;
  final int? col;
  final int? x;
  final int? y;
  final int? width;
  final bool isModal;
  final Completer<void>? dismissCompleter;

  const AgiDialogState({
    required this.message,
    this.row,
    this.col,
    this.x,
    this.y,
    this.width,
    this.isModal = true,
    this.dismissCompleter,
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
  late final AgiLogicInterpreter interpreter;

  AgiPic? currentPic;
  AgiDialogState? activeDialog;

  bool _isRunning = false;
  bool _isPaused = false;
  double _speedHz;
  Timer? _gameLoopTimer;

  int _cycleCount = 0;
  int _clockTicks = 0;
  List<int> _parsedWordIds = [];
  List<String> _inputWords = [];
  String? _lastSubmittedCommand;
  String? _lastError;
  bool _keyPressedThisCycle = false;
  bool _isStatusLineEnabled = true;
  bool _isInputEnabled = true;
  bool _isUserControl = true;
  final List<AgiDisplayText> _displayedTexts = [];
  final math.Random _rng;
  int? _activeSoundEndFlag;
  int horizon = CollisionDetector.defaultHorizon;
  AgiBlockArea? activeBlock;

  AgiGameEngine({
    this.resourceLoader,
    this.soundPlayer,
    AgiMemory? memory,
    List<AnimatedObject>? animatedObjects,
    this._speedHz = 20.0,
    int? randomSeed,
    int maxAnimatedObjects = 64,
  })  : memory = memory ?? AgiMemory(),
        animatedObjects = animatedObjects ??
            List.generate(maxAnimatedObjects, (i) => AnimatedObject(number: i)),
        _rng = randomSeed != null ? math.Random(randomSeed) : math.Random() {
    if (this.soundPlayer != null) {
      this.soundPlayer!.onFinished = _onSoundFinished;
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
  int get currentRoom => memory.getVar(0);
  AnimatedObject get ego => animatedObjects[0];

  /// Starts the game loop timer.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _isPaused = false;
    _scheduleLoop();
    notifyListeners();
  }

  /// Pauses the game loop.
  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  /// Resumes a paused game loop.
  void resume() {
    _isPaused = false;
    notifyListeners();
  }

  /// Updates execution loop frequency in Hertz (default 20 Hz = 50ms per tick).
  void setSpeedHz(double hz) {
    if (hz <= 0) return;
    _speedHz = hz;
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
        if (_isRunning && !_isPaused && !(activeDialog?.isModal ?? false)) {
          tick();
        }
      },
    );
  }

  /// Initializes game with authentic Sierra AGI opening registers, loading root LOGIC 0
  /// and running the initial bootstrap scan.
  void initializeGame({int startingRoom = 0}) {
    memory.reset();

    // Authentic Sierra AGI system variable defaults
    memory.setVar(0, 0); // %v0 = current.room (0 on boot)
    memory.setVar(1, 0); // %v1 = previous.room (0 on boot)
    memory.setVar(8, 10); // %v8 = free heap space in 4KB pages
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

    if (resourceLoader != null) {
      // Load initial inventory item locations
      for (int i = 0; i < resourceLoader!.initialObjects.length; i++) {
        final item = resourceLoader!.initialObjects[i];
        memory.itemRooms[i] = item.startingRoom;
      }

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
        interpreter.executeCycle();
      } catch (e) {
        _lastError = 'Interpreter error in cycle $_cycleCount: $e';
        if (kDebugMode) {
          print(_lastError);
        }
      }
    }

    // ----------------------------------------------------
    // Post-Scan: Clock update & transient flags cleanup
    // ----------------------------------------------------
    _updateClock();

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

    notifyListeners();
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

  /// Toggles game audio sound on/off (%f9) and notifies UI listeners.
  void toggleSound() {
    memory.toggleFlag(9);
    notifyListeners();
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
    final dict = resourceLoader?.dictionary ?? AgiDictionary();
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

  /// Formats Sierra AGI message formatting placeholders (%v, %w, %s, %m, %g, %o).
  String formatMessage(String text) {
    if (!text.contains('%')) return text;

    return text.replaceAllMapped(
      RegExp(r'%([vwsmgo])(\d+)(?:\|(\d+))?'),
      (match) {
        final code = match.group(1)!;
        final num = int.tryParse(match.group(2)!) ?? 0;
        final pad = match.group(3) != null ? (int.tryParse(match.group(3)!) ?? 0) : null;

        switch (code) {
          case 'v':
            final val = memory.getVar(num);
            var str = val.toString();
            if (pad != null && pad > str.length) {
              str = str.padLeft(pad, '0');
            }
            return str;

          case 'w':
            if (num >= 1 && num <= _inputWords.length) {
              return _inputWords[num - 1];
            }
            return '';

          case 's':
            return memory.getString(num);

          case 'm':
            final msg = interpreter.currentFrame?.script.getMessage(num) ?? '';
            return formatMessage(msg);

          case 'g':
            final logic0 = resourceLoader?.loadLogic(0);
            final msg = logic0?.getMessage(num) ?? '';
            return formatMessage(msg);

          case 'o':
            final objIdx = memory.getVar(num);
            if (resourceLoader != null && objIdx >= 0 && objIdx < resourceLoader!.initialObjects.length) {
              return resourceLoader!.initialObjects[objIdx].name;
            }
            return '';

          default:
            return match.group(0)!;
        }
      },
    );
  }

  /// Dismisses active modal dialog box and resumes gameplay.
  void dismissDialog() {
    final dialog = activeDialog;
    if (dialog != null) {
      dialog.dismissCompleter?.complete();
      activeDialog = null;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // State Checkpoints & Snapshots (Debugging & Save-States)
  // ---------------------------------------------------------------------------

  final List<AgiGameStateSnapshot> _checkpointHistory = [];

  /// Rolling history of in-memory checkpoints taken during gameplay.
  List<AgiGameStateSnapshot> get checkpointHistory =>
      List.unmodifiable(_checkpointHistory);

  /// Captures a complete serializable snapshot of the current game engine state.
  AgiGameStateSnapshot createSnapshot({String label = ''}) {
    return AgiGameStateSnapshot.capture(this, label: label);
  }

  /// Restores the game engine to an exact [snapshot] state.
  void restoreSnapshot(AgiGameStateSnapshot snapshot) {
    snapshot.restore(this);
    notifyListeners();
  }

  /// Records a new snapshot into [_checkpointHistory] and returns it.
  AgiGameStateSnapshot recordCheckpoint({String label = ''}) {
    final snap = createSnapshot(label: label);
    _checkpointHistory.insert(0, snap);
    if (_checkpointHistory.length > 20) {
      _checkpointHistory.removeLast();
    }
    notifyListeners();
    return snap;
  }

  /// Removes a checkpoint from history.
  void removeCheckpoint(int index) {
    if (index >= 0 && index < _checkpointHistory.length) {
      _checkpointHistory.removeAt(index);
      notifyListeners();
    }
  }

  /// Clears all stored checkpoint snapshots.
  void clearCheckpoints() {
    _checkpointHistory.clear();
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

    // Flag 0: EGO entirely on water (pri 3)
    var onWater = true;
    for (int bx = egoObj.x; bx < egoObj.x + objWidth; bx++) {
      if (bx < 0 || bx >= 160 || egoObj.y < 0 || egoObj.y >= 168 || priBuf.priorityAt(bx, egoObj.y) != 3) {
        onWater = false;
        break;
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
        if (diffX.abs() > obj.stepSize || diffY.abs() > obj.stepSize) {
          final dirX = diffX > 0 ? 1 : (diffX < 0 ? -1 : 0);
          final dirY = diffY > 0 ? 1 : (diffY < 0 ? -1 : 0);
          obj.direction = _vectorToDirection(dirX, dirY);
        } else {
          obj.direction = 0;
        }
        break;

      case 3: // move_to
        final diffX = obj.targetX - obj.x;
        final diffY = obj.targetY - obj.y;
        final dist = math.sqrt(diffX * diffX + diffY * diffY);
        if (dist <= obj.stepSize) {
          obj.x = obj.targetX;
          obj.y = obj.targetY;
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
    dx = delta.$1 * obj.stepSize;
    dy = delta.$2 * obj.stepSize;

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

    // Priority buffer collision check
    if (priBuf != null) {
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

    obj.prevX = obj.x;
    obj.prevY = obj.y;
    obj.x = clampedX;
    obj.y = clampedY;
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
        } else {
          obj.isCycling = false;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
          }
        }
        break;
      case 3: // reverse_loop
        if (obj.cel > 0) {
          obj.cel--;
        } else {
          obj.isCycling = false;
          if (obj.endOfLoopFlag != null) {
            memory.setFlag(obj.endOfLoopFlag!);
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

    // Reposition Ego based on border crossed (%v2)
    final borderHit = memory.getVar(2);
    _repositionEgoForBorder(borderHit);

    // Reset transient edge hit variables, displayed text, and user control
    memory.setVar(2, 0);
    memory.setVar(4, 0);
    memory.setVar(5, 0);
    _displayedTexts.clear();
    _isUserControl = true;
    _isInputEnabled = true;

    // Unload non-Ego animated objects
    for (int i = 1; i < animatedObjects.length; i++) {
      animatedObjects[i].reset();
    }

    // Load new room picture if available
    if (resourceLoader != null && resourceLoader!.presentPicNumbers.contains(roomNumber)) {
      currentPic = resourceLoader!.loadPic(roomNumber);
      currentPic?.preloadGpuTextures();
    }

    // Load root room logic (LOGIC 0) for rescan
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
    if (resourceLoader != null && resourceLoader!.presentLogicNumbers.contains(logicNumber)) {
      return resourceLoader!.loadLogic(logicNumber);
    }
    return null;
  }

  @override
  void onPrint(String message) {
    activeDialog = AgiDialogState(
      message: formatMessage(message),
      isModal: true,
      dismissCompleter: Completer<void>(),
    );
    notifyListeners();
  }

  @override
  void onPrintAt(String message, int x, int y, int width) {
    activeDialog = AgiDialogState(
      message: formatMessage(message),
      x: x,
      y: y,
      width: width,
      isModal: true,
      dismissCompleter: Completer<void>(),
    );
    notifyListeners();
  }

  @override
  void onDisplay(int row, int col, String message) {
    final formatted = formatMessage(message);
    _displayedTexts.removeWhere((t) => t.row == row && t.col == col);
    _displayedTexts.add(AgiDisplayText(row: row, col: col, message: formatted));
    notifyListeners();
  }

  @override
  void onClearLines(int top, int bottom, int color) {
    _displayedTexts.removeWhere((t) => t.row >= top && t.row <= bottom);
    notifyListeners();
  }

  @override
  void onClearTextRect(int top, int left, int bottom, int right, int color) {
    _displayedTexts.removeWhere(
      (t) => t.row >= top && t.row <= bottom && t.col >= left && t.col <= right,
    );
    notifyListeners();
  }

  @override
  void onStatusLine(bool enabled) {
    _isStatusLineEnabled = enabled;
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
  void onTextScreen() {}

  @override
  void onGraphics() {}

  @override
  void onShakeScreen(int count) {}

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

    if (soundPlayer != null && resourceLoader != null) {
      if (resourceLoader!.presentSoundNumbers.contains(soundNumber)) {
        final snd = resourceLoader!.loadSound(soundNumber);
        if (!snd.isEmpty && snd.length > 0) {
          _activeSoundEndFlag = completionFlag;
          soundPlayer!.play(snd).catchError((_) {
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
    soundPlayer?.stop();
    if (_activeSoundEndFlag != null) {
      memory.setFlag(_activeSoundEndFlag!);
      _activeSoundEndFlag = null;
    }
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
      notifyListeners();
    }
  }

  @override
  void onShowPic() {
    currentPic?.preloadGpuTextures();
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
  void onShowObj(int objNumber) {}

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
  bool checkSaid(List<int> wordGroupIds) {
    // In Sierra AGI, said() only matches if user input was entered this cycle (Flag 2)
    // and no previous said() check has claimed/accepted the input (Flag 4).
    if (!memory.getFlag(2) || memory.getFlag(4)) {
      return false;
    }

    if (_parsedWordIds.isEmpty && wordGroupIds.isNotEmpty) {
      return false;
    }

    int inputIdx = 0;
    int expectedIdx = 0;

    while (expectedIdx < wordGroupIds.length) {
      final expected = wordGroupIds[expectedIdx];

      // 9998 = Rest of Line (_ROL) wildcard: matches all remaining tokens
      if (expected == 9998) {
        memory.setFlag(4); // said.accepted = 1
        return true;
      }

      if (inputIdx >= _parsedWordIds.length) {
        return false;
      }

      final actual = _parsedWordIds[inputIdx];

      // 9999 = Any Word (_ANY) wildcard: matches any single token
      if (expected == 9999 || expected == actual) {
        inputIdx++;
        expectedIdx++;
      } else {
        return false;
      }
    }

    // Must match all tokens exactly unless ROL was specified
    if (inputIdx == _parsedWordIds.length) {
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
    onStopSound();
    stop();
    super.dispose();
  }
}
