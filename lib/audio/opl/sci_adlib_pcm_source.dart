// Stage 6a streaming SCI AdLib source: SCI track -> Sierra driver -> OPL2 chip -> resampler -> pull-based PCM.
//
// Single pass over the track; loop points are ignored (looping belongs
// to the player/kernel via reset/replay).
//
// Native timeline is sample-consistent with the offline renderer
// (sciAdLibRenderTrack): events dispatched at native frame
// round(tick*49716/60) computed from the absolute tick, AdLib mask
// filter applied, channel 15 skipped, channel -1 forwarded, allNotesOff
// at totalTicks frame, then tail. At outputSampleRate == 49716 the
// resampler is a true identity and output equals the offline renderer
// sample-for-sample (duplicated to stereo).
//
// Channels = 2. Default: the OPL2 chip is mono; the mono sample is
// duplicated to L/R (authentic single-OPL2). With [stereoDualOpl2] the
// source instead runs two chips via [DualOpl2ChipRegisterSink]
// (ScummVM-style dual-OPL2 enhancement using source pan CCs, not OPL3
// native panning) and interleaves true L/R samples.
//
// Resampler: measured windowed-sinc (lib/audio/pcm_resampler.dart) from
// 49716 to outputSampleRate. The measured choice vs linear,
// passband/spur/CPU numbers, and the ship gate live in
// tool/measure_resampler.dart output. Identity (49716) is a true
// bypass and equals the offline renderer sample-for-sample. Output is
// deterministic and independent of renderInto block sizes. No
// steady-state allocation (preallocated buffers; growing only at
// construction/reset).

import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/pcm_resampler.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

int _frameForTick(int tick) => (tick * kOpl2SampleRate / 60).round();

int _frameForTickAtRate(int tick, int rate) => (tick * rate / 60).round();

const int _kNativeBlockFrames = 1024;

/// Buffered filtered event with precomputed native dispatch frame.
final class _FilteredEvent {
  final SciMidiEvent event;
  final int frame;
  const _FilteredEvent(this.event, this.frame);
}

class SciAdLibPcmSource extends PcmSource {
  final SciMidiTrack track;
  final SciAdlibBank bank;
  final int outputSampleRate;
  final int tailTicks;
  final SciAdlibProfile? profile;

  /// When true, use dual-OPL2 stereo (two chips, pan-scaled velocities).
  /// Default false preserves single-chip duplicated-mono behavior.
  final bool stereoDualOpl2;
  int _masterVolume;

  /// Current session debug overrides (Stage 7 inspector only). Kept here
  /// so [reset]/[seekToFrame] can re-apply them after the driver is
  /// rebuilt. Never persisted.
  late SciAdLibDebugOverrides _debugOverrides;

  /// Write-log capture flag, carried across chip rebuilds in [reset].
  bool _writeLogEnabled = false;

  late final SciAdlibProfile _profile;
  late final Set<int> _mask;
  late final List<_FilteredEvent> _filtered;
  late final int _endTick;
  late final int _endFrameNative;
  late final int _totalNativeFrames;
  late final int _totalFrames;

  late Opl2Chip _chip;
  Opl2Chip? _chipRight;
  late SciAdLibDriver _driver;

  int _position = 0;
  int _eventIdx = 0;
  bool _didAllNotesOff = false;
  int _generated = 0;
  int _bufStart = 0;
  int _bufLen = 0;
  int _prevLast = 0;
  bool _prevValid = false;
  int _prevLastRight = 0;
  bool _prevValidRight = false;

  final Int16List _nativeBuf = Int16List(_kNativeBlockFrames);
  final Int16List _nativeBufRight = Int16List(_kNativeBlockFrames);
  Int16List _discard = Int16List(0);

  /// Measured sinc resampler; null (identity bypass) iff
  /// outputSampleRate == kOpl2SampleRate.
  late final PcmResampler? _resampler;

  /// Kernel half-width W in native samples; 0 when identity.
  late final int _halfWidth;

