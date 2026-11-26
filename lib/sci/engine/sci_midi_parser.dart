// Lossless SCI0 MIDI decoding.
//
// Parses SCI0 sound resources into [SciMidiTrack]. Format semantics follow
// the SCI0 resource layout (doc/sci_adlib_mt32_audio_plan.md): one event
// stream at 60 Hz ticks after a 17- or 33-byte header, running status,
// 0xF8 delta bytes meaning +240 ticks, channel 15 as the cue/control
// channel, 0xFC as end-of-track, and an optional digital sample after the
// end-of-track run when byte 0 is 2. ScummVM's `midiparser_sci.cpp` and
// `resource_audio.cpp` were behavior references only (clean-room semantics;
// no code was transliterated).
//
// Truncation policy: a stream that ends mid-event stops parsing at the last
// complete event, sets [SciMidiTrack.isTruncated], and keeps the leftover
// bytes in [SciMidiTrack.truncatedTail]; it never throws on truncated event
// data. Only a resource shorter than its own header throws, as a
// [FormatException], because no model can be built from it.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

/// Parses SCI0 sound resources into the lossless [SciMidiTrack] model.
class SciMidiParser {
  static const int headerEarly = 0x11; // 17 bytes
  static const int headerLate = 0x21; // 33 bytes
  static const int endOfTrack = 0xFC;
  static const int stretchDelta = 0xF8;
  static const int endOfSysex = 0xF7;
  static const int sysexStart = 0xF0;

  /// Data-byte counts for channel voice commands 0x8..0xE.
  static const List<int> midiParamCount = [2, 2, 2, 2, 1, 1, 2];

  /// Parses [data] as an SCI0 sound resource.
  ///
  /// [headerSize] overrides header detection; without it a resource of 33+
  /// bytes is treated as late and anything shorter as early, matching the
  /// legacy parser's default. The variant is early for header sizes below
  /// 33 and late otherwise. Throws [FormatException] when [data] is shorter
  /// than the header it claims.
  static SciMidiTrack parse(Uint8List data, {int? headerSize}) {
    final effectiveHeader = headerSize ??
        (data.length >= headerLate
            ? headerLate
            : (data.length >= headerEarly ? headerEarly : data.length));
    final variant =
        effectiveHeader >= headerLate ? SciMidiHeaderVariant.late : SciMidiHeaderVariant.early;
    final neededHeader = variant == SciMidiHeaderVariant.late ? headerLate : headerEarly;
    if (data.length < neededHeader) {
      throw FormatException(
          'SCI0 resource shorter than its ${variant.name} header: ${data.length} bytes');
    }

    final flagsByte = data[0];
    final channels = _decodeChannelInits(data, variant);

    // Locate the MIDI stream and, when flags byte 0 == 2, split off the
    // digital sample. Like ScummVM, the split scans naively for the first
    // 0xFC and skips any run of 0xFC bytes; the sample payload after the run
    // (44-byte header plus PCM) is never scanned as MIDI.
    var streamEnd = data.length;
    SciMidiSample? sample;
    var sampleFlagSetButNoData = false;
    if (flagsByte == 2) {
      var fcIndex = effectiveHeader;
      while (fcIndex < data.length && data[fcIndex] != endOfTrack) {
        fcIndex++;
      }
      if (fcIndex >= data.length) {
        sampleFlagSetButNoData = true;
      } else {
        var afterRun = fcIndex;
        while (afterRun < data.length && data[afterRun] == endOfTrack) {
          afterRun++;
        }
        if (afterRun >= data.length) {
          sampleFlagSetButNoData = true;
        } else {
          sample = _decodeSample(data, afterRun);
          streamEnd = fcIndex;
        }
      }
    }

    final parsed = _parseStream(data, effectiveHeader, streamEnd);
    final events = parsed.events;
    var hasEndOfTrack = parsed.hasEndOfTrack;
    // A split sample trimmed the 0xFC run, so the stream ends without the
    // terminator inside the MIDI span; the terminator still exists as an
    // event at the end of the MIDI portion.
    if (sample != null && !hasEndOfTrack) {
      events.add(SciMidiEvent(
        tick: parsed.totalTicks,
        kind: SciMidiEventKind.endOfTrack,
        channel: -1,
        status: endOfTrack,
      ));
      hasEndOfTrack = true;
    }

    return SciMidiTrack(
      variant: variant,
      headerSize: effectiveHeader,
      flagsByte: flagsByte,
      hasDigitalSample: sample != null,
      sampleFlagSetButNoData: sampleFlagSetButNoData,
      sample: sample,
      channels: channels,
      events: List.unmodifiable(events),
      cues: List.unmodifiable(parsed.cues),
      loopTick: parsed.loopTick,
      totalTicks: parsed.totalTicks,
      hasEndOfTrack: hasEndOfTrack,
      isTruncated: parsed.isTruncated,
      truncatedTail: parsed.truncatedTail,
    );
  }

  static List<SciMidiChannelInit> _decodeChannelInits(
      Uint8List data, SciMidiHeaderVariant variant) {
    return List.generate(16, (ch) {
      if (variant == SciMidiHeaderVariant.early) {
        final raw = data[1 + ch];
        return SciMidiChannelInit(
          channel: ch,
          rawBytes: [raw],
          requestedVoices: raw >> 4,
          playMask: raw & 0x0F,
          hasControlFlag: (raw & 0x08) != 0,
        );
      }
      final voicesByte = data[1 + ch * 2];
      final maskByte = data[1 + ch * 2 + 1];
      return SciMidiChannelInit(
        channel: ch,
        rawBytes: [voicesByte, maskByte],
        requestedVoices: voicesByte & 0x7F,
        playMask: maskByte,
      );
    });
  }

