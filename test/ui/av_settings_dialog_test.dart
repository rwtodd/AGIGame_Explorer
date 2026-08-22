import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/screens/launcher_screen.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/av_settings_dialog.dart';

void main() {
  group('AvSettingsDialog & Pre-Launch Configuration Tests', () {
    testWidgets('renders AvSettingsDialog, switches tabs, and mutates audio settings',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                home: Scaffold(
                  body: AvSettingsDialog(),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and Audio Tab
      expect(find.text('AUDIO-VISUAL CONFIGURATION'), findsOneWidget);
      expect(find.text('PCjr / Tandy 1000 3-Voice + Noise'), findsOneWidget);
      expect(find.text('IBM PC 1-Channel Internal Speaker'), findsOneWidget);
      expect(find.text('Enhanced Mode (Modern DSP Synthesizer)'), findsOneWidget);
      expect(find.text('PLAY TEST SOUND'), findsOneWidget);

      // Select Enhanced mode
      final enhancedTile = find.text('Enhanced Mode (Modern DSP Synthesizer)');
      await tester.ensureVisible(enhancedTile);
      await tester.tap(enhancedTile);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).audio.soundMode, AgiSoundMode.enhanced);
      expect(find.text('ENHANCED WAVEFORM'), findsOneWidget);
      expect(find.text('DSP ROOM REVERB'), findsOneWidget);

      // Tap PWM Waveform chip
      final pwmChip = find.text('PWM');
      await tester.ensureVisible(pwmChip);
      await tester.tap(pwmChip);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).audio.waveform, WaveformType.pulseWidthModulation);

      // Tap Cathedral (60%) Reverb preset
      final cathPreset = find.text('Cathedral (60%)');
      await tester.ensureVisible(cathPreset);
      await tester.tap(cathPreset);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).audio.enableReverb, isTrue);
      expect(container.read(settingsProvider).audio.reverbMix, 0.60);

      // Switch to Video & Display tab
      await tester.tap(find.text('Video & Display'));
      await tester.pumpAndSettle();

      expect(find.text('4:3 CRT Aspect Ratio Correction'), findsOneWidget);
      expect(find.text('Strict Integer Scaling'), findsOneWidget);
      expect(find.text('CRT Scanlines & Phosphor Shader'), findsOneWidget);
      expect(find.text('Pixel Grid Overlay'), findsOneWidget);
      expect(find.text('Render Black Text Backgrounds'), findsOneWidget);
      expect(find.text('DEFAULT RENDER MODE'), findsOneWidget);

      // Toggle CRT scanlines on
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(5));

      // Switch 0 = Aspect ratio (starts true)
      // Switch 1 = Strict integer (starts false)
      // Switch 2 = CRT Scanlines (starts false)
      // Switch 3 = Pixel Grid (starts false)
      // Switch 4 = Render Black Text Backgrounds (starts false)
      await tester.ensureVisible(switches.at(2));
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).display.showCrtShader, isTrue);

      // Select Priority Buffer render mode
      final priorityBtn = find.text('Priority Buffer');
      await tester.ensureVisible(priorityBtn);
      await tester.tap(priorityBtn);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).display.renderMode, AgiPictureRenderMode.priorityMap);
    });

    testWidgets('LauncherScreen displays A/V configure button and opens AvSettingsDialog',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LauncherScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header A/V Settings button
      expect(find.text('A/V Settings'), findsOneWidget);

      // Tap header A/V settings button
      await tester.tap(find.text('A/V Settings'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.byType(AvSettingsDialog), findsOneWidget);
      expect(find.text('AUDIO-VISUAL CONFIGURATION'), findsOneWidget);

      // Close dialog via DONE button
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      expect(find.byType(AvSettingsDialog), findsNothing);
    });

    testWidgets('GameScreen initializes AgiGameEngine and display properties with custom pre-launch settings from cycle 0',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final engine = AgiGameEngine();
      addTearDown(() => engine.dispose());

      final customSettings = const AgiUserSettings(
        display: AgiDisplaySettings(
          showCrtShader: true,
          showPixelGrid: true,
          correctAspectRatio: false,
          strictIntegerScaling: true,
          renderMode: AgiPictureRenderMode.flatVisual,
        ),
        audio: AgiAudioSettings(
          soundMode: AgiSoundMode.enhanced,
          waveform: WaveformType.sawtooth,
          enableReverb: true,
          reverbMix: 0.30,
          masterVolume: 0.90,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: GameScreen(
              engine: engine,
              initialSettings: customSettings,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(GameScreen), findsOneWidget);

      // Verify engine received pre-launch configuration
      expect(engine.soundMode, AgiSoundMode.enhanced);
      expect(engine.synthesizerConfig.waveform, WaveformType.sawtooth);
      expect(engine.synthesizerConfig.enableReverb, isTrue);
      expect(engine.synthesizerConfig.reverbMix, 0.30);
      expect(engine.synthesizerConfig.masterVolume, 0.90);

      // Open the in-game slideout sidebar to inspect audio tab (in Enhanced mode icon is auto_awesome)
      await tester.tap(find.byIcon(Icons.auto_awesome).first);
      await tester.pumpAndSettle();

      // Enhanced mode should be selected from cycle 0
      expect(find.text('Enhanced Mode'), findsOneWidget);
      expect(find.text('Sawtooth'), findsOneWidget);
    });
  });
}
