// Memory and Segment Manager for the Sierra SCI PMachine.

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';
import 'package:flutter_agigame/sci/script/sci_script_parser.dart';

/// A doubly-linked list node in the SCI Segment Manager.
class SciNode {
  final SciReg pos;
  SciReg value;
  SciReg key;
  SciReg pred;
  SciReg succ;

  SciNode({
    required this.pos,
    this.value = SciReg.nullReg,
    this.key = SciReg.nullReg,
    this.pred = SciReg.nullReg,
    this.succ = SciReg.nullReg,
  });

  @override
  String toString() => 'SciNode($pos, val: $value, key: $key, pred: $pred, succ: $succ)';
}

/// A doubly-linked list in the SCI Segment Manager.
class SciList {
  final SciReg pos;
  SciReg first;
  SciReg last;
  int count;

  SciList({
    required this.pos,
    this.first = SciReg.nullReg,
    this.last = SciReg.nullReg,
    this.count = 0,
  });

  @override
  String toString() => 'SciList($pos, count: $count, first: $first, last: $last)';
}

/// Memory Segment Manager for the SCI VM.
///
/// Manages loaded scripts, class tables, heap objects, doubly-linked lists,
/// and dynamically allocated nodes/strings.
class SciSegManager {
  static const int listSegmentId = 0x1000;
  static const int nodeSegmentId = 0x1001;
  static const int cloneSegmentId = 0x1002;
  static const int hunkSegmentId = 0x1003;
  static const int globalSegmentId = 0x1004;

  int _nextScriptSegmentId = 1;

  /// Map of script number -> segment ID.
  final Map<int, int> scriptToSegment = {};

  /// Map of segment ID -> instantiated SciScript.
  final Map<int, SciScript> loadedScripts = {};

  /// Mapping from class number (species) to script number (from VOCAB.996).
  final List<int> classScripts = [];

  /// Mapping from class number (species) to instantiated VM address.
  final Map<int, SciReg> classAddresses = {};

  /// Doubly linked lists indexed by list offset.
  final Map<int, SciList> lists = {};
  final _Offset16Pool _listIds = _Offset16Pool();

  /// Doubly linked list nodes indexed by node offset.
  final Map<int, SciNode> nodes = {};
  final _Offset16Pool _nodeIds = _Offset16Pool();

  /// Cloned objects indexed by clone offset.
  final Map<int, SciObject> clones = {};
  final _Offset16Pool _cloneIds = _Offset16Pool();

  /// Dynamic memory buffers (hunks / strings) indexed by offset.
  final Map<int, Uint8List> hunkBuffers = {};
  int _nextHunkOffset = 1;

  /// Global variables array (in SCI0, corresponds to script 0 locals).
  List<SciReg> globals = [];

  /// Active VM execution stack, allowing string and memory operations to access stack variables.
  List<SciReg>? currentStack;

  /// Volume manager for on-demand script loading.
  SciVolumeManager? volumeManager;

  SciSegManager({this.volumeManager});

  /// Resets all loaded scripts, objects, lists, nodes, hunks, and globals.
  void reset() {
    _nextScriptSegmentId = 1;
    scriptToSegment.clear();
    loadedScripts.clear();
    classAddresses.clear();
    lists.clear();
    _listIds.clear();
    nodes.clear();
    _nodeIds.clear();
    clones.clear();
    _cloneIds.clear();
    hunkBuffers.clear();
    _nextHunkOffset = 1;
    globals.clear();
    currentStack = null;
  }

  /// Loads the class-to-script mapping table from `VOCAB.996`.
  void loadClassTable(Uint8List vocab996Bytes) {
    classScripts.clear();
    final totalClasses = vocab996Bytes.length >> 2;
    for (var c = 0; c < totalClasses; c++) {
      final scriptNr = vocab996Bytes[c * 4 + 2] | (vocab996Bytes[c * 4 + 3] << 8);
      classScripts.add(scriptNr);
    }
  }

