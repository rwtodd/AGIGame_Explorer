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

  /// Total rendered frames: `pcm.length`, i.e.
  /// `((renderedTicks + tailTicks) * kOpl2SampleRate / 60).round()`.
  final int totalFrames;

  const SciAdLibRenderResult({
    required this.pcm,
    required this.sampleRate,
    required this.renderedTicks,
    required this.totalFrames,
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
  final output = Int16List(totalFrames);
  if (totalFrames == 0) {
    return SciAdLibRenderResult(
      pcm: output,
      sampleRate: kOpl2SampleRate,
      renderedTicks: endTick,
      totalFrames: totalFrames,
    );
  }
  final chip = Opl2Chip();
  final driver = SciAdLibDriver(
    bank: bank,
    sink: Opl2ChipRegisterSink(chip),
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

  void renderUntil(int target) {
    final t = target.clamp(0, totalFrames);
    while (cursor < t) {
      final n = (t - cursor).clamp(1, sciAdLibRenderBlockFrames);
      chip.generate(block, n);
      output.setRange(cursor, cursor + n, block);
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
    track = SciMidiParser.parse(soundBytes);
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
    ),
    provenance: bankResult.provenance,
    unavailableReason: null,
  );
}

/// Encodes a render result as a mono 49,716 Hz WAV file.
Uint8List sciAdLibRenderToWav(SciAdLibRenderResult result) =>
    WavEncoder.encode(
      samples: result.pcm,
      sampleRate: result.sampleRate,
      numChannels: 1,
    );

