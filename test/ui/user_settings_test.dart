import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  group('AgiUserSettings & Persistence Tests', () {
    test('default settings have sensible AGI defaults', () {
      const settings = AgiUserSettings();
      expect(settings.display.correctAspectRatio, isTrue);
      expect(settings.display.strictIntegerScaling, isFalse);
      expect(settings.display.showCrtShader, isFalse);
      expect(settings.display.showPixelGrid, isFalse);
      expect(settings.display.renderMode, AgiPictureRenderMode.compositedSlices);

      expect(settings.audio.soundMode, AgiSoundMode.pcJr);
      expect(settings.audio.waveform, WaveformType.square);
      expect(settings.audio.enableReverb, isFalse);
      expect(settings.audio.reverbMix, 0.0);
      expect(settings.audio.masterVolume, 0.75);
    });

    test('serializes and deserializes AgiUserSettings to/from JSON round-trip', () {
      const original = AgiUserSettings(
        display: AgiDisplaySettings(
          correctAspectRatio: false,
          strictIntegerScaling: true,
          showCrtShader: true,
          showPixelGrid: true,
          renderMode: AgiPictureRenderMode.priorityMap,
        ),
        audio: AgiAudioSettings(
          soundMode: AgiSoundMode.enhanced,
          waveform: WaveformType.pulseWidthModulation,
          enableReverb: true,
          reverbMix: 0.35,
          masterVolume: 0.90,
        ),
      );

      final json = original.toJson();
      final restored = AgiUserSettings.fromJson(json);

      expect(restored.display.correctAspectRatio, isFalse);
      expect(restored.display.strictIntegerScaling, isTrue);
      expect(restored.display.showCrtShader, isTrue);
      expect(restored.display.showPixelGrid, isTrue);
      expect(restored.display.renderMode, AgiPictureRenderMode.priorityMap);

      expect(restored.audio.soundMode, AgiSoundMode.enhanced);
      expect(restored.audio.waveform, WaveformType.pulseWidthModulation);
      expect(restored.audio.enableReverb, isTrue);
      expect(restored.audio.reverbMix, 0.35);
      expect(restored.audio.masterVolume, 0.90);
    });

    test('toSynthesizerConfig maps sound modes and DSP correctly', () {
      const ibmSettings = AgiAudioSettings(soundMode: AgiSoundMode.ibmPc);
      expect(ibmSettings.toSynthesizerConfig().mode, PcmPlaybackMode.ibmPcSingleChannel);

      const pcjrSettings = AgiAudioSettings(soundMode: AgiSoundMode.pcJr);
      expect(pcjrSettings.toSynthesizerConfig().mode, PcmPlaybackMode.tandy3VoiceNoise);

      const enhancedSettings = AgiAudioSettings(
        soundMode: AgiSoundMode.enhanced,
        waveform: WaveformType.sawtooth,
        enableReverb: true,
        reverbMix: 0.25,
        masterVolume: 0.85,
      );
      final synth = enhancedSettings.toSynthesizerConfig();
      expect(synth.mode, PcmPlaybackMode.enhanced);
      expect(synth.waveform, WaveformType.sawtooth);
      expect(synth.enableReverb, isTrue);
      expect(synth.reverbMix, 0.25);
      expect(synth.masterVolume, 0.85);
    });

    test('SettingsNotifier persists mutations to disk and reloads', () async {
      final tempDir = Directory.systemTemp.createTempSync('agi_settings_test');
      final configFile = File('${tempDir.path}/test_settings.json');

      try {
        final notifier = SettingsNotifier(configFile: configFile);
        expect(notifier.state.display.showCrtShader, isFalse);

        notifier.updateDisplay(
          showCrtShader: true,
          correctAspectRatio: false,
          strictIntegerScaling: true,
        );
        notifier.setSoundMode(AgiSoundMode.enhanced);
        notifier.setSynthesizerConfig(
          const SynthesizerConfig(
            mode: PcmPlaybackMode.enhanced,
            waveform: WaveformType.sine,
            enableReverb: true,
            reverbMix: 0.40,
            masterVolume: 0.65,
          ),
        );

        await notifier.saveSettings();
        expect(configFile.existsSync(), isTrue);

        // Create a new notifier reading the same file
        final secondNotifier = SettingsNotifier(configFile: configFile);
        await secondNotifier.loadSettings();

        expect(secondNotifier.state.display.showCrtShader, isTrue);
        expect(secondNotifier.state.display.correctAspectRatio, isFalse);
        expect(secondNotifier.state.display.strictIntegerScaling, isTrue);
        expect(secondNotifier.state.audio.soundMode, AgiSoundMode.enhanced);
        expect(secondNotifier.state.audio.waveform, WaveformType.sine);
        expect(secondNotifier.state.audio.enableReverb, isTrue);
        expect(secondNotifier.state.audio.reverbMix, 0.40);
        expect(secondNotifier.state.audio.masterVolume, 0.65);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
