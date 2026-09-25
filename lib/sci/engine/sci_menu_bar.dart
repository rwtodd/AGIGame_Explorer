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

  /// True when the strip currently shows [statusText] rather than menu
  /// titles. Sierra/ScummVM treat the 10px strip as last-writer-wins:
  /// `DrawStatus` paints status text over the titles, `DrawMenuBar` paints
  /// titles back over the status.
  bool statusActive = false;
  int? openMenuId;
  int highlightedItemId = 1;

  void reset() {
    menus.clear();
    visible = false;
    statusText = '';
    statusPen = 0;
    statusBack = 15;
    statusActive = false;
    openMenuId = null;
    highlightedItemId = 1;
  }

  void openMenu(int menuId) {
    if (menuId < 1 || menuId > menus.length) return;
    openMenuId = menuId;
    highlightedItemId = _firstEnabledItem(menus[menuId - 1]);
  }

  void closeMenu() {
    openMenuId = null;
    highlightedItemId = 1;
  }

  int _firstEnabledItem(SciMenu menu) {
    for (var i = 0; i < menu.items.length; i++) {
      if (!menu.items[i].isSeparator && menu.items[i].enabled) return i + 1;
    }
    return 1;
  }

  void moveHighlight(int delta) {
    final id = openMenuId;
    if (id == null) return;
    final items = menus[id - 1].items;
    if (items.isEmpty) return;
    var idx = highlightedItemId;
    for (var n = 0; n < items.length; n++) {
      idx += delta;
      if (idx < 1) idx = items.length;
      if (idx > items.length) idx = 1;
      final item = items[idx - 1];
      if (!item.isSeparator && item.enabled) {
        highlightedItemId = idx;
        return;
      }
    }
  }

  /// Packed Sierra menu result, or null if [itemId] is not selectable.
  int? packedSelection(int menuId, int itemId) {
    final item = itemAt(menuId, itemId);
    if (item == null || item.isSeparator || !item.enabled) return null;
    return (menuId << 8) | itemId;
  }

  /// Hit-test a dropdown item. Returns 1-based item id or 0.
  int itemIdAt(int x, int y, SierraFont? font) {
    final id = openMenuId;
    if (id == null) return 0;
    final menu = menus[id - 1];
    final drop = _dropdownRect(font);
    if (!drop.contains(Offset(x.toDouble(), y.toDouble()))) return 0;
    final row = ((y - drop.top) / 10).floor();
    if (row < 0 || row >= menu.items.length) return 0;
    return row + 1;
  }

  Rect _dropdownRect(SierraFont? font) {
    final id = openMenuId!;
    var cx = 8.0;
    for (final menu in menus) {
      final w = (font?.measureTextWidth(menu.title) ?? menu.title.length * 8) + 8;
      if (menu.id == id) {
        final menuW = menu.items.fold<int>(w.toInt(), (m, it) {
          final iw = (font?.measureTextWidth(it.label) ?? it.label.length * 8) + 16;
          return iw > m ? iw : m;
        });
        return Rect.fromLTWH(cx, 10, menuW.toDouble(), menu.items.length * 10.0);
      }
      cx += w;
    }
    return const Rect.fromLTWH(8, 10, 80, 40);
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

  /// Overlay for the 10px strip: status text wins once `DrawStatus` has
  /// painted it; menu titles show while a menu is open or when no status
  /// text has taken over the strip.
  SciWindowOverlay? toOverlay({SierraFont? font}) {
    final showTitles =
        (openMenuId != null || !statusActive) && visible && menus.isNotEmpty;
    if (!showTitles && statusText.isEmpty) return null;
    final controls = <SciControlItem>[];
    if (showTitles) {
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

  /// Pull-down list under the open menu title, or null.
  SciWindowOverlay? dropdownOverlay({SierraFont? font}) {
    final id = openMenuId;
    if (id == null || !visible) return null;
    final menu = menus[id - 1];
    final drop = _dropdownRect(font);
    final controls = <SciControlItem>[];
    for (var i = 0; i < menu.items.length; i++) {
      final item = menu.items[i];
      final row = Rect.fromLTWH(1, 1.0 + i * 10, drop.width, 10);
      if (item.isSeparator) {
        controls.add(SciFillControl(rect: row, color: 7));
        continue;
      }
      final hi = (i + 1) == highlightedItemId;
      controls.add(SciTextControl(
        rect: row,
        text: item.checked ? '*${item.label}' : item.label,
        colorPen: hi ? 15 : 0,
        colorBack: hi ? 0 : 15,
        font: font,
      ));
    }
    return SciWindowOverlay(
      id: 0,
      rect: Rect.fromLTWH(drop.left - 1, drop.top - 1, drop.width + 2, drop.height + 2),
      colorPen: 0,
      colorBack: 15,
      priority: 15,
      font: font,
      hasDropShadow: true,
      showChrome: true,
      showFrame: true,
      controls: controls,
    );
  }
}
