// AGI FM adapter (Stage 9): AGI tone voices -> project-authored OPL
// presets, dual-OPL2 for per-voice pan, SN76489 noise mixed in.
//
// This is a dedicated adapter, not the Sierra SCI driver. The three AGI
// tone voices are pinned to OPL channels 0/1/2 and play project-authored
// [SciAdlibInstrument]s from the [kAgiFmPresets] registry. There is no
// dynamic voice allocation and no SCI patch-number mapping.
//
// Pan model (deliberate difference from the SCI driver): two Opl2Chips
// run in lockstep. Every register is written identically to both chips
// EXCEPT the carrier total level (0x40, operator 1), which carries the
// per-side pan. The modulator TL is written identically to both sides,
// so panning changes only the carrier level and never shifts timbre.
// The SCI driver's dual path instead scales velocities per side, which
// for FM patches also scales modulation depth; this adapter keeps the
// modulator constant per note on both sides.
//
// Levels. AGI attenuation runs 0..15 in 2 dB steps. An OPL total-level
// step is 0.75 dB. The static per-segment carrier offset is therefore
//   attOffset = round(attenuation * 8 / 3)   [since 2 / 0.75 = 8 / 3]
// and the modulator gets half that offset, so quieter notes dull
// slightly (less modulation) while the carrier does the level work.
// Per-voice gain adds a further carrier-only offset
//   gainOffset = round(-20 * log10(gain) / 0.75)
// (gain == 0 silences the voice: no key-on is ever emitted).
// Velocity for panning is v = 63 - effectiveCarrierTL, split per side
// by constant-power pan:
//   vL = round(v * cos(pan * pi / 2)), vR = round(v * sin(pan * pi / 2))
//   sideCarrierTL = clamp(63 - vSide, 0, 63)
// (v <= 0 means the segment is silent on both sides; key state is
// still tracked so contiguous-legato rules keep working).
//
// Rotation / timing rules (dispatch at native frames
// round(tick * 49716 / 60)):
//   * voice off -> on: program pitch + levels, key-on.
//   * contiguous next segment (start == prev end), same frequencyCount:
//     levels-only update (no key retrigger, no envelope restart).
//   * contiguous, different pitch: pitch + levels rewrite while the
//     key stays on (legato).
//   * gap or silent/invalid segment: key-off at the previous sounding
//     segment's end frame (the moment the tone actually stops — the
//     same moment the Tandy renderer goes quiet).
// Track end keys off every still-sounding voice at the
// sound.length frame, then a 30-tick tail lets envelopes release.
//
// Rendering mirrors the SCI AdLib streaming source: 1024-frame native
// blocks, measured sinc resampling to the output rate with retained
// half-width history, true bypass at the native rate, and a noise
// mix rendered by a lockstep [AgiPcmSource] (SN76489) when
// [SynthesizerConfig.fmNoiseSource] is tandy.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_agigame/audio/agi_pcm_source.dart';
import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/pcm_resampler.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// One AGI FM preset: lead/harmony/bass instruments for tone voices
/// 1/2/3 plus an output trim. The instruments are project-authored
/// (see [SciAdlibInstrument.fromFields]); no game bank bytes are used.
final class AgiFmPreset {
  /// Stable identifier (matches [SynthesizerConfig.fmPresetId]).
  final String id;

  /// Display name.
  final String displayName;

  /// Instrument for tone voice 1.
  final SciAdlibInstrument lead;

  /// Instrument for tone voice 2.
  final SciAdlibInstrument harmony;

  /// Instrument for tone voice 3.
  final SciAdlibInstrument bass;

  /// Output trim multiplied into the final mix (default 1.0).
  final double outputTrim;

  const AgiFmPreset({
    required this.id,
    required this.displayName,
    required this.lead,
    required this.harmony,
    required this.bass,
    this.outputTrim = 1.0,
  });
}

