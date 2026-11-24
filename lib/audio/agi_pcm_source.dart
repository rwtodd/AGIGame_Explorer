import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// Stateful pull-based [PcmSource] that renders an [AgiSound] exactly as
/// the legacy one-shot [PcmSynthesizer.renderPcm] did, sample for sample.
///
/// Note boundaries are derived from absolute sound ticks via
/// `((tick / 60) * sampleRate).round()`, so output does not depend on
/// how callers split their [renderInto] requests. Per-voice phase,
/// envelope position, SN76489 LFSR state, fractional noise shift clock,
/// and Freeverb filter state all persist across blocks; [reset]
/// restores every piece of that state.
class AgiPcmSource extends PcmSource {
  final SynthesizerConfig config;

  /// TI SN76489 / PCjr attenuation lookup table in linear amplitude (2dB steps).
  static final List<double> _sn76489AttenTable = List<double>.generate(16, (i) {
    if (i >= 15) return 0.0;
    return pow(10.0, -2.0 * i / 20.0).toDouble();
  });

  final List<_ToneVoice> _toneVoices = [];
  final List<_NoiseSegment> _noiseSegments = [];
  final bool _hasNoise;

  final int _totalFrames;
  int _position = 0;

  // SN76489 noise state: the 15-bit LFSR persists across the whole
  // sound (only the per-segment fractional shift counter resets).
  int _shiftRegister = 0x4000;

  // Freeverb state (created fresh by reset()).
  List<_CombFilter> _combsL = const [];
  List<_CombFilter> _combsR = const [];
  List<_AllPassFilter> _allpassesL = const [];
  List<_AllPassFilter> _allpassesR = const [];
  final bool _reverbEnabled;

  // Reused float mix buffers for the current renderInto block.
  Float64List _mixL = Float64List(0);
  Float64List _mixR = Float64List(0);

  // Scratch buffer for seekToFrame render-and-discard.
  Int16List _discard = Int16List(0);

  // Envelope constants, identical to the legacy renderer's values.
  late final int _attackSamples;
  late final int _releaseSamples;
  late final int _clickSamples;

  AgiPcmSource(AgiSound sound, {SynthesizerConfig config = const SynthesizerConfig()})
      : config = config,
        _totalFrames = _computeTotalFrames(sound, config),
        _reverbEnabled = config.enableReverb ||
            (config.mode == PcmPlaybackMode.enhanced && config.reverbMix > 0.0),
        _hasNoise = sound.noise != null {
    final sampleRate = config.sampleRate.toDouble();
    _attackSamples = (0.004 * sampleRate).round();
    _releaseSamples = (0.004 * sampleRate).round();
    _clickSamples = (0.001 * sampleRate).round();

    final mode = config.mode;
    final useEnvelope = mode == PcmPlaybackMode.enhanced;
    final waveform = mode == PcmPlaybackMode.enhanced ? config.waveform : WaveformType.square;

    int voiceCount = 0;
    if (mode == PcmPlaybackMode.ibmPcSingleChannel) {
      voiceCount = sound.voices.isNotEmpty ? 1 : 0;
    } else {
      voiceCount = min(sound.voices.length, 3);
    }

    for (var i = 0; i < voiceCount; i++) {
      final pan = i == 0
          ? config.voice1Pan
          : (i == 1 ? config.voice2Pan : config.voice3Pan);
      _toneVoices.add(_buildVoice(sound.voices[i], pan, waveform, useEnvelope));
    }

    if (_hasNoise && mode != PcmPlaybackMode.ibmPcSingleChannel) {
      final toneVoice3 = sound.voices.length >= 3 ? sound.voices[2] : null;
      for (final n in sound.noise!.noises) {
        if (n.isSilent) continue;
        final startSample = ((n.startTime / 60.0) * sampleRate).round();
        final numSamples = ((n.duration / 60.0) * sampleRate).round();
        final endSample = min(startSample + numSamples, _totalFrames);

        double noiseClockHz;
        if (n.frequencyCount == 0x00 && toneVoice3 != null) {
          // Find tone 3 frequency count at current start time
          final tone3Note = toneVoice3.notes.firstWhere(
            (nt) => nt.startTime <= n.startTime && nt.endTime > n.startTime,
            orElse: () => toneVoice3.notes.first,
          );
          noiseClockHz = tone3Note.frequencyInHz;
        } else {
          final divisor = n.frequencyCount > 0 ? n.frequencyCount : 0x10;
          noiseClockHz = AgiNote.tandyClockDiv32 / divisor;
        }
        if (noiseClockHz <= 0) noiseClockHz = 1000.0;

        _noiseSegments.add(_NoiseSegment(
          startSample: startSample,
          endSample: endSample,
          amp: _sn76489AttenTable[n.attenuation.clamp(0, 15)],
          isWhite: n.type == NoiseType.white,
          samplesPerShift: sampleRate / noiseClockHz,
          leftGain: cos(config.noisePan * pi * 0.5),
          rightGain: sin(config.noisePan * pi * 0.5),
        ));
      }
    }

    _initReverb();
  }

