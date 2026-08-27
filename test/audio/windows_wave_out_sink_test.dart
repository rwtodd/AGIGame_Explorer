import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/windows_wave_out_sink.dart';

void main() {
  group('WindowsWaveOutSink Lifecycle & Playback Tests', () {
    test('WindowsWaveOutSink initializes, writes PCM, plays, pauses, stops, and disposes on Windows', () async {
      if (!Platform.isWindows) return;

      final sink = WindowsWaveOutSink();
      expect(sink.status, equals(AudioPlaybackStatus.uninitialized));

      final statusEvents = <AudioPlaybackStatus>[];
      final sub = sink.statusStream.listen(statusEvents.add);

      await sink.initialize(sampleRate: 44100, numChannels: 2, bufferSizeInFrames: 1024);
      expect(sink.status, equals(AudioPlaybackStatus.stopped));
      expect(sink.sampleRate, equals(44100));
      expect(sink.numChannels, equals(2));

      // Generate 0.1s of 440 Hz stereo sine wave
      final sampleCount = (44100 * 0.1).round() * 2;
      final samples = Int16List(sampleCount);
      for (int i = 0; i < sampleCount; i += 2) {
        final sample = (10000 * 0.5).round();
        samples[i] = sample;
        samples[i + 1] = sample;
      }

      sink.writePcm(samples);
      sink.setVolume(0.75);

      sink.play();
      expect(sink.status, equals(AudioPlaybackStatus.playing));
      await Future.delayed(const Duration(milliseconds: 10));

      sink.pause();
      expect(sink.status, equals(AudioPlaybackStatus.paused));
      await Future.delayed(const Duration(milliseconds: 10));

      sink.play();
      expect(sink.status, equals(AudioPlaybackStatus.playing));
      await Future.delayed(const Duration(milliseconds: 10));

      sink.stop();
      expect(sink.status, equals(AudioPlaybackStatus.stopped));
      await Future.delayed(const Duration(milliseconds: 10));

      sink.flush();

      sink.dispose();
      expect(sink.status, equals(AudioPlaybackStatus.uninitialized));
      await Future.delayed(const Duration(milliseconds: 10));

      await sub.cancel();
      expect(statusEvents, contains(AudioPlaybackStatus.stopped));
      expect(statusEvents, contains(AudioPlaybackStatus.playing));
      expect(statusEvents, contains(AudioPlaybackStatus.paused));
    });
  });
}
