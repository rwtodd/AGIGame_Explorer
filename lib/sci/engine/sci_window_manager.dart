import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

/// A graphics port in the SCI0 Window Manager.
class SciPort {
  final int id;
  Rect rect;
  int top;
  int left;
  int curTop;
  int curLeft;
  int penClr;
  int backClr;
  int fontId;
  int penMode;
  bool greyedOutput;

  SciPort({
    required this.id,
    required this.rect,
    this.top = 0,
    this.left = 0,
    this.curTop = 0,
    this.curLeft = 0,
    this.penClr = 0,
    this.backClr = 15,
    this.fontId = 0,
    this.penMode = 0,
    this.greyedOutput = false,
  });
}

/// In-memory representation of an open SCI dialog window.
class SciWindowRecord extends SciPort {
  Rect dims;
  Rect restoreRect;
  final int style;
  final int priority;
  final String? title;
  final bool hasDropShadow;
  final bool noFrame;
  final bool hasTitleBar;
  final bool isTransparent;
  final Offset contentOffset;

  final List<SciControlItem> controls = [];
  final Map<int, SciControlItem> controlsByRef = {};

  SciWindowRecord({
    required super.id,
    required this.dims,
    required this.restoreRect,
    required super.left,
    required super.top,
    this.style = 0,
    this.priority = 15,
    this.title,
    this.hasDropShadow = true,
    this.noFrame = false,
    this.hasTitleBar = false,
    this.isTransparent = false,
    this.contentOffset = Offset.zero,
    super.penClr = 0,
    super.backClr = 15,
  }) : super(rect: dims);

  /// Adds or updates a control item inside this window.
  void setControl(int refOffset, SciControlItem control) {
    if (controlsByRef.containsKey(refOffset)) {
      final old = controlsByRef[refOffset]!;
      final idx = controls.indexOf(old);
      if (idx >= 0) {
        controls[idx] = control;
      } else {
        controls.add(control);
      }
    } else {
      controls.add(control);
    }
    controlsByRef[refOffset] = control;
  }

  /// Converts this active window record into a renderable [SciWindowOverlay].
  SciWindowOverlay toOverlay({SierraFont? font}) {
    return SciWindowOverlay(
      id: id,
      rect: dims,
      title: hasTitleBar ? title : null,
      colorPen: penClr,
      colorBack: backClr,
      priority: priority,
      font: font,
      hasDropShadow: hasDropShadow,
      showChrome: true,
      showFrame: !noFrame,
      isTransparent: isTransparent,
      contentOffset: contentOffset,
      controls: List.unmodifiable(controls),
    );
  }
}

/// A region of the screen saved via `kGraph(SaveBox)`.
class SciSavedBox {
  final int handle;
  final Rect rect;
  final int portId;
  final List<SciControlItem> items = [];

  SciSavedBox({
    required this.handle,
    required this.rect,
    required this.portId,
  });
}

/// Window Manager for the Sierra SCI PMachine.
///
/// Coordinates `kNewWindow`, `kDisposeWindow`, `kGetPort`, `kSetPort`,
/// `kDrawControl`, `kHiliteControl`, and `kDisplay`.
class SciWindowManager {
  static const int wmgrPortId = 0;
  static const int picWindId = 1;
  static const int firstScriptWindowId = 2;
  static const int styleTransparent = 0x0001;
  static const int styleNoFrame = 0x0002;
  static const int styleTitle = 0x0004;
  static const int styleTopMost = 0x0008;
  static const int styleUser = 0x0080;
  static const int styleUserTransparent = 0x0081;

  late final SciPort _wmgrPort;
  late final SciPort _picWind;

  final Map<int, SciPort> _ports = {};
  final List<SciWindowRecord> _windowStack = [];
  final List<SciControlItem> _picDisplays = [];
  final Map<int, ({SciControlItem item, int portId})> _savedDisplays = {};
  final Map<int, SciSavedBox> _savedBoxes = {};
  final List<SciSavedBox> _activeBoxStack = [];

  SciPort _curPort;
  int _nextWindowId = firstScriptWindowId;
  int _nextDisplaySaveId = 1;
  int _nextBoxSaveId = 1;