  /// Last [_halfWidth] native samples before [_bufStart], per channel.
  /// Proof: evaluation reads only [i0-halfWidth+1, i0+halfWidth] with
  /// i0 = floor(pos) and pos advance ~1.1/output; after
  /// _ensureAvail(i0+halfWidth) the current block starts at
  /// _bufStart > i0+halfWidth-1024. Any index below _bufStart is
  /// therefore >= _bufStart-(1024-halfWidth) ... bounded: worst back
  /// reach is i0-halfWidth+1 >= _bufStart-halfWidth+1 (since
  /// _bufStart <= i0+halfWidth and block alignment). In all cases the
  /// needed span is within [ _bufStart-halfWidth, _generated ); halfWidth
  /// (<=38) <= 1024 block, so one previous-block tail suffices and
  /// generation advances at most one block past i0+halfWidth.
  late final Int16List _hist;
  late final Int16List _histRight;

  double get _step => kOpl2SampleRate / outputSampleRate.toDouble();

  SciAdLibPcmSource(
    this.track,
    this.bank, {
    this.outputSampleRate = 44100,
    int masterVolume = 15,
    SciAdlibProfile? profile,
    this.tailTicks = 30,
    this.stereoDualOpl2 = false,
    SciAdLibDebugOverrides debugOverrides = const SciAdLibDebugOverrides.empty(),
  })  : _masterVolume = masterVolume.clamp(0, 15),
        profile = profile {
    _debugOverrides = debugOverrides;
    if (tailTicks < 0) {
      throw ArgumentError('tailTicks must be >= 0: $tailTicks');
    }
    if (outputSampleRate <= 0) {
      throw ArgumentError('outputSampleRate must be > 0: $outputSampleRate');
    }
    _profile = profile ??
        (track.variant == SciMidiHeaderVariant.early
            ? SciAdlibProfile.sci0Early
            : SciAdlibProfile.sci0Late);
    _mask = track.channelMaskFor(SciMidiDevice.adLib);
    _endTick = track.totalTicks;
    _filtered = <_FilteredEvent>[];
    for (final e in track.events) {
      if (e.tick > _endTick) continue;
      if (e.channel == 15) continue;
      if (e.channel >= 0 && !_mask.contains(e.channel)) continue;
      _filtered.add(_FilteredEvent(e, _frameForTick(e.tick)));
    }
    _endFrameNative = _frameForTick(_endTick);
    _totalNativeFrames = _frameForTick(_endTick + tailTicks);
    _totalFrames = _frameForTickAtRate(_endTick + tailTicks, outputSampleRate);
    if (outputSampleRate == kOpl2SampleRate) {
      _resampler = null;
      _halfWidth = 0;
      _hist = Int16List(0);
      _histRight = Int16List(0);
    } else {
      final r = PcmResampler(kOpl2SampleRate, outputSampleRate);
      _resampler = r;
      _halfWidth = r.halfWidth;
      _hist = Int16List(_halfWidth);
      _histRight = Int16List(_halfWidth);
    }
    reset();
  }

  @override
  int get sampleRate => outputSampleRate;

  @override
  int get channels => 2;

  @override
  int? get totalFrames => _totalFrames;

  @override
  int get positionFrames => _position;

  @override
  bool get isFinished => _position >= _totalFrames;

  @override
  void reset() {
    _position = 0;
    _eventIdx = 0;
    _didAllNotesOff = false;
    _generated = 0;
    _bufStart = 0;
    _bufLen = 0;
    _prevValid = false;
    _prevLast = 0;
    _prevValidRight = false;
    _prevLastRight = 0;
    for (var i = 0; i < _hist.length; i++) {
      _hist[i] = 0;
      _histRight[i] = 0;
    }
    _chip = Opl2Chip();
    if (stereoDualOpl2) {
      _chipRight = Opl2Chip();
      _driver = SciAdLibDriver(
        bank: bank,
        sink: DualOpl2ChipRegisterSink(_chip, _chipRight!),
        profile: _profile,
      );
    } else {
      _chipRight = null;
      _driver = SciAdLibDriver(
        bank: bank,
        sink: Opl2ChipRegisterSink(_chip),
        profile: _profile,
      );
    }
    _chip.writeLogEnabled = _writeLogEnabled;
    _chipRight?.writeLogEnabled = _writeLogEnabled;
    _driver.open();
    _driver.setMasterVolume(_masterVolume);
    _driver.initTrack(track);
    _driver.applyDebugOverrides(_debugOverrides);
  }

