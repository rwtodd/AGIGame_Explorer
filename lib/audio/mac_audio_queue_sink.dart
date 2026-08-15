import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';

// Native struct bindings for macOS AudioToolbox
final class _AudioStreamBasicDescription extends Struct {
  @Double()
  external double mSampleRate;
  @Uint32()
  external int mFormatID;
  @Uint32()
  external int mFormatFlags;
  @Uint32()
  external int mBytesPerPacket;
  @Uint32()
  external int mFramesPerPacket;
  @Uint32()
  external int mBytesPerFrame;
  @Uint32()
  external int mChannelsPerFrame;
  @Uint32()
  external int mBitsPerChannel;
  @Uint32()
  external int mReserved;
}

final class _AudioQueueBuffer extends Struct {
  @Uint32()
  external int mAudioDataBytesCapacity;
  external Pointer<Int8> mAudioData;
  @Uint32()
  external int mAudioDataByteSize;
  external Pointer<Void> mUserData;
  @Uint32()
  external int mPacketDescriptionCapacity;
  external Pointer<Void> mPacketDescriptions;
  @Uint32()
  external int mPacketDescriptionCount;
}

// AudioToolbox Constants
const int _kAudioFormatLinearPCM = 0x6C70636D; // 'lpcm'
const int _kAudioFormatFlagIsSignedInteger = 1 << 2;
const int _kAudioFormatFlagIsPacked = 1 << 3;
const int _kAudioQueueParamVolume = 1;

typedef _AudioQueueOutputCallbackNative = Void Function(
    Pointer<Void> inUserData, Pointer<Void> inAQ, Pointer<_AudioQueueBuffer> inBuffer);

typedef _AudioQueueNewOutputDart = int Function(
    Pointer<_AudioStreamBasicDescription> inFormat,
    Pointer<NativeFunction<_AudioQueueOutputCallbackNative>> inCallbackProc,
    Pointer<Void> inUserData,
    Pointer<Void> inCallbackRunLoop,
    Pointer<Void> inCallbackRunLoopMode,
    int inFlags,
    Pointer<Pointer<Void>> outAQ);

typedef _AudioQueueAllocateBufferDart = int Function(
    Pointer<Void> inAQ, int inBufferByteSize, Pointer<Pointer<_AudioQueueBuffer>> outBuffer);

typedef _AudioQueueEnqueueBufferDart = int Function(
    Pointer<Void> inAQ,
    Pointer<_AudioQueueBuffer> inBuffer,
    int inNumPacketDescs,
    Pointer<Void> inPacketDescs);

typedef _AudioQueueStartDart = int Function(Pointer<Void> inAQ, Pointer<Void> inStartTime);
typedef _AudioQueueStopDart = int Function(Pointer<Void> inAQ, bool inImmediate);
typedef _AudioQueuePauseDart = int Function(Pointer<Void> inAQ);
typedef _AudioQueueResetDart = int Function(Pointer<Void> inAQ);
typedef _AudioQueueFlushDart = int Function(Pointer<Void> inAQ);
typedef _AudioQueueDisposeDart = int Function(Pointer<Void> inAQ, bool inImmediate);
typedef _AudioQueueSetParameterDart = int Function(
    Pointer<Void> inAQ, int inParamID, double inValue);

/// High performance power-of-two circular ring buffer for 16-bit PCM samples.
///
/// Avoids all heap allocations, array copies, and list resizing during playback.
class _AudioRingBuffer {
  Int16List _buffer;
  int _capacity;
  int _mask;
  int _readIndex = 0;
  int _writeIndex = 0;

  _AudioRingBuffer({int initialCapacityPowerOfTwo = 19}) // 2^19 = 524,288 samples (~6s stereo)
      : _capacity = 1 << initialCapacityPowerOfTwo,
        _mask = (1 << initialCapacityPowerOfTwo) - 1,
        _buffer = Int16List(1 << initialCapacityPowerOfTwo);

  int get availableToRead => _writeIndex - _readIndex;
  int get availableToWrite => _capacity - availableToRead;

  void write(Int16List samples) {
    if (samples.isEmpty) return;

    // Ensure capacity if needed
    if (samples.length > availableToWrite) {
      _grow(samples.length);
    }

    final len = samples.length;
    for (int i = 0; i < len; i++) {
      _buffer[(_writeIndex + i) & _mask] = samples[i];
    }
    _writeIndex += len;
  }

  void _grow(int neededExtra) {
    var newCap = _capacity;
    while (newCap - availableToRead < neededExtra) {
      newCap <<= 1;
    }
    final newBuffer = Int16List(newCap);
    final count = availableToRead;
    for (int i = 0; i < count; i++) {
      newBuffer[i] = _buffer[(_readIndex + i) & _mask];
    }
    _buffer = newBuffer;
    _capacity = newCap;
    _mask = newCap - 1;
    _readIndex = 0;
    _writeIndex = count;
  }

