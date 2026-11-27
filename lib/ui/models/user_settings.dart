import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// User display preferences for video rendering and scaling.
class AgiDisplaySettings {
  final bool correctAspectRatio;
  final bool strictIntegerScaling;
  final bool showCrtShader;
  final bool showPixelGrid;
  final bool renderBlackTextBackgrounds;
  final AgiPictureRenderMode renderMode;
  final bool sciEnableDithering;

  const AgiDisplaySettings({
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
    this.showCrtShader = false,
    this.showPixelGrid = false,
    this.renderBlackTextBackgrounds = false,
    this.renderMode = AgiPictureRenderMode.shaderComposited,
    this.sciEnableDithering = true,
  });

  AgiDisplaySettings copyWith({
    bool? correctAspectRatio,
    bool? strictIntegerScaling,
    bool? showCrtShader,
    bool? showPixelGrid,
    bool? renderBlackTextBackgrounds,
    AgiPictureRenderMode? renderMode,
    bool? sciEnableDithering,
  }) {
    return AgiDisplaySettings(
      correctAspectRatio: correctAspectRatio ?? this.correctAspectRatio,
      strictIntegerScaling: strictIntegerScaling ?? this.strictIntegerScaling,
      showCrtShader: showCrtShader ?? this.showCrtShader,
      showPixelGrid: showPixelGrid ?? this.showPixelGrid,
      renderBlackTextBackgrounds:
          renderBlackTextBackgrounds ?? this.renderBlackTextBackgrounds,
      renderMode: renderMode ?? this.renderMode,
      sciEnableDithering: sciEnableDithering ?? this.sciEnableDithering,
    );
  }

  Map<String, dynamic> toJson() => {
        'correctAspectRatio': correctAspectRatio,
        'strictIntegerScaling': strictIntegerScaling,
        'showCrtShader': showCrtShader,
        'showPixelGrid': showPixelGrid,
        'renderBlackTextBackgrounds': renderBlackTextBackgrounds,
        'renderMode': renderMode.name,
        'sciEnableDithering': sciEnableDithering,
      };

  factory AgiDisplaySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiDisplaySettings();

    AgiPictureRenderMode mode = AgiPictureRenderMode.shaderComposited;
    final modeStr = json['renderMode'] as String?;
    if (modeStr != null) {
      mode = AgiPictureRenderMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AgiPictureRenderMode.shaderComposited,
      );
    }

    return AgiDisplaySettings(
      correctAspectRatio: json['correctAspectRatio'] as bool? ?? true,
      strictIntegerScaling: json['strictIntegerScaling'] as bool? ?? false,
      showCrtShader: json['showCrtShader'] as bool? ?? false,
      showPixelGrid: json['showPixelGrid'] as bool? ?? false,
      renderBlackTextBackgrounds:
          json['renderBlackTextBackgrounds'] as bool? ?? false,
      renderMode: mode,
      sciEnableDithering: json['sciEnableDithering'] as bool? ?? true,
    );
  }
}

/// Default per-voice pans for AGI audio (matches [SynthesizerConfig]).
const List<double> kDefaultVoicePans = [0.35, 0.65, 0.50];

/// Default per-voice gains (unity).
const List<double> kDefaultVoiceGains = [1.0, 1.0, 1.0];

/// User audio preferences for sound synthesis and DSP effects.
class AgiAudioSettings {
  final AgiSoundMode soundMode;
  final WaveformType waveform;
  final bool enableReverb;
  final double reverbMix;
  final double masterVolume;

  /// SCI music-output device (legacy PSG by default; AdLib is opt-in).
  final SciMusicDevice sciMusicDevice;

  /// AGI FM adapter preset identifier (default 'neutralKeys').
  final String fmPresetId;

  /// AGI FM channel gain (default 1.0).
  final double fmGain;

  /// AGI FM-path noise gain (default 1.0).
  final double fmNoiseGain;

  /// AGI FM noise source (default tandy).
  final AgiFmNoiseSource fmNoiseSource;

  /// Per-AGI-voice gains (length 3, default unity).
  final List<double> voiceGains;

  /// Per-AGI-voice pans (length 3, default [kDefaultVoicePans]).
  final List<double> voicePans;

  const AgiAudioSettings({
    this.soundMode = AgiSoundMode.pcJr,
    this.waveform = WaveformType.square,
    this.enableReverb = false,
    this.reverbMix = 0.0,
    this.masterVolume = 0.75,
    this.sciMusicDevice = SciMusicDevice.legacyPsg,
    this.fmPresetId = 'neutralKeys',
    this.fmGain = 1.0,
    this.fmNoiseGain = 1.0,
    this.fmNoiseSource = AgiFmNoiseSource.tandy,
    this.voiceGains = kDefaultVoiceGains,
    this.voicePans = kDefaultVoicePans,
  });

