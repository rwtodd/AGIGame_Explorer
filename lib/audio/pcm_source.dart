import 'dart:typed_data';

/// Current playback state of a PCM transport player.
enum SoundPlayerStatus {
  stopped,
  playing,
  paused,

  /// All frames were submitted and the sink has consumed them.
  completed,
}

/// Pull-based streaming PCM source contract.
///
/// A [PcmSource] renders interleaved signed 16-bit samples on demand,
/// one frame at a time, without allocating in steady state. It is the
/// transport boundary shared by the AGI renderer, future SCI FM device,
/// and MT-32 backends: a player owns one source and repeatedly asks for
/// blocks of frames until the source reports [isFinished].
abstract class PcmSource {
  /// Output sample rate in Hz.
  int get sampleRate;

  /// Number of interleaved channels (2 for stereo sources).
  int get channels;

  /// Total number of frames the source will ever produce, when finite.
  /// `null` means the source is unbounded (live synthesis).
  int? get totalFrames;

  /// Frames rendered since the last [reset] (or construction).
  int get positionFrames;

  /// Whether all frames have been rendered. Once finished, [renderInto]
  /// returns 0 and never produces more samples.
  bool get isFinished;

  /// Restores the source to its initial state: position 0, fresh
  /// synthesis state (phase, noise shift register, reverb filters).
  void reset();

  /// Seeks to an absolute frame offset. Implementations may reset and
  /// render-and-discard in chunks, which is O(frame) in time.
  void seekToFrame(int frame);

  /// Renders up to [frameCount] frames into [interleaved], which holds
  /// interleaved samples (frame 0 left, frame 0 right, ... for stereo).
  ///
  /// Writes at most `frameCount * channels` samples and returns the
  /// number of frames actually written. A short return (fewer than
  /// [frameCount] frames) happens only at end-of-stream; callers must
  /// not treat a short block as an error.
  ///
  /// [interleaved] must have length at least `frameCount * channels`,
  /// otherwise an [ArgumentError] is thrown before any sample is
  /// written. The destination is consumed synchronously: the source
  /// does not retain it after this call returns.
  int renderInto(Int16List interleaved, int frameCount);

  /// Releases any resources held by the source. The default
  /// implementation is a no-op (pure-Dart sources hold no resources).
  void dispose() {}
}

/// Available playback / synthesis modes for rendering AGI sounds.
enum PcmPlaybackMode {
  /// Authentic IBM PC 1-channel square wave (Voice 1 only).
  ibmPcSingleChannel,

  /// Authentic Tandy 1000 / IBM PCjr 3-Voice Tone + Noise (SN76489 chip emulation).
  tandy3VoiceNoise,

  /// Enhanced modern synthesizer with selectable waveforms, stereo separation, and reverb.
  enhanced,

  /// FM synthesis via the AGI FM adapter (project-authored OPL presets).
  fmPresets,
}

/// Where the AGI FM adapter gets its noise channel from.
enum AgiFmNoiseSource {
  /// SN76489 noise rendered by the existing Tandy renderer.
  tandy,

  /// No noise channel is mixed in.
  off,
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

  /// FM preset identifier used when [mode] is
  /// [PcmPlaybackMode.fmPresets] (default 'neutralKeys').
  final String fmPresetId;

  /// FM channel gain (default 1.0, clamped 0..2 at use).
  final double fmGain;

  /// FM-path noise gain (default 1.0, clamped 0..2 at use).
  final double fmNoiseGain;

  /// Noise source for the FM path (default tandy).
  final AgiFmNoiseSource fmNoiseSource;

  /// Per-voice gains for the AGI FM adapter (default 1.0 each,
  /// clamped 0..2 at use; 0 silences that voice).
  final double voice1Gain;
  final double voice2Gain;
  final double voice3Gain;

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
    this.fmPresetId = 'neutralKeys',
    this.fmGain = 1.0,
    this.fmNoiseGain = 1.0,
    this.fmNoiseSource = AgiFmNoiseSource.tandy,
    this.voice1Gain = 1.0,
    this.voice2Gain = 1.0,
    this.voice3Gain = 1.0,
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

  /// Factory for AGI FM adapter mode.
  factory SynthesizerConfig.fm({
    int sampleRate = 44100,
    String fmPresetId = 'neutralKeys',
  }) =>
      SynthesizerConfig(
        sampleRate: sampleRate,
        mode: PcmPlaybackMode.fmPresets,
        waveform: WaveformType.square,
        masterVolume: 0.75,
        enableReverb: false,
        fmPresetId: fmPresetId,
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
    String? fmPresetId,
    double? fmGain,
    double? fmNoiseGain,
    AgiFmNoiseSource? fmNoiseSource,
    double? voice1Gain,
    double? voice2Gain,
    double? voice3Gain,
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
      fmPresetId: fmPresetId ?? this.fmPresetId,
      fmGain: fmGain ?? this.fmGain,
      fmNoiseGain: fmNoiseGain ?? this.fmNoiseGain,
      fmNoiseSource: fmNoiseSource ?? this.fmNoiseSource,
      voice1Gain: voice1Gain ?? this.voice1Gain,
      voice2Gain: voice2Gain ?? this.voice2Gain,
      voice3Gain: voice3Gain ?? this.voice3Gain,
    );
  }
}
