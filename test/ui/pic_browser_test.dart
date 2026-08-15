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
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

class _TestVolumeManager extends VolumeManager {
  final Map<int, Uint8List> picMap;
  _TestVolumeManager(this.picMap);

  @override
  Uint8List getResource(DirEntry entry) {
    if (picMap.containsKey(entry.offset)) {
      return picMap[entry.offset]!;
    }
    throw ResourceNotPresentException('Not found in mock volume');
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry entry) async => getResource(entry);

  @override
  Uint8List getWordsData() => Uint8List.fromList([0, 0]);

  @override
  Uint8List getObjectsData() => Uint8List.fromList([
        3, 0, 16,
        3, 0, 1,
        98, 111, 111, 107, 0,
      ]);

  @override
  void close() {}
}

class _TestMetaData implements GameMetaData {
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
  testWidgets('PicBrowserScreen loads, displays picture, toggles modes, and interacts with UI', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final srcBytes = File('test/fixtures/srcbytes.bin').readAsBytesSync();

    final picDirBytes = Uint8List(18);
    picDirBytes.fillRange(0, 15, 0xFF);
    picDirBytes[15] = 0x00;
    picDirBytes[16] = 0x10;
    picDirBytes[17] = 0x00;

    final rdir = V2ResourceDirectory(
      logics: Uint8List(0),
      pics: picDirBytes,
      views: Uint8List(0),
      sounds: Uint8List(0),
    );

    final vmgr = _TestVolumeManager({0x1000: srcBytes});
    final meta = _TestMetaData();

    final loader = AgiResourceLoader.custom(
      meta: meta,
      rdir: rdir,
      vmgr: vmgr,
    );

    final container = ProviderContainer();
    final notifier = container.read(launcherProvider.notifier);
    notifier.state = notifier.state.copyWith(
      status: LauncherStatus.loaded,
      loader: loader,
      gameInfo: loader.toGameInfo(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: const PicBrowserScreen(initialPicNumber: 5),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title and elements
    expect(find.text('PIC BROWSER'), findsOneWidget);
    expect(find.text('PICTURE 5'), findsOneWidget);
    expect(find.byType(AgiPictureWidget), findsOneWidget);

    // Verify Display toggles
    expect(find.text('CRT Shader'), findsOneWidget);
    expect(find.text('Integer Scale'), findsOneWidget);
    expect(find.text('4:3 Ratio'), findsOneWidget);
    expect(find.text('Vector Replay'), findsOneWidget);

    // Toggle CRT Shader
    await tester.ensureVisible(find.text('CRT Shader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CRT Shader'));
    await tester.pumpAndSettle();

    // Toggle Integer Scale
    await tester.ensureVisible(find.text('Integer Scale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Integer Scale'));
    await tester.pumpAndSettle();

    // Switch to Priority Mode
    await tester.ensureVisible(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();

    // Switch to Control Mode
    await tester.ensureVisible(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();

    // Switch to Composited Mode
    await tester.ensureVisible(find.text('Composited'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Composited'));
    await tester.pumpAndSettle();

    // Toggle Vector Replay
    await tester.ensureVisible(find.text('Vector Replay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vector Replay'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Tap step backward
    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pumpAndSettle();
  });
}
