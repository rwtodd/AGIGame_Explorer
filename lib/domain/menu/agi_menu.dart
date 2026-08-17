/// Represents a single item in an AGI dropdown menu.
class AgiMenuItem {
  final String text;
  final int controllerSlot;
  bool isEnabled;
  final int row;
  final int column;

  AgiMenuItem({
    required this.text,
    required this.controllerSlot,
    this.isEnabled = true,
    this.row = 0,
    this.column = 0,
  });

  /// Returns true if this menu item is a visual separator line (e.g. "--------").
  bool get isSeparator {
    final trimmed = text.trim();
    return trimmed.isNotEmpty && trimmed.split('').every((c) => c == '-');
  }

  /// Copy with optional field replacements.
  AgiMenuItem copyWith({
    String? text,
    int? controllerSlot,
    bool? isEnabled,
    int? row,
    int? column,
  }) {
    return AgiMenuItem(
      text: text ?? this.text,
      controllerSlot: controllerSlot ?? this.controllerSlot,
      isEnabled: isEnabled ?? this.isEnabled,
      row: row ?? this.row,
      column: column ?? this.column,
    );
  }
}

/// Represents a top-level menu category (column) in the AGI menu bar (e.g. "Sierra", "File", "Action").
class AgiMenu {
  final String name;
  final int column;
  final int row;
  final List<AgiMenuItem> items;
  int selectedItemIndex;
  int maxItemTextLength;

  AgiMenu({
    required this.name,
    required this.column,
    this.row = 0,
    List<AgiMenuItem>? items,
    this.selectedItemIndex = 0,
    this.maxItemTextLength = 0,
  }) : items = items ?? [];

  /// Number of items in this menu category.
  int get itemCount => items.length;

  /// Returns currently selected menu item, if any.
  AgiMenuItem? get selectedItem {
    if (items.isEmpty) return null;
    final clamped = selectedItemIndex.clamp(0, items.length - 1);
    return items[clamped];
  }
}

/// Manager responsible for building, state tracking, and navigating AGI menus.
class AgiMenuManager {
  final List<AgiMenu> _menus = [];
  bool _isSubmitted = false;
  bool _isOpen = false;
  int _activeMenuIndex = 0;

  int _setupMenuColumn = 1;
  int _setupMenuItemColumn = 1;

  /// All registered menus.
  List<AgiMenu> get menus => List.unmodifiable(_menus);

  /// Whether the menu definition has been submitted and locked by logic scripts.
  bool get isSubmitted => _isSubmitted;

  /// True if menus have been submitted and are available to open.
  bool get isAvailable => _isSubmitted && _menus.isNotEmpty;

  /// Whether the interactive menu bar and dropdown overlay is actively open.
  bool get isOpen => _isOpen;

  /// Current active top-level menu column index.
  int get activeMenuIndex => _activeMenuIndex;

  /// Currently active menu column.
  AgiMenu? get activeMenu {
    if (_menus.isEmpty) return null;
    final clamped = _activeMenuIndex.clamp(0, _menus.length - 1);
    return _menus[clamped];
  }

  /// Clears all menus and resets state.
  void reset() {
    _menus.clear();
    _isSubmitted = false;
    _isOpen = false;
    _activeMenuIndex = 0;
    _setupMenuColumn = 1;
    _setupMenuItemColumn = 1;
  }

  /// Adds a new top-level menu heading (called by `set.menu(m)` opcode 156).
  void addMenu(String name) {
    if (_isSubmitted) return;

    var menuName = name;
    if (_setupMenuColumn + menuName.length > 40) {
      final available = 40 - _setupMenuColumn;
      if (available > 0) {
        menuName = menuName.substring(0, available);
      }
    }

    final menu = AgiMenu(
      name: menuName,
      column: _setupMenuColumn,
      row: 0,
    );
    _menus.add(menu);

    _setupMenuColumn += menuName.length + 1;
    _setupMenuItemColumn = menu.column;
  }

  /// Adds an item to the current active menu heading (called by `set.menu.item(m, ctl)` opcode 157).
  void addMenuItem(String text, int controllerSlot) {
    if (_isSubmitted || _menus.isEmpty) return;

    final currentMenu = _menus.last;
    final itemTextLength = text.length;

    if (currentMenu.maxItemTextLength < itemTextLength) {
      currentMenu.maxItemTextLength = itemTextLength;
    }

    if (currentMenu.items.isEmpty) {
      if (itemTextLength + currentMenu.column < 39) {
        _setupMenuItemColumn = currentMenu.column;
      } else {
        _setupMenuItemColumn = (39 - itemTextLength).clamp(1, 39);
      }
    }

    final row = 2 + currentMenu.items.length;
    final item = AgiMenuItem(
      text: text,
      controllerSlot: controllerSlot,
      isEnabled: true,
      row: row,
      column: _setupMenuItemColumn,
    );

    currentMenu.items.add(item);
  }

