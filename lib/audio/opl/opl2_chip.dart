// Pure Dart, clean-room YM3812 (OPL2) register-level core, mono.
//
// Implemented from the documented YM3812 register map and synthesis model
// (Yamaha datasheet behavior); no third-party emulator source was copied.
// Sine tables are generated at construction from dart:math.
//
// Goal: musical/register-level fidelity, not bit identity. Approximations
// are documented where they occur (envelope rate curves, key-scale level,
// modulation depth) — see comments near each table.
//
// Output is mono at the native 49,716 Hz rate. No allocation in steady
// state: all per-channel/operator state lives in preallocated typed arrays;
// generate() creates no per-sample objects, closures, or lists.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/opl_debug_snapshot.dart';

export 'package:flutter_agigame/audio/opl/opl_debug_snapshot.dart';

/// Native OPL2 sample rate in Hz.
const int kOpl2SampleRate = 49716;

/// Number of melodic 2-operator channels.
const int kOpl2Channels = 9;

/// Number of operators (2 per channel).
const int kOpl2Operators = 18;

/// Phase accumulator fractional resolution: 20-bit phase, values stay well
/// under 2^53 on native (64-bit signed) integers. The phase increment for a
/// channel is fnum * MULT * 2^block (integer math, deterministic).
const int _phaseBits = 20;

/// Mask for the full 20-bit phase accumulator.
const int _phaseMask = (1 << _phaseBits) - 1;

/// Quarter-wave sine table length.
const int _sineTableLen = 1024;

/// Envelope silence floor in dB attenuation (level above this = silent).
const double _silenceDb = 96.0;

/// Frequency multiplier table, index 0..15 (datasheet table).
const List<int> _multTable = [
  1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30,
];

/// Multiplier applied to the base frequency per register MULT value
/// (register value 0 => 0.5x; see [Opl2Chip] phase computation).
const List<double> _multScale = [
  0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15,
];

/// FM phase-deviation scale, in 20-bit phase units per unit modulator
/// output: 4 cycles full-scale ((1<<22) = 4 * 2^20). Fitted black-box to a
/// PQ2 patch 43 capture (ScummVM/Nuked, 2026-11-26): PM fit gave peak
/// deviation ~2.1 rad at modulator amplitude ~0.089 (TL=28), i.e. full-scale
/// deviation ~24 rad ~ 3.8 cycles; 4 cycles adopted. Applies only to the
/// waveform lookup phase, never the phase accumulator.
const int _fmDeviationScale = 1 << 22;

/// Feedback gains (dimensionless, includes the pi factor documented in the
/// datasheet: pi/16, pi/8, pi/4, pi/2, pi, 2pi, 4pi). Calibrated black-box
/// against a ScummVM/Nuked capture of the synthetic calibration kit
/// (2026-11-26): a joint PM/feedback simulation fit against the feedback
/// ladder (programs 12-19 harmonic stacks) minimized error with the
/// post-attenuation avg-of-previous-two tap and deviation scale of 4 cycles,
/// but with feedback gains TWICE the datasheet table (mean log-harmonic
/// error 0.100 at x2 vs best alternatives >=0.177 at other scalings).
const List<double> _feedbackGains = [
  0.0,
  math.pi / 16,
  math.pi / 8,
  math.pi / 4,
  math.pi / 2,
  math.pi,
  2 * math.pi,
  4 * math.pi,
];

/// Key-scale attenuation slopes in dB per octave for KSL = 0..3. Measured
/// black-box on calibration programs 39-42 (notes 36..96, all C's,
/// fnum=345) against a ScummVM/Nuked capture (2026-11-26): KSL=1
/// attenuates ~3.1 dB/octave, KSL=2 ~1.65 dB/octave, KSL=3 ~6.2 dB/octave.
/// Values 1 and 2 are swapped relative to the naive datasheet order, so
/// the table is [0, 3.0, 1.5, 6.0], not [0, 1.5, 3.0, 6.0].
const List<double> _kslSlopesDbPerOctave = [0.0, 3.0, 1.5, 6.0];

