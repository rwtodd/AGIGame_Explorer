import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/domain/save_slot_info.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

/// Helper to serialize [SciReg] to JSON Map.
Map<String, int> regToJson(SciReg r) => {'s': r.segment, 'o': r.offset};

/// Helper to deserialize [SciReg] from JSON Map.
SciReg regFromJson(dynamic j) {
  if (j is Map) {
    return SciReg(
      (j['s'] as num?)?.toInt() ?? 0,
      (j['o'] as num?)?.toInt() ?? 0,
    );
  } else if (j is int) {
    return SciReg.fromInt(j);
  }
  return SciReg.nullReg;
}

/// Serialized state of a single loaded script.
class SciScriptSnapshot {
  final int scriptNumber;
  final int segmentId;
  final List<SciReg> locals;
  final Map<int, List<SciReg>> objects;

  const SciScriptSnapshot({
    required this.scriptNumber,
    required this.segmentId,
    required this.locals,
    required this.objects,
  });

  Map<String, dynamic> toJson() => {
        'scriptNumber': scriptNumber,
        'segmentId': segmentId,
        'locals': locals.map(regToJson).toList(),
        'objects': {
          for (final e in objects.entries) '${e.key}': e.value.map(regToJson).toList(),
        },
      };

  factory SciScriptSnapshot.fromJson(Map<String, dynamic> json) {
    final rawLocals = json['locals'] as List? ?? const [];
    final locals = rawLocals.map(regFromJson).toList();
    final rawObjects = json['objects'] as Map? ?? const {};
    final objects = <int, List<SciReg>>{};
    for (final e in rawObjects.entries) {
      final offset = int.tryParse(e.key.toString());
      if (offset != null && e.value is List) {
        objects[offset] = (e.value as List).map(regFromJson).toList();
      }
    }
    return SciScriptSnapshot(
      scriptNumber: (json['scriptNumber'] as num?)?.toInt() ?? 0,
      segmentId: (json['segmentId'] as num?)?.toInt() ?? 0,
      locals: locals,
      objects: objects,
    );
  }
}

/// Serialized state of a dynamic object clone.
class SciCloneSnapshot {
  final int offset;
  final SciReg pos;
  final SciReg species;
  final SciReg superClass;
  final SciReg info;
  final SciReg name;
  final String? nameString;
  final List<SciReg> variables;
  final List<int> baseVars;
  final Map<int, int> methods;

  const SciCloneSnapshot({
    required this.offset,
    required this.pos,
    required this.species,
    required this.superClass,
    required this.info,
    required this.name,
    this.nameString,
    required this.variables,
    required this.baseVars,
    required this.methods,
  });

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'pos': regToJson(pos),
        'species': regToJson(species),
        'superClass': regToJson(superClass),
        'info': regToJson(info),
        'name': regToJson(name),
        if (nameString != null) 'nameString': nameString,
        'variables': variables.map(regToJson).toList(),
        'baseVars': baseVars,
        'methods': {for (final e in methods.entries) '${e.key}': e.value},
      };

  factory SciCloneSnapshot.fromJson(Map<String, dynamic> json) {
    final rawVars = json['variables'] as List? ?? const [];
    final rawBaseVars = json['baseVars'] as List? ?? const [];
    final rawMethods = json['methods'] as Map? ?? const {};
    final methods = <int, int>{};
    for (final e in rawMethods.entries) {
      final sel = int.tryParse(e.key.toString());
      if (sel != null && e.value is num) {
        methods[sel] = (e.value as num).toInt();
      }
    }
    return SciCloneSnapshot(
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      pos: regFromJson(json['pos']),
      species: regFromJson(json['species']),
      superClass: regFromJson(json['superClass']),
      info: regFromJson(json['info']),
      name: regFromJson(json['name']),
      nameString: json['nameString'] as String?,
      variables: rawVars.map(regFromJson).toList(),
      baseVars: rawBaseVars.map((v) => (v as num).toInt()).toList(),
      methods: methods,
    );
  }
}

/// Serialized state of a doubly linked list.
class SciListSnapshot {
  final int offset;
  final SciReg first;
  final SciReg last;
  final int count;