  int read(Pointer<Int16> dest, int maxSamples) {
    final toRead = min(maxSamples, availableToRead);
    if (toRead <= 0) return 0;

    for (int i = 0; i < toRead; i++) {
      dest[i] = _buffer[(_readIndex + i) & _mask];
    }
    _readIndex += toRead;
    return toRead;
  }

  void clear() {
    _readIndex = 0;
    _writeIndex = 0;
  }
}

/// Native macOS CoreAudio implementation of [AudioOutputSink] using AudioToolbox AudioQueue.
class MacAudioQueueSink implements AudioOutputSink {
  static DynamicLibrary? _audioToolboxLib;

  static DynamicLibrary get _audioToolbox {
    if (_audioToolboxLib != null) return _audioToolboxLib!;
    if (Platform.isMacOS) {
      _audioToolboxLib =
          DynamicLibrary.open('/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox');
    } else {
      _audioToolboxLib = DynamicLibrary.process();
    }
    return _audioToolboxLib!;
  }

  // FFI Functions
  late final _AudioQueueNewOutputDart _newOutput;
  late final _AudioQueueAllocateBufferDart _allocateBuffer;
  late final _AudioQueueEnqueueBufferDart _enqueueBuffer;
  late final _AudioQueueStartDart _startAQ;
  late final _AudioQueueStopDart _stopAQ;
  late final _AudioQueuePauseDart _pauseAQ;
  late final _AudioQueueResetDart _resetAQ;
  late final _AudioQueueFlushDart _flushAQ;
  late final _AudioQueueDisposeDart _disposeAQ;
  late final _AudioQueueSetParameterDart _setParameter;

  Pointer<Void>? _audioQueue;
  NativeCallable<_AudioQueueOutputCallbackNative>? _nativeCallback;
  final List<Pointer<_AudioQueueBuffer>> _buffers = [];
  final Map<int, int> _bufferEpoch = {};

  static const int _numBuffers = 3;
  int _bufferByteSize = 0;
  int _sampleRate = 44100;
  int _numChannels = 2;
  int _bytesPerFrame = 4;
  double _volume = 1.0;
  int _currentEpoch = 0;

  AudioPlaybackStatus _status = AudioPlaybackStatus.uninitialized;
  final StreamController<AudioPlaybackStatus> _statusController =
      StreamController<AudioPlaybackStatus>.broadcast();

  // High performance O(1) circular sample ring buffer
  final _AudioRingBuffer _ringBuffer = _AudioRingBuffer();
  int _playedFrames = 0;

  @override
  AudioPlaybackStatus get status => _status;

  @override
  int get sampleRate => _sampleRate;

  @override
  int get numChannels => _numChannels;

  @override
  int get playedFrames => _playedFrames;

  @override
  Stream<AudioPlaybackStatus> get statusStream => _statusController.stream;

  MacAudioQueueSink() {
    _initFfiBindings();
  }

  void _initFfiBindings() {
    final lib = _audioToolbox;
    _newOutput = lib
        .lookup<NativeFunction<Int32 Function(
          Pointer<_AudioStreamBasicDescription>,
          Pointer<NativeFunction<_AudioQueueOutputCallbackNative>>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Uint32,
          Pointer<Pointer<Void>>)>>('AudioQueueNewOutput')
        .asFunction<_AudioQueueNewOutputDart>();

    _allocateBuffer = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<_AudioQueueBuffer>>)>>('AudioQueueAllocateBuffer')
        .asFunction<_AudioQueueAllocateBufferDart>();

