import 'dart:typed_data';

import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/audio/streaming_pcm_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic stereo ramp source: frame `i` yields
/// `pattern(i)` on the left and `-pattern(i)` on the right.
class RampSource extends PcmSource {
  final int _total;
  int _pos = 0;

  RampSource(this._total);

  static int pattern(int frame) => (frame % 2048) - 1024;

  @override
  int get sampleRate => 44100;

  @override
  int get channels => 2;

  @override
  int? get totalFrames => _total;

  @override
  int get positionFrames => _pos;

  @override
  bool get isFinished => _pos >= _total;

  @override
  void reset() {
    _pos = 0;
  }

  @override
  void seekToFrame(int frame) {
    _pos = frame.clamp(0, _total);
  }

  @override
  int renderInto(Int16List interleaved, int frameCount) {
    if (interleaved.length < frameCount * channels) {
      throw ArgumentError('interleaved buffer too small');
    }
    var n = frameCount;
    final remaining = _total - _pos;
    if (n > remaining) n = remaining;
    if (n <= 0) return 0;
    for (var i = 0; i < n; i++) {
      final p = pattern(_pos + i);
      interleaved[i * 2] = p;
      interleaved[i * 2 + 1] = -p;
    }
    _pos += n;
    return n;
  }
}

int queuedFrames(NullAudioSink sink) =>
    sink.queuedBuffers.fold(0, (a, b) => a + b.length) ~/ 2;

