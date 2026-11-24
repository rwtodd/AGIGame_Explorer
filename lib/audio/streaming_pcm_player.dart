import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';

/// Shared pull-based PCM transport: owns one [PcmSource], renders it into
/// a bounded lookahead of queued PCM in an [AudioOutputSink], and tracks
/// generated/audible frame positions.
///
/// Timing model: a refill timer fires every 25 ms while playing. Each tick
/// estimates how many frames the sink has consumed as
/// `max(sink.playedFrames delta since the last accounting reset,
/// stopwatch frames accumulated while playing)`. The sink delta is
/// authoritative for real hardware sinks, whose `playedFrames` advances
/// from native buffer-completion callbacks; the stopwatch term keeps
/// virtual sinks such as `NullAudioSink` progressing in real time even
/// though their `playedFrames` only moves when a test simulates frames.
/// Taking the maximum keeps both kinds of sink moving without a
/// sink-type special case.
class StreamingPcmPlayer {
  final AudioOutputSink _sink;
  final int blockFrames;
  final int lookaheadFrames;
  final bool ownsSink;

  PcmSource? _source;
  SoundPlayerStatus _status = SoundPlayerStatus.stopped;
  bool _isDisposed = false;

  /// Whether the source wraps seamlessly at end-of-stream.
  bool looping = false;

  /// When true, the source advances but a preallocated zero block is
  /// written instead of rendered samples.
  bool muted = false;

  /// Fired exactly once when playback completes (non-looping).
  void Function()? onFinished;

  /// Called with [audibleFrames] on each refill tick while playing.
  void Function(int audibleFrames)? onPositionFrames;

  Timer? _refillTimer;
  final Stopwatch _stopwatch = Stopwatch();

  // One reusable render block, allocated once in the constructor.
  // Sized for stereo worst case; renderInto frame counts are clamped
  // to `_block.length ~/ source.channels`.
  final Int16List _block;
  final Int16List _zeroBlock;

  int _seekBase = 0;
  int _submittedFrames = 0;

  // Consumed-frame estimate state (see class doc).
  int _sinkPlayedBase = 0;
  int _accumulatedPlayingFrames = 0;
  int _lastStopwatchUs = 0;

  int _underrunCount = 0;
  int? _finalAudibleFrames;

  StreamingPcmPlayer({
    required AudioOutputSink sink,
    this.blockFrames = 1024,
    this.lookaheadFrames = 8192,
    this.ownsSink = false,
    // ignore: prefer_initializing_formals
  })  : _sink = sink,
        _block = Int16List(blockFrames * 2),
        _zeroBlock = Int16List(blockFrames * 2) {
    if (blockFrames <= 0) {
      throw ArgumentError.value(blockFrames, 'blockFrames', 'must be positive');
    }
    if (lookaheadFrames <= 0) {
      throw ArgumentError.value(
          lookaheadFrames, 'lookaheadFrames', 'must be positive');
    }
  }

  /// Current playback status.
  SoundPlayerStatus get status => _status;

  /// Whether audio is actively playing.
  bool get isPlaying => _status == SoundPlayerStatus.playing;

  /// Whether playback is paused.
  bool get isPaused => _status == SoundPlayerStatus.paused;

  /// Whether the player has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of times the sink drained all queued audio while the source
  /// still had frames to render.
  int get underrunCount => _underrunCount;

  /// Audible frame position: [_seekBase] plus the consumed-frame estimate,
  /// clamped to `[_seekBase, _seekBase + submitted]`.
  int get audibleFrames {
    if (_status == SoundPlayerStatus.completed && _finalAudibleFrames != null) {
      return _finalAudibleFrames!;
    }
    if (_source == null) return 0;
    var v = _seekBase + _consumedEstimate();
    final hi = _seekBase + _submittedFrames;
    if (v > hi) v = hi;
    if (v < _seekBase) v = _seekBase;
    return v;
  }

