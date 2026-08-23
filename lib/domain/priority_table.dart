import 'dart:typed_data';

/// Manages depth priority band mappings (Y coordinate -> priority 4..14).
///
/// In standard AGI (base 48), priority bands start at Y=48 and are 12 pixels tall.
/// In late AGI v2 (>= 2.936, 2.425) and AGI v3, `set.pri.base(base)` dynamically rescales
/// the priority bands to accommodate taller character sprites (such as Rosella in KQ4).
class AgiPriorityTable {
  static const int defaultBase = 48;
  static const int scriptHeight = 168;

  final Uint8List _table = Uint8List(scriptHeight);
  int? _priorityBase;

  /// The active priority base, or null if the default table is active.
  int? get priorityBase => _priorityBase;

  /// Whether a custom priority base has been applied.
  bool get isModified => _priorityBase != null;

  AgiPriorityTable({int? initialBase}) {
    if (initialBase != null) {
      setPriorityBase(initialBase);
    } else {
      createDefaultTable();
    }
  }

  /// Restores the default AGI priority curve (12 pixels per band, starting at Y=48).
  void createDefaultTable() {
    _priorityBase = null;
    int y = 0;
    for (int priority = 1; priority < 15; priority++) {
      for (int step = 0; step < 12; step++) {
        if (y < scriptHeight) {
          _table[y++] = priority < 4 ? 4 : priority;
        }
      }
    }
  }

  /// Sets the dynamic priority base using the authentic Sierra AGI / ScummVM formula.
  void setPriorityBase(int base) {
    _priorityBase = base;
    final x = (scriptHeight - base) * scriptHeight ~/ 10;
    if (x == 0) return;

    for (int y = 0; y < scriptHeight; y++) {
      int p;
      if (y < base) {
        p = 4;
      } else {
        p = (y - base) * scriptHeight ~/ x + 5;
        if (p > 15) p = 15;
      }
      _table[y] = p;
    }
  }

  /// Maps a baseline Y coordinate (0..167) to its effective depth priority (4..14).
  int priorityFromY(int y) {
    if (y < 0) return _table[0];
    if (y >= scriptHeight) return _table[scriptHeight - 1];
    return _table[y];
  }

  /// Maps a fixed priority band back to the blit-sort Y coordinate (top of that band).
  int priorityToY(int priority) {
    if (_priorityBase == null) {
      if (priority <= 4) return 0;
      if (priority >= 15) return 168;
      return (priority - 5) * 12 + 48;
    }

    int currentY = scriptHeight - 1;
    while (currentY >= 0 && _table[currentY] >= priority) {
      currentY--;
    }
    return currentY < 0 ? 0 : currentY;
  }
}
