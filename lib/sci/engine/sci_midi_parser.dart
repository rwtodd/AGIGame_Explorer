// Lossless SCI0/SCI1 MIDI decoding.
//
// Parses SCI0 sound resources (a single event stream after a 17- or
// 33-byte header) and SCI1 multi-track sound resources (a device-track
// header table with one stream per descriptor, merged in tick order) into
// [SciMidiTrack]. SCI0 semantics follow doc/sci_adlib_mt32_audio_plan.md:
// 60 Hz ticks, running status, 0xF8 delta bytes meaning +240 ticks,
// channel 15 as the cue/control channel, 0xFC as end-of-track, and an
// optional digital sample after the end-of-track run when byte 0 is 2.
// SCI1 semantics follow the header-table and midiMixChannels behavior of
// ScummVM's resource/sound code as a behavioral reference (clean-room
// semantics; no code was transliterated).
//
// Truncation policy: a stream that ends mid-event stops parsing at the last
// complete event, sets [SciMidiTrack.isTruncated], and keeps the leftover
// bytes in [SciMidiTrack.truncatedTail]; it never throws on truncated event
// data. Only a resource shorter than its own header throws, as a
// [FormatException], because no model can be built from it.

import 'dart:typed_data';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

/// Parses sound resources into the lossless [SciMidiTrack] model.
class SciMidiParser {
  static const int headerEarly = 0x11; // 17 bytes
  static const int headerLate = 0x21; // 33 bytes
  static const int endOfTrack = 0xFC;
  static const int stretchDelta = 0xF8;
  static const int endOfSysex = 0xF7;
  static const int sysexStart = 0xF0;

  /// Data-byte counts for channel voice commands 0x8..0xE.
  static const List<int> midiParamCount = [2, 2, 2, 2, 1, 1, 2];