  const SciListSnapshot({
    required this.offset,
    required this.first,
    required this.last,
    required this.count,
  });

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'first': regToJson(first),
        'last': regToJson(last),
        'count': count,
      };

  factory SciListSnapshot.fromJson(Map<String, dynamic> json) => SciListSnapshot(
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        first: regFromJson(json['first']),
        last: regFromJson(json['last']),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// Serialized state of a doubly linked list node.
class SciNodeSnapshot {
  final int offset;
  final SciReg value;
  final SciReg key;
  final SciReg pred;
  final SciReg succ;

  const SciNodeSnapshot({
    required this.offset,
    required this.value,
    required this.key,
    required this.pred,
    required this.succ,
  });

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'value': regToJson(value),
        'key': regToJson(key),
        'pred': regToJson(pred),
        'succ': regToJson(succ),
      };

  factory SciNodeSnapshot.fromJson(Map<String, dynamic> json) => SciNodeSnapshot(
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        value: regFromJson(json['value']),
        key: regFromJson(json['key']),
        pred: regFromJson(json['pred']),
        succ: regFromJson(json['succ']),
      );
}

/// Serialized state of a dynamic memory hunk buffer.
class SciHunkSnapshot {
  final int offset;
  final Uint8List bytes;

  const SciHunkSnapshot({
    required this.offset,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'data': base64Encode(bytes),
      };

  factory SciHunkSnapshot.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'] as String? ?? '';
    return SciHunkSnapshot(
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      bytes: rawData.isNotEmpty ? base64Decode(rawData) : Uint8List(0),
    );
  }
}

/// Serialized PMachine execution stack frame.
class SciExecStackSnapshot {
  final SciReg objp;
  final SciReg pc;
  final int localSegment;
  final int sp;
  final int fp;
  final int argp;
  final int argc;
  final int tempCount;
  final int typeIndex;
  final int selector;
  final int script;
  final int pubfunct;
  final int varIndex;

  const SciExecStackSnapshot({
    required this.objp,
    required this.pc,
    required this.localSegment,
    required this.sp,
    required this.fp,
    this.argp = 0,
    this.argc = 0,
    this.tempCount = 0,
    this.typeIndex = 0,
    this.selector = 0,
    this.script = 0,
    this.pubfunct = 0,
    this.varIndex = 0,
  });

  factory SciExecStackSnapshot.fromFrame(SciExecStack f) => SciExecStackSnapshot(
        objp: f.objp,
        pc: f.pc,
        localSegment: f.localSegment,
        sp: f.sp,
        fp: f.fp,
        argp: f.argp,
        argc: f.argc,
        tempCount: f.tempCount,
        typeIndex: f.type.index,
        selector: f.selector,
        script: f.script,
        pubfunct: f.pubfunct,
        varIndex: f.varIndex,
      );

  SciExecStack toExecStack() => SciExecStack(
        objp: objp,
        pc: pc,
        localSegment: localSegment,
        sp: sp,
        fp: fp,
        argp: argp,
        argc: argc,
        tempCount: tempCount,
        type: SciExecStackType.values[typeIndex.clamp(0, SciExecStackType.values.length - 1)],
        selector: selector,
        script: script,
        pubfunct: pubfunct,
        varIndex: varIndex,
      );

  Map<String, dynamic> toJson() => {
        'objp': regToJson(objp),
        'pc': regToJson(pc),
        'localSegment': localSegment,
        'sp': sp,
        'fp': fp,
        'argp': argp,
        'argc': argc,
        'tempCount': tempCount,
        'typeIndex': typeIndex,
        'selector': selector,
        'script': script,
        'pubfunct': pubfunct,
        'varIndex': varIndex,
      };

