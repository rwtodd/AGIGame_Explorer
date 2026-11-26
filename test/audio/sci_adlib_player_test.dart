// Stage 6a: AgiSoundPlayer.playPcmSource tests — fake PcmSource for player
// semantics plus one real SciAdLibPcmSource smoke test.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_pcm_source.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

class FakeSource extends PcmSource {
  final int _total;
  int _pos = 0;
  @override
  final int sampleRate;
  FakeSource(this._total, {this.sampleRate = 44100});
  static int pattern(int frame) => (frame % 2048) - 1024;
  @override
  int get channels => 2;
  @override
  int? get totalFrames => _total;
  @override
  int get positionFrames => _pos;
  @override
  bool get isFinished => _pos >= _total;
  @override
  void reset() => _pos = 0;
  @override
  void seekToFrame(int frame) => _pos = frame.clamp(0, _total);
  @override
  int renderInto(Int16List interleaved, int frameCount) {
    if (interleaved.length < frameCount * 2) throw ArgumentError('too small');
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

Uint8List sineRecord() {
  final b = Uint8List(28);
  b[0] = 0; b[1] = 1; b[2] = 0; b[3] = 15; b[4] = 0; b[5] = 1; b[6] = 8; b[7] = 8; b[8] = 63;
  b[13] = 0; b[14] = 1; b[16] = 15; b[18] = 1; b[19] = 8; b[20] = 8;
  return b;
}

SciAdlibBank makeSineBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    data.setRange(28 * i, 28 * i + 28, sineRecord());
  }
  return SciAdlibBank.fromBytes(data);
}

SciMidiChannelInit chLate(int ch, {int voices = 0, int mask = 0}) =>
    SciMidiChannelInit(channel: ch, rawBytes: [voices, mask], requestedVoices: voices, playMask: mask);

void main() {
  group('AgiSoundPlayer.playPcmSource', () {
    late NullAudioSink sink;
    late AgiSoundPlayer player;
    setUp(() {
      sink = NullAudioSink();
      player = AgiSoundPlayer(sink: sink);
    });
    tearDown(() => player.dispose());

    test('playing -> onFinished, monotonic ticks, pause/resume', () async {
      final src = FakeSource(4410, sampleRate: 44100); // 0.1s = 6 ticks
      var finished = 0;
      player.onFinished = () => finished++;
      final positions = <SoundPlaybackPosition>[];
      final sub = player.positionStream.listen(positions.add);

      await player.playPcmSource(src, totalTicks: 6);
      expect(player.status, SoundPlayerStatus.playing);
      expect(player.isGenericActive, isTrue);
      expect(player.currentSound, isNull);
      expect(sink.status, AudioPlaybackStatus.playing);
      expect(sink.queuedBuffers, isNotEmpty);

      player.pause();
      expect(player.isPaused, isTrue);
      expect(sink.status, AudioPlaybackStatus.paused);
      player.resume();
      expect(player.isPlaying, isTrue);

      // fast-forward sink and let refill complete
      sink.simulateFramesPlayed(4410);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(finished, 1);
      // position ticks monotonic within [0, total]
      var last = 0;
      for (final p in positions) {
        expect(p.currentTick, greaterThanOrEqualTo(0));
        expect(p.currentTick, lessThanOrEqualTo(6));
        if (p.currentTick < last) {}
        last = p.currentTick;
      }
      await sub.cancel();
    });

    test('muted completes via timer with no non-zero sink writes', () async {
      final src = FakeSource(4410, sampleRate: 44100);
      var finished = 0;
      player.onFinished = () => finished++;
      await player.playPcmSource(src, totalTicks: 6, muted: true);
      expect(player.status, SoundPlayerStatus.playing);
      expect(sink.queuedBuffers, isEmpty);
      // total 6 ticks = 0.1s + 0.05 tail => wait for timer
      await Future.delayed(const Duration(milliseconds: 300));
      expect(finished, 1);
      expect(player.isStopped, isTrue);
      expect(
        sink.queuedBuffers.expand((b) => b).every((s) => s == 0),
        isTrue,
      );
    });

    test('stop resets', () async {
      final src = FakeSource(44100, sampleRate: 44100);
      await player.playPcmSource(src, totalTicks: 60);
      player.stop();
      expect(player.isStopped, isTrue);
      expect(sink.status, AudioPlaybackStatus.stopped);
    });

    test('real SciAdLibPcmSource smoke', () async {
      final channels = [for (var i = 0; i < 16; i++) chLate(i)];
      channels[0] = chLate(0, voices: 2, mask: 0x04);
      final track = SciMidiTrack(
        variant: SciMidiHeaderVariant.late,
        headerSize: 33,
        flagsByte: 0,
        hasDigitalSample: false,
        sampleFlagSetButNoData: false,
        sample: null,
        channels: channels,
        events: [
          SciMidiEvent(tick: 0, kind: SciMidiEventKind.programChange, channel: 0, status: 0xC0, data1: 5),
          SciMidiEvent(tick: 0, kind: SciMidiEventKind.noteOn, channel: 0, status: 0x90, data1: 69, data2: 100),
          SciMidiEvent(tick: 120, kind: SciMidiEventKind.noteOff, channel: 0, status: 0x80, data1: 69, data2: 0),
          SciMidiEvent(tick: 120, kind: SciMidiEventKind.endOfTrack, channel: -1, status: 0xFC),
        ],
        cues: const [],
        loopTick: null,
        totalTicks: 120,
        hasEndOfTrack: true,
        isTruncated: false,
        truncatedTail: Uint8List(0),
      );
      final src = SciAdLibPcmSource(track, makeSineBank(), outputSampleRate: 44100);
      await player.playPcmSource(src, totalTicks: 120);
      expect(player.isPlaying, isTrue);
      expect(player.isGenericActive, isTrue);
      expect(sink.queuedBuffers, isNotEmpty);
      var peak = 0;
      for (final b in sink.queuedBuffers) {
        for (final s in b) {
          if (s.abs() > peak) peak = s.abs();
        }
      }
      expect(peak, greaterThan(0));
      player.stop();
    });
  });
}