  /// Allocates a new segment ID for a script.
  int allocateScriptSegment(int scriptNr) {
    if (scriptToSegment.containsKey(scriptNr)) {
      return scriptToSegment[scriptNr]!;
    }
    final segId = _nextScriptSegmentId++;
    scriptToSegment[scriptNr] = segId;
    return segId;
  }

  /// Instantiates a script into the segment manager using the parser.
  SciScript instantiateScript(
    int scriptNr,
    SciVolumeManager volumeMgr, {
    SciScriptParser? parser,
  }) {
    if (scriptToSegment.containsKey(scriptNr)) {
      final seg = scriptToSegment[scriptNr]!;
      if (loadedScripts.containsKey(seg)) {
        return loadedScripts[seg]!;
      }
    }

    final segId = allocateScriptSegment(scriptNr);
    final scriptBytes = volumeMgr.getResource(SciResourceType.script, scriptNr);
    final scriptParser = parser ?? SciScriptParser();
    final script = scriptParser.parse(scriptNr, scriptBytes, segId, this);

    loadedScripts[segId] = script;

    // If this is script 0, its locals are the engine's globals!
    if (scriptNr == 0) {
      globals = script.locals;
    }

    volumeManager ??= volumeMgr;

    // Register any classes defined in this script
    for (final obj in script.objects.values) {
      if (obj.isClass) {
        final species = obj.species.toUint16();
        registerClass(species, obj.pos);
      }
    }

    // Resolve classes and instances
    for (final obj in script.objects.values) {
      if (obj.isClass) {
        if (obj.superClass.isNumber && obj.superClass.toUint16() != 0xFFFF) {
          final supAddr = getClassAddress(obj.superClass.toUint16(), volumeManager: volumeMgr);
          if (!supAddr.isNull) {
            obj.superClass = supAddr;
          }
        }
      } else {
        final speciesNr = obj.species.isNumber ? obj.species.toUint16() : -1;
        if (speciesNr >= 0 && speciesNr != 0xFFFF) {
          final classAddr = getClassAddress(speciesNr, volumeManager: volumeMgr);
          if (!classAddr.isNull) {
            obj.species = classAddr;
            final classObj = getObject(classAddr);
            if (classObj != null) {
              if (obj.baseVars.isEmpty && classObj.baseVars.isNotEmpty) {
                obj.baseVars.addAll(classObj.baseVars);
              }
              while (obj.variables.length < classObj.variables.length) {
                obj.variables.add(classObj.variables[obj.variables.length]);
              }
            }
          }
        }
        if (obj.superClass.isNumber && obj.superClass.toUint16() != 0xFFFF) {
          final supAddr = getClassAddress(obj.superClass.toUint16(), volumeManager: volumeMgr);
          if (!supAddr.isNull) {
            obj.superClass = supAddr;
          }
        }
      }
    }

    return script;
  }

  /// Registers the VM address for a class species.
  void registerClass(int species, SciReg addr) {
    classAddresses[species] = addr;
  }

  /// Gets the address of a class, optionally loading its script via [volumeManager].
  SciReg getClassAddress(int classNr, {SciVolumeManager? volumeManager}) {
    if (classAddresses.containsKey(classNr)) {
      return classAddresses[classNr]!;
    }
    if (classNr < 0 || classNr >= classScripts.length) {
      return SciReg.nullReg;
    }
    final scriptNr = classScripts[classNr];
    if (volumeManager != null) {
      instantiateScript(scriptNr, volumeManager);
      return classAddresses[classNr] ?? SciReg.nullReg;
    }
    return SciReg.nullReg;
  }

  /// Retrieves an object by its VM address [addr] or by class species ID if [addr.isNumber].
  SciObject? getObject(SciReg addr) {
    if (addr.isNull) return null;
    if (addr.segment == cloneSegmentId) {
      return clones[addr.offset];
    }
    if (addr.segment == hunkSegmentId) {
      return clones[addr.offset];
    }
    if (addr.segment == 0) {
      // Species lookup: resolve class object
      final classAddr = classAddresses[addr.offset];
      if (classAddr != null) {
        return getObject(classAddr);
      }
      return null;
    }
    final script = loadedScripts[addr.segment];
    if (script != null) {
      return script.getObject(addr.offset);
    }
    return null;
  }