  AgiAudioSettings copyWith({
    AgiSoundMode? soundMode,
    WaveformType? waveform,
    bool? enableReverb,
    double? reverbMix,
    double? masterVolume,
    SciMusicDevice? sciMusicDevice,
    String? fmPresetId,
    double? fmGain,
    double? fmNoiseGain,
    AgiFmNoiseSource? fmNoiseSource,
    List<double>? voiceGains,
    List<double>? voicePans,
  }) {
    return AgiAudioSettings(
      soundMode: soundMode ?? this.soundMode,
      waveform: waveform ?? this.waveform,
      enableReverb: enableReverb ?? this.enableReverb,
      reverbMix: reverbMix ?? this.reverbMix,
      masterVolume: masterVolume ?? this.masterVolume,
      sciMusicDevice: sciMusicDevice ?? this.sciMusicDevice,
      fmPresetId: fmPresetId ?? this.fmPresetId,
      fmGain: fmGain ?? this.fmGain,
      fmNoiseGain: fmNoiseGain ?? this.fmNoiseGain,
      fmNoiseSource: fmNoiseSource ?? this.fmNoiseSource,
      voiceGains: voiceGains ?? this.voiceGains,
      voicePans: voicePans ?? this.voicePans,
    );
  }

  SynthesizerConfig toSynthesizerConfig() {
    final mode = switch (soundMode) {
      AgiSoundMode.ibmPc => PcmPlaybackMode.ibmPcSingleChannel,
      AgiSoundMode.enhanced => PcmPlaybackMode.enhanced,
      AgiSoundMode.fm => PcmPlaybackMode.fmPresets,
      AgiSoundMode.pcJr || AgiSoundMode.off => PcmPlaybackMode.tandy3VoiceNoise,
    };

    // FM fields are passed through for every mode so a preview
    // surface can render FM from the same config; non-FM renderers
    // simply ignore them.
    return SynthesizerConfig(
      mode: mode,
      waveform: waveform,
      enableReverb: enableReverb && reverbMix > 0.0,
      reverbMix: reverbMix,
      masterVolume: masterVolume,
      voice1Pan: voicePans[0],
      voice2Pan: voicePans[1],
      voice3Pan: voicePans[2],
      fmPresetId: fmPresetId,
      fmGain: fmGain,
      fmNoiseGain: fmNoiseGain,
      fmNoiseSource: fmNoiseSource,
      voice1Gain: voiceGains[0],
      voice2Gain: voiceGains[1],
      voice3Gain: voiceGains[2],
    );
  }

  Map<String, dynamic> toJson() => {
        'soundMode': soundMode.name,
        'waveform': waveform.name,
        'enableReverb': enableReverb,
        'reverbMix': reverbMix,
        'masterVolume': masterVolume,
        'sciMusicDevice': sciMusicDevice.name,
        'fmPresetId': fmPresetId,
        'fmGain': fmGain,
        'fmNoiseGain': fmNoiseGain,
        'fmNoiseSource': fmNoiseSource.name,
        'voiceGains': voiceGains,
        'voicePans': voicePans,
      };

  factory AgiAudioSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiAudioSettings();

    AgiSoundMode soundMode = AgiSoundMode.pcJr;
    final soundModeStr = json['soundMode'] as String?;
    if (soundModeStr != null) {
      soundMode = AgiSoundMode.values.firstWhere(
        (m) => m.name == soundModeStr,
        orElse: () => AgiSoundMode.pcJr,
      );
    }

    WaveformType waveform = WaveformType.square;
    final waveStr = json['waveform'] as String?;
    if (waveStr != null) {
      waveform = WaveformType.values.firstWhere(
        (w) => w.name == waveStr,
        orElse: () => WaveformType.square,
      );
    }

    // Tolerant of pre-Stage-6b settings files (missing key) and of
    // unknown values from a newer build: both fall back to legacy.
    SciMusicDevice sciMusicDevice = SciMusicDevice.legacyPsg;
    final deviceStr = json['sciMusicDevice'] as String?;
    if (deviceStr != null) {
      sciMusicDevice = SciMusicDevice.values.firstWhere(
        (d) => d.name == deviceStr,
        orElse: () => SciMusicDevice.legacyPsg,
      );
    }

