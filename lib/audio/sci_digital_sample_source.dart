// Stage 8 streaming SCI digital-sample source: SCI0/SCI1 unsigned 8-bit
// PCM payload -> pull-based stereo PCM.
//
// The SCI sample (44-byte SCI0 header, or a 10-byte SCI1 descriptor) is
// NOT part of the FM patch or OPL register state; it gets its own PCM
// source, matching the plan's "Sound Blaster completion" framing. The
// ScummVM decision it models: a sample REPLACES the MIDI rendition
// (never mixed) — see the kernel routing in sci_kernel.dart.
//
// Conversion: unsigned 8-bit -> int16 as (byte - 128) << 8, scaled by
// masterVolume/15 (double math, round, clamp), duplicated to L/R.
// Resampler: measured windowed-sinc (lib/audio/pcm_resampler.dart) from
// the sample rate to outputSampleRate; the filter runs in the int16
// domain, then master-volume scaling (round + clamp). Identity rate
// is a true bypass (exact frames). Numbers live in
// tool/measure_resampler.dart output. Output is deterministic and
// independent of renderInto block sizes; no steady-state allocation.

import 'dart:typed_data';

import 'package:flutter_agigame/audio/pcm_resampler.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

class SciDigitalSamplePcmSource extends PcmSource {
  /// The wrapped sample (rate, playable window, PCM payload).
  final SciMidiSample sample;

  /// Output sample rate in Hz.
  final int outputSampleRate;

  /// Input (sample) rate in Hz; 0 when the sample has no usable rate,
  /// in which case the source is empty (totalFrames 0, finished).
  final int inputSampleRate;

  int _masterVolume;

  late final int _totalFrames;
  int _position = 0;

  /// Measured sinc resampler; null iff inputSampleRate == outputSampleRate
  /// (identity fast path) or the sample is unplayable (rate 0).
  late final PcmResampler? _resampler;

  /// Scratch buffer for seekToFrame render-and-discard.
  Int16List _discard = Int16List(0);

  SciDigitalSamplePcmSource(
    this.sample, {
    this.outputSampleRate = 44100,
    int masterVolume = 15,
  })  : inputSampleRate = sample.sampleRate ?? 0,
        _masterVolume = masterVolume.clamp(0, 15) {
    if (outputSampleRate <= 0) {
      throw ArgumentError('outputSampleRate must be > 0: $outputSampleRate');
    }
    if (sample.isPlayable) {
      _totalFrames =
          (sample.playableLength * outputSampleRate / inputSampleRate).round();
    } else {
      _totalFrames = 0;
    }
    _resampler = (sample.isPlayable && inputSampleRate != outputSampleRate)
        ? PcmResampler(inputSampleRate, outputSampleRate)
        : null;
  }

  /// Current SCI master-volume value (0..15) applied to the sample.
  int get masterVolume => _masterVolume;

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

  /// Sets the SCI master volume (0..15); takes effect on subsequent
  /// renders.
  void setMasterVolume(int volume) {
    _masterVolume = volume.clamp(0, 15);
  }

  /// Signed int16 value of the playable-window PCM byte at [index]
  /// (0-based from the window start), before master-volume scaling.
  int _pcmAt(int index) {
    final bytes = sample.pcmBytes;
    final at = sample.playableOffset + index;
    if (at < 0 || at >= bytes.length) return 0;
    return (bytes[at] - 128) << 8;
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

    final scale = _masterVolume / 15.0;
    final playable = sample.playableLength;
    final identity = inputSampleRate == outputSampleRate;
    // Hoisted out of the per-frame loop (bound once per render block).
    int readWindow(int idx) =>
        (idx >= 0 && idx < playable) ? _pcmAt(idx) : 0;

    for (var i = 0; i < n; i++) {
      final frame = _position + i;
      final int value;
      if (identity) {
        value = _pcmAt(frame);
      } else {
        // Windowed-sinc, keyed off the absolute output frame so the
        // result cannot depend on renderInto block splits. Edge
        // policy: outside [0, playable) reads 0; filter in int16
        // domain, then master-volume scale below.
        final r = _resampler!;
        final double pos = r.inputPositionForFrame(frame);
        value = r.evaluateInt16(readWindow, pos);
      }
      final scaled = (value * scale).round().clamp(-32768, 32767);
      interleaved[i * 2] = scaled;
      interleaved[i * 2 + 1] = scaled;
    }
    _position += n;
    return n;
  }
}
