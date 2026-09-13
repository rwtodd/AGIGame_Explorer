// In-memory model of an instantiated SCI0 Script resource.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/parser/sci_said_matcher.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

/// Represents an instantiated SCI0 script resource in memory.
class SciScript {
  /// Script resource number (e.g. 0, 994, 999).
  final int scriptNumber;

  /// Assigned memory segment ID in [SciSegManager].
  final int segmentId;

  /// Raw byte buffer of the script.
  final Uint8List bytes;

  /// Public export offsets (the on-disk count word is dropped by the parser).
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

  /// Code block ranges (offset, length) within the script.
  final List<(int offset, int length)> codeBlocks;

  /// String block ranges (offset, length) within the script.
  final List<(int offset, int length)> stringBlocks;

  /// Said specification block ranges (offset, length) within the script.
  final List<(int offset, int length)> saidBlocks;

  /// Parsed Said specifications by script offset.
  final Map<int, SciSaidSpec> saidSpecs;

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
    List<(int offset, int length)>? codeBlocks,
    List<(int offset, int length)>? stringBlocks,
    List<(int offset, int length)>? saidBlocks,
    Map<int, SciSaidSpec>? saidSpecs,
  })  : exports = exports != null ? List<int>.unmodifiable(exports) : const <int>[],
        locals = locals != null ? List<SciReg>.from(locals) : <SciReg>[],
        objects = objects != null ? Map<int, SciObject>.from(objects) : <int, SciObject>{},
        strings = strings != null ? Map<int, String>.from(strings) : <int, String>{},
        synonyms = synonyms != null ? List<int>.unmodifiable(synonyms) : const <int>[],
        relocationOffsets = relocationOffsets != null
            ? List<int>.unmodifiable(relocationOffsets)
            : const <int>[],
        codeBlocks = codeBlocks != null
            ? List<(int offset, int length)>.unmodifiable(codeBlocks)
            : const [],
        stringBlocks = stringBlocks != null
            ? List<(int offset, int length)>.unmodifiable(stringBlocks)
            : const [],
        saidBlocks = saidBlocks != null
            ? List<(int offset, int length)>.unmodifiable(saidBlocks)
            : const [],
        saidSpecs = saidSpecs != null ? Map<int, SciSaidSpec>.from(saidSpecs) : <int, SciSaidSpec>{};

  /// Total script buffer size in bytes.
  int get size => bytes.length;

  /// Returns the offset for an exported function or object by export index.
  int? getExportOffset(int exportIndex) {
    if (exportIndex < 0 || exportIndex >= exports.length) return null;
    return exports[exportIndex];
  }

  /// Retrieves an object at [offset], or null if not found.
  SciObject? getObject(int offset) => objects[offset];

  /// Returns whether an offset is within a declared strings block or known string table.
  bool isStringOffset(int offset) {
    if (strings.containsKey(offset)) return true;
    for (final block in stringBlocks) {
      if (offset >= block.$1 && offset < block.$1 + block.$2) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether an offset is within a declared Said block or known Said specs table.
  bool isSaidOffset(int offset) {
    if (saidSpecs.containsKey(offset)) return true;
    for (final block in saidBlocks) {
      if (offset >= block.$1 && offset < block.$1 + block.$2) {
        return true;
      }
    }
    return false;
  }

  /// Retrieves a parsed [SciSaidSpec] at [offset], or creates one if in a Said block.
  SciSaidSpec? getSaidSpec(int offset) {
    if (saidSpecs.containsKey(offset)) return saidSpecs[offset];
    if (isSaidOffset(offset) && offset >= 0 && offset < bytes.length) {
      final spec = SciSaidSpec.fromBytes(bytes, offset);
      saidSpecs[offset] = spec;
      return spec;
    }
    return null;
  }

  /// Retrieves a null-terminated ASCII string starting at [offset].
  ///
  /// Only returns valid strings if [offset] resides within a known strings block
  /// or pre-parsed object name table, preventing binary/bytecode from being
  /// misinterpreted as strings.
  String getString(int offset) {
    if (strings.containsKey(offset)) return strings[offset]!;
    if (offset < 0 || offset >= bytes.length) return '';
    if (!isStringOffset(offset)) return '';

    var end = offset;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    final slice = bytes.sublist(offset, end);
    // Validate characters: printable ASCII (32..126), tab (9), newline (10), CR (13), or menu icon (1)
    for (final b in slice) {
      if (b != 1 && b != 9 && b != 10 && b != 13 && (b < 32 || b > 126)) {
        return '';
      }
    }
    return String.fromCharCodes(slice);
  }

  /// Returns whether an object exists at the specified [offset].
  bool isObject(int offset) => objects.containsKey(offset);

  /// Returns all procedure entry offsets (exported procedures and code block offsets).
  List<int> get procedureOffsets {
    final set = <int>{};
    for (final exp in exports) {
      if (exp != 0 && !isObject(exp)) {
        set.add(exp);
      }
    }
    for (final cb in codeBlocks) {
      set.add(cb.$1);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  String toString() =>
      'SciScript(#$scriptNumber, seg: $segmentId, size: ${bytes.length}, objs: ${objects.length}, locals: ${locals.length}, exports: ${exports.length})';
}
