/// Represents a single character cell in the AGI 40x25 text screen buffer.
class AgiTextCell {
  String char;
  int fg; // EGA color 0..15
  int bg; // EGA color 0..15

  AgiTextCell({
    this.char = ' ',
    this.fg = 15, // Default White
    this.bg = 0,  // Default Black
  });

  bool get isEmpty => char == ' ' && (bg == 0 || bg == 15 && fg == 15);
  bool get isBlank => char == ' ' || char.isEmpty;

  AgiTextCell clone() => AgiTextCell(char: char, fg: fg, bg: bg);
}

/// Authentic Sierra AGI 40-column by 25-row character screen matrix.
///
/// Native AGI resolution is 320x200 pixels in 4:3 aspect ratio, composed of
/// 40 columns and 25 rows of 8x8 pixel character cells.
class AgiTextScreenBuffer {
  static const int columns = 40;
  static const int rows = 25;

  final List<List<AgiTextCell>> _grid;
  int currentFg = 15;
  int currentBg = 0;

  AgiTextScreenBuffer()
      : _grid = List.generate(
          rows,
          (_) => List.generate(columns, (_) => AgiTextCell()),
        );

  /// Retrieves cell at [row], [col].
  AgiTextCell getCell(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= columns) {
      return AgiTextCell();
    }
    return _grid[row][col];
  }

  /// Clears the entire 40x25 text screen with spaces and given or current colors.
  void clear({int? fg, int? bg}) {
    final effectiveFg = fg ?? currentFg;
    final effectiveBg = bg ?? currentBg;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        _grid[r][c].char = ' ';
        _grid[r][c].fg = effectiveFg;
        _grid[r][c].bg = effectiveBg;
      }
    }
  }

  /// Clears lines from [top] to [bottom] inclusive with [color] (EGA 0..15).
  void clearLines(int top, int bottom, int color) {
    final startRow = top.clamp(0, rows - 1);
    final endRow = bottom.clamp(0, rows - 1);
    final minRow = startRow <= endRow ? startRow : endRow;
    final maxRow = startRow <= endRow ? endRow : startRow;

    for (int r = minRow; r <= maxRow; r++) {
      for (int c = 0; c < columns; c++) {
        _grid[r][c].char = ' ';
        _grid[r][c].fg = currentFg;
        _grid[r][c].bg = color.clamp(0, 15);
      }
    }
  }

  /// Clears character rectangle between [top, left] and [bottom, right] inclusive.
  void clearTextRect(int top, int left, int bottom, int right, int color) {
    final r1 = top.clamp(0, rows - 1);
    final r2 = bottom.clamp(0, rows - 1);
    final c1 = left.clamp(0, columns - 1);
    final c2 = right.clamp(0, columns - 1);

    final minR = r1 <= r2 ? r1 : r2;
    final maxR = r1 <= r2 ? r2 : r1;
    final minC = c1 <= c2 ? c1 : c2;
    final maxC = c1 <= c2 ? c2 : c1;

    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        _grid[r][c].char = ' ';
        _grid[r][c].fg = currentFg;
        _grid[r][c].bg = color.clamp(0, 15);
      }
    }
  }

  /// Writes [text] starting at ([row], [col]) using active or specified colors.
  /// Handles `\n` linebreaks and wraps at column 40.
  void writeString(
    int row,
    int col,
    String text, {
    int? fg,
    int? bg,
  }) {
    if (row < 0 || row >= rows || col < 0 || col >= columns) return;

    final effectiveFg = fg ?? currentFg;
    final effectiveBg = bg ?? currentBg;

    int curRow = row;
    int curCol = col;
    final resetCol = col;

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];

      if (ch == '\n' || ch == '\r') {
        curRow++;
        curCol = resetCol;
        if (curRow >= rows) break;
        continue;
      }

      if (curCol >= columns) {
        curRow++;
        curCol = 0;
        if (curRow >= rows) break;
      }

      _grid[curRow][curCol].char = ch;
      _grid[curRow][curCol].fg = effectiveFg;
      _grid[curRow][curCol].bg = effectiveBg;
      curCol++;
    }
  }

  /// Returns true if there are any non-space characters in the buffer.
  bool get hasContent {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        if (!_grid[r][c].isBlank) return true;
      }
    }
    return false;
  }
}
