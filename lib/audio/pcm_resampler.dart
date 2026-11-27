// Measured windowed-sinc resampler (Stage 8 slice 2).
//
// Replaces the Stage 6 labelled-linear choice for the 49,716 Hz OPL
// output and for SCI digital samples (3,750--20,000 Hz) to the sink
// rate (44,100 / 48,000). Identity rate is a true bypass.
//
// Design (standard DSP, no copied implementation):
//   Cutoff fc = transitionFactor * min(inputRate, outputRate) / (2 * inputRate)
//     i.e. min-Nyquist scaled by [transitionFactor]. Downsampling
//     widens the kernel automatically because fc (cycles per input
//     sample) drops with output/input, so the zero-crossing count
//     Z maps to half-width W = ceil(Z / (2*fc)) input samples.
//   Kernel h(x) = 2*fc * sinc(2*fc*x) * w(x/W), sinc(y)=sin(pi*y)/(pi*y),
//     w = 4-term Blackman-Harris (a0..a3 = 0.35875, 0.48829, 0.14128,
//     0.01168; -92 dB sidelobes, cos-sum only so no Bessel table).
//     Chosen over plain Blackman (-58 dB) to clear the 60 dB target
//     at this kernel length, and over Kaiser to avoid a Bessel
//     implementation: BH gives the needed attenuation with a
//     3-cosine window and exact unity normalization below.
//   Zero crossings Z = 32 per side, transitionFactor = 0.97 =>
//     66--76 taps for the production pairs (W ~= 38 downsample
//     49716->44100, W ~= 33 upsample 11000->44100). Measured:
//     passband gain 0.00 dB to 0.7x min-Nyquist, -0.11 dB at 0.9x;
//     spur -73 dB vs linear -5 dB; stereo 49716->44100 CPU ~3% of one
//     core. 0.95 rolled off -0.54 dB at 0.9x, so 0.97 was chosen;
//     48 crossings fixed droop but pushed CPU to ~4.5%.
//     halfWidth <= 38 < 1024 native block, so the OPL history proof holds.
//   Coefficients are precomputed on a 1/2048 fractional-phase grid per
//     rate-pair instance (never per sample), each phase normalized so
//     sum(coeffs) == 1 exactly (DC gain 1 despite window truncation).
//     Nearest-phase lookup; max input-position error 1/4096 sample,
//     ~ -70 dB worst-case phase noise, under the 60 dB spur budget.
//     Selection is a pure function of input position + accessor:
//     deterministic, call-order / block-split independent, zero-phase
//     (centered kernel, no time shift vs frame j -> j*in/out).
//   Edge policy: accessor returns 0 outside [0, inputLength); the full
//     kernel is applied (no edge renormalization), so the stream ends
//     fade over half a kernel toward silence. No allocation in
//     evaluate; the only table is the Float64List above.
//
// Numbers (passband / spur / CPU) live in tool/measure_resampler.dart
// output; the plan gate is the measured choice, not sinc at any cost.

import 'dart:math' as math;
import 'dart:typed_data';

class PcmResampler {
  final int inputRate;
  final int outputRate;

  /// Cutoff scale relative to min-Nyquist (transition band between
  /// ~0.92 and 1.00 * min-Nyquist).
  static const double transitionFactor = 0.97;

  /// Zero crossings per side of the truncated sinc.
  static const int zeroCrossings = 32;

  /// Fractional-phase resolution of the coefficient table.
  static const int phaseCount = 2048;

  /// 4-term Blackman-Harris coefficients a0..a3.
  static const double _bhA0 = 0.35875;
  static const double _bhA1 = 0.48829;
  static const double _bhA2 = 0.14128;
  static const double _bhA3 = 0.01168;

  /// Cutoff in cycles per input sample; 0.5 for identity (unused).
  final double cutoff;

  /// Kernel half-width W in input samples (support [-W+1, W] offsets).
  final int halfWidth;

  /// Number of taps, 2 * halfWidth.
  final int taps;

  final Float64List _coeffs;

  final bool _identity;

  /// Whether this instance is a true bypass (inputRate == outputRate).
  bool get isIdentity => _identity;

