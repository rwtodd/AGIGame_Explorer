import 'dart:io';
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
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/objects_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/words_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/launcher_screen.dart';

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
        98, 111, 111, 107, 0, // 'book\0'
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
    final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();

    final dirBytes = Uint8List(3);
    dirBytes[0] = 0x00;
    dirBytes[1] = 0x10;
    dirBytes[2] = 0x00;

    final rdir = V2ResourceDirectory(
      logics: dirBytes,
      pics: dirBytes,
      views: dirBytes,
      sounds: dirBytes,
    );

    final vmgr = _MockVolumeManager({
      0x1000: srcBytes,
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

  testWidgets('LauncherScreen shows clickable metric tiles and navigates to browser', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const LauncherScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('GAME RESOURCES (CLICK TO EXPLORE)'), findsOneWidget);
    expect(find.text('PICTURE Rooms'), findsOneWidget);

    // Tap PICTURE Rooms tile
    await tester.ensureVisible(find.text('PICTURE Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PICTURE Rooms'));
    await tester.pumpAndSettle();

    expect(find.text('PIC BROWSER'), findsOneWidget);
  });

  testWidgets('ObjectsBrowserScreen renders objects and filters by search', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const ObjectsBrowserScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('OBJECTS BROWSER'), findsOneWidget);
    expect(find.text('#0'), findsOneWidget);
    expect(find.text('OBJECT #0'), findsOneWidget);
    expect(find.text('book'), findsWidgets);

    // Search query
    await tester.enterText(find.byType(TextField), 'book');
    await tester.pumpAndSettle();
    expect(find.text('#0'), findsOneWidget);
  });

  testWidgets('WordsBrowserScreen renders vocabulary dictionary', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const WordsBrowserScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('WORDS.TOK VOCABULARY'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('SoundBrowserScreen renders synthesizer bar and tracks', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const SoundBrowserScreen(initialSoundNumber: 0),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('SOUND BROWSER'), findsOneWidget);
    expect(find.text('Synth Mode: '), findsOneWidget);
    expect(find.text('Render & Export WAV'), findsOneWidget);
  });
}
