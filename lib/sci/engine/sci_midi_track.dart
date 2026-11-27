// Immutable SCI0 MIDI track model.
//
// A [SciMidiTrack] is a lossless, device-neutral representation of one SCI0
// sound resource: the early (17-byte) or late (33-byte) header with all 16
// channel initialization records, the complete timed MIDI event stream, and
// the optional digital-sample payload, kept separate from the MIDI bytes.
// Nothing here is OPL-, Tandy-, or MT-32-specific; device adapters (the
// legacy [AgiSound] translation, a future AdLib driver, a future MT-32
// backend) all consume this same stream. See
// doc/sci_adlib_mt32_audio_plan.md, stage 2.

import 'dart:typed_data';

/// SCI0 header layout: early packs one byte per channel after the flags
/// byte, late packs a voice-count byte plus a play-mask byte per channel.
enum SciMidiHeaderVariant { early, late }

/// Sound resource layout: the SCI0 single-stream form, or the SCI1
/// multi-track form (a device-track header table with one opcode stream
/// per descriptor, merged in tick order).
enum SciMidiSoundFormat { sci0, sci1MultiTrack }

/// Device classes whose play bits are decoded from the header records.
enum SciMidiDevice { adLib, tandyPcJr, pcSpeaker, mt32 }

/// Kinds of events in the SCI0 stream. Note-on with velocity 0 is normalized
/// to [noteOff] by the parser, matching ScummVM's parser behavior.
enum SciMidiEventKind {
  noteOn,
  noteOff,
  polyPressure,
  controlChange,
  programChange,
  channelPressure,
  pitchBend,
  sysEx,
  endOfTrack,

  /// Any other system status byte (0xF1-0xF6, 0xF8-0xFB, 0xFD-0xFF). The
  /// parser consumes no data bytes for these, matching the legacy parser.
  system,
}

/// One decoded channel initialization record from the SCI0 header.
class SciMidiChannelInit {
  /// Logical MIDI channel 0..15.
  final int channel;

  /// Raw header bytes for this channel: one byte (early) or two bytes
  /// (late: voice count, then play mask).
  final List<int> rawBytes;

  /// Requested hardware-voice count. Early: upper nibble. Late: voice-count
  /// byte masked with 0x7F (the AdLib driver ignores the top bit).
  final int requestedVoices;

  /// Device/play bits for this channel. Early: lower nibble (bit 0 AdLib,
  /// bit 1 PCjr, bit 2 PC speaker, bit 3 control/rhythm marker). Late: the
  /// play-mask byte (AdLib 0x04, PCjr 0x10, PC speaker 0x20, MT-32 0x01).
  final int playMask;

  /// Early headers only: bit 3 of the raw byte is set.
  final bool hasControlFlag;

  const SciMidiChannelInit({
    required this.channel,
    required this.rawBytes,
    required this.requestedVoices,
    required this.playMask,
    this.hasControlFlag = false,
  });

  /// Early classification: bit 3 set with bit 0 clear marks the control
  /// channel (channel 15 in practice). The drivers only interpret this in
  /// SCI0-early data; late headers have no equivalent bit.
  bool get isControlChannel =>
      hasControlFlag && (playMask & 0x01) == 0;

  /// Early classification: bit 3 set with bit 0 set marks the rhythm port.
  bool get isRhythmPort => hasControlFlag && (playMask & 0x01) != 0;

  /// The raw play-id bit this device's driver tests for, for [variant].
  /// Early values are already reduced to the low device bits, matching
  /// ScummVM's `getChannelFilterMask` (which masks early flags with 0x07
  /// before testing, so the bit-3 control marker never selects a device).
  static int devicePlayMask(SciMidiHeaderVariant variant, SciMidiDevice device) {
    return switch ((variant, device)) {
      (SciMidiHeaderVariant.early, SciMidiDevice.adLib) => 0x01,
      (SciMidiHeaderVariant.early, SciMidiDevice.tandyPcJr) => 0x02,
      (SciMidiHeaderVariant.early, SciMidiDevice.pcSpeaker) => 0x04,
      (SciMidiHeaderVariant.early, SciMidiDevice.mt32) => 0x01,
      (SciMidiHeaderVariant.late, SciMidiDevice.adLib) => 0x04,
      (SciMidiHeaderVariant.late, SciMidiDevice.tandyPcJr) => 0x10,
      (SciMidiHeaderVariant.late, SciMidiDevice.pcSpeaker) => 0x20,
      (SciMidiHeaderVariant.late, SciMidiDevice.mt32) => 0x01,
    };
  }

