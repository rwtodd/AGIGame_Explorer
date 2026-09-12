import 'dart:ui';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

/// One pull-down item under a [SciMenu].
class SciMenuItem {
  String label;
  String shortcut;
  bool enabled;
  bool checked;
  bool isSeparator;

  SciMenuItem({
    required this.label,
    this.shortcut = '',
    this.enabled = true,
    this.checked = false,
    this.isSeparator = false,
  });
}

/// One top-level menu (File, Game, …). Ids are 1-based like Sierra.
class SciMenu {
  final int id;
  final String title;
  final List<SciMenuItem> items;

  SciMenu({required this.id, required this.title, required this.items});
}

/// SCI0 menu bar + status strip (rows 0..9).
class SciMenuBar {
  final List<SciMenu> menus = [];
  bool visible = false;
  String statusText = '';
  int statusPen = 0;
  int statusBack = 15;
  int? openMenuId;

  void reset() {
    menus.clear();
    visible = false;
    statusText = '';
    statusPen = 0;
    statusBack = 15;
    openMenuId = null;
  }

  /// Parses Sierra `AddMenu` content (`label\`key:label2:…`).
  void addMenu(String title, String content) {
    final items = <SciMenuItem>[];
    final parts = content.split(':');
    for (final part in parts) {
      if (part.isEmpty) continue;
      var label = part;
      var shortcut = '';
      final tick = part.indexOf('`');
      if (tick >= 0) {
        label = part.substring(0, tick);
        shortcut = part.substring(tick + 1);
      }
      final trimmed = label.trim();
      final isSep = trimmed.isEmpty || trimmed.replaceAll('#', '').isEmpty;
      items.add(SciMenuItem(
        label: isSep ? '-' : trimmed,
        shortcut: shortcut,
        isSeparator: isSep,
      ));
    }
    menus.add(SciMenu(id: menus.length + 1, title: title, items: items));
  }

  SciMenuItem? itemAt(int menuId, int itemId) {
    if (menuId < 1 || menuId > menus.length) return null;
    final items = menus[menuId - 1].items;
    if (itemId < 1 || itemId > items.length) return null;
    return items[itemId - 1];
  }

  /// Hit-test a screen point against menu titles. Returns 1-based menu id or 0.
  int menuIdAt(int x, int y, SierraFont? font) {
    if (!visible || y < 0 || y >= 10 || menus.isEmpty) return 0;
    var cx = 8;
    for (final menu in menus) {
      final w = (font?.measureTextWidth(menu.title) ?? menu.title.length * 8) + 8;
      if (x >= cx && x < cx + w) return menu.id;
      cx += w;
    }
    return 0;
  }

  /// Overlay for the 10px strip: menu titles, or status text when the bar is hidden.
  SciWindowOverlay? toOverlay({SierraFont? font}) {
    if (!visible && statusText.isEmpty) return null;
    final controls = <SciControlItem>[];
    if (visible && menus.isNotEmpty) {
      var x = 8.0;
      for (final menu in menus) {
        final w = (font?.measureTextWidth(menu.title) ?? menu.title.length * 8) + 8;
        controls.add(SciTextControl(
          rect: Rect.fromLTWH(x, 1, w.toDouble(), 9),
          text: menu.title,
          colorPen: 0,
          colorBack: null,
          font: font,
        ));
        x += w;
      }
    } else if (statusText.isNotEmpty) {
      controls.add(SciTextControl(
        rect: const Rect.fromLTWH(8, 1, 304, 9),
        text: statusText,
        colorPen: statusPen,
        colorBack: statusBack,
        font: font,
      ));
    }
    return SciWindowOverlay(
      id: 0,
      rect: const Rect.fromLTWH(0, 0, 320, 10),
      colorPen: 0,
      colorBack: 15,
      priority: 15,
      font: font,
      hasDropShadow: false,
      showChrome: true,
      showFrame: false,
      controls: controls,
    );
  }
}
