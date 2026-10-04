import 'dart:ui';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

/// One pull-down item under a [SciMenu].
class SciMenuItem {
  String label;
  String shortcut;
  bool enabled;
  bool checked;
  bool _isSeparator;
  int tag;
  int _keyPress;
  int _keyModifier;
  SciReg? said;

  bool get isSeparator => _isSeparator || SciMenuBar.isSeparatorLabel(label);
  set isSeparator(bool value) => _isSeparator = value;

  int get keyPress {
    if (_keyPress != 0) return _keyPress;
    return parseShortcutKeys(shortcut).$1;
  }

  set keyPress(int value) => _keyPress = value;

  int get keyModifier {
    if (_keyModifier != 0) return _keyModifier;
    return parseShortcutKeys(shortcut).$2;
  }

  set keyModifier(int value) => _keyModifier = value;

  SciMenuItem({
    required this.label,
    this.shortcut = '',
    this.enabled = true,
    this.checked = false,
    bool isSeparator = false,
    this.tag = 0,
    int keyPress = 0,
    int keyModifier = 0,
    this.said,
  }) :
       // ignore: prefer_initializing_formals
       _keyPress = keyPress,
       // ignore: prefer_initializing_formals
       _keyModifier = keyModifier,
       // ignore: prefer_initializing_formals
       _isSeparator = isSeparator;

  Map<String, dynamic> toJson() => {
        'label': label,
        'shortcut': shortcut,
        'enabled': enabled,
        'checked': checked,
        'isSeparator': isSeparator,
        'tag': tag,
        'keyPress': _keyPress,
        'keyModifier': _keyModifier,
      };

  factory SciMenuItem.fromJson(Map<String, dynamic> json) {
    final label = json['label']?.toString() ?? '';
    final isSep = json['isSeparator'] as bool? ?? SciMenuBar.isSeparatorLabel(label);
    return SciMenuItem(
      label: label,
      shortcut: json['shortcut']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? true,
      checked: json['checked'] as bool? ?? false,
      isSeparator: isSep,
      tag: (json['tag'] as num?)?.toInt() ?? 0,
      keyPress: (json['keyPress'] as num?)?.toInt() ?? 0,
      keyModifier: (json['keyModifier'] as num?)?.toInt() ?? 0,
    );
  }

  /// Tests if this menu item matches an incoming keyboard event.
  bool matchesKey(int key, int mod) {
    if (isSeparator || !enabled) return false;
    final targetKey = keyPress;
    final targetMod = keyModifier;
    if (targetKey == 0) return false;

    var actualKey = key;
    var actualMod = mod & 15; // lower 4 bits (shift: 1|2, ctrl: 4, alt: 8)

    // ASCII control codes (1..26) when Ctrl modifier is set
    if ((actualMod & 4) != 0 && actualKey > 0 && actualKey < 27) {
      actualKey += 96;
    } else if (actualKey >= 65 && actualKey <= 90) {
      actualKey += 32; // uppercase -> lowercase
    }

    // Tab (9) maps to Ctrl+I in SCI
    if (actualKey == 9) {
      actualMod = 4;
      actualKey = 105; // 'i'
    }

    return targetKey == actualKey && targetMod == actualMod;
  }

  /// Parses a single Sierra menu item string into label, shortcut, tag, and isSeparator.
  static ({String label, String shortcut, int tag, bool isSeparator}) parseItemString(String part) {
    var tagPos = -1;
    var tickPos = -1;

    for (var i = 0; i < part.length; i++) {
      final c = part[i];
      if (c == '=') {
        // Special case: normal animation speed uses right-aligned "=" (`=)
        if (tickPos != i - 1) {
          tagPos = i;
        }
      } else if (c == '`') {
        tickPos = i;
      }
    }

    String label;
    String shortcut = '';
    int tag = 0;

    if (tickPos >= 0) {
      label = part.substring(0, tickPos);
      if (tagPos > tickPos) {
        shortcut = part.substring(tickPos + 1, tagPos);
        tag = int.tryParse(part.substring(tagPos + 1)) ?? 0;
      } else {
        shortcut = part.substring(tickPos + 1);
      }
    } else if (tagPos >= 0) {
      label = part.substring(0, tagPos);
      tag = int.tryParse(part.substring(tagPos + 1)) ?? 0;
    } else {
      label = part;
    }

    shortcut = shortcut.trim();
    final trimmedLabel = label.trim();
    final isSep = SciMenuBar.isSeparatorLabel(trimmedLabel);

    return (
      label: isSep ? '-' : trimmedLabel,
      shortcut: shortcut,
      tag: tag,
      isSeparator: isSep,
    );
  }

