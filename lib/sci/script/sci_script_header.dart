// SCI0 script header detection, pure Dart.
//
// Extracted from sci_script_parser.dart so that volume/resource loading
// (volume.dart, sci_adlib_patch.dart, and the corpus-miner CLI) can depend
// on it without transitively importing package:flutter/foundation.dart.

import 'dart:typed_data';

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

/// Detects whether raw script bytes use the early SCI0 script format
/// (a 16-bit locals count at byte 0, followed by script blocks at byte 2).
bool hasOldSci0ScriptHeader(Uint8List data) {
  if (data.length < 4) return false;
  final byteData = ByteData.sublistView(data);
  var offset = 2;
  const maxObjType = 16;
  while (offset + 2 <= data.length) {
    final objType = byteData.getUint16(offset, Endian.little);
    if (objType == SciScriptBlockType.terminator) {
      offset += 2;
      return offset == data.length;
    }
    if (offset + 4 > data.length) return false;
    if (objType > maxObjType) return false;
    final skip = byteData.getUint16(offset + 2, Endian.little);
    if (skip < 4) return false;
    offset += skip;
  }
  return false;
}
