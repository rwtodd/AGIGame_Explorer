import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_fm_adapter.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/av_settings_dialog.dart';
import 'package:flutter_agigame/ui/widgets/sidebar_slideout_panel.dart';

void main() {
  group('Stage 9 FM presets UI', () {
    testWidgets(
      'sidebar shows FM tile, selects AgiSoundMode.fm, and edits FM config',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final engine = AgiGameEngine();
        addTearDown(() => engine.dispose());

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  home: Scaffold(
                    // Mirror GameScreen: rebuild the panel on engine changes.
                    body: ListenableBuilder(
                      listenable: engine,
                      builder: (context, _) => SidebarSlideoutPanel(
                        isOpen: true,
                        activeTab: SidebarPanelTab.audio,
                        engine: engine,
                        session: engine,
                        onTabChanged: (_) {},
                        onClose: () {},
                        showCrtShader: false,
                        onCrtShaderChanged: (_) {},
                        showPixelGrid: false,
                        onPixelGridChanged: (_) {},
                        renderBlackTextBackgrounds: false,
                        onRenderBlackTextBackgroundsChanged: (_) {},
                        correctAspectRatio: true,
                        onAspectRatioChanged: (_) {},
                        strictIntegerScaling: false,
                        onStrictIntegerScalingChanged: (_) {},
                        renderMode: AgiPictureRenderMode.shaderComposited,
                        onRenderModeChanged: (_) {},
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('FM Presets (OPL2)'), findsOneWidget);
        expect(find.text('FM PRESETS'), findsNothing);

        await tester.ensureVisible(find.text('FM Presets (OPL2)'));
        await tester.tap(find.text('FM Presets (OPL2)'));
        await tester.pumpAndSettle();

        expect(engine.soundMode, AgiSoundMode.fm);
        expect(
          container.read(settingsProvider).audio.soundMode,
          AgiSoundMode.fm,
        );
        expect(find.text('FM PRESETS'), findsOneWidget);
        expect(find.text('FM Gain'), findsOneWidget);
        expect(find.text('Noise Gain'), findsOneWidget);
        expect(find.text('V1'), findsOneWidget);
        expect(find.text('V2'), findsOneWidget);
        expect(find.text('V3'), findsOneWidget);

        // One chip per kAgiFmPresets entry.
        for (final preset in kAgiFmPresets) {
          expect(find.text(preset.displayName), findsOneWidget);
        }

        await tester.ensureVisible(find.text('Bright Brass'));
        await tester.tap(find.text('Bright Brass'));
        await tester.pumpAndSettle();

        expect(
          container.read(settingsProvider).audio.fmPresetId,
          'brightBrass',
        );
        expect(engine.synthesizerConfig.fmPresetId, 'brightBrass');

        // First slider in the FM section is FM Gain; drag it left.
        final fmGainSlider = find.byType(Slider).first;
        await tester.ensureVisible(fmGainSlider);
        await tester.drag(fmGainSlider, const Offset(-40, 0));
        await tester.pumpAndSettle();

        expect(
          container.read(settingsProvider).audio.fmGain,
          isNot(closeTo(1.0, 0.001)),
        );
        expect(engine.synthesizerConfig.fmGain, isNot(closeTo(1.0, 0.001)));
      },
    );

    testWidgets('AV dialog shows FM option and edits preset + gain', (
      tester,
    ) async {
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
                home: Scaffold(body: AvSettingsDialog()),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FM Presets (OPL2)'), findsOneWidget);
      expect(find.text('FM PRESET'), findsNothing);

      await tester.ensureVisible(find.text('FM Presets (OPL2)'));
      await tester.tap(find.text('FM Presets (OPL2)'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).audio.soundMode, AgiSoundMode.fm);
      expect(find.text('FM PRESET'), findsOneWidget);
      expect(find.text('FM Gain'), findsOneWidget);

      for (final preset in kAgiFmPresets) {
        expect(find.text(preset.displayName), findsOneWidget);
      }

      await tester.ensureVisible(find.text('Soft Organ'));
      await tester.tap(find.text('Soft Organ'));
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).audio.fmPresetId, 'softOrgan');

      // First slider is FM Gain.
      final fmGainSlider = find.byType(Slider).first;
      await tester.ensureVisible(fmGainSlider);
      await tester.drag(fmGainSlider, const Offset(-40, 0));
      await tester.pumpAndSettle();

      expect(
        container.read(settingsProvider).audio.fmGain,
        isNot(closeTo(1.0, 0.001)),
      );
    });
  });
}
