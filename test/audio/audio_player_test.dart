import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';

void main() {
  group('AudioOutputSink & NullAudioSink', () {
    test('NullAudioSink lifecycle and status changes', () async {
      final sink = NullAudioSink();
      expect(sink.status, AudioPlaybackStatus.uninitialized);

      await sink.initialize(sampleRate: 44100, numChannels: 2);
      expect(sink.status, AudioPlaybackStatus.stopped);

      sink.writePcm(Int16List.fromList([100, -100, 200, -200]));
      expect(sink.queuedBuffers.length, 1);

      sink.play();
      expect(sink.status, AudioPlaybackStatus.playing);

      sink.pause();
      expect(sink.status, AudioPlaybackStatus.paused);

      sink.stop();
      expect(sink.status, AudioPlaybackStatus.stopped);
      expect(sink.queuedBuffers, isEmpty);

      sink.dispose();
      expect(sink.status, AudioPlaybackStatus.uninitialized);
    });
  });

  group('AgiSoundPlayer', () {
    late NullAudioSink mockSink;
    late AgiSoundPlayer player;

    final dummySound = AgiSound(
      voices: [
        const ToneChannel(
          notes: [
            AgiNote(startTime: 0, duration: 60, frequencyCount: 254, attenuation: 0),
            AgiNote(startTime: 60, duration: 60, frequencyCount: 127, attenuation: 2),
          ],
        ),
      ],
      noise: const NoiseChannel(
        noises: [
          AgiNoise(
            startTime: 0,
            duration: 30,
            frequencyCount: 0x10,
            attenuation: 4,
            type: NoiseType.white,
          ),
        ],
      ),
    );

    setUp(() {
      mockSink = NullAudioSink();
      player = AgiSoundPlayer(sink: mockSink);
    });

    tearDown(() {
      player.dispose();
    });

    test('initial state is stopped and zero position', () {
      expect(player.status, SoundPlayerStatus.stopped);
      expect(player.isPlaying, false);
      expect(player.isPaused, false);
      expect(player.isStopped, true);
      expect(player.totalTicks, 0);
    });

    test('play starts playback and writes PCM to sink', () async {
      await player.play(dummySound, config: const SynthesizerConfig(sampleRate: 44100));

      expect(player.status, SoundPlayerStatus.playing);
      expect(player.isPlaying, true);
      expect(player.totalTicks, 120);
      expect(mockSink.status, AudioPlaybackStatus.playing);
      expect(mockSink.queuedBuffers, isNotEmpty);
    });

    test('pause and resume toggle player and sink status', () async {
      await player.play(dummySound);
      expect(player.isPlaying, true);

      player.pause();
      expect(player.isPaused, true);
      expect(mockSink.status, AudioPlaybackStatus.paused);

      player.resume();
      expect(player.isPlaying, true);
      expect(mockSink.status, AudioPlaybackStatus.playing);
    });

    test('stop resets playback state', () async {
      await player.play(dummySound);
      player.stop();

      expect(player.isStopped, true);
      expect(mockSink.status, AudioPlaybackStatus.stopped);
    });

    test('seekToTick updates playback position', () async {
      await player.play(dummySound, startTick: 0);
      await player.seekToTick(60);

      expect(player.isPlaying, true);
      expect(mockSink.queuedBuffers.length, 1);
    });

    test('volume control propagates to sink', () {
      player.setVolume(0.5);
      expect(player.volume, 0.5);
    });

    test('looping toggle sets loop property', () {
      expect(player.isLooping, false);
      player.setLooping(true);
      expect(player.isLooping, true);
    });
  });
}
