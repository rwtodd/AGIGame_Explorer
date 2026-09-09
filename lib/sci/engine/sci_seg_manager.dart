// Memory and Segment Manager for the Sierra SCI PMachine.

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

  /// Volume manager for on-demand script loading.
  SciVolumeManager? volumeManager;

  SciSegManager({this.volumeManager});

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

    if (addr.isNumber) {
      // Immediate number refers to class species ID
      final classNr = addr.toUint16();
      final classAddr = getClassAddress(classNr, volumeManager: volumeManager);
      if (!classAddr.isNull && classAddr != addr) {
        return getObject(classAddr);
      }
      return null;
    }

    if (addr.segment == cloneSegmentId) {
      return clones[addr.offset];
    }

    final script = loadedScripts[addr.segment];
    if (script != null) {
      return script.getObject(addr.offset);
    }

    return null;
  }

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
    if (ptr.segment == hunkSegmentId) return hunkBuffers[ptr.offset];
    return loadedScripts[ptr.segment]?.bytes;
  }

  int byteIndexFor(SciReg ptr) => ptr.segment == hunkSegmentId ? 0 : ptr.offset;

  int strlen(SciReg ptr) {
    final bytes = bytesFor(ptr);
    if (bytes == null) return 0;
    var i = byteIndexFor(ptr);
    var n = 0;
    while (i < bytes.length && bytes[i] != 0) {
      n++;
      i++;
    }
    return n;
  }

  int strcmp(SciReg a, SciReg b, [int? maxLen]) {
    final ba = bytesFor(a);
    final bb = bytesFor(b);
    if (ba == null || bb == null) return 1;
    var ia = byteIndexFor(a);
    var ib = byteIndexFor(b);
    var n = 0;
    while (true) {
      if (maxLen != null && n >= maxLen) return 0;
      final ca = ia < ba.length ? ba[ia] : 0;
      final cb = ib < bb.length ? bb[ib] : 0;
      if (ca != cb) return ca < cb ? -1 : 1;
      if (ca == 0) return 0;
      ia++;
      ib++;
      n++;
    }
  }

  bool strcpy(SciReg dest, SciReg src, {int? maxLen, bool rawCopy = false}) {
    final db = bytesFor(dest);
    final sb = bytesFor(src);
    if (db == null || sb == null) return false;
    var di = byteIndexFor(dest);
    var si = byteIndexFor(src);
    if (rawCopy && maxLen != null) {
      final n = maxLen < (db.length - di) ? maxLen : (db.length - di);
      for (var i = 0; i < n && si < sb.length; i++) {
        db[di++] = sb[si++];
      }
      return true;
    }
    final limit = maxLen ?? (db.length - di);
    var copied = 0;
    while (copied < limit && di < db.length && si < sb.length && sb[si] != 0) {
      db[di++] = sb[si++];
      copied++;
    }
    if (di < db.length && (maxLen == null || copied < limit)) {
      db[di] = 0;
    }
    return true;
  }

  int strAt(SciReg ptr, int index, [int? writeValue]) {
    final bytes = bytesFor(ptr);
    if (bytes == null) return 0;
    final i = byteIndexFor(ptr) + index;
    if (i < 0 || i >= bytes.length) return 0;
    final old = bytes[i];
    if (writeValue != null) {
      bytes[i] = writeValue & 0xFF;
    }
    return old;
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
}