  /// Parses [data] as a sound resource.
  ///
  /// [soundFormat] selects the SCI0 single-stream layout (default) or the
  /// SCI1 multi-track layout. For SCI0, [headerSize] overrides header
  /// detection; without it a resource of 33+ bytes is treated as late and
  /// anything shorter as early, matching the legacy parser's default. The
  /// variant is early for header sizes below 33 and late otherwise. Throws
  /// [FormatException] when [data] is shorter than the header it claims.
  static SciMidiTrack parse(
    Uint8List data, {
    int? headerSize,
    SciMidiSoundFormat soundFormat = SciMidiSoundFormat.sci0,
  }) {
    if (soundFormat == SciMidiSoundFormat.sci1MultiTrack) {
      return _parseSci1MultiTrack(data);
    }
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

  /// Decodes the SCI1 digital-sample descriptor channel at [offset] with
  /// [size] claimed bytes. The 10-byte header is: raw channel/flags byte,
  /// poly/prio byte, sample-rate u16 LE, sample-length u16 LE, sample
  /// start u16 LE, sample end u16 LE; PCM follows at offset + 10.
  static SciMidiSample _decodeSci1Sample(Uint8List data, int offset, int size) {
    final headerLen = size < 10 ? size : 10;
    int? readU16LE(int rel) {
      if (size < rel + 2) return null;
      return data[offset + rel] | (data[offset + rel + 1] << 8);
    }

    return SciMidiSample(
      rawHeaderBytes: Uint8List.sublistView(data, offset, offset + headerLen),
      sampleRate: readU16LE(2),
      sampleLength: readU16LE(4),
      payloadOffset: offset,
      pcmBytes: size > 10
          ? Uint8List.sublistView(data, offset + 10, offset + size)
          : Uint8List(0),
    );
  }

  /// Parses [data] as an SCI1 multi-track sound resource.
  ///
  /// Header layout: a sequence of device tracks, each starting with one
  /// type byte followed by 6-byte channel descriptors (unknown u16 ignored,
  /// data offset u16 LE, size u16 LE) terminated by a 0xFF byte. A 0xFF
  /// byte in a track-type position ends the header. Track type 0xF0 is the
  /// digital/priority pseudo-track and carries one 6-byte entry whose first
  /// byte is a priority. Throws [FormatException] when the header is
  /// truncated/incomplete or no type-0 (AdLib) track exists. The header table
  /// selects the first type-0 track; every other device track is ignored.
  static SciMidiTrack _parseSci1MultiTrack(Uint8List data) {
    final tracks = <_Sci1TrackHeader>[];
    var pos = 0;
    var headerComplete = false;
    while (pos < data.length) {
      final type = data[pos++];
      if (type == 0xFF) {
        headerComplete = true;
        break;
      }
      if (type == 0xF0) {
        // Digital/priority pseudo-track: one 6-byte entry whose first byte
        // is the priority, then the 0xFF list terminator.
        if (pos + 6 > data.length) {
          throw FormatException(
              'SCI1 sound resource has a truncated header: incomplete '
              'digital-track entry (${data.length} bytes)');
        }
        pos += 6;
        if (pos >= data.length || data[pos] != 0xFF) {
          throw FormatException(
              'SCI1 sound resource has a truncated header: missing '
              'digital-track terminator (${data.length} bytes)');
        }
        pos++;
        tracks.add(const _Sci1TrackHeader(0xF0, []));
        continue;
      }
      final descriptors = <_Sci1Descriptor>[];
      while (true) {
        if (pos >= data.length) {
          throw FormatException(
              'SCI1 sound resource has a truncated header: unterminated '
              'track (type 0x${type.toRadixString(16)})');
        }
        if (data[pos] == 0xFF) {
          pos++;
          break;
        }
        if (pos + 6 > data.length) {
          throw FormatException(
              'SCI1 sound resource has a truncated header: incomplete '
              'channel descriptor (${data.length} bytes)');
        }
        final offset = data[pos + 2] | (data[pos + 3] << 8);
        final size = data[pos + 4] | (data[pos + 5] << 8);
        descriptors.add(_Sci1Descriptor(offset, size));
        pos += 6;
      }
      tracks.add(_Sci1TrackHeader(type, descriptors));
    }
    if (!headerComplete) {
      throw FormatException(
          'SCI1 sound resource has a truncated header: missing track '
          'terminator (${data.length} bytes)');
    }

    _Sci1TrackHeader? selected;
    for (final track in tracks) {
      if (track.type == 0) {
        selected = track;
        break;
      }
    }
    if (selected == null) {
      throw FormatException(
          'SCI1 sound resource has no type-0 (AdLib) track');
    }

    var isTruncated = false;
    SciMidiSample? sample;
    var hasDigitalSample = false;
    final midiDescriptors = <_MidiDescriptorState>[];

    for (final descriptor in selected.descriptors) {
      final offset = descriptor.offset;
      var size = descriptor.size;
      if (offset >= data.length) {
        if (size > 0) isTruncated = true;
        continue;
      }
      if (size == 0) {
        continue;
      }
      if (offset + size > data.length) {
        size = data.length - offset;
        isTruncated = true;
      }
      if (size < 2) {
        isTruncated = true;
        continue;
      }
      final rawNumber = data[offset];
      final byte1 = data[offset + 1];
      if (rawNumber == 0xFE) {
        // Digital channel: captured as a sample, never parsed as MIDI.
        // Only descriptors with the full 10-byte SCI1 sample header are
        // captured (the first such wins); a shorter slice is truncated.
        if (size < 10) {
          isTruncated = true;
        } else if (!hasDigitalSample) {
          hasDigitalSample = true;
          sample = _decodeSci1Sample(data, offset, size);
        }
        continue;
      }
      midiDescriptors.add(_MidiDescriptorState(
        logicalChannel: rawNumber & 0x0F,
        poly: byte1 & 0x0F,
        start: offset + 2,
        end: offset + size,
      ));
    }

    final events = <SciMidiEvent>[];
    final cues = <SciMidiCue>[];
    int? loopTick;

    // Merge the per-descriptor streams in midiMixChannels order: repeatedly
    // pick the active descriptor whose next increment (peeked byte 0xF8
    // meaning 240, else the byte itself) lands earliest, with descriptor
    // order winning ties. Each pick consumes exactly one delta/F8 step;
    // a non-F8 step is then followed by one command from that descriptor.
    while (true) {
      _MidiDescriptorState? best;
      var bestTime = 0;
      for (final channel in midiDescriptors) {
        if (channel.terminated || channel.curPos >= channel.end) {
          continue;
        }
        final peek = data[channel.curPos];
        final next = channel.time + (peek == stretchDelta ? 240 : peek);
        if (best == null || next < bestTime) {
          best = channel;
          bestTime = next;
        }
      }
      if (best == null) break;

      final deltaByte = data[best.curPos++];
      best.time += deltaByte == stretchDelta ? 240 : deltaByte;
      if (deltaByte == stretchDelta) {
        continue;
      }

      if (best.curPos >= best.end) {
        // Delta with no following command: the descriptor simply ends here.
        best.terminated = true;
        best.endTick = best.time;
        best.remainderStart = best.end;
        continue;
      }

      final commandPos = best.curPos;
      final first = data[best.curPos++];

      if (first == endOfTrack) {
        // 0xFC ends only this descriptor.
        best.terminated = true;
        best.endedViaEndOfTrack = true;
        best.endTick = best.time;
        best.remainderStart = best.curPos;
        continue;
      }

      if (first == sysexStart) {
        final sysex = <int>[sysexStart];
        var terminated = false;
        while (best.curPos < best.end) {
          final b = data[best.curPos++];
          sysex.add(b);
          if (b == endOfSysex) {
            terminated = true;
            break;
          }
        }
        if (!terminated) {
          isTruncated = true;
          best.terminated = true;
          best.endTick = best.time;
          best.remainderStart = commandPos;
        }
        events.add(SciMidiEvent(
          tick: best.time,
          kind: SciMidiEventKind.sysEx,
          channel: -1,
          status: sysexStart,
          sysExBytes: List.unmodifiable(sysex),
        ));
        continue;
      }

      final int status;
      final bool usedRunningStatus;
      if ((first & 0x80) != 0) {
        status = first;
        usedRunningStatus = false;
        best.prev = first;
      } else {
        if (best.prev == 0) {
          // Data byte before any status byte: the descriptor cannot continue.
          isTruncated = true;
          best.terminated = true;
          best.endTick = best.time;
          best.remainderStart = commandPos;
          continue;
        }
        status = best.prev;
        usedRunningStatus = true;
      }

      if (status >= 0xF0) {
        // Other system status bytes take no parameters.
        events.add(SciMidiEvent(
          tick: best.time,
          kind: SciMidiEventKind.system,
          channel: -1,
          status: status,
        ));
        continue;
      }

      final command = (status >> 4) & 0x7;
      final n = midiParamCount[command];
      final params = <int>[];
      var midEventTruncated = false;
      if (usedRunningStatus) {
        params.add(first);
        if (best.curPos + (n - 1) > best.end) {
          midEventTruncated = true;
        } else {
          for (var i = 0; i < n - 1; i++) {
            params.add(data[best.curPos++]);
          }
        }
      } else {
        if (best.curPos + n > best.end) {
          midEventTruncated = true;
        } else {
          for (var i = 0; i < n; i++) {
            params.add(data[best.curPos++]);
          }
        }
      }
      if (midEventTruncated) {
        isTruncated = true;
        best.terminated = true;
        best.endTick = best.time;
        best.remainderStart = commandPos;
        continue;
      }

      final channel = status & 0x0F;
      final data1 = params[0];
      final data2 = n > 1 ? params[1] : -1;
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
        tick: best.time,
        kind: kind,
        channel: channel,
        status: status,
        data1: data1,
        data2: data2,
        usedRunningStatus: usedRunningStatus,
      ));

      if (kind == SciMidiEventKind.programChange && channel == 0x0F) {
        if (data1 == 127) {
          loopTick = best.time;
        } else {
          cues.add(SciMidiCue(tick: best.time, signal: data1));
        }
      }
    }