/// Precomputed key-scale attenuation table fitted from the v3 calibration
/// capture (late_test_v3.flac vs our render, 2026-11-26/27): KSL semitone
/// ladders (notes 60..72, driver fnum with block=floor(note/12)-1).
/// The old linear term `block + fnum/1024` barely moved within a block
/// then cliffed ~4 dB at the block boundary (max error 5.5 dB KSL3,
/// 2.0 dB KSL1). The reference rises in steps aligned to `fnum>>6`
/// boundaries, fitted as att = slope * max(0, coord - 1.0) with
/// coord = (block-1) + log2(rep/256) and rep = ((fnum>>6)<<6)+32
/// (max error 0.30 dB for register KSL=1 slope 3, 1.77 dB for KSL=3
/// slope 6, residual at the first two semitones likely transition
/// contamination). Flattened index ((ksl*8)+block)*16 + (fnum>>6).
/// [dart:math] log is used only here, never per sample.
final Float64List _kslTable = _buildKslTable();

Float64List _buildKslTable() {
  final table = Float64List(4 * 8 * 16);
  final ln2 = math.log(2.0);
  for (var ksl = 0; ksl < 4; ksl++) {
    final slope = _kslSlopesDbPerOctave[ksl];
    for (var block = 0; block < 8; block++) {
      for (var top = 0; top < 16; top++) {
        final rep = (top << 6) + 32;
        final coord = (block - 1) + math.log(rep / 256.0) / ln2;
        final att = slope * (coord - 1.0);
        table[((ksl * 8) + block) * 16 + top] = att < 0.0 ? 0.0 : att;
      }
    }
  }
  return table;
}

/// Modulator offsets indexed by channel (datasheet channel->operator map).
const List<int> _modOffsets = [0, 1, 2, 8, 9, 10, 16, 17, 18];

/// Envelope segments.
const int _segSilent = 0;
const int _segAttack = 1;
const int _segDecay = 2;
const int _segSustain = 3;
const int _segRelease = 4;

/// Pure Dart YM3812 (OPL2) register-level synthesizer core, mono.
final class Opl2Chip {
  static const int registerCount = 256;

  final Uint8List _regs = Uint8List(registerCount);

  // Global state.
  int _noteSel = 0;
  bool _csm = false;
  bool _amDepth = false;
  bool _vibDepth = false;
  int _rhythmBits = 0;

  // Per-channel cached decoded state (SoA, size 9).
  final Int32List _fnum = Int32List(kOpl2Channels);
  final Int32List _block = Int32List(kOpl2Channels);
  final List<bool> _keyOn = List<bool>.filled(kOpl2Channels, false);
  final Int32List _feedback = Int32List(kOpl2Channels);
  final Int32List _connection = Int32List(kOpl2Channels);

  // Per-operator cached decoded state (SoA, size 18). Index = channel*2+op.
  final Int32List _mult = Int32List(kOpl2Operators);
  final Int32List _multIdx = Int32List(kOpl2Operators);
  final List<bool> _ksr = List<bool>.filled(kOpl2Operators, false);
  final Int32List _ksl = Int32List(kOpl2Operators);
  final Int32List _tl = Int32List(kOpl2Operators);
  final Int32List _ar = Int32List(kOpl2Operators);
  final Int32List _dr = Int32List(kOpl2Operators);
  final Int32List _sl = Int32List(kOpl2Operators);
  final Int32List _rr = Int32List(kOpl2Operators);
  final List<bool> _am = List<bool>.filled(kOpl2Operators, false);
  final List<bool> _vib = List<bool>.filled(kOpl2Operators, false);
  final List<bool> _egType = List<bool>.filled(kOpl2Operators, false);
  final Int32List _wave = Int32List(kOpl2Operators);

