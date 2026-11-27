// Offline SCI0 AdLib audition renderer (Stage 5b).
//
// Renders a lossless [SciMidiTrack] through the Sierra AdLib driver
// (Stage 5a) and the pure Dart OPL2 chip (Stage 4) into native-rate
// mono PCM. No gameplay/streaming integration lives here; that is Stage 6.
// Used by tests and the future Sound Browser for deterministic offline
// audition/export.
//
// Duration math (exact): ticks run at 60 Hz and the chip runs at
// [kOpl2SampleRate] (49,716 Hz). The rendered span is
// `endTick + tailTicks` where `endTick = min(track.totalTicks, maxTicks?)`,
// and `totalFrames = ((endTick + tailTicks) * kOpl2SampleRate / 60).round()`.
// Each event's frame is also `(tick * kOpl2SampleRate / 60).round()`,
// computed from the absolute tick, so there is no accumulated rounding
// drift. At `endTick` the driver receives `allNotesOff()`, then the
// release tail is rendered. Loop points are ignored (single pass;
// looping belongs to the streaming sequencer in Stage 6).
//
// Channel filtering: an event is dispatched only when its channel is in
// `track.channelMaskFor(SciMidiDevice.adLib)`. Channel-15 events are
// skipped entirely (cues/control; they must not reach the driver as
// program changes). Events with channel -1 (sysEx/system/end-of-track)
// are forwarded to the driver, which ignores them; forwarding keeps the
// renderer from silently making distinctions the driver itself does not.
// Events after `endTick` are not dispatched.
//
// Profile: the caller may override it; otherwise it is derived from
// `track.variant` — early maps to [SciAdlibProfile.sci0Early] (8 voices)
// and late to [SciAdlibProfile.sci0Late] (9 voices). Each render builds a
// fresh chip + driver, so renders are independent and deterministic.

import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/wav_encoder.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// Block size used when generating chip frames (one reusable buffer).
const int sciAdLibRenderBlockFrames = 1024;

/// Result of one offline AdLib render: mono PCM plus render facts.
final class SciAdLibRenderResult {
  /// Mono PCM samples at [sampleRate] Hz.
  final Int16List pcm;

  /// Native chip sample rate ([kOpl2SampleRate]).
  final int sampleRate;

  /// Ticks of the track actually rendered, excluding the tail
  /// (`min(track.totalTicks, maxTicks?)`).
  final int renderedTicks;

  /// Total rendered frames: `pcm.length / channels`, i.e.
  /// `((renderedTicks + tailTicks) * kOpl2SampleRate / 60).round()`.
  final int totalFrames;

  /// Channel count (1 mono, 2 stereo-dual-OPL2). Defaults to 1.
  final int channels;

  const SciAdLibRenderResult({
    required this.pcm,
    required this.sampleRate,
    required this.renderedTicks,
    required this.totalFrames,
    this.channels = 1,
  });

  /// Peak absolute sample value (0 for silence).
  int get peakAbs {
    var peak = 0;
    for (final s in pcm) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return peak;
  }
}

/// Frame index of an absolute 60 Hz tick at native chip rate.
int _frameForTick(int tick) => (tick * kOpl2SampleRate / 60).round();

