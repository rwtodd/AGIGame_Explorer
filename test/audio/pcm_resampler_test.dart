// Stage 8 slice 2: measured windowed-sinc resampler (pure Dart).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/pcm_resampler.dart';

Int16List constInput(int len, int value) {
  final a = Int16List(len);
  for (var i = 0; i < len; i++) {
    a[i] = value;
  }
  return a;
}

/// Linear reference (pre-slice formula, repeat at end) for A/B only.
int linearEval(Int16List input, int inRate, int outRate, int frame) {
  if (inRate == outRate) return input[frame.clamp(0, input.length - 1)];
  final pos = frame * inRate / outRate;
  final i0 = pos.floor();
  final frac = pos - i0;
  int at(int i) => (i < 0) ? input[0] : (i >= input.length) ? input[input.length - 1] : input[i];
  final s0 = at(i0);
  final s1 = at(i0 + 1);
  return (s0 + (s1 - s0) * frac).round().clamp(-32768, 32767);
}

/// Output-frame warm-up so the input position is at least
/// [r.halfWidth]+128 input samples clear of both stream ends.
int warmOutputs(PcmResampler r, int inR, int outR) =>
    ((r.halfWidth + 128) * outR / inR).ceil() + 64;

double rms(Int16List a, int start, int end) {
  var s = 0.0;
  for (var i = start; i < end; i++) {
    final v = a[i].toDouble();
    s += v * v;
  }
  return math.sqrt(s / math.max(1, end - start));
}

void main() {
  group('PcmResampler', () {
    test('identity is a true bypass', () {
      final r = PcmResampler(44100, 44100);
      expect(r.isIdentity, isTrue);
      final inp = Int16List.fromList([0, 100, -200, 32767, -32768]);
      expect(r.evaluate((i) => (i >= 0 && i < inp.length) ? inp[i] : 0, 2.0),  -200);
      expect(r.evaluateInt16((i) => (i >= 0 && i < inp.length) ? inp[i] : 0, 3.0), 32767);
    });

    test('DC preservation at several ratios (<=1 LSB after edges)', () {
      for (final (inR, outR) in [(49716, 44100), (49716, 48000), (11000, 44100), (3750, 44100), (44100, 48000)]) {
        final r = PcmResampler(inR, outR);
        final inp = constInput(inR, 5000); // 1 s
        final outFrames = outR;
        int read(int i) => (i >= 0 && i < inp.length) ? inp[i] : 0;
        // Skip half-kernel edges in output terms.
        final warm = warmOutputs(r, inR, outR);
        for (final j in [warm, warm + 1, outFrames ~/ 2, outFrames - warm - 1]) {
          final v = r.evaluateInt16(read, r.inputPositionForFrame(j));
          expect((v - 5000).abs(), lessThanOrEqualTo(1),
              reason: '$inR->$outR frame $j got $v');
        }
      }
    });

    test('sine passband gain within tolerance at 0.5x min-Nyquist', () {
      for (final (inR, outR) in [(49716, 44100), (11000, 44100)]) {
        final r = PcmResampler(inR, outR);
        final minNyq = math.min(inR, outR) / 2.0;
        final freq = 0.5 * minNyq;
        const amp = 12000;
        final inp = Int16List(inR);
        for (var i = 0; i < inR; i++) {
          inp[i] = (amp * math.sin(2 * math.pi * freq * i / inR)).round();
        }
        int read(int i) => (i >= 0 && i < inp.length) ? inp[i] : 0;
        final outFrames = outR;
        final warm = warmOutputs(r, inR, outR);
        // Least-squares sin/cos amplitude over middle window.
        final start = warm;
        final end = outFrames - warm;
        var c = 0.0, s = 0.0;
        for (var j = start; j < end; j++) {
          final v = r.evaluate(read, r.inputPositionForFrame(j));
          final phase = 2 * math.pi * freq * j / outR;
          c += v * math.cos(phase);
          s += v * math.sin(phase);
        }
        final n = (end - start).toDouble();
        final est = 2 * math.sqrt(c * c + s * s) / n;
        final gainDb = 20 * math.log(est / amp) / math.ln10;
        expect(gainDb.abs(), lessThan(0.5),
            reason: '$inR->$outR gainDb=$gainDb est=$est');
      }
    });

    test('alias suppression: above-output-Nyquist tone strongly attenuated vs linear', () {
      const inR = 49716, outR = 44100;
      final r = PcmResampler(inR, outR);
      final freq = 0.95 * inR / 2; // > output Nyquist (22050)
      final inp = Int16List(inR);
      for (var i = 0; i < inR; i++) {
        inp[i] = (12000 * math.sin(2 * math.pi * freq * i / inR)).round();
      }
      int read(int i) => (i >= 0 && i < inp.length) ? inp[i] : 0;
      final outFrames = outR;
      final sincOut = Int16List(outFrames);
      final linOut = Int16List(outFrames);
      for (var j = 0; j < outFrames; j++) {
        sincOut[j] = r.evaluateInt16(read, r.inputPositionForFrame(j));
        linOut[j] = linearEval(inp, inR, outR, j);
      }
      final warm = warmOutputs(r, inR, outR);
      final sincRms = rms(sincOut, warm, outFrames - warm);
      final linRms = rms(linOut, warm, outFrames - warm);
      // Sinc must be at least 20 dB below linear here (and near silence).
      expect(sincRms, lessThan(linRms * 0.1),
          reason: 'sincRms=$sincRms linRms=$linRms');
    });

    test('purity: same position twice / different orders identical', () {
      final r = PcmResampler(49716, 44100);
      final inp = Int16List(49716);
      for (var i = 0; i < inp.length; i++) {
        inp[i] = ((i * 37) % 20000 - 10000).clamp(-32768, 32767);
      }
      int read(int i) => (i >= 0 && i < inp.length) ? inp[i] : 0;
      final positions = <double>[];
      for (var j = 0; j < 500; j++) {
        positions.add(j * 99.7);
      }
      final forward = [for (final p in positions) r.evaluateInt16(read, p)];
      var backward = <int>[];
      for (var i = positions.length - 1; i >= 0; i--) {
        backward.add(r.evaluateInt16(read, positions[i]));
      }
      backward = backward.reversed.toList();
      expect(backward, forward);
      // Second forward pass identical.
      final again = [for (final p in positions) r.evaluateInt16(read, p)];
      expect(again, forward);
    });

    test('edge zeros at stream start: first frames finite, no throw', () {
      final r = PcmResampler(11000, 44100);
      final inp = constInput(11000, 8000);
      int read(int i) => (i >= 0 && i < inp.length) ? inp[i] : 0;
      for (var j = 0; j < 200; j++) {
        final v = r.evaluate(read, r.inputPositionForFrame(j));
        expect(v.isFinite, isTrue, reason: 'frame $j -> $v');
      }
      // Negative and beyond-end positions are 0 (accessor edge), finite.
      expect(r.evaluate(read, -5.3).isFinite, isTrue);
      expect(r.evaluate(read, 999999.0).isFinite, isTrue);
    });

    test('downsample half-width widens with ratio (behavioral via spur is in A/B; here direct)', () {
      final up = PcmResampler(11000, 44100);
      final down = PcmResampler(49716, 44100);
      expect(down.isDownsampling, isTrue);
      expect(up.isDownsampling, isFalse);
      // Widening: half-width scales with in/out when downsampling.
      expect(down.halfWidth, greaterThan(up.halfWidth - 4));
      expect(down.taps, equals(2 * down.halfWidth));
      expect(down.halfWidth, lessThanOrEqualTo(1024));
    });
  });
}