/// Builds one project-authored instrument. Operator 0 is the modulator
/// and operator 1 is the carrier in the decoded 28-byte model (the
/// same convention the SCI driver programs into the chip). Envelope
/// type 1 marks a sustained voice: the note holds until key-off, which
/// is what AGI tones need. All five presets use it for every voice.
///
/// Sustain levels stay low (loud) so held notes keep most of their
/// peak amplitude: the OPL chip's fixed output scale (~4500 int16 per
/// full-scale voice) runs about 8 dB below the Tandy renderer's
/// full-scale square, and the preset trims compensate most of that.
SciAdlibInstrument _fmInstrument({
  required int modTL,
  required int modMult,
  int modAttack = 9,
  int modDecay = 5,
  int modSustain = 1,
  int modRelease = 10,
  int feedback = 0,
  int algorithm = 0,
  required int carrierTL,
  required int carrierMult,
  int carrierAttack = 9,
  int carrierDecay = 5,
  int carrierSustain = 0,
  int carrierRelease = 10,
}) {
  return SciAdlibInstrument.fromFields(
    operator0: SciAdlibOperator(
      kbScaleLevel: 0,
      frequencyMult: modMult,
      attackRate: modAttack,
      sustainLevel: modSustain,
      envelopeType: 1,
      decayRate: modDecay,
      releaseRate: modRelease,
      totalLevel: modTL,
      amplitudeMod: 0,
      vibrato: 0,
      kbScaleRate: 0,
      waveForm: 0,
    ),
    operator1: SciAdlibOperator(
      kbScaleLevel: 0,
      frequencyMult: carrierMult,
      attackRate: carrierAttack,
      sustainLevel: carrierSustain,
      envelopeType: 1,
      decayRate: carrierDecay,
      releaseRate: carrierRelease,
      totalLevel: carrierTL,
      amplitudeMod: 0,
      vibrato: 0,
      kbScaleRate: 0,
      waveForm: 0,
    ),
    modulator: SciAdlibModulator(feedback: feedback, algorithm: algorithm),
  );
}

// Levels note: carrier TLs sit hot (2..6) and preset trims at 4x
// because the chip's fixed output scale (~4500 int16 full-scale per
// voice) plus the spec's linear velocity pan together run ~13 dB
// below the Tandy renderer's full-scale square. Hot TLs keep the
// per-note attenuation offset working (quiet notes still get quieter)
// while the trim stages 3-voice mixes back into the Tandy ballpark;
// worst-case theoretical peak (3 voiced at TL 0) stays just over
// int16 full scale, and realistic mixes peak well below it.
SciAdlibInstrument _neutralKeysLead() => _fmInstrument(
      modTL: 12,
      modMult: 1,
      feedback: 2,
      carrierTL: 3,
      carrierMult: 1,
      carrierDecay: 7,
    );
SciAdlibInstrument _neutralKeysHarmony() => _fmInstrument(
      modTL: 14,
      modMult: 1,
      carrierTL: 5,
      carrierMult: 1,
      carrierDecay: 7,
    );
SciAdlibInstrument _neutralKeysBass() => _fmInstrument(
      modTL: 8,
      modMult: 1,
      carrierTL: 3,
      carrierMult: 1,
      carrierAttack: 7,
    );

SciAdlibInstrument _brightBrassLead() => _fmInstrument(
      modTL: 6,
      modMult: 2,
      modAttack: 6,
      feedback: 3,
      carrierTL: 4,
      carrierMult: 1,
      carrierAttack: 6,
      carrierDecay: 6,
    );
SciAdlibInstrument _brightBrassHarmony() => _fmInstrument(
      modTL: 8,
      modMult: 2,
      modAttack: 7,
      feedback: 2,
      carrierTL: 6,
      carrierMult: 1,
      carrierAttack: 7,
      carrierDecay: 6,
    );
SciAdlibInstrument _brightBrassBass() => _fmInstrument(
      modTL: 10,
      modMult: 1,
      modAttack: 5,
      carrierTL: 4,
      carrierMult: 1,
      carrierAttack: 5,
    );

// Soft organ: additive connection (algorithm 1) — operator0 stops
// modulating and sounds as a 2x second carrier under the fundamental,
// the classic 2-drawbar organ blend. (Mid-depth FM here would land
// on Bessel zeros and suppress the fundamental; additive is both
// simpler and organ-correct.) The second carrier sits ~11 dB down
// and is not per-side panned, which reads as a centered harmonic
// halo under the panned fundamental.
SciAdlibInstrument _softOrganLead() => _fmInstrument(
      algorithm: 1,
      modTL: 18,
      modMult: 2,
      modAttack: 5,
      carrierTL: 4,
      carrierMult: 1,
      carrierAttack: 5,
      carrierDecay: 3,
    );
SciAdlibInstrument _softOrganHarmony() => _fmInstrument(
      algorithm: 1,
      modTL: 21,
      modMult: 2,
      modAttack: 5,
      carrierTL: 7,
      carrierMult: 1,
      carrierAttack: 5,
      carrierDecay: 3,
    );
SciAdlibInstrument _softOrganBass() => _fmInstrument(
      algorithm: 1,
      modTL: 16,
      modMult: 2,
      modAttack: 4,
      carrierTL: 3,
      carrierMult: 1,
      carrierAttack: 4,
      carrierDecay: 3,
    );