  factory SciExecStackSnapshot.fromJson(Map<String, dynamic> json) => SciExecStackSnapshot(
        objp: regFromJson(json['objp']),
        pc: regFromJson(json['pc']),
        localSegment: (json['localSegment'] as num?)?.toInt() ?? 0,
        sp: (json['sp'] as num?)?.toInt() ?? 0,
        fp: (json['fp'] as num?)?.toInt() ?? 0,
        argp: (json['argp'] as num?)?.toInt() ?? 0,
        argc: (json['argc'] as num?)?.toInt() ?? 0,
        tempCount: (json['tempCount'] as num?)?.toInt() ?? 0,
        typeIndex: (json['typeIndex'] as num?)?.toInt() ?? 0,
        selector: (json['selector'] as num?)?.toInt() ?? 0,
        script: (json['script'] as num?)?.toInt() ?? 0,
        pubfunct: (json['pubfunct'] as num?)?.toInt() ?? 0,
        varIndex: (json['varIndex'] as num?)?.toInt() ?? 0,
      );
}

/// Complete serializable snapshot of Sierra SCI0 Game State.
class SciGameStateSnapshot {
  final String version;
  final String timestamp;
  final String label;
  final int roomNumber;
  final int prevRoomNumber;
  final int? picNumber;
  final int score;
  final int maxScore;
  final int cycleCount;
  final double speedHz;
  final bool isPaused;

  // Timing & Clock
  final int sciTicks;
  final int lastWaitTicks;
  final int lastWaitTime;
  final bool waitingForPit;
  final int gameIsRestarting;
  final int getTimeStreak;

  // Visual thumbnail
  final Uint8List? thumbnailRgba;

  // Globals
  final List<SciReg> globals;

  // SegManager elements
  final List<SciScriptSnapshot> scripts;
  final List<SciCloneSnapshot> clones;
  final List<SciListSnapshot> lists;
  final List<SciNodeSnapshot> nodes;
  final List<SciHunkSnapshot> hunks;
  final int nextScriptSegmentId;
  final int nextHunkOffset;

  // VM Execution State
  final SciReg acc;
  final SciReg prev;
  final int rest;
  final List<SciReg> stack;
  final List<SciExecStackSnapshot> executionStack;
  final int executionStackBase;
  final int stepCounter;

  const SciGameStateSnapshot({
    this.version = '1.0',
    required this.timestamp,
    required this.label,
    required this.roomNumber,
    required this.prevRoomNumber,
    this.picNumber,
    required this.score,
    required this.maxScore,
    required this.cycleCount,
    required this.speedHz,
    required this.isPaused,
    required this.sciTicks,
    required this.lastWaitTicks,
    required this.lastWaitTime,
    required this.waitingForPit,
    this.gameIsRestarting = 0,
    this.getTimeStreak = 0,
    this.thumbnailRgba,
    required this.globals,
    required this.scripts,
    required this.clones,
    required this.lists,
    required this.nodes,
    required this.hunks,
    required this.nextScriptSegmentId,
    required this.nextHunkOffset,
    required this.acc,
    required this.prev,
    this.rest = 0,
    required this.stack,
    required this.executionStack,
    this.executionStackBase = 0,
    this.stepCounter = 0,
  });