  SciWindowManager()
      : _wmgrPort = SciPort(
          id: wmgrPortId,
          rect: const Rect.fromLTWH(0, 0, 320, 200),
        ),
        _picWind = SciPort(
          id: picWindId,
          rect: const Rect.fromLTWH(0, 10, 320, 190),
          top: 10,
        ),
        _curPort = SciPort(
          id: picWindId,
          rect: const Rect.fromLTWH(0, 10, 320, 190),
          top: 10,
        ) {
    _ports[wmgrPortId] = _wmgrPort;
    _ports[picWindId] = _picWind;
    _curPort = _picWind;
  }

  /// Active graphics port.
  SciPort get currentPort => _curPort;

  /// Stack of active dialog windows.
  List<SciWindowRecord> get windowStack => List.unmodifiable(_windowStack);

  /// Resets all windows, ports, and saved displays.
  void reset() {
    _windowStack.clear();
    _picDisplays.clear();
    _savedDisplays.clear();
    _savedBoxes.clear();
    _activeBoxStack.clear();
    _ports.clear();
    _ports[wmgrPortId] = _wmgrPort;
    _ports[picWindId] = _picWind;
    _curPort = _picWind;
    _nextWindowId = firstScriptWindowId;
    _nextDisplaySaveId = 1;
    _nextBoxSaveId = 1;
  }

  /// Creates a new window overlay via `kNewWindow`.
  SciWindowRecord openWindow({
    required Rect dims,
    Rect? restoreRect,
    int style = 0,
    int priority = 15,
    int colorPen = 0,
    int colorBack = 15,
    String? title,
  }) {
    final winId = _nextWindowId++;

    // Clip / constrain dimensions inside screen space (320x200)
    var left = dims.left;
    var top = dims.top;
    var right = dims.right;
    var bottom = dims.bottom;

    if (left < 0) {
      right += -left;
      left = 0;
    }
    if (top < 0) {
      bottom += -top;
      top = 0;
    }
    if (right > 320) {
      final diff = right - 320;
      left = math.max(0, left - diff);
      right = 320;
    }
    if (bottom > 200) {
      final diff = bottom - 200;
      top = math.max(0, top - diff);
      bottom = 200;
    }

    // Script args are the inner port. Chrome grows outward (ScummVM addWindow).
    final inner = Rect.fromLTRB(left, top, right, bottom);
    final isUserWindow = (style & styleUser) != 0 || style == styleUserTransparent;
    final isTransparent = (style & styleTransparent) != 0 || isUserWindow;
    final noFrame = (style & styleNoFrame) != 0 || isUserWindow;
    final hasDropShadow = !noFrame && !isUserWindow;
    final hasTitleBar = !isUserWindow && (style & styleTitle) != 0 && title != null && title.isNotEmpty;

    var outerLeft = inner.left;
    var outerTop = inner.top;
    var outerRight = inner.right;
    var outerBottom = inner.bottom;
    if (!noFrame && !isUserWindow) {
      outerLeft -= 1;
      outerTop -= 1;
      outerRight += 1;
      outerBottom += 1;
    }
    if (hasTitleBar) {
      outerTop -= 10;
    }
    outerLeft = math.max(0, outerLeft);
    outerTop = math.max(0, outerTop);
    outerRight = math.min(320, outerRight);
    outerBottom = math.min(200, outerBottom);
    final outer = Rect.fromLTRB(outerLeft, outerTop, outerRight, outerBottom);

    final wnd = SciWindowRecord(
      id: winId,
      dims: outer,
      restoreRect: restoreRect ?? outer,
      left: inner.left.round(),
      top: inner.top.round(),
      style: style,
      priority: priority >= 0 ? priority : 15,
      penClr: colorPen,
      backClr: colorBack,
      title: title,
      hasDropShadow: hasDropShadow,
      noFrame: noFrame,
      hasTitleBar: hasTitleBar,
      isTransparent: isTransparent,
      contentOffset: Offset(inner.left - outer.left, inner.top - outer.top),
    );

    _ports[winId] = wnd;
    _windowStack.add(wnd);
    _curPort = wnd;

    return wnd;
  }

  /// Disposes an open window by ID via `kDisposeWindow`.
  bool closeWindow(int windowId) {
    _ports.remove(windowId);
    final idx = _windowStack.indexWhere((w) => w.id == windowId);
    if (idx >= 0) {
      _windowStack.removeAt(idx);
      _curPort = _windowStack.isNotEmpty ? _windowStack.last : _picWind;
      return true;
    }
    return false;
  }