  /// Alias for [getObject].
  SciObject? lookupObject(SciReg addr) => getObject(addr);

  /// Resolves the human-readable name of an object.
  String getObjectName(SciReg addr) {
    final obj = getObject(addr);
    if (obj == null) return '<unknown ${addr.toString()}>';
    if (obj.nameString != null && obj.nameString!.isNotEmpty) {
      return obj.nameString!;
    }
    return 'obj_${addr.toString()}';
  }

  /// Allocates a new cloned instance of [source].
  SciObject cloneObject(SciObject source) {
    final offset = _cloneIds.alloc(clones.containsKey);
    final clonePos = SciReg.pointer(cloneSegmentId, offset);
    final cloned = source.clone(clonePos);
    if (source.isClass) {
      cloned.superClass = source.pos;
      cloned.species = source.pos;
    } else if (source.isClone) {
      cloned.superClass = source.superClass;
      cloned.species = source.species;
    } else {
      cloned.superClass = source.pos;
      cloned.species = source.species;
    }
    clones[offset] = cloned;
    return cloned;
  }

  /// Frees a cloned object.
  bool disposeClone(SciReg addr) {
    if (addr.segment == cloneSegmentId) {
      final removed = clones.remove(addr.offset) != null;
      if (removed) _cloneIds.release(addr.offset);
      return removed;
    }
    return false;
  }

  // --- Doubly-Linked List Management ---

  SciList? lookupList(SciReg listReg) {
    if (listReg.segment == listSegmentId) {
      return lists[listReg.offset];
    }
    return null;
  }

  List<SciReg> listElements(SciList list) {
    final elements = <SciReg>[];
    var curr = list.first;
    while (!curr.isNull && curr.segment == nodeSegmentId) {
      final node = nodes[curr.offset];
      if (node == null) break;
      if (!node.value.isNull) {
        elements.add(node.value);
      }
      curr = node.succ;
    }
    return elements;
  }

  SciReg newList() {
    final offset = _listIds.alloc(lists.containsKey);
    final pos = SciReg.pointer(listSegmentId, offset);
    final list = SciList(pos: pos);
    lists[offset] = list;
    return pos;
  }

  bool disposeList(SciReg listReg) {
    if (listReg.segment != listSegmentId) return false;
    final list = lists.remove(listReg.offset);
    if (list == null) return false;
    _listIds.release(listReg.offset);

    // Free all nodes in the list
    var curr = list.first;
    while (!curr.isNull && curr.segment == nodeSegmentId) {
      final node = nodes.remove(curr.offset);
      if (node == null) break;
      _nodeIds.release(curr.offset);
      curr = node.succ;
    }
    return true;
  }

  SciReg newNode(SciReg value, [SciReg key = SciReg.nullReg]) {
    final offset = _nodeIds.alloc(nodes.containsKey);
    final pos = SciReg.pointer(nodeSegmentId, offset);
    final node = SciNode(pos: pos, value: value, key: key);
    nodes[offset] = node;
    return pos;
  }

  SciReg firstNode(SciReg listReg) {
    if (listReg.segment != listSegmentId) return SciReg.nullReg;
    return lists[listReg.offset]?.first ?? SciReg.nullReg;
  }

  SciReg lastNode(SciReg listReg) {
    if (listReg.segment != listSegmentId) return SciReg.nullReg;
    return lists[listReg.offset]?.last ?? SciReg.nullReg;
  }

  SciReg nextNode(SciReg nodeReg) {
    if (nodeReg.segment != nodeSegmentId) return SciReg.nullReg;
    return nodes[nodeReg.offset]?.succ ?? SciReg.nullReg;
  }

  SciReg prevNode(SciReg nodeReg) {
    if (nodeReg.segment != nodeSegmentId) return SciReg.nullReg;
    return nodes[nodeReg.offset]?.pred ?? SciReg.nullReg;
  }

