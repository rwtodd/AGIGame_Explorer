import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';

void main() {
  group('Pre-Launch Engine A/V Configuration Tests', () {
    test('AgiGameEngine retains pre-launch sound mode and synth parameters across game initialization and tick 0', () {
      final soundPlayer = AgiSoundPlayer();
      addTearDown(() => soundPlayer.dispose());

      final engine = AgiGameEngine(soundPlayer: soundPlayer);
      addTearDown(() => engine.dispose());

      const userAudio = AgiAudioSettings(
        soundMode: AgiSoundMode.ibmPc,
        waveform: WaveformType.square,
        enableReverb: false,
        reverbMix: 0.0,
        masterVolume: 0.50,
      );

      // Pre-configure audio prior to initialization
      engine.setSoundMode(userAudio.soundMode);
      engine.setSynthesizerConfig(userAudio.toSynthesizerConfig());

      expect(engine.soundMode, AgiSoundMode.ibmPc);
      expect(engine.synthesizerConfig.mode, PcmPlaybackMode.ibmPcSingleChannel);
      expect(engine.synthesizerConfig.masterVolume, 0.50);

      // Initialize game
      engine.initializeGame(startingRoom: 0);

      // Verify mode and synth config were not wiped during initialization
      expect(engine.soundMode, AgiSoundMode.ibmPc);
      expect(engine.synthesizerConfig.mode, PcmPlaybackMode.ibmPcSingleChannel);
      expect(engine.synthesizerConfig.masterVolume, 0.50);

      // Run cycle 0
      engine.tick();

      expect(engine.soundMode, AgiSoundMode.ibmPc);
      expect(engine.synthesizerConfig.mode, PcmPlaybackMode.ibmPcSingleChannel);
    });

    test('AgiGameEngine enhanced mode with DSP reverb is active from cycle 0', () {
      final soundPlayer = AgiSoundPlayer();
      addTearDown(() => soundPlayer.dispose());

      final engine = AgiGameEngine(soundPlayer: soundPlayer);
      addTearDown(() => engine.dispose());

      const userAudio = AgiAudioSettings(
        soundMode: AgiSoundMode.enhanced,
        waveform: WaveformType.pulseWidthModulation,
        enableReverb: true,
        reverbMix: 0.45,
        masterVolume: 0.85,
      );

      engine.setSoundMode(userAudio.soundMode);
      engine.setSynthesizerConfig(userAudio.toSynthesizerConfig());

      expect(engine.soundMode, AgiSoundMode.enhanced);
      expect(engine.synthesizerConfig.mode, PcmPlaybackMode.enhanced);
      expect(engine.synthesizerConfig.waveform, WaveformType.pulseWidthModulation);
      expect(engine.synthesizerConfig.enableReverb, isTrue);
      expect(engine.synthesizerConfig.reverbMix, 0.45);

      engine.initializeGame(startingRoom: 0);
      engine.tick();

      expect(engine.soundMode, AgiSoundMode.enhanced);
      expect(engine.synthesizerConfig.waveform, WaveformType.pulseWidthModulation);
      expect(engine.synthesizerConfig.enableReverb, isTrue);
      expect(engine.synthesizerConfig.reverbMix, 0.45);
    });
  });
}
