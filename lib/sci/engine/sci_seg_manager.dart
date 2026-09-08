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
  int _nextListOffset = 1;

  /// Doubly linked list nodes indexed by node offset.
  final Map<int, SciNode> nodes = {};
  int _nextNodeOffset = 1;

  /// Cloned objects indexed by clone offset.
  final Map<int, SciObject> clones = {};
  int _nextCloneOffset = 1;

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

    // Register any classes defined in this script
    for (final obj in script.objects.values) {
      if (obj.isClass) {
        final species = obj.species.toUint16();
        registerClass(species, obj.pos);
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
    final offset = _nextCloneOffset++;
    final clonePos = SciReg.pointer(cloneSegmentId, offset);
    final cloned = source.clone(clonePos);
    clones[offset] = cloned;
    return cloned;
  }

  /// Frees a cloned object.
  bool disposeClone(SciReg addr) {
    if (addr.segment == cloneSegmentId) {
      return clones.remove(addr.offset) != null;
    }
    return false;
  }

  // --- Doubly-Linked List Management ---

  SciReg newList() {
    final offset = _nextListOffset++;
    final pos = SciReg.pointer(listSegmentId, offset);
    final list = SciList(pos: pos);
    lists[offset] = list;
    return pos;
  }

  bool disposeList(SciReg listReg) {
    if (listReg.segment != listSegmentId) return false;
    final list = lists.remove(listReg.offset);
    if (list == null) return false;

    // Free all nodes in the list
    var curr = list.first;
    while (!curr.isNull && curr.segment == nodeSegmentId) {
      final node = nodes.remove(curr.offset);
      if (node == null) break;
      curr = node.succ;
    }
    return true;
  }

  SciReg newNode(SciReg value, [SciReg key = SciReg.nullReg]) {
    final offset = _nextNodeOffset++;
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

  void addAfter(SciReg listReg, SciReg nodeReg, SciReg afterReg) {
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

  void emptyList(SciReg listReg) {
    if (listReg.segment != listSegmentId) return;
    final list = lists[listReg.offset];
    if (list == null) return;

    var curr = list.first;
    while (!curr.isNull && curr.segment == nodeSegmentId) {
      final node = nodes.remove(curr.offset);
      if (node == null) break;
      curr = node.succ;
    }
    list.first = SciReg.nullReg;
    list.last = SciReg.nullReg;
    list.count = 0;
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
