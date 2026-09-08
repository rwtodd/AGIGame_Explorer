// SCI0 Object and Class models.

import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';

/// Flags stored in the `-info-` selector (property variable 2).
class SciObjectInfoFlags {
  static const int clone = 0x0001;
  static const int isClass = 0x8000;
}

/// Represents an instantiated SCI0 Object or Class.
class SciObject {
  /// VM address of this object (`segment:offset`).
  SciReg pos;

  /// Property variables.
  final List<SciReg> variables;

  /// Selector IDs corresponding to each property variable (only populated on classes).
  final List<int> baseVars;

  /// Method dictionary mapping Selector ID to code offset within the owning script.
  final Map<int, int> methods;

  /// Static name string (e.g. "PQ", "Game", "Actor") if resolved.
  String? nameString;

  SciObject({
    required this.pos,
    required List<SciReg> variables,
    List<int>? baseVars,
    Map<int, int>? methods,
    this.nameString,
  })  : variables = List<SciReg>.from(variables),
        baseVars = baseVars != null ? List<int>.from(baseVars) : <int>[],
        methods = methods != null ? Map<int, int>.from(methods) : <int, int>{};

  /// Number of property variables.
  int get varCount => variables.length;

  /// Number of methods directly defined on this object.
  int get methodCount => methods.length;

  // --- Standard SCI0 Property Selectors (Indices 0..3) ---

  /// Selector 0: `species` (Class ID / species number).
  SciReg get species => variables.isNotEmpty ? variables[0] : SciReg.nullReg;
  set species(SciReg val) {
    if (variables.isNotEmpty) variables[0] = val;
  }

  /// Selector 1: `superClass` (Species number of super class, or pointer).
  SciReg get superClass => variables.length > 1 ? variables[1] : SciReg.nullReg;
  set superClass(SciReg val) {
    if (variables.length > 1) variables[1] = val;
  }

  /// Selector 2: `-info-` (Class / clone / visibility flags).
  SciReg get info => variables.length > 2 ? variables[2] : SciReg.nullReg;
  set info(SciReg val) {
    if (variables.length > 2) variables[2] = val;
  }

  /// Selector 3: `-name-` (Pointer to name string in script).
  SciReg get name => variables.length > 3 ? variables[3] : SciReg.nullReg;
  set name(SciReg val) {
    if (variables.length > 3) variables[3] = val;
  }

  /// True if this object is a Class template (`info & 0x8000 != 0`).
  bool get isClass => (info.toUint16() & SciObjectInfoFlags.isClass) != 0;

  /// True if this object is a dynamically cloned instance (`info & 0x0001 != 0`).
  bool get isClone => (info.toUint16() & SciObjectInfoFlags.clone) != 0;

  /// Locates the variable property index corresponding to [selectorId].
  ///
  /// For classes and instances with populated [baseVars], searches [baseVars].
  /// Otherwise, resolves the parent class via [superClass] or [species].
  /// Returns -1 if not found.
  int locateVarSelector(SciSegManager segMan, int selectorId) {
    if (baseVars.isNotEmpty) {
      return baseVars.indexOf(selectorId);
    }
    if (isClass) {
      return -1;
    }
    final classObj = segMan.getObject(superClass) ?? segMan.getObject(species);
    if (classObj != null) {
      return classObj.locateVarSelector(segMan, selectorId);
    }
    return -1;
  }

  /// Checks if this object or any superclass defines a method for [selectorId].
  ///
  /// Returns a tuple of `(owningObject, codeOffset)` or null if not found.
  (SciObject, int)? lookupMethod(SciSegManager segMan, int selectorId) {
    if (!isClone && methods.containsKey(selectorId)) {
      return (this, methods[selectorId]!);
    }
    // Walk superclass hierarchy
    final parent = isClass
        ? segMan.getObject(superClass)
        : (segMan.getObject(superClass) ?? segMan.getObject(species));
    if (parent != null) {
      return parent.lookupMethod(segMan, selectorId);
    }
    return null;
  }

  /// Gets the property value for [selectorId], or [SciReg.nullReg] if not found.
  SciReg getProp(SciSegManager segMan, int selectorId) {
    final idx = locateVarSelector(segMan, selectorId);
    if (idx >= 0 && idx < variables.length) {
      return variables[idx];
    }
    return SciReg.nullReg;
  }

  /// Sets the property value for [selectorId].
  void setProp(SciSegManager segMan, int selectorId, SciReg val) {
    final idx = locateVarSelector(segMan, selectorId);
    if (idx >= 0 && idx < variables.length) {
      variables[idx] = val;
    }
  }

  /// Creates a clone of this object with a new address [clonePos].
  SciObject clone(SciReg clonePos) {
    final clonedVars = List<SciReg>.from(variables);
    if (clonedVars.length > 2) {
      // Mark as clone (0x0001) and remove class flag (0x8000)
      final newInfo = (clonedVars[2].toUint16() | SciObjectInfoFlags.clone) &
          ~SciObjectInfoFlags.isClass;
      clonedVars[2] = SciReg.fromInt(newInfo);
    }
    return SciObject(
      pos: clonePos,
      variables: clonedVars,
      baseVars: baseVars,
      methods: methods,
      nameString: nameString != null ? '$nameString (clone)' : null,
    );
  }

  @override
  String toString() =>
      'SciObject(${nameString ?? "obj"} at $pos, vars: ${variables.length}, methods: ${methods.length}${isClass ? ", CLASS" : ""}${isClone ? ", CLONE" : ""})';
}
