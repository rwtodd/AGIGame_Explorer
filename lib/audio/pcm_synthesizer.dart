import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/audio/wav_encoder.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// Available playback / synthesis modes for rendering AGI sounds.
enum PcmPlaybackMode {
  /// Authentic IBM PC 1-channel square wave (Voice 1 only).
  ibmPcSingleChannel,

  /// Authentic Tandy 1000 / IBM PCjr 3-Voice Tone + Noise (SN76489 chip emulation).
  tandy3VoiceNoise,

  /// Enhanced modern synthesizer with selectable waveforms, stereo separation, and reverb.
  enhanced,
}

/// Available waveform shapes for the Enhanced synthesis mode.
enum WaveformType {
  /// Classic square wave.
  square,

  /// Soft sine wave.
  sine,

  /// Bright sawtooth wave.
  sawtooth,

  /// Warm triangle wave.
  triangle,

  /// Square wave with dynamic pulse-width modulation (PWM).
  pulseWidthModulation,
}

/// Configuration settings for the PCM synthesizer.
class SynthesizerConfig {
  /// Output sample rate in Hz (default 44100).
  final int sampleRate;

  /// Synthesis mode (IBM PC, Tandy 3-Voice, or Enhanced).
  final PcmPlaybackMode mode;

  /// Waveform used when [mode] is [PcmPlaybackMode.enhanced].
  final WaveformType waveform;

  /// Master volume scaling from 0.0 to 1.0 (default 0.75).
  final double masterVolume;

  /// Whether to apply reverb DSP. Default true in enhanced mode, false otherwise.
  final bool enableReverb;

  /// Reverb wet/dry mix ratio from 0.0 (dry) to 1.0 (wet). Default 0.25.
  final double reverbMix;

  /// Reverb room decay feedback from 0.0 to 0.98. Default 0.72.
  final double reverbRoomSize;

  /// Reverb high-frequency damping from 0.0 to 1.0. Default 0.2.
  final double reverbDamping;

  /// Stereo pan position for Tone Voice 1 (0.0 = full left, 0.5 = center, 1.0 = full right).
  final double voice1Pan;

  /// Stereo pan position for Tone Voice 2.
  final double voice2Pan;

  /// Stereo pan position for Tone Voice 3.
  final double voice3Pan;

  /// Stereo pan position for Noise channel.
  final double noisePan;

  const SynthesizerConfig({
    this.sampleRate = 44100,
    this.mode = PcmPlaybackMode.tandy3VoiceNoise,
    this.waveform = WaveformType.square,
    this.masterVolume = 0.75,
    this.enableReverb = false,
    this.reverbMix = 0.25,
    this.reverbRoomSize = 0.72,
    this.reverbDamping = 0.2,
    this.voice1Pan = 0.35,
    this.voice2Pan = 0.65,
    this.voice3Pan = 0.50,
    this.noisePan = 0.50,
  });

  /// Factory for default Tandy 1000 / PCjr mode.
  factory SynthesizerConfig.tandy({int sampleRate = 44100}) => SynthesizerConfig(
        sampleRate: sampleRate,
        mode: PcmPlaybackMode.tandy3VoiceNoise,
        waveform: WaveformType.square,
        masterVolume: 0.75,
        enableReverb: false,
      );

  /// Factory for authentic IBM PC single speaker mode.
  factory SynthesizerConfig.ibmPc({int sampleRate = 44100}) => SynthesizerConfig(
        sampleRate: sampleRate,
        mode: PcmPlaybackMode.ibmPcSingleChannel,
        waveform: WaveformType.square,
        masterVolume: 0.8,
        enableReverb: false,
        voice1Pan: 0.5,
      );

  /// Factory for enhanced stereo synthesizer with reverb and selectable waveform.
  factory SynthesizerConfig.enhanced({
    int sampleRate = 44100,
    WaveformType waveform = WaveformType.pulseWidthModulation,
    double reverbMix = 0.28,
  }) =>
      SynthesizerConfig(
        sampleRate: sampleRate,
        mode: PcmPlaybackMode.enhanced,
        waveform: waveform,
        masterVolume: 0.75,
        enableReverb: true,
        reverbMix: reverbMix,
        voice1Pan: 0.3,
        voice2Pan: 0.7,
        voice3Pan: 0.5,
        noisePan: 0.5,
      );