  /// Parses raw shortcut string into (keyPress, keyModifier).
  static (int keyPress, int keyModifier) parseShortcutKeys(String rawShortcut) {
    if (rawShortcut.isEmpty) return (0, 0);
    if (rawShortcut == '=') return (61, 0);
    var s = rawShortcut;
    final eq = s.indexOf('=');
    if (eq > 0) s = s.substring(0, eq);
    s = s.trim();

    if (s.startsWith('#')) {
      final sub = s.substring(1);
      return switch (sub) {
        '1' => (0x3B00, 0),
        '2' => (0x3C00, 0),
        '3' => (0x3D00, 0),
        '4' => (0x3E00, 0),
        '5' => (0x3F00, 0),
        '6' => (0x4000, 0),
        '7' => (0x4100, 0),
        '8' => (0x4200, 0),
        '9' => (0x4300, 0),
        '0' => (0x4400, 0),
        _ => (0, 0),
      };
    }
    if (s.startsWith('^') && s.length > 1) {
      return (s[1].toLowerCase().codeUnitAt(0), 4); // 4 = kSciKeyModCtrl
    }
    if (s.startsWith('@') && s.length > 1) {
      return (s[1].toLowerCase().codeUnitAt(0), 8); // 8 = kSciKeyModAlt
    }
    if (s == '+' || s == '-' || s == '=') {
      return (s.codeUnitAt(0), 0);
    }
    return (0, 0);
  }

  /// Formats raw Sierra shortcut strings (e.g. `#5` -> `F5`, `^q` -> `Ctrl+Q`).
  static String formatShortcut(String raw) {
    if (raw.isEmpty) return '';
    if (raw == '=') return '=';
    var s = raw;
    final eq = s.indexOf('=');
    if (eq > 0) s = s.substring(0, eq);
    s = s.trim();
    if (s.startsWith('#')) {
      final sub = s.substring(1);
      if (sub == '0') return 'F10';
      final n = int.tryParse(sub);
      if (n != null) return 'F$n';
    }
    if (s.startsWith('^') && s.length > 1) {
      return 'Ctrl+${s.substring(1).toUpperCase()}';
    }
    if (s.startsWith('@') && s.length > 1) {
      return 'Alt+${s.substring(1).toUpperCase()}';
    }
    return s;
  }
}

/// One top-level menu (File, Game, …). Ids are 1-based like Sierra.
class SciMenu {
  final int id;
  final String title;
  final List<SciMenuItem> items;

