// Measured resampler-quality pass (Stage 8 slice 2). Runnable as:
//   dart tool/measure_resampler.dart
// Pure-Dart tooling (dart:math/typed_data/io only) importing the
// production evaluator from lib/audio/pcm_resampler.dart. Linear
// reference below is the pre-slice formula (per-frame linear between
// adjacent input samples, last sample repeated at the end) so the
// tool can A/B it against production sinc. Deterministic inputs only.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_agigame/audio/pcm_resampler.dart';

double _db(double ratio) {
  if (ratio <= 0) return -999.0;
  return 20 * math.log(ratio) / math.ln10;
}

/// Linear reference: pos = j*in/out, i0=floor, frac, repeat at end.
int linearEval(Int16List input, int inRate, int outRate, int frame) {
  if (inRate == outRate) return input[frame.clamp(0, input.length - 1)];
  final pos = frame * inRate / outRate;
  final i0 = pos.floor();
  final frac = pos - i0;
  final len = input.length;
  int at(int i) => (i < 0) ? input[0] : (i >= len) ? input[len - 1] : input[i];
  final s0 = at(i0);
  final s1 = at(i0 + 1);
  return (s0 + (s1 - s0) * frac).round().clamp(-32768, 32767);
}

Int16List renderLinear(Int16List input, int inRate, int outRate, int outFrames) {
  final out = Int16List(outFrames);
  for (var j = 0; j < outFrames; j++) {
    out[j] = linearEval(input, inRate, outRate, j);
  }
  return out;
}

Int16List renderSinc(PcmResampler r, Int16List input, int outFrames) {
  final out = Int16List(outFrames);
  final len = input.length;
  int read(int i) => (i >= 0 && i < len) ? input[i] : 0;
  for (var j = 0; j < outFrames; j++) {
    out[j] = r.evaluateInt16(read, r.inputPositionForFrame(j));
  }
  return out;
}

Int16List sineInput(int inRate, double freqHz,
    {int amp = 12000, int seconds = 1}) {
  final n = inRate * seconds;
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (amp * math.sin(2 * math.pi * freqHz * i / inRate))
        .round()
        .clamp(-32768, 32767);
  }
  return out;
}

/// Goertzel amplitude over [seg] from [start] (rectangular; N large).
double goertzelAmplitude(Int16List seg, int start, double freqHz, int outRate) {
  final n = seg.length - start;
  final w = 2 * math.pi * freqHz / outRate;
  final cosW = math.cos(w);
  final coeff = 2 * cosW;
  double s0 = 0, s1 = 0, s2 = 0;
  for (var i = 0; i < n; i++) {
    s0 = seg[start + i].toDouble() + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final power = s2 * s2 + s1 * s1 - coeff * s1 * s2;
  final mag = math.sqrt(power < 0 ? 0 : power);
  return 2 * mag / n;
}

// --- iterative radix-2 FFT (power-of-two) ---
void fft(List<double> re, List<double> im) {
  final n = re.length;
  // bit-reverse
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang);
    final wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      double cwr = 1, cwi = 0;
      for (var j = 0; j < len >> 1; j++) {
        final ur = re[i + j];
        final ui = im[i + j];
        final vr = re[i + j + (len >> 1)] * cwr - im[i + j + (len >> 1)] * cwi;
        final vi = re[i + j + (len >> 1)] * cwi + im[i + j + (len >> 1)] * cwr;
        re[i + j] = ur + vr;
        im[i + j] = ui + vi;
        re[i + j + (len >> 1)] = ur - vr;
        im[i + j + (len >> 1)] = ui - vi;
        final nxtR = cwr * wr - cwi * wi;
        cwi = cwr * wi + cwi * wr;
        cwr = nxtR;
      }
    }
  }
}