  static SciMidiSample _decodeSample(Uint8List data, int payloadOffset) {
    final headerEnd = (payloadOffset + 44).clamp(payloadOffset, data.length);
    final headerBytes = Uint8List.sublistView(data, payloadOffset, headerEnd);
    int? readU16LE(int offset) {
      final at = payloadOffset + offset;
      if (at + 1 >= data.length) return null;
      return data[at] | (data[at + 1] << 8);
    }

    final pcmStart = (payloadOffset + 44).clamp(payloadOffset, data.length);
    return SciMidiSample(
      rawHeaderBytes: headerBytes,
      sampleRate: readU16LE(14),
      sampleLength: readU16LE(32),
      payloadOffset: payloadOffset,
      pcmBytes: Uint8List.sublistView(data, pcmStart, data.length),
    );
  }

  static _StreamResult _parseStream(Uint8List data, int start, int end) {
    final events = <SciMidiEvent>[];
    final cues = <SciMidiCue>[];
    int? loopTick;
    var tick = 0;
    var running = 0;
    var hasEndOfTrack = false;
    var isTruncated = false;
    Uint8List truncatedTail = Uint8List(0);
    var i = start;

    void markTruncated(int from) {
      isTruncated = true;
      truncatedTail = Uint8List.sublistView(data, from, end);
    }

    while (i < end) {
      // Delta time: 0xF8 bytes each add 240 ticks; the following byte is the
      // delta itself.
      while (i < end && data[i] == stretchDelta) {
        tick += 240;
        i++;
      }
      if (i >= end) break;
      if (data[i] == endOfTrack) {
        events.add(SciMidiEvent(
          tick: tick,
          kind: SciMidiEventKind.endOfTrack,
          channel: -1,
          status: endOfTrack,
        ));
        hasEndOfTrack = true;
        break;
      }
      tick += data[i++];
      if (i >= end) break;

      final eventStart = i;
      final int status;
      final bool usedRunningStatus;
      if ((data[i] & 0x80) != 0) {
        status = data[i];
        i++;
        usedRunningStatus = false;
        running = status;
      } else {
        status = running;
        usedRunningStatus = true;
      }

      if (status == endOfTrack) {
        events.add(SciMidiEvent(
          tick: tick,
          kind: SciMidiEventKind.endOfTrack,
          channel: -1,
          status: endOfTrack,
        ));
        hasEndOfTrack = true;
        break;
      }

      if (status == sysexStart) {
        final sysex = <int>[status];
        var terminated = false;
        while (i < end) {
          final b = data[i++];
          sysex.add(b);
          if (b == endOfSysex) {
            terminated = true;
            break;
          }
        }
        if (!terminated) markTruncated(eventStart);
        events.add(SciMidiEvent(
          tick: tick,
          kind: SciMidiEventKind.sysEx,
          channel: -1,
          status: sysexStart,
          sysExBytes: List.unmodifiable(sysex),
        ));
        continue;
      }

      // Legacy-parity: a data byte with no running status in force reads as
      // status 0x00 (note-off, channel 0), as the old parser did.
      final channel = status & 0x0F;
      final isChannelVoice = status < 0xF0;
      if (!isChannelVoice) {
        events.add(SciMidiEvent(
          tick: tick,
          kind: SciMidiEventKind.system,
          channel: -1,
          status: status,
        ));
        continue;
      }

      final command = (status >> 4) & 0x7;
      final n = midiParamCount[command];
      if (i + n > end) {
        markTruncated(eventStart);
        break;
      }
      final data1 = data[i];
      final data2 = n > 1 ? data[i + 1] : -1;
      i += n;

      final kind = switch (command) {
        0 => SciMidiEventKind.noteOff,
        1 => data2 == 0 ? SciMidiEventKind.noteOff : SciMidiEventKind.noteOn,
        2 => SciMidiEventKind.polyPressure,
        3 => SciMidiEventKind.controlChange,
        4 => SciMidiEventKind.programChange,
        5 => SciMidiEventKind.channelPressure,
        6 => SciMidiEventKind.pitchBend,
        _ => SciMidiEventKind.system,
      };
      events.add(SciMidiEvent(
        tick: tick,
        kind: kind,
        channel: channel,
        status: status,
        data1: data1,
        data2: data2,
        usedRunningStatus: usedRunningStatus,
      ));

      if (kind == SciMidiEventKind.programChange && channel == 0x0F) {
        if (data1 == 127) {
          loopTick = tick;
        } else {
          cues.add(SciMidiCue(tick: tick, signal: data1));
        }
      }
    }

    return _StreamResult(
      events: events,
      cues: cues,
      loopTick: loopTick,
      totalTicks: tick,
      hasEndOfTrack: hasEndOfTrack,
      isTruncated: isTruncated,
      truncatedTail: truncatedTail,
    );
  }
}

class _StreamResult {
  final List<SciMidiEvent> events;
  final List<SciMidiCue> cues;
  final int? loopTick;
  final int totalTicks;
  final bool hasEndOfTrack;
  final bool isTruncated;
  final Uint8List truncatedTail;

  const _StreamResult({
    required this.events,
    required this.cues,
    required this.loopTick,
    required this.totalTicks,
    required this.hasEndOfTrack,
    required this.isTruncated,
    required this.truncatedTail,
  });
}
