import 'dart:convert';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

/// Standard Sierra AGI Variable Names (Variables 0 to 26).
const Map<int, String> agiVariableNames = {
  0: 'current_room',
  1: 'previous_room',
  2: 'edge_ego_hit',
  3: 'current_score',
  4: 'edge_obj_hit',
  5: 'edge_code',
  6: 'ego_direction',
  7: 'max_score',
  8: 'free_memory_pages',
  9: 'unknown_word_number',
  10: 'cycle_delay',
  11: 'clock_seconds',
  12: 'clock_minutes',
  13: 'clock_hours',
  14: 'clock_days',
  15: 'joystick_sensitivity',
  16: 'ego_view_resource',
  17: 'interpreter_error_code',
  18: 'interpreter_error_param',
  19: 'key_pressed',
  20: 'computer_type',
  21: 'window_timer',
  22: 'sound_type',
  23: 'sound_volume',
  24: 'max_input_length',
  25: 'selected_item_num',
  26: 'monitor_type',
};

/// Standard Sierra AGI Flag Names (Flags 0 to 16).
const Map<int, String> agiFlagNames = {
  0: 'ego_on_water',
  1: 'ego_completely_obscured',
  2: 'have_input',
  3: 'ego_signal / hit_special_2',
  4: 'said_accepted',
  5: 'new_room_init',
  6: 'restart_in_progress',
  7: 'script_blocked',
  8: 'fast_forward_mode',
  9: 'sound_enabled',
  10: 'debug_mode',
  11: 'has_noise_channel',
  12: 'restore_in_progress',
  13: 'status_select',
  14: 'menu_enabled',
  15: 'print_mode',
  16: 'restart_mode',
};

/// Serialized state of a single animated object slot.
class AgiObjectSnapshot {
  final int number;
  final int x;
  final int y;
  final int prevX;
  final int prevY;
  final int view;
  final int loop;
  final int cel;
  final int priority;
  final bool fixedPriority;
  final bool fixedLoop;
  final int direction;
  final int stepSize;
  final int stepTime;
  final int stepTimer;
  final int cycleTime;
  final int cycleTimer;
  final bool isAnimated;
  final bool isDrawn;
  final bool isUpdating;
  final bool isCycling;
  final int cycleMode;
  final int? endOfLoopFlag;
  final int motionType;
  final int targetX;
  final int targetY;
  final int stepDistance;
  final int? targetFlag;
  final bool ignoreHorizon;
  final bool ignoreBlocks;
  final bool ignoreObjects;
  final bool onWater;
  final bool onLand;

  const AgiObjectSnapshot({
    required this.number,
    required this.x,
    required this.y,
    required this.prevX,
    required this.prevY,
    required this.view,
    required this.loop,
    required this.cel,
    required this.priority,
    required this.fixedPriority,
    required this.fixedLoop,
    required this.direction,
    required this.stepSize,
    required this.stepTime,
    required this.stepTimer,
    required this.cycleTime,
    required this.cycleTimer,
    required this.isAnimated,
    required this.isDrawn,
    required this.isUpdating,
    required this.isCycling,
    required this.cycleMode,
    this.endOfLoopFlag,
    required this.motionType,
    required this.targetX,
    required this.targetY,
    required this.stepDistance,
    this.targetFlag,
    required this.ignoreHorizon,
    required this.ignoreBlocks,
    required this.ignoreObjects,
    this.onWater = false,
    this.onLand = false,
  });

  factory AgiObjectSnapshot.fromObject(AnimatedObject obj) {
    return AgiObjectSnapshot(
      number: obj.number,
      x: obj.x,
      y: obj.y,
      prevX: obj.prevX,
      prevY: obj.prevY,
      view: obj.view,
      loop: obj.loop,
      cel: obj.cel,
      priority: obj.priority,
      fixedPriority: obj.fixedPriority,
      fixedLoop: obj.fixedLoop,
      direction: obj.direction,
      stepSize: obj.stepSize,
      stepTime: obj.stepTime,
      stepTimer: obj.stepTimer,
      cycleTime: obj.cycleTime,
      cycleTimer: obj.cycleTimer,
      isAnimated: obj.isAnimated,
      isDrawn: obj.isDrawn,
      isUpdating: obj.isUpdating,
      isCycling: obj.isCycling,
      cycleMode: obj.cycleMode,
      endOfLoopFlag: obj.endOfLoopFlag,
      motionType: obj.motionType,
      targetX: obj.targetX,
      targetY: obj.targetY,
      stepDistance: obj.stepDistance,
      targetFlag: obj.targetFlag,
      ignoreHorizon: obj.ignoreHorizon,
      ignoreBlocks: obj.ignoreBlocks,
      ignoreObjects: obj.ignoreObjects,
      onWater: obj.onWater,
      onLand: obj.onLand,
    );
  }