/// Offline-renders [track] with [bank] into native-rate mono PCM.
///
/// Builds a fresh [Opl2Chip] + [SciAdLibDriver] per call (independent,
/// deterministic). Parameters: [maxTicks] (nullable) caps the track span,
/// [tailTicks] (default 30 = 0.5 s) is the release tail after
/// `allNotesOff()` at the end, [masterVolume] (default 15) is the SCI0
/// master volume 0..15, and [profile] overrides the variant-derived
/// driver profile.
SciAdLibRenderResult sciAdLibRenderTrack(
  SciMidiTrack track,
  SciAdlibBank bank, {
  int? maxTicks,
  int tailTicks = 30,
  int masterVolume = 15,
  SciAdlibProfile? profile,
  bool stereo = false,
}) {
  if (tailTicks < 0) {
    throw ArgumentError('tailTicks must be >= 0: $tailTicks');
  }
  if (maxTicks != null && maxTicks < 0) {
    throw ArgumentError('maxTicks must be >= 0: $maxTicks');
  }
  final endTick = maxTicks == null
      ? track.totalTicks
      : (track.totalTicks < maxTicks ? track.totalTicks : maxTicks);
  final totalFrames = _frameForTick(endTick + tailTicks);
  final endFrame = _frameForTick(endTick);
  final channels = stereo ? 2 : 1;
  final output = Int16List(totalFrames * channels);
  if (totalFrames == 0) {
    return SciAdLibRenderResult(
      pcm: output,
      sampleRate: kOpl2SampleRate,
      renderedTicks: endTick,
      totalFrames: totalFrames,
      channels: channels,
    );
  }
  final chip = Opl2Chip();
  final chipRight = stereo ? Opl2Chip() : null;
  final driver = SciAdLibDriver(
    bank: bank,
    sink: stereo
        ? DualOpl2ChipRegisterSink(chip, chipRight!)
        : Opl2ChipRegisterSink(chip),
    profile: profile ??
        (track.variant == SciMidiHeaderVariant.early
            ? SciAdlibProfile.sci0Early
            : SciAdlibProfile.sci0Late),
  );
  driver.open();
  driver.setMasterVolume(masterVolume);
  driver.initTrack(track);

  final mask = track.channelMaskFor(SciMidiDevice.adLib);
  final block = Int16List(sciAdLibRenderBlockFrames);
  var cursor = 0;

  final blockRight = Int16List(sciAdLibRenderBlockFrames);
  void renderUntil(int target) {
    final t = target.clamp(0, totalFrames);
    while (cursor < t) {
      final n = (t - cursor).clamp(1, sciAdLibRenderBlockFrames);
      chip.generate(block, n);
      if (stereo) {
        chipRight!.generate(blockRight, n);
        for (var i = 0; i < n; i++) {
          output[(cursor + i) * 2] = block[i];
          output[(cursor + i) * 2 + 1] = blockRight[i];
        }
      } else {
        output.setRange(cursor, cursor + n, block);
      }
      cursor += n;
    }
  }

  for (final event in track.events) {
    if (event.tick > endTick) continue;
    // Channel-15 cues/control never reach the driver as program changes.
    if (event.channel == 15) continue;
    // Non-AdLib channels are filtered out; channel -1 (sysEx/system/
    // end-of-track) is forwarded — the driver ignores it.
    if (event.channel >= 0 && !mask.contains(event.channel)) continue;
    renderUntil(_frameForTick(event.tick));
    driver.handleEvent(event);
  }
  renderUntil(endFrame);
  driver.allNotesOff();
  renderUntil(totalFrames);

  return SciAdLibRenderResult(
    pcm: output,
    sampleRate: kOpl2SampleRate,
    renderedTicks: endTick,
    totalFrames: totalFrames,
    channels: channels,
  );
}

/// Result of the volume-backed convenience render. Never throws for the
/// ordinary unavailable case: [render] is null and [unavailableReason]
/// explains why (sound missing/unreadable, bank unavailable with the
/// loader's reason, or parse [FormatException]).
final class SciAdLibVolumeRenderResult {
  /// The render, or null when unavailable.
  final SciAdLibRenderResult? render;

  /// Where the bank came from on success; unavailable on failure.
  final SciAdlibBankProvenance provenance;

  /// Human-readable reason; null when [render] succeeded.
  final String? unavailableReason;

  const SciAdLibVolumeRenderResult({
    required this.render,
    required this.provenance,
    required this.unavailableReason,
  });

  /// True when a render was produced.
  bool get isAvailable => render != null;
}

/// Loads sound resource [soundNumber] from [volumes], parses it, loads
/// the AdLib bank, and offline-renders it. Returns an unavailable
/// result (instead of throwing) for a missing/unreadable sound resource,
/// an unavailable bank (with the loader's reason), or a parse
/// [FormatException]. On success the result carries the bank provenance.
SciAdLibVolumeRenderResult sciAdLibRenderSound(
  SciVolumeManager volumes,
  int soundNumber, {
  int? maxTicks,
  int tailTicks = 30,
  int masterVolume = 15,
  SciAdlibProfile? profile,
  bool stereo = false,
}) {
  late final Uint8List soundBytes;
  try {
    soundBytes = volumes.getResource(SciResourceType.sound, soundNumber);
  } on SciException catch (e) {
    return SciAdLibVolumeRenderResult(
      render: null,
      provenance: SciAdlibBankProvenance.unavailable,
      unavailableReason: 'Sound resource $soundNumber unreadable: ${e.message}',
    );
  }
  final bankResult = sciLoadAdlibBank(volumes);
  final bank = bankResult.bank;
  if (!bankResult.isAvailable || bank == null) {
    return SciAdLibVolumeRenderResult(
      render: null,
      provenance: bankResult.provenance,
      unavailableReason: 'AdLib bank unavailable: ${bankResult.reason}',
    );
  }
  late final SciMidiTrack track;
  try {
    final isSci1 = volumes.usesPostSci01Compression;
    track = SciMidiParser.parse(
      soundBytes,
      headerSize: isSci1
          ? null
          : (volumes.isEarlySci0
              ? SciMidiParser.headerEarly
              : SciMidiParser.headerLate),
      soundFormat:
          isSci1 ? SciMidiSoundFormat.sci1MultiTrack : SciMidiSoundFormat.sci0,
    );
  } on FormatException catch (e) {
    return SciAdLibVolumeRenderResult(
      render: null,
      provenance: bankResult.provenance,
      unavailableReason: 'Sound resource $soundNumber parse error: ${e.message}',
    );
  }
  return SciAdLibVolumeRenderResult(
    render: sciAdLibRenderTrack(
      track,
      bank,
      maxTicks: maxTicks,
      tailTicks: tailTicks,
      masterVolume: masterVolume,
      profile: profile,
      stereo: stereo,
    ),
    provenance: bankResult.provenance,
    unavailableReason: null,
  );
}