SciAdlibInstrument _bassLeadSplitLead() => _fmInstrument(
      modTL: 5,
      modMult: 2,
      feedback: 2,
      carrierTL: 4,
      carrierMult: 1,
    );
SciAdlibInstrument _bassLeadSplitHarmony() => _fmInstrument(
      modTL: 10,
      modMult: 1,
      carrierTL: 6,
      carrierMult: 1,
    );
// Deep FM bass: sub-octave modulator (mult 0) puts sideband energy
// at f/2 around the untouched carrier pitch (mult 1), hot carrier
// level so low notes carry. The carrier multiplier stays 1 in every
// preset: AGI pitches are never transposed, only re-timbre'd.
SciAdlibInstrument _bassLeadSplitBass() => _fmInstrument(
      modTL: 6,
      modMult: 0,
      carrierTL: 2,
      carrierMult: 1,
      carrierAttack: 8,
    );

// Near square: modulator at 2x puts FM sidebands on the odd harmonics
// (f, 3f, 5f...), approximating a square wave for comparison against
// the Tandy square. Strong, sustained modulation keeps the 3rd up.
SciAdlibInstrument _nearSquareLead() => _fmInstrument(
      modTL: 5,
      modMult: 2,
      feedback: 2,
      carrierTL: 3,
      carrierMult: 1,
      carrierDecay: 3,
    );
SciAdlibInstrument _nearSquareHarmony() => _fmInstrument(
      modTL: 7,
      modMult: 2,
      feedback: 2,
      carrierTL: 5,
      carrierMult: 1,
      carrierDecay: 3,
    );
SciAdlibInstrument _nearSquareBass() => _fmInstrument(
      modTL: 9,
      modMult: 2,
      feedback: 2,
      carrierTL: 4,
      carrierMult: 1,
      carrierDecay: 3,
    );

/// Ordered registry of project-authored AGI FM presets. The first
/// entry ([kAgiFmPresets.first]) is the fallback for unknown ids.
final List<AgiFmPreset> kAgiFmPresets = List.unmodifiable([
  AgiFmPreset(
    id: 'neutralKeys',
    displayName: 'Neutral Keys',
    lead: _neutralKeysLead(),
    harmony: _neutralKeysHarmony(),
    bass: _neutralKeysBass(),
    outputTrim: 4.5,
  ),
  AgiFmPreset(
    id: 'brightBrass',
    displayName: 'Bright Brass',
    lead: _brightBrassLead(),
    harmony: _brightBrassHarmony(),
    bass: _brightBrassBass(),
    outputTrim: 4.5,
  ),
  AgiFmPreset(
    id: 'softOrgan',
    displayName: 'Soft Organ',
    lead: _softOrganLead(),
    harmony: _softOrganHarmony(),
    bass: _softOrganBass(),
    outputTrim: 4.5,
  ),
  AgiFmPreset(
    id: 'bassLeadSplit',
    displayName: 'Bass + Lead Split',
    lead: _bassLeadSplitLead(),
    harmony: _bassLeadSplitHarmony(),
    bass: _bassLeadSplitBass(),
    outputTrim: 4.5,
  ),
  AgiFmPreset(
    id: 'nearSquare',
    displayName: 'Near Square',
    lead: _nearSquareLead(),
    harmony: _nearSquareHarmony(),
    bass: _nearSquareBass(),
    outputTrim: 4.5,
  ),
]);

/// Looks up a preset by id, falling back to the first preset.
AgiFmPreset agiFmPresetForId(String id) {
  for (final preset in kAgiFmPresets) {
    if (preset.id == id) return preset;
  }
  return kAgiFmPresets.first;
}

/// Factory used by the player and WAV export: FM mode builds an
/// [AgiFmPcmSource], every other mode keeps the existing renderer.
PcmSource createAgiPcmSource(AgiSound sound, SynthesizerConfig config) {
  if (config.mode == PcmPlaybackMode.fmPresets) {
    return AgiFmPcmSource(sound, config: config);
  }
  return AgiPcmSource(sound, config: config);
}

// --- Translation internals. ---

const int _kNativeBlockFrames = 1024;
const int _kTailTicks = 30;

/// OPL register offsets for channels 0/1/2 (datasheet channel map).
const List<int> _regOffsets = [0, 1, 2];

enum _DispatchKind { keyOn, levelsOnly, legato, keyOff }

/// One precomputed register action at a native frame.
final class _Dispatch {
  final int frame;
  final int voice;
  final _DispatchKind kind;
  final int fnum;
  final int block;

  /// Carrier TL per side (left/right chips).
  final int carrierTLL;
  final int carrierTLR;

