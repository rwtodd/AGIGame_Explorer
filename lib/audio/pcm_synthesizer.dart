import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/audio/agi_fm_adapter.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/audio/wav_encoder.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// The synthesis configuration types live in [pcm_source.dart]; they are
/// re-exported here so existing imports keep working.
export 'pcm_source.dart'
    show PcmPlaybackMode, WaveformType, SynthesizerConfig, AgiFmNoiseSource;

/// Software synthesizer for rendering [AgiSound] resources into 16-bit PCM audio.
///
/// This is an offline facade over [AgiPcmSource]: [renderPcm] drains a
/// fresh streaming source in 4096-frame blocks, so its output is
/// identical (sample for sample) to pulling blocks from the source
/// directly, and to the legacy one-shot renderer it replaces.
class PcmSynthesizer {
  final SynthesizerConfig config;

  const PcmSynthesizer([this.config = const SynthesizerConfig()]);

  /// Renders [sound] into an interleaved 16-bit signed stereo PCM sample buffer ([Int16List]).
  ///
  /// Routes through [createAgiPcmSource], so WAV export follows the
  /// configured mode (including FM presets) automatically.
  Int16List renderPcm(AgiSound sound) {
    final source = createAgiPcmSource(sound, config);
    final totalFrames = source.totalFrames ?? 0;
    if (totalFrames <= 0) {
      return Int16List(0);
    }

    final pcmSamples = Int16List(totalFrames * 2);
    var framesWritten = 0;
    while (!source.isFinished) {
      final chunk = min(4096, totalFrames - framesWritten);
      final written = source.renderInto(
        Int16List.sublistView(pcmSamples, framesWritten * 2),
        chunk,
      );
      framesWritten += written;
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
}
