import 'package:flutter_agigame/domain/menu/agi_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgiMenu & AgiMenuItem Models', () {
    test('AgiMenuItem correctly detects separator rows', () {
      final sep1 = AgiMenuItem(text: '--------', controllerSlot: 99);
      final sep2 = AgiMenuItem(text: '  ------  ', controllerSlot: 99);
      final normal = AgiMenuItem(text: 'About <F1>', controllerSlot: 1);

      expect(sep1.isSeparator, isTrue);
      expect(sep2.isSeparator, isTrue);
      expect(normal.isSeparator, isFalse);
    });

    test('AgiMenu maintains items and selectedItem', () {
      final menu = AgiMenu(name: 'Sierra', column: 1);
      expect(menu.itemCount, 0);
      expect(menu.selectedItem, isNull);

      final item1 = AgiMenuItem(text: 'About', controllerSlot: 1);
      final item2 = AgiMenuItem(text: 'Help', controllerSlot: 2);
      menu.items.addAll([item1, item2]);

      expect(menu.itemCount, 2);
      expect(menu.selectedItem, item1);

      menu.selectedItemIndex = 1;
      expect(menu.selectedItem, item2);
    });
  });

  group('AgiMenuManager Lifecycle & Opcodes', () {
    late AgiMenuManager menuMgr;

    setUp(() {
      menuMgr = AgiMenuManager();
    });

    test('builds authentic menu structure and calculates columns', () {
      menuMgr.addMenu('Sierra');
      menuMgr.addMenuItem('About <F1>', 1);
      menuMgr.addMenuItem('Help <F2>', 2);

      menuMgr.addMenu('File');
      menuMgr.addMenuItem('Save <F5>', 3);
      menuMgr.addMenuItem('Restore <F7>', 4);
      menuMgr.addMenuItem('--------', 99);
      menuMgr.addMenuItem('Restart <F9>', 5);
      menuMgr.addMenuItem('Quit', 6);

      expect(menuMgr.menus.length, 2);
      expect(menuMgr.menus[0].name, 'Sierra');
      expect(menuMgr.menus[0].column, 1);
      expect(menuMgr.menus[0].items.length, 2);

      expect(menuMgr.menus[1].name, 'File');
      expect(menuMgr.menus[1].column, 1 + 'Sierra'.length + 1); // col 8
      expect(menuMgr.menus[1].items.length, 5);

      expect(menuMgr.isSubmitted, isFalse);
      expect(menuMgr.isAvailable, isFalse);

      menuMgr.submit();

      expect(menuMgr.isSubmitted, isTrue);
      expect(menuMgr.isAvailable, isTrue);
    });

    test('submit locks further additions', () {
      menuMgr.addMenu('Sierra');
      menuMgr.addMenuItem('About', 1);
      menuMgr.submit();

      menuMgr.addMenu('Extra');
      menuMgr.addMenuItem('ExtraItem', 10);

      expect(menuMgr.menus.length, 1);
      expect(menuMgr.menus[0].items.length, 1);
    });

    test('enables and disables items by controller slot', () {
      menuMgr.addMenu('File');
      menuMgr.addMenuItem('Save', 3);
      menuMgr.addMenuItem('Restore', 4);
      menuMgr.submit();

      expect(menuMgr.menus[0].items[0].isEnabled, isTrue);
      expect(menuMgr.menus[0].items[1].isEnabled, isTrue);

      menuMgr.disableItem(3);
      expect(menuMgr.menus[0].items[0].isEnabled, isFalse);
      expect(menuMgr.menus[0].items[1].isEnabled, isTrue);

      menuMgr.enableItem(3);
      expect(menuMgr.menus[0].items[0].isEnabled, isTrue);

      menuMgr.disableItem(3);
      menuMgr.disableItem(4);
      menuMgr.enableAllItems();
      expect(menuMgr.menus[0].items[0].isEnabled, isTrue);
      expect(menuMgr.menus[0].items[1].isEnabled, isTrue);
    });
  });

  group('AgiMenuManager Navigation & Selection', () {
    late AgiMenuManager menuMgr;

    setUp(() {
      menuMgr = AgiMenuManager();
      menuMgr.addMenu('Sierra');
      menuMgr.addMenuItem('About', 1);
      menuMgr.addMenuItem('Help', 2);

      menuMgr.addMenu('File');
      menuMgr.addMenuItem('Save', 3);
      menuMgr.addMenuItem('Restore', 4);
      menuMgr.addMenuItem('--------', 99);
      menuMgr.addMenuItem('Quit', 5);

      menuMgr.submit();
    });

    test('opens and closes menu', () {
      expect(menuMgr.isOpen, isFalse);

      menuMgr.openMenu();
      expect(menuMgr.isOpen, isTrue);
      expect(menuMgr.activeMenuIndex, 0);

      menuMgr.closeMenu();
      expect(menuMgr.isOpen, isFalse);

      menuMgr.openMenu(menuIndex: 1);
      expect(menuMgr.isOpen, isTrue);
      expect(menuMgr.activeMenuIndex, 1);
    });

    test('navigates left and right across categories', () {
      menuMgr.openMenu(menuIndex: 0);
      expect(menuMgr.activeMenuIndex, 0);

      menuMgr.navigateRight();
      expect(menuMgr.activeMenuIndex, 1);

      menuMgr.navigateRight();
      expect(menuMgr.activeMenuIndex, 0); // Wraps to first

      menuMgr.navigateLeft();
      expect(menuMgr.activeMenuIndex, 1); // Wraps to last
    });

    test('navigates up and down skipping separators', () {
      menuMgr.openMenu(menuIndex: 1); // File menu: Save (0), Restore (1), sep (2), Quit (3)
      expect(menuMgr.activeMenu!.selectedItemIndex, 0);

      menuMgr.navigateDown();
      expect(menuMgr.activeMenu!.selectedItemIndex, 1);

      menuMgr.navigateDown();
      expect(menuMgr.activeMenu!.selectedItemIndex, 3); // Skips index 2 separator!

      menuMgr.navigateDown();
      expect(menuMgr.activeMenu!.selectedItemIndex, 0); // Wraps around

      menuMgr.navigateUp();
      expect(menuMgr.activeMenu!.selectedItemIndex, 3); // Wraps around backwards, skipping separator
    });

    test('Home and End jump to first and last menu categories', () {
      menuMgr.openMenu(menuIndex: 0);
      menuMgr.navigateEnd();
      expect(menuMgr.activeMenuIndex, 1);

      menuMgr.navigateHome();
      expect(menuMgr.activeMenuIndex, 0);
    });

    test('PageUp and PageDown jump to first and last non-separator items', () {
      menuMgr.openMenu(menuIndex: 1);
      menuMgr.navigatePageDown();
      expect(menuMgr.activeMenu!.selectedItemIndex, 3); // Quit

      menuMgr.navigatePageUp();
      expect(menuMgr.activeMenu!.selectedItemIndex, 0); // Save
    });

    test('selecting enabled item triggers controller and closes menu', () {
      menuMgr.openMenu(menuIndex: 0);
      menuMgr.navigateDown(); // Help (ctl 2)
      final slot = menuMgr.selectCurrentItem();

      expect(slot, 2);
      expect(menuMgr.isOpen, isFalse);
    });

    test('selecting disabled item returns null without closing menu', () {
      menuMgr.disableItem(2);
      menuMgr.openMenu(menuIndex: 0);
      menuMgr.navigateDown(); // Help (ctl 2, disabled)

      final slot = menuMgr.selectCurrentItem();
      expect(slot, isNull);
      expect(menuMgr.isOpen, isTrue);
    });
  });
}