  /// Modulator TL (identical on both chips).
  final int modulatorTL;

  const _Dispatch({
    required this.frame,
    required this.voice,
    required this.kind,
    this.fnum = 0,
    this.block = 0,
    this.carrierTLL = 63,
    this.carrierTLR = 63,
    this.modulatorTL = 63,
  });
}

/// Computes OPL block/fnum for [freqHz] so fnum lands in 0..1023 with
/// the highest usable resolution (smallest block that fits). From the
/// datasheet relation freq = fnum * 49716 / 2^(20-block), i.e.
/// fnum = round(freq * 2^(20-block) / 49716). Written here, not copied
/// from the SCI driver.
(int, int) _pitchForFreq(double freqHz) {
  var block = 0;
  var fnum = (freqHz * (1 << 20) / kOpl2SampleRate).round();
  while (fnum > 1023 && block < 7) {
    block++;
    fnum >>= 1;
  }
  if (fnum < 1) fnum = 1;
  if (fnum > 1023) fnum = 1023;
  return (fnum, block);
}

/// Adapter [PcmSource]: AGI sound -> preset OPL instruments -> dual
/// OPL2 -> resampler -> pull-based stereo PCM, with the SN76489 noise
/// mixed in from a lockstep [AgiPcmSource] when configured.
class AgiFmPcmSource extends PcmSource {
  final AgiSound sound;
  final SynthesizerConfig config;

  /// Resolved preset (unknown ids fall back to the first preset).
  late final AgiFmPreset preset;

  late final List<SciAdlibInstrument> _instruments;
  late final List<int> _gainOffsets;
  late final List<double> _pans;
  late final List<_Dispatch> _dispatches;
  late final int _totalNativeFrames;
  late final int _totalFrames;

  late Opl2Chip _chip;
  late Opl2Chip _chipRight;

  /// Lockstep noise source; null when the noise channel is absent or
  /// [AgiFmNoiseSource.off] is configured.
  late final AgiPcmSource? _noiseSource;
  late final double _fmGain;
  late final double _noiseGain;

  int _position = 0;
  int _dispatchIdx = 0;
  int _generated = 0;
  int _bufStart = 0;
  int _bufLen = 0;
  int _prevLast = 0;
  bool _prevValid = false;
  int _prevLastRight = 0;
  bool _prevValidRight = false;

  final Int16List _nativeBuf = Int16List(_kNativeBlockFrames);
  final Int16List _nativeBufRight = Int16List(_kNativeBlockFrames);
  Int16List _discard = Int16List(0);
  Int16List _noiseScratch = Int16List(0);

  bool _writeLogEnabled = false;

  late final PcmResampler? _resampler;
  late final int _halfWidth;
  late final Int16List _hist;
  late final Int16List _histRight;

  double get _step => kOpl2SampleRate / config.sampleRate.toDouble();

  AgiFmPcmSource(this.sound, {required this.config}) {
    preset = agiFmPresetForId(config.fmPresetId);
    _instruments = [preset.lead, preset.harmony, preset.bass];
    _fmGain = config.fmGain.clamp(0.0, 2.0);
    _noiseGain = config.fmNoiseGain.clamp(0.0, 2.0);

    final gains = [config.voice1Gain, config.voice2Gain, config.voice3Gain];
    _gainOffsets = <int>[
      for (final g in gains) _gainOffsetFor(g.clamp(0.0, 2.0)),
    ];
    _pans = <double>[
      config.voice1Pan.clamp(0.0, 1.0),
      config.voice2Pan.clamp(0.0, 1.0),
      config.voice3Pan.clamp(0.0, 1.0),
    ];

    // Lockstep noise source (SN76489 via the existing renderer) over a
    // derived sound whose tone voices are silent rests, so it stays
    // bit-identical to the Tandy path for the same noise channel.
    if (config.fmNoiseSource == AgiFmNoiseSource.tandy && sound.noise != null) {
      final silentVoices = <ToneChannel>[
        for (final _ in sound.voices)
          ToneChannel(notes: const [
            AgiNote(startTime: 0, duration: 1, frequencyCount: 0, attenuation: 15),
          ]),
      ];
      final derived = AgiSound(voices: silentVoices, noise: sound.noise);
      _noiseSource = AgiPcmSource(
        derived,
        config: SynthesizerConfig(
          sampleRate: config.sampleRate,
          mode: PcmPlaybackMode.tandy3VoiceNoise,
          masterVolume: 1.0,
          enableReverb: false,
          noisePan: config.noisePan,
        ),
      );
    } else {
      _noiseSource = null;
    }

    final empty = sound.isEmpty || sound.length <= 0;
    _dispatches = empty ? const [] : _translate();
    _totalNativeFrames = empty ? 0 : _frameForTick(sound.length + _kTailTicks);
    var fmTotal = empty ? 0 : _frameForTickAtRate(sound.length + _kTailTicks);
    final noiseTotal = _noiseSource?.totalFrames ?? 0;
    if (noiseTotal > fmTotal) fmTotal = noiseTotal;
    _totalFrames = fmTotal;

    if (config.sampleRate == kOpl2SampleRate) {
      _resampler = null;
      _halfWidth = 0;
      _hist = Int16List(0);
      _histRight = Int16List(0);
    } else {
      final r = PcmResampler(kOpl2SampleRate, config.sampleRate);
      _resampler = r;
      _halfWidth = r.halfWidth;
      _hist = Int16List(_halfWidth);
      _histRight = Int16List(_halfWidth);
    }
    reset();
  }