  // Per-operator live state (SoA, size 18).
  final Int32List _phase = Int32List(kOpl2Operators);
  final Float64List _envDb = Float64List(kOpl2Operators);
  final Int32List _seg = Int32List(kOpl2Operators);
  final Float64List _prevOut = Float64List(kOpl2Operators);
  final Float64List _prevPrevOut = Float64List(kOpl2Operators);

  // LFO state (cycles [0,1)), advanced in generate() regardless of key state.
  double _amLfoPhase = 0.0;
  double _vibLfoPhase = 0.0;

  // Amplitude table: index = attenuationDb * 4, resolution 0.25 dB.
  static const double _ampStepDb = 0.25;
  static const int _ampTableLen = 641; // 0..160 dB
  final Float64List _ampTable = Float64List(_ampTableLen);

  // Quarter-wave sine table [0..1], generated from dart:math at construction.
  final Float64List _sineTable = Float64List(_sineTableLen);

  int _frameIndex = 0;

  /// Optional write-log capture (off by default).
  bool writeLogEnabled = false;
  final List<OplWriteRecord> _writeLog = <OplWriteRecord>[];

  /// Captured write records (unmodifiable view copied on read for tests;
  /// use [clearWriteLog] to drain).
  List<OplWriteRecord> get writeLog => List<OplWriteRecord>.of(_writeLog);

  /// Total frames generated since reset.
  int get frameIndex => _frameIndex;

  Opl2Chip() {
    for (var i = 0; i < _sineTableLen; i++) {
      _sineTable[i] = math.sin(0.5 * math.pi * i / _sineTableLen);
    }
    for (var i = 0; i < _ampTableLen; i++) {
      _ampTable[i] = math.pow(10.0, -(i * _ampStepDb) / 20.0).toDouble();
    }
    reset();
  }

  /// Clears registers and all operator/channel state; deterministic.
  void reset() {
    _regs.fillRange(0, registerCount, 0);
    _noteSel = 0;
    _csm = false;
    _amDepth = false;
    _vibDepth = false;
    _rhythmBits = 0;
    _fnum.fillRange(0, kOpl2Channels, 0);
    _block.fillRange(0, kOpl2Channels, 0);
    for (var i = 0; i < kOpl2Channels; i++) {
      _keyOn[i] = false;
      _feedback[i] = 0;
      _connection[i] = 0;
    }
    _mult.fillRange(0, kOpl2Operators, 0);
    _multIdx.fillRange(0, kOpl2Operators, 0);
    for (var i = 0; i < kOpl2Operators; i++) {
      _ksr[i] = false;
      _ksl[i] = 0;
      _tl[i] = 0;
      _ar[i] = 0;
      _dr[i] = 0;
      _sl[i] = 0;
      _rr[i] = 0;
      _am[i] = false;
      _vib[i] = false;
      _egType[i] = false;
      _wave[i] = 0;
      _phase[i] = 0;
      _envDb[i] = _silenceDb;
      _seg[i] = _segSilent;
      _prevOut[i] = 0.0;
      _prevPrevOut[i] = 0.0;
    }
    _amLfoPhase = 0.0;
    _vibLfoPhase = 0.0;
    _frameIndex = 0;
    _writeLog.clear();
  }

  /// Writes one register (address/value masked to 8 bits) and updates the
  /// cached decoded state. Key-on/off transitions happen here.
  void writeRegister(int address, int value) {
    final a = address & 0xFF;
    final v = value & 0xFF;
    if (writeLogEnabled) {
      _writeLog.add(
        OplWriteRecord(frameIndex: _frameIndex, address: a, value: v),
      );
    }
    _regs[a] = v;
    _decodeWrite(a, v);
  }

  /// Reads back a register (address masked to 8 bits).
  int readRegister(int address) => _regs[address & 0xFF];

  /// Clears the write log.
  void clearWriteLog() => _writeLog.clear();