  void restoreToObject(AnimatedObject obj) {
    obj.x = x;
    obj.y = y;
    obj.prevX = prevX;
    obj.prevY = prevY;
    obj.view = view;
    obj.loop = loop;
    obj.cel = cel;
    obj.priority = priority;
    obj.fixedPriority = fixedPriority;
    obj.fixedLoop = fixedLoop;
    obj.direction = direction;
    obj.stepSize = stepSize;
    obj.stepTime = stepTime;
    obj.stepTimer = stepTimer;
    obj.cycleTime = cycleTime;
    obj.cycleTimer = cycleTimer;
    obj.isAnimated = isAnimated;
    obj.isDrawn = isDrawn;
    obj.isUpdating = isUpdating;
    obj.isCycling = isCycling;
    obj.cycleMode = cycleMode;
    obj.endOfLoopFlag = endOfLoopFlag;
    obj.motionType = motionType;
    obj.targetX = targetX;
    obj.targetY = targetY;
    obj.stepDistance = stepDistance;
    obj.targetFlag = targetFlag;
    obj.ignoreHorizon = ignoreHorizon;
    obj.ignoreBlocks = ignoreBlocks;
    obj.ignoreObjects = ignoreObjects;
    obj.onWater = onWater;
    obj.onLand = onLand;
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'x': x,
        'y': y,
        'prevX': prevX,
        'prevY': prevY,
        'view': view,
        'loop': loop,
        'cel': cel,
        'priority': priority,
        'fixedPriority': fixedPriority,
        'fixedLoop': fixedLoop,
        'direction': direction,
        'stepSize': stepSize,
        'stepTime': stepTime,
        'stepTimer': stepTimer,
        'cycleTime': cycleTime,
        'cycleTimer': cycleTimer,
        'isAnimated': isAnimated,
        'isDrawn': isDrawn,
        'isUpdating': isUpdating,
        'isCycling': isCycling,
        'cycleMode': cycleMode,
        if (endOfLoopFlag != null) 'endOfLoopFlag': endOfLoopFlag,
        'motionType': motionType,
        'targetX': targetX,
        'targetY': targetY,
        'stepDistance': stepDistance,
        if (targetFlag != null) 'targetFlag': targetFlag,
        'ignoreHorizon': ignoreHorizon,
        'ignoreBlocks': ignoreBlocks,
        'ignoreObjects': ignoreObjects,
        'onWater': onWater,
        'onLand': onLand,
      };

  factory AgiObjectSnapshot.fromJson(Map<String, dynamic> json) {
    return AgiObjectSnapshot(
      number: json['number'] as int,
      x: json['x'] as int,
      y: json['y'] as int,
      prevX: json['prevX'] as int? ?? json['x'] as int,
      prevY: json['prevY'] as int? ?? json['y'] as int,
      view: json['view'] as int,
      loop: json['loop'] as int,
      cel: json['cel'] as int,
      priority: json['priority'] as int,
      fixedPriority: json['fixedPriority'] as bool? ?? false,
      fixedLoop: json['fixedLoop'] as bool? ?? false,
      direction: json['direction'] as int? ?? 0,
      stepSize: json['stepSize'] as int? ?? 1,
      stepTime: json['stepTime'] as int? ?? 1,
      stepTimer: json['stepTimer'] as int? ?? 1,
      cycleTime: json['cycleTime'] as int? ?? 1,
      cycleTimer: json['cycleTimer'] as int? ?? 1,
      isAnimated: json['isAnimated'] as bool? ?? false,
      isDrawn: json['isDrawn'] as bool? ?? false,
      isUpdating: json['isUpdating'] as bool? ?? true,
      isCycling: json['isCycling'] as bool? ?? true,
      cycleMode: json['cycleMode'] as int? ?? 0,
      endOfLoopFlag: json['endOfLoopFlag'] as int?,
      motionType: json['motionType'] as int? ?? 0,
      targetX: json['targetX'] as int? ?? 0,
      targetY: json['targetY'] as int? ?? 0,
      stepDistance: json['stepDistance'] as int? ?? 1,
      targetFlag: json['targetFlag'] as int?,
      ignoreHorizon: json['ignoreHorizon'] as bool? ?? false,
      ignoreBlocks: json['ignoreBlocks'] as bool? ?? false,
      ignoreObjects: json['ignoreObjects'] as bool? ?? false,
      onWater: json['onWater'] as bool? ?? false,
      onLand: json['onLand'] as bool? ?? false,
    );
  }
}