  SynthesizerConfig copyWith({
    int? sampleRate,
    PcmPlaybackMode? mode,
    WaveformType? waveform,
    double? masterVolume,
    bool? enableReverb,
    double? reverbMix,
    double? reverbRoomSize,
    double? reverbDamping,
    double? voice1Pan,
    double? voice2Pan,
    double? voice3Pan,
    double? noisePan,
  }) {
    return SynthesizerConfig(
      sampleRate: sampleRate ?? this.sampleRate,
      mode: mode ?? this.mode,
      waveform: waveform ?? this.waveform,
      masterVolume: masterVolume ?? this.masterVolume,
      enableReverb: enableReverb ?? this.enableReverb,
      reverbMix: reverbMix ?? this.reverbMix,
      reverbRoomSize: reverbRoomSize ?? this.reverbRoomSize,
      reverbDamping: reverbDamping ?? this.reverbDamping,
      voice1Pan: voice1Pan ?? this.voice1Pan,
      voice2Pan: voice2Pan ?? this.voice2Pan,
      voice3Pan: voice3Pan ?? this.voice3Pan,
      noisePan: noisePan ?? this.noisePan,
    );
  }
}

/// Software synthesizer for rendering [AgiSound] resources into 16-bit PCM audio.
class PcmSynthesizer {
  final SynthesizerConfig config;

  const PcmSynthesizer([this.config = const SynthesizerConfig()]);

  /// TI SN76489 / PCjr attenuation lookup table in linear amplitude (2dB steps).
  static final List<double> _sn76489AttenTable = List<double>.generate(16, (i) {
    if (i >= 15) return 0.0;
    return pow(10.0, -2.0 * i / 20.0).toDouble();
  });

  /// Renders [sound] into an interleaved 16-bit signed stereo PCM sample buffer ([Int16List]).
  Int16List renderPcm(AgiSound sound) {
    final totalTicks = sound.length;
    if (totalTicks <= 0) {
      return Int16List(0);
    }

    final totalSeconds = totalTicks / 60.0;
    // Add extra tail for reverb if enabled
    final tailSeconds = (config.enableReverb || config.mode == PcmPlaybackMode.enhanced) ? 1.0 : 0.05;
    final totalFrames = ((totalSeconds + tailSeconds) * config.sampleRate).ceil();

    final leftBuffer = Float64List(totalFrames);
    final rightBuffer = Float64List(totalFrames);

    switch (config.mode) {
      case PcmPlaybackMode.ibmPcSingleChannel:
        if (sound.voices.isNotEmpty) {
          _renderToneVoice(
            voice: sound.voices[0],
            leftOut: leftBuffer,
            rightOut: rightBuffer,
            pan: config.voice1Pan,
            waveform: WaveformType.square,
            useEnvelope: false,
          );
        }
        break;

      case PcmPlaybackMode.tandy3VoiceNoise:
        for (var i = 0; i < sound.voices.length && i < 3; i++) {
          final pan = i == 0
              ? config.voice1Pan
              : (i == 1 ? config.voice2Pan : config.voice3Pan);
          _renderToneVoice(
            voice: sound.voices[i],
            leftOut: leftBuffer,
            rightOut: rightBuffer,
            pan: pan,
            waveform: WaveformType.square,
            useEnvelope: false,
          );
        }
        if (sound.noise != null) {
          _renderNoiseChannel(
            noise: sound.noise!,
            toneVoice3: sound.voices.length >= 3 ? sound.voices[2] : null,
            leftOut: leftBuffer,
            rightOut: rightBuffer,
            pan: config.noisePan,
          );
        }
        break;

      case PcmPlaybackMode.enhanced:
        for (var i = 0; i < sound.voices.length && i < 3; i++) {
          final pan = i == 0
              ? config.voice1Pan
              : (i == 1 ? config.voice2Pan : config.voice3Pan);
          _renderToneVoice(
            voice: sound.voices[i],
            leftOut: leftBuffer,
            rightOut: rightBuffer,
            pan: pan,
            waveform: config.waveform,
            useEnvelope: true,
          );
        }
        if (sound.noise != null) {
          _renderNoiseChannel(
            noise: sound.noise!,
            toneVoice3: sound.voices.length >= 3 ? sound.voices[2] : null,
            leftOut: leftBuffer,
            rightOut: rightBuffer,
            pan: config.noisePan,
          );
        }
        break;
    }

    // Apply Reverb DSP if enabled
    if (config.enableReverb || (config.mode == PcmPlaybackMode.enhanced && config.reverbMix > 0.0)) {
      _applyFreeverb(leftBuffer, rightBuffer);
    }

    // Convert Float64 to Interleaved Int16 PCM with soft clipping
    final pcmSamples = Int16List(totalFrames * 2);
    final master = config.masterVolume * 0.45; // headroom scaling

    for (var frame = 0; frame < totalFrames; frame++) {
      var l = leftBuffer[frame] * master;
      var r = rightBuffer[frame] * master;

      // Soft polynomial limiter
      l = _softLimit(l);
      r = _softLimit(r);

      final l16 = (l * 32767.0).round().clamp(-32768, 32767);
      final r16 = (r * 32767.0).round().clamp(-32768, 32767);

      pcmSamples[frame * 2] = l16;
      pcmSamples[frame * 2 + 1] = r16;
    }

    return pcmSamples;
  }