  /// Stops any current source (flushing the sink), seeks [source] to
  /// [startFrame], (re)initializes the sink if it is uninitialized or
  /// running at a different sample rate, fills up to [lookaheadFrames],
  /// starts the sink, and starts the 25 ms refill timer.
  Future<void> playSource(PcmSource source, {int startFrame = 0}) async {
    if (_isDisposed) return;

    _refillTimer?.cancel();
    _refillTimer = null;
    _sink.flush();

    _source = source;
    _status = SoundPlayerStatus.stopped;
    final tf = source.totalFrames;
    _seekBase = tf != null ? startFrame.clamp(0, tf) : startFrame;
    _submittedFrames = 0;
    _accumulatedPlayingFrames = 0;
    _lastStopwatchUs = 0;
    _finalAudibleFrames = null;

    source.seekToFrame(_seekBase);

    if (_sink.status == AudioPlaybackStatus.uninitialized ||
        _sink.sampleRate != source.sampleRate) {
      await _sink.initialize(
        sampleRate: source.sampleRate,
        numChannels: source.channels,
        bufferSizeInFrames: 4096,
      );
    }

    _status = SoundPlayerStatus.playing;
    _stopwatch.reset();
    _stopwatch.start();
    _lastStopwatchUs = 0;

    _fill();
    _sink.play();
    _sinkPlayedBase = _sink.playedFrames;

    // A zero-length source completes immediately rather than spinning.
    if (!_maybeComplete()) {
      _refillTimer = Timer.periodic(
        const Duration(milliseconds: 25),
        (_) => _onRefillTick(),
      );
    }
  }

  /// Pauses playback: stops stopwatch accumulation, cancels the refill
  /// timer, and pauses the sink.
  void pause() {
    if (_isDisposed || _status != SoundPlayerStatus.playing) return;
    _accumulateStopwatch();
    _stopwatch.stop();
    _refillTimer?.cancel();
    _refillTimer = null;
    _sink.pause();
    _status = SoundPlayerStatus.paused;
  }

  /// Resumes playback after [pause].
  void resume() {
    if (_isDisposed || _status != SoundPlayerStatus.paused) return;
    _sink.play();
    _sinkPlayedBase = _sink.playedFrames;
    _status = SoundPlayerStatus.playing;
    _stopwatch.start();
    _lastStopwatchUs = _stopwatch.elapsedMicroseconds;
    _refillTimer = Timer.periodic(
      const Duration(milliseconds: 25),
      (_) => _onRefillTick(),
    );
  }

  /// Stops playback: cancels the timer, stops the sink, resets the
  /// source, and resets the position to 0.
  void stop() {
    if (_isDisposed) return;
    _refillTimer?.cancel();
    _refillTimer = null;
    _stopwatch.reset();
    _stopwatch.stop();
    _sink.stop();
    _source?.reset();
    _status = SoundPlayerStatus.stopped;
    _seekBase = 0;
    _submittedFrames = 0;
    _accumulatedPlayingFrames = 0;
    _lastStopwatchUs = 0;
    _finalAudibleFrames = null;
    _sinkPlayedBase = _sink.playedFrames;
  }

  /// Seeks to an absolute frame while playing or paused. Flushes the
  /// sink, seeks the source, resets position accounting, refills, and
  /// resumes the sink only if playback was active.
  void seekToFrame(int frame) {
    if (_isDisposed || _source == null) return;
    final wasPlaying = _status == SoundPlayerStatus.playing;
    final wasPaused = _status == SoundPlayerStatus.paused;
    if (!wasPlaying && !wasPaused) return;

    if (wasPlaying) {
      _accumulateStopwatch();
      _stopwatch.stop();
      _refillTimer?.cancel();
      _refillTimer = null;
    }

    _sink.flush();
    final tf = _source!.totalFrames;
    _seekBase = tf != null ? frame.clamp(0, tf) : frame;
    _source!.seekToFrame(_seekBase);
    _submittedFrames = 0;
    _accumulatedPlayingFrames = 0;
    _lastStopwatchUs = 0;
    _finalAudibleFrames = null;

    _fill();
    _sinkPlayedBase = _sink.playedFrames;

    if (wasPlaying) {
      _sink.play();
      _sinkPlayedBase = _sink.playedFrames;
      _status = SoundPlayerStatus.playing;
      _stopwatch.start();
      _lastStopwatchUs = _stopwatch.elapsedMicroseconds;
      if (!_maybeComplete()) {
        _refillTimer = Timer.periodic(
          const Duration(milliseconds: 25),
          (_) => _onRefillTick(),
        );
      }
    }
  }