  SciReg nodeValue(SciReg nodeReg) {
    if (nodeReg.segment != nodeSegmentId) return SciReg.nullReg;
    return nodes[nodeReg.offset]?.value ?? SciReg.nullReg;
  }

  void addToFront(SciReg listReg, SciReg nodeReg) {
    if (listReg.segment != listSegmentId || nodeReg.segment != nodeSegmentId) return;
    final list = lists[listReg.offset];
    final node = nodes[nodeReg.offset];
    if (list == null || node == null) return;

    node.pred = SciReg.nullReg;
    node.succ = list.first;

    if (!list.first.isNull && nodes.containsKey(list.first.offset)) {
      nodes[list.first.offset]!.pred = nodeReg;
    }
    list.first = nodeReg;
    if (list.last.isNull) {
      list.last = nodeReg;
    }
    list.count++;
  }

  void addToEnd(SciReg listReg, SciReg nodeReg) {
    if (listReg.segment != listSegmentId || nodeReg.segment != nodeSegmentId) return;
    final list = lists[listReg.offset];
    final node = nodes[nodeReg.offset];
    if (list == null || node == null) return;

    node.succ = SciReg.nullReg;
    node.pred = list.last;

    if (!list.last.isNull && nodes.containsKey(list.last.offset)) {
      nodes[list.last.offset]!.succ = nodeReg;
    }
    list.last = nodeReg;
    if (list.first.isNull) {
      list.first = nodeReg;
    }
    list.count++;
  }

  /// Inserts [nodeReg] after [afterReg] (Sierra `AddAfter(list, existing, new)`).
  void addAfter(SciReg listReg, SciReg afterReg, SciReg nodeReg) {
    if (listReg.segment != listSegmentId || nodeReg.segment != nodeSegmentId) return;
    if (afterReg.isNull) {
      addToFront(listReg, nodeReg);
      return;
    }
    final list = lists[listReg.offset];
    final node = nodes[nodeReg.offset];
    final after = nodes[afterReg.offset];
    if (list == null || node == null || after == null) return;

    node.pred = afterReg;
    node.succ = after.succ;

    if (!after.succ.isNull && nodes.containsKey(after.succ.offset)) {
      nodes[after.succ.offset]!.pred = nodeReg;
    } else {
      list.last = nodeReg;
    }
    after.succ = nodeReg;
    list.count++;
  }

  /// Predicate: true when the list has no nodes. Does not mutate the list.
  bool isListEmpty(SciReg listReg) {
    if (listReg.isNull) return true;
    final list = lookupList(listReg);
    return list == null || list.first.isNull;
  }

  void disposeScript(int scriptNr) {
    if (scriptNr == 0) return;
    final seg = scriptToSegment.remove(scriptNr);
    if (seg == null) return;
    loadedScripts.remove(seg);
    classAddresses.removeWhere((_, addr) => addr.segment == seg);
  }

  Uint8List? bytesFor(SciReg ptr) {
    if (!ptr.isPointer) return null;
    if (ptr.segment == hunkSegmentId) {
      if (hunkBuffers.containsKey(ptr.offset)) return hunkBuffers[ptr.offset];
      for (final entry in hunkBuffers.entries) {
        if (ptr.offset >= entry.key && ptr.offset < entry.key + entry.value.length) {
          return entry.value;
        }
      }
      return null;
    }
    return loadedScripts[ptr.segment]?.bytes;
  }

  int byteIndexFor(SciReg ptr) {
    if (ptr.segment == hunkSegmentId) {
      if (hunkBuffers.containsKey(ptr.offset)) return 0;
      for (final entry in hunkBuffers.entries) {
        if (ptr.offset >= entry.key && ptr.offset < entry.key + entry.value.length) {
          return ptr.offset - entry.key;
        }
      }
      return 0;
    }
    return ptr.offset;
  }