  /// Sets the active port via `kSetPort`.
  void setPort(int portId) {
    _curPort = _ports[portId] ?? _picWind;
  }

  /// Pic-window origin used when turning port-local `Display` coords into screen space.
  void setPicWindowOrigin(int top, int left) {
    _picWind.top = top;
    _picWind.left = left;
    if (_curPort.id == picWindId) {
      _curPort = _picWind;
    }
  }

  /// `DrawPic` replaces the visual screen, so unsaved picture-port text goes with it.
  void clearPicDisplays() {
    if (_picDisplays.isEmpty && _savedDisplays.isEmpty) return;
    _picDisplays.clear();
    _savedDisplays.removeWhere((_, entry) => entry.portId == picWindId);
  }

  /// Gets the ID of the active port via `kGetPort`.
  int getPort() => _curPort.id;

  /// Retrieves a port by ID.
  SciPort? getPortById(int portId) => _ports[portId];

  /// Sets a control on the currently active window or a target window.
  void setControl({
    required int controlRefOffset,
    required SciControlItem controlItem,
    int? windowId,
  }) {
    SciWindowRecord? target;
    if (windowId != null) {
      final p = _ports[windowId];
      if (p is SciWindowRecord) target = p;
    }
    target ??= _curPort is SciWindowRecord
        ? (_curPort as SciWindowRecord)
        : (_windowStack.isNotEmpty ? _windowStack.last : null);

    target?.setControl(controlRefOffset, controlItem);
  }

  /// Saves a box region via `kGraph(SaveBox)`.
  int saveBox(Rect rect) {
    final handle = _nextBoxSaveId++;
    final box = SciSavedBox(
      handle: handle,
      rect: rect,
      portId: _curPort.id,
    );
    _savedBoxes[handle] = box;
    _activeBoxStack.add(box);
    return handle;
  }

  /// Restores a box region via `kGraph(RestoreBox)`.
  void restoreBox(int handle) {
    final box = _savedBoxes.remove(handle);
    if (box != null) {
      _activeBoxStack.remove(box);
      for (final item in box.items) {
        final target = _ports[box.portId];
        if (target is SciWindowRecord) {
          target.controls.remove(item);
        } else {
          _picDisplays.remove(item);
        }
      }
      return;
    }
    restoreDisplay(handle);
  }

  /// Adds a transient display control via `kDisplay` or `kGraph`.
  int addDisplay(SciControlItem item, {bool saveUnder = false}) {
    final targetWindow = _curPort is SciWindowRecord
        ? (_curPort as SciWindowRecord)
        : null;

    if (targetWindow != null) {
      targetWindow.controls.add(item);
    } else {
      _picDisplays.add(item);
    }

    if (_activeBoxStack.isNotEmpty) {
      for (final box in _activeBoxStack) {
        box.items.add(item);
      }
    }

    if (saveUnder) {
      final handle = _nextDisplaySaveId++;
      _savedDisplays[handle] = (item: item, portId: targetWindow?.id ?? picWindId);
      return handle;
    }
    return 0;
  }

  /// Restores / removes a display item via `kDisplay` (tag 108).
  void restoreDisplay(int handle) {
    if (_savedBoxes.containsKey(handle)) {
      restoreBox(handle);
      return;
    }
    final entry = _savedDisplays.remove(handle);
    if (entry != null) {
      final target = _ports[entry.portId];
      if (target is SciWindowRecord) {
        target.controls.remove(entry.item);
      } else {
        _picDisplays.remove(entry.item);
      }
    }
  }

  /// Builds the current list of [SciWindowOverlay]s for the rendering pipeline.
  List<SciWindowOverlay> toOverlays({SierraFont? Function(int fontId)? fontResolver}) {
    if (_windowStack.isEmpty && _picDisplays.isEmpty) return const [];
    final overlays = <SciWindowOverlay>[];
    if (_picDisplays.isNotEmpty) {
      overlays.add(SciWindowOverlay(
        id: picWindId,
        rect: const Rect.fromLTWH(0, 0, 320, 200),
        priority: 0,
        hasDropShadow: false,
        showChrome: false,
        controls: List.unmodifiable(_picDisplays),
        font: fontResolver?.call(_picWind.fontId),
      ));
    }
    for (final wnd in _windowStack) {
      final font = fontResolver?.call(wnd.fontId);
      overlays.add(wnd.toOverlay(font: font));
    }
    return overlays;
  }
}