  /// Downsampling when true (inputRate > outputRate); the kernel
  /// widens as input/output via [cutoff] / [halfWidth].
  bool get isDownsampling => inputRate > outputRate;

  /// Shared instances by rate pair. Instances are immutable after
  /// construction, and sources are rebuilt per sound start / loop
  /// replay, so caching keeps the ~150k-coefficient table build to
  /// once per pair (a handful of pairs occur in practice).
  static final Map<int, PcmResampler> _cache = <int, PcmResampler>{};

  factory PcmResampler(int inputRate, int outputRate) =>
      _cache.putIfAbsent(
        (inputRate << 32) | outputRate,
        () => PcmResampler._build(inputRate, outputRate),
      );

  factory PcmResampler._build(int inputRate, int outputRate) {
    if (inputRate <= 0 || outputRate <= 0) {
      throw ArgumentError('rates must be > 0: $inputRate -> $outputRate');
    }
    if (inputRate == outputRate) {
      return PcmResampler._(inputRate, outputRate, 0.5, 1, 1,
          Float64List(0), true);
    }
    final minRate = inputRate < outputRate ? inputRate : outputRate;
    final cutoff = transitionFactor * minRate / (2 * inputRate);
    final halfWidth = (zeroCrossings / (2 * cutoff)).ceil();
    final taps = 2 * halfWidth;
    final coeffs = Float64List(phaseCount * taps);
    final scale = 2 * cutoff;
    final pi = math.pi;
    for (var p = 0; p < phaseCount; p++) {
      final f = p / phaseCount;
      final base = p * taps;
      var sum = 0.0;
      for (var t = 0; t < taps; t++) {
        final d = -halfWidth + 1 + t; // integer offset from base floor cell
        final x = f - d; // pos - n, in [-W, W]
        final y = scale * x;
        double sinc;
        if (y == 0.0) {
          sinc = 1.0;
        } else {
          sinc = math.sin(pi * y) / (pi * y);
        }
        // Blackman-Harris window, u = x / W in [-1, 1].
        final phase = pi * (x / halfWidth + 1.0); // 0..2pi
        final w = _bhA0 -
            _bhA1 * math.cos(phase) +
            _bhA2 * math.cos(2 * phase) -
            _bhA3 * math.cos(3 * phase);
        final c = scale * sinc * w;
        coeffs[base + t] = c;
        sum += c;
      }
      final inv = 1.0 / sum;
      for (var t = 0; t < taps; t++) {
        coeffs[base + t] *= inv;
      }
    }
    return PcmResampler._(inputRate, outputRate, cutoff, halfWidth, taps,
        coeffs, false);
  }

  PcmResampler._(this.inputRate, this.outputRate, this.cutoff,
      this.halfWidth, this.taps, this._coeffs, this._identity);

  /// Input position for output frame [frame]: frame * in/out.
  /// Zero-phase: the kernel is centered on this position.
  double inputPositionForFrame(int frame) =>
      frame * inputRate / outputRate;

  /// Filtered value at fractional input position [inputPos].
  ///
  /// [read] returns the int16 sample at integer input index (0 outside
  /// the valid range). Pure function of ([read], [inputPos]): no state,
  /// no allocation, independent of call order and block splits.
  double evaluate(int Function(int inputIndex) read, double inputPos) {
    if (_identity) {
      if (inputPos.isNaN || inputPos.isInfinite) return 0;
      return read(inputPos.round()).toDouble();
    }
    if (inputPos.isNaN || inputPos.isInfinite) return 0;
    final base = inputPos.floor();
    final frac = inputPos - base;
    var phase = (frac * phaseCount).round();
    if (phase >= phaseCount) phase -= phaseCount;
    if (phase < 0) phase += phaseCount;
    final off = phase * taps;
    final w1 = -halfWidth + 1;
    double sum = 0;
    for (var t = 0; t < taps; t++) {
      final s = read(base + w1 + t);
      if (s != 0) sum += s * _coeffs[off + t];
    }
    return sum;
  }

  /// [evaluate] rounded and clamped to int16.
  int evaluateInt16(int Function(int inputIndex) read, double inputPos) =>
      evaluate(read, inputPos).round().clamp(-32768, 32767);
}