  /// Reads a single byte at [ptr] + [byteOffset].
  ///
  /// Supports hunk memory, stack memory ([listSegmentId]), globals, and script resources/locals.
  int? readByte(SciReg ptr, int byteOffset, {List<SciReg>? stack}) {
    if (!ptr.isPointer) return null;
    final effectiveStack = stack ?? currentStack;

    if (ptr.segment == hunkSegmentId) {
      if (hunkBuffers.containsKey(ptr.offset)) {
        final buf = hunkBuffers[ptr.offset]!;
        final i = byteOffset;
        return (i >= 0 && i < buf.length) ? buf[i] : 0;
      }
      for (final entry in hunkBuffers.entries) {
        final base = entry.key;
        final buf = entry.value;
        if (ptr.offset >= base && ptr.offset < base + buf.length) {
          final i = (ptr.offset - base) + byteOffset;
          return (i >= 0 && i < buf.length) ? buf[i] : 0;
        }
      }
      return null;
    }

    if (ptr.segment == listSegmentId && effectiveStack != null) {
      final totalByte = ptr.offset + byteOffset;
      final wordIndex = totalByte >> 1;
      if (wordIndex >= 0 && wordIndex < effectiveStack.length) {
        final word = effectiveStack[wordIndex].toUint16();
        return (totalByte & 1) == 0 ? (word & 0xFF) : ((word >> 8) & 0xFF);
      }
      return 0;
    }

    if (ptr.segment == globalSegmentId ||
        (ptr.segment == 1 && !loadedScripts.containsKey(1)) ||
        (scriptToSegment.containsKey(0) && ptr.segment == scriptToSegment[0] && ptr.offset >= (loadedScripts[ptr.segment]?.bytes.length ?? 0))) {
      final totalByte = ptr.offset + byteOffset;
      final wordIndex = totalByte >> 1;
      if (wordIndex >= 0 && wordIndex < globals.length) {
        final word = globals[wordIndex].toUint16();
        return (totalByte & 1) == 0 ? (word & 0xFF) : ((word >> 8) & 0xFF);
      }
    }

    final script = loadedScripts[ptr.segment];
    if (script != null) {
      final totalByte = ptr.offset + byteOffset;
      if (totalByte >= 0 && totalByte < script.bytes.length) {
        return script.bytes[totalByte];
      }
      final wordIndex = totalByte >> 1;
      if (wordIndex >= 0 && wordIndex < script.locals.length) {
        final word = script.locals[wordIndex].toUint16();
        return (totalByte & 1) == 0 ? (word & 0xFF) : ((word >> 8) & 0xFF);
      }
    }

    return null;
  }

  /// Writes a single byte at [ptr] + [byteOffset].
  void writeByte(SciReg ptr, int byteOffset, int byteVal, {List<SciReg>? stack}) {
    if (!ptr.isPointer) return;
    final effectiveStack = stack ?? currentStack;
    final b = byteVal & 0xFF;

    if (ptr.segment == hunkSegmentId) {
      if (hunkBuffers.containsKey(ptr.offset)) {
        final buf = hunkBuffers[ptr.offset]!;
        final i = byteOffset;
        if (i >= 0 && i < buf.length) {
          buf[i] = b;
        }
        return;
      }
      for (final entry in hunkBuffers.entries) {
        final base = entry.key;
        final buf = entry.value;
        if (ptr.offset >= base && ptr.offset < base + buf.length) {
          final i = (ptr.offset - base) + byteOffset;
          if (i >= 0 && i < buf.length) {
            buf[i] = b;
          }
          return;
        }
      }
      return;
    }

    if (ptr.segment == listSegmentId && effectiveStack != null) {
      final totalByte = ptr.offset + byteOffset;
      final wordIndex = totalByte >> 1;
      while (effectiveStack.length <= wordIndex) {
        effectiveStack.add(SciReg.nullReg);
      }
      final word = effectiveStack[wordIndex].toUint16();
      final newWord = (totalByte & 1) == 0
          ? ((word & 0xFF00) | b)
          : ((word & 0x00FF) | (b << 8));
      effectiveStack[wordIndex] = SciReg.fromInt(newWord);
      return;
    }

    if (ptr.segment == globalSegmentId ||
        (ptr.segment == 1 && !loadedScripts.containsKey(1)) ||
        (scriptToSegment.containsKey(0) && ptr.segment == scriptToSegment[0] && ptr.offset >= (loadedScripts[ptr.segment]?.bytes.length ?? 0))) {
      final totalByte = ptr.offset + byteOffset;
      final wordIndex = totalByte >> 1;
      while (globals.length <= wordIndex) {
        globals.add(SciReg.nullReg);
      }
      final word = globals[wordIndex].toUint16();
      final newWord = (totalByte & 1) == 0
          ? ((word & 0xFF00) | b)
          : ((word & 0x00FF) | (b << 8));
      globals[wordIndex] = SciReg.fromInt(newWord);
      return;
    }

    final script = loadedScripts[ptr.segment];
    if (script != null) {
      final totalByte = ptr.offset + byteOffset;
      if (totalByte >= 0 && totalByte < script.bytes.length) {
        script.bytes[totalByte] = b;
        return;
      }
      final wordIndex = totalByte >> 1;
      while (script.locals.length <= wordIndex) {
        script.locals.add(SciReg.nullReg);
      }
      final word = script.locals[wordIndex].toUint16();
      final newWord = (totalByte & 1) == 0
          ? ((word & 0xFF00) | b)
          : ((word & 0x00FF) | (b << 8));
      script.locals[wordIndex] = SciReg.fromInt(newWord);
      return;
    }
  }

