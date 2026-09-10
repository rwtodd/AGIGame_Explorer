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

  final List<SciControlItem> controls = [];
  final Map<int, SciControlItem> controlsByRef = {};

  SciWindowRecord({
    required super.id,
    required this.dims,
    required this.restoreRect,
    this.style = 0,
    this.priority = 15,
    this.title,
    this.hasDropShadow = true,
    super.penClr = 0,
    super.backClr = 15,
  }) : super(
          rect: dims,
          left: dims.left.round(),
          top: dims.top.round(),
        );

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
      title: title,
      colorPen: penClr,
      colorBack: backClr,
      priority: priority,
      font: font,
      hasDropShadow: hasDropShadow,
      controls: List.unmodifiable(controls),
    );
  }
}

/// Window Manager for the Sierra SCI PMachine.
///
/// Coordinates `kNewWindow`, `kDisposeWindow`, `kGetPort`, `kSetPort`,
/// `kDrawControl`, `kHiliteControl`, and `kDisplay`.
class SciWindowManager {
  static const int wmgrPortId = 0;
  static const int picWindId = 1;
  static const int firstScriptWindowId = 2;

  late final SciPort _wmgrPort;
  late final SciPort _picWind;

  final Map<int, SciPort> _ports = {};
  final List<SciWindowRecord> _windowStack = [];
  final Map<int, ({SciControlItem item, int portId})> _savedDisplays = {};

  SciPort _curPort;
  int _nextWindowId = firstScriptWindowId;
  int _nextDisplaySaveId = 1;

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
    _savedDisplays.clear();
    _ports.clear();
    _ports[wmgrPortId] = _wmgrPort;
    _ports[picWindId] = _picWind;
    _curPort = _picWind;
    _nextWindowId = firstScriptWindowId;
    _nextDisplaySaveId = 1;
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

    final adjustedDims = Rect.fromLTRB(left, top, right, bottom);
    final adjustedRestore = restoreRect ?? adjustedDims;

    // Sierra style bit 1 = NOFRAME, bit 2 = TITLE
    final hasDropShadow = (style & 0x0002) == 0;

    final wnd = SciWindowRecord(
      id: winId,
      dims: adjustedDims,
      restoreRect: adjustedRestore,
      style: style,
      priority: priority >= 0 ? priority : 15,
      penClr: colorPen,
      backClr: colorBack,
      title: title,
      hasDropShadow: hasDropShadow,
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

  /// Adds a transient display control via `kDisplay`.
  int addDisplay(SciControlItem item, {bool saveUnder = false}) {
    final targetWindow = _curPort is SciWindowRecord
        ? (_curPort as SciWindowRecord)
        : (_windowStack.isNotEmpty ? _windowStack.last : null);

    if (targetWindow != null) {
      targetWindow.controls.add(item);
    }

    if (saveUnder) {
      final handle = _nextDisplaySaveId++;
      _savedDisplays[handle] = (item: item, portId: targetWindow?.id ?? _curPort.id);
      return handle;
    }
    return 0;
  }

  /// Restores / removes a display item via `kDisplay` (tag 108).
  void restoreDisplay(int handle) {
    final entry = _savedDisplays.remove(handle);
    if (entry != null) {
      final target = _ports[entry.portId];
      if (target is SciWindowRecord) {
        target.controls.remove(entry.item);
      }
    }
  }

  /// Builds the current list of [SciWindowOverlay]s for the rendering pipeline.
  List<SciWindowOverlay> toOverlays({SierraFont? Function(int fontId)? fontResolver}) {
    if (_windowStack.isEmpty) return const [];
    return _windowStack.map((wnd) {
      final font = fontResolver?.call(wnd.fontId);
      return wnd.toOverlay(font: font);
    }).toList(growable: false);
  }
}
