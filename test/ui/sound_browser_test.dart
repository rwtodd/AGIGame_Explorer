import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';

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
  Uint8List getWordsData() => Uint8List(54);

  @override
  Uint8List getObjectsData() => Uint8List.fromList([3, 0, 16, 3, 0, 1, 98, 111, 111, 107, 0]);

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
  late NullAudioSink mockSink;
  late AgiSoundPlayer mockPlayer;

  final soundRawData = Uint8List.fromList([
    8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
    149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
    160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
    0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
  ]);

  setUp(() {
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
      0x1000: soundRawData,
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

    mockSink = NullAudioSink();
    mockPlayer = AgiSoundPlayer(sink: mockSink);
  });

  tearDown(() {
    mockPlayer.dispose();
  });

  testWidgets('SoundBrowserScreen renders complete playback panel and timeline', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: SoundBrowserScreen(
            initialSoundNumber: 0,
            soundPlayer: mockPlayer,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Transport
    expect(find.text('SOUND BROWSER'), findsOneWidget);
    expect(find.text('SOUND #0'), findsOneWidget);
    expect(find.text('PLAYBACK'), findsOneWidget);
    expect(find.text('RENDERING METHOD'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Export WAV Audio (.wav)'), findsOneWidget);
  });

  testWidgets('SoundBrowserScreen toggles play, pause, and stop', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: SoundBrowserScreen(
            initialSoundNumber: 0,
            soundPlayer: mockPlayer,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Play
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(mockPlayer.isPlaying, true);
    expect(find.text('Pause'), findsOneWidget);

    // Tap Pause
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(mockPlayer.isPaused, true);
    expect(find.text('Play'), findsOneWidget);

    // Tap Stop
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(mockPlayer.isStopped, true);
  });

  testWidgets('SoundBrowserScreen disables play when MIDI or CSound method is selected', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AgiTheme.darkTheme,
          home: SoundBrowserScreen(
            initialSoundNumber: 0,
            soundPlayer: mockPlayer,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Select MIDI method
    await tester.tap(find.text('Tandy 3-Voice + Noise'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard MIDI File (SMF)').last);
    await tester.pumpAndSettle();

    // Verify play button is disabled and export shows MIDI
    expect(find.text('Export MIDI File (.mid)'), findsOneWidget);
    expect(find.text('Export Only'), findsOneWidget);

    // Select CSound method
    await tester.tap(find.text('Standard MIDI File (SMF)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CSound Score & Orchestra').last);
    await tester.pumpAndSettle();

    expect(find.text('Export CSound (.sco)'), findsOneWidget);
  });
}
