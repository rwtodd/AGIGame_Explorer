import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/logic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/objects_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';

class _MockVolumeManager extends VolumeManager {
  final Map<int, Uint8List> dataMap;
  _MockVolumeManager(this.dataMap);

  @override
  Uint8List getResource(DirEntry entry) {
    if (dataMap.containsKey(entry.offset)) {
      return dataMap[entry.offset]!;
    }
    throw ResourceNotPresentException('Not found in mock volume');
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry entry) async => getResource(entry);

  @override
  Uint8List getWordsData() {
    final bytes = Uint8List(54);
    bytes[0] = 0;
    bytes[1] = 52;
    bytes[52] = 0;
    bytes[53] = 0;
    return bytes;
  }

  @override
  Uint8List getObjectsData() => Uint8List.fromList([
        3, 0, 16,
        3, 0, 1,
        98, 111, 111, 107, 0,
      ]);

  @override
  void close() {}
}

class _MockMetaData implements GameMetaData {
  @override
  final double version = 2.089;
  @override
  final String versionString = '2.089';
  @override
  final String? prefix = null;
  @override
  final String gamePath = '/dummy';
  @override
  final Uint8List decryptionKey = Uint8List(0);
  @override
  bool get isV3 => false;
  @override
  bool get isBeforeV3 => true;
}

