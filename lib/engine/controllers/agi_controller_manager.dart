import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';

/// Represents a single key-to-controller mapping registered via `set.key`.
class ControllerKeyBinding {
  final int scancode;
  final int ascii;
  final int controllerCode;

  const ControllerKeyBinding({
    required this.scancode,
    required this.ascii,
    required this.controllerCode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControllerKeyBinding &&
          runtimeType == other.runtimeType &&
          scancode == other.scancode &&
          ascii == other.ascii &&
          controllerCode == other.controllerCode;

  @override
  int get hashCode => Object.hash(scancode, ascii, controllerCode);

  @override
  String toString() =>
      'ControllerKeyBinding(scan: 0x${scancode.toRadixString(16)}, ascii: 0x${ascii.toRadixString(16)} -> ctl: $controllerCode)';
}

/// Manages keyboard shortcut and function key mappings to AGI controllers (0..49).
///
/// Sierra AGI scripts configure controllers dynamically using `set.key(scancode, ascii, ctl)`.
/// When a key press matching a registered mapping occurs, the corresponding controller flag
/// in [AgiMemory.controllers] is raised (`true`), allowing `controller(c)` test opcodes to execute.
class AgiControllerManager {
  final List<ControllerKeyBinding> _bindings = [];

  /// Returns an unmodifiable list of all registered key bindings.
  List<ControllerKeyBinding> get bindings => List.unmodifiable(_bindings);

  /// Registers or updates a key mapping to [controllerCode] for a given [scancode] and/or [ascii].
  ///
  /// If a mapping for the exact (scancode, ascii) pair already exists, it is updated.
  void setKey(int scancode, int ascii, int controllerCode) {
    if (scancode == 0 && ascii == 0) {
      return;
    }

    _bindings.removeWhere((b) => b.scancode == scancode && b.ascii == ascii);
    _bindings.add(ControllerKeyBinding(
      scancode: scancode,
      ascii: ascii,
      controllerCode: controllerCode,
    ));
  }

  /// Finds the controller code associated with [scancode] and [ascii], if any.
  ///
  /// Lookup precedence:
  /// 1. Exact match on both [scancode] and [ascii] (when both non-zero).
  /// 2. Extended key match: [scancode] != 0 and [ascii] == 0 (F1..F10, Alt keys).
  /// 3. ASCII match: [ascii] != 0 and [scancode] == 0 (TAB, ESC, Ctrl keys).
  int? getController(int scancode, int ascii) {
    if (_bindings.isEmpty) return null;

    // 1. Exact match (both non-zero)
    if (scancode != 0 && ascii != 0) {
      for (final b in _bindings) {
        if (b.scancode == scancode && b.ascii == ascii) {
          return b.controllerCode;
        }
      }
    }

    // 2. Extended key match (e.g. F-keys, Alt keys where ascii is 0)
    // ONLY matches if the incoming keystroke also has ascii == 0
    if (scancode != 0 && ascii == 0) {
      for (final b in _bindings) {
        if (b.scancode == scancode && b.ascii == 0) {
          return b.controllerCode;
        }
      }
    }

    // 3. ASCII match (e.g. TAB, ESC, Ctrl keys where scancode is 0 or any)
    if (ascii != 0) {
      for (final b in _bindings) {
        if (b.ascii == ascii && b.scancode == 0) {
          return b.controllerCode;
        }
      }
    }

    return null;
  }

  /// Triggers a controller by [scancode] and [ascii] on [memory].
  ///
  /// Returns `true` if a controller mapping was found and triggered.
  bool triggerKey(int scancode, int ascii, AgiMemory memory) {
    final ctl = getController(scancode, ascii);
    if (ctl != null) {
      memory.setController(ctl, true);
      return true;
    }
    return false;
  }

  /// Directly triggers a controller flag by [controllerCode].
  void triggerController(int controllerCode, AgiMemory memory) {
    memory.setController(controllerCode, true);
  }

  /// Translates a Flutter [KeyEvent] and triggers any registered controller on [memory].
  ///
  /// Returns `true` if a controller was triggered.
  bool handleKeyEvent(KeyEvent event, AgiMemory memory) {
    final (scancode, ascii) = mapKeyEvent(event);
    if (scancode == 0 && ascii == 0) return false;
    return triggerKey(scancode, ascii, memory);
  }

  /// Clears all key bindings.
  void clear() {
    _bindings.clear();
  }

  /// Resets bindings.
  void reset() {
    _bindings.clear();
  }

  /// Configures standard default Sierra AGI controller bindings.
  ///
  /// Standard bindings:
  /// - F1 (0x3B, 0) -> Controller 1 (Help)
  /// - F2 (0x3C, 0) -> Controller 2 (Sound Toggle)
  /// - F3 (0x3D, 0) -> Controller 3 (Retype Last Command)
  /// - F5 (0x3F, 0) -> Controller 5 (Save Game)
  /// - F7 (0x41, 0) -> Controller 7 (Restore Game)
  /// - F9 (0x43, 0) -> Controller 9 (Restart Game)
  /// - TAB (0x0F, 9) / F10 (0x44, 0) -> Controller 10 (Inventory / Status)
  /// - ESC (0x01, 27) -> Controller 20 (Menu Bar)
  void loadStandardSierraBindings() {
    setKey(0x3B, 0, 1);  // F1: Help
    setKey(0x3C, 0, 2);  // F2: Sound Toggle
    setKey(0x3D, 0, 3);  // F3: Retype
    setKey(0x3F, 0, 5);  // F5: Save
    setKey(0x41, 0, 7);  // F7: Restore
    setKey(0x43, 0, 9);  // F9: Restart
    setKey(0x0F, 9, 10); // TAB: Status / Inventory
    setKey(0x44, 0, 10); // F10: Status / Inventory
    setKey(0x01, 27, 20); // ESC: Menu
  }

  /// Maps a Flutter [KeyEvent] to IBM PC (scancode, ascii) pair.
  static (int scancode, int ascii) mapKeyEvent(KeyEvent event) {
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    return mapLogicalKey(
      event.logicalKey,
      isControl: isCtrl,
      isAlt: isAlt,
      isShift: isShift,
      character: event.character,
    );
  }

  /// Maps a [LogicalKeyboardKey] with modifier flags to IBM PC (scancode, ascii) pair.
  static (int scancode, int ascii) mapLogicalKey(
    LogicalKeyboardKey key, {
    bool isControl = false,
    bool isAlt = false,
    bool isShift = false,
    String? character,
  }) {
    // 1. Function Keys F1..F10 (IBM PC Scan Codes 0x3B..0x44, ASCII 0)
    if (key == LogicalKeyboardKey.f1) return (0x3B, 0);
    if (key == LogicalKeyboardKey.f2) return (0x3C, 0);
    if (key == LogicalKeyboardKey.f3) return (0x3D, 0);
    if (key == LogicalKeyboardKey.f4) return (0x3E, 0);
    if (key == LogicalKeyboardKey.f5) return (0x3F, 0);
    if (key == LogicalKeyboardKey.f6) return (0x40, 0);
    if (key == LogicalKeyboardKey.f7) return (0x41, 0);
    if (key == LogicalKeyboardKey.f8) return (0x42, 0);
    if (key == LogicalKeyboardKey.f9) return (0x43, 0);
    if (key == LogicalKeyboardKey.f10) return (0x44, 0);

    // 2. Control Key Combinations (Ctrl+A..Ctrl+Z -> ASCII 1..26)
    if (isControl && !isAlt) {
      if (key == LogicalKeyboardKey.keyA) return (0x1E, 1);
      if (key == LogicalKeyboardKey.keyB) return (0x30, 2);
      if (key == LogicalKeyboardKey.keyC) return (0x2E, 3);
      if (key == LogicalKeyboardKey.keyD) return (0x20, 4);
      if (key == LogicalKeyboardKey.keyE) return (0x12, 5);
      if (key == LogicalKeyboardKey.keyF) return (0x21, 6);
      if (key == LogicalKeyboardKey.keyG) return (0x22, 7);
      if (key == LogicalKeyboardKey.keyH) return (0x23, 8);
      if (key == LogicalKeyboardKey.keyI) return (0x17, 9);
      if (key == LogicalKeyboardKey.keyJ) return (0x24, 10);
      if (key == LogicalKeyboardKey.keyK) return (0x25, 11);
      if (key == LogicalKeyboardKey.keyL) return (0x26, 12);
      if (key == LogicalKeyboardKey.keyM) return (0x32, 13);
      if (key == LogicalKeyboardKey.keyN) return (0x31, 14);
      if (key == LogicalKeyboardKey.keyO) return (0x18, 15);
      if (key == LogicalKeyboardKey.keyP) return (0x19, 16);
      if (key == LogicalKeyboardKey.keyQ) return (0x10, 17);
      if (key == LogicalKeyboardKey.keyR) return (0x13, 18);
      if (key == LogicalKeyboardKey.keyS) return (0x1F, 19);
      if (key == LogicalKeyboardKey.keyT) return (0x14, 20);
      if (key == LogicalKeyboardKey.keyU) return (0x16, 21);
      if (key == LogicalKeyboardKey.keyV) return (0x2F, 22);
      if (key == LogicalKeyboardKey.keyW) return (0x11, 23);
      if (key == LogicalKeyboardKey.keyX) return (0x2D, 24);
      if (key == LogicalKeyboardKey.keyY) return (0x15, 25);
      if (key == LogicalKeyboardKey.keyZ) return (0x2C, 26);
    }

    // 3. Alt Key Combinations (Alt+A..Alt+Z -> Scan code, ASCII 0)
    if (isAlt && !isControl) {
      if (key == LogicalKeyboardKey.keyA) return (0x1E, 0);
      if (key == LogicalKeyboardKey.keyB) return (0x30, 0);
      if (key == LogicalKeyboardKey.keyC) return (0x2E, 0);
      if (key == LogicalKeyboardKey.keyD) return (0x20, 0);
      if (key == LogicalKeyboardKey.keyE) return (0x12, 0);
      if (key == LogicalKeyboardKey.keyF) return (0x21, 0);
      if (key == LogicalKeyboardKey.keyG) return (0x22, 0);
      if (key == LogicalKeyboardKey.keyH) return (0x23, 0);
      if (key == LogicalKeyboardKey.keyI) return (0x17, 0);
      if (key == LogicalKeyboardKey.keyJ) return (0x24, 0);
      if (key == LogicalKeyboardKey.keyK) return (0x25, 0);
      if (key == LogicalKeyboardKey.keyL) return (0x26, 0);
      if (key == LogicalKeyboardKey.keyM) return (0x32, 0);
      if (key == LogicalKeyboardKey.keyN) return (0x31, 0);
      if (key == LogicalKeyboardKey.keyO) return (0x18, 0);
      if (key == LogicalKeyboardKey.keyP) return (0x19, 0);
      if (key == LogicalKeyboardKey.keyQ) return (0x10, 0);
      if (key == LogicalKeyboardKey.keyR) return (0x13, 0);
      if (key == LogicalKeyboardKey.keyS) return (0x1F, 0);
      if (key == LogicalKeyboardKey.keyT) return (0x14, 0);
      if (key == LogicalKeyboardKey.keyU) return (0x16, 0);
      if (key == LogicalKeyboardKey.keyV) return (0x2F, 0);
      if (key == LogicalKeyboardKey.keyW) return (0x11, 0);
      if (key == LogicalKeyboardKey.keyX) return (0x2D, 0);
      if (key == LogicalKeyboardKey.keyY) return (0x15, 0);
      if (key == LogicalKeyboardKey.keyZ) return (0x2C, 0);
      if (key == LogicalKeyboardKey.digit1) return (0x78, 0);
      if (key == LogicalKeyboardKey.digit2) return (0x79, 0);
      if (key == LogicalKeyboardKey.digit3) return (0x7A, 0);
      if (key == LogicalKeyboardKey.digit4) return (0x7B, 0);
      if (key == LogicalKeyboardKey.digit5) return (0x7C, 0);
      if (key == LogicalKeyboardKey.digit6) return (0x7D, 0);
      if (key == LogicalKeyboardKey.digit7) return (0x7E, 0);
      if (key == LogicalKeyboardKey.digit8) return (0x7F, 0);
      if (key == LogicalKeyboardKey.digit9) return (0x80, 0);
      if (key == LogicalKeyboardKey.digit0) return (0x81, 0);
    }

    // 4. Special Control Keys
    if (key == LogicalKeyboardKey.tab) return (0x0F, 9);
    if (key == LogicalKeyboardKey.escape) return (0x01, 27);
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      return (0x1C, 13);
    }
    if (key == LogicalKeyboardKey.backspace) return (0x0E, 8);
    if (key == LogicalKeyboardKey.space) return (0x39, 32);

    // 5. Standard Character ASCII
    if (character != null && character.isNotEmpty) {
      final code = character.codeUnitAt(0);
      return (0, code);
    }

    return (0, 0);
  }
}
