import 'dart:convert';
import 'dart:io';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:path/path.dart' as p;

/// Represents summary metadata for a saved game slot without needing to deserialize full engine state.
class SaveSlotInfo {
  final int slot;
  final String description;
  final DateTime timestamp;
  final int roomNumber;
  final int score;
  final int maxScore;
  final String filePath;
  final bool exists;

  const SaveSlotInfo({
    required this.slot,
    required this.description,
    required this.timestamp,
    required this.roomNumber,
    required this.score,
    required this.maxScore,
    required this.filePath,
    required this.exists,
  });

  /// Formatted slot display string (e.g. `Slot 1: In front of castle (Score: 12/210, Room 1)`).
  String get displayName {
    if (!exists) return 'Slot $slot: < Empty >';
    final desc = description.isNotEmpty ? description : 'Room $roomNumber';
    return 'Slot $slot: $desc';
  }

  /// Formatted human-readable date/time string.
  String get formattedDate {
    if (!exists) return '';
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

/// Serializer and Deserializer for Sierra AGI save game states (`.sav` files).
///
/// Implements full game state snapshots for `save.game()` (Opcode 125) and
/// `restore.game()` (Opcode 126).
class GameStateSerializer {
  /// Current save state format version.
  static const String version = '1.0';

  /// Default file extension for save game states.
  static const String fileExtension = 'sav';

  /// Serializes live [AgiGameEngine] state to a JSON-compatible Map.
  static Map<String, dynamic> serialize(
    AgiGameEngine engine, {
    String description = '',
  }) {
    final mem = engine.memory;
    final now = DateTime.now().toUtc().toIso8601String();

    // 1. All 256 variables as a full List<int>
    final variablesList = List<int>.from(mem.variables);

    // 2. All 256 flags as a full List<bool>
    final flagsList = List<bool>.from(mem.flags);

    // 3. String registers 0..23
    final stringsMap = <String, String>{};
    for (int i = 0; i < mem.strings.length; i++) {
      if (mem.strings[i].isNotEmpty) {
        stringsMap['$i'] = mem.strings[i];
      }
    }

    // 4. Inventory item room locations
    final itemRoomsMap = <String, int>{};
    mem.itemRooms.forEach((k, v) {
      itemRoomsMap['$k'] = v;
    });

    // 5. Active controllers (controllers that are set)
    final activeControllers = <int>[];
    for (int i = 0; i < mem.controllers.length; i++) {
      if (mem.controllers[i]) {
        activeControllers.add(i);
      }
    }

    // 6. Animated objects state
    final objectsList = <Map<String, dynamic>>[];
    for (final obj in engine.animatedObjects) {
      if (obj.isDrawn || obj.isAnimated || obj.number == 0 || obj.view != 0) {
        objectsList.add(AgiObjectSnapshot.fromObject(obj).toJson());
      }
    }

    // 7. Interpreter call stack
    final callStackList = engine.interpreter.callStack
        .map((f) => AgiCallFrameSnapshot(scriptNumber: f.scriptNumber, ip: f.ip).toJson())
        .toList();

    return {
      'version': version,
      'timestamp': now,
      'description': description.isNotEmpty
          ? description
          : 'Room ${mem.getVar(0)} (Score: ${mem.getVar(3)})',
      'currentRoom': mem.getVar(0),
      'previousRoom': mem.getVar(1),
      'score': mem.getVar(3),
      'scoreMax': mem.getVar(7),
      'cycleCount': engine.cycleCount,
      'speedHz': engine.speedHz,
      'soundOn': mem.getFlag(9),
      'isPaused': engine.isPaused,
      'isInputEnabled': engine.isInputEnabled,
      'isUserControl': engine.isUserControl,
      'scanStartIp': mem.scanStartIp,
      'scanStarts': mem.scanStarts.map((k, v) => MapEntry(k.toString(), v)),
      'lastSubmittedCommand': engine.lastSubmittedCommand ?? '',
      'variables': variablesList,
      'flags': flagsList,
      'strings': stringsMap,
      'itemRooms': itemRoomsMap,
      'activeControllers': activeControllers,
      'animatedObjects': objectsList,
      'callStack': callStackList,
    };
  }

  /// Formats serialized state as a JSON string.
  static String serializeToJson(
    AgiGameEngine engine, {
    String description = '',
    bool pretty = true,
  }) {
    final map = serialize(engine, description: description);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  /// Deserializes game state from [data] Map and restores it into [engine].
  static void deserialize(Map<String, dynamic> data, AgiGameEngine engine) {
    final mem = engine.memory;

    // 1. Restore Variables
    final varsRaw = data['variables'];
    if (varsRaw is List) {
      for (int i = 0; i < varsRaw.length && i < mem.variables.length; i++) {
        mem.setVar(i, (varsRaw[i] as num).toInt());
      }
    } else if (varsRaw is Map) {
      mem.variables.fillRange(0, mem.variables.length, 0);
      varsRaw.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null && idx >= 0 && idx < mem.variables.length) {
          mem.setVar(idx, (v as num).toInt());
        }
      });
    }

    // 2. Restore Flags
    final flagsRaw = data['flags'];
    if (flagsRaw is List) {
      if (flagsRaw.isNotEmpty && flagsRaw.first is bool) {
        for (int i = 0; i < flagsRaw.length && i < mem.flags.length; i++) {
          if (flagsRaw[i] == true) {
            mem.setFlag(i);
          } else {
            mem.resetFlag(i);
          }
        }
      } else {
        // List of active flag indices (integers)
        mem.flags.fillRange(0, mem.flags.length, false);
        for (final item in flagsRaw) {
          final idx = (item as num).toInt();
          if (idx >= 0 && idx < mem.flags.length) {
            mem.setFlag(idx);
          }
        }
      }
    }

    // 3. Restore Strings
    final strRaw = data['strings'];
    mem.strings.fillRange(0, mem.strings.length, '');
    if (strRaw is Map) {
      strRaw.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null && idx >= 0 && idx < mem.strings.length) {
          mem.setString(idx, v.toString());
        }
      });
    } else if (strRaw is List) {
      for (int i = 0; i < strRaw.length && i < mem.strings.length; i++) {
        mem.setString(i, strRaw[i]?.toString() ?? '');
      }
    }

    // 4. Restore Inventory Item Locations
    final itemRoomsRaw = data['itemRooms'];
    mem.itemRooms.clear();
    if (itemRoomsRaw is Map) {
      itemRoomsRaw.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null) {
          mem.itemRooms[idx] = (v as num).toInt();
        }
      });
    }

    // 5. Restore Controllers
    final ctrlRaw = data['activeControllers'];
    mem.resetControllers();
    if (ctrlRaw is List) {
      for (final c in ctrlRaw) {
        final idx = (c as num).toInt();
        mem.setController(idx, true);
      }
    }

    // 6. Restore Scan Starts
    mem.scanStarts.clear();
    if (data['scanStarts'] is Map) {
      (data['scanStarts'] as Map).forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null && v is num) {
          mem.setScanStart(idx, v.toInt());
        }
      });
    } else {
      final scanStartIp = (data['scanStartIp'] as num?)?.toInt() ?? 0;
      if (scanStartIp != 0) {
        mem.scanStartIp = scanStartIp;
      }
    }

    // 7. Restore Animated Objects
    for (final obj in engine.animatedObjects) {
      obj.reset();
    }
    final objsRaw = data['animatedObjects'] ?? data['objects'];
    if (objsRaw is List) {
      for (final item in objsRaw) {
        if (item is Map<String, dynamic>) {
          final snap = AgiObjectSnapshot.fromJson(item);
          if (snap.number >= 0 && snap.number < engine.animatedObjects.length) {
            snap.restoreToObject(engine.animatedObjects[snap.number]);
          }
        }
      }
    }

    // 8. Restore Engine Parameters
    final speed = (data['speedHz'] as num?)?.toDouble() ?? 20.0;
    engine.setSpeedHz(speed);

    engine.isUserControl = (data['isUserControl'] as bool?) ?? true;
    engine.isInputEnabled = (data['isInputEnabled'] as bool?) ?? true;

    // 9. Flag 12 (restore_in_progress) is set on restore per AGI specification
    // (Flag 5 / new_room is NOT set on restore in authentic Sierra AGI / NAGI / ScummVM)
    mem.setFlag(12); // restore_game command executed

    // 10. Reload current room resources if loader is present (without wiping animated objects)
    final currentRoom = mem.getVar(0);
    if (engine.resourceLoader != null) {
      engine.reloadRoomForRestore(currentRoom);
    }
  }

  /// Deserializes game state from a JSON string into [engine].
  static void deserializeFromJson(String jsonString, AgiGameEngine engine) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    deserialize(map, engine);
  }

  /// Parses slot metadata from a JSON string without full engine instantiation.
  static SaveSlotInfo parseMetadata(
    String jsonString, {
    int slot = 1,
    String filePath = '',
  }) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final desc = map['description']?.toString() ??
          map['label']?.toString() ??
          'Saved Game';
      final timestampStr = map['timestamp']?.toString() ?? '';
      final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
      final room = (map['currentRoom'] as num?)?.toInt() ??
          (map['roomNumber'] as num?)?.toInt() ??
          0;
      final score = (map['score'] as num?)?.toInt() ?? 0;
      final maxScore = (map['scoreMax'] as num?)?.toInt() ??
          (map['maxScore'] as num?)?.toInt() ??
          0;

      return SaveSlotInfo(
        slot: slot,
        description: desc,
        timestamp: timestamp,
        roomNumber: room,
        score: score,
        maxScore: maxScore,
        filePath: filePath,
        exists: true,
      );
    } catch (_) {
      return SaveSlotInfo(
        slot: slot,
        description: 'Corrupted Save Data',
        timestamp: DateTime.now(),
        roomNumber: 0,
        score: 0,
        maxScore: 0,
        filePath: filePath,
        exists: false,
      );
    }
  }

  /// Generates the standard file name for save slot [slot] (1..12).
  static String getSlotFileName(int slot) => 'slot_$slot.$fileExtension';

  /// Synchronously saves [engine] state to the specified [slot] in [directory].
  static File saveToSlotSync(
    AgiGameEngine engine,
    int slot, {
    String description = '',
    Directory? directory,
  }) {
    final saveDir = directory ?? Directory.current;
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }

    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    final jsonContent = serializeToJson(
      engine,
      description: description.isNotEmpty ? description : 'Slot $slot Save',
      pretty: true,
    );

    file.writeAsStringSync(jsonContent, flush: true);
    return file;
  }

  /// Saves [engine] state to the specified [slot] in [directory].
  static Future<File> saveToSlot(
    AgiGameEngine engine,
    int slot, {
    String description = '',
    Directory? directory,
  }) async {
    return saveToSlotSync(
      engine,
      slot,
      description: description,
      directory: directory,
    );
  }

  /// Synchronously restores [engine] state from the specified [slot] in [directory].
  static bool restoreFromSlotSync(
    AgiGameEngine engine,
    int slot, {
    Directory? directory,
  }) {
    final saveDir = directory ?? Directory.current;
    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    if (!file.existsSync()) {
      return false;
    }

    final jsonContent = file.readAsStringSync();
    deserializeFromJson(jsonContent, engine);
    return true;
  }

  /// Restores [engine] state from the specified [slot] in [directory].
  static Future<bool> restoreFromSlot(
    AgiGameEngine engine,
    int slot, {
    Directory? directory,
  }) async {
    return restoreFromSlotSync(engine, slot, directory: directory);
  }

  /// Synchronously lists metadata for save slots [1..maxSlots] in [directory].
  static List<SaveSlotInfo> listSlotsSync({
    Directory? directory,
    int maxSlots = 12,
  }) {
    final saveDir = directory ?? Directory.current;
    final results = <SaveSlotInfo>[];

    for (int slot = 1; slot <= maxSlots; slot++) {
      final fileName = getSlotFileName(slot);
      final filePath = p.join(saveDir.path, fileName);
      final file = File(filePath);

      if (file.existsSync()) {
        try {
          final content = file.readAsStringSync();
          results.add(parseMetadata(content, slot: slot, filePath: filePath));
        } catch (e) {
          results.add(SaveSlotInfo(
            slot: slot,
            description: 'Unreadable save slot',
            timestamp: DateTime.now(),
            roomNumber: 0,
            score: 0,
            maxScore: 0,
            filePath: filePath,
            exists: false,
          ));
        }
      } else {
        results.add(SaveSlotInfo(
          slot: slot,
          description: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          roomNumber: 0,
          score: 0,
          maxScore: 0,
          filePath: filePath,
          exists: false,
        ));
      }
    }

    return results;
  }

  /// Lists metadata for save slots [1..maxSlots] in [directory].
  static Future<List<SaveSlotInfo>> listSlots({
    Directory? directory,
    int maxSlots = 12,
  }) async {
    return listSlotsSync(directory: directory, maxSlots: maxSlots);
  }

  /// Synchronously retrieves metadata for a single slot [slot].
  static SaveSlotInfo? getSlotInfoSync(
    int slot, {
    Directory? directory,
  }) {
    final saveDir = directory ?? Directory.current;
    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    if (!file.existsSync()) {
      return null;
    }

    final content = file.readAsStringSync();
    return parseMetadata(content, slot: slot, filePath: filePath);
  }

  /// Retrieves metadata for a single slot [slot].
  static Future<SaveSlotInfo?> getSlotInfo(
    int slot, {
    Directory? directory,
  }) async {
    return getSlotInfoSync(slot, directory: directory);
  }

  /// Synchronously deletes save slot [slot] if present.
  static bool deleteSlotSync(int slot, {Directory? directory}) {
    final saveDir = directory ?? Directory.current;
    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Deletes save slot [slot] if present.
  static Future<bool> deleteSlot(int slot, {Directory? directory}) async {
    return deleteSlotSync(slot, directory: directory);
  }
}