/// Strongest non-fundamental bin (dB relative to fundamental) via
/// Hann-windowed FFT of [Nfft] samples taken from segment middle.
double spurDb(Int16List out, int outRate, double freqHz) {
  const nfft = 32768;
  final start = (out.length - nfft) ~/ 2;
  final re = List<double>.filled(nfft, 0);
  final im = List<double>.filled(nfft, 0);
  for (var i = 0; i < nfft; i++) {
    final w = 0.5 * (1 - math.cos(2 * math.pi * i / (nfft - 1)));
    re[i] = out[start + i].toDouble() * w;
  }
  fft(re, im);
  final fundBin = ((freqHz * nfft / outRate).round()).clamp(1, nfft ~/ 2 - 1);
  double fund = 0;
  for (var b = fundBin - 2; b <= fundBin + 2; b++) {
    final m = math.sqrt(re[b] * re[b] + im[b] * im[b]);
    if (m > fund) fund = m;
  }
  double spur = 0;
  // Exclude a wide guard around the fundamental so Hann-window
  // main-lobe/sidelobe leakage near the tone is not reported as an
  // image spur; true images (at multiples of in/out rates) are far.
  const guard = 32;
  for (var b = 1; b < nfft ~/ 2; b++) {
    if ((b - fundBin).abs() <= guard) continue;
    final m = math.sqrt(re[b] * re[b] + im[b] * im[b]);
    if (m > spur) spur = m;
  }
  return _db(spur / (fund <= 0 ? 1 : fund));
}

/// Alias attenuation (dB vs input amplitude 12000) for tones above
/// output Nyquist: max FFT bin (Hann, coherent-gain corrected).
double aliasAttenDb(Int16List out, int outRate) {
  const nfft = 32768;
  if (out.length < nfft) return -999;
  final start = (out.length - nfft) ~/ 2;
  final re = List<double>.filled(nfft, 0);
  final im = List<double>.filled(nfft, 0);
  double wsum = 0;
  for (var i = 0; i < nfft; i++) {
    final w = 0.5 * (1 - math.cos(2 * math.pi * i / (nfft - 1)));
    wsum += w;
    re[i] = out[start + i].toDouble() * w;
  }
  fft(re, im);
  double peak = 0;
  for (var b = 1; b < nfft ~/ 2; b++) {
    final m = math.sqrt(re[b] * re[b] + im[b] * im[b]);
    if (m > peak) peak = m;
  }
  // Hann coherent gain = 0.5; input sine amplitude 12000 => expected
  // unwindowed mag = A*N/2 (FFT sum) => windowed peak ~ A*N*0.5/2? Actually
  // FFT bin of windowed sine peak ~= A * wsum / 2. Normalize by that.
  final ref = 12000 * wsum / 2;
  return _db(peak / ref);
}

double timeMs(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0;
}