  static int _gainOffsetFor(double gain) {
    if (gain <= 0.0) return 0;
    return (-20.0 * math.log(gain) / math.ln2 / 0.75).round();
  }

  int _frameForTick(int tick) => (tick * kOpl2SampleRate / 60).round();
  int _frameForTickAtRate(int tick) => (tick * config.sampleRate / 60).round();

  // Per-segment carrier/modulator levels from attenuation + gain + pan.
  // Returns (carrierTLL, carrierTLR, modulatorTL).
  (int, int, int) _levelsFor(int voice, int attenuation) {
    final instrument = _instruments[voice];
    final attOffset = (attenuation.clamp(0, 15) * 8 / 3).round();
    final gainOffset = _gainOffsets[voice];
    var carrierTL = instrument.operator1.totalLevel + attOffset + gainOffset;
    var modulatorTL = instrument.operator0.totalLevel + (attOffset / 2).round();
    carrierTL = carrierTL.clamp(0, 63);
    modulatorTL = modulatorTL.clamp(0, 63);

    final velocity = 63 - carrierTL;
    final pan = _pans[voice];
    final cos = math.cos(pan * math.pi / 2);
    final sin = math.sin(pan * math.pi / 2);
    final vL = (velocity * cos).round();
    final vR = (velocity * sin).round();
    final sideL = (63 - vL).clamp(0, 63);
    final sideR = (63 - vR).clamp(0, 63);
    // v <= 0 => both sides silent (TL 63); the clamp above already
    // yields 63 for vL/vR <= 0, spelled out here for clarity.
    return (sideL, sideR, modulatorTL);
  }

