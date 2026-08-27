import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// User display preferences for video rendering and scaling.
class AgiDisplaySettings {
  final bool correctAspectRatio;
  final bool strictIntegerScaling;
  final bool showCrtShader;
  final bool showPixelGrid;
  final bool renderBlackTextBackgrounds;
  final AgiPictureRenderMode renderMode;

  const AgiDisplaySettings({
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
    this.showCrtShader = false,
    this.showPixelGrid = false,
    this.renderBlackTextBackgrounds = false,
    this.renderMode = AgiPictureRenderMode.compositedSlices,
  });

  AgiDisplaySettings copyWith({
    bool? correctAspectRatio,
    bool? strictIntegerScaling,
    bool? showCrtShader,
    bool? showPixelGrid,
    bool? renderBlackTextBackgrounds,
    AgiPictureRenderMode? renderMode,
  }) {
    return AgiDisplaySettings(
      correctAspectRatio: correctAspectRatio ?? this.correctAspectRatio,
      strictIntegerScaling: strictIntegerScaling ?? this.strictIntegerScaling,
      showCrtShader: showCrtShader ?? this.showCrtShader,
      showPixelGrid: showPixelGrid ?? this.showPixelGrid,
      renderBlackTextBackgrounds:
          renderBlackTextBackgrounds ?? this.renderBlackTextBackgrounds,
      renderMode: renderMode ?? this.renderMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'correctAspectRatio': correctAspectRatio,
        'strictIntegerScaling': strictIntegerScaling,
        'showCrtShader': showCrtShader,
        'showPixelGrid': showPixelGrid,
        'renderBlackTextBackgrounds': renderBlackTextBackgrounds,
        'renderMode': renderMode.name,
      };

  factory AgiDisplaySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiDisplaySettings();

    AgiPictureRenderMode mode = AgiPictureRenderMode.compositedSlices;
    final modeStr = json['renderMode'] as String?;
    if (modeStr != null) {
      mode = AgiPictureRenderMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AgiPictureRenderMode.compositedSlices,
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
    );
  }
}

/// User audio preferences for sound synthesis and DSP effects.
class AgiAudioSettings {
  final AgiSoundMode soundMode;
  final WaveformType waveform;
  final bool enableReverb;
  final double reverbMix;
  final double masterVolume;

  const AgiAudioSettings({
    this.soundMode = AgiSoundMode.pcJr,
    this.waveform = WaveformType.square,
    this.enableReverb = false,
    this.reverbMix = 0.0,
    this.masterVolume = 0.75,
  });

  AgiAudioSettings copyWith({
    AgiSoundMode? soundMode,
    WaveformType? waveform,
    bool? enableReverb,
    double? reverbMix,
    double? masterVolume,
  }) {
    return AgiAudioSettings(
      soundMode: soundMode ?? this.soundMode,
      waveform: waveform ?? this.waveform,
      enableReverb: enableReverb ?? this.enableReverb,
      reverbMix: reverbMix ?? this.reverbMix,
      masterVolume: masterVolume ?? this.masterVolume,
    );
  }

  SynthesizerConfig toSynthesizerConfig() {
    final mode = switch (soundMode) {
      AgiSoundMode.ibmPc => PcmPlaybackMode.ibmPcSingleChannel,
      AgiSoundMode.enhanced => PcmPlaybackMode.enhanced,
      AgiSoundMode.pcJr || AgiSoundMode.off => PcmPlaybackMode.tandy3VoiceNoise,
    };

    return SynthesizerConfig(
      mode: mode,
      waveform: waveform,
      enableReverb: enableReverb && reverbMix > 0.0,
      reverbMix: reverbMix,
      masterVolume: masterVolume,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundMode': soundMode.name,
        'waveform': waveform.name,
        'enableReverb': enableReverb,
        'reverbMix': reverbMix,
        'masterVolume': masterVolume,
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

    return AgiAudioSettings(
      soundMode: soundMode,
      waveform: waveform,
      enableReverb: json['enableReverb'] as bool? ?? false,
      reverbMix: (json['reverbMix'] as num?)?.toDouble() ?? 0.0,
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 0.75,
    );
  }
}

/// User preferences for AI natural language command parsing.
class AgiAiSettings {
  final bool enabled;
  final String apiKey;
  final String model;

  const AgiAiSettings({
    this.enabled = false,
    this.apiKey = '',
    this.model = 'gemini-3.5-flash-lite',
  });

  AgiAiSettings copyWith({
    bool? enabled,
    String? apiKey,
    String? model,
  }) {
    return AgiAiSettings(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'apiKey': apiKey,
        'model': model,
      };

  factory AgiAiSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgiAiSettings();

    final rawModel = json['model'] as String? ?? 'gemini-3.5-flash-lite';
    // Auto-migrate retired/legacy models
    final sanitizedModel = switch (rawModel) {
      'gemini-2.0-flash' || 'gemini-2.5-flash' || 'gemini-1.5-flash' => 'gemini-3.5-flash-lite',
      _ => rawModel,
    };

    return AgiAiSettings(
      enabled: json['enabled'] as bool? ?? false,
      apiKey: json['apiKey'] as String? ?? '',
      model: sanitizedModel,
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