    _enqueueBuffer = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<_AudioQueueBuffer>, Uint32, Pointer<Void>)>>('AudioQueueEnqueueBuffer')
        .asFunction<_AudioQueueEnqueueBufferDart>();

    _startAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>>('AudioQueueStart')
        .asFunction<_AudioQueueStartDart>();

    _stopAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Bool)>>('AudioQueueStop')
        .asFunction<_AudioQueueStopDart>();

    _pauseAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('AudioQueuePause')
        .asFunction<_AudioQueuePauseDart>();

    _resetAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('AudioQueueReset')
        .asFunction<_AudioQueueResetDart>();

    _flushAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('AudioQueueFlush')
        .asFunction<_AudioQueueFlushDart>();

    _disposeAQ = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Bool)>>('AudioQueueDispose')
        .asFunction<_AudioQueueDisposeDart>();

    _setParameter = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32, Float)>>('AudioQueueSetParameter')
        .asFunction<_AudioQueueSetParameterDart>();
  }

  @override
  Future<void> initialize({
    int sampleRate = 44100,
    int numChannels = 2,
    int bufferSizeInFrames = 2048,
  }) async {
    if (_audioQueue != null) {
      dispose();
    }

    _sampleRate = sampleRate;
    _numChannels = numChannels;
    _bytesPerFrame = _numChannels * 2; // 16-bit PCM = 2 bytes per sample
    _bufferByteSize = bufferSizeInFrames * _bytesPerFrame;

    final format = calloc<_AudioStreamBasicDescription>();
    format.ref.mSampleRate = _sampleRate.toDouble();
    format.ref.mFormatID = _kAudioFormatLinearPCM;
    format.ref.mFormatFlags = _kAudioFormatFlagIsSignedInteger | _kAudioFormatFlagIsPacked;
    format.ref.mBytesPerPacket = _bytesPerFrame;
    format.ref.mFramesPerPacket = 1;
    format.ref.mBytesPerFrame = _bytesPerFrame;
    format.ref.mChannelsPerFrame = _numChannels;
    format.ref.mBitsPerChannel = 16;
    format.ref.mReserved = 0;

    _nativeCallback = NativeCallable<_AudioQueueOutputCallbackNative>.listener(_onBufferCallback);

    final aqPtr = calloc<Pointer<Void>>();
    final status = _newOutput(
      format,
      _nativeCallback!.nativeFunction,
      nullptr,
      nullptr,
      nullptr,
      0,
      aqPtr,
    );

    calloc.free(format);

    if (status != 0 || aqPtr.value == nullptr) {
      calloc.free(aqPtr);
      throw Exception('Failed to create macOS AudioQueue (status: $status)');
    }

    _audioQueue = aqPtr.value;
    calloc.free(aqPtr);

    // Allocate audio queue buffers
    final bufPtr = calloc<Pointer<_AudioQueueBuffer>>();
    for (var i = 0; i < _numBuffers; i++) {
      _allocateBuffer(_audioQueue!, _bufferByteSize, bufPtr);
      _buffers.add(bufPtr.value);
    }
    calloc.free(bufPtr);

    setVolume(_volume);
    _status = AudioPlaybackStatus.stopped;
    _statusController.add(_status);
  }

  void _onBufferCallback(
    Pointer<Void> inUserData,
    Pointer<Void> inAQ,
    Pointer<_AudioQueueBuffer> inBuffer,
  ) {
    if (_status != AudioPlaybackStatus.playing || _audioQueue == null) return;

    final epoch = _bufferEpoch[inBuffer.address];
    // Drop / ignore any stray completion from an earlier playback session or stop/reset
    if (epoch != _currentEpoch) {
      return;
    }

    final framesPlayedInBuffer = inBuffer.ref.mAudioDataByteSize ~/ _bytesPerFrame;
    _playedFrames += framesPlayedInBuffer;

    _fillAndEnqueueBuffer(inBuffer);
  }

  void _fillAndEnqueueBuffer(Pointer<_AudioQueueBuffer> buffer) {
    if (_audioQueue == null) return;

    final samplesNeeded = _bufferByteSize ~/ 2;
    final int16Data = buffer.ref.mAudioData.cast<Int16>();

    final samplesRead = _ringBuffer.read(int16Data, samplesNeeded);

    // Pad remaining buffer with silence if less than full buffer
    for (var i = samplesRead; i < samplesNeeded; i++) {
      int16Data[i] = 0;
    }
    buffer.ref.mAudioDataByteSize = _bufferByteSize;

    _bufferEpoch[buffer.address] = _currentEpoch;
    _enqueueBuffer(_audioQueue!, buffer, 0, nullptr);
  }

  @override
  void writePcm(Int16List samples) {
    _ringBuffer.write(samples);
  }

  @override
  void play() {
    if (_audioQueue == null) return;
    if (_status == AudioPlaybackStatus.playing) return;

    _currentEpoch++;
    _playedFrames = 0;

    // Sequential priming of all buffers for this new playback epoch
    for (final buf in _buffers) {
      _fillAndEnqueueBuffer(buf);
    }

    _startAQ(_audioQueue!, nullptr);
    _status = AudioPlaybackStatus.playing;
    _statusController.add(_status);
  }

  @override
  void pause() {
    if (_audioQueue == null) return;
    if (_status != AudioPlaybackStatus.playing) return;

    _pauseAQ(_audioQueue!);
    _status = AudioPlaybackStatus.paused;
    _statusController.add(_status);
  }

  @override
  void stop() {
    if (_audioQueue == null) return;

    _currentEpoch++;
    _status = AudioPlaybackStatus.stopped;
    _stopAQ(_audioQueue!, true);
    _resetAQ(_audioQueue!);
    _ringBuffer.clear();
    _playedFrames = 0;

    _statusController.add(_status);
  }

  @override
  void flush() {
    if (_audioQueue == null) return;
    _currentEpoch++;
    _ringBuffer.clear();
    _flushAQ(_audioQueue!);
  }

  @override
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    if (_audioQueue != null) {
      _setParameter(_audioQueue!, _kAudioQueueParamVolume, _volume);
    }
  }

  @override
  void dispose() {
    if (_audioQueue != null) {
      _currentEpoch++;
      _stopAQ(_audioQueue!, true);
      _disposeAQ(_audioQueue!, true);
      _audioQueue = null;
    }
    _buffers.clear();
    _bufferEpoch.clear();
    _nativeCallback?.close();
    _nativeCallback = null;
    _ringBuffer.clear();

    _status = AudioPlaybackStatus.uninitialized;
    _statusController.add(_status);
    _statusController.close();
  }
}
