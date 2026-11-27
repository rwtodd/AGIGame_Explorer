// Stage 6a: SciAdLibPcmSource tests.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_pcm_source.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_renderer.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

Uint8List sineRecord() {
  final b = Uint8List(28);
  b[0] = 0;
  b[1] = 1;
  b[2] = 0;
  b[3] = 15;
  b[4] = 0;
  b[5] = 1;
  b[6] = 8;
  b[7] = 8;
  b[8] = 63;
  b[9] = 0;
  b[10] = 0;
  b[11] = 0;
  b[12] = 0;
  b[13] = 0;
  b[14] = 1;
  b[15] = 0;
  b[16] = 15;
  b[17] = 0;
  b[18] = 1;
  b[19] = 8;
  b[20] = 8;
  b[21] = 0;
  b[22] = 0;
  b[23] = 0;
  b[24] = 0;
  b[25] = 0;
  b[26] = 0;
  b[27] = 0;
  return b;
}

SciAdlibBank makeSineBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    data.setRange(28 * i, 28 * i + 28, sineRecord());
  }
  return SciAdlibBank.fromBytes(data);
}

SciMidiChannelInit chLate(int channel, {int voices = 0, int mask = 0}) =>
    SciMidiChannelInit(
      channel: channel,
      rawBytes: [voices, mask],
      requestedVoices: voices,
      playMask: mask,
    );

SciMidiEvent noteOnEv(int tick, int channel, int note, int velocity) =>
    SciMidiEvent(tick: tick, kind: SciMidiEventKind.noteOn, channel: channel, status: 0x90 | channel, data1: note, data2: velocity);
SciMidiEvent noteOffEv(int tick, int channel, int note) => SciMidiEvent(tick: tick, kind: SciMidiEventKind.noteOff, channel: channel, status: 0x80 | channel, data1: note, data2: 0);
SciMidiEvent programEv(int tick, int channel, int program) => SciMidiEvent(tick: tick, kind: SciMidiEventKind.programChange, channel: channel, status: 0xC0 | channel, data1: program);
SciMidiEvent ccEv(int tick, int channel, int controller, int value) => SciMidiEvent(tick: tick, kind: SciMidiEventKind.controlChange, channel: channel, status: 0xB0 | channel, data1: controller, data2: value);
SciMidiEvent endEv(int tick) => SciMidiEvent(tick: tick, kind: SciMidiEventKind.endOfTrack, channel: -1, status: 0xFC);

SciMidiTrack makeRendererTrack({required List<SciMidiEvent> events, required int totalTicks, int channel = 0, bool masked = true}) {
  final channels = [for (var i = 0; i < 16; i++) chLate(i)];
  channels[channel] = chLate(channel, voices: masked ? 2 : 2, mask: masked ? 0x04 : 0x00);
  return SciMidiTrack(variant: SciMidiHeaderVariant.late, headerSize: 33, flagsByte: 0, hasDigitalSample: false, sampleFlagSetButNoData: false, sample: null, channels: channels, events: events, cues: const [], loopTick: null, totalTicks: totalTicks, hasEndOfTrack: true, isTruncated: false, truncatedTail: Uint8List(0));
}

SciMidiTrack sustainedA4Track({bool masked = true, int channel = 0}) => makeRendererTrack(
      masked: masked,
      channel: channel,
      totalTicks: 120,
      events: [
        programEv(0, channel, 5),
        noteOnEv(0, channel, 69, 100),
        noteOffEv(120, channel, 69),
        endEv(120),
      ],
    );

Int16List drainSource(SciAdLibPcmSource source, int blockSize) {
  final total = source.totalFrames ?? 0;
  final out = Int16List(total * 2);
  var frames = 0;
  final scratch = Int16List(blockSize * 2);
  while (!source.isFinished) {
    final n = source.renderInto(scratch, blockSize);
    expect(n, greaterThan(0));
    out.setRange(frames * 2, frames * 2 + n * 2, scratch);
    frames += n;
  }
  expect(frames, equals(total));
  return out;
}