  static int _computeTotalFrames(AgiSound sound, SynthesizerConfig config) {
    final totalTicks = sound.length;
    if (totalTicks <= 0) return 0;
    final totalSeconds = totalTicks / 60.0;
    // Add extra tail for reverb if enabled
    final tailSeconds =
        (config.enableReverb || config.mode == PcmPlaybackMode.enhanced) ? 1.0 : 0.05;
    return ((totalSeconds + tailSeconds) * config.sampleRate).ceil();
  }

  _ToneVoice _buildVoice(
    ToneChannel voice,
    double pan,
    WaveformType waveform,
    bool useEnvelope,
  ) {
    final sampleRate = config.sampleRate.toDouble();
    final segments = <_ToneSegment>[];
    for (final note in voice.notes) {
      if (note.isSilent) continue;

      final startSample = ((note.startTime / 60.0) * sampleRate).round();
      final numSamples = ((note.duration / 60.0) * sampleRate).round();
      final endSample = min(startSample + numSamples, _totalFrames);

      final freq = note.frequencyInHz;
      if (freq <= 0.0 || freq > sampleRate * 0.49) continue;

      segments.add(_ToneSegment(
        startSample: startSample,
        endSample: endSample,
        numSamples: numSamples,
        phaseInc: freq / sampleRate,
        baseAmp: _sn76489AttenTable[note.attenuation.clamp(0, 15)],
        // The legacy renderer reset phase for every note (no merged-
        // segment tracking existed), so every segment starts at 0.0.
        phaseStart: 0.0,
      ));
    }
    return _ToneVoice(
      segments: segments,
      leftGain: cos(pan * pi * 0.5),
      rightGain: sin(pan * pi * 0.5),
      waveform: waveform,
      useEnvelope: useEnvelope,
    );
  }

  void _initReverb() {
    final roomSize = config.reverbRoomSize;
    final damp = config.reverbDamping;

    // Comb filter tuning delay lengths (scaled for sample rate)
    final scale = config.sampleRate / 44100.0;
    const combTuningsL = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    const combTuningsR = [1139, 1211, 1300, 1379, 1445, 1514, 1580, 1640];
    const allpassTuningsL = [556, 441, 341, 225];
    const allpassTuningsR = [579, 464, 364, 248];

    _combsL = List<_CombFilter>.generate(
      combTuningsL.length,
      (i) => _CombFilter((combTuningsL[i] * scale).round(), roomSize, damp),
    );
    _combsR = List<_CombFilter>.generate(
      combTuningsR.length,
      (i) => _CombFilter((combTuningsR[i] * scale).round(), roomSize, damp),
    );
    _allpassesL = List<_AllPassFilter>.generate(
      allpassTuningsL.length,
      (i) => _AllPassFilter((allpassTuningsL[i] * scale).round(), 0.5),
    );
    _allpassesR = List<_AllPassFilter>.generate(
      allpassTuningsR.length,
      (i) => _AllPassFilter((allpassTuningsR[i] * scale).round(), 0.5),
    );
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
    _shiftRegister = 0x4000;
    for (final voice in _toneVoices) {
      for (final seg in voice.segments) {
        seg.phase = seg.phaseStart;
        seg.nextFrame = seg.startSample;
      }
    }
    for (final seg in _noiseSegments) {
      seg.sampleCounter = 0.0;
      seg.nextFrame = seg.startSample;
    }
    if (_reverbEnabled) _initReverb();
  }

  /// Seeks by resetting and rendering-and-discarding frames in chunks.
  /// This is O(frame) in time: there is no random-access cursor, so
  /// seeking far into a sound costs as much rendering as playing
  /// through it.
  @override
  void seekToFrame(int frame) {
    final target = frame.clamp(0, _totalFrames);
    reset();
    while (_position < target) {
      var chunk = target - _position;
      if (chunk > 4096) chunk = 4096;
      if (_discard.length < chunk * channels) {
        _discard = Int16List(chunk * channels);
      }
      renderInto(_discard, chunk);
    }
  }