  void _decodeWrite(int a, int v) {
    if (a == 0x08) {
      _noteSel = (v >> 6) & 1;
      _csm = (v & 0x01) != 0;
      return;
    }
    if (a == 0xBD) {
      _amDepth = (v & 0x80) != 0;
      _vibDepth = (v & 0x40) != 0;
      _rhythmBits = v & 0x3F;
      return;
    }
    // Store-and-ignore (documented hardware features not implemented):
    // timers/IRQ/status 0x02..0x04, test register 0x01 (waveform select
    // always works regardless of bit 5), CSM mode, composite sine mode.
    if (a == 0x01 || a == 0x02 || a == 0x03 || a == 0x04) return;

    // Channel frequency / key-on / feedback / connection.
    if (a >= 0xA0 && a <= 0xA8) {
      final ch = a - 0xA0;
      _fnum[ch] = (_fnum[ch] & 0x300) | v;
      return;
    }
    if (a >= 0xB0 && a <= 0xB8) {
      final ch = a - 0xB0;
      _fnum[ch] = (_fnum[ch] & 0xFF) | ((v & 0x03) << 8);
      _block[ch] = (v >> 2) & 0x07;
      final newKey = (v & 0x20) != 0;
      final oldKey = _keyOn[ch];
      _keyOn[ch] = newKey;
      if (newKey && !oldKey) _keyOnChannel(ch);
      if (!newKey && oldKey) _keyOffChannel(ch);
      return;
    }
    if (a >= 0xC0 && a <= 0xC8) {
      final ch = a - 0xC0;
      _feedback[ch] = (v >> 1) & 0x07;
      _connection[ch] = v & 0x01;
      return;
    }

    // Operator registers.
    for (var ch = 0; ch < kOpl2Channels; ch++) {
      final base = _modOffsets[ch];
      if (a == 0x20 + base || a == 0x23 + base) {
        _decodeOp20(ch, a == 0x23 + base, v);
        return;
      }
      if (a == 0x40 + base || a == 0x43 + base) {
        _decodeOp40(ch, a == 0x43 + base, v);
        return;
      }
      if (a == 0x60 + base || a == 0x63 + base) {
        _decodeOp60(ch, a == 0x63 + base, v);
        return;
      }
      if (a == 0x80 + base || a == 0x83 + base) {
        _decodeOp80(ch, a == 0x83 + base, v);
        return;
      }
      if (a == 0xE0 + base || a == 0xE3 + base) {
        final idx = ch * 2 + (a == 0xE3 + base ? 1 : 0);
        _wave[idx] = v & 0x03;
        return;
      }
    }
  }

  void _decodeOp20(int ch, bool carrier, int v) {
    final idx = ch * 2 + (carrier ? 1 : 0);
    _am[idx] = (v & 0x80) != 0;
    _vib[idx] = (v & 0x40) != 0;
    _egType[idx] = (v & 0x20) != 0;
    _ksr[idx] = (v & 0x10) != 0;
    _multIdx[idx] = v & 0x0F;
    _mult[idx] = _multTable[v & 0x0F];
  }

  void _decodeOp40(int ch, bool carrier, int v) {
    final idx = ch * 2 + (carrier ? 1 : 0);
    _ksl[idx] = (v >> 6) & 0x03;
    _tl[idx] = v & 0x3F;
  }

  void _decodeOp60(int ch, bool carrier, int v) {
    final idx = ch * 2 + (carrier ? 1 : 0);
    _ar[idx] = (v >> 4) & 0x0F;
    _dr[idx] = v & 0x0F;
  }

  void _decodeOp80(int ch, bool carrier, int v) {
    final idx = ch * 2 + (carrier ? 1 : 0);
    _sl[idx] = (v >> 4) & 0x0F;
    _rr[idx] = v & 0x0F;
  }

  void _keyOnChannel(int ch) {
    final m = ch * 2;
    final c = ch * 2 + 1;
    for (final idx in [m, c]) {
      _phase[idx] = 0;
      // Envelope level is intentionally NOT reset: a key-on during
      // release re-enters attack from the current attenuation (hardware
      // retrigger behavior). Dense arpeggios depend on this; restarting
      // from silence makes every retrigger swell instead of ping.
      // _envDb at chip reset is already the silence floor.
      _prevOut[idx] = 0.0;
      _prevPrevOut[idx] = 0.0;
      // Instant attack (eff >= 60) is handled at envelope advance time
      // via the effective-rate check.
      _seg[idx] = _segAttack;
    }
  }