void main() {
  group('StreamingPcmPlayer', () {
    late NullAudioSink sink;

    setUp(() {
      sink = NullAudioSink();
    });

    test('initial fill respects lookahead', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      await player.playSource(RampSource(5000));

      expect(player.isPlaying, isTrue);
      expect(sink.status, AudioPlaybackStatus.playing);
      // One lookahead window of 250 frames, at most one extra block
      // (blocks are whole: 100 + 100 + 100).
      expect(queuedFrames(sink), 300);
      expect(sink.queuedBuffers.length, 3);
      expect(queuedFrames(sink), lessThanOrEqualTo(250 + 100));

      // First block starts at the ramp start.
      expect(sink.queuedBuffers.first[0], RampSource.pattern(0));
      expect(sink.queuedBuffers.first[1], -RampSource.pattern(0));
      expect(sink.queuedBuffers.first[2], RampSource.pattern(1));
    });

    test('refill after simulated frames played keeps lookahead topped up',
        () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      await player.playSource(RampSource(5000));
      expect(queuedFrames(sink), 300);

      sink.simulateFramesPlayed(200);
      // Let refill ticks run (25 ms cadence).
      await Future.delayed(const Duration(milliseconds: 90));

      // Consumed 200, so more frames were rendered on top. The queued
      // stream is a contiguous ramp from frame 0 regardless of how many
      // refill ticks ran.
      expect(queuedFrames(sink), greaterThan(250));
      final totalFrames = queuedFrames(sink);
      final lastStartFrame = totalFrames - sink.queuedBuffers.last.length ~/ 2;
      expect(
        sink.queuedBuffers.last[0],
        RampSource.pattern(lastStartFrame),
      );

      // Underrun: the sink consumed everything queued while the source
      // still has frames left.
      sink.simulateFramesPlayed(player.audibleFrames + 5000);
      await Future.delayed(const Duration(milliseconds: 90));
      expect(player.underrunCount, greaterThan(0));
    });

    test('completion fires onFinished exactly once when consumed reaches total',
        () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      var finished = 0;
      player.onFinished = () => finished++;

      await player.playSource(RampSource(500));

      // Consume everything the sink has; this drives refill to the end.
      sink.simulateFramesPlayed(500);
      await Future.delayed(const Duration(milliseconds: 120));

      expect(player.status, SoundPlayerStatus.completed);
      expect(player.isPlaying, isFalse);
      expect(player.audibleFrames, 500);
      expect(finished, 1);

      // Another tick window must not fire again.
      sink.simulateFramesPlayed(500);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(finished, 1);
    });

    test('zero-length source completes immediately without spinning', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      var finished = 0;
      player.onFinished = () => finished++;

      await player.playSource(RampSource(0));

      expect(player.status, SoundPlayerStatus.completed);
      expect(finished, 1);
      expect(sink.queuedBuffers, isEmpty);
    });

    test('looping wraps and repeats pattern seamlessly', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);
      player.looping = true;

      var finished = 0;
      player.onFinished = () => finished++;

      await player.playSource(RampSource(300));
      expect(queuedFrames(sink), 300);

      // Consume all queued; refill must wrap past 300 into a new pass.
      sink.simulateFramesPlayed(250);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(player.isPlaying, isTrue);
      expect(finished, 0);
      // Queued stream now extends beyond one pass, i.e. pattern repeats.
      expect(queuedFrames(sink), greaterThan(300));
      final flat = sink.queuedBuffers.expand((b) => b).toList();
      // Frame 300 (start of second pass) matches frame 0's pattern.
      expect(flat[300 * 2], RampSource.pattern(0));
      expect(flat[300 * 2 + 1], -RampSource.pattern(0));
      expect(flat[122 * 2], RampSource.pattern(122));

      player.looping = false;
      player.stop();
    });

    test('seek lands at the exact ramp offset', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      await player.playSource(RampSource(5000));
      player.seekToFrame(1024);

      expect(player.isPlaying, isTrue);
      // Exact pattern offset is checked below; the stopwatch estimate
      // may add a frame of real elapsed time since the seek.
      expect(player.audibleFrames, greaterThanOrEqualTo(1024));
      expect(sink.queuedBuffers, isNotEmpty);
      expect(sink.queuedBuffers.first[0], RampSource.pattern(1024));
      expect(sink.queuedBuffers.first[1], -RampSource.pattern(1024));
      expect(sink.queuedBuffers.first[2], RampSource.pattern(1025));
    });

    test('muted advances the source but writes zeros', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);
      player.muted = true;

      await player.playSource(RampSource(5000));

      expect(player.isPlaying, isTrue);
      expect(queuedFrames(sink), 300);
      expect(
        sink.queuedBuffers.expand((b) => b).every((s) => s == 0),
        isTrue,
      );

      // Source still advances via refill ticks.
      sink.simulateFramesPlayed(200);
      await Future.delayed(const Duration(milliseconds: 90));
      expect(queuedFrames(sink), greaterThan(250));
      expect(
        sink.queuedBuffers.expand((b) => b).every((s) => s == 0),
        isTrue,
      );
    });

    test('NullAudioSink copies: first queued block survives later renders',
        () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      await player.playSource(RampSource(5000));
      final firstBlock = sink.queuedBuffers.first;
      final firstValues = Int16List.fromList(firstBlock);

      // Force a refill: without a sink-side copy, the player reuses one
      // block buffer and the first queued buffer would be overwritten.
      sink.simulateFramesPlayed(250);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(sink.queuedBuffers.length, greaterThan(1));
      expect(firstBlock, firstValues);
      expect(firstBlock[0], RampSource.pattern(0));
      expect(firstBlock[2], RampSource.pattern(1));
    });

    test('pause holds position and resume continues', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      final positions = <int>[];
      player.onPositionFrames = positions.add;

      await player.playSource(RampSource(5000));
      sink.simulateFramesPlayed(200);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(positions, isNotEmpty);

      player.pause();
      expect(player.isPaused, isTrue);
      expect(sink.status, AudioPlaybackStatus.paused);
      final pausedAt = player.audibleFrames;
      final positionCount = positions.length;
      await Future.delayed(const Duration(milliseconds: 80));
      // No refill ticks while paused: position and callbacks freeze.
      expect(positions.length, positionCount);
      expect(player.audibleFrames, pausedAt);

      player.resume();
      expect(player.isPlaying, isTrue);
      expect(sink.status, AudioPlaybackStatus.playing);
      await Future.delayed(const Duration(milliseconds: 60));
      expect(positions.length, greaterThan(positionCount));
    });

    test('stop clears queued audio and resets position', () async {
      final player = StreamingPcmPlayer(
        sink: sink,
        blockFrames: 100,
        lookaheadFrames: 250,
      );
      addTearDown(player.dispose);

      await player.playSource(RampSource(5000));
      expect(queuedFrames(sink), 300);
      player.stop();

      expect(player.status, SoundPlayerStatus.stopped);
      expect(player.audibleFrames, 0);
      expect(sink.queuedBuffers, isEmpty);
      expect(sink.status, AudioPlaybackStatus.stopped);
    });
  });
}