  int strlen(SciReg ptr, {List<SciReg>? stack}) {
    if (!ptr.isPointer) return 0;
    var len = 0;
    while (true) {
      final b = readByte(ptr, len, stack: stack);
      if (b == null || b == 0) break;
      len++;
    }
    return len;
  }

  int strcmp(SciReg a, SciReg b, [int? maxLen, List<SciReg>? stack]) {
    var i = 0;
    while (true) {
      if (maxLen != null && i >= maxLen) return 0;
      final ca = readByte(a, i, stack: stack) ?? 0;
      final cb = readByte(b, i, stack: stack) ?? 0;
      if (ca != cb) return ca < cb ? -1 : 1;
      if (ca == 0) return 0;
      i++;
    }
  }

  bool strcpy(SciReg dest, SciReg src, {int? maxLen, bool rawCopy = false, List<SciReg>? stack}) {
    if (!dest.isPointer || !src.isPointer) return false;
    var i = 0;
    while (true) {
      if (maxLen != null && i >= maxLen) break;
      final b = readByte(src, i, stack: stack) ?? 0;
      if (!rawCopy && b == 0) {
        writeByte(dest, i, 0, stack: stack);
        break;
      }
      writeByte(dest, i, b, stack: stack);
      i++;
    }
    if (!rawCopy && (maxLen == null || i < maxLen)) {
      writeByte(dest, i, 0, stack: stack);
    }
    return true;
  }

  int strAt(SciReg ptr, int index, [int? writeValue, List<SciReg>? stack]) {
    final old = readByte(ptr, index, stack: stack) ?? 0;
    if (writeValue != null) {
      writeByte(ptr, index, writeValue, stack: stack);
    }
    return old;
  }

  /// Reads a null-terminated ASCII/Latin-1 string starting at [ptr].
  String getString(SciReg ptr, {List<SciReg>? stack}) {
    if (!ptr.isPointer) return '';
    final codeUnits = <int>[];
    var offset = 0;
    while (true) {
      final b = readByte(ptr, offset, stack: stack);
      if (b == null || b == 0) break;
      codeUnits.add(b);
      offset++;
    }
    return String.fromCharCodes(codeUnits);
  }

  /// Writes [text] as null-terminated ASCII string into [ptr].
  void writeString(SciReg ptr, String text, {List<SciReg>? stack, int? maxLen}) {
    if (!ptr.isPointer) return;
    final units = text.codeUnits;
    final limit = maxLen != null ? min(maxLen - 1, units.length) : units.length;
    for (var i = 0; i < limit; i++) {
      writeByte(ptr, i, units[i], stack: stack);
    }
    writeByte(ptr, limit, 0, stack: stack);
  }

