// Stage 8: SciDigitalSamplePcmSource unit tests (unsigned 8-bit SCI
// samples -> stereo PCM, windowed-sinc resample, master volume, window).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/sci_digital_sample_source.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

SciMidiSample sampleOf(List<int> pcm, {int? rate = 11025, int? length, int? start, int? end}) {
  return SciMidiSample(
    rawHeaderBytes: Uint8List(44),
    sampleRate: rate,
    sampleLength: length ?? pcm.length,
    sampleStart: start,
    sampleEnd: end,
    payloadOffset: 0,
    pcmBytes: Uint8List.fromList(pcm),
  );
}

List<int> renderAll(SciDigitalSamplePcmSource source) {
  final total = source.totalFrames!;
  final buf = Int16List(total * 2);
  final written = source.renderInto(buf, total);
  expect(written, total);
  return buf.toList();
}

void main() {
  group('SciDigitalSamplePcmSource', () {
    test('conversion: silence (128) is 0, polarity and scaling at vol 15', () {
      final source = SciDigitalSamplePcmSource(
        sampleOf([128, 255, 0, 129, 127], rate: 44100),
        outputSampleRate: 44100,
        masterVolume: 15,
      );
      final out = renderAll(source);
      // identity rate: exact frames, L == R.
      expect(out, [0, 0, 32512, 32512, -32768, -32768, 256, 256, -256, -256]);
      expect(source.channels, 2);
      expect(source.sampleRate, 44100);
      expect(source.totalFrames, 5);
    });

    test('masterVolume 0 is silent; mid volume scales deterministically', () {
      final quiet = renderAll(SciDigitalSamplePcmSource(
        sampleOf([255, 0], rate: 44100),
        outputSampleRate: 44100,
        masterVolume: 0,
      ));
      expect(quiet, [0, 0, 0, 0]);

      final half = renderAll(SciDigitalSamplePcmSource(
        sampleOf([255], rate: 44100),
        outputSampleRate: 44100,
        masterVolume: 8,
      ));
      // (127 << 8) * 8/15 = 32512 * 0.5333.. = 17339.73.. -> 17340
      expect(half, [17340, 17340]);
    });

    test('setMasterVolume clamps 0..15 and applies on subsequent renders', () {
      final source = SciDigitalSamplePcmSource(
        sampleOf([255], rate: 44100),
        outputSampleRate: 44100,
        masterVolume: 15,
      );
      source.setMasterVolume(99);
      expect(source.masterVolume, 15);
      source.setMasterVolume(-3);
      expect(source.masterVolume, 0);
      source.reset();
      expect(renderAll(source), [0, 0]);
      source.setMasterVolume(15);
      source.reset();
      expect(renderAll(source), [32512, 32512]);
    });

    test('totalFrames math: round(playableLength * out / in)', () {
      // 7415 bytes at 11000 Hz -> 44100: round(7415*44100/11000)=29727
      final source = SciDigitalSamplePcmSource(
        sampleOf(List.filled(7415, 128), rate: 11000),
        outputSampleRate: 44100,
      );
      expect(source.totalFrames, 29727);
      expect(source.inputSampleRate, 11000);
    });

    test('resample is independent of renderInto block splits', () {
      List<int> renderInBlocks(List<int> blockSizes) {
        final source = SciDigitalSamplePcmSource(
          sampleOf([0, 128, 255, 200, 50, 128, 90], rate: 8000),
          outputSampleRate: 44100,
        );
        final total = source.totalFrames!;
        final out = Int16List(total * 2);
        var pos = 0;
        var i = 0;
        final scratch = Int16List(200000);
        while (pos < total) {
          final want = blockSizes[i % blockSizes.length];
          final block = want > total - pos ? total - pos : want;
          final n = source.renderInto(scratch, block);
          out.setRange(pos * 2, pos * 2 + n * 2, scratch);
          pos += n;
          i++;
          if (n == 0) break;
        }
        return out.toList();
      }

      final whole = renderInBlocks([100000]);
      final split = renderInBlocks([1, 7, 3, 64]);
      final ones = renderInBlocks([1]);
      expect(split, whole);
      expect(ones, whole);
      // Non-silent stereo output.
      expect(whole.any((s) => s != 0), isTrue);
      for (var i = 0; i < whole.length; i += 2) {
        expect(whole[i], whole[i + 1]);
      }
    });

    test('reset zeroes position; seek clamps into [0, totalFrames]', () {
      final source = SciDigitalSamplePcmSource(
        sampleOf([255, 255, 255, 255], rate: 44100),
        outputSampleRate: 44100,
      );
      final buf = Int16List(4);
      expect(source.renderInto(buf, 2), 2);
      expect(source.positionFrames, 2);
      source.reset();
      expect(source.positionFrames, 0);
      expect(source.isFinished, isFalse);
      source.seekToFrame(3);
      expect(source.positionFrames, 3);
      final tail = Int16List(4);
      expect(source.renderInto(tail, 2), 1);
      expect(source.isFinished, isTrue);
      source.seekToFrame(9999);
      expect(source.positionFrames, 4);
      source.seekToFrame(-5);
      expect(source.positionFrames, 0);
    });

    test('finished semantics: rendering at end returns 0', () {
      final source = SciDigitalSamplePcmSource(
        sampleOf([200], rate: 44100),
        outputSampleRate: 44100,
      );
      expect(source.renderInto(Int16List(4), 1), 1);
      expect(source.isFinished, isTrue);
      expect(source.renderInto(Int16List(4), 1), 0);
    });

    test('unplayable samples yield 0 frames and finish immediately', () {
      for (final s in [
        sampleOf([200], rate: null),
        sampleOf([200], rate: 0),
        sampleOf([], rate: 11025),
      ]) {
        final source = SciDigitalSamplePcmSource(s, outputSampleRate: 44100);
        expect(source.totalFrames, 0);
        expect(source.isFinished, isTrue);
        expect(source.renderInto(Int16List(4), 1), 0);
      }
    });

    test('start/end window is honored (SCI1 start + ScummVM end convention)', () {
      // pcm [a,b,c,d,e,f], start=2, end=5 (base-len end part 1) -> [c,d,e]
      final source = SciDigitalSamplePcmSource(
        sampleOf([200, 200, 255, 255, 255, 200], rate: 44100, start: 2, end: 5),
        outputSampleRate: 44100,
      );
      expect(source.totalFrames, 3);
      expect(renderAll(source), [32512, 32512, 32512, 32512, 32512, 32512]);
    });

    test('undersized buffer throws ArgumentError before writing', () {
      final source = SciDigitalSamplePcmSource(
        sampleOf([200, 200], rate: 44100),
        outputSampleRate: 44100,
      );
      final buf = Int16List.fromList([111, 222, 333]);
      expect(() => source.renderInto(buf, 2), throwsArgumentError);
      expect(buf, [111, 222, 333]);
    });

    test('outputSampleRate <= 0 is rejected like the sibling sources', () {
      expect(
        () => SciDigitalSamplePcmSource(sampleOf([200]), outputSampleRate: 0),
        throwsArgumentError,
      );
    });

    test('exposes the wrapped sample and input rate', () {
      final s = sampleOf([200], rate: 11025);
      final source = SciDigitalSamplePcmSource(s, outputSampleRate: 44100);
      expect(identical(source.sample, s), isTrue);
      expect(source.inputSampleRate, 11025);
    });
  });
}
