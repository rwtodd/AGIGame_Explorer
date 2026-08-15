import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/mac_audio_queue_sink.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// Current playback state of [AgiSoundPlayer].
enum SoundPlayerStatus {
  stopped,
  playing,
  paused,
}

/// Represents the current playback position and timing information.
class SoundPlaybackPosition {
  /// Current playback position in 1/60th second ticks.
  final int currentTick;

  /// Total duration in 1/60th second ticks.
  final int totalTicks;

  /// Current playback position in elapsed seconds.
  final double currentSeconds;

  /// Total duration in seconds.
  final double totalSeconds;

  /// Normalized progress from 0.0 to 1.0.
  final double progressFraction;

  /// Current playback player status.
  final SoundPlayerStatus status;

  const SoundPlaybackPosition({
    this.currentTick = 0,
    this.totalTicks = 0,
    this.currentSeconds = 0.0,
    this.totalSeconds = 0.0,
    this.progressFraction = 0.0,
    this.status = SoundPlayerStatus.stopped,
  });

  static const zero = SoundPlaybackPosition();
}

/// High-level audio player engine for AGI sounds.
///
/// Handles synthesis, PCM streaming, position tracking, seeking, volume,
/// looping, and completion events for both Sound Browser preview and AGI gameplay.
class AgiSoundPlayer {
  final AudioOutputSink _sink;
  final bool _autoDisposeSink;

  AgiSound? _currentSound;
  SynthesizerConfig _currentConfig = const SynthesizerConfig();

  SoundPlayerStatus _status = SoundPlayerStatus.stopped;
  int _startTickOffset = 0;
  int _totalTicks = 0;
  bool _isLooping = false;
  double _volume = 0.8;

  Timer? _positionTimer;
  final Stopwatch _stopwatch = Stopwatch();

  void Function()? onFinished;

  final StreamController<SoundPlaybackPosition> _positionController =
      StreamController<SoundPlaybackPosition>.broadcast();

  /// Stream of playback position updates (emitted at ~60 Hz during active playback).
  Stream<SoundPlaybackPosition> get positionStream => _positionController.stream;

  /// Current playback status.
  SoundPlayerStatus get status => _status;

  /// Whether audio is actively playing.
  bool get isPlaying => _status == SoundPlayerStatus.playing;

  /// Whether playback is paused.
  bool get isPaused => _status == SoundPlayerStatus.paused;

  /// Whether playback is stopped.
  bool get isStopped => _status == SoundPlayerStatus.stopped;

  /// Whether looping is enabled.
  bool get isLooping => _isLooping;

  /// Current volume level (0.0 to 1.0).
  double get volume => _volume;

  /// Total ticks of the current sound.
  int get totalTicks => _totalTicks;

  /// Active sound resource loaded into player.
  AgiSound? get currentSound => _currentSound;

  AgiSoundPlayer({
    AudioOutputSink? sink,
  })  : _sink = sink ?? _createDefaultSink(),
        _autoDisposeSink = sink == null;

  static AudioOutputSink _createDefaultSink() {
    if (Platform.isMacOS) {
      try {
        return MacAudioQueueSink();
      } catch (e) {
        return NullAudioSink();
      }
    }
    return NullAudioSink();
  }

  /// Initializes the underlying audio output device.
  Future<void> initialize({int sampleRate = 44100}) async {
    await _sink.initialize(
      sampleRate: sampleRate,
      numChannels: 2,
      bufferSizeInFrames: 4096,
    );
    _sink.setVolume(_volume);
  }

