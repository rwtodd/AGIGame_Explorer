// SCI Selectors and VOCAB.997 parser.

import 'dart:convert';
import 'dart:typed_data';

/// Handles parsing of `VOCAB.997` and provides fast selector name <-> ID resolution.
class SciSelectors {
  final Map<String, int> _nameToId = {};
  final Map<int, String> _idToName = {};

  // --- Cached Standard Selector IDs ---
  int species = 0;
  int superClass = 1;
  int info = 2;
  int name = 3;
  int y = 4;
  int x = 5;
  int view = 6;
  int loop = 7;
  int cel = 8;
  int underBits = 9;
  int nsTop = 10;
  int nsLeft = 11;
  int nsBottom = 12;
  int nsRight = 13;
  int lsTop = 14;
  int lsLeft = 15;
  int lsBottom = 16;
  int lsRight = 17;
  int signal = 18;
  int illegalBits = 19;
  int brTop = 20;
  int brLeft = 21;
  int brBottom = 22;
  int brRight = 23;
  int play = -1;
  int doit = -1;
  int handleEvent = -1;
  int init = -1;
  int replay = -1;
  int startRoom = -1;
  int canBeHere = -1;
  int cantBeHere = -1;
  int mover = -1;
  int looper = -1;
  int client = -1;
  int dx = -1;
  int dy = -1;
  int xStep = -1;
  int yStep = -1;
  int moveSpeed = -1;
  int priority = -1;
  int z = -1;
  int text = -1;
  int elements = -1;
  int font = -1;
  int cursor = -1;
  int delete = -1;
  int wordFail = -1;
  int syntaxFail = -1;
  int pragmaFail = -1;
  int claimed = -1;
  int heading = -1;
  int isBlocked = -1;
  int bI1 = -1;
  int bI2 = -1;
  int bDi = -1;
  int bIncr = -1;
  int bXAxis = -1;
  int bMovCnt = -1;
  int moveDone = -1;
  int type = -1;
  int message = -1;
  int modifiers = -1;
  int number = -1;
  int state = -1;
  int mode = -1;
  int max = -1;
  int horizon = -1;

  bool isEarlySci0 = false;

  SciSelectors();

  /// Loads selector names from raw `VOCAB.997` bytes.
  void loadVocab997(Uint8List vocab997Bytes, {bool isEarlySci0 = false}) {
    this.isEarlySci0 = isEarlySci0;
    _nameToId.clear();
    _idToName.clear();

    final byteData = ByteData.sublistView(vocab997Bytes);
    final count = byteData.getUint16(0, Endian.little) + 1;
    final step = isEarlySci0 ? 2 : 1;

    for (var i = 0; i < count; i++) {
      final offset = byteData.getUint16(2 + i * 2, Endian.little);
      if (offset + 2 > vocab997Bytes.length) continue;
      final len = byteData.getUint16(offset, Endian.little);
      if (offset + 2 + len > vocab997Bytes.length) continue;

      final nameStr = ascii.decode(vocab997Bytes.sublist(offset + 2, offset + 2 + len));
      final id = i * step;
      _nameToId[nameStr] = id;
      _idToName[id] = nameStr;
      if (isEarlySci0) {
        _idToName[id + 1] = nameStr;
      }
    }

    _cacheStandardSelectors();
  }