void main() {
  final pairs = <(int, int)>[
    (49716, 44100),
    (49716, 48000),
    (11000, 44100),
    (5000, 44100),
    (3750, 44100),
  ];
  const ratios = [0.1, 0.3, 0.5, 0.7, 0.9];
  const warm = 512;
  stdout.writeln('pair          algo  gain_dB@0.1/0.3/0.5/0.7/0.9  spur@0.9(dB)  aliasAtten(dB)  cpu10s(ms) stereo%');
  final summary = <String, double>{}; // pair -> spur improvement (sinc-linear)
  final droopSinc09 = <String, double>{};
  final cpuStereoPct = <String, double>{};
  for (final (inRate, outRate) in pairs) {
    final minNyq = math.min(inRate, outRate) / 2.0;
    final repo = PcmResampler(inRate, outRate);
    // Pre-generate inputs per ratio.
    final inputs = <double, Int16List>{};
    for (final r in ratios) {
      inputs[r] = sineInput(inRate, r * minNyq);
    }
    final outFrames = outRate; // 1 s output
    for (final algo in ['linear', 'sinc']) {
      final gains = <double>[];
      for (final r in ratios) {
        final inp = inputs[r]!;
        final rendered = algo == 'linear'
            ? renderLinear(inp, inRate, outRate, outFrames)
            : renderSinc(repo, inp, outFrames);
        final amp = goertzelAmplitude(rendered, warm, r * minNyq, outRate);
        gains.add(_db(amp / 12000));
      }
      // spur at 0.9 tone
      final inp09 = inputs[0.9]!;
      final r09 = algo == 'linear'
          ? renderLinear(inp09, inRate, outRate, outFrames)
          : renderSinc(repo, inp09, outFrames);
      final spur = spurDb(r09, outRate, 0.9 * minNyq);
      // alias tone (downsample only; else show n/a)
      String aliasStr = 'n/a';
      if (inRate > outRate) {
        final aliasIn = sineInput(inRate, 0.95 * inRate / 2);
        final ra = algo == 'linear'
            ? renderLinear(aliasIn, inRate, outRate, outFrames)
            : renderSinc(repo, aliasIn, outFrames);
        final att = aliasAttenDb(ra, outRate);
        aliasStr = att.toStringAsFixed(1);
      }
      // CPU: deterministic pseudo-random input, 10 s mono, warmup 1 s.
      final cpuIn = Int16List(inRate * 10);
      var seed = 0x12345678;
      for (var i = 0; i < cpuIn.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        cpuIn[i] = ((seed % 24000) - 12000).clamp(-32768, 32767);
      }
      final cpuOut = Int16List(outRate * 10);
      final evals = outRate * 10;
      void runCpu() {
        if (algo == 'linear') {
          for (var j = 0; j < evals; j++) {
            cpuOut[j] = linearEval(cpuIn, inRate, outRate, j);
          }
        } else {
          final len = cpuIn.length;
          int read(int i) => (i >= 0 && i < len) ? cpuIn[i] : 0;
          for (var j = 0; j < evals; j++) {
            cpuOut[j] = repo.evaluateInt16(read, repo.inputPositionForFrame(j));
          }
        }
      }
      runCpu(); // warmup (JIT)
      final ms = timeMs(runCpu);
      final stereoPct = 2 * ms / 10000 * 100;
      final g = gains.map((x) => x.toStringAsFixed(2)).join('/');
      stdout.writeln(
          '${"$inRate->$outRate".padRight(13)} ${algo.padRight(6)} ${g.padRight(29)} ${spur.toStringAsFixed(1).padRight(11)} ${aliasStr.padRight(13)} ${ms.toStringAsFixed(1).padRight(10)} ${stereoPct.toStringAsFixed(2)}');
      final key = '$inRate->$outRate';
      if (algo == 'sinc') {
        droopSinc09[key] = gains[4];
        cpuStereoPct[key] = stereoPct;
        summary['$key:spur'] = spur;
      } else {
        summary['$key:spurL'] = spur;
      }
      // prevent dead-code elimination from dropping cpuOut
      if (cpuOut[0] == 123456789) stdout.writeln('unreachable');
    }
    stdout.writeln(
        '  filter $inRate->$outRate: cutoff=${repo.cutoff.toStringAsFixed(4)} halfWidth=${repo.halfWidth} taps=${repo.taps} down=${repo.isDownsampling}');
  }
  double imp(String k) =>
      summary['$k:spurL']! - summary['$k:spur']!; // linear - sinc, positive = sinc better (more negative spur is better)
  stdout.writeln('DECISION RULE:');
  final k1 = '49716->44100', k2 = '11000->44100';
  stdout.writeln(' spur improvement $k1: ${imp(k1).toStringAsFixed(1)} dB (>=20 required)');
  stdout.writeln(' spur improvement $k2: ${imp(k2).toStringAsFixed(1)} dB (>=20 required)');
  stdout.writeln(
      ' droop@0.9 $k1 sinc: ${droopSinc09[k1]!.toStringAsFixed(2)} dB (abs<=0.5 required)');
  stdout.writeln(
      ' stereo CPU $k1 sinc: ${cpuStereoPct[k1]!.toStringAsFixed(2)}% (<5 required)');
  final ship = imp(k1) >= 20 &&
      imp(k2) >= 20 &&
      droopSinc09[k1]!.abs() <= 0.5 &&
      cpuStereoPct[k1]! < 5;
  stdout.writeln(ship ? 'VERDICT: SHIP sinc' : 'VERDICT: STOP - keep linear');
}