  /// Plays [sound] using the provided [config], starting from [startTick].
  Future<void> play(
    AgiSound sound, {
    SynthesizerConfig? config,
    int startTick = 0,
  }) async {
    if (sound.isEmpty || sound.length <= 0) {
      stop();
      return;
    }

    _currentSound = sound;
    if (config != null) _currentConfig = config;
    _totalTicks = sound.length;
    _startTickOffset = startTick.clamp(0, _totalTicks);

    // Make sure sink is initialized
    if (_sink.status == AudioPlaybackStatus.uninitialized) {
      await initialize(sampleRate: _currentConfig.sampleRate);
    }

    _sink.stop();
    _sink.flush();

    // Synthesize PCM samples
    final synth = PcmSynthesizer(_currentConfig);
    final pcmSamples = synth.renderPcm(sound);

    if (pcmSamples.isEmpty) {
      stop();
      return;
    }

    // If starting from a non-zero tick offset, calculate sample offset
    Int16List samplesToWrite;
    if (_startTickOffset > 0) {
      final sampleRate = _currentConfig.sampleRate;
      final startFrame = ((_startTickOffset / 60.0) * sampleRate).round();
      final startSampleIndex = min(startFrame * 2, pcmSamples.length);
      samplesToWrite = Int16List.sublistView(pcmSamples, startSampleIndex);
    } else {
      samplesToWrite = pcmSamples;
    }

    _sink.writePcm(samplesToWrite);
    _sink.setVolume(_volume);
    _sink.play();

    _status = SoundPlayerStatus.playing;
    _stopwatch.reset();
    _stopwatch.start();

    _startPositionTimer();
    _emitPosition();
  }

  /// Resumes playback if paused.
  void resume() {
    if (_status != SoundPlayerStatus.paused) return;

    _sink.play();
    _status = SoundPlayerStatus.playing;
    _stopwatch.start();
    _startPositionTimer();
    _emitPosition();
  }

  /// Pauses playback.
  void pause() {
    if (_status != SoundPlayerStatus.playing) return;

    _stopwatch.stop();
    _sink.pause();
    _status = SoundPlayerStatus.paused;
    _stopPositionTimer();
    _emitPosition();
  }

  /// Stops playback and resets position to the beginning.
  void stop() {
    _stopwatch.reset();
    _sink.stop();
    _status = SoundPlayerStatus.stopped;
    _stopPositionTimer();
    _startTickOffset = 0;
    _emitPosition();
  }

  /// Seeks to a specific [tick] position in the sound.
  Future<void> seekToTick(int tick) async {
    final targetTick = tick.clamp(0, _totalTicks);
    final wasPlaying = isPlaying;

    if (_currentSound != null) {
      if (wasPlaying) {
        await play(_currentSound!, config: _currentConfig, startTick: targetTick);
      } else {
        _startTickOffset = targetTick;
        _stopwatch.reset();
        _emitPosition();
      }
    }
  }

  /// Sets the output volume from 0.0 to 1.0.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _sink.setVolume(_volume);
  }

  /// Sets whether the sound should automatically loop when finished.
  void setLooping(bool loop) {
    _isLooping = loop;
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _onPositionTick();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _onPositionTick() {
    if (_status != SoundPlayerStatus.playing) return;

    final elapsedSeconds =
        (_startTickOffset / 60.0) + (_stopwatch.elapsedMicroseconds / 1000000.0);
    final totalSeconds = _totalTicks / 60.0;

    // Check if playback has reached or exceeded total duration (+ tail)
    final tailSeconds = (_currentConfig.enableReverb || _currentConfig.mode == PcmPlaybackMode.enhanced)
        ? 1.0
        : 0.05;

    if (elapsedSeconds >= (totalSeconds + tailSeconds)) {
      if (_isLooping && _currentSound != null) {
        play(_currentSound!, config: _currentConfig, startTick: 0);
      } else {
        stop();
        onFinished?.call();
      }
      return;
    }

    _emitPosition();
  }

  void _emitPosition() {
    if (_totalTicks <= 0) {
      _positionController.add(SoundPlaybackPosition(status: _status));
      return;
    }

    final elapsedSeconds =
        (_startTickOffset / 60.0) + (_stopwatch.elapsedMicroseconds / 1000000.0);
    final totalSeconds = _totalTicks / 60.0;
    final currentSeconds = min(elapsedSeconds, totalSeconds);
    final currentTick = min((currentSeconds * 60.0).round(), _totalTicks);
    final progress = totalSeconds > 0 ? (currentSeconds / totalSeconds).clamp(0.0, 1.0) : 0.0;

    _positionController.add(SoundPlaybackPosition(
      currentTick: currentTick,
      totalTicks: _totalTicks,
      currentSeconds: currentSeconds,
      totalSeconds: totalSeconds,
      progressFraction: progress,
      status: _status,
    ));
  }

  /// Releases all player and audio sink resources.
  void dispose() {
    stop();
    _stopPositionTimer();
    if (_autoDisposeSink) {
      _sink.dispose();
    }
    _positionController.close();
  }
}
