import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';

// Native struct bindings for Windows Multimedia (winmm.dll)
final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

final class _WaveHdr extends Struct {
  external Pointer<Int8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WaveHdr> lpNext;
  @IntPtr()
  external int reserved;
}

// WinMM Constants
const int _kWaveFormatPcm = 1;
const int _kWaveMapper = 0xFFFFFFFF; // (UINT)-1
const int _kCallbackFunction = 0x00030000;
const int _kWomDone = 0x3BD;
const int _kMmSysErrNoError = 0;
const int _kWhdrPrepared = 0x00000002;

typedef _WaveOutProcNative = Void Function(
  Pointer<Void> hwo,
  Uint32 uMsg,
  IntPtr dwInstance,
  IntPtr dwParam1,
  IntPtr dwParam2,
);

typedef _WaveOutOpenDart = int Function(
  Pointer<Pointer<Void>> phwo,
  int uDeviceID,
  Pointer<_WaveFormatEx> pwfx,
  Pointer<NativeFunction<_WaveOutProcNative>> dwCallback,
  Pointer<Void> dwInstance,
  int fdwOpen,
);

typedef _WaveOutPrepareHeaderDart = int Function(
  Pointer<Void> hwo,
  Pointer<_WaveHdr> pwh,
  int cbwh,
);

typedef _WaveOutUnprepareHeaderDart = int Function(
  Pointer<Void> hwo,
  Pointer<_WaveHdr> pwh,
  int cbwh,
);

typedef _WaveOutWriteDart = int Function(
  Pointer<Void> hwo,
  Pointer<_WaveHdr> pwh,
  int cbwh,
);

typedef _WaveOutPauseDart = int Function(Pointer<Void> hwo);
typedef _WaveOutRestartDart = int Function(Pointer<Void> hwo);
typedef _WaveOutResetDart = int Function(Pointer<Void> hwo);
typedef _WaveOutCloseDart = int Function(Pointer<Void> hwo);
typedef _WaveOutSetVolumeDart = int Function(Pointer<Void> hwo, int dwVolume);

/// High performance power-of-two circular ring buffer for 16-bit PCM samples.
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

/// Native Windows implementation of [AudioOutputSink] using Windows Multimedia (`winmm.dll`) `waveOut`.
class WindowsWaveOutSink implements AudioOutputSink {
  static DynamicLibrary? _winmmLib;

  static DynamicLibrary get _winmm {
    if (_winmmLib != null) return _winmmLib!;
    if (Platform.isWindows) {
      _winmmLib = DynamicLibrary.open('winmm.dll');
    } else {
      _winmmLib = DynamicLibrary.process();
    }
    return _winmmLib!;
  }

  // FFI Functions
  late final _WaveOutOpenDart _open;
  late final _WaveOutPrepareHeaderDart _prepareHeader;
  late final _WaveOutUnprepareHeaderDart _unprepareHeader;
  late final _WaveOutWriteDart _write;
  late final _WaveOutPauseDart _pause;
  late final _WaveOutRestartDart _restart;
  late final _WaveOutResetDart _reset;
  late final _WaveOutCloseDart _close;
  late final _WaveOutSetVolumeDart _setVolume;

  Pointer<Void>? _hWaveOut;
  NativeCallable<_WaveOutProcNative>? _nativeCallback;
  final List<Pointer<_WaveHdr>> _headers = [];
  final Map<int, int> _headerEpoch = {};

  static const int _numBuffers = 4;
  int _bufferByteSize = 0;
  int _sampleRate = 44100;
  int _numChannels = 2;
  int _bytesPerFrame = 4;
  double _volume = 1.0;
  int _currentEpoch = 0;

  AudioPlaybackStatus _status = AudioPlaybackStatus.uninitialized;
  final StreamController<AudioPlaybackStatus> _statusController =
      StreamController<AudioPlaybackStatus>.broadcast();

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

  WindowsWaveOutSink() {
    _initFfiBindings();
  }