  void _keyOffChannel(int ch) {
    final m = ch * 2;
    final c = ch * 2 + 1;
    for (final idx in [m, c]) {
      if (_seg[idx] != _segSilent && _seg[idx] != _segRelease) {
        _seg[idx] = _segRelease;
      }
    }
  }

  /// Immutable decoded view: copied values, not references into chip state.
  OplDebugSnapshot snapshot() {
    final channels = <OplChannelSnapshot>[
      for (var ch = 0; ch < kOpl2Channels; ch++)
        OplChannelSnapshot(
          channel: ch,
          fnum: _fnum[ch],
          block: _block[ch],
          keyOn: _keyOn[ch],
          feedback: _feedback[ch],
          connection: _connection[ch],
          modulatorOffset: _modOffsets[ch],
          carrierOffset: _modOffsets[ch] + 3,
        ),
    ];
    final operators = <OplOperatorSnapshot>[
      for (var ch = 0; ch < kOpl2Channels; ch++)
        for (var op = 0; op < 2; op++)
          () {
            final idx = ch * 2 + op;
            return OplOperatorSnapshot(
              channel: ch,
              operatorIndex: op,
              registerOffset: _modOffsets[ch] + (op == 1 ? 3 : 0),
              mult: _multScale[_multIdx[idx]],
              ksr: _ksr[idx] ? 1 : 0,
              ksl: _ksl[idx],
              tl: _tl[idx],
              ar: _ar[idx],
              dr: _dr[idx],
              sl: _sl[idx],
              rr: _rr[idx],
              am: _am[idx],
              vib: _vib[idx],
              egType: _egType[idx],
              waveform: _wave[idx],
              envelopeDb: _envDb[idx],
              envelopeSegment: _seg[idx],
              phase: _phase[idx],
            );
          }(),
    ];
    return OplDebugSnapshot(
      noteSel: _noteSel,
      csm: _csm,
      amDepth: _amDepth,
      vibDepth: _vibDepth,
      rhythmBits: _rhythmBits,
      channels: channels,
      operators: operators,
    );
  }

  /// Renders [frameCount] mono frames at 49,716 Hz into output[0..frameCount).
  ///
  /// No allocation in steady state: only preallocated typed arrays are
  /// touched; modulation/LFO state is scalar locals. Mixing sums all 9
  /// channels with a documented headroom of ~0.137 full-scale per voice
  /// (4500/32768) and hard saturating clip (never wraps). Chosen from
  /// measured renders to keep dense 9-voice passages below saturation
  /// while single voices stay healthy.
  void generate(Int16List output, int frameCount) {
    if (output.length < frameCount) {
      throw ArgumentError('output length ${output.length} < frameCount '
          '$frameCount');
    }
    const amStep = 3.7 / kOpl2SampleRate;
    const vibStep = 6.1 / kOpl2SampleRate;
    for (var n = 0; n < frameCount; n++) {
      final amPhase = _amLfoPhase;
      final vibPhase = _vibLfoPhase;
      final amSin = math.sin(2 * math.pi * amPhase);
      final vibSin = math.sin(2 * math.pi * vibPhase);
      var mix = 0.0;

      for (var ch = 0; ch < kOpl2Channels; ch++) {
        if (!_keyOn[ch] && _seg[ch * 2] == _segSilent &&
            _seg[ch * 2 + 1] == _segSilent) {
          continue;
        }
        final fnum = _fnum[ch];
        final block = _block[ch];
        final fb = _feedback[ch];
        final conn = _connection[ch];
        final mi = ch * 2;
        final ci = ch * 2 + 1;

        // Feedback (operator 0 self-modulation): average of previous two
        // outputs scaled by the pi-based gain, as a phase deviation applied
        // to the lookup only (phase units).
        var fbPhase = 0.0;
        if (fb != 0) {
          final avg = 0.5 * (_prevOut[mi] + _prevPrevOut[mi]);
          fbPhase = avg * _feedbackGains[fb] * (_phaseMask / (2 * math.pi));
        }
        final modOut = _operatorOutput(mi, fnum, block, fbPhase, amSin, vibSin);

        // FM connection: carrier lookup phase is deviated by the modulator
        // output (4 cycles full-scale, [_fmDeviationScale]); deviation never
        // touches the accumulator. Additive: sum both.
        final carrier = _operatorOutput(
          ci,
          fnum,
          block,
          conn == 0 ? modOut * _fmDeviationScale : 0.0,
          amSin,
          vibSin,
        );
        mix += conn == 0 ? carrier : modOut + carrier;
      }

      final s = (mix * 4500.0).round();
      output[n] = s > 32767
          ? 32767
          : (s < -32768 ? -32768 : s);

      _amLfoPhase += amStep;
      if (_amLfoPhase >= 1.0) _amLfoPhase -= 1.0;
      _vibLfoPhase += vibStep;
      if (_vibLfoPhase >= 1.0) _vibLfoPhase -= 1.0;
      _frameIndex++;
    }
  }

