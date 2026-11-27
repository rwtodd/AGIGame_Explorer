import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Programs one channel (0) with a deterministic register sequence.
///
/// Carrier offset = modulator + 3. Mod default: MULT=1 (value 1), TL=0,
/// AR/DR/SL/RR = 10/10/8/10, EG-type on (sustain). Values overridable.
void programChannel(
  Opl2Chip chip, {
  int channel = 0,
  int fnum = 0x200,
  int block = 4,
  int modMult = 1,
  int carMult = 1,
  int modTl = 63,
  int carTl = 0,
  int modAr = 10,
  int modDr = 10,
  int modSl = 8,
  int modRr = 10,
  int carAr = 10,
  int carDr = 10,
  int carSl = 8,
  int carRr = 10,
  bool egType = true,
  bool modAm = false,
  bool modVib = false,
  bool carAm = false,
  bool carVib = false,
  int modWave = 0,
  int carWave = 0,
  int modKsl = 0,
  int carKsl = 0,
  int feedback = 0,
  int connection = 0,
  bool keyOn = true,
}) {
  const offsets = [0, 1, 2, 8, 9, 10, 16, 17, 18];
  final base = offsets[channel];
  int op20(int mult, bool am, bool vib, bool eg) =>
      (am ? 0x80 : 0) | (vib ? 0x40 : 0) | (eg ? 0x20 : 0) | mult;
  chip.writeRegister(0x20 + base, op20(modMult, modAm, modVib, egType));
  chip.writeRegister(0x23 + base, op20(carMult, carAm, carVib, egType));
  chip.writeRegister(0x40 + base, (modKsl << 6) | modTl);
  chip.writeRegister(0x43 + base, (carKsl << 6) | carTl);
  chip.writeRegister(0x60 + base, (modAr << 4) | modDr);
  chip.writeRegister(0x63 + base, (carAr << 4) | carDr);
  chip.writeRegister(0x80 + base, (modSl << 4) | modRr);
  chip.writeRegister(0x83 + base, (carSl << 4) | carRr);
  chip.writeRegister(0xE0 + base, modWave);
  chip.writeRegister(0xE3 + base, carWave);
  chip.writeRegister(0xC0 + channel, (feedback << 1) | connection);
  chip.writeRegister(0xA0 + channel, fnum & 0xFF);
  chip.writeRegister(
    0xB0 + channel,
    (keyOn ? 0x20 : 0) | (block << 2) | ((fnum >> 8) & 0x03),
  );
}

double rms(Int16List b, int start, int end) {
  var s = 0;
  for (var i = start; i < end; i++) {
    s += b[i] * b[i];
  }
  final n = end - start;
  return n == 0 ? 0 : math.sqrt(s / n);
}

double peak(Int16List b) {
  var p = 0;
  for (final v in b) {
    final a = v.abs();
    if (a > p) p = a;
  }
  return p.toDouble();
}

/// Counts positive-going zero crossings and returns up-crossing frame idx.
List<int> upCrossings(Int16List b) {
  final out = <int>[];
  for (var i = 1; i < b.length; i++) {
    if (b[i - 1] < 0 && b[i] >= 0) out.add(i);
  }
  return out;
}

double measuredFreqHz(Int16List b) {
  final c = upCrossings(b);
  if (c.length < 2) return 0;
  final span = c.last - c.first;
  return (c.length - 1) * kOpl2SampleRate / span;
}