  void _initFfiBindings() {
    final lib = _winmm;

    _open = lib
        .lookup<NativeFunction<Int32 Function(
          Pointer<Pointer<Void>>,
          Uint32,
          Pointer<_WaveFormatEx>,
          Pointer<NativeFunction<_WaveOutProcNative>>,
          Pointer<Void>,
          Uint32,
        )>>('waveOutOpen')
        .asFunction<_WaveOutOpenDart>();

    _prepareHeader = lib
        .lookup<NativeFunction<Int32 Function(
          Pointer<Void>,
          Pointer<_WaveHdr>,
          Uint32,
        )>>('waveOutPrepareHeader')
        .asFunction<_WaveOutPrepareHeaderDart>();

    _unprepareHeader = lib
        .lookup<NativeFunction<Int32 Function(
          Pointer<Void>,
          Pointer<_WaveHdr>,
          Uint32,
        )>>('waveOutUnprepareHeader')
        .asFunction<_WaveOutUnprepareHeaderDart>();

    _write = lib
        .lookup<NativeFunction<Int32 Function(
          Pointer<Void>,
          Pointer<_WaveHdr>,
          Uint32,
        )>>('waveOutWrite')
        .asFunction<_WaveOutWriteDart>();

    _pause = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutPause')
        .asFunction<_WaveOutPauseDart>();

    _restart = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutRestart')
        .asFunction<_WaveOutRestartDart>();

    _reset = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutReset')
        .asFunction<_WaveOutResetDart>();

    _close = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('waveOutClose')
        .asFunction<_WaveOutCloseDart>();

    _setVolume = lib
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>('waveOutSetVolume')
        .asFunction<_WaveOutSetVolumeDart>();
  }

  @override
  Future<void> initialize({
    int sampleRate = 44100,
    int numChannels = 2,
    int bufferSizeInFrames = 2048,
  }) async {
    if (_hWaveOut != null) {
      dispose();
    }

    _sampleRate = sampleRate;
    _numChannels = numChannels;
    _bytesPerFrame = _numChannels * 2; // 16-bit PCM = 2 bytes per sample
    _bufferByteSize = bufferSizeInFrames * _bytesPerFrame;

    final format = calloc<_WaveFormatEx>();
    format.ref.wFormatTag = _kWaveFormatPcm;
    format.ref.nChannels = _numChannels;
    format.ref.nSamplesPerSec = _sampleRate;
    format.ref.nAvgBytesPerSec = _sampleRate * _bytesPerFrame;
    format.ref.nBlockAlign = _bytesPerFrame;
    format.ref.wBitsPerSample = 16;
    format.ref.cbSize = 0;

    _nativeCallback = NativeCallable<_WaveOutProcNative>.listener(_onWaveOutCallback);

    final phwo = calloc<Pointer<Void>>();
    final status = _open(
      phwo,
      _kWaveMapper,
      format,
      _nativeCallback!.nativeFunction,
      nullptr,
      _kCallbackFunction,
    );

    calloc.free(format);

    if (status != _kMmSysErrNoError || phwo.value == nullptr) {
      calloc.free(phwo);
      throw Exception('Failed to open Windows waveOut device (status: $status)');
    }

    _hWaveOut = phwo.value;
    calloc.free(phwo);

    // Allocate wave headers
    for (var i = 0; i < _numBuffers; i++) {
      final hdr = calloc<_WaveHdr>();
      hdr.ref.lpData = calloc<Int8>(_bufferByteSize);
      hdr.ref.dwBufferLength = _bufferByteSize;
      hdr.ref.dwBytesRecorded = 0;
      hdr.ref.dwUser = i;
      hdr.ref.dwFlags = 0;
      hdr.ref.dwLoops = 0;
      hdr.ref.lpNext = nullptr;
      hdr.ref.reserved = 0;

      _headers.add(hdr);
    }

    setVolume(_volume);
    _status = AudioPlaybackStatus.stopped;
    _statusController.add(_status);
  }