void main() {
  late AgiResourceLoader loader;
  late ProviderContainer container;

  setUp(() {
    final builder = BytesBuilder();
    builder.add([0x0B, 0x00]); // LE text offset = 11
    builder.add([0x65, 0x01, 0x16, 0x01, 0x1E, 0x01, 0x62, 0x01, 0x5C, 0x00, 0x00]); // bytecodes: print(%m1), call(1), load.view(1), load.sound(1), get(%i0), return
    builder.add([0x02]); // 2 messages
    builder.add([0x14, 0x00]); // end offset
    builder.add([0x06, 0x00]); // ptr 1
    builder.add([0x0C, 0x00]); // ptr 2
    final m1 = Uint8List.fromList(const [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00]); // 'Hello\0'
    final m2 = Uint8List.fromList(const [0x57, 0x6F, 0x72, 0x6C, 0x64, 0x00]); // 'World\0'
    CryptoUtils.decodeInPlace(m1, key: CryptoUtils.avisDurganKey);
    CryptoUtils.decodeInPlace(m2, key: CryptoUtils.avisDurganKey);
    builder.add(m1);
    builder.add(m2);
    final logicBytes = builder.toBytes();

    final dirBytes = Uint8List(6);
    dirBytes[0] = 0x00;
    dirBytes[1] = 0x10;
    dirBytes[2] = 0x00;
    dirBytes[3] = 0x00;
    dirBytes[4] = 0x20;
    dirBytes[5] = 0x00;

    final rdir = V2ResourceDirectory(
      logics: dirBytes,
      pics: dirBytes,
      views: dirBytes,
      sounds: dirBytes,
    );

    final vmgr = _MockVolumeManager({
      0x1000: logicBytes,
      0x2000: logicBytes,
    });

    final meta = _MockMetaData();
    loader = AgiResourceLoader.custom(
      meta: meta,
      rdir: rdir,
      vmgr: vmgr,
    );

    container = ProviderContainer();
    final notifier = container.read(launcherProvider.notifier);
    notifier.state = notifier.state.copyWith(
      status: LauncherStatus.loaded,
      loader: loader,
      gameInfo: loader.toGameInfo(),
    );
  });

  tearDown(() {
    container.dispose();
  });

  testWidgets('LogicBrowserScreen renders disassembly code without top message dump', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LOGIC BROWSER'), findsOneWidget);
    expect(find.text('Disassembly Code'), findsOneWidget);
    expect(find.text('Message Strings'), findsOneWidget);

    // Verify disassembly code instructions are visible
    expect(find.textContaining('call('), findsWidgets);
    expect(find.textContaining('return'), findsWidgets);
  });

  testWidgets('LogicBrowserScreen tab switching preserves scroll controllers', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Message Strings tab
    await tester.tap(find.text('Message Strings'));
    await tester.pumpAndSettle();

    // Switch back to Disassembly Code tab
    await tester.tap(find.text('Disassembly Code'));
    await tester.pumpAndSettle();

    expect(find.byKey(const PageStorageKey('disassembly_list')), findsOneWidget);
  });

  testWidgets('LogicBrowserScreen search filters and double click clears filter', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    // Enter search filter
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'call');
    await tester.pumpAndSettle();

    // Find filtered line item containing 'call'
    final lineItem = find.textContaining('call(');
    expect(lineItem, findsWidgets);

    // Double-tap on the matching line
    await tester.tap(lineItem.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(lineItem.first);
    await tester.pumpAndSettle();

    // Search query should be cleared and full view restored
    final textFieldWidget = tester.widget<TextField>(searchField);
    expect(textFieldWidget.controller?.text, isEmpty);
  });

  testWidgets('LogicBrowserScreen hyper-linking to scripts pushes history with Home/Back buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LOGIC 0'), findsOneWidget);
    // Initially back button is 'Back to Overview'
    expect(find.byTooltip('Back to Overview'), findsOneWidget);

    // Tap hyper-link chip [LOGIC 1]
    final logicChip = find.descendant(
      of: find.byTooltip('Navigate to LOGIC 1'),
      matching: find.byType(GestureDetector),
    );
    expect(logicChip, findsWidgets);
    await tester.tap(logicChip.first);
    await tester.pumpAndSettle();

    // Now on LOGIC 1: both 'Back to LOGIC 0' and 'Exit to Overview' are present
    expect(find.byTooltip('Back to LOGIC 0'), findsOneWidget);
    expect(find.byTooltip('Exit to Overview'), findsOneWidget);

    // Tapping 'Back to LOGIC 0' restores LOGIC 0
    await tester.tap(find.byTooltip('Back to LOGIC 0'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIC 0'), findsOneWidget);
    expect(find.byTooltip('Back to Overview'), findsOneWidget);

    // Manual navigation via Next chevron resets history
    await tester.tap(find.byTooltip('Next Script'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIC 1'), findsWidgets);
    expect(find.byTooltip('Back to Overview'), findsOneWidget);
  });

  testWidgets('LogicBrowserScreen Find in Disassembly Code jumps to instruction with highlight and clears filter', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Message Strings tab
    await tester.tap(find.text('Message Strings'));
    await tester.pumpAndSettle();

    // Type in search filter
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Hello');
    await tester.pumpAndSettle();

    // Tap "Find in Disassembly Code"
    final findBtn = find.byTooltip('Find in Disassembly Code');
    expect(findBtn, findsWidgets);
    await tester.tap(findBtn.first);
    await tester.pumpAndSettle();

    // Tab 0 should be active, filter cleared, and instruction visible
    expect(find.byKey(const PageStorageKey('disassembly_list')), findsOneWidget);
    final textFieldWidget = tester.widget<TextField>(searchField);
    expect(textFieldWidget.controller?.text, isEmpty);
    expect(find.textContaining('print('), findsWidgets);
  });

  testWidgets('LogicBrowserScreen renders cross-reference chips for views, sounds, and objects', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LogicBrowserScreen(initialLogicNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byTooltip('Open VIEW 1 in View Browser'), findsOneWidget);
    expect(find.byTooltip('Open SOUND 1 in Sound Browser'), findsOneWidget);
    expect(find.byTooltip('Open item %i0 in Inventory/Objects Browser'), findsOneWidget);

    // Tap VIEW chip to open ViewBrowserScreen
    await tester.tap(find.byTooltip('Open VIEW 1 in View Browser'));
    await tester.pumpAndSettle();
    expect(find.byType(ViewBrowserScreen), findsOneWidget);

    // Pop back to LogicBrowserScreen
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(LogicBrowserScreen), findsOneWidget);

    // Tap SOUND chip to open SoundBrowserScreen
    await tester.tap(find.byTooltip('Open SOUND 1 in Sound Browser'));
    await tester.pumpAndSettle();
    expect(find.byType(SoundBrowserScreen), findsOneWidget);

    // Pop back to LogicBrowserScreen
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(LogicBrowserScreen), findsOneWidget);

    // Tap Objects chip to open ObjectsBrowserScreen
    await tester.tap(find.byTooltip('Open item %i0 in Inventory/Objects Browser'));
    await tester.pumpAndSettle();
    expect(find.byType(ObjectsBrowserScreen), findsOneWidget);
  });
}
