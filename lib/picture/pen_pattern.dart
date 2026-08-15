/// Interface for pixel patterns used by AGI picture pens.
abstract class PenPattern {
  /// Whether this pen pattern requires an argument byte from the PIC byte stream.
  bool get takesArgument;

  /// Sets the pattern variation number (for splatter patterns).
  void setPattern(int patternNumber);

  /// Returns an iterator of booleans indicating whether each successive pixel should be plotted.
  Iterator<bool> createIterator();
}

/// Solid pen pattern: all pixels within the pen shape are plotted.
class SolidPenPattern implements PenPattern {
  const SolidPenPattern();

  static const SolidPenPattern instance = SolidPenPattern();

  @override
  bool get takesArgument => false;

  @override
  void setPattern(int patternNumber) {
    throw UnsupportedError('Cannot set pattern number on SolidPenPattern');
  }

  @override
  Iterator<bool> createIterator() => const _SolidIterator();
}

class _SolidIterator implements Iterator<bool> {
  const _SolidIterator();

  @override
  bool get current => true;

  @override
  bool moveNext() => true;
}

/// Splatter pen pattern: uses Sierra's LFSR polynomial `0xB8` to generate textured stipples.
class SplatterPattern implements PenPattern {
  int _patternNumber = 0;

  SplatterPattern([int initialPattern = 0]) : _patternNumber = initialPattern;

  @override
  bool get takesArgument => true;

  @override
  void setPattern(int patternNumber) {
    _patternNumber = patternNumber;
  }

  @override
  Iterator<bool> createIterator() => _SplatterIterator(_patternNumber);
}

class _SplatterIterator implements Iterator<bool> {
  int _patternData;
  bool _current = false;

  _SplatterIterator(int pattern) : _patternData = (pattern & 0xFF) | 0x01;

  @override
  bool get current => _current;

  @override
  bool moveNext() {
    final lsb = _patternData & 1;
    _patternData = (_patternData >> 1) ^ (lsb != 0 ? 0xB8 : 0);
    _current = (_patternData & 3) == 2;
    return true;
  }
}