  /// Submits and finalizes the menu structure (called by `submit.menu()` opcode 158).
  void submit() {
    if (_menus.isEmpty) return;
    _isSubmitted = true;
    _activeMenuIndex = 0;
    for (final menu in _menus) {
      menu.selectedItemIndex = 0;
    }
  }

  /// Enables a menu item by its associated controller ID (opcode 159).
  void enableItem(int controllerSlot) {
    _setItemEnabled(controllerSlot, true);
  }

  /// Disables a menu item by its associated controller ID (opcode 160).
  void disableItem(int controllerSlot) {
    _setItemEnabled(controllerSlot, false);
  }

  void _setItemEnabled(int controllerSlot, bool enabled) {
    for (final menu in _menus) {
      for (final item in menu.items) {
        if (item.controllerSlot == controllerSlot) {
          item.isEnabled = enabled;
        }
      }
    }
  }

  /// Enables all items across all menus (used during restart and restore).
  void enableAllItems() {
    for (final menu in _menus) {
      for (final item in menu.items) {
        item.isEnabled = true;
      }
    }
  }

  /// Opens the menu system.
  void openMenu({int? menuIndex}) {
    if (!_isSubmitted || _menus.isEmpty) return;
    _isOpen = true;
    if (menuIndex != null) {
      _activeMenuIndex = menuIndex.clamp(0, _menus.length - 1);
    } else {
      _activeMenuIndex = _activeMenuIndex.clamp(0, _menus.length - 1);
    }
    _ensureSelectableItem();
  }

  /// Closes the menu system.
  void closeMenu() {
    _isOpen = false;
  }

  /// Moves active menu to the left (wrapping around).
  void navigateLeft() {
    if (!_isOpen || _menus.isEmpty) return;
    _activeMenuIndex = (_activeMenuIndex - 1 + _menus.length) % _menus.length;
    _ensureSelectableItem();
  }

  /// Moves active menu to the right (wrapping around).
  void navigateRight() {
    if (!_isOpen || _menus.isEmpty) return;
    _activeMenuIndex = (_activeMenuIndex + 1) % _menus.length;
    _ensureSelectableItem();
  }

  /// Moves selection up within current dropdown menu.
  void navigateUp() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return;

    int newIndex = menu.selectedItemIndex;
    final total = menu.items.length;
    for (int i = 0; i < total; i++) {
      newIndex = (newIndex - 1 + total) % total;
      if (!menu.items[newIndex].isSeparator) {
        menu.selectedItemIndex = newIndex;
        break;
      }
    }
  }

  /// Moves selection down within current dropdown menu.
  void navigateDown() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return;

    int newIndex = menu.selectedItemIndex;
    final total = menu.items.length;
    for (int i = 0; i < total; i++) {
      newIndex = (newIndex + 1) % total;
      if (!menu.items[newIndex].isSeparator) {
        menu.selectedItemIndex = newIndex;
        break;
      }
    }
  }

  /// Selects first item in current menu (PageUp).
  void navigatePageUp() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return;
    for (int i = 0; i < menu.items.length; i++) {
      if (!menu.items[i].isSeparator) {
        menu.selectedItemIndex = i;
        break;
      }
    }
  }

  /// Selects last item in current menu (PageDown).
  void navigatePageDown() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return;
    for (int i = menu.items.length - 1; i >= 0; i--) {
      if (!menu.items[i].isSeparator) {
        menu.selectedItemIndex = i;
        break;
      }
    }
  }

  /// Selects first menu column (Home).
  void navigateHome() {
    if (!_isOpen || _menus.isEmpty) return;
    _activeMenuIndex = 0;
    _ensureSelectableItem();
  }

  /// Selects last menu column (End).
  void navigateEnd() {
    if (!_isOpen || _menus.isEmpty) return;
    _activeMenuIndex = _menus.length - 1;
    _ensureSelectableItem();
  }

  /// Sets the active menu index directly.
  void setActiveMenu(int index) {
    if (index >= 0 && index < _menus.length) {
      _activeMenuIndex = index;
      _ensureSelectableItem();
    }
  }

  /// Sets selected item index for active menu.
  void setSelectedItemIndex(int index) {
    final menu = activeMenu;
    if (menu != null && index >= 0 && index < menu.items.length) {
      if (!menu.items[index].isSeparator) {
        menu.selectedItemIndex = index;
      }
    }
  }

  /// Selects current item and returns its controller slot if enabled, or null otherwise.
  int? selectCurrentItem() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return null;

    final item = menu.selectedItem;
    if (item == null || item.isSeparator || !item.isEnabled) {
      return null;
    }

    closeMenu();
    return item.controllerSlot;
  }

  void _ensureSelectableItem() {
    final menu = activeMenu;
    if (menu == null || menu.items.isEmpty) return;
    if (menu.selectedItem != null && menu.selectedItem!.isSeparator) {
      navigateDown();
    }
  }
}
