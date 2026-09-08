// SCI0 Script Resource Bytecode and Object Parser.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';

/// Block types in SCI0 compiled `SCRIPT` resources.
class SciScriptBlockType {
  static const int terminator = 0x0000;
  static const int object = 0x0001;
  static const int code = 0x0002;
  static const int synonyms = 0x0003;
  static const int said = 0x0004;
  static const int strings = 0x0005;
  static const int classBlock = 0x0006;
  static const int exports = 0x0007;
  static const int pointers = 0x0008;
  static const int localVars = 0x000A;
}

/// Parser for SCI0 compiled `SCRIPT` resources.
class SciScriptParser {
  const SciScriptParser();

  /// Parses raw SCI0 script bytes into a [SciScript].
  SciScript parse(
    int scriptNumber,
    Uint8List data,
    int segmentId, [
    SciSegManager? segMan,
  ]) {
    final byteData = ByteData.sublistView(data);
    var pos = 0;

    final exports = <int>[];
    final locals = <SciReg>[];
    var localsOffset = 0;
    final objects = <int, SciObject>{};
    final strings = <int, String>{};
    final synonyms = <int>[];
    final relocationOffsets = <int>[];

    // Read blocks sequentially until terminator (blockType == 0) or EOF
    while (pos + 4 <= data.length) {
      final blockType = byteData.getUint16(pos, Endian.little);
      if (blockType == SciScriptBlockType.terminator) break;

      final blockSize = byteData.getUint16(pos + 2, Endian.little);
      if (blockSize < 4 || pos + blockSize > data.length) {
        break;
      }

      switch (blockType) {
        case SciScriptBlockType.exports:
          _parseExports(byteData, pos, blockSize, exports);
          break;

        case SciScriptBlockType.localVars:
          localsOffset = pos + 4;
          _parseLocalVars(byteData, pos, blockSize, locals);
          break;

        case SciScriptBlockType.pointers:
          _parseRelocationPointers(byteData, pos, blockSize, relocationOffsets);
          break;

        case SciScriptBlockType.object:
        case SciScriptBlockType.classBlock:
          final obj = _parseObject(
            data,
            byteData,
            pos,
            blockSize,
            segmentId,
            isClass: blockType == SciScriptBlockType.classBlock,
          );
          if (obj != null) {
            objects[obj.pos.offset] = obj;
          }
          break;

        case SciScriptBlockType.synonyms:
          _parseSynonyms(byteData, pos, blockSize, synonyms);
          break;

        case SciScriptBlockType.strings:
          // Strings are indexed on-demand or parsed directly
          break;

        case SciScriptBlockType.code:
        case SciScriptBlockType.said:
        default:
          break;
      }

      pos += blockSize;
    }

    // Apply relocation offsets: converts immediate offsets into pointers (segmentId:offset)
    _applyRelocations(
      segmentId,
      relocationOffsets,
      localsOffset,
      locals,
      objects,
    );

    return SciScript(
      scriptNumber: scriptNumber,
      segmentId: segmentId,
      bytes: data,
      exports: exports,
      locals: locals,
      objects: objects,
      strings: strings,
      synonyms: synonyms,
      relocationOffsets: relocationOffsets,
    );
  }

  void _parseExports(
    ByteData byteData,
    int pos,
    int blockSize,
    List<int> exports,
  ) {
    if (blockSize < 6) return;
    final count = byteData.getUint16(pos + 4, Endian.little);
    for (var i = 0; i < count && (pos + 6 + (i + 1) * 2) <= pos + blockSize; i++) {
      final exportOffset = byteData.getUint16(pos + 6 + i * 2, Endian.little);
      exports.add(exportOffset);
    }
  }

  void _parseLocalVars(
    ByteData byteData,
    int pos,
    int blockSize,
    List<SciReg> locals,
  ) {
    final count = (blockSize - 4) >> 1;
    for (var i = 0; i < count; i++) {
      final val = byteData.getUint16(pos + 4 + i * 2, Endian.little);
      locals.add(SciReg.fromInt(val));
    }
  }

  void _parseRelocationPointers(
    ByteData byteData,
    int pos,
    int blockSize,
    List<int> relocationOffsets,
  ) {
    final count = (blockSize - 4) >> 1;
    for (var i = 0; i < count; i++) {
      final reloc = byteData.getUint16(pos + 4 + i * 2, Endian.little);
      relocationOffsets.add(reloc);
    }
  }