  /// Allocates a new null-terminated string buffer in hunk memory and returns its pointer.
  SciReg allocString(String text) {
    final codeUnits = text.codeUnits;
    final reg = allocHunk(codeUnits.length + 1);
    final buf = hunkBuffers[reg.offset]!;
    for (int i = 0; i < codeUnits.length; i++) {
      buf[i] = codeUnits[i];
    }
    buf[codeUnits.length] = 0;
    return reg;
  }

  SciReg findKey(SciReg listReg, SciReg key) {
    if (listReg.segment != listSegmentId) return SciReg.nullReg;
    final list = lists[listReg.offset];
    if (list == null) return SciReg.nullReg;

    var curr = list.first;
    while (!curr.isNull && curr.segment == nodeSegmentId) {
      final node = nodes[curr.offset];
      if (node == null) break;
      if (node.key == key) return curr;
      curr = node.succ;
    }
    return SciReg.nullReg;
  }

  bool deleteKey(SciReg listReg, SciReg key) {
    final nodeReg = findKey(listReg, key);
    if (nodeReg.isNull) return false;
    return deleteNode(listReg, nodeReg);
  }

  bool deleteNode(SciReg listReg, SciReg nodeReg) {
    if (listReg.segment != listSegmentId || nodeReg.segment != nodeSegmentId) return false;
    final list = lists[listReg.offset];
    final node = nodes[nodeReg.offset];
    if (list == null || node == null) return false;

    if (!node.pred.isNull && nodes.containsKey(node.pred.offset)) {
      nodes[node.pred.offset]!.succ = node.succ;
    } else {
      list.first = node.succ;
    }

    if (!node.succ.isNull && nodes.containsKey(node.succ.offset)) {
      nodes[node.succ.offset]!.pred = node.pred;
    } else {
      list.last = node.pred;
    }

    nodes.remove(nodeReg.offset);
    _nodeIds.release(nodeReg.offset);
    list.count--;
    return true;
  }

  // --- Dynamic Memory Allocation (Hunk) ---

  SciReg allocHunk(int bytes) {
    final offset = _nextHunkOffset;
    _nextHunkOffset += bytes;
    hunkBuffers[offset] = Uint8List(bytes);
    return SciReg.pointer(hunkSegmentId, offset);
  }

  Uint8List? getHunk(SciReg addr) {
    if (addr.segment != hunkSegmentId) return null;
    return hunkBuffers[addr.offset];
  }

  /// Writes a 16-bit word value at [ptr] + [wordOffset] (words).
  ///
  /// Supports globals, script locals, VM stack/temps/params, and hunk memory.
  void writeWord(
    SciReg ptr,
    int wordOffset,
    SciReg value, {
    List<SciReg>? stack,
  }) {
    final wordIndex = (ptr.offset >> 1) + wordOffset;
    final effectiveStack = stack ?? currentStack;

    if (ptr.segment == globalSegmentId ||
        (ptr.segment == 1 && !loadedScripts.containsKey(1)) ||
        (scriptToSegment.containsKey(0) && ptr.segment == scriptToSegment[0] && ptr.offset >= (loadedScripts[ptr.segment]?.bytes.length ?? 0))) {
      while (globals.length <= wordIndex) {
        globals.add(SciReg.nullReg);
      }
      globals[wordIndex] = value;
      return;
    }

    if (ptr.segment == listSegmentId && effectiveStack != null) {
      while (effectiveStack.length <= wordIndex) {
        effectiveStack.add(SciReg.nullReg);
      }
      effectiveStack[wordIndex] = value;
      return;
    }

    final script = loadedScripts[ptr.segment];
    if (script != null) {
      final byteOffset = ptr.offset + wordOffset * 2;
      if (byteOffset + 1 < script.bytes.length) {
        script.bytes[byteOffset] = value.offset & 0xFF;
        script.bytes[byteOffset + 1] = (value.offset >> 8) & 0xFF;
        return;
      }
      while (script.locals.length <= wordIndex) {
        script.locals.add(SciReg.nullReg);
      }
      script.locals[wordIndex] = value;
      return;
    }

    if (ptr.segment == hunkSegmentId) {
      Uint8List? buf = hunkBuffers[ptr.offset];
      var base = ptr.offset;
      if (buf == null) {
        for (final entry in hunkBuffers.entries) {
          if (ptr.offset >= entry.key && ptr.offset < entry.key + entry.value.length) {
            buf = entry.value;
            base = entry.key;
            break;
          }
        }
      }
      if (buf != null) {
        final byteOffset = (ptr.offset - base) + wordOffset * 2;
        if (byteOffset + 1 < buf.length) {
          buf[byteOffset] = value.offset & 0xFF;
          buf[byteOffset + 1] = (value.offset >> 8) & 0xFF;
        }
      }
      return;
    }
  }