  double _operatorOutput(int idx, int fnum, int block, double fmPhase,
      double amSin, double vibSin) {
    // Gated (silent) operators contribute nothing and do not advance phase.
    var seg = _seg[idx];
    if (seg == _segSilent) return 0.0;

    // Vibrato: +/- several cents on the phase increment when VIB is set.
    var inc = _phaseIncrement(idx, fnum, block);
    if (_vib[idx]) {
      final cents = _vibDepth ? 14.0 : 7.0;
      inc = (inc * math.pow(2.0, cents / 1200.0 * vibSin)).round();
    }
    // Advance the accumulator by the increment ONLY; fmPhase is a lookup
    // deviation and must never accumulate (that would turn PM into FM).
    _phase[idx] = (_phase[idx] + inc) & _phaseMask;
    final lookupPhase = (_phase[idx] + fmPhase.round()) & _phaseMask;

    // Envelope advance, then attenuation combining (log domain).
    _advanceEnvelope(idx, fnum, block);
    if (_seg[idx] == _segSilent) return 0.0;

    var att = _tl[idx] * 0.75 + _envDb[idx] + _kslDb(idx, fnum, block);
    if (_am[idx]) {
      // Datasheet AM depths (1.0 / 4.8 dB) are peak-to-peak; the sine
      // modulation amplitude is half that. Calibration capture
      // (2026-11-26) measured ~1.08 dB p-p at the shallow setting
      // vs 2.00 dB p-p with the previous ±1.0 dB interpretation.
      final depth = _amDepth ? 2.4 : 0.5;
      att += depth * amSin;
      if (att < 0.0) att = 0.0;
    }
    var ampTableIdx = (att / _ampStepDb).round();
    if (ampTableIdx < 0) ampTableIdx = 0;
    if (ampTableIdx >= _ampTableLen) ampTableIdx = _ampTableLen - 1;
    final amp = _ampTable[ampTableIdx];

    final out = _waveValue(idx, amp, lookupPhase);
    // History for feedback (operator 0 only; harmless for carriers).
    _prevPrevOut[idx] = _prevOut[idx];
    _prevOut[idx] = out;
    return out;
  }

  int _phaseIncrement(int idx, int fnum, int block) {
    // f = fnum * SR / 2^(20-block) * MULT(0.5x..15x);
    // inc = f/SR * 2^20 = fnum * MULT * 2^block (integer, deterministic).
    // MULT is used doubled (register 0 => 1 = 0.5x*2), so divide by 2.
    final doubledMult = _multTable[_multIdx[idx]];
    return (fnum * doubledMult << block) ~/ 2;
  }