double rmsOf(Int16List interleaved) {
  var sum = 0.0;
  for (var i = 0; i < interleaved.length; i++) {
    final s = interleaved[i].toDouble();
    sum += s * s;
  }
  return math.sqrt(sum / math.max(1, interleaved.length));
}

void main() {
  group('SciAdLibPcmSource', () {
    test('native-rate identity equals offline renderer', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final expected = sciAdLibRenderTrack(track, bank, masterVolume: 15, tailTicks: 30);
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 49716, masterVolume: 15, tailTicks: 30);
      final out = drainSource(src, 1024);
      expect(src.totalFrames, equals(expected.totalFrames));
      expect(out.length, equals(expected.pcm.length * 2));
      for (var i = 0; i < expected.pcm.length; i++) {
        expect(out[i * 2], equals(expected.pcm[i]), reason: 'frame $i left');
        expect(out[i * 2 + 1], equals(expected.pcm[i]), reason: 'frame $i right');
      }
    });

    test('block-size invariance', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      for (final rate in [49716, 44100]) {
        final ref = drainSource(SciAdLibPcmSource(track, bank, outputSampleRate: rate), 4096);
        for (final block in [1, 17, 512]) {
          final actual = drainSource(SciAdLibPcmSource(track, bank, outputSampleRate: rate), block);
          expect(actual, equals(ref), reason: 'rate $rate block $block');
        }
      }
    });

    test('44100 totalFrames, non-silent, pitch, finished', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 44100);
      final expected = ((120 + 30) * 44100 / 60).round();
      expect(src.totalFrames, equals(expected));
      expect(src.sampleRate, equals(44100));
      expect(src.channels, equals(2));
      final out = drainSource(src, 1024);
      expect(src.isFinished, isTrue);
      expect(src.positionFrames, equals(src.totalFrames));
      // non-silent
      var peak = 0;
      for (final s in out) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, greaterThan(1000));
      // A4 zero-crossing in 1s window at 0.5s offset
      final start = 44100 ~/ 2;
      final frames = 44100;
      var crossings = 0;
      var prev = out[start * 2] >= 0 ? 1 : -1;
      for (var i = start + 1; i < start + frames; i++) {
        final sign = out[i * 2] >= 0 ? 1 : -1;
        if (sign != prev) crossings++;
        prev = sign;
      }
      final freq = (crossings / 2) / (frames / 44100);
      expect(freq, closeTo(440, 440 * 0.03));
      // short final block: drain with block larger than remaining
      final src2 = SciAdLibPcmSource(track, bank, outputSampleRate: 44100);
      final total = src2.totalFrames!;
      final big = Int16List((total + 100) * 2);
      final big2 = Int16List(200);
      final first = src2.renderInto(big, total - 10);
      expect(first, equals(total - 10));
      final last = src2.renderInto(big2, 100);
      expect(last, equals(10));
      expect(src2.isFinished, isTrue);
    });

    test('reset determinism', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 44100);
      final a = drainSource(src, 1024);
      src.reset();
      expect(src.positionFrames, equals(0));
      final b = drainSource(src, 1024);
      expect(b, equals(a));
    });

    test('seekToFrame matches continuous', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final full = drainSource(SciAdLibPcmSource(track, bank, outputSampleRate: 44100), 1024);
      const seekAt = 10000;
      const count = 500;
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 44100);
      src.seekToFrame(seekAt);
      expect(src.positionFrames, equals(seekAt));
      final block = Int16List(count * 2);
      expect(src.renderInto(block, count), equals(count));
      expect(block, equals(Int16List.sublistView(full, seekAt * 2, seekAt * 2 + count * 2)));
    });

    test('seek beyond end clamps', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 44100);
      src.seekToFrame(999999999);
      expect(src.positionFrames, equals(src.totalFrames));
      expect(src.isFinished, isTrue);
      expect(src.renderInto(Int16List(16), 8), equals(0));
    });

    test('setMasterVolume lowers RMS', () {
      final track = sustainedA4Track();
      final bank = makeSineBank();
      final loud = drainSource(SciAdLibPcmSource(track, bank, outputSampleRate: 44100, masterVolume: 15), 1024);
      final src = SciAdLibPcmSource(track, bank, outputSampleRate: 44100, masterVolume: 15);
      // render a bit, lower volume, render rest (use small track still sustained)
      final scratch = Int16List(1024 * 2);
      final combined = Int16List((src.totalFrames ?? 0) * 2);
      final head = Int16List(4410 * 2);
      var off = 0;
      src.renderInto(head, 4410);
      combined.setRange(off, off + head.length, head);
      off += head.length;
      src.setMasterVolume(3);
      while (!src.isFinished) {
        final n = src.renderInto(scratch, 1024);
        combined.setRange(off, off + n * 2, Int16List.sublistView(scratch, 0, n * 2));
        off += n * 2;
      }
      // RMS of second half should be lower than full-volume corresponding region
      final loudSecondHalf = Int16List.sublistView(loud, 4410 * 2);
      final quietSecondHalf = Int16List.sublistView(combined, 4410 * 2);
      expect(rmsOf(quietSecondHalf), lessThan(rmsOf(loudSecondHalf)));
    });

    double channelRms(Int16List interleaved, int ch) {
      var sum = 0.0;
      var count = 0;
      for (var i = ch; i < interleaved.length; i += 2) {
        final s = interleaved[i].toDouble();
        sum += s * s;
        count++;
      }
      return math.sqrt(sum / math.max(1, count));
    }

    SciMidiTrack pannedTrack(int pan) => makeRendererTrack(
          totalTicks: 120,
          events: [
            programEv(0, 0, 5),
            ccEv(0, 0, 0x0A, pan),
            noteOnEv(0, 0, 69, 100),
            noteOffEv(120, 0, 69),
            endEv(120),
          ],
        );

    test('stereoDualOpl2 pans hard-left to left channel', () {
      final out = drainSource(
        SciAdLibPcmSource(pannedTrack(0), makeSineBank(),
            outputSampleRate: 49716, stereoDualOpl2: true),
        1024,
      );
      final left = channelRms(out, 0);
      final right = channelRms(out, 1);
      expect(left, greaterThan(100));
      expect(right, lessThan(left * 0.5));
    });

    test('stereoDualOpl2 pans hard-right to right channel', () {
      final out = drainSource(
        SciAdLibPcmSource(pannedTrack(127), makeSineBank(),
            outputSampleRate: 49716, stereoDualOpl2: true),
        1024,
      );
      final left = channelRms(out, 0);
      final right = channelRms(out, 1);
      expect(right, greaterThan(100));
      expect(left, lessThan(right * 0.5));
    });

    test('default mono source duplicates sample-for-sample', () {
      final src = SciAdLibPcmSource(sustainedA4Track(), makeSineBank(),
          outputSampleRate: 49716);
      expect(src.stereoDualOpl2, isFalse);
      final out = drainSource(src, 1024);
      for (var i = 0; i < out.length; i += 2) {
        expect(out[i], equals(out[i + 1]));
      }
    });

    test('stereo center pan matches mono energy on both channels', () {
      final mono = drainSource(
        SciAdLibPcmSource(pannedTrack(64), makeSineBank(),
            outputSampleRate: 49716),
        1024,
      );
      final stereo = drainSource(
        SciAdLibPcmSource(pannedTrack(64), makeSineBank(),
            outputSampleRate: 49716, stereoDualOpl2: true),
        1024,
      );
      // Center-panned stereo should equal mono duplicated output.
      expect(stereo, equals(mono));
    });

    test('destination too small throws', () {
      final src = SciAdLibPcmSource(sustainedA4Track(), makeSineBank());
      expect(() => src.renderInto(Int16List(10), 100), throwsArgumentError);
      expect(src.positionFrames, equals(0));
    });
  });
}
