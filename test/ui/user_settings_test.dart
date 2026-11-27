import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
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
      expect(settings.display.renderMode, AgiPictureRenderMode.shaderComposited);

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

    test('sciMusicDevice defaults to legacyPsg, round-trips, and is'
        ' tolerant of old/unknown JSON', () {
      expect(const AgiUserSettings().audio.sciMusicDevice, SciMusicDevice.legacyPsg);

      const original = AgiAudioSettings(sciMusicDevice: SciMusicDevice.adLibOpl2);
      final json = original.toJson();
      expect(json['sciMusicDevice'], 'adLibOpl2');
      expect(
        AgiAudioSettings.fromJson(json).sciMusicDevice,
        SciMusicDevice.adLibOpl2,
      );

      // Pre-Stage-6b settings file: key missing -> legacy default.
      final legacyJson = Map<String, dynamic>.from(json)..remove('sciMusicDevice');
      expect(
        AgiAudioSettings.fromJson(legacyJson).sciMusicDevice,
        SciMusicDevice.legacyPsg,
      );

      // Unknown value from a newer build -> legacy default.
      final unknownJson = Map<String, dynamic>.from(json)
        ..['sciMusicDevice'] = 'adLibOpl3';
      expect(
        AgiAudioSettings.fromJson(unknownJson).sciMusicDevice,
        SciMusicDevice.legacyPsg,
      );

      // Sound Blaster (Stage 8) round-trips by name.
      const sb = AgiAudioSettings(sciMusicDevice: SciMusicDevice.soundBlaster);
      expect(sb.toJson()['sciMusicDevice'], 'soundBlaster');
      expect(
        AgiAudioSettings.fromJson(sb.toJson()).sciMusicDevice,
        SciMusicDevice.soundBlaster,
      );
    });

    test('FM settings round-trip by name and map through to config', () {
      const original = AgiAudioSettings(
        soundMode: AgiSoundMode.fm,
        fmPresetId: 'nearSquare',
        fmGain: 1.5,
        fmNoiseGain: 0.6,
        fmNoiseSource: AgiFmNoiseSource.off,
        voiceGains: [1.2, 0.8, 0.5],
        voicePans: [0.2, 0.8, 0.4],
      );
      final json = original.toJson();
      expect(json['soundMode'], 'fm');
      expect(json['fmPresetId'], 'nearSquare');
      expect(json['fmNoiseSource'], 'off');

      final restored = AgiAudioSettings.fromJson(json);
      expect(restored.soundMode, AgiSoundMode.fm);
      expect(restored.fmPresetId, 'nearSquare');
      expect(restored.fmGain, 1.5);
      expect(restored.fmNoiseGain, 0.6);
      expect(restored.fmNoiseSource, AgiFmNoiseSource.off);
      expect(restored.voiceGains, [1.2, 0.8, 0.5]);
      expect(restored.voicePans, [0.2, 0.8, 0.4]);

      final config = restored.toSynthesizerConfig();
      expect(config.mode, PcmPlaybackMode.fmPresets);
      expect(config.fmPresetId, 'nearSquare');
      expect(config.fmGain, 1.5);
      expect(config.fmNoiseGain, 0.6);
      expect(config.fmNoiseSource, AgiFmNoiseSource.off);
      expect(config.voice1Gain, 1.2);
      expect(config.voice2Gain, 0.8);
      expect(config.voice3Gain, 0.5);
      expect(config.voice1Pan, 0.2);
      expect(config.voice2Pan, 0.8);
      expect(config.voice3Pan, 0.4);
    });

    test('pre-Stage-9 JSON (no FM keys) loads FM defaults', () {
      final legacyJson = <String, dynamic>{
        'soundMode': 'pcJr',
        'waveform': 'square',
        'enableReverb': false,
        'reverbMix': 0.0,
        'masterVolume': 0.75,
      };
      final restored = AgiAudioSettings.fromJson(legacyJson);
      expect(restored.fmPresetId, 'neutralKeys');
      expect(restored.fmGain, 1.0);
      expect(restored.fmNoiseGain, 1.0);
      expect(restored.fmNoiseSource, AgiFmNoiseSource.tandy);
      expect(restored.voiceGains, [1.0, 1.0, 1.0]);
      expect(restored.voicePans, [0.35, 0.65, 0.50]);
    });

    test('unknown FM values and short lists are tolerant', () {
      final json = <String, dynamic>{
        'fmNoiseSource': 'adLibOpl3',
        'voiceGains': [0.5],
        'voicePans': 'nonsense',
      };
      final restored = AgiAudioSettings.fromJson(json);
      expect(restored.fmNoiseSource, AgiFmNoiseSource.tandy);
      expect(restored.voiceGains[0], 0.5);
      expect(restored.voiceGains[1], 1.0);
      expect(restored.voicePans, [0.35, 0.65, 0.50]);
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
