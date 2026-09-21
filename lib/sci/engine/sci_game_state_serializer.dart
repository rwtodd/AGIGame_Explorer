import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_agigame/domain/save_slot_info.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_game_state_snapshot.dart';
import 'package:path/path.dart' as p;

/// Serializer and Deserializer for Sierra SCI0 save game states (`.sav` files).
class SciGameStateSerializer {
  /// Current save state format version.
  static const String version = '1.0';

  /// Default file extension for save game states.
  static const String fileExtension = 'sav';

  /// Serializes live [SciGameEngine] state to a JSON-compatible Map.
  static Map<String, dynamic> serialize(
    SciGameEngine engine, {
    String description = '',
    bool includeThumbnail = true,
  }) {
    final snap = SciGameStateSnapshot.capture(
      engine,
      label: description.isNotEmpty ? description : null,
    );
    return snap.toJson(includeThumbnail: includeThumbnail);
  }

  /// Formats serialized state as a JSON string.
  static String serializeToJson(
    SciGameEngine engine, {
    String description = '',
    bool pretty = true,
    bool includeThumbnail = true,
  }) {
    final snap = SciGameStateSnapshot.capture(
      engine,
      label: description.isNotEmpty ? description : null,
    );
    return snap.toJsonString(pretty: pretty, includeThumbnail: includeThumbnail);
  }

  /// Deserializes game state from [data] Map and restores it into [engine].
  static void deserialize(Map<String, dynamic> data, SciGameEngine engine) {
    final snap = SciGameStateSnapshot.fromJson(data);
    snap.restore(engine);
  }

  /// Deserializes game state from a JSON string into [engine].
  static void deserializeFromJson(String jsonString, SciGameEngine engine) {
    final snap = SciGameStateSnapshot.fromJsonString(jsonString);
    snap.restore(engine);
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

      Uint8List? thumb;
      final thumbRaw = map['thumbnail'];
      if (thumbRaw != null && thumbRaw is String && thumbRaw.isNotEmpty) {
        try {
          thumb = base64Decode(thumbRaw);
        } catch (_) {}
      }

      return SaveSlotInfo(
        slot: slot,
        description: desc,
        timestamp: timestamp,
        roomNumber: room,
        score: score,
        maxScore: maxScore,
        filePath: filePath,
        exists: true,
        thumbnailRgba: thumb,
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

  /// Generates standard file name for save slot [slot] (1..12).
  static String getSlotFileName(int slot) => 'slot_$slot.$fileExtension';

  /// Synchronously saves [engine] state to the specified [slot] in [directory].
  static File saveToSlotSync(
    SciGameEngine engine,
    int slot, {
    String description = '',
    Directory? directory,
  }) {
    final saveDir = directory ?? engine.saveDirectory ?? Directory.current;
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }

    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    final snap = SciGameStateSnapshot.capture(
      engine,
      label: description.isNotEmpty ? description : 'Slot $slot Save',
    );
    final jsonContent = snap.toJsonString(pretty: true, includeThumbnail: true);

    file.writeAsStringSync(jsonContent, flush: true);
    return file;
  }

  /// Saves [engine] state to the specified [slot] in [directory].
  static Future<File> saveToSlot(
    SciGameEngine engine,
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
    SciGameEngine engine,
    int slot, {
    Directory? directory,
  }) {
    final saveDir = directory ?? engine.saveDirectory ?? Directory.current;
    final filePath = p.join(saveDir.path, getSlotFileName(slot));
    final file = File(filePath);

    if (!file.existsSync()) {
      return false;
    }

    final jsonContent = file.readAsStringSync();
    final snap = SciGameStateSnapshot.fromJsonString(jsonContent);
    snap.restore(engine);
    return true;
  }

  /// Restores [engine] state from the specified [slot] in [directory].
  static Future<bool> restoreFromSlot(
    SciGameEngine engine,
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