  /// Captures a complete snapshot from a live [SciGameEngine].
  ///
  /// Pass [includeThumbnail] false to skip screen compositing entirely; the
  /// pixel walk in [SciGameEngine.captureScreenThumbnailRgba] runs on the UI
  /// thread, so thumbnail-free callers (metadata, thumbnails-off exports)
  /// must not pay for it.
  factory SciGameStateSnapshot.capture(
    SciGameEngine engine, {
    String? label,
    Uint8List? thumbnailRgba,
    bool includeThumbnail = true,
  }) {
    final now = DateTime.now().toIso8601String();
    final seg = engine.segManager;
    final vm = engine.vm;
    final kernel = engine.kernel;

    final room = engine.currentRoom;
    final prevRoom = engine.prevRoomForSnapshot;
    final defaultLabel = 'Room $room (Cycle ${engine.cycleCount})';

    // Capture scripts
    final scripts = <SciScriptSnapshot>[];
    final mappedSegments = seg.scriptToSegment.values.toSet();
    for (final s in seg.loadedScripts.values) {
      if (!mappedSegments.contains(s.segmentId)) continue;
      final objects = <int, List<SciReg>>{};
      for (final obj in s.objects.values) {
        objects[obj.pos.offset] = List<SciReg>.from(obj.variables);
      }
      scripts.add(SciScriptSnapshot(
        scriptNumber: s.scriptNumber,
        segmentId: s.segmentId,
        locals: List<SciReg>.from(s.locals),
        objects: objects,
      ));
    }

    // Capture clones
    final clones = <SciCloneSnapshot>[];
    for (final e in seg.clones.entries) {
      final c = e.value;
      clones.add(SciCloneSnapshot(
        offset: e.key,
        pos: c.pos,
        species: c.species,
        superClass: c.superClass,
        info: c.info,
        name: c.name,
        nameString: c.nameString,
        variables: List<SciReg>.from(c.variables),
        baseVars: List<int>.from(c.baseVars),
        methods: Map<int, int>.from(c.methods),
      ));
    }

    // Capture lists
    final lists = <SciListSnapshot>[];
    for (final e in seg.lists.entries) {
      lists.add(SciListSnapshot(
        offset: e.key,
        first: e.value.first,
        last: e.value.last,
        count: e.value.count,
      ));
    }

    // Capture nodes
    final nodes = <SciNodeSnapshot>[];
    for (final e in seg.nodes.entries) {
      nodes.add(SciNodeSnapshot(
        offset: e.key,
        value: e.value.value,
        key: e.value.key,
        pred: e.value.pred,
        succ: e.value.succ,
      ));
    }

    // Capture hunks
    final hunks = <SciHunkSnapshot>[];
    for (final e in seg.hunkBuffers.entries) {
      hunks.add(SciHunkSnapshot(
        offset: e.key,
        bytes: Uint8List.fromList(e.value),
      ));
    }

    // Capture VM execution stack
    final execStack = vm.executionStack.map(SciExecStackSnapshot.fromFrame).toList();

    final Uint8List? thumb =
        includeThumbnail ? (thumbnailRgba ?? engine.captureScreenThumbnailRgba()) : null;

    return SciGameStateSnapshot(
      version: '1.0',
      timestamp: now,
      label: label ?? defaultLabel,
      roomNumber: room,
      prevRoomNumber: prevRoom,
      picNumber: kernel.currentPic?.picNumber,
      score: engine.score,
      maxScore: engine.maxScore,
      cycleCount: engine.cycleCount,
      speedHz: engine.speedHz,
      isPaused: engine.isPaused,
      sciTicks: kernel.currentSciTicks,
      lastWaitTicks: kernel.lastWaitTicks,
      lastWaitTime: kernel.lastWaitTime,
      waitingForPit: kernel.waitingForPit,
      gameIsRestarting: kernel.gameIsRestarting,
      getTimeStreak: kernel.getTimeStreak,
      thumbnailRgba: thumb,
      globals: List<SciReg>.from(seg.globals),
      scripts: scripts,
      clones: clones,
      lists: lists,
      nodes: nodes,
      hunks: hunks,
      nextScriptSegmentId: seg.nextScriptSegmentId,
      nextHunkOffset: seg.nextHunkOffset,
      acc: vm.acc,
      prev: vm.prev,
      rest: vm.r_rest,
      stack: List<SciReg>.from(vm.stack),
      executionStack: execStack,
      executionStackBase: vm.executionStackBase,
      stepCounter: vm.stepCounter,
    );
  }

