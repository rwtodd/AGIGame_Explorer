import 'dart:async';
import 'dart:io';
import 'package:flutter_agigame/audio/agi_pcm_source.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/mac_audio_queue_sink.dart';
import 'package:flutter_agigame/audio/windows_wave_out_sink.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/audio/streaming_pcm_player.dart';
import 'package:flutter_agigame/domain/sound.dart';

export 'package:flutter_agigame/audio/pcm_source.dart' show SoundPlayerStatus;

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
/// Compatibility facade over [StreamingPcmPlayer] + [AgiPcmSource],
/// preserving the public API and observable semantics for Sound Browser
/// previews and AGI gameplay. Muted playback (`muted: true`) historically
/// drives a stopwatch completion timer without touching the sink; that
/// timer path is preserved verbatim and is intentionally not routed
/// through the streaming player.
class AgiSoundPlayer {
  final AudioOutputSink _sink;
  final bool _autoDisposeSink;
  late final StreamingPcmPlayer _player;

  AgiSound? _currentSound;
  SynthesizerConfig _currentConfig = const SynthesizerConfig();

  SoundPlayerStatus _status = SoundPlayerStatus.stopped;
  int _startTickOffset = 0;
  int _totalTicks = 0;
  int _sourceTotalFrames = 0;
  bool _isLooping = false;
  double _volume = 0.8;
  bool _isMuted = false;

  // Muted-path only: stopwatch + periodic position timer.
  Timer? _positionTimer;
  final Stopwatch _stopwatch = Stopwatch();
  bool _mutedActive = false;

  bool _isDisposed = false;

  void Function()? onFinished;

  final StreamController<SoundPlaybackPosition> _positionController =
      StreamController<SoundPlaybackPosition>.broadcast();

  /// Stream of playback position updates (emitted at ~60 Hz during active playback).
  Stream<SoundPlaybackPosition> get positionStream => _positionController.stream;

  /// Whether player has been disposed.
  bool get isDisposed => _isDisposed;

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

  /// Whether playback is currently muted.
  bool get isMuted => _isMuted;

  AgiSoundPlayer({
    AudioOutputSink? sink,
  })  : _autoDisposeSink = sink == null,
        _sink = sink ?? _createDefaultSink() {
    _player = StreamingPcmPlayer(sink: _sink, ownsSink: _autoDisposeSink);
    _player.onPositionFrames = (_) => _emitPosition();
    _player.onFinished = _onStreamingFinished;
  }