  /// Key-scale attenuation lookup into the precomputed log-step table
  /// [_kslTable] (see its fit note). Never negative; indices are clamped
  /// defensively like the amp-table lookup in [_operatorOutput].
  double _kslDb(int idx, int fnum, int block) {
    var ksl = _ksl[idx];
    if (ksl < 0) ksl = 0;
    if (ksl > 3) ksl = 3;
    var b = block;
    if (b < 0) b = 0;
    if (b > 7) b = 7;
    var top = fnum >> 6;
    if (top < 0) top = 0;
    if (top > 15) top = 15;
    return _kslTable[((ksl * 8) + b) * 16 + top];
  }

  double _waveValue(int idx, double amp, int phase) {
    final wave = _wave[idx];
    final quarter = phase >> (_phaseBits - 2); // 0..3
    const half = _phaseMask >> 1;
    // Quarter-wave index into the sine table. Odd quarters traverse the
    // table in reverse so the waveform falls (1->0) instead of rising
    // again (which would make a sawtooth-shaped "sine").
    final inQuarter = phase & ((1 << (_phaseBits - 2)) - 1);
    var tableIdx = (inQuarter * _sineTableLen) >> (_phaseBits - 2);
    if (tableIdx >= _sineTableLen) tableIdx = _sineTableLen - 1;
    if (quarter.isOdd) tableIdx = _sineTableLen - 1 - tableIdx;
    final s = _sineTable[tableIdx];

    switch (wave) {
      case 0:
        return phase > half ? -s * amp : s * amp;
      case 1: // Half sine: negative half = 0.
        if (phase > half) return 0.0;
        return s * amp;
      case 2: // Abs sine.
        return s * amp;
      default: // Waveform 3: rising quarter-sine repeated twice per
        // phase cycle, silence in the second quarter of each half-cycle,
        // never negative. The quarter table is read rising (no mirror)
        // in even quarters and the output drops abruptly to zero for odd
        // quarters. Candidate-shape simulation against the ScummVM/Nuked
        // calibration capture (2026-11-26) favored this construction
        // over a symmetric arch (which phase-fold smearing had suggested).
        if (quarter.isOdd) return 0.0;
        var idx = (inQuarter * _sineTableLen) >> (_phaseBits - 2);
        if (idx >= _sineTableLen) idx = _sineTableLen - 1;
        return _sineTable[idx] * amp;
    }
  }