  /// Whether this channel's play bits select [device], without the
  /// channel-filter overrides (channel 15 always plays, channel 9 depends
  /// on the driver's rhythm request) that [SciMidiTrack.channelMaskFor]
  /// applies. The legacy adapter uses this method to preserve its exact
  /// historical channel selection.
  bool maskMatches(SciMidiHeaderVariant variant, SciMidiDevice device) =>
      (playMask & devicePlayMask(variant, device)) != 0;

  String toDebugString() {
    final raw =
        rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return 'ch$channel raw=$raw voices=$requestedVoices mask=0x${playMask.toRadixString(16).padLeft(2, '0')} ctrl=$hasControlFlag';
  }

  @override
  String toString() => 'SciMidiChannelInit(${toDebugString()})';
}

/// One timed MIDI event at an absolute 60 Hz tick. Running status has been
/// expanded (see [usedRunningStatus]); [status] is always the full status
/// byte, including for messages that arrived without one.
class SciMidiEvent {
  /// Absolute tick from track start.
  final int tick;
  final SciMidiEventKind kind;

  /// Channel 0..15, or -1 for SysEx, end-of-track, and system events.
  final int channel;

  /// Full status byte (0x80-0xEF for channel messages, 0xF0 SysEx,
  /// 0xFC end-of-track, other 0xF0+ values for [SciMidiEventKind.system]).
  final int status;

  /// First data byte, or -1 when the message has no data bytes.
  final int data1;

  /// Second data byte, or -1 when the message has only one data byte.
  final int data2;

  /// Complete SysEx message bytes (0xF0...0xF7) for [SciMidiEventKind.sysEx];
  /// empty otherwise. Payload bytes are preserved verbatim, including any
  /// with the high bit set.
  final List<int> sysExBytes;

  /// True when the stream carried no status byte and this event reused the
  /// previous running status.
  final bool usedRunningStatus;

  const SciMidiEvent({
    required this.tick,
    required this.kind,
    required this.channel,
    required this.status,
    this.data1 = -1,
    this.data2 = -1,
    this.sysExBytes = const [],
    this.usedRunningStatus = false,
  });

  /// Pitch-bend value 0..16383 (8192 center), for [SciMidiEventKind.pitchBend].
  int get pitchBendValue => ((data2 & 0x7F) << 7) | (data1 & 0x7F);

  bool get isNoteOn => kind == SciMidiEventKind.noteOn;
  bool get isNoteOff => kind == SciMidiEventKind.noteOff;
  bool get isProgramChange => kind == SciMidiEventKind.programChange;
  bool get isEndOfTrack => kind == SciMidiEventKind.endOfTrack;

  String toDebugString() {
    final statusHex = '0x${status.toRadixString(16).padLeft(2, '0')}';
    final running = usedRunningStatus ? ' running' : '';
    return switch (kind) {
      SciMidiEventKind.noteOn =>
        '@$tick noteOn ch=$channel note=$data1 vel=$data2 status=$statusHex$running',
      SciMidiEventKind.noteOff =>
        '@$tick noteOff ch=$channel note=$data1 vel=$data2 status=$statusHex$running',
      SciMidiEventKind.polyPressure =>
        '@$tick polyPressure ch=$channel note=$data1 pressure=$data2 status=$statusHex$running',
      SciMidiEventKind.controlChange =>
        '@$tick controlChange ch=$channel cc=$data1 value=$data2 status=$statusHex$running',
      SciMidiEventKind.programChange =>
        '@$tick programChange ch=$channel program=$data1 status=$statusHex$running',
      SciMidiEventKind.channelPressure =>
        '@$tick channelPressure ch=$channel pressure=$data1 status=$statusHex$running',
      SciMidiEventKind.pitchBend =>
        '@$tick pitchBend ch=$channel value=$pitchBendValue status=$statusHex$running',
      SciMidiEventKind.sysEx =>
        '@$tick sysEx bytes=${sysExBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      SciMidiEventKind.endOfTrack => '@$tick endOfTrack',
      SciMidiEventKind.system => '@$tick system status=$statusHex',
    };
  }

  @override
  String toString() => 'SciMidiEvent(${toDebugString()})';
}