  @override
  int renderInto(Int16List interleaved, int frameCount) {
    if (interleaved.length < frameCount * channels) {
      throw ArgumentError(
        'interleaved length ${interleaved.length} is less than '
        'frameCount * channels (${frameCount * channels})',
      );
    }
    if (frameCount <= 0) return 0;

    var n = frameCount;
    final remaining = _totalFrames - _position;
    if (n > remaining) n = remaining;
    if (n <= 0) return 0;

    if (_mixL.length < n) {
      _mixL = Float64List(n);
      _mixR = Float64List(n);
    }
    _mixL.fillRange(0, n, 0.0);
    _mixR.fillRange(0, n, 0.0);

    final blockStart = _position;
    final blockEnd = blockStart + n;

    // Tone voices in order, then noise: this preserves the legacy
    // per-sample float summation association (v1 + v2 + v3 + noise).
    for (final voice in _toneVoices) {
      _renderVoiceBlock(voice, blockStart, blockEnd);
    }
    for (final seg in _noiseSegments) {
      _renderNoiseBlock(seg, blockStart, blockEnd);
    }

    // Apply Freeverb DSP if enabled (stateful across blocks, so
    // block size cannot change the output).
    if (_reverbEnabled) {
      final wet = config.reverbMix;
      final dry = 1.0 - (wet * 0.5);
      for (var i = 0; i < n; i++) {
        final inputL = _mixL[i];
        final inputR = _mixR[i];
        final monoIn = (inputL + inputR) * 0.015;

        var outL = 0.0;
        var outR = 0.0;

        for (var c = 0; c < _combsL.length; c++) {
          outL += _combsL[c].process(monoIn);
          outR += _combsR[c].process(monoIn);
        }

        for (var a = 0; a < _allpassesL.length; a++) {
          outL = _allpassesL[a].process(outL);
          outR = _allpassesR[a].process(outR);
        }

        _mixL[i] = inputL * dry + outL * wet;
        _mixR[i] = inputR * dry + outR * wet;
      }
    }

    // Convert Float64 to Interleaved Int16 PCM with soft clipping.
    final master = config.masterVolume * 0.45; // headroom scaling
    for (var i = 0; i < n; i++) {
      var l = _mixL[i] * master;
      var r = _mixR[i] * master;

      // Soft polynomial limiter
      l = _softLimit(l);
      r = _softLimit(r);

      final l16 = (l * 32767.0).round().clamp(-32768, 32767);
      final r16 = (r * 32767.0).round().clamp(-32768, 32767);

      interleaved[i * 2] = l16;
      interleaved[i * 2 + 1] = r16;
    }

    _position += n;
    return n;
  }

  void _renderVoiceBlock(_ToneVoice voice, int blockStart, int blockEnd) {
    final sampleRate = config.sampleRate.toDouble();
    for (final seg in voice.segments) {
      var s = seg.nextFrame;
      final stop = min(seg.endSample, blockEnd);
      if (s < blockStart) s = blockStart;
      var phase = seg.phase;

      for (; s < stop; s++) {
        final t = (s - seg.startSample) / sampleRate;
        final noteProgress = (s - seg.startSample) / max(1, seg.numSamples);

        double sample;
        switch (voice.waveform) {
          case WaveformType.square:
            sample = phase < 0.5 ? 1.0 : -1.0;
            break;

          case WaveformType.sine:
            sample = sin(2.0 * pi * phase);
            break;

          case WaveformType.sawtooth:
            sample = 2.0 * phase - 1.0;
            break;

          case WaveformType.triangle:
            sample = 1.0 - 4.0 * (phase - 0.5).abs();
            break;

          case WaveformType.pulseWidthModulation:
            final pulseWidth = 0.5 + 0.2 * sin(2.0 * pi * 1.8 * t);
            sample = phase < pulseWidth ? 1.0 : -1.0;
            break;
        }

        // Apply smooth envelope in enhanced mode to eliminate clicks and harsh sustain
        var env = 1.0;
        if (voice.useEnvelope) {
          final posInNote = s - seg.startSample;
          final posFromEnd = seg.endSample - s;

          if (posInNote < _attackSamples) {
            env = posInNote / max(1, _attackSamples);
          } else if (posFromEnd < _releaseSamples) {
            env = posFromEnd / max(1, _releaseSamples);
          } else {
            // Gentle natural decay over sustain
            env = exp(-0.4 * noteProgress);
          }
        } else {
          // Simple 1ms anti-click ramp
          final posInNote = s - seg.startSample;
          final posFromEnd = seg.endSample - s;
          if (posInNote < _clickSamples) {
            env = posInNote / max(1, _clickSamples);
          } else if (posFromEnd < _clickSamples) {
            env = posFromEnd / max(1, _clickSamples);
          }
        }

        final outSample = sample * seg.baseAmp * env;
        _mixL[s - blockStart] += outSample * voice.leftGain;
        _mixR[s - blockStart] += outSample * voice.rightGain;

        phase += seg.phaseInc;
        if (phase >= 1.0) phase -= 1.0;
      }

      seg.phase = phase;
      seg.nextFrame = s;
    }
  }