  void _onWaveOutCallback(
    Pointer<Void> hwo,
    int uMsg,
    int dwInstance,
    int dwParam1,
    int dwParam2,
  ) {
    if (uMsg != _kWomDone || _hWaveOut == null || _status != AudioPlaybackStatus.playing) {
      return;
    }

    final hdr = Pointer<_WaveHdr>.fromAddress(dwParam1);
    final epoch = _headerEpoch[hdr.address];
    if (epoch != _currentEpoch) {
      return;
    }

    final framesPlayedInBuffer = hdr.ref.dwBufferLength ~/ _bytesPerFrame;
    _playedFrames += framesPlayedInBuffer;

    if (_status == AudioPlaybackStatus.playing) {
      _fillAndWriteBuffer(hdr);
    }
  }

  void _fillAndWriteBuffer(Pointer<_WaveHdr> hdr) {
    if (_hWaveOut == null) return;

    final samplesNeeded = _bufferByteSize ~/ 2;
    final int16Data = hdr.ref.lpData.cast<Int16>();

    final samplesRead = _ringBuffer.read(int16Data, samplesNeeded);

    // Pad remaining buffer with silence if less than full buffer
    for (var i = samplesRead; i < samplesNeeded; i++) {
      int16Data[i] = 0;
    }

    if ((hdr.ref.dwFlags & _kWhdrPrepared) != 0) {
      _unprepareHeader(_hWaveOut!, hdr, sizeOf<_WaveHdr>());
    }
    hdr.ref.dwBufferLength = _bufferByteSize;
    hdr.ref.dwFlags = 0;
    _prepareHeader(_hWaveOut!, hdr, sizeOf<_WaveHdr>());

    _headerEpoch[hdr.address] = _currentEpoch;
    _write(_hWaveOut!, hdr, sizeOf<_WaveHdr>());
  }

  @override
  void writePcm(Int16List samples) {
    _ringBuffer.write(samples);
  }

  @override
  void play() {
    if (_hWaveOut == null) return;
    if (_status == AudioPlaybackStatus.playing) return;

    if (_status == AudioPlaybackStatus.paused) {
      _restart(_hWaveOut!);
      _status = AudioPlaybackStatus.playing;
      _statusController.add(_status);
      return;
    }

    _currentEpoch++;
    _playedFrames = 0;

    for (final hdr in _headers) {
      _fillAndWriteBuffer(hdr);
    }

    _status = AudioPlaybackStatus.playing;
    _statusController.add(_status);
  }

  @override
  void pause() {
    if (_hWaveOut == null) return;
    if (_status != AudioPlaybackStatus.playing) return;

    _pause(_hWaveOut!);
    _status = AudioPlaybackStatus.paused;
    _statusController.add(_status);
  }

  @override
  void stop() {
    if (_hWaveOut == null) return;

    _currentEpoch++;
    _status = AudioPlaybackStatus.stopped;
    _reset(_hWaveOut!);
    _ringBuffer.clear();
    _playedFrames = 0;

    _statusController.add(_status);
  }

  @override
  void flush() {
    if (_hWaveOut == null) return;
    _currentEpoch++;
    _ringBuffer.clear();
    _reset(_hWaveOut!);
  }

  @override
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    if (_hWaveOut != null) {
      final vol16 = (_volume * 0xFFFF).round().clamp(0, 0xFFFF);
      final dwVolume = (vol16 << 16) | vol16;
      _setVolume(_hWaveOut!, dwVolume);
    }
  }

  @override
  void dispose() {
    if (_hWaveOut != null) {
      _currentEpoch++;
      _reset(_hWaveOut!);
      for (final hdr in _headers) {
        if ((hdr.ref.dwFlags & _kWhdrPrepared) != 0) {
          _unprepareHeader(_hWaveOut!, hdr, sizeOf<_WaveHdr>());
        }
        calloc.free(hdr.ref.lpData);
        calloc.free(hdr);
      }
      _headers.clear();
      _headerEpoch.clear();
      _close(_hWaveOut!);
      _hWaveOut = null;
    }
    _nativeCallback?.close();
    _nativeCallback = null;
    _ringBuffer.clear();

    _status = AudioPlaybackStatus.uninitialized;
    _statusController.add(_status);
    _statusController.close();
  }
}
