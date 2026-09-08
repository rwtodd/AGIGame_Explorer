// In-memory model of an instantiated SCI0 Script resource.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

/// Represents an instantiated SCI0 script resource in memory.
class SciScript {
  /// Script resource number (e.g. 0, 994, 999).
  final int scriptNumber;

  /// Assigned memory segment ID in [SciSegManager].
  final int segmentId;

  /// Raw byte buffer of the script.
  final Uint8List bytes;

  /// Public exports table (entry 0 is export count, followed by offsets).
  final List<int> exports;

  /// Local variables for this script.
  final List<SciReg> locals;

  /// Objects defined in this script, keyed by their offset within the script.
  final Map<int, SciObject> objects;

  /// String table or extracted strings by relative offset.
  final Map<int, String> strings;

  /// Synonyms table.
  final List<int> synonyms;

  /// Pointers/offsets relocated by the relocation block.
  final List<int> relocationOffsets;

  SciScript({
    required this.scriptNumber,
    required this.segmentId,
    required this.bytes,
    List<int>? exports,
    List<SciReg>? locals,
    Map<int, SciObject>? objects,
    Map<int, String>? strings,
    List<int>? synonyms,
    List<int>? relocationOffsets,
  })  : exports = exports != null ? List<int>.unmodifiable(exports) : const <int>[],
        locals = locals != null ? List<SciReg>.from(locals) : <SciReg>[],
        objects = objects != null ? Map<int, SciObject>.from(objects) : <int, SciObject>{},
        strings = strings != null ? Map<int, String>.from(strings) : <int, String>{},
        synonyms = synonyms != null ? List<int>.unmodifiable(synonyms) : const <int>[],
        relocationOffsets = relocationOffsets != null
            ? List<int>.unmodifiable(relocationOffsets)
            : const <int>[];

  /// Total script buffer size in bytes.
  int get size => bytes.length;

  /// Returns the offset for an exported function or object by export index.
  int? getExportOffset(int exportIndex) {
    if (exportIndex < 0 || exportIndex >= exports.length) return null;
    return exports[exportIndex];
  }

  /// Retrieves an object at [offset], or null if not found.
  SciObject? getObject(int offset) => objects[offset];

  /// Retrieves a null-terminated ASCII string starting at [offset].
  String getString(int offset) {
    if (strings.containsKey(offset)) return strings[offset]!;
    if (offset < 0 || offset >= bytes.length) return '';
    var end = offset;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    final str = String.fromCharCodes(bytes.sublist(offset, end));
    strings[offset] = str;
    return str;
  }

  @override
  String toString() =>
      'SciScript(#$scriptNumber, seg: $segmentId, size: ${bytes.length}, objs: ${objects.length}, locals: ${locals.length}, exports: ${exports.length})';
}