  @override
  void seekToFrame(int frame) {
    final target = frame.clamp(0, _totalFrames);
    reset();
    while (_position < target) {
      var chunk = target - _position;
      if (chunk > 4096) chunk = 4096;
      if (_discard.length < chunk * 2) {
        _discard = Int16List(chunk * 2);
      }
      renderInto(_discard, chunk);
    }
  }

  @override
  int renderInto(Int16List interleaved, int frameCount) {
    if (interleaved.length < frameCount * 2) {
      throw ArgumentError(
        'interleaved length ${interleaved.length} is less than '
        'frameCount * channels (${frameCount * 2})',
      );
    }
    if (frameCount <= 0) return 0;
    var n = frameCount;
    final remaining = _totalFrames - _position;
    if (n > remaining) n = remaining;
    if (n <= 0) return 0;
    final step = _step;
    final identity = step == 1.0;
    // Hoisted out of the per-frame loop (bound once per render block).
    int readLeft(int idx) => _readResampled(idx);
    int readRight(int idx) => _readResampled(idx, right: true);
    for (var i = 0; i < n; i++) {
      final pos = (_position + i) * step;
      final int sample;
      final int sampleRight;
      if (identity) {
        final idx = _position + i;
        _ensureAvail(idx);
        sample = _totalNativeFrames == 0 ? 0 : _readNative(idx);
        sampleRight = stereoDualOpl2 && _totalNativeFrames != 0
            ? _readNative(idx, right: true)
            : sample;
      } else {
        final double p = pos;
        final int i0 = p.floor();
        final r = _resampler!;
        if (_totalNativeFrames == 0) {
          sample = 0;
          sampleRight = 0;
        } else {
          _ensureAvail(
              i0 + _halfWidth < _totalNativeFrames
                  ? i0 + _halfWidth
                  : _totalNativeFrames - 1);
          sample = r.evaluateInt16(readLeft, p);
          sampleRight = stereoDualOpl2
              ? r.evaluateInt16(readRight, p)
              : sample;
        }
      }
      interleaved[i * 2] = sample;
      interleaved[i * 2 + 1] = sampleRight;
    }
    _position += n;
    return n;
  }

  // --- native generation ---

  int _readNative(int idx, {bool right = false}) {
    if (right) {
      if (idx < _bufStart) {
        // Previous block's last sample (or 0 for first block edge).
        return _prevValidRight ? _prevLastRight : 0;
      }
      return _nativeBufRight[idx - _bufStart];
    }
    if (idx < _bufStart) {
      // Previous block's last sample (or 0 for first block edge).
      return _prevValid ? _prevLast : 0;
    }
    return _nativeBuf[idx - _bufStart];
  }

  /// Random-access native read for the sinc evaluator: 0 outside
  /// [0, _totalNativeFrames). In-range reads hit the current block or
  /// [_bufStart-_halfWidth, _bufStart) history; callers must
  /// [_ensureAvail] to i0+halfWidth first (see [_halfWidth] proof).
  /// Reads at/after _generated (past-end lookahead) are 0.
  int _readResampled(int idx, {bool right = false}) {
    if (idx < 0 || idx >= _totalNativeFrames) return 0;
    if (idx >= _generated) return 0;
    if (idx >= _bufStart) {
      return right
          ? _nativeBufRight[idx - _bufStart]
          : _nativeBuf[idx - _bufStart];
    }
    final h = right ? _histRight : _hist;
    if (h.isEmpty) return 0;
    final hi = idx - (_bufStart - _halfWidth);
    if (hi < 0 || hi >= _halfWidth) return 0;
    return h[hi];
  }

  void _ensureAvail(int idx) {
    if (_totalNativeFrames == 0) return;
    if (idx >= _generated) {
      while (_generated <= idx && _generated < _totalNativeFrames) {
        _generateNextBlock();
        if (_bufLen == 0) break;
      }
    }
  }