  void _renderNoiseBlock(_NoiseSegment seg, int blockStart, int blockEnd) {
    var s = seg.nextFrame;
    final stop = min(seg.endSample, blockEnd);
    if (s < blockStart) s = blockStart;
    var sampleCounter = seg.sampleCounter;

    for (; s < stop; s++) {
      sampleCounter += 1.0;
      if (sampleCounter >= seg.samplesPerShift) {
        sampleCounter -= seg.samplesPerShift;

        // SN76489 LFSR shift logic:
        final bit0 = _shiftRegister & 1;
        int feedback;
        if (seg.isWhite) {
          final bit1 = (_shiftRegister >> 1) & 1;
          feedback = bit0 ^ bit1;
        } else {
          // Periodic noise
          feedback = bit0;
        }
        _shiftRegister = (_shiftRegister >> 1) | (feedback << 14);
      }

      final noiseSample = ((_shiftRegister & 1) == 1) ? 1.0 : -1.0;
      final outSample = noiseSample * seg.amp;

      _mixL[s - blockStart] += outSample * seg.leftGain;
      _mixR[s - blockStart] += outSample * seg.rightGain;
    }

    seg.sampleCounter = sampleCounter;
    seg.nextFrame = s;
  }

  static double _softLimit(double x) {
    if (x > 1.0) return 1.0;
    if (x < -1.0) return -1.0;
    return x;
  }
}

class _ToneVoice {
  final List<_ToneSegment> segments;
  final double leftGain;
  final double rightGain;
  final WaveformType waveform;
  final bool useEnvelope;

  _ToneVoice({
    required this.segments,
    required this.leftGain,
    required this.rightGain,
    required this.waveform,
    required this.useEnvelope,
  });
}

class _ToneSegment {
  final int startSample;
  final int endSample;
  final int numSamples;
  final double phaseInc;
  final double baseAmp;
  final double phaseStart;

  // Streaming cursor state, restored by reset().
  double phase;
  int nextFrame;

  _ToneSegment({
    required this.startSample,
    required this.endSample,
    required this.numSamples,
    required this.phaseInc,
    required this.baseAmp,
    required this.phaseStart,
  })  : phase = phaseStart,
        nextFrame = startSample;
}

class _NoiseSegment {
  final int startSample;
  final int endSample;
  final double amp;
  final bool isWhite;
  final double samplesPerShift;
  final double leftGain;
  final double rightGain;

  // Streaming cursor state, restored by reset(). The LFSR itself
  // lives on the source so it persists across segments.
  double sampleCounter = 0.0;
  int nextFrame;

  _NoiseSegment({
    required this.startSample,
    required this.endSample,
    required this.amp,
    required this.isWhite,
    required this.samplesPerShift,
    required this.leftGain,
    required this.rightGain,
  }) : nextFrame = startSample;
}

class _CombFilter {
  final Float64List buffer;
  final double feedback;
  final double damp;
  int bufferIndex = 0;
  double filterStore = 0.0;

  _CombFilter(int size, this.feedback, this.damp)
      : buffer = Float64List(max(1, size));

  double process(double input) {
    final output = buffer[bufferIndex];
    filterStore = (output * (1.0 - damp)) + (filterStore * damp);
    buffer[bufferIndex] = input + (filterStore * feedback);

    bufferIndex++;
    if (bufferIndex >= buffer.length) bufferIndex = 0;

    return output;
  }
}

class _AllPassFilter {
  final Float64List buffer;
  final double feedback;
  int bufferIndex = 0;

  _AllPassFilter(int size, this.feedback) : buffer = Float64List(max(1, size));

  double process(double input) {
    final bufOut = buffer[bufferIndex];
    final output = -input + bufOut;
    buffer[bufferIndex] = input + (bufOut * feedback);

    bufferIndex++;
    if (bufferIndex >= buffer.length) bufferIndex = 0;

    return output;
  }
}