  /// Translates every voice into ordered dispatch actions. Dispatches
  /// are sorted by native frame; same-frame order is voice order.
  List<_Dispatch> _translate() {
    final nyquist = config.sampleRate * 0.49;
    final out = <_Dispatch>[];
    final gains = [config.voice1Gain, config.voice2Gain, config.voice3Gain];

    for (var voice = 0; voice < 3; voice++) {
      if (voice >= sound.voices.length) break;
      // Gain 0 silences the voice: no key-on is ever emitted.
      final silenced = gains[voice].clamp(0.0, 2.0) <= 0.0;
      var keyed = false;
      var prevEndTick = 0;
      var prevFreq = 0;
      var lastFnum = 0;
      var lastBlock = 0;

      void keyOffAt(int tick) {
        if (!keyed) return;
        out.add(_Dispatch(
          frame: _frameForTick(tick),
          voice: voice,
          kind: _DispatchKind.keyOff,
          fnum: lastFnum,
          block: lastBlock,
        ));
        keyed = false;
      }

      for (final note in sound.voices[voice].notes) {
        final freq = note.frequencyInHz;
        final audible =
            !note.isSilent && freq > 0.0 && freq <= nyquist && !silenced;
        if (!audible) {
          // Gap/silent/invalid segment: the tone stops at the previous
          // sounding segment's end (the Tandy renderer's quit frame).
          keyOffAt(prevEndTick);
          prevFreq = 0;
          continue;
        }
        final (fnum, block) = _pitchForFreq(freq);
        final (tlL, tlR, modTL) = _levelsFor(voice, note.attenuation);
        if (!keyed) {
          out.add(_Dispatch(
            frame: _frameForTick(note.startTime),
            voice: voice,
            kind: _DispatchKind.keyOn,
            fnum: fnum,
            block: block,
            carrierTLL: tlL,
            carrierTLR: tlR,
            modulatorTL: modTL,
          ));
          keyed = true;
        } else if (note.startTime == prevEndTick) {
          // Contiguous: same pitch = levels-only, new pitch = legato.
          out.add(_Dispatch(
            frame: _frameForTick(note.startTime),
            voice: voice,
            kind: note.frequencyCount == prevFreq
                ? _DispatchKind.levelsOnly
                : _DispatchKind.legato,
            fnum: fnum,
            block: block,
            carrierTLL: tlL,
            carrierTLR: tlR,
            modulatorTL: modTL,
          ));
        } else {
          // Gap in the note list (non-contiguous sounding note without
          // an intervening silent record): release the old note at its
          // end, then strike the new one.
          keyOffAt(prevEndTick);
          out.add(_Dispatch(
            frame: _frameForTick(note.startTime),
            voice: voice,
            kind: _DispatchKind.keyOn,
            fnum: fnum,
            block: block,
            carrierTLL: tlL,
            carrierTLR: tlR,
            modulatorTL: modTL,
          ));
          keyed = true;
        }
        lastFnum = fnum;
        lastBlock = block;
        prevFreq = note.frequencyCount;
        prevEndTick = note.endTime;
      }
      keyOffAt(sound.length);
    }

    // Stable sort by frame (voice order preserved within a frame).
    final indexed = <(int, _Dispatch)>[
      for (var i = 0; i < out.length; i++) (i, out[i]),
    ]..sort((a, b) {
        final byFrame = a.$2.frame.compareTo(b.$2.frame);
        if (byFrame != 0) return byFrame;
        return a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  /// Programs the preset operators once, mirroring the SCI driver's
  /// register contract but only for the fixed channels 0/1/2.
  void _programVoice(Opl2Chip chip, int voice, SciAdlibInstrument ins) {
    final base = _regOffsets[voice];
    void setOp(int offset, SciAdlibOperator op) {
      chip.writeRegister(
        0x40 + offset,
        (op.kbScaleLevel << 6) | op.totalLevel,
      );
      chip.writeRegister(0x60 + offset, (op.attackRate << 4) | op.decayRate);
      chip.writeRegister(0x80 + offset, (op.sustainLevel << 4) | op.releaseRate);
      chip.writeRegister(
        0x20 + offset,
        (op.amplitudeMod != 0 ? 0x80 : 0) |
            (op.vibrato != 0 ? 0x40 : 0) |
            (op.envelopeType != 0 ? 0x20 : 0) |
            (op.kbScaleRate != 0 ? 0x10 : 0) |
            op.frequencyMult,
      );
      chip.writeRegister(0xE0 + offset, op.waveForm);
    }

    setOp(base, ins.operator0);
    setOp(base + 3, ins.operator1);
    chip.writeRegister(
      0xC0 + voice,
      (ins.modulator.feedback << 1) | ins.modulator.algorithm,
    );
  }

  /// Applies one dispatch to both chips. Carrier TL differs per side
  /// (pan); modulator TL and every pitch/key write are identical.
  void _apply(_Dispatch d) {
    final voice = d.voice;
    final base = _regOffsets[voice];
    final carrierReg = 0x40 + base + 3;
    final modReg = 0x40 + base;
    final carrierKsl = _instruments[voice].operator1.kbScaleLevel << 6;
    final modKsl = _instruments[voice].operator0.kbScaleLevel << 6;

    void both(void Function(Opl2Chip chip) fn) {
      fn(_chip);
      fn(_chipRight);
    }

    switch (d.kind) {
      case _DispatchKind.keyOn:
      case _DispatchKind.legato:
        both((chip) => chip.writeRegister(0xA0 + voice, d.fnum & 0xff));
        both((chip) => chip.writeRegister(
              0xB0 + voice,
              0x20 | (d.block << 2) | ((d.fnum >> 8) & 0x3),
            ));
        _chip.writeRegister(carrierReg, carrierKsl | d.carrierTLL);
        _chipRight.writeRegister(carrierReg, carrierKsl | d.carrierTLR);
        both((chip) => chip.writeRegister(modReg, modKsl | d.modulatorTL));
      case _DispatchKind.levelsOnly:
        _chip.writeRegister(carrierReg, carrierKsl | d.carrierTLL);
        _chipRight.writeRegister(carrierReg, carrierKsl | d.carrierTLR);
        both((chip) => chip.writeRegister(modReg, modKsl | d.modulatorTL));
      case _DispatchKind.keyOff:
        both((chip) => chip.writeRegister(
              0xB0 + voice,
              (d.block << 2) | ((d.fnum >> 8) & 0x3),
            ));
    }
  }

  @override
  int get sampleRate => config.sampleRate;

  @override
  int get channels => 2;

  @override
  int? get totalFrames => _totalFrames;

  @override
  int get positionFrames => _position;

  @override
  bool get isFinished => _position >= _totalFrames;

  @override
  void reset() {
    _position = 0;
    _dispatchIdx = 0;
    _generated = 0;
    _bufStart = 0;
    _bufLen = 0;
    _prevValid = false;
    _prevLast = 0;
    _prevValidRight = false;
    _prevLastRight = 0;
    for (var i = 0; i < _hist.length; i++) {
      _hist[i] = 0;
      _histRight[i] = 0;
    }
    _chip = Opl2Chip();
    _chipRight = Opl2Chip();
    _chip.writeLogEnabled = _writeLogEnabled;
    _chipRight.writeLogEnabled = _writeLogEnabled;
    for (final chip in [_chip, _chipRight]) {
      chip.writeRegister(0xBD, 0);
      chip.writeRegister(0x08, 0);
      chip.writeRegister(0x01, 0x20);
      for (var voice = 0; voice < 3; voice++) {
        _programVoice(chip, voice, _instruments[voice]);
      }
    }
    _noiseSource?.reset();
  }

  @override
  void seekToFrame(int frame) {
    final target = frame.clamp(0, _totalFrames);
    reset();
    while (_position < target) {
      var chunk = target - _position;
      if (chunk > 4096) chunk = 4096;
      if (_discard.length < chunk * 2) {
        _discard = Int16List(chunk * 2);
      }
      renderInto(_discard, chunk);
    }
  }

  @override
  int renderInto(Int16List interleaved, int frameCount) {
    if (interleaved.length < frameCount * 2) {
      throw ArgumentError(
        'interleaved length ${interleaved.length} is less than '
        'frameCount * channels (${frameCount * 2})',
      );
    }
    if (frameCount <= 0) return 0;
    var n = frameCount;
    final remaining = _totalFrames - _position;
    if (n > remaining) n = remaining;
    if (n <= 0) return 0;

    // Lockstep noise block (positions must stay in lockstep with the
    // FM stream, including short final blocks; a short noise return
    // means silence for the rest of this block).
    final noise = _noiseSource;
    var noiseLen = 0;
    if (noise != null) {
      if (_noiseScratch.length < n * 2) {
        _noiseScratch = Int16List(n * 2);
      }
      noiseLen = noise.renderInto(_noiseScratch, n);
    }

    final step = _step;
    final identity = step == 1.0;
    int readLeft(int idx) => _readResampled(idx);
    int readRight(int idx) => _readResampled(idx, right: true);
    for (var i = 0; i < n; i++) {
      final int fmL;
      final int fmR;
      if (identity) {
        final idx = _position + i;
        _ensureAvail(idx);
        fmL = _totalNativeFrames == 0 ? 0 : _readNative(idx);
        fmR = _totalNativeFrames == 0 ? 0 : _readNative(idx, right: true);
      } else {
        final p = (_position + i) * step;
        final i0 = p.floor();
        final r = _resampler!;
        if (_totalNativeFrames == 0) {
          fmL = 0;
          fmR = 0;
        } else {
          _ensureAvail(i0 + _halfWidth < _totalNativeFrames
              ? i0 + _halfWidth
              : _totalNativeFrames - 1);
          fmL = r.evaluateInt16(readLeft, p);
          fmR = r.evaluateInt16(readRight, p);
        }
      }
      final nL = noise != null && i < noiseLen ? _noiseScratch[i * 2] : 0;
      final nR = noise != null && i < noiseLen ? _noiseScratch[i * 2 + 1] : 0;
      interleaved[i * 2] = _mixSample(fmL, nL);
      interleaved[i * 2 + 1] = _mixSample(fmR, nR);
    }
    _position += n;
    return n;
  }

  int _mixSample(int fm, int noise) {
    // The preset trim compensates the OPL chip's output scale only;
    // Tandy noise already renders at Tandy level and is not trimmed
    // (trimming it would hard-clip loud noise for no benefit).
    final value = (fm * _fmGain * preset.outputTrim + noise * _noiseGain) *
        config.masterVolume;
    return value.round().clamp(-32768, 32767);
  }

  // --- native generation (mirrors the SCI AdLib source) ---

  int _readNative(int idx, {bool right = false}) {
    if (right) {
      if (idx < _bufStart) return _prevValidRight ? _prevLastRight : 0;
      return _nativeBufRight[idx - _bufStart];
    }
    if (idx < _bufStart) return _prevValid ? _prevLast : 0;
    return _nativeBuf[idx - _bufStart];
  }

  /// Random-access native read for the sinc evaluator: 0 outside
  /// [0, _totalNativeFrames). In-range reads hit the current block or
  /// [_bufStart-_halfWidth, _bufStart) history; callers must
  /// [_ensureAvail] to i0+halfWidth first (same proof as the SCI
  /// source). Reads past the generated frontier are 0.
  int _readResampled(int idx, {bool right = false}) {
    if (idx < 0 || idx >= _totalNativeFrames) return 0;
    if (idx >= _generated) return 0;
    if (idx >= _bufStart) {
      return right
          ? _nativeBufRight[idx - _bufStart]
          : _nativeBuf[idx - _bufStart];
    }
    final h = right ? _histRight : _hist;
    if (h.isEmpty) return 0;
    final hi = idx - (_bufStart - _halfWidth);
    if (hi < 0 || hi >= _halfWidth) return 0;
    return h[hi];
  }

  void _ensureAvail(int idx) {
    if (_totalNativeFrames == 0) return;
    if (idx >= _generated) {
      while (_generated <= idx && _generated < _totalNativeFrames) {
        _generateNextBlock();
        if (_bufLen == 0) break;
      }
    }
  }

  void _generateNextBlock() {
    if (_generated >= _totalNativeFrames) return;
    if (_bufLen > 0) {
      _prevLast = _nativeBuf[_bufLen - 1];
      _prevValid = true;
      _prevLastRight = _nativeBufRight[_bufLen - 1];
      _prevValidRight = true;
      if (_halfWidth > 0) {
        if (_bufLen >= _halfWidth) {
          _hist.setRange(0, _halfWidth, _nativeBuf, _bufLen - _halfWidth);
          _histRight.setRange(
            0,
            _halfWidth,
            _nativeBufRight,
            _bufLen - _halfWidth,
          );
        } else {
          final keep = _halfWidth - _bufLen;
          _hist.setRange(0, keep, _hist, _bufLen);
          _hist.setRange(keep, _halfWidth, _nativeBuf, 0);
          _histRight.setRange(0, keep, _histRight, _bufLen);
          _histRight.setRange(keep, _halfWidth, _nativeBufRight, 0);
        }
      }
    }
    _bufStart = _generated;
    _bufLen = 0;
    final blockTarget =
        (_generated + _kNativeBlockFrames).clamp(0, _totalNativeFrames);
    while (_generated < blockTarget) {
      final nextDispatch = _dispatchIdx < _dispatches.length
          ? _dispatches[_dispatchIdx].frame
          : _totalNativeFrames;
      if (nextDispatch <= _generated) {
        _apply(_dispatches[_dispatchIdx]);
        _dispatchIdx++;
        continue;
      }
      final upto = nextDispatch < blockTarget ? nextDispatch : blockTarget;
      final n = upto - _generated;
      // n > 0 because nextDispatch > _generated and upto > _generated.
      final offset = _generated - _bufStart;
      _chip.generate(Int16List.sublistView(_nativeBuf, offset, offset + n), n);
      _chipRight.generate(
        Int16List.sublistView(_nativeBufRight, offset, offset + n),
        n,
      );
      _generated += n;
      _bufLen = _generated - _bufStart;
    }
  }

  // --- debug surface (tests + future inspector) ---

  /// Left-chip snapshot.
  OplDebugSnapshot debugSnapshot() => _chip.snapshot();

  /// Left + right snapshots.
  List<OplDebugSnapshot> debugSnapshots() => <OplDebugSnapshot>[
        _chip.snapshot(),
        _chipRight.snapshot(),
      ];

  /// Whether write-log capture is on (both chips).
  bool get writeLogEnabled => _writeLogEnabled;

  /// Enables/disables write-log capture on both chips; survives reset.
  set writeLogEnabled(bool value) {
    _writeLogEnabled = value;
    _chip.writeLogEnabled = value;
    _chipRight.writeLogEnabled = value;
  }

  /// Left-chip write records (primary surface for key-edge tests).
  List<OplWriteRecord> get leftWriteLogs => _chip.writeLog;

  /// Right-chip write records.
  List<OplWriteRecord> get rightWriteLogs => _chipRight.writeLog;

  /// Captured write records, left chip then right chip.
  List<OplWriteRecord> get writeLogs => <OplWriteRecord>[
        ..._chip.writeLog,
        ..._chipRight.writeLog,
      ];

  /// Drains the write log on both chips.
  void clearWriteLogs() {
    _chip.clearWriteLog();
    _chipRight.clearWriteLog();
  }

  /// Exposes the lockstep noise source for tests (null when off/absent).
  AgiPcmSource? get debugNoiseSource => _noiseSource;
}