  /// Populates well-known standard selector IDs based on loaded names.
  void _cacheStandardSelectors() {
    final step = isEarlySci0 ? 2 : 1;
    species = findSelector('species') ?? (0 * step);
    superClass = findSelector('superClass') ?? (1 * step);
    info = findSelector('-info-') ?? (2 * step);
    name = findSelector('name') ?? (3 * step);
    y = findSelector('y') ?? (4 * step);
    x = findSelector('x') ?? (5 * step);
    view = findSelector('view') ?? (6 * step);
    loop = findSelector('loop') ?? (7 * step);
    cel = findSelector('cel') ?? (8 * step);
    underBits = findSelector('underBits') ?? (9 * step);
    nsTop = findSelector('nsTop') ?? (10 * step);
    nsLeft = findSelector('nsLeft') ?? (11 * step);
    nsBottom = findSelector('nsBottom') ?? (12 * step);
    nsRight = findSelector('nsRight') ?? (13 * step);
    lsTop = findSelector('lsTop') ?? (14 * step);
    lsLeft = findSelector('lsLeft') ?? (15 * step);
    lsBottom = findSelector('lsBottom') ?? (16 * step);
    lsRight = findSelector('lsRight') ?? (17 * step);
    signal = findSelector('signal') ?? (18 * step);
    illegalBits = findSelector('illegalBits') ?? (19 * step);
    brTop = findSelector('brTop') ?? (20 * step);
    brLeft = findSelector('brLeft') ?? (21 * step);
    brBottom = findSelector('brBottom') ?? (22 * step);
    brRight = findSelector('brRight') ?? (23 * step);

    play = findSelector('play') ?? -1;
    doit = findSelector('doit') ?? -1;
    handleEvent = findSelector('handleEvent') ?? -1;
    init = findSelector('init') ?? -1;
    replay = findSelector('replay') ?? -1;
    startRoom = findSelector('startRoom') ?? -1;
    canBeHere = findSelector('canBeHere') ?? -1;
    cantBeHere = findSelector('cantBeHere') ?? -1;
    mover = findSelector('mover') ?? -1;
    looper = findSelector('looper') ?? -1;
    client = findSelector('client') ?? -1;
    dx = findSelector('dx') ?? -1;
    dy = findSelector('dy') ?? -1;
    xStep = findSelector('xStep') ?? -1;
    yStep = findSelector('yStep') ?? -1;
    moveSpeed = findSelector('moveSpeed') ?? -1;
    priority = findSelector('priority') ?? -1;
    z = findSelector('z') ?? -1;
    text = findSelector('text') ?? -1;
    elements = findSelector('elements') ?? -1;
    font = findSelector('font') ?? -1;
    cursor = findSelector('cursor') ?? -1;
    delete = findSelector('delete') ?? -1;
    wordFail = findSelector('wordFail') ?? -1;
    syntaxFail = findSelector('syntaxFail') ?? -1;
    pragmaFail = findSelector('pragmaFail') ?? -1;
    claimed = findSelector('claimed') ?? -1;
    heading = findSelector('heading') ?? -1;
    isBlocked = findSelector('isBlocked') ?? -1;
    bI1 = findSelector('b-i1') ?? findSelector('b_i1') ?? -1;
    bI2 = findSelector('b-i2') ?? findSelector('b_i2') ?? -1;
    bDi = findSelector('b-di') ?? findSelector('b_di') ?? -1;
    bIncr = findSelector('b-incr') ?? findSelector('b_incr') ?? -1;
    bXAxis = findSelector('b-xAxis') ?? findSelector('b_xAxis') ?? -1;
    bMovCnt = findSelector('b-moveCnt') ??
        findSelector('b-movCnt') ??
        findSelector('b_movCnt') ??
        -1;
    moveDone = findSelector('moveDone') ?? -1;
    type = findSelector('type') ?? -1;
    message = findSelector('message') ?? -1;
    modifiers = findSelector('modifiers') ?? -1;
    number = findSelector('number') ?? -1;
    state = findSelector('state') ?? -1;
    mode = findSelector('mode') ?? -1;
    max = findSelector('max') ?? -1;
    horizon = findSelector('horizon') ?? -1;
  }

  /// Finds selector ID by name, or null if not found.
  int? findSelector(String name) => _nameToId[name];

  /// Registers or overrides a selector mapping (useful in tests or synthetic scripts).
  void registerSelector(String name, int id) {
    _nameToId[name] = id;
    _idToName[id] = name;
    if (isEarlySci0) {
      _idToName[id ^ 1] = name;
    }
  }

  /// Finds selector name by ID, or fallback string if not found.
  String getSelectorName(int id) {
    var name = _idToName[id];
    if (name == null && isEarlySci0) {
      name = _idToName[id & ~1];
    }
    return name ?? 'sel_$id';
  }

  /// Total number of loaded selectors.
  int get length => _nameToId.length;
}