  /// Restores this snapshot into an existing [SciGameEngine].
  void restore(SciGameEngine engine, {bool? preservePauseState}) {
    final wasPaused = engine.isPaused;
    engine.pause();

    engine.atlasManager.clear();
    engine.segManager.reset();
    engine.vm.reset();
    engine.kernel.reset();

    // 1. Re-initialize vocabularies and class table
    final vocab996Bytes = engine.volumeManager.getResource(SciResourceType.vocab, 996);
    engine.segManager.loadClassTable(vocab996Bytes);

    final vocab997Bytes = engine.volumeManager.getResource(SciResourceType.vocab, 997);
    engine.selectors.loadVocab997(vocab997Bytes, isEarlySci0: engine.volumeManager.isEarlySci0);

    final vocab0Entry = engine.volumeManager.resourceMap.findById(const SciResourceId(SciResourceType.vocab, 0));
    if (vocab0Entry != null) {
      final vocab0Bytes = engine.volumeManager.getResource(SciResourceType.vocab, 0);
      final vocab = SciVocab();
      vocab.loadVocab000(vocab0Bytes);
      engine.kernel.vocab = vocab;
    }
    final vocab900Entry = engine.volumeManager.resourceMap.findById(const SciResourceId(SciResourceType.vocab, 900));
    if (vocab900Entry != null) {
      try {
        engine.kernel.vocab900 = engine.volumeManager.getResource(SciResourceType.vocab, 900);
      } catch (_) {}
    }

    // 2. Pre-populate scriptToSegment mapping so dependent script instantiations use correct segments
    for (final s in scripts) {
      engine.segManager.scriptToSegment[s.scriptNumber] = s.segmentId;
    }

    // Ensure script 0 is instantiated first so globals and class tables are ready
    final orderedScripts = List<SciScriptSnapshot>.from(scripts)
      ..sort((a, b) {
        if (a.scriptNumber == 0) return -1;
        if (b.scriptNumber == 0) return 1;
        return a.scriptNumber.compareTo(b.scriptNumber);
      });

    for (final s in orderedScripts) {
      final script = engine.segManager.instantiateScript(s.scriptNumber, engine.volumeManager);

      // Restore locals
      for (var i = 0; i < s.locals.length && i < script.locals.length; i++) {
        script.locals[i] = s.locals[i];
      }

      // Restore object variables
      for (final e in s.objects.entries) {
        final obj = script.getObject(e.key);
        if (obj != null) {
          for (var i = 0; i < e.value.length && i < obj.variables.length; i++) {
            obj.variables[i] = e.value[i];
          }
        }
      }
    }

    // 3. Restore globals
    engine.segManager.globals = List<SciReg>.from(globals);
    final s0Seg = engine.segManager.scriptToSegment[0];
    if (s0Seg != null) {
      final s0 = engine.segManager.loadedScripts[s0Seg];
      if (s0 != null) {
        for (var i = 0; i < engine.segManager.globals.length && i < s0.locals.length; i++) {
          s0.locals[i] = engine.segManager.globals[i];
        }
      }
    }

    // 4. Restore clones
    for (final c in clones) {
      final cloneObj = SciObject(
        pos: c.pos,
        variables: List<SciReg>.from(c.variables),
        baseVars: List<int>.from(c.baseVars),
        methods: Map<int, int>.from(c.methods),
        nameString: c.nameString,
      );
      engine.segManager.clones[c.offset] = cloneObj;
    }

    // 5. Restore lists
    for (final l in lists) {
      engine.segManager.lists[l.offset] = SciList(
        pos: SciReg.pointer(SciSegManager.listSegmentId, l.offset),
        first: l.first,
        last: l.last,
        count: l.count,
      );
    }

    // 6. Restore nodes
    for (final n in nodes) {
      engine.segManager.nodes[n.offset] = SciNode(
        pos: SciReg.pointer(SciSegManager.nodeSegmentId, n.offset),
        value: n.value,
        key: n.key,
        pred: n.pred,
        succ: n.succ,
      );
    }

    // 7. Restore hunks & allocators
    for (final h in hunks) {
      engine.segManager.hunkBuffers[h.offset] = h.bytes;
    }
    engine.segManager.nextHunkOffset = nextHunkOffset;
    engine.segManager.nextScriptSegmentId = nextScriptSegmentId;

    // 8. Restore clock and kernel
    engine.kernel.currentSciTicks = sciTicks;
    engine.kernel.lastWaitTicks = lastWaitTicks;
    engine.kernel.lastWaitTime = lastWaitTime;
    engine.kernel.waitingForPit = waitingForPit;
    engine.kernel.gameIsRestarting = 2; // GAMEISRESTARTING_RESTORE
    engine.kernel.getTimeStreak = getTimeStreak;

    // 9. Restore cycle and picture
    engine.cycleCountForRestore = cycleCount;
    engine.speedHz = speedHz;
    engine.prevRoomForSnapshot = prevRoomNumber;
    if (picNumber != null) {
      engine.kernel.initPicture(picNumber!);
    }

    // 10. Restore VM state
    engine.vm.acc = acc;
    engine.vm.prev = prev;
    engine.vm.r_rest = rest;
    engine.vm.executionStackBase = executionStackBase;
    engine.vm.stepCounter = stepCounter;
    engine.vm.yieldOnAnimate = true;
    engine.vm.abortScriptProcessing = false;

    // 11. Locate Game object and resume execution via Sierra (theGame replay:)
    if (s0Seg != null) {
      final s0 = engine.segManager.loadedScripts[s0Seg];
      if (s0 != null && s0.exports.isNotEmpty) {
        final gameObjOffset = s0.exports[0];
        final game = s0.getObject(gameObjOffset);
        if (game != null) {
          engine.gameObjForRestore = game.pos;
        }
      }
    }
    engine.syncGameSpeedForRestore();
    engine.startedForRestore = true;

    final gameObj = engine.gameObjForRestore;
    if (gameObj != null && engine.selectors.replay != -1) {
      engine.vm.executionStack.clear();
      engine.vm.stack.clear();
      try {
        engine.vm.sendSelector(gameObj, engine.selectors.replay, []);
      } catch (e, st) {
        if (engine.kernel.verboseLogging) {
          debugPrint('[SciEngine] ERROR during restore replay: $e\n$st');
        }
      }
    } else {
      // Fallback: restore operand stack and call stack directly
      engine.vm.stack.clear();
      engine.vm.stack.addAll(stack);
      engine.vm.executionStack.clear();
      for (final f in executionStack) {
        engine.vm.executionStack.add(f.toExecStack());
      }
    }

    if (preservePauseState ?? true) {
      if (wasPaused) {
        engine.pause();
      } else {
        engine.resume();
      }
    } else {
      if (isPaused) {
        engine.pause();
      } else {
        engine.resume();
      }
    }

    engine.notifyListeners();
  }