  /// Stops playback, disposes the current source, and disposes the sink
  /// only when this player owns it ([ownsSink]).
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    stop();
    _source?.dispose();
    _source = null;
    if (ownsSink) {
      _sink.dispose();
    }
  }

  void _onRefillTick() {
    if (_isDisposed || _status != SoundPlayerStatus.playing) return;
    final source = _source;
    if (source == null) return;

    // Underrun: the sink consumed everything submitted while the source
    // still has frames left to render.
    if (!source.isFinished &&
        _submittedFrames > 0 &&
        (_sink.playedFrames - _sinkPlayedBase) >= _submittedFrames) {
      _underrunCount++;
    }

    _fill();
    if (_maybeComplete()) return;
    onPositionFrames?.call(audibleFrames);
  }

  /// Tops the sink up to [lookaheadFrames] queued frames from the source.
  void _fill() {
    final source = _source;
    if (source == null) return;
    final ch = source.channels;
    // Snapshot the consumed estimate once: re-evaluating it per block
    // would count rendering wall time as consumed playback.
    final baseConsumed = _consumedEstimate();

    while (true) {
      if (source.isFinished) {
        if (!looping) break;
        final tf = source.totalFrames;
        if (tf == null || tf <= 0) {
          // Nothing to loop over: complete instead of spinning.
          _finalize();
          return;
        }
        source.reset();
      }
      if (_submittedFrames - baseConsumed >= lookaheadFrames) break;

      var n = blockFrames;
      final maxFrames = _block.length ~/ ch;
      if (n > maxFrames) n = maxFrames;

      final written = source.renderInto(_block, n);
      if (written <= 0) {
        // Defensive: a source that stops producing without reporting
        // finished would otherwise spin here.
        if (source.isFinished) continue;
        break;
      }
      // Advance the source even when muted, but write a zero block.
      if (muted) {
        _sink.writePcm(Int16List.sublistView(_zeroBlock, 0, written * ch));
      } else {
        _sink.writePcm(Int16List.sublistView(_block, 0, written * ch));
      }
      _submittedFrames += written;
    }
  }

  /// Returns true if [finalize] ran.
  bool _maybeComplete() {
    final source = _source;
    if (source == null || looping) return false;
    if (!source.isFinished) return false;
    if (_consumedEstimate() < _submittedFrames) return false;
    _finalize();
    return true;
  }

  void _finalize() {
    if (_status == SoundPlayerStatus.completed) return;
    _finalAudibleFrames = _seekBase + _submittedFrames;
    _refillTimer?.cancel();
    _refillTimer = null;
    _stopwatch.stop();
    _sink.stop();
    _status = SoundPlayerStatus.completed;
    onFinished?.call();
  }

  void _accumulateStopwatch() {
    if (_status != SoundPlayerStatus.playing || !_stopwatch.isRunning) return;
    final nowUs = _stopwatch.elapsedMicroseconds;
    if (nowUs <= _lastStopwatchUs) return;
    final rate = _source?.sampleRate ?? _sink.sampleRate;
    _accumulatedPlayingFrames += (nowUs - _lastStopwatchUs) * rate ~/ 1000000;
    _lastStopwatchUs = nowUs;
  }

  int _consumedEstimate() {
    _accumulateStopwatch();
    final sinkDelta = _sink.playedFrames - _sinkPlayedBase;
    final v = sinkDelta > _accumulatedPlayingFrames
        ? sinkDelta
        : _accumulatedPlayingFrames;
    return v < 0 ? 0 : v;
  }
}