  /// Renders [sound] directly into complete RIFF WAV container bytes.
  Uint8List renderWav(AgiSound sound) {
    final samples = renderPcm(sound);
    return WavEncoder.encode(
      samples: samples,
      sampleRate: config.sampleRate,
      numChannels: 2,
    );
  }

  static double _softLimit(double x) {
    if (x > 1.0) return 1.0;
    if (x < -1.0) return -1.0;
    return x;
  }

  void _renderToneVoice({
    required ToneChannel voice,
    required Float64List leftOut,
    required Float64List rightOut,
    required double pan,
    required WaveformType waveform,
    required bool useEnvelope,
  }) {
    final leftGain = cos(pan * pi * 0.5);
    final rightGain = sin(pan * pi * 0.5);
    final sampleRate = config.sampleRate.toDouble();

    for (final note in voice.notes) {
      if (note.isSilent) continue;

      final startSample = ((note.startTime / 60.0) * sampleRate).round();
      final numSamples = ((note.duration / 60.0) * sampleRate).round();
      final endSample = min(startSample + numSamples, leftOut.length);

      final freq = note.frequencyInHz;
      if (freq <= 0.0 || freq > sampleRate * 0.49) continue;

      final baseAmp = _sn76489AttenTable[note.attenuation.clamp(0, 15)];
      final phaseInc = freq / sampleRate;
      var phase = 0.0;

      for (var s = startSample; s < endSample; s++) {
        final t = (s - startSample) / sampleRate;
        final noteProgress = (s - startSample) / max(1, numSamples);

        double sample;
        switch (waveform) {
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
        if (useEnvelope) {
          // 4ms attack
          final attackSamples = (0.004 * sampleRate).round();
          // 4ms release
          final releaseSamples = (0.004 * sampleRate).round();
          final posInNote = s - startSample;
          final posFromEnd = endSample - s;

          if (posInNote < attackSamples) {
            env = posInNote / max(1, attackSamples);
          } else if (posFromEnd < releaseSamples) {
            env = posFromEnd / max(1, releaseSamples);
          } else {
            // Gentle natural decay over sustain
            env = exp(-0.4 * noteProgress);
          }
        } else {
          // Simple 1ms anti-click ramp
          final clickSamples = (0.001 * sampleRate).round();
          final posInNote = s - startSample;
          final posFromEnd = endSample - s;
          if (posInNote < clickSamples) {
            env = posInNote / max(1, clickSamples);
          } else if (posFromEnd < clickSamples) {
            env = posFromEnd / max(1, clickSamples);
          }
        }

        final outSample = sample * baseAmp * env;
        leftOut[s] += outSample * leftGain;
        rightOut[s] += outSample * rightGain;

        phase += phaseInc;
        if (phase >= 1.0) phase -= 1.0;
      }
    }
  }

  void _renderNoiseChannel({
    required NoiseChannel noise,
    required ToneChannel? toneVoice3,
    required Float64List leftOut,
    required Float64List rightOut,
    required double pan,
  }) {
    final leftGain = cos(pan * pi * 0.5);
    final rightGain = sin(pan * pi * 0.5);
    final sampleRate = config.sampleRate.toDouble();

    // 15-bit LFSR for authentic SN76489 noise
    var shiftRegister = 0x4000;

    for (final n in noise.noises) {
      if (n.isSilent) continue;

      final startSample = ((n.startTime / 60.0) * sampleRate).round();
      final numSamples = ((n.duration / 60.0) * sampleRate).round();
      final endSample = min(startSample + numSamples, leftOut.length);

      // Determine shift clock frequency
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

      final amp = _sn76489AttenTable[n.attenuation.clamp(0, 15)];
      final isWhite = n.type == NoiseType.white;
      final samplesPerShift = sampleRate / noiseClockHz;
      var sampleCounter = 0.0;

      for (var s = startSample; s < endSample; s++) {
        sampleCounter += 1.0;
        if (sampleCounter >= samplesPerShift) {
          sampleCounter -= samplesPerShift;

          // SN76489 LFSR shift logic:
          final bit0 = shiftRegister & 1;
          int feedback;
          if (isWhite) {
            final bit1 = (shiftRegister >> 1) & 1;
            feedback = bit0 ^ bit1;
          } else {
            // Periodic noise
            feedback = bit0;
          }
          shiftRegister = (shiftRegister >> 1) | (feedback << 14);
        }

        final noiseSample = ((shiftRegister & 1) == 1) ? 1.0 : -1.0;
        final outSample = noiseSample * amp;

        leftOut[s] += outSample * leftGain;
        rightOut[s] += outSample * rightGain;
      }
    }
  }

  /// High quality Freeverb stereo reverberation DSP.
  void _applyFreeverb(Float64List left, Float64List right) {
    final nFrames = min(left.length, right.length);
    final roomSize = config.reverbRoomSize;
    final damp = config.reverbDamping;
    final wet = config.reverbMix;
    final dry = 1.0 - (wet * 0.5);

    // Comb filter tuning delay lengths (scaled for sample rate)
    final scale = config.sampleRate / 44100.0;
    final combTuningsL = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    final combTuningsR = [1139, 1211, 1300, 1379, 1445, 1514, 1580, 1640];
    final allpassTuningsL = [556, 441, 341, 225];
    final allpassTuningsR = [579, 464, 364, 248];

    final combsL = List<_CombFilter>.generate(
      combTuningsL.length,
      (i) => _CombFilter((combTuningsL[i] * scale).round(), roomSize, damp),
    );
    final combsR = List<_CombFilter>.generate(
      combTuningsR.length,
      (i) => _CombFilter((combTuningsR[i] * scale).round(), roomSize, damp),
    );
    final allpassesL = List<_AllPassFilter>.generate(
      allpassTuningsL.length,
      (i) => _AllPassFilter((allpassTuningsL[i] * scale).round(), 0.5),
    );
    final allpassesR = List<_AllPassFilter>.generate(
      allpassTuningsR.length,
      (i) => _AllPassFilter((allpassTuningsR[i] * scale).round(), 0.5),
    );

    for (var i = 0; i < nFrames; i++) {
      final inputL = left[i];
      final inputR = right[i];
      final monoIn = (inputL + inputR) * 0.015;

      var outL = 0.0;
      var outR = 0.0;

      for (var c = 0; c < combsL.length; c++) {
        outL += combsL[c].process(monoIn);
        outR += combsR[c].process(monoIn);
      }

      for (var a = 0; a < allpassesL.length; a++) {
        outL = allpassesL[a].process(outL);
        outR = allpassesR[a].process(outR);
      }

      left[i] = inputL * dry + outL * wet;
      right[i] = right[i] * dry + outR * wet;
    }
  }
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
