import 'dart:typed_data';

/// Represents the runtime memory and state registers for the Sierra AGI interpreter:
/// - 256 8-bit variables (v0 - v255)
/// - 256 boolean flags (f0 - f255)
/// - 24 string variables (s0 - s23)
/// - 50 controller / key action triggers (c0 - c49)
/// - Inventory item room locations
/// - Symbol naming aliases & default AGI register descriptions
class AgiMemory {
  /// 256 8-bit unsigned integer variables (v0 - v255).
  final Uint8List variables = Uint8List(256);

  /// 256 boolean flags (f0 - f255).
  final List<bool> flags = List<bool>.filled(256, false);

  /// 24 string variables (s0 - s23).
  final List<String> strings = List<String>.filled(24, '');

  /// 50 controller triggers (c0 - c49).
  final List<bool> controllers = List<bool>.filled(50, false);

  /// Current room locations for inventory items (0..n).
  final Map<int, int> itemRooms = {};

  /// Custom aliases for variable symbols (e.g. from community .var files).
  final Map<int, String> customVarNames = {};

  /// Custom aliases for flag symbols (e.g. from community .flg files).
  final Map<int, String> customFlagNames = {};

  /// Debug pins: restored after every engine tick. LOGIC may change the
  /// live value during a scan; [applyPins] writes these back afterwards.
  final Map<int, bool> pinnedFlags = {};
  final Map<int, int> pinnedVars = {};

  /// Extra flag/var indices to keep visible in the inspector (including zeros).
  final Set<int> watchedFlags = {};
  final Set<int> watchedVars = {};

  /// Instruction pointers where scan execution begins per logic script number
  /// (default 0, altered by set.scan.start and reset.scan.start).
  final Map<int, int> scanStarts = {};

  /// Instruction pointer where Logic 0 scan execution begins (default 0, altered by set.scan.start).
  int get scanStartIp => getScanStart(0);
  set scanStartIp(int value) => setScanStart(0, value);

  /// Gets the scan start IP for [scriptNumber] (default 0).
  int getScanStart(int scriptNumber) => scanStarts[scriptNumber] ?? 0;

  /// Sets the scan start IP for [scriptNumber].
  void setScanStart(int scriptNumber, int ip) {
    scanStarts[scriptNumber] = ip;
  }

  /// Resets the scan start IP for [scriptNumber] to 0.
  void resetScanStart(int scriptNumber) {
    scanStarts.remove(scriptNumber);
  }

  /// Clears scan start offsets for all non-root logics upon entering a new room.
  void clearNonZeroScanStarts() {
    scanStarts.removeWhere((k, v) => k != 0);
  }

  AgiMemory() {
    reset();
  }

  /// Resets memory state to initial interpreter defaults.
  ///
  /// Debug pins and watches persist: they are a debugger overlay, not game
  /// state, so [restartGame] / [initializeGame] keep them. Live values are
  /// not rewritten here; [applyPins] restores them at the end of each tick.
  void reset() {
    variables.fillRange(0, 256, 0);
    flags.fillRange(0, 256, false);
    strings.fillRange(0, 24, '');
    controllers.fillRange(0, 50, false);
    itemRooms.clear();
    scanStarts.clear();

    // By default in AGI, flag 5 is set on entering a new room
    flags[5] = true;
  }

  void clearPins() {
    pinnedFlags.clear();
    pinnedVars.clear();
    watchedFlags.clear();
    watchedVars.clear();
  }

  bool isFlagPinned(int index) => pinnedFlags.containsKey(index & 0xFF);
  bool isVarPinned(int index) => pinnedVars.containsKey(index & 0xFF);

  void pinFlag(int index, bool value) {
    final idx = index & 0xFF;
    pinnedFlags[idx] = value;
    watchedFlags.add(idx);
    flags[idx] = value;
  }

  void unpinFlag(int index) {
    pinnedFlags.remove(index & 0xFF);
  }

  void pinVar(int index, int value) {
    final idx = index & 0xFF;
    pinnedVars[idx] = value & 0xFF;
    watchedVars.add(idx);
    variables[idx] = value & 0xFF;
  }

  void unpinVar(int index) {
    pinnedVars.remove(index & 0xFF);
  }

  void watchFlag(int index) => watchedFlags.add(index & 0xFF);
  void watchVar(int index) => watchedVars.add(index & 0xFF);

  /// Writes pinned values back. Called at the end of each engine tick.
  void applyPins() {
    for (final entry in pinnedFlags.entries) {
      flags[entry.key] = entry.value;
    }
    for (final entry in pinnedVars.entries) {
      variables[entry.key] = entry.value;
    }
  }

  /// Reads variable [index] (0 - 255).
  int getVar(int index) => variables[index & 0xFF];

  /// Sets variable [index] (0 - 255) to [value] (truncated to 8-bit unsigned).
  void setVar(int index, int value) {
    variables[index & 0xFF] = value & 0xFF;
  }

  /// Increments variable [index] (saturates at 255 per AGI specification).
  void incrementVar(int index) {
    final idx = index & 0xFF;
    if (variables[idx] < 0xFF) {
      variables[idx]++;
    }
  }

  /// Decrements variable [index] (saturates at 0 per AGI specification).
  void decrementVar(int index) {
    final idx = index & 0xFF;
    if (variables[idx] > 0) {
      variables[idx]--;
    }
  }