/// Serialized call stack frame.
class AgiCallFrameSnapshot {
  final int scriptNumber;
  final int ip;

  const AgiCallFrameSnapshot({
    required this.scriptNumber,
    required this.ip,
  });

  Map<String, dynamic> toJson() => {
        'scriptNumber': scriptNumber,
        'ip': ip,
      };

  factory AgiCallFrameSnapshot.fromJson(Map<String, dynamic> json) =>
      AgiCallFrameSnapshot(
        scriptNumber: json['scriptNumber'] as int,
        ip: json['ip'] as int,
      );
}

/// Complete serializable snapshot of Sierra AGI Game State.
class AgiGameStateSnapshot {
  final String timestamp;
  final String label;
  final int roomNumber;
  final int cycleCount;
  final double speedHz;
  final int score;
  final int maxScore;
  final bool soundOn;
  final bool isPaused;
  final bool isInputEnabled;
  final bool isUserControl;
  final String lastSubmittedCommand;
  final String? lastError;

  /// Map of variable index (as string) to its integer value (0..255).
  final Map<String, int> variables;

  /// List of active (true) flag numbers.
  final List<int> activeFlags;

  /// List of active (true) controller numbers.
  final List<int> activeControllers;

  /// Map of inventory item index (as string) to room number (0 = player inventory, 255 = discarded).
  final Map<String, int> itemRooms;

  /// Map of string variable index (as string) to string value.
  final Map<String, String> strings;

  /// Serialized animated object states (only drawn or animated objects).
  final List<AgiObjectSnapshot> objects;

  /// Call stack frames.
  final List<AgiCallFrameSnapshot> callStack;

  final int scanStartIp;

  const AgiGameStateSnapshot({
    required this.timestamp,
    this.label = '',
    required this.roomNumber,
    required this.cycleCount,
    required this.speedHz,
    required this.score,
    required this.maxScore,
    required this.soundOn,
    required this.isPaused,
    required this.isInputEnabled,
    this.isUserControl = true,
    required this.lastSubmittedCommand,
    this.lastError,
    required this.variables,
    required this.activeFlags,
    required this.activeControllers,
    required this.itemRooms,
    required this.strings,
    required this.objects,
    required this.callStack,
    required this.scanStartIp,
  });

  /// Captures a complete snapshot from live [AgiGameEngine].
  factory AgiGameStateSnapshot.capture(AgiGameEngine engine, {String label = ''}) {
    final mem = engine.memory;
    final now = DateTime.now().toIso8601String();

    // Capture non-zero variables
    final vars = <String, int>{};
    for (int i = 0; i < mem.variables.length; i++) {
      if (mem.variables[i] != 0) {
        vars['$i'] = mem.variables[i];
      }
    }

    // Capture active flags
    final activeFlags = <int>[];
    for (int i = 0; i < mem.flags.length; i++) {
      if (mem.flags[i]) {
        activeFlags.add(i);
      }
    }

    // Capture active controllers
    final activeControllers = <int>[];
    for (int i = 0; i < mem.controllers.length; i++) {
      if (mem.controllers[i]) {
        activeControllers.add(i);
      }
    }

    // Capture item rooms
    final itemRooms = <String, int>{};
    mem.itemRooms.forEach((k, v) {
      itemRooms['$k'] = v;
    });

    // Capture non-empty strings
    final strings = <String, String>{};
    for (int i = 0; i < mem.strings.length; i++) {
      if (mem.strings[i].isNotEmpty) {
        strings['$i'] = mem.strings[i];
      }
    }

    // Capture animated objects that are drawn, animated, or have non-default state
    final objects = <AgiObjectSnapshot>[];
    for (final obj in engine.animatedObjects) {
      if (obj.isDrawn || obj.isAnimated || obj.number == 0) {
        objects.add(AgiObjectSnapshot.fromObject(obj));
      }
    }

    // Capture call stack
    final callStack = engine.interpreter.callStack
        .map((f) => AgiCallFrameSnapshot(
              scriptNumber: f.scriptNumber,
              ip: f.ip,
            ))
        .toList();

    return AgiGameStateSnapshot(
      timestamp: now,
      label: label.isEmpty ? 'Room ${engine.currentRoom} (Cycle ${engine.cycleCount})' : label,
      roomNumber: engine.currentRoom,
      cycleCount: engine.cycleCount,
      speedHz: engine.speedHz,
      score: mem.getVar(3),
      maxScore: mem.getVar(7),
      soundOn: mem.getFlag(9),
      isPaused: engine.isPaused,
      isInputEnabled: engine.isInputEnabled,
      isUserControl: engine.isUserControl,
      lastSubmittedCommand: engine.lastSubmittedCommand ?? '',
      lastError: engine.lastError,
      variables: vars,
      activeFlags: activeFlags,
      activeControllers: activeControllers,
      itemRooms: itemRooms,
      strings: strings,
      objects: objects,
      callStack: callStack,
      scanStartIp: mem.scanStartIp,
    );
  }