/// A channel-15 cue or loop marker, in 60 Hz SCI ticks from track start.
/// Loop markers (program 127 on channel 15) are not cues; see
/// [SciMidiTrack.loopTick].
class SciMidiCue {
  final int tick;
  final int signal;

  const SciMidiCue({required this.tick, required this.signal});

  @override
  String toString() => 'SciMidiCue(tick: $tick, signal: $signal)';
}

/// The optional SCI0 digital sample, split out of the resource so the MIDI
/// stream is never scanned into PCM bytes.
class SciMidiSample {
  /// Raw 44-byte sample header (fewer bytes if the payload is truncated).
  final Uint8List rawHeaderBytes;

  /// Little-endian uint16 at header offset 14; null when fewer than 16
  /// header bytes are present.
  final int? sampleRate;

  /// Little-endian uint16 at header offset 32; null when fewer than 34
  /// header bytes are present.
  final int? sampleLength;

  /// SCI1 descriptor start word (10-byte header offset 6); null for
  /// SCI0 samples (which play from the start) and when truncated.
  final int? sampleStart;

  /// SCI1 descriptor end word (10-byte header offset 8); null for
  /// SCI0 samples (which play to the end) and when truncated.
  final int? sampleEnd;

  /// Absolute byte offset of the sample payload (the 44-byte header) within
  /// the original resource.
  final int payloadOffset;

  /// PCM bytes after the 44-byte header; empty when the payload is shorter.
  final Uint8List pcmBytes;

  const SciMidiSample({
    required this.rawHeaderBytes,
    required this.sampleRate,
    required this.sampleLength,
    required this.payloadOffset,
    required this.pcmBytes,
    this.sampleStart,
    this.sampleEnd,
  });

  /// Whether the whole 44-byte header is present.
  bool get hasCompleteHeader => rawHeaderBytes.length >= 44;

  /// Number of PCM bytes the ScummVM playback window covers: [sampleLength]
  /// when it names a positive length, clamped to the payload that is
  /// actually present.
  int get _windowBase {
    final declared = sampleLength;
    final base = (declared != null && declared > 0) ? declared : pcmBytes.length;
    return base > pcmBytes.length ? pcmBytes.length : base;
  }

  /// First PCM byte of the playable window (SCI1 start word, else 0),
  /// clamped into the payload.
  int get effectiveStart {
    final start = sampleStart ?? 0;
    if (start < 0) return 0;
    return start > _windowBase ? _windowBase : start;
  }

  /// Number of trailing PCM bytes excluded by the SCI1 end word, using
  /// ScummVM's `base - end` convention (an end word of 0, or one that
  /// does not fall inside the window, excludes nothing).
  int get _endPart {
    final end = sampleEnd;
    final base = _windowBase;
    if (end == null || end <= 0 || end >= base) return 0;
    return base - end;
  }

  /// Length in PCM bytes of the playable window, clamped to be >= 0.
  /// Pure and total: never throws.
  int get playableLength {
    final length = _windowBase - effectiveStart - _endPart;
    return length < 0 ? 0 : length;
  }

  /// Absolute PCM offset of the playable window within [pcmBytes].
  int get playableOffset => effectiveStart;

  /// Whether this sample can be rendered: a positive rate and at least
  /// one playable PCM byte.
  bool get isPlayable => sampleRate != null && sampleRate! > 0 && playableLength > 0;

  /// Playable duration in 60 Hz SCI ticks, rounded up; 0 when the sample
  /// is not playable. Pure and total: never throws.
  int get durationTicks {
    final rate = sampleRate;
    final length = playableLength;
    if (rate == null || rate <= 0 || length <= 0) return 0;
    return ((length * 60 + rate - 1) ~/ rate);
  }

  @override
  String toString() =>
      'SciMidiSample(rate: $sampleRate, length: $sampleLength, pcmBytes: ${pcmBytes.length}, payloadOffset: $payloadOffset)';
}

/// An immutable, lossless parse of one SCI0 sound resource.
class SciMidiTrack {
  /// Early (17-byte) or late (33-byte) header layout.
  final SciMidiHeaderVariant variant;

  /// Header size in bytes as used to locate the event stream.
  final int headerSize;

  /// Raw byte 0 of the resource. 0 means no digital sample; 2 marks a
  /// sample following the MIDI stream. The SCI0 drivers only run their
  /// header init for byte 0 == 0, or (late only) byte 0 == 2.
  final int flagsByte;