  static AudioOutputSink _createDefaultSink() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return NullAudioSink();
    }
    if (Platform.isMacOS) {
      try {
        return MacAudioQueueSink();
      } catch (e) {
        return NullAudioSink();
      }
    }
    if (Platform.isWindows) {
      try {
        return WindowsWaveOutSink();
      } catch (e) {
        return NullAudioSink();
      }
    }
    return NullAudioSink();
  }

  /// Initializes the underlying audio output device.
  Future<void> initialize({int sampleRate = 44100}) async {
    if (_isDisposed) return;
    await _sink.initialize(
      sampleRate: sampleRate,
      numChannels: 2,
      bufferSizeInFrames: 4096,
    );
    _sink.setVolume(_volume);
  }

  /// Mutes audio output while keeping playback timer running.
  void mute() {
    _isMuted = true;
    _sink.setVolume(0.0);
  }

  /// Unmutes audio output.
  void unmute() {
    _isMuted = false;
    _sink.setVolume(_volume);
  }

  /// Plays [sound] using the provided [config], starting from [startTick].
  /// When [muted] is true, the sound timer drives playback to completion without audio output.
  Future<void> play(
    AgiSound sound, {
    SynthesizerConfig? config,
    int startTick = 0,
    bool muted = false,
  }) async {
    if (_isDisposed) return;
    if (sound.isEmpty || sound.length <= 0) {
      stop();
      return;
    }

    _stopwatch.reset();
    _stopPositionTimer();

    _currentSound = sound;
    if (config != null) _currentConfig = config;
    _totalTicks = sound.length;
    _startTickOffset = startTick.clamp(0, _totalTicks);
    _isMuted = muted;
    _mutedActive = muted;

    _sink.stop();
    _sink.flush();

    if (!muted) {
      final source = AgiPcmSource(sound, config: _currentConfig);
      final totalFrames = source.totalFrames ?? 0;
      _sourceTotalFrames = totalFrames;

      // Equivalent of the legacy empty-render check: nothing to play.
      if (totalFrames <= 0) {
        stop();
        return;
      }

      _player.looping = _isLooping;
      _player.muted = false;
      final startFrame =
          ((_startTickOffset / 60.0) * _currentConfig.sampleRate).round();
      await _player.playSource(source, startFrame: startFrame);
      if (_isDisposed) return;
      _sink.setVolume(_volume);
      _status = SoundPlayerStatus.playing;
      _emitPosition();
    } else {
      // No sound-producing source should keep rendering into the sink.
      _player.stop();
      _status = SoundPlayerStatus.playing;
      _stopwatch.start();
      _startPositionTimer();
      _emitPosition();
    }
  }

  /// Resumes playback if paused.
  void resume() {
    if (_isDisposed || _status != SoundPlayerStatus.paused) return;

    if (_mutedActive) {
      _sink.play();
      _status = SoundPlayerStatus.playing;
      _stopwatch.start();
      _startPositionTimer();
      _emitPosition();
    } else {
      _player.resume();
      _status = SoundPlayerStatus.playing;
      _emitPosition();
    }
  }

  /// Pauses playback.
  void pause() {
    if (_isDisposed || _status != SoundPlayerStatus.playing) return;

    if (_mutedActive) {
      _stopwatch.stop();
      _sink.pause();
      _status = SoundPlayerStatus.paused;
      _stopPositionTimer();
      _emitPosition();
    } else {
      _player.pause();
      _status = SoundPlayerStatus.paused;
      _emitPosition();
    }
  }

  /// Stops playback and resets position to the beginning.
  void stop() {
    if (_isDisposed) return;
    _stopwatch.reset();
    _stopPositionTimer();
    _mutedActive = false;
    _player.stop();
    _sink.stop();
    _status = SoundPlayerStatus.stopped;
    _startTickOffset = 0;
    _emitPosition();
  }

  /// Seeks to a specific [tick] position in the sound.
  Future<void> seekToTick(int tick) async {
    if (_isDisposed) return;
    final targetTick = tick.clamp(0, _totalTicks);
    final wasPlaying = isPlaying;

    if (_currentSound != null) {
      if (wasPlaying) {
        await play(_currentSound!, config: _currentConfig, startTick: targetTick);
      } else {
        if (_mutedActive) {
          _startTickOffset = targetTick;
          _stopwatch.reset();
          _emitPosition();
        } else {
          _startTickOffset = targetTick;
          _player.seekToFrame(
            ((targetTick / 60.0) * _currentConfig.sampleRate).round(),
          );
          _emitPosition();
        }
      }
    }
  }

  /// Sets the output volume from 0.0 to 1.0.
  void setVolume(double volume) {
    if (_isDisposed) return;
    _volume = volume.clamp(0.0, 1.0);
    _sink.setVolume(_volume);
  }

  /// Sets whether the sound should automatically loop when finished.
  void setLooping(bool loop) {
    _isLooping = loop;
    _player.looping = loop;
  }

  void _onStreamingFinished() {
    if (_isDisposed) return;
    _status = SoundPlayerStatus.stopped;
    _emitPosition();
    onFinished?.call();
  }

  void _startPositionTimer() {
    if (_isDisposed) return;
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
    if (_isDisposed || _status != SoundPlayerStatus.playing) return;

    final elapsedSeconds =
        (_startTickOffset / 60.0) + (_stopwatch.elapsedMicroseconds / 1000000.0);
    final totalSeconds = _totalTicks / 60.0;

    // Check if playback has reached or exceeded total duration (+ tail)
    final tailSeconds = (_currentConfig.enableReverb ||
            _currentConfig.mode == PcmPlaybackMode.enhanced)
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
    if (_isDisposed || _positionController.isClosed) return;

    if (_totalTicks <= 0) {
      _positionController.add(SoundPlaybackPosition(status: _status));
      return;
    }

    final totalSeconds = _totalTicks / 60.0;
    double currentSeconds;
    if (_mutedActive) {
      final elapsedSeconds =
          (_startTickOffset / 60.0) + (_stopwatch.elapsedMicroseconds / 1000000.0);
      currentSeconds = elapsedSeconds.clamp(0.0, totalSeconds);
    } else {
      var frames = _player.audibleFrames;
      if (_player.looping && _sourceTotalFrames > 0) {
        frames %= _sourceTotalFrames;
      }
      currentSeconds = (frames / _currentConfig.sampleRate).clamp(0.0, totalSeconds);
    }
    final currentTick = (currentSeconds * 60.0).round().clamp(0, _totalTicks);
    final progress =
        totalSeconds > 0 ? (currentSeconds / totalSeconds).clamp(0.0, 1.0) : 0.0;

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
    if (_isDisposed) return;
    _isDisposed = true;
    _stopPositionTimer();
    _stopwatch.reset();
    _mutedActive = false;
    // StreamingPcmPlayer disposes the sink only when it owns it
    // (ownsSink mirrors the former _autoDisposeSink rule).
    _player.dispose();
    _sink.stop();
    _status = SoundPlayerStatus.stopped;
    if (!_positionController.isClosed) {
      _positionController.close();
    }
  }
}