  /// Restores this snapshot into an existing [AgiGameEngine].
  void restore(AgiGameEngine engine) {
    final mem = engine.memory;

    // Reset memory
    mem.variables.fillRange(0, mem.variables.length, 0);
    variables.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx != null && idx >= 0 && idx < mem.variables.length) {
        mem.variables[idx] = v;
      }
    });

    mem.flags.fillRange(0, mem.flags.length, false);
    for (final f in activeFlags) {
      if (f >= 0 && f < mem.flags.length) {
        mem.flags[f] = true;
      }
    }

    mem.controllers.fillRange(0, mem.controllers.length, false);
    for (final c in activeControllers) {
      if (c >= 0 && c < mem.controllers.length) {
        mem.controllers[c] = true;
      }
    }

    mem.itemRooms.clear();
    itemRooms.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx != null) {
        mem.itemRooms[idx] = v;
      }
    });

    mem.strings.fillRange(0, mem.strings.length, '');
    strings.forEach((k, v) {
      final idx = int.tryParse(k);
      if (idx != null && idx >= 0 && idx < mem.strings.length) {
        mem.strings[idx] = v;
      }
    });

    mem.scanStartIp = scanStartIp;

    // Restore objects
    for (final obj in engine.animatedObjects) {
      obj.reset();
    }
    for (final snapObj in objects) {
      if (snapObj.number >= 0 && snapObj.number < engine.animatedObjects.length) {
        snapObj.restoreToObject(engine.animatedObjects[snapObj.number]);
      }
    }

    // Set engine properties
    engine.setSpeedHz(speedHz);
    engine.isUserControl = isUserControl;
    engine.isInputEnabled = isInputEnabled;
    if (isPaused) {
      engine.pause();
    } else {
      engine.resume();
    }

    // If room loader is present, reload room picture and logic without wiping objects
    if (engine.resourceLoader != null) {
      engine.reloadRoomForRestore(roomNumber);
    }
  }

  /// Serializes to Map.
  Map<String, dynamic> toJson() => {
        'version': '1.0',
        'timestamp': timestamp,
        'label': label,
        'roomNumber': roomNumber,
        'cycleCount': cycleCount,
        'speedHz': speedHz,
        'score': score,
        'maxScore': maxScore,
        'soundOn': soundOn,
        'isPaused': isPaused,
        'isInputEnabled': isInputEnabled,
        'isUserControl': isUserControl,
        'lastSubmittedCommand': lastSubmittedCommand,
        if (lastError != null) 'lastError': lastError,
        'variables': variables,
        'activeFlags': activeFlags,
        'activeControllers': activeControllers,
        'itemRooms': itemRooms,
        'strings': strings,
        'objects': objects.map((o) => o.toJson()).toList(),
        'callStack': callStack.map((c) => c.toJson()).toList(),
        'scanStartIp': scanStartIp,
      };

  /// Formats snapshot as a JSON string.
  String toJsonString({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  /// Deserializes from Map.
  factory AgiGameStateSnapshot.fromJson(Map<String, dynamic> json) {
    final varsRaw = (json['variables'] as Map?) ?? {};
    final vars = varsRaw.map((k, v) => MapEntry(k.toString(), v as int));

    final flagsRaw = json['activeFlags'] as List<dynamic>? ?? [];
    final activeFlags = flagsRaw.cast<int>();

    final ctrlRaw = json['activeControllers'] as List<dynamic>? ?? [];
    final activeControllers = ctrlRaw.cast<int>();

    final itemsRaw = (json['itemRooms'] as Map?) ?? {};
    final itemRooms = itemsRaw.map((k, v) => MapEntry(k.toString(), v as int));

    final strRaw = (json['strings'] as Map?) ?? {};
    final strings = strRaw.map((k, v) => MapEntry(k.toString(), v.toString()));

    final objsRaw = json['objects'] as List<dynamic>? ?? [];
    final objects = objsRaw
        .map((o) => AgiObjectSnapshot.fromJson((o as Map).cast<String, dynamic>()))
        .toList();

    final stackRaw = json['callStack'] as List<dynamic>? ?? [];
    final callStack = stackRaw
        .map((c) => AgiCallFrameSnapshot.fromJson((c as Map).cast<String, dynamic>()))
        .toList();

    return AgiGameStateSnapshot(
      timestamp: json['timestamp'] as String? ?? '',
      label: json['label'] as String? ?? '',
      roomNumber: json['roomNumber'] as int? ?? 0,
      cycleCount: json['cycleCount'] as int? ?? 0,
      speedHz: (json['speedHz'] as num?)?.toDouble() ?? 20.0,
      score: json['score'] as int? ?? 0,
      maxScore: json['maxScore'] as int? ?? 0,
      soundOn: json['soundOn'] as bool? ?? true,
      isPaused: json['isPaused'] as bool? ?? false,
      isInputEnabled: json['isInputEnabled'] as bool? ?? true,
      isUserControl: json['isUserControl'] as bool? ?? true,
      lastSubmittedCommand: json['lastSubmittedCommand'] as String? ?? '',
      lastError: json['lastError'] as String?,
      variables: vars,
      activeFlags: activeFlags,
      activeControllers: activeControllers,
      itemRooms: itemRooms,
      strings: strings,
      objects: objects,
      callStack: callStack,
      scanStartIp: json['scanStartIp'] as int? ?? 0,
    );
  }

  /// Deserializes from JSON string.
  factory AgiGameStateSnapshot.fromJsonString(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    return AgiGameStateSnapshot.fromJson(map);
  }
}

/// Diff report comparing two game snapshots.
class AgiGameStateDiff {
  final AgiGameStateSnapshot before;
  final AgiGameStateSnapshot after;

  /// Map of changed variables: `varNumber -> (beforeValue, afterValue)`.
  final Map<int, (int, int)> changedVariables = {};

  /// Flags that were turned ON in [after].
  final List<int> flagsSet = [];

  /// Flags that were turned OFF in [after].
  final List<int> flagsReset = [];

  /// Controllers that were toggled.
  final List<int> controllersSet = [];
  final List<int> controllersReset = [];

  /// Object changes: `objectNumber -> description of changes`.
  final Map<int, String> objectChanges = {};

  AgiGameStateDiff(this.before, this.after) {
    _computeDiff();
  }

  void _computeDiff() {
    // 1. Variables Diff
    final allVarKeys = {...before.variables.keys, ...after.variables.keys};
    for (final key in allVarKeys) {
      final varIdx = int.tryParse(key);
      if (varIdx == null) continue;
      final beforeVal = before.variables[key] ?? 0;
      final afterVal = after.variables[key] ?? 0;
      if (beforeVal != afterVal) {
        changedVariables[varIdx] = (beforeVal, afterVal);
      }
    }

    // 2. Flags Diff
    final beforeFlagsSet = before.activeFlags.toSet();
    final afterFlagsSet = after.activeFlags.toSet();

    for (final f in afterFlagsSet.difference(beforeFlagsSet)) {
      flagsSet.add(f);
    }
    for (final f in beforeFlagsSet.difference(afterFlagsSet)) {
      flagsReset.add(f);
    }
    flagsSet.sort();
    flagsReset.sort();

    // 3. Controllers Diff
    final beforeCtrlSet = before.activeControllers.toSet();
    final afterCtrlSet = after.activeControllers.toSet();
    for (final c in afterCtrlSet.difference(beforeCtrlSet)) {
      controllersSet.add(c);
    }
    for (final c in beforeCtrlSet.difference(afterCtrlSet)) {
      controllersReset.add(c);
    }
    controllersSet.sort();
    controllersReset.sort();

    // 4. Objects Diff
    final beforeObjs = {for (var o in before.objects) o.number: o};
    final afterObjs = {for (var o in after.objects) o.number: o};
    final allObjNums = {...beforeObjs.keys, ...afterObjs.keys};

    for (final num in allObjNums) {
      final b = beforeObjs[num];
      final a = afterObjs[num];

      if (b == null && a != null) {
        objectChanges[num] = 'Spawned at (${a.x}, ${a.y}), View ${a.view}, Pri ${a.priority}';
      } else if (b != null && a == null) {
        objectChanges[num] = 'Despawned (was at (${b.x}, ${b.y}))';
      } else if (b != null && a != null) {
        final diffs = <String>[];
        if (b.x != a.x || b.y != a.y) {
          diffs.add('pos: (${b.x}, ${b.y}) -> (${a.x}, ${a.y})');
        }
        if (b.view != a.view) diffs.add('view: ${b.view} -> ${a.view}');
        if (b.loop != a.loop) diffs.add('loop: ${b.loop} -> ${a.loop}');
        if (b.cel != a.cel) diffs.add('cel: ${b.cel} -> ${a.cel}');
        if (b.priority != a.priority) diffs.add('pri: ${b.priority} -> ${a.priority}');
        if (b.direction != a.direction) diffs.add('dir: ${b.direction} -> ${a.direction}');
        if (b.isDrawn != a.isDrawn) diffs.add('isDrawn: ${b.isDrawn} -> ${a.isDrawn}');
        if (b.isAnimated != a.isAnimated) diffs.add('isAnimated: ${b.isAnimated} -> ${a.isAnimated}');

        if (diffs.isNotEmpty) {
          objectChanges[num] = diffs.join(', ');
        }
      }
    }
  }

  /// Formats the diff into clean GitHub Markdown for easy copying into pair-programming chat.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('### 🎮 AGI Game State Diff');
    buffer.writeln('**Before**: `${before.label}` (Room ${before.roomNumber}, Cycle ${before.cycleCount})');
    buffer.writeln('**After**: `${after.label}` (Room ${after.roomNumber}, Cycle ${after.cycleCount})');
    buffer.writeln();

    if (before.roomNumber != after.roomNumber) {
      buffer.writeln('🏠 **Room Change**: Room ${before.roomNumber} &rarr; Room ${after.roomNumber}');
      buffer.writeln();
    }

    if (after.lastSubmittedCommand.isNotEmpty &&
        after.lastSubmittedCommand != before.lastSubmittedCommand) {
      buffer.writeln('💬 **Command Executed**: `"${after.lastSubmittedCommand}"`');
      buffer.writeln();
    }

    // Flags
    if (flagsSet.isNotEmpty || flagsReset.isNotEmpty) {
      buffer.writeln('#### 🚩 Flags Changed');
      if (flagsSet.isNotEmpty) {
        final setStr = flagsSet
            .map((f) => '`%f$f (${agiFlagNames[f] ?? "flag_$f"})` = ON')
            .join('\n- ');
        buffer.writeln('- $setStr');
      }
      if (flagsReset.isNotEmpty) {
        final resetStr = flagsReset
            .map((f) => '`%f$f (${agiFlagNames[f] ?? "flag_$f"})` = OFF')
            .join('\n- ');
        buffer.writeln('- $resetStr');
      }
      buffer.writeln();
    }

    // Variables
    if (changedVariables.isNotEmpty) {
      buffer.writeln('#### 🔢 Variables Changed');
      final sortedVars = changedVariables.keys.toList()..sort();
      for (final v in sortedVars) {
        final (beforeVal, afterVal) = changedVariables[v]!;
        final name = agiVariableNames[v] ?? 'var_$v';
        buffer.writeln('- `%v$v ($name)`: `$beforeVal` &rarr; `$afterVal`');
      }
      buffer.writeln();
    }

    // Animated Objects
    if (objectChanges.isNotEmpty) {
      buffer.writeln('#### 🚶 Animated Objects Changed');
      final sortedObjs = objectChanges.keys.toList()..sort();
      for (final num in sortedObjs) {
        final name = num == 0 ? 'Ego (o0)' : 'Object $num (o$num)';
        buffer.writeln('- **$name**: ${objectChanges[num]}');
      }
      buffer.writeln();
    }

    if (changedVariables.isEmpty &&
        flagsSet.isEmpty &&
        flagsReset.isEmpty &&
        objectChanges.isEmpty &&
        before.roomNumber == after.roomNumber) {
      buffer.writeln('_No variables, flags, or object positions changed between snapshots._');
    }

    return buffer.toString();
  }
}
