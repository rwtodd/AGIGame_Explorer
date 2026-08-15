import 'dart:async';
import 'dart:typed_data';

/// Playback status of an [AudioOutputSink].
enum AudioPlaybackStatus {
  /// Audio sink has not been initialized or is closed.
  uninitialized,

  /// Audio sink is stopped and buffers are empty.
  stopped,

  /// Audio sink is actively playing buffered audio.
  playing,

  /// Audio sink is paused.
  paused,
}

/// Abstract audio output sink representing a hardware or virtual audio stream.
///
/// Designed to receive 16-bit interleaved linear PCM audio chunks and output them
/// with low latency to the system's audio device.
abstract class AudioOutputSink {
  /// Current playback status.
  AudioPlaybackStatus get status;

  /// Output sample rate in Hz (e.g. 44100).
  int get sampleRate;

  /// Number of interleaved audio channels (1 = Mono, 2 = Stereo).
  int get numChannels;

  /// Approximate total number of audio frames played since playback started.
  int get playedFrames;

  /// Stream of status change events.
  Stream<AudioPlaybackStatus> get statusStream;

  /// Initializes the audio output device with the given [sampleRate], [numChannels],
  /// and target [bufferSizeInFrames] (latency control).
  Future<void> initialize({
    int sampleRate = 44100,
    int numChannels = 2,
    int bufferSizeInFrames = 2048,
  });

  /// Writes interleaved 16-bit signed PCM [samples] to the audio buffer.
  ///
  /// For stereo audio, samples must alternate [left0, right0, left1, right1, ...].
  void writePcm(Int16List samples);

  /// Starts or resumes audio playback.
  void play();

  /// Pauses audio playback without clearing queued buffers.
  void pause();

  /// Stops audio playback and flushes any pending audio buffers.
  void stop();

  /// Clears any pending audio buffers.
  void flush();

  /// Sets the master volume level from 0.0 (muted) to 1.0 (full volume).
  void setVolume(double volume);

  /// Closes the audio sink and releases native resources.
  void dispose();
}

/// A no-op audio output sink for testing and fallback environments.
class NullAudioSink implements AudioOutputSink {
  @override
  AudioPlaybackStatus status = AudioPlaybackStatus.uninitialized;

  @override
  int sampleRate = 44100;

  @override
  int numChannels = 2;

  int _playedFrames = 0;

  @override
  int get playedFrames => _playedFrames;

  final StreamController<AudioPlaybackStatus> _statusController =
      StreamController<AudioPlaybackStatus>.broadcast();

  @override
  Stream<AudioPlaybackStatus> get statusStream => _statusController.stream;

  final List<Int16List> queuedBuffers = [];

  @override
  Future<void> initialize({
    int sampleRate = 44100,
    int numChannels = 2,
    int bufferSizeInFrames = 2048,
  }) async {
    this.sampleRate = sampleRate;
    this.numChannels = numChannels;
    status = AudioPlaybackStatus.stopped;
    _statusController.add(status);
  }

  @override
  void writePcm(Int16List samples) {
    queuedBuffers.add(samples);
  }

  @override
  void play() {
    status = AudioPlaybackStatus.playing;
    _statusController.add(status);
  }

  @override
  void pause() {
    status = AudioPlaybackStatus.paused;
    _statusController.add(status);
  }

  @override
  void stop() {
    status = AudioPlaybackStatus.stopped;
    _playedFrames = 0;
    queuedBuffers.clear();
    _statusController.add(status);
  }

  @override
  void flush() {
    queuedBuffers.clear();
  }

  @override
  void setVolume(double volume) {}

  /// Simulates advancing playback by [frames] in test environments.
  void simulateFramesPlayed(int frames) {
    _playedFrames += frames;
  }

  @override
  void dispose() {
    status = AudioPlaybackStatus.uninitialized;
    _statusController.close();
  }
}
