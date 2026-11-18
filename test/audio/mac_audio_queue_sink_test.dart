import 'dart:io';
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
}