/// Builds a synthetic late-header [SciMidiTrack] for auditioning one bank
/// patch with no game resource (Stage 7 inspector patch browser).
///
/// Layout: 2 voices requested on each of channels 1-4 (late AdLib mask
/// 0x04, matching the game header form), each channel's program set to
/// [patch], CC7 (volume) at 127, pitch bend at center, sustain pedal off,
/// and pan 16/48/80/112 respectively. Notes 60/64/67/72 enter staggered
/// every 30 ticks (0/30/60/90) and are all held as a chord to tick 210,
/// with matching note-offs and a single merged end-of-track at 210.
/// Events are tick-sorted with all setup events before note-ons at
/// tick 0.
///
/// [patch] must be >= 0 (throws [ArgumentError] otherwise); values beyond
/// the bank are the driver's ordinary out-of-range fallback.
SciMidiTrack sciAdLibPatchAuditionTrack(int patch) {
  if (patch < 0) {
    throw ArgumentError('patch must be >= 0: $patch');
  }
  const channels = [1, 2, 3, 4];
  const notes = [60, 64, 67, 72];
  const pans = [16, 48, 80, 112];
  final channelInits = <SciMidiChannelInit>[
    for (var ch = 0; ch < 16; ch++)
      if (ch >= 1 && ch <= 4)
        SciMidiChannelInit(
          channel: ch,
          rawBytes: const [2, 0x04],
          requestedVoices: 2,
          playMask: 0x04,
        )
      else
        SciMidiChannelInit(
          channel: ch,
          rawBytes: const [0, 0],
          requestedVoices: 0,
          playMask: 0,
        ),
  ];
  final events = <SciMidiEvent>[];
  // Setup for every channel first (all at tick 0, before note-ons).
  for (var i = 0; i < channels.length; i++) {
    final ch = channels[i];
    events.add(SciMidiEvent(
      tick: 0,
      kind: SciMidiEventKind.programChange,
      channel: ch,
      status: 0xC0 | ch,
      data1: patch,
    ));
    events.add(SciMidiEvent(
      tick: 0,
      kind: SciMidiEventKind.controlChange,
      channel: ch,
      status: 0xB0 | ch,
      data1: 0x07,
      data2: 127,
    ));
    events.add(SciMidiEvent(
      tick: 0,
      kind: SciMidiEventKind.pitchBend,
      channel: ch,
      status: 0xE0 | ch,
      data1: 0,
      data2: 64,
    ));
    events.add(SciMidiEvent(
      tick: 0,
      kind: SciMidiEventKind.controlChange,
      channel: ch,
      status: 0xB0 | ch,
      data1: 0x40,
      data2: 0,
    ));
    events.add(SciMidiEvent(
      tick: 0,
      kind: SciMidiEventKind.controlChange,
      channel: ch,
      status: 0xB0 | ch,
      data1: 0x0A,
      data2: pans[i],
    ));
  }
  for (var i = 0; i < channels.length; i++) {
    final ch = channels[i];
    events.add(SciMidiEvent(
      tick: i * 30,
      kind: SciMidiEventKind.noteOn,
      channel: ch,
      status: 0x90 | ch,
      data1: notes[i],
      data2: 100,
    ));
  }
  for (var i = 0; i < channels.length; i++) {
    final ch = channels[i];
    events.add(SciMidiEvent(
      tick: 210,
      kind: SciMidiEventKind.noteOff,
      channel: ch,
      status: 0x80 | ch,
      data1: notes[i],
      data2: 0,
    ));
  }
  events.add(const SciMidiEvent(
    tick: 210,
    kind: SciMidiEventKind.endOfTrack,
    channel: -1,
    status: 0xFC,
  ));
  // Tick-sorted, stable by insertion order (setup before note-ons at 0).
  final order = List<int>.generate(events.length, (i) => i);
  order.sort((a, b) {
    final byTick = events[a].tick.compareTo(events[b].tick);
    return byTick != 0 ? byTick : a.compareTo(b);
  });
  final sorted = <SciMidiEvent>[for (final i in order) events[i]];
  return SciMidiTrack(
    variant: SciMidiHeaderVariant.late,
    headerSize: 33,
    flagsByte: 0,
    hasDigitalSample: false,
    sampleFlagSetButNoData: false,
    sample: null,
    channels: channelInits,
    events: sorted,
    cues: const [],
    loopTick: null,
    totalTicks: 210,
    hasEndOfTrack: true,
    isTruncated: false,
    truncatedTail: Uint8List(0),
  );
}

/// Encodes a render result as a 49,716 Hz WAV file using its channel count.
Uint8List sciAdLibRenderToWav(SciAdLibRenderResult result) =>
    WavEncoder.encode(
      samples: result.pcm,
      sampleRate: result.sampleRate,
      numChannels: result.channels,
    );