  SciMenu({required this.id, required this.title, required this.items});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory SciMenu.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return SciMenu(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      items: rawItems
          .map((i) => SciMenuItem.fromJson((i as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
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

  /// Serializes titles, items (including SetMenu enabled/checked/label
  /// state), visibility, and status text so save/restore keeps working
  /// menus. Transient open/highlight state is intentionally not persisted;
  /// saves happen with the menu closed.
  Map<String, dynamic> toJson() => {
        'visible': visible,
        'statusText': statusText,
        'statusPen': statusPen,
        'statusBack': statusBack,
        'statusActive': statusActive,
        'menus': menus.map((m) => m.toJson()).toList(),
      };

  /// Replaces bar contents from [toJson] output. Missing or empty input
  /// leaves the reset state alone (pre-menu saves stay menuless rather
  /// than crashing, and pick menus back up on reboot).
  void restoreJson(Map<String, dynamic> json) {
    reset();
    if (json.isEmpty) return;
    visible = json['visible'] as bool? ?? false;
    statusText = json['statusText']?.toString() ?? '';
    statusPen = (json['statusPen'] as num?)?.toInt() ?? 0;
    statusBack = (json['statusBack'] as num?)?.toInt() ?? 15;
    statusActive = json['statusActive'] as bool? ?? false;
    final rawMenus = json['menus'] as List? ?? const [];
    var id = 0;
    for (final m in rawMenus) {
      id++;
      final menu = SciMenu.fromJson((m as Map).cast<String, dynamic>());
      menus.add(SciMenu(id: id, title: menu.title, items: menu.items));
    }
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
    final item = menu.items[row];
    if (item.isSeparator || !item.enabled) return 0;
    return row + 1;
  }

  Rect _dropdownRect(SierraFont? font) {
    final id = openMenuId!;
    var cx = 8.0;
    for (final menu in menus) {
      final w = (font?.measureTextWidth(menu.title) ?? menu.title.length * 8) + 8;
      if (menu.id == id) {
        final menuW = menu.items.fold<int>(w.toInt(), (m, it) {
          final labelW = (font?.measureTextWidth(it.label) ?? it.label.length * 8) + 16;
          final sc = SciMenuItem.formatShortcut(it.shortcut);
          final scW = sc.isNotEmpty ? ((font?.measureTextWidth(sc) ?? sc.length * 8) + 16) : 0;
          final totalW = labelW + scW;
          return totalW > m ? totalW : m;
        });
        return Rect.fromLTWH(cx, 10, menuW.toDouble(), menu.items.length * 10.0);
      }
      cx += w;
    }
    return const Rect.fromLTWH(8, 10, 80, 40);
  }

  /// Returns whether [label] represents a menu separator line.
  ///
  /// In Sierra SCI0, dividing rules are authored as strings consisting solely
  /// of separator characters: dashes (`-`), exclamation marks (`!`), hashes (`#`),
  /// spaces (` `), or multilingual markers like `%G` (e.g. `--!`, `-!`, `---`, `###`).
  static bool isSeparatorLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return true;
    final withoutLang = trimmed.replaceAll(RegExp(r'%[a-zA-Z]'), '');
    return withoutLang.isEmpty ||
        withoutLang.split('').every((c) => c == '-' || c == '!' || c == '#' || c == ' ');
  }

  /// Parses Sierra `AddMenu` content (`label\`key:label2:…`).
  void addMenu(String title, String content) {
    final items = <SciMenuItem>[];
    final parts = content.split(':');
    for (final part in parts) {
      if (part.isEmpty) continue;
      final parsed = SciMenuItem.parseItemString(part);
      items.add(SciMenuItem(
        label: parsed.label,
        shortcut: parsed.shortcut,
        tag: parsed.tag,
        isSeparator: parsed.isSeparator,
      ));
    }
    menus.add(SciMenu(id: menus.length + 1, title: title, items: items));
  }

  /// Returns `(menuId, itemId)` of the first enabled item matching the key press,
  /// or null if no match.
  (int, int)? findItemMatchingKey(int key, int mod) {
    for (final menu in menus) {
      for (var i = 0; i < menu.items.length; i++) {
        final item = menu.items[i];
        if (item.matchesKey(key, mod)) {
          return (menu.id, i + 1);
        }
      }
    }
    return null;
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
          isSingleLine: true,
        ));
        x += w;
      }
    } else if (statusText.isNotEmpty) {
      controls.add(SciTextControl(
        rect: const Rect.fromLTWH(0, 1, 320, 9),
        text: statusText,
        colorPen: statusPen,
        colorBack: statusBack,
        font: font,
        isSingleLine: true,
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
        controls.add(SciFillControl(
          rect: Rect.fromLTWH(2, row.top + 4, drop.width - 4, 1),
          color: 7,
        ));
        continue;
      }
      final hi = (i + 1) == highlightedItemId;
      controls.add(SciTextControl(
        rect: row,
        text: item.checked ? '*${item.label}' : item.label,
        colorPen: hi ? 15 : 0,
        colorBack: hi ? 0 : 15,
        font: font,
        isSingleLine: true,
      ));
      final sc = SciMenuItem.formatShortcut(item.shortcut);
      if (sc.isNotEmpty) {
        controls.add(SciTextControl(
          rect: Rect.fromLTWH(row.left, row.top, row.width - 4, row.height),
          text: sc,
          colorPen: hi ? 15 : 0,
          colorBack: null,
          font: font,
          align: TextAlign.right,
          isSingleLine: true,
        ));
      }
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