  /// True when a digital sample was actually split out (flags byte 2 with
  /// data after the 0xFC run).
  final bool hasDigitalSample;

  /// True when the flags byte said 2 but no sample data followed (seen in
  /// early Space Quest III resources); the stream is then parsed whole.
  final bool sampleFlagSetButNoData;

  /// The split-out sample, or null when [hasDigitalSample] is false.
  final SciMidiSample? sample;

  /// All 16 channel initialization records, in channel order.
  final List<SciMidiChannelInit> channels;

  /// The complete timed event stream, in order, with running status expanded.
  final List<SciMidiEvent> events;

  /// Channel-15 cues (program changes other than the loop marker 127).
  final List<SciMidiCue> cues;

  /// Tick of the last channel-15 program-127 loop marker, or null.
  final int? loopTick;

  /// Total duration in 60 Hz ticks (tick of end-of-track, or of the last
  /// parsed event when the stream has no end-of-track).
  final int totalTicks;

  /// True when an end-of-track (0xFC) was seen.
  final bool hasEndOfTrack;

  /// True when parsing stopped early because the stream ended mid-event.
  /// Events parsed before the truncation are still present; [truncatedTail]
  /// holds the unparsable remaining stream bytes for debugging.
  final bool isTruncated;
  final Uint8List truncatedTail;

  /// Sound resource layout (SCI0 single stream or SCI1 multi-track).
  /// Defaults to [SciMidiSoundFormat.sci0] so SCI0 call sites are unchanged.
  final SciMidiSoundFormat soundFormat;

  const SciMidiTrack({
    required this.variant,
    required this.headerSize,
    required this.flagsByte,
    this.soundFormat = SciMidiSoundFormat.sci0,
    required this.hasDigitalSample,
    required this.sampleFlagSetButNoData,
    required this.sample,
    required this.channels,
    required this.events,
    required this.cues,
    required this.loopTick,
    required this.totalTicks,
    required this.hasEndOfTrack,
    required this.isTruncated,
    required this.truncatedTail,
  });

  /// True when the track carries at least one audible note-on
  /// (velocity > 0). A sample-only sound has none; ScummVM then plays its
  /// digital sample instead of the (silent) MIDI rendition.
  bool get hasAudibleNotes =>
      events.any((e) => e.kind == SciMidiEventKind.noteOn && e.data2 > 0);

  /// Channels selected by the ScummVM-style filter for [device]: the play
  /// bit must match, channel 15 is always selected, and channel 9 is
  /// selected when [wantsRhythm] is set or the mask matches. Channel 9
  /// does not become a hardware rhythm mode by itself.
  Set<int> channelMaskFor(SciMidiDevice device, {bool wantsRhythm = false}) {
    final selected = <int>{};
    for (final init in channels) {
      final play = switch (init.channel) {
        15 => true,
        9 => wantsRhythm || init.maskMatches(variant, device),
        _ => init.maskMatches(variant, device),
      };
      if (play) selected.add(init.channel);
    }
    return selected;
  }

  /// Events on channels selected for [device] by [channelMaskFor].
  List<SciMidiEvent> eventsFor(SciMidiDevice device, {bool wantsRhythm = false}) {
    final mask = channelMaskFor(device, wantsRhythm: wantsRhythm);
    return events.where((e) => mask.contains(e.channel)).toList();
  }

  /// Deterministic text dump for tests, debugging, and fixtures.
  String toDebugString() {
    final lines = <String>[
      'SCI0 variant=${variant.name} headerSize=$headerSize flags=0x${flagsByte.toRadixString(16).padLeft(2, '0')} sample=$hasDigitalSample',
      for (final init in channels) '  ${init.toDebugString()}',
      for (final e in events) '  ${e.toDebugString()}',
      'cues: ${cues.map((c) => '${c.signal}@${c.tick}').join(' ')}',
      'loopTick: $loopTick',
      'totalTicks: $totalTicks endOfTrack: $hasEndOfTrack truncated: $isTruncated',
      if (sample != null)
        'sample: rate=${sample!.sampleRate} length=${sample!.sampleLength} pcmBytes=${sample!.pcmBytes.length} payloadOffset=${sample!.payloadOffset}',
    ];
    return lines.join('\n');
  }

  @override
  String toString() => 'SciMidiTrack(${toDebugString().split('\n').first})';
}
