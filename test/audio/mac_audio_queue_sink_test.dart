import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/mac_audio_queue_sink.dart';

void main() {
  test('MacAudioQueueSink can be re-initialized after dispose', () async {
    if (!Platform.isMacOS) {
      markTestSkipped('macOS-only test');
      return;
    }
    final sink = MacAudioQueueSink();
    await sink.initialize(sampleRate: 44100);
    sink.dispose();
    sink.dispose();
    await sink.initialize(sampleRate: 22050);
    expect(sink.sampleRate, 22050);
    expect(sink.status, AudioPlaybackStatus.stopped);
    sink.dispose();
  });

  test('resume from pause preserves playedFrames (no re-prime)', () async {
    if (!Platform.isMacOS) {
      markTestSkipped('macOS-only test');
      return;
    }
    final sink = MacAudioQueueSink();
    addTearDown(sink.dispose);
    await sink.initialize(
      sampleRate: 44100,
      numChannels: 2,
      bufferSizeInFrames: 2048,
    );

    // One second of stereo PCM so buffers complete during the test.
    final samples = Int16List(44100 * 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (i % 2048) - 1024;
    }
    sink.writePcm(samples);
    sink.play();
    expect(sink.status, AudioPlaybackStatus.playing);

    // Wait for the device to play at least one buffer.
    final sw = Stopwatch()..start();
    while (sink.playedFrames == 0 && sw.elapsed < const Duration(seconds: 2)) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    if (sink.playedFrames == 0) {
      markTestSkipped('audio device did not advance playedFrames');
      return;
    }

    sink.pause();
    expect(sink.status, AudioPlaybackStatus.paused);
    final atPause = sink.playedFrames;
    expect(atPause, greaterThan(0));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(sink.playedFrames, atPause);

    sink.play();
    expect(sink.status, AudioPlaybackStatus.playing);
    // The old code reset playedFrames to 0 here and re-filled buffers
    // the OS still held queued.
    expect(sink.playedFrames, atPause);
    sink.stop();
  });
}