    // FM fields (Stage 9): missing keys (pre-Stage-9 files) and short
    // or malformed lists fall back to defaults; unknown enum names
    // fall back to tandy.
    final fmNoiseSourceStr = json['fmNoiseSource'] as String?;
    final fmNoiseSource = fmNoiseSourceStr == null
        ? AgiFmNoiseSource.tandy
        : AgiFmNoiseSource.values.firstWhere(
            (d) => d.name == fmNoiseSourceStr,
            orElse: () => AgiFmNoiseSource.tandy,
          );

    List<double> parseList(Object? value, List<double> defaults) {
      if (value is! List) return List<double>.from(defaults);
      final out = <double>[];
      for (var i = 0; i < 3; i++) {
        if (i < value.length && value[i] is num) {
          out.add((value[i] as num).toDouble());
        } else {
          out.add(defaults[i]);
        }
      }
      return out;
    }

    return AgiAudioSettings(
      soundMode: soundMode,
      waveform: waveform,
      enableReverb: json['enableReverb'] as bool? ?? false,
      reverbMix: (json['reverbMix'] as num?)?.toDouble() ?? 0.0,
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 0.75,
      sciMusicDevice: sciMusicDevice,
      fmPresetId: json['fmPresetId'] as String? ?? 'neutralKeys',
      fmGain: (json['fmGain'] as num?)?.toDouble() ?? 1.0,
      fmNoiseGain: (json['fmNoiseGain'] as num?)?.toDouble() ?? 1.0,
      fmNoiseSource: fmNoiseSource,
      voiceGains: parseList(json['voiceGains'], kDefaultVoiceGains),
      voicePans: parseList(json['voicePans'], kDefaultVoicePans),
    );
  }
}

/// User preferences for AI natural language command parsing.
class AgiAiSettings {
  final bool enabled;
  final String model;

  /// Local sidecar endpoint (e.g. `http://127.0.0.1:8080`).
  final String endpoint;

  final double similarityThreshold;

  const AgiAiSettings({
    this.enabled = false,
    this.model = 'embeddinggemma-2-text',
    this.endpoint = 'http://127.0.0.1:8080',
    this.similarityThreshold = 0.75,
  });

  AgiAiSettings copyWith({
    bool? enabled,
    String? model,
    String? endpoint,
    double? similarityThreshold,
  }) {
    return AgiAiSettings(
      enabled: enabled ?? this.enabled,
      model: model ?? this.model,
      endpoint: endpoint ?? this.endpoint,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'model': model,
        'endpoint': endpoint,
        'similarityThreshold': similarityThreshold,
      };

  factory AgiAiSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiAiSettings();

    final rawModel = json['model'] as String? ?? 'embeddinggemma-2-text';
    // Auto-migrate retired cloud models to the local EmbeddingGemma 2 encoder.
    // (Stored API keys are dropped: local embeddings need no key.)
    final sanitizedModel = switch (rawModel) {
      'text-embedding-004' ||
      'gemini-embedding-001' ||
      'gemini-3.5-flash-lite' ||
      'gemini-3.6-flash' ||
      'gemini-3.7-flash' ||
      'gemini-flash-latest' ||
      'gemini-2.0-flash' ||
      'gemini-2.5-flash' ||
      'gemini-1.5-flash' =>
        'embeddinggemma-2-text',
      _ => rawModel,
    };

    return AgiAiSettings(
      enabled: json['enabled'] as bool? ?? false,
      model: sanitizedModel,
      endpoint: json['endpoint'] as String? ?? 'http://127.0.0.1:8080',
      similarityThreshold:
          (json['similarityThreshold'] as num?)?.toDouble() ?? 0.75,
    );
  }
}

/// Root container for user AGI engine and workbench settings.
class AgiUserSettings {
  final AgiDisplaySettings display;
  final AgiAudioSettings audio;
  final AgiAiSettings ai;

  const AgiUserSettings({
    this.display = const AgiDisplaySettings(),
    this.audio = const AgiAudioSettings(),
    this.ai = const AgiAiSettings(),
  });

  AgiUserSettings copyWith({
    AgiDisplaySettings? display,
    AgiAudioSettings? audio,
    AgiAiSettings? ai,
  }) {
    return AgiUserSettings(
      display: display ?? this.display,
      audio: audio ?? this.audio,
      ai: ai ?? this.ai,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': '1.0',
        'display': display.toJson(),
        'audio': audio.toJson(),
        'ai': ai.toJson(),
      };

  factory AgiUserSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiUserSettings();

    return AgiUserSettings(
      display: AgiDisplaySettings.fromJson(json['display'] as Map<String, dynamic>?),
      audio: AgiAudioSettings.fromJson(json['audio'] as Map<String, dynamic>?),
      ai: AgiAiSettings.fromJson(json['ai'] as Map<String, dynamic>?),
    );
  }
}