  SciObject? _parseObject(
    Uint8List data,
    ByteData byteData,
    int blockPos,
    int blockSize,
    int segmentId, {
    required bool isClass,
  }) {
    // Header layout:
    // blockPos + 0: blockType (uint16)
    // blockPos + 2: blockSize (uint16)
    // blockPos + 4: magic 0x1234 (uint16)
    // blockPos + 6: localVariables offset (uint16)
    // blockPos + 8: functionArea offset (uint16)
    // blockPos + 10: selectorCounter (uint16)
    // blockPos + 12: properties begin (objectPosition = blockPos + 12)
    if (blockSize < 12) return null;

    final magic = byteData.getUint16(blockPos + 4, Endian.little);
    if (magic != 0x1234) {
      // Not a valid SCI0 object header
      return null;
    }

    final funcAreaOffset = byteData.getUint16(blockPos + 8, Endian.little);
    final selectorCount = byteData.getUint16(blockPos + 10, Endian.little);
    final objectPos = blockPos + 12;

    // Read properties (selector values)
    final variables = <SciReg>[];
    for (var i = 0; i < selectorCount; i++) {
      final propVal = byteData.getUint16(objectPos + i * 2, Endian.little);
      variables.add(SciReg.fromInt(propVal));
    }

    // Read baseVars (selector IDs) if this is a Class
    final baseVars = <int>[];
    if (isClass) {
      final baseVarsOffset = objectPos + selectorCount * 2;
      for (var i = 0; i < selectorCount; i++) {
        final selId = byteData.getUint16(baseVarsOffset + i * 2, Endian.little);
        baseVars.add(selId);
      }
    }

    // Read method dictionary
    final methods = <int, int>{};
    final methodBlockOffset = objectPos + funcAreaOffset - 2;
    if (methodBlockOffset + 2 <= data.length) {
      final methodCount = byteData.getUint16(methodBlockOffset, Endian.little);
      final selListOffset = methodBlockOffset + 2;
      final codeOffsetBase = selListOffset + methodCount * 2 + 2; // +2 skips zero terminator

      if (codeOffsetBase + methodCount * 2 <= data.length) {
        for (var i = 0; i < methodCount; i++) {
          final selId = byteData.getUint16(selListOffset + i * 2, Endian.little);
          final codeOffset = byteData.getUint16(codeOffsetBase + i * 2, Endian.little);
          methods[selId] = codeOffset;
        }
      }
    }

    // Extract static object name (property 3 is name pointer)
    String? nameStr;
    if (variables.length > 3 && variables[3].toUint16() != 0) {
      final nameOffset = variables[3].toUint16();
      if (nameOffset < data.length) {
        var end = nameOffset;
        while (end < data.length && data[end] != 0) {
          end++;
        }
        nameStr = String.fromCharCodes(data.sublist(nameOffset, end));
      }
    }

    return SciObject(
      pos: SciReg.pointer(segmentId, objectPos),
      variables: variables,
      baseVars: baseVars,
      methods: methods,
      nameString: nameStr,
    );
  }

  void _parseSynonyms(
    ByteData byteData,
    int pos,
    int blockSize,
    List<int> synonyms,
  ) {
    final count = (blockSize - 4) >> 1;
    for (var i = 0; i < count; i++) {
      synonyms.add(byteData.getUint16(pos + 4 + i * 2, Endian.little));
    }
  }

  void _applyRelocations(
    int segmentId,
    List<int> relocations,
    int localsOffset,
    List<SciReg> locals,
    Map<int, SciObject> objects,
  ) {
    for (final reloc in relocations) {
      // 1. Check if reloc falls within locals
      final localIdx = (reloc - localsOffset) >> 1;
      if (localIdx >= 0 && localIdx < locals.length) {
        locals[localIdx] = SciReg.pointer(segmentId, locals[localIdx].offset);
        continue;
      }

      // 2. Check if reloc falls within any object's properties
      for (final obj in objects.values) {
        final propIdx = (reloc - obj.pos.offset) >> 1;
        if (propIdx >= 0 && propIdx < obj.variables.length) {
          obj.variables[propIdx] = SciReg.pointer(segmentId, obj.variables[propIdx].offset);
          break;
        }
      }
    }
  }
}