/// Peak-amplitude estimate at one exact frequency over a window, via the
/// Goertzel recurrence (rectangular window). Best used at frequencies
/// computed from the documented phase increment (exact harmonics), and over
/// windows spanning many periods.
double goertzelAmp(Int16List b, int start, int end, double freqHz) {
  final w = 2 * math.pi * freqHz / kOpl2SampleRate;
  final cw = math.cos(w);
  var s0 = 0.0, s1 = 0.0, s2 = 0.0;
  for (var i = start; i < end; i++) {
    s0 = b[i] + 2 * cw * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final power = s1 * s1 + s2 * s2 - 2 * cw * s1 * s2;
  return math.sqrt(power / ((end - start) * (end - start) / 4.0));
}

void main() {
  test('reset silence after reset', () {
    final chip = Opl2Chip();
    final out = Int16List(1000);
    chip.generate(out, 1000);
    expect(peak(out), 0);
  });

  test('no key-on produces silence even with registers programmed', () {
    final chip = Opl2Chip();
    programChannel(chip, keyOn: false);
    final out = Int16List(4972); // 0.1s
    chip.generate(out, 4972);
    expect(peak(out), 0);
  });

  test('reset determinism and block-size invariance', () {
    Opl2Chip make() {
      final c = Opl2Chip();
      programChannel(c, fnum: 0x2A1, block: 4);
      return c;
    }

    Int16List run(int blockSize) {
      final c = make();
      final out = Int16List(4972);
      var pos = 0;
      while (pos < out.length) {
        final n = math.min(blockSize, out.length - pos);
        c.generate(Int16List.sublistView(out, pos), n);
        pos += n;
      }
      return out;
    }

    final a = run(4972);
    final b = run(1);
    final c = run(17);
    expect(b, equals(a));
    expect(c, equals(a));
    expect(peak(a), greaterThan(0));
    // Second run from reset = identical.
    expect(run(512), equals(run(512)));
  });

  test('key on/off audible then releases to silence', () {
    final chip = Opl2Chip();
    programChannel(chip, carRr: 15, modRr: 15);
    final on = Int16List(4972);
    chip.generate(on, 4972);
    expect(rms(on, 2000, 4972), greaterThan(100));
    // Key off.
    chip.writeRegister(0xB0, 0x10); // block 4, key off
    final off = Int16List(49716); // 1s
    chip.generate(off, 49716);
    expect(rms(off, 40000, 49716), lessThan(rms(off, 0, 5000)));
    expect(rms(off, 45000, 49716), lessThan(50));
  });

  test('tuning matches fnum/block formula (MULT=1, carrier only)', () {
    // Case 1: fnum 0x200, block 4 => f = 512*49716/2^16 = 388.4 Hz
    {
      final chip = Opl2Chip();
      programChannel(chip, fnum: 0x200, block: 4);
      final out = Int16List(49716); // 1s
      chip.generate(out, 49716);
      final f = measuredFreqHz(Int16List.sublistView(out, 5000));
      expect(f, closeTo(388.4, 388.4 * 0.03));
    }
    // Case 2: different block and MULT=2 (register value 2).
    {
      final chip = Opl2Chip();
      programChannel(chip, fnum: 0x180, block: 5, carMult: 2);
      final out = Int16List(49716);
      chip.generate(out, 49716);
      // f = 384*49716/2^15 * 2 = 1165.6 Hz
      final f = measuredFreqHz(Int16List.sublistView(out, 5000));
      expect(f, closeTo(1165.6, 1165.6 * 0.04));
    }
  });

  test('envelope: attack rises, decay falls, sustain holds, release falls',
      () {
    final chip = Opl2Chip();
    // Slowish attack (AR=5, eff=22, tau~=5370 samples, -3 dB at ~133 ms),
    // slow measured decay (DR=2, ~7 dB/s), audible sustain at SL=4.
    // With the measured curves AR=0 would not finish its attack in 1 s.
    programChannel(chip,
        carAr: 5, carDr: 2, carSl: 4, egType: true, carRr: 10,
        modTl: 63, modAr: 15, modDr: 15, modRr: 15);
    final out = Int16List(49716); // 1s key-on
    chip.generate(out, 49716);
    final early = rms(out, 500, 2000);
    final peakWin = rms(out, 25000, 30000);
    final mid = rms(out, 35000, 40000);
    final late = rms(out, 40000, 49716);
    expect(peakWin, greaterThan(early));
    // Decay: peak window louder than later windows.
    expect(mid, lessThan(peakWin));
    // Sustain holds roughly level (not silent, not decaying away).
    expect(late, greaterThan(100));
    expect(late, greaterThan(mid * 0.5));
  });

  // Envelope anchors measured black-box against a Nuked OPL reference
  // capture (PQ2 sound 1, 2026-11-26). Setup shared by the three anchor
  // tests: block 4 / fnum 0x200 / KSR off gives ksn=9, rateOffset=2, so
  // eff = 4*rate + 2. Additive connection, silent modulator, sine wave.
  // Decay anchor: DR=2 (eff=10) decays at ~7 dB/s (formula 1.24*2^(eff/4)).
  test('anchor: decay at eff=10 is ~7 dB/s', () {
    final chip = Opl2Chip();
    programChannel(chip,
        fnum: 0x200, block: 4, modTl: 63, carTl: 0, carAr: 15, carDr: 2,
        carSl: 15, carRr: 15, modAr: 15, modDr: 15, modRr: 15,
        connection: 1, egType: true);
    final out = Int16List(49716); // 1 s
    chip.generate(out, out.length);
    // Windows 0.5 s apart, long enough for stable RMS at 388 Hz.
    final start = rms(out, 2000, 7000);
    final end = rms(out, 26858, 31858);
    expect(start, greaterThan(1000));
    final dropDb = 20 * math.log(start / end) / math.ln10;
    // Expect ~3.5 dB over 0.5 s, +/-35%.
    expect(dropDb, inInclusiveRange(3.5 * 0.65, 3.5 * 1.35));
  });

  // Attack anchor: AR=6 (eff=26) reaches -3 dB of peak in ~67 ms
  // (tau~=2685 samples, t(-3dB)=1.23*tau) and -20 dB in <=20 ms
  // (measured: -20/-6/-3 dB at ~10/44/67 ms, ratio ~6.7).
  test('anchor: attack at eff=26 reaches -3 dB in 45..95 ms, -20 dB <=20 ms',
      () {
    final chip = Opl2Chip();
    programChannel(chip,
        fnum: 0x200, block: 4, modTl: 63, carTl: 0, carAr: 6, carDr: 0,
        carSl: 15, carRr: 15, modAr: 15, modDr: 15, modRr: 15,
        connection: 1, egType: true);
    final out = Int16List(12000); // ~0.24 s
    chip.generate(out, out.length);
    const win = 128; // one period at 388 Hz
    final peak = rms(out, 8000, 11000);
    expect(peak, greaterThan(1000));
    double timeTo(double db) {
      final target = peak * math.pow(10, db / 20.0).toDouble();
      for (var s = 0; s + win <= out.length; s += 32) {
        if (rms(out, s, s + win) >= target) {
          return s * 1000.0 / kOpl2SampleRate;
        }
      }
      return -1.0;
    }

    final t3 = timeTo(-3.0);
    final t20 = timeTo(-20.0);
    expect(t3, greaterThan(0));
    expect(t20, greaterThan(0));
    expect(t3, inInclusiveRange(45.0, 95.0));
    expect(t20, lessThanOrEqualTo(20.0));
  });

  // Release anchor: RR=6 (eff=26) shares the decay curve,
  // ~112 dB/s nominal (~11 dB per 100 ms).
  test('anchor: release at eff=26 falls 5..20 dB per 100 ms', () {
    final chip = Opl2Chip();
    programChannel(chip,
        fnum: 0x200, block: 4, modTl: 63, carTl: 0, carAr: 15, carDr: 2,
        carSl: 15, carRr: 6, modAr: 15, modDr: 15, modRr: 15,
        connection: 1, egType: true);
    final on = Int16List(49716); // 1 s key-on (decay at ~7 dB/s)
    chip.generate(on, on.length);
    chip.writeRegister(0xB0, 0x10); // block 4, key off
    final off = Int16List(4972); // 0.1 s release
    chip.generate(off, off.length);
    // Window just before key-off vs window ~90 ms after.
    final before = rms(on, 49716 - 2000, 49716);
    final after = rms(off, 2500, 4500);
    expect(before, greaterThan(1000));
    expect(after, greaterThan(10));
    final dropDb = 20 * math.log(before / after) / math.ln10;
    expect(dropDb, inInclusiveRange(5.0, 20.0));
  });

  test('percussive envelope decays to silence without key-off', () {
    final chip = Opl2Chip();
    programChannel(chip,
        carAr: 15, carDr: 12, carSl: 4, egType: false, modTl: 63,
        modAr: 15, modDr: 15);
    final out = Int16List(49716 * 2);
    chip.generate(out, out.length);
    expect(rms(out, 90000, out.length), lessThan(50));
  });

  test('sine waveform peaks near T/4 and mirrors around the peak', () {
    final chip = Opl2Chip();
    // Sustained sine carrier (instant attack, sustain at 0 dB); additive
    // connection so modulator FM cannot distort the carrier shape.
    programChannel(chip,
        fnum: 0x200, block: 4, modTl: 63, carTl: 0, carAr: 15, carDr: 0,
        carSl: 0, modAr: 15, modDr: 0, modSl: 0, connection: 1);
    final out = Int16List(49716);
    chip.generate(out, out.length);
    // Steady state region; anchor measurements on an output up-crossing so
    // phase-increment-before-output alignment is accounted for.
    final slice = Int16List.sublistView(out, 10000);
    final c = upCrossings(slice);
    expect(c.length, greaterThan(2));
    final u = c[1];
    // Nominal period from the documented phase increment (phase advances
    // before output, but the up-crossing anchor absorbs that offset):
    // inc = fnum(0x200) * MULT(1) * 2^block(4) => period 2^20/8192 = 128.
    const period = 128;
    var peakIdx = u;
    for (var i = u; i < u + period; i++) {
      if (slice[i] > slice[peakIdx]) peakIdx = i;
    }
    final peakOffset = (peakIdx - u) / period;
    // Peak within ~1/16 period of T/4.
    expect(peakOffset, closeTo(0.25, 0.0625));
    final peakVal = slice[peakIdx].abs();
    expect(peakVal, greaterThan(3000));
    // Symmetric points either side of the peak (T/4 +- T/16) are
    // approximately equal for a true sine; a sawtooth-shaped waveform
    // (unmirrored quarter table) differs by >50% of peak here.
    final pre = slice[u + (3 * period / 16).round()];
    final post = slice[u + (5 * period / 16).round()];
    expect((pre - post).abs(), lessThan(peakVal * 0.15));
  });

  test('key scale: KSL=3 attenuates higher block; KSL=0 does not', () {
    double steadyRms(int block, int ksl) {
      final chip = Opl2Chip();
      programChannel(chip,
          fnum: 0x200, block: block, modTl: 63, carKsl: ksl, carTl: 0,
          carAr: 15, carDr: 0, carSl: 0, modAr: 15, modDr: 0, modSl: 0,
          connection: 1);
      final out = Int16List(49716);
      chip.generate(out, out.length);
      // Steady state over equal sample counts (long window: many periods
      // at both frequencies, so RMS compares amplitude, not cycle count).
      return rms(out, 25000, 49716);
    }

    final lo = steadyRms(2, 3);
    final hi = steadyRms(6, 3);
    expect(lo, greaterThan(300));
    // 4 block steps at 6 dB/octave => ~24 dB down, clearly lower.
    expect(hi, lessThan(lo * 0.3));
    // KSL=0: no key scaling, RMS approximately equal across blocks.
    final lo0 = steadyRms(2, 0);
    final hi0 = steadyRms(6, 0);
    final ratio = hi0 / lo0;
    expect(ratio, greaterThan(0.9));
    expect(ratio, lessThan(1.1));
  });

  test('percussive envelope decays past SL to silence (mid SL)', () {
    final chip = Opl2Chip();
    programChannel(chip,
        carAr: 15, carDr: 8, carSl: 5, egType: false, modTl: 63,
        modAr: 15, modDr: 15, connection: 1);
    final out = Int16List(49716);
    chip.generate(out, out.length);
    // Audible early (decay from peak), near silent later without key-off.
    expect(rms(out, 0, 200), greaterThan(500));
    expect(rms(out, 40000, 49716), lessThan(50));
  });

  // Percussive (EG-type=0): DR takes the envelope to SL, then RR takes
  // over even while the key stays on. With fast DR (12), SL=0 (0 dB) and
  // slow RR (1), the note must still be clearly audible 100-200 ms after
  // the instant attack; the old DR-continued behavior (DR=12, ~7k dB/s)
  // would be essentially silent within ~15 ms.
  test('percussive EG-type=0: fast DR to SL then slower RR stays audible',
      () {
    final chip = Opl2Chip();
    programChannel(chip,
        carAr: 15,
        carDr: 12,
        carSl: 0,
        carRr: 1,
        egType: false,
        modTl: 63,
        modAr: 15,
        modDr: 15,
        connection: 1);
    final out = Int16List(49716); // 1 s key-on, never released
    chip.generate(out, out.length);
    final early = rms(out, 200, 1200);
    expect(early, greaterThan(1000));
    // 100-200 ms after attack: RR=1 (eff=6, ~3.5 dB/s) leaves the
    // envelope within ~1 dB of peak, so RMS stays near the early level.
    final late = rms(out, 5000, 10000);
    expect(late, greaterThan(1000));
    expect(late, greaterThan(early * 0.5));
    // Envelope continues to fall at the RR slope, not the DR slope:
    // a later window is measurably quieter than the early one.
    final later = rms(out, 30000, 40000);
    expect(later, lessThan(late));
    expect(later, greaterThan(100));
  });

  test('total level: higher TL is strictly quieter (monotonic)', () {
    double level(int tl) {
      final chip = Opl2Chip();
      programChannel(chip, carTl: tl, modTl: 63, carAr: 15, carDr: 0,
          carSl: 0, modAr: 15, modDr: 15);
      final out = Int16List(4972);
      chip.generate(out, 4972);
      return rms(out, 2000, 4972);
    }

    final l0 = level(0);
    final l10 = level(10);
    final l30 = level(30);
    final l63 = level(63);
    expect(l0, greaterThan(l10));
    expect(l10, greaterThan(l30));
    expect(l30, greaterThan(l63));
  });

  test('waveform 1 (half-sine) has no significant negative excursions', () {
    final chip = Opl2Chip();
    programChannel(chip, carWave: 1, modTl: 63, carAr: 15, carDr: 0,
        carSl: 0, modAr: 15, modDr: 15);
    final out = Int16List(4972);
    chip.generate(out, 4972);
    var minV = 0;
    for (final v in out) {
      if (v < minV) minV = v;
    }
    expect(minV, greaterThan(-50));
    expect(peak(out), greaterThan(500));
  });

  test('waveform 2 (abs sine) has no negative excursions', () {
    final chip = Opl2Chip();
    programChannel(chip, carWave: 2, modTl: 63, carAr: 15, carDr: 0,
        carSl: 0, modAr: 15, modDr: 15);
    final out = Int16List(4972);
    chip.generate(out, 4972);
    var minV = 0;
    for (final v in out) {
      if (v < minV) minV = v;
    }
    expect(minV, greaterThan(-50));
  });

  test('feedback changes output measurably; additive differs from FM', () {
    Int16List render({int fb = 0, int conn = 0}) {
      final chip = Opl2Chip();
      programChannel(chip,
          modTl: 0, carTl: 0, feedback: fb, connection: conn,
          carAr: 15, carDr: 0, carSl: 0, modAr: 15, modDr: 0,
          modSl: 0, modMult: 1);
      final out = Int16List(4972);
      chip.generate(out, 4972);
      return out;
    }

    final noFb = render(fb: 0);
    final withFb = render(fb: 5);
    expect(peak(withFb), greaterThan(0));
    final diffRms = rms(
      Int16List.fromList(List.generate(4972, (i) => withFb[i] - noFb[i])),
      1000,
      4972,
    );
    expect(diffRms, greaterThan(10));
    final fm = render(conn: 0);
    final add = render(conn: 1);
    final fmAddDiff = rms(
      Int16List.fromList(List.generate(4972, (i) => fm[i] - add[i])),
      1000,
      4972,
    );
    expect(fmAddDiff, greaterThan(10));
  });

  // FM pitch integrity + harmonic richness (synthetic patch43-like program,
  // fitted black-box to a 2026-11-26 PQ2 capture): both ops MULT=0 (0.5x),
  // feedback=7, mod TL=28 (mod amp ~=0.089), carrier TL=3, fast attack, EG
  // sustain. Deviation is lookup-only PM (4 cycles full-scale, ~2.2 rad
  // index here), so the spectrum is a harmonic stack at the carrier, not a
  // shifted sideband. The old accumulating implementation rendered a
  // dominant ~440 Hz component with a near-absent fundamental here.
  test('FM keeps carrier pitch and harmonic stack (patch43-like)', () {
    const fnum = 0x300;
    const block = 5;
    final chip = Opl2Chip();
    programChannel(chip,
        fnum: fnum, block: block, modMult: 0, carMult: 0, modTl: 28,
        carTl: 3, modAr: 15, carAr: 15, modDr: 0, carDr: 0, modSl: 0,
        carSl: 0, feedback: 7, connection: 0, egType: true);
    // Expected carrier from the documented phase increment:
    // f = fnum * SR / 2^(20-block) * MULTscale(0) ~= 582.6 Hz.
    final expected = fnum * kOpl2SampleRate / (1 << (20 - block)) * 0.5;
    final out = Int16List(49716);
    chip.generate(out, out.length);
    // Post-attack sustained window.
    final h1 = goertzelAmp(out, 20000, 40000, expected);
    // Fundamental is a strong bin at the carrier frequency.
    expect(h1, greaterThan(100));
    // No dominant wrong sideband: fundamental dwarfs non-harmonic bins.
    final wrong = goertzelAmp(out, 20000, 40000, 441.0);
    final half = goertzelAmp(out, 20000, 40000, expected * 1.5);
    expect(h1, greaterThan(wrong * 5));
    expect(h1, greaterThan(half * 5));
    // Harmonic richness: H2 is within the measured stack (H2/H1 ~= 1.3),
    // far above a lone sine (the old bug's output).
    final h2 = goertzelAmp(out, 20000, 40000, expected * 2);
    expect(h2 / h1, greaterThan(0.4));
  });

  // PM must not drift or shift pitch over time: zero-crossing rate in an
  // early and a late post-attack window agree within 2%, and equal
  // 2x the carrier (with ~2.2 rad index the PM phase is non-monotonic,
  // giving two zero crossings per carrier period). The accumulating bug
  // settled at ~437 Hz in this same setup.
  test('FM pitch does not drift (early vs late windows)', () {
    const fnum = 0x300;
    const block = 5;
    final chip = Opl2Chip();
    programChannel(chip,
        fnum: fnum, block: block, modMult: 0, carMult: 0, modTl: 28,
        carTl: 3, modAr: 15, carAr: 15, modDr: 0, carDr: 0, modSl: 0,
        carSl: 0, feedback: 7, connection: 0, egType: true);
    final expected = fnum * kOpl2SampleRate / (1 << (20 - block)) * 0.5;
    final out = Int16List(49716);
    chip.generate(out, out.length);
    final early = measuredFreqHz(Int16List.sublistView(out, 5000, 20000));
    final late = measuredFreqHz(Int16List.sublistView(out, 20000, 40000));
    expect(late, closeTo(early, early * 0.02));
    expect(late, closeTo(expected * 2, expected * 2 * 0.03));
  });

  test('AM modulates amplitude over time; VIB varies instantaneous rate', () {
    // AM: sustained envelope, RMS of early vs later 3.7Hz-phase windows.
    {
      final chipOn = Opl2Chip();
      programChannel(chipOn,
          carAm: true, modTl: 63, carAr: 15, carDr: 0, carSl: 0,
          modAr: 15, modDr: 15);
      chipOn.writeRegister(0xBD, 0x80); // AM depth 4.8 dB
      final on = Int16List(49716 * 2);
      chipOn.generate(on, on.length);
      final offChip = Opl2Chip();
      programChannel(offChip,
          carAm: false, modTl: 63, carAr: 15, carDr: 0, carSl: 0,
          modAr: 15, modDr: 15);
      offChip.writeRegister(0xBD, 0x80);
      final off = Int16List(49716 * 2);
      offChip.generate(off, off.length);
      // AM LFO period ~0.27s: compare windowed RMS variation across LFO.
      var maxR = 0.0;
      var minR = double.infinity;
      for (var s = 0; s < 20; s++) {
        final r = rms(on, s * 2500, s * 2500 + 2500);
        if (r > maxR) maxR = r;
        if (r < minR) minR = r;
      }
      var maxOff = 0.0;
      var minOff = double.infinity;
      for (var s = 0; s < 20; s++) {
        final r = rms(off, s * 2500, s * 2500 + 2500);
        if (r > maxOff) maxOff = r;
        if (r < minOff) minOff = r;
      }
      expect(maxR - minR, greaterThan(maxOff - minOff + 20));
    }
    // VIB: zero-crossing intervals vary with VIB on vs off.
    {
      List<double> intervals(bool vib) {
        final chip = Opl2Chip();
        programChannel(chip,
            fnum: 0x2A0, block: 4, carVib: vib, modTl: 63,
            carAr: 15, carDr: 0, carSl: 0, modAr: 15, modDr: 15);
        chip.writeRegister(0xBD, 0x40); // vibrato depth 14 cents
        final out = Int16List(49716);
        chip.generate(out, 49716);
        final c = upCrossings(Int16List.sublistView(out, 5000));
        return [for (var i = 1; i < c.length; i++) (c[i] - c[i - 1]).toDouble()];
      }

      final on = intervals(true);
      final off = intervals(false);
      double cv(List<double> v) {
        final mean = v.reduce((a, b) => a + b) / v.length;
        final varr = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length;
        return math.sqrt(varr) / mean;
      }

      expect(cv(on), greaterThan(cv(off) * 1.2));
    }
  });

  test('snapshot decodes programmed registers; write-log records', () {
    final chip = Opl2Chip();
    chip.writeLogEnabled = true;
    programChannel(chip,
        fnum: 0x1A3, block: 5, carMult: 2, carTl: 20, feedback: 3,
        connection: 1);
    chip.writeRegister(0xBD, 0xC0);
    chip.writeRegister(0x08, 0x40);
    final snap = chip.snapshot();
    expect(snap.channels[0].fnum, 0x1A3);
    expect(snap.channels[0].block, 5);
    expect(snap.channels[0].keyOn, true);
    expect(snap.channels[0].feedback, 3);
    expect(snap.channels[0].connection, 1);
    expect(snap.amDepth, true);
    expect(snap.vibDepth, true);
    expect(snap.noteSel, 1);
    final car = snap.operators[1];
    expect(car.mult, 2);
    expect(car.tl, 20);
    // Mutating chip after snapshot does not affect the copy.
    chip.writeRegister(0xB0, 0x14);
    expect(snap.channels[0].block, 5);
    // Write log.
    final log = chip.writeLog;
    expect(log.length, greaterThan(10));
    expect(log.first.frameIndex, 0);
    expect(log.first.address, 0x20);
    chip.generate(Int16List(10), 10);
    chip.writeRegister(0xBD, 0x00);
    expect(chip.writeLog.last.frameIndex, 10);
    chip.clearWriteLog();
    expect(chip.writeLog, isEmpty);
  });

  test('loud multi-channel program saturates, never wraps, RMS sane', () {
    final chip = Opl2Chip();
    for (var ch = 0; ch < 9; ch++) {
      programChannel(chip, channel: ch, modTl: 0, carTl: 0, carAr: 15,
          carDr: 0, carSl: 0, modAr: 15, modDr: 0, modSl: 0);
    }
    final out = Int16List(49716);
    chip.generate(out, out.length);
    for (final v in out) {
      expect(v, inInclusiveRange(-32768, 32767));
    }
    // No opposite-sign jumps beyond int16 wraps: adjacent diff bounded.
    var maxJump = 0;
    for (var i = 1; i < out.length; i++) {
      final d = (out[i] - out[i - 1]).abs();
      if (d > maxJump) maxJump = d;
    }
    expect(maxJump, lessThan(65536));
    expect(rms(out, 0, out.length), lessThanOrEqualTo(32768));
    expect(peak(out), lessThanOrEqualTo(32768));
    // Should have hit the clipper (loud program).
    expect(peak(out), greaterThan(30000));
  });

  test('generate validates output length', () {
    final chip = Opl2Chip();
    expect(() => chip.generate(Int16List(4), 8), throwsArgumentError);
  });

  test('registers mask address/value to 8 bits', () {
    final chip = Opl2Chip();
    chip.writeRegister(0x1BD, 0x100);
    expect(chip.readRegister(0xBD), 0);
    chip.writeRegister(0xBD, 0xC0);
    expect(chip.readRegister(0xBD), 0xC0);
  });

  test('performance smoke: 5s of 9-channel audio', () {
    final chip = Opl2Chip();
    for (var ch = 0; ch < 9; ch++) {
      programChannel(chip, channel: ch, modTl: 10, carTl: 5, carAr: 12,
          carDr: 8, carSl: 4, modAr: 12, modDr: 8);
    }
    final out = Int16List(49716 * 5);
    final sw = Stopwatch()..start();
    chip.generate(out, out.length);
    final ms = sw.elapsedMilliseconds;
    // Report for the plan budget comparison; generous assert only.
    // ignore: avoid_print
    print('Opl2 5s render: $ms ms');
    expect(ms, lessThan(5000));
    expect(peak(out), greaterThan(0));
  });
}