  void _generateNextBlock() {
    if (_generated >= _totalNativeFrames) return;
    if (_bufLen > 0) {
      _prevLast = _nativeBuf[_bufLen - 1];
      _prevValid = true;
      if (stereoDualOpl2) {
        _prevLastRight = _nativeBufRight[_bufLen - 1];
        _prevValidRight = true;
      }
      // Retain last [_halfWidth] samples of the outgoing block as
      // history for the next block (see [_halfWidth] proof). Short
      // blocks (< W) only occur as the final partial block, after
      // which no further generation happens; the shift still keeps
      // the invariant for completeness.
      if (_halfWidth > 0) {
        if (_bufLen >= _halfWidth) {
          _hist.setRange(0, _halfWidth,
              _nativeBuf, _bufLen - _halfWidth);
          if (stereoDualOpl2) {
            _histRight.setRange(0, _halfWidth,
                _nativeBufRight, _bufLen - _halfWidth);
          } else {
            _histRight.setRange(0, _halfWidth, _hist);
          }
        } else {
          final keep = _halfWidth - _bufLen;
          _hist.setRange(0, keep, _hist, _bufLen);
          _hist.setRange(keep, _halfWidth, _nativeBuf, 0);
          if (stereoDualOpl2) {
            _histRight.setRange(0, keep, _histRight, _bufLen);
            _histRight.setRange(keep, _halfWidth, _nativeBufRight, 0);
          } else {
            _histRight.setRange(0, _halfWidth, _hist);
          }
        }
      }
    }
    _bufStart = _generated;
    _bufLen = 0;
    final blockTarget =
        (_generated + _kNativeBlockFrames).clamp(0, _totalNativeFrames);
    while (_generated < blockTarget) {
      final int nextDispatch;
      if (_eventIdx < _filtered.length) {
        nextDispatch = _filtered[_eventIdx].frame;
      } else if (!_didAllNotesOff) {
        nextDispatch = _endFrameNative;
      } else {
        nextDispatch = _totalNativeFrames;
      }
      if (nextDispatch <= _generated) {
        if (_eventIdx < _filtered.length) {
          _driver.handleEvent(_filtered[_eventIdx].event);
          _eventIdx++;
        } else {
          _driver.allNotesOff();
          _didAllNotesOff = true;
        }
        continue;
      }
      final upto =
          nextDispatch < blockTarget ? nextDispatch : blockTarget;
      final n = upto - _generated;
      // n > 0 because nextDispatch > _generated and upto > _generated.
      final offset = _generated - _bufStart;
      _chip.generate(
        Int16List.sublistView(_nativeBuf, offset, offset + n),
        n,
      );
      if (stereoDualOpl2) {
        _chipRight!.generate(
          Int16List.sublistView(_nativeBufRight, offset, offset + n),
          n,
        );
      }
      _generated += n;
      _bufLen = _generated - _bufStart;
    }
  }

  void setMasterVolume(int volume) {
    _masterVolume = volume.clamp(0, 15);
    _driver.setMasterVolume(_masterVolume);
  }

  /// Left-chip snapshot; in stereo-dual mode the right chip is not
  /// separately exposed here.
  OplDebugSnapshot debugSnapshot() => _chip.snapshot();

  /// Left snapshot plus the right snapshot in stereo-dual mode (one
  /// entry for mono, two for stereo).
  List<OplDebugSnapshot> debugSnapshots() => <OplDebugSnapshot>[
        _chip.snapshot(),
        if (stereoDualOpl2 && _chipRight != null) _chipRight!.snapshot(),
      ];

  /// Current session debug overrides.
  SciAdLibDebugOverrides get debugOverrides => _debugOverrides;

  /// Delegates to the driver so changes are audible on the next render
  /// advance.
  void applyDebugOverrides(SciAdLibDebugOverrides overrides) {
    _debugOverrides = overrides;
    _driver.applyDebugOverrides(overrides);
  }

  /// The driver, for the Stage 7 debug inspector only. Raw register
  /// access stays inside the driver; this getter exists so the
  /// inspector can read channel/voice state.
  SciAdLibDriver get debugDriver => _driver;

  /// Whether write-log capture is on (both chips).
  bool get writeLogEnabled => _writeLogEnabled;

  /// Enables/disables write-log capture on both chips (current source).
  set writeLogEnabled(bool value) {
    _writeLogEnabled = value;
    _chip.writeLogEnabled = value;
    _chipRight?.writeLogEnabled = value;
  }

  /// Captured write records, left chip then right chip in stereo mode.
  List<OplWriteRecord> get writeLogs => <OplWriteRecord>[
        ..._chip.writeLog,
        if (stereoDualOpl2 && _chipRight != null) ..._chipRight!.writeLog,
      ];

  /// Drains the write log on both chips.
  void clearWriteLogs() {
    _chip.clearWriteLog();
    _chipRight?.clearWriteLog();
  }

  @override
  void dispose() {}
}