    var hasEndOfTrack = true;
    for (final channel in midiDescriptors) {
      if (!channel.endedViaEndOfTrack) {
        hasEndOfTrack = false;
        break;
      }
    }

    var totalTicks = 0;
    for (final channel in midiDescriptors) {
      final end = channel.terminated ? channel.endTick : channel.time;
      if (end > totalTicks) totalTicks = end;
    }
    for (final event in events) {
      if (event.tick > totalTicks) totalTicks = event.tick;
    }

    if (hasEndOfTrack) {
      events.add(SciMidiEvent(
        tick: totalTicks,
        kind: SciMidiEventKind.endOfTrack,
        channel: -1,
        status: endOfTrack,
      ));
    }

    final tail = BytesBuilder();
    for (final channel in midiDescriptors) {
      tail.add(Uint8List.sublistView(data, channel.remainderStart, channel.end));
    }

    // Synthesized late-equivalent channel inits for the existing driver:
    // requested voices are the summed poly nibbles of the descriptors on
    // each logical channel and the play mask is the late AdLib bit 0x04.
    // These are not literal header bytes from the SCI1 table.
    final voicesByChannel = <int, int>{};
    for (final channel in midiDescriptors) {
      voicesByChannel.update(channel.logicalChannel,
          (v) => v + channel.poly, ifAbsent: () => channel.poly);
    }
    final channels = List.generate(16, (ch) {
      final voices = voicesByChannel[ch] ?? 0;
      final hasDescriptor = voicesByChannel.containsKey(ch);
      return SciMidiChannelInit(
        channel: ch,
        rawBytes: [voices, hasDescriptor ? 0x04 : 0x00],
        requestedVoices: voices,
        playMask: hasDescriptor ? 0x04 : 0x00,
      );
    });

    return SciMidiTrack(
      variant: SciMidiHeaderVariant.late,
      soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      headerSize: pos,
      flagsByte: selected.type,
      hasDigitalSample: hasDigitalSample,
      sampleFlagSetButNoData: false,
      sample: sample,
      channels: channels,
      events: List.unmodifiable(events),
      cues: List.unmodifiable(cues),
      loopTick: loopTick,
      totalTicks: totalTicks,
      hasEndOfTrack: hasEndOfTrack,
      isTruncated: isTruncated,
      truncatedTail: tail.toBytes(),
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

/// One SCI1 header descriptor (the 6 bytes after a track start byte).
class _Sci1Descriptor {
  final int offset;
  final int size;

  const _Sci1Descriptor(this.offset, this.size);
}

/// One parsed SCI1 device track (a track type plus its descriptors).
class _Sci1TrackHeader {
  final int type;
  final List<_Sci1Descriptor> descriptors;

  const _Sci1TrackHeader(this.type, this.descriptors);
}

/// Mutable per-descriptor mixer state for SCI1 parsing.
class _MidiDescriptorState {
  final int logicalChannel;
  final int poly;
  final int start;
  final int end;
  int curPos;
  int time = 0;
  int prev = 0;
  bool terminated = false;
  bool endedViaEndOfTrack = false;
  int endTick = 0;
  int remainderStart;

  _MidiDescriptorState({
    required this.logicalChannel,
    required this.poly,
    required this.start,
    required this.end,
  })  : curPos = start,
        remainderStart = end;
}