  /// Optional dynamic flag hook (e.g. for on-demand Flag 1 Ego obscurity evaluation).
  bool? Function(int index)? flagGetterHook;

  /// Reads flag [index] (0 - 255).
  bool getFlag(int index) {
    final idx = index & 0xFF;
    // Pinned flags skip the Flag 1 obscurity hook so a pin actually sticks.
    if (!pinnedFlags.containsKey(idx) && flagGetterHook != null) {
      final hookVal = flagGetterHook!(idx);
      if (hookVal != null) {
        return hookVal;
      }
    }
    return flags[idx];
  }

  /// Sets flag [index] to true.
  void setFlag(int index) {
    flags[index & 0xFF] = true;
  }

  /// Resets flag [index] to false.
  void resetFlag(int index) {
    flags[index & 0xFF] = false;
  }

  /// Toggles flag [index].
  void toggleFlag(int index) {
    final idx = index & 0xFF;
    flags[idx] = !flags[idx];
  }

  /// Gets string variable [index] (0 - 23).
  String getString(int index) {
    if (index >= 0 && index < strings.length) {
      return strings[index];
    }
    return '';
  }

  /// Sets string variable [index] (0 - 23).
  void setString(int index, String value) {
    if (index >= 0 && index < strings.length) {
      strings[index] = value;
    }
  }

  /// Gets controller trigger [index] (0 - 49).
  bool getController(int index) {
    if (index >= 0 && index < controllers.length) {
      return controllers[index];
    }
    return false;
  }

  /// Sets controller trigger [index] (0 - 49).
  void setController(int index, bool value) {
    if (index >= 0 && index < controllers.length) {
      controllers[index] = value;
    }
  }

  /// Resets all controller triggers to false (called at start of cycle).
  void resetControllers() {
    controllers.fillRange(0, controllers.length, false);
  }

  /// Sets custom alias for variable [varNum].
  void setVarAlias(int varNum, String name) {
    customVarNames[varNum & 0xFF] = name;
  }

  /// Sets custom alias for flag [flagNum].
  void setFlagAlias(int flagNum, String name) {
    customFlagNames[flagNum & 0xFF] = name;
  }

  /// Returns variable name: custom alias if present, else standard name/description.
  String getVarDisplayName(int varNum) {
    final idx = varNum & 0xFF;
    if (customVarNames.containsKey(idx)) {
      return customVarNames[idx]!;
    }
    final desc = defaultVarDescriptions[idx];
    return desc != null ? '%v$idx ($desc)' : '%v$idx';
  }

  /// Returns flag name: custom alias if present, else standard name/description.
  String getFlagDisplayName(int flagNum) {
    final idx = flagNum & 0xFF;
    if (customFlagNames.containsKey(idx)) {
      return customFlagNames[idx]!;
    }
    final desc = defaultFlagDescriptions[idx];
    return desc != null ? '%f$idx ($desc)' : '%f$idx';
  }

  /// Standard default AGI flag descriptions.
  static const Map<int, String> defaultFlagDescriptions = {
    0: 'EGO base line on water surface (pri 3)',
    1: 'EGO is invisible / completely obscured',
    2: 'Player has issued a command line',
    3: 'EGO base line touched signal pixel (pri 2)',
    4: 'said() command accepted user input',
    5: 'New room executed for the first time',
    6: 'restart_game command executed',
    7: 'Writing to script-buffer is blocked',
    8: 'v15 determines joystick sensitivity',
    9: 'Sound on/off',
    10: 'Built-in debugger on',
    11: 'Logic 0 run for the first time',
    12: 'restore_game command executed',
    13: 'Status command item selection allowed',
    14: 'Menu system enabled',
    15: 'Print mode (0: enter to close, 1: persists)',
    16: 'Restart cancelled',
  };

  /// Standard default AGI variable descriptions.
  static const Map<int, String> defaultVarDescriptions = {
    0: 'Current room number',
    1: 'Previous room number',
    2: 'Border touched by EGO (0:none, 1:top, 2:right, 3:bottom, 4:left)',
    3: 'Current score',
    4: 'Object touching border (other than EGO)',
    5: 'Border code touched by object in v4',
    6: 'Direction of EGO motion (0:none, 1:N, 2:NE, 3:E, 4:SE, 5:S, 6:SW, 7:W, 8:NW)',
    7: 'Maximum score',
    8: 'Free pages in memory',
    9: 'Unrecognized word number from dictionary',
    10: 'Time delay in interpreter cycles (1/20s)',
    11: 'Clock seconds',
    12: 'Clock minutes',
    13: 'Clock hours',
    14: 'Clock days',
    15: 'Joystick sensitivity',
    16: 'View ID associated with EGO',
    17: 'Interpreter error code',
    18: 'Additional error parameter',
    19: 'Key pressed on keyboard',
    20: 'Computer type (0: IBM PC)',
    21: 'Window auto-close timer (0.5s units)',
    22: 'Sound generator type (1: PC speaker, 3: Tandy 3-voice)',
    23: 'Sound volume',
    24: 'Maximum score (alternate / secondary)',
    25: 'ID of item selected using status command',
    26: 'Graphics mode (0: CGA, 2: Hercules, 3: EGA)',
  };
}