  Map<String, dynamic> toJson({bool includeThumbnail = true}) => {
        'version': version,
        'engine': 'SCI0',
        'timestamp': timestamp,
        'label': label,
        'roomNumber': roomNumber,
        'prevRoomNumber': prevRoomNumber,
        if (picNumber != null) 'picNumber': picNumber,
        'score': score,
        'maxScore': maxScore,
        'cycleCount': cycleCount,
        'speedHz': speedHz,
        'isPaused': isPaused,
        'clock': {
          'sciTicks': sciTicks,
          'lastWaitTicks': lastWaitTicks,
          'lastWaitTime': lastWaitTime,
          'waitingForPit': waitingForPit,
          'gameIsRestarting': gameIsRestarting,
          'getTimeStreak': getTimeStreak,
        },
        'globals': globals.map(regToJson).toList(),
        'scripts': scripts.map((s) => s.toJson()).toList(),
        'clones': clones.map((c) => c.toJson()).toList(),
        'lists': lists.map((l) => l.toJson()).toList(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'hunks': hunks.map((h) => h.toJson()).toList(),
        'allocators': {
          'nextScriptSegmentId': nextScriptSegmentId,
          'nextHunkOffset': nextHunkOffset,
        },
        'vm': {
          'acc': regToJson(acc),
          'prev': regToJson(prev),
          'rest': rest,
          'stack': stack.map(regToJson).toList(),
          'executionStack': executionStack.map((f) => f.toJson()).toList(),
          'executionStackBase': executionStackBase,
          'stepCounter': stepCounter,
        },
        if (includeThumbnail && thumbnailRgba != null) ...{
          'thumbnail': base64Encode(thumbnailRgba!),
          if (SaveSlotInfo.inferThumbnailSize(thumbnailRgba!.length) case final size?) ...{
            'thumbnailWidth': size.$1,
            'thumbnailHeight': size.$2,
          },
        },
      };

  String toJsonString({bool pretty = true, bool includeThumbnail = true}) {
    final map = toJson(includeThumbnail: includeThumbnail);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  factory SciGameStateSnapshot.fromJson(Map<String, dynamic> json) {
    final rawClock = json['clock'] as Map? ?? const {};
    final rawAlloc = json['allocators'] as Map? ?? const {};
    final rawVm = json['vm'] as Map? ?? const {};

    final rawGlobals = json['globals'] as List? ?? const [];
    final globals = rawGlobals.map(regFromJson).toList();

    final rawScripts = json['scripts'] as List? ?? const [];
    final scripts = rawScripts
        .map((s) => SciScriptSnapshot.fromJson(s as Map<String, dynamic>))
        .toList();

    final rawClones = json['clones'] as List? ?? const [];
    final clones = rawClones
        .map((c) => SciCloneSnapshot.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawLists = json['lists'] as List? ?? const [];
    final lists = rawLists
        .map((l) => SciListSnapshot.fromJson(l as Map<String, dynamic>))
        .toList();

    final rawNodes = json['nodes'] as List? ?? const [];
    final nodes = rawNodes
        .map((n) => SciNodeSnapshot.fromJson(n as Map<String, dynamic>))
        .toList();

    final rawHunks = json['hunks'] as List? ?? const [];
    final hunks = rawHunks
        .map((h) => SciHunkSnapshot.fromJson(h as Map<String, dynamic>))
        .toList();

    final rawStack = rawVm['stack'] as List? ?? const [];
    final stack = rawStack.map(regFromJson).toList();

    final rawExecStack = rawVm['executionStack'] as List? ?? const [];
    final executionStack = rawExecStack
        .map((f) => SciExecStackSnapshot.fromJson(f as Map<String, dynamic>))
        .toList();

    Uint8List? thumb;
    final thumbRaw = json['thumbnail'];
    if (thumbRaw != null && thumbRaw is String && thumbRaw.isNotEmpty) {
      try {
        thumb = base64Decode(thumbRaw);
      } catch (_) {}
    }

    return SciGameStateSnapshot(
      version: json['version']?.toString() ?? '1.0',
      timestamp: json['timestamp']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      roomNumber: (json['roomNumber'] as num?)?.toInt() ?? 0,
      prevRoomNumber: (json['prevRoomNumber'] as num?)?.toInt() ?? 0,
      picNumber: (json['picNumber'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toInt() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toInt() ?? 0,
      cycleCount: (json['cycleCount'] as num?)?.toInt() ?? 0,
      speedHz: (json['speedHz'] as num?)?.toDouble() ?? 20.0,
      isPaused: json['isPaused'] as bool? ?? false,
      sciTicks: (rawClock['sciTicks'] as num?)?.toInt() ?? 0,
      lastWaitTicks: (rawClock['lastWaitTicks'] as num?)?.toInt() ?? 0,
      lastWaitTime: (rawClock['lastWaitTime'] as num?)?.toInt() ?? 0,
      waitingForPit: rawClock['waitingForPit'] as bool? ?? false,
      gameIsRestarting: (rawClock['gameIsRestarting'] as num?)?.toInt() ?? 0,
      getTimeStreak: (rawClock['getTimeStreak'] as num?)?.toInt() ?? 0,
      thumbnailRgba: thumb,
      globals: globals,
      scripts: scripts,
      clones: clones,
      lists: lists,
      nodes: nodes,
      hunks: hunks,
      nextScriptSegmentId: (rawAlloc['nextScriptSegmentId'] as num?)?.toInt() ?? 1,
      nextHunkOffset: (rawAlloc['nextHunkOffset'] as num?)?.toInt() ?? 1,
      acc: regFromJson(rawVm['acc']),
      prev: regFromJson(rawVm['prev']),
      rest: (rawVm['rest'] as num?)?.toInt() ?? 0,
      stack: stack,
      executionStack: executionStack,
      executionStackBase: (rawVm['executionStackBase'] as num?)?.toInt() ?? 0,
      stepCounter: (rawVm['stepCounter'] as num?)?.toInt() ?? 0,
    );
  }

  factory SciGameStateSnapshot.fromJsonString(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    return SciGameStateSnapshot.fromJson(map);
  }
}