  void _advanceEnvelope(int idx, int fnum, int block) {
    var seg = _seg[idx];
    if (seg == _segSilent) return;
    final ksn = (block << 1) |
        ( _noteSel == 1 ? ((fnum >> 8) & 1) : ((fnum >> 9) & 1));
    final rateOffset = _ksr[idx] ? ksn : (ksn >> 2);
    var level = _envDb[idx];

    if (seg == _segAttack) {
      // Yamaha semantics: raw rate 0 freezes the segment regardless of
      // the key-scale offset (AR=0 never attacks).
      if (_ar[idx] == 0) {
        _envDb[idx] = level;
        return;
      }
      final eff = 4 * _ar[idx] + rateOffset;
      if (eff >= 60) {
        // Instant attack (measured fast attack at AR=15 high-ksn rates).
        level = 0.0;
      } else {
        // Geometric-in-dB attack: att(t) = att0 * exp(-t/tau), i.e.
        // level *= exp(-1/tau) per sample. Measured black-box on
        // calibration attack programs against a ScummVM/Nuked capture
        // (2026-11-26): AR=1 (eff=6) t(-20dB)=658 ms, t(-3dB)=1357 ms
        // (ratio 2.06); AR=4: 75/170; AR=6: 15/40. The ratio ~2 matches
        // geometric-in-dB, not the amplitude-domain approach (ratio ~11).
        // tau(eff) = 55000 * 2^(-eff/4) samples: eff=6 -> tau=19455
        // samples = 391 ms, t(-3dB)=tau*ln(96/3)=1357 ms; eff=26 ->
        // tau=608 samples, t(-3dB)=42 ms. Note: an earlier band-envelope
        // measurement that suggested the amplitude-domain shape (PQ2
        // patch 19) was confounded by two-operator/accompaniment content
        // and is superseded by these calibration anchors.
        final tau = _attackTau(eff);
        level *= math.exp(-1.0 / tau);
        if (level <= 0.01) {
          level = 0.0;
          seg = _segDecay;
          _seg[idx] = seg;
          _envDb[idx] = level;
          return;
        }
      }
      _envDb[idx] = level;
      // After reaching full level, attack becomes decay on next sample.
      if (level <= 0.0) _seg[idx] = _segDecay;
      return;
    }

    if (seg == _segDecay) {
      if (_dr[idx] == 0) {
        _envDb[idx] = level;
        return;
      }
      final eff = 4 * _dr[idx] + rateOffset;
      level += _decayRateDbPerSample(eff);
      final slDb = _sl[idx] * 3.0;
      if (level >= slDb) {
        level = slDb;
        // EG-type on (sustain): hold at SL for as long as the key is on.
        // EG-type off (percussive): DR takes the envelope to SL, then RR
        // takes over even while KON remains 1 (piano-like decay).
        _seg[idx] = _egType[idx] ? _segSustain : _segRelease;
      }
      // Percussive release continues toward the silence floor below.
      if (level >= _silenceDb) {
        level = _silenceDb;
        _seg[idx] = _segSilent;
      }
      _envDb[idx] = level;
      return;
    }

    if (seg == _segSustain) {
      // No change while held (key still on).
      return;
    }

    if (seg == _segRelease) {
      if (_rr[idx] == 0) {
        _envDb[idx] = level;
        return;
      }
      final eff = 4 * _rr[idx] + rateOffset;
      // Release uses the same rate curve as decay (no separate factor).
      level += _decayRateDbPerSample(eff);
      if (level >= _silenceDb) {
        level = _silenceDb;
        _seg[idx] = _segSilent;
      }
      _envDb[idx] = level;
    }
  }

  /// Attack time constant in samples for the geometric-in-dB attack
  /// att(t) = att0 * exp(-t/tau). Measured black-box on calibration attack
  /// programs against a ScummVM/Nuked capture (2026-11-26): AR=1 (eff=6)
  /// t(-20dB)=658 ms, t(-3dB)=1357 ms; AR=4: 75/170; AR=6: 15/40, i.e.
  /// t(-3)/t(-20) ~= 2.06, matching geometric-in-dB. tau doubles every 4
  /// eff steps downward: tau(eff) = 55000 * 2^(-eff/4) samples, so eff=6 ->
  /// tau=19455 samples (391 ms) and eff=26 -> tau=608 samples with
  /// t(-3dB)=tau*ln(96/3)=42 ms. This is a measured anchor, not a
  /// datasheet table.
  double _attackTau(int eff) {
    var e = eff;
    if (e < 0) e = 0;
    if (e > 75) e = 75;
    return 55000.0 * math.pow(2.0, -e / 4.0).toDouble();
  }

  /// Decay/release ramp in dB per sample.
  ///
  /// Black-box measurement against a Nuked OPL reference capture,
  /// 2026-11-26 (PQ2 sound 1 through a ScummVM Nuked driver): decay and
  /// release share one curve, dbPerSec(eff) = 1.24 * 2^(eff/4), anchored
  /// so dbPerSec(10) ~= 7 dB/s (measured carrier-fundamental decay for
  /// DR=2, ksn offset 2). Sanity: eff=26 ~= 112 dB/s (release fit ~72
  /// dB/s, within tolerance), eff=0 ~= 1.2 dB/s, eff=60 ~= 40,000 dB/s
  /// (near-instant). Measured anchors, not datasheet tables.
  double _decayRateDbPerSample(int eff) {
    var e = eff;
    if (e < 0) e = 0;
    if (e > 75) e = 75;
    final dbPerSec = 1.24 * math.pow(2.0, e / 4.0).toDouble();
    return dbPerSec / kOpl2SampleRate;
  }
}