  /// Reads a 16-bit word value from [ptr] + [wordOffset] (words).
  SciReg readWord(
    SciReg ptr,
    int wordOffset, {
    List<SciReg>? stack,
  }) {
    final wordIndex = (ptr.offset >> 1) + wordOffset;
    final effectiveStack = stack ?? currentStack;

    if (ptr.segment == globalSegmentId ||
        (ptr.segment == 1 && !loadedScripts.containsKey(1)) ||
        (scriptToSegment.containsKey(0) && ptr.segment == scriptToSegment[0] && ptr.offset >= (loadedScripts[ptr.segment]?.bytes.length ?? 0))) {
      if (wordIndex >= 0 && wordIndex < globals.length) {
        return globals[wordIndex];
      }
      return SciReg.nullReg;
    }

    if (ptr.segment == listSegmentId && effectiveStack != null) {
      if (wordIndex >= 0 && wordIndex < effectiveStack.length) {
        return effectiveStack[wordIndex];
      }
      return SciReg.nullReg;
    }

    final script = loadedScripts[ptr.segment];
    if (script != null) {
      final byteOffset = ptr.offset + wordOffset * 2;
      if (byteOffset + 1 < script.bytes.length) {
        final lo = script.bytes[byteOffset];
        final hi = script.bytes[byteOffset + 1];
        return SciReg.fromInt(lo | (hi << 8));
      }
      if (wordIndex >= 0 && wordIndex < script.locals.length) {
        return script.locals[wordIndex];
      }
      return SciReg.nullReg;
    }

    if (ptr.segment == hunkSegmentId) {
      Uint8List? buf = hunkBuffers[ptr.offset];
      var base = ptr.offset;
      if (buf == null) {
        for (final entry in hunkBuffers.entries) {
          if (ptr.offset >= entry.key && ptr.offset < entry.key + entry.value.length) {
            buf = entry.value;
            base = entry.key;
            break;
          }
        }
      }
      if (buf != null) {
        final byteOffset = (ptr.offset - base) + wordOffset * 2;
        if (byteOffset + 1 < buf.length) {
          final lo = buf[byteOffset];
          final hi = buf[byteOffset + 1];
          return SciReg.fromInt(lo | (hi << 8));
        }
      }
      return SciReg.nullReg;
    }

    return SciReg.nullReg;
  }
}

/// SCI pointers only have a 16-bit offset. Recycle IDs so `Event new:` /
/// `dispose:` (and lists/nodes) do not wrap and leak after 65535 allocations.
class _Offset16Pool {
  static const int _max = 0xFFFF;
  int _next = 1;
  final List<int> _free = [];

  int alloc(bool Function(int offset) inUse) {
    while (_free.isNotEmpty) {
      final o = _free.removeLast();
      if (o > 0 && o <= _max && !inUse(o)) return o;
    }
    for (var n = 0; n < _max; n++) {
      if (_next > _max) _next = 1;
      final o = _next++;
      if (!inUse(o)) return o;
    }
    return 1;
  }

  void release(int offset) {
    if (offset > 0 && offset <= _max) _free.add(offset);
  }

  void clear() {
    _next = 1;
    _free.clear();
  }
}
