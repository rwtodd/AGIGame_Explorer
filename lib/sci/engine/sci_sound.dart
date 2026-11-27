// SCI0 sound slots, cue timelines, and legacy MIDI translation.
//
// SCI0 sound resources are parsed losslessly into a [SciMidiTrack] (see
// sci_midi_parser.dart); [Sci0SoundParser.parseSound] keeps the historical
// behavior by adapting that model into [AgiSound] notes for the IBM PC
// Speaker, Tandy 1000, and Enhanced playback modes. The adapter below is a
// faithful port of the old flattening parser: single active note per
// channel, header-mask channel selection with the note-occurrence fallback,
// channel-15 cue/loop extraction, and the silent fallback channel are all
// preserved intentionally, as legacy behavior, until a real device backend
// replaces them.

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';

/// SCI music-output device selected by the user (Stage 6b).
///
/// Only the two values below exist in this stage; `auto`,
/// Sound Blaster, and MT-32 are later stages and deliberately not
/// modelled here yet. The legacy device keeps today's translated
/// PC-speaker/Tandy-ish playback through [AgiSoundPlayer]; the AdLib
/// device renders the lossless track through the OPL2 driver instead.
enum SciMusicDevice {
  /// Historical translated playback (default; see [Sci0SoundParser]).
  legacyPsg,

  /// Sierra AdLib / OPL2 FM playback via the patch-bank driver.
  adLibOpl2,
}

/// SCI0 `Sound` object `state` values (ScummVM `SoundStatus`).
class SciSoundStatus {
  static const int stopped = 0;
  static const int initialized = 1;
  static const int paused = 2;
  static const int playing = 3;
}

/// End-of-track / finished-song signal written to the Sound object's `signal`.
const int sciSoundFinished = 0xFFFF;

/// Channel 15 loop point marker program change.
const int kSetSignalLoop = 127;

/// Device mask bits in SCI0 sound resource headers.
class SciSoundHardwareMask {
  static const int mt32 = 0x01;
  static const int casio = 0x02;
  static const int adLib = 0x04;
  static const int cms = 0x08;
  static const int tandy = 0x10;
  static const int pcSpeaker = 0x20;
  static const int amigaMac = 0x40;
}

/// One MIDI-channel-15 cue or the terminator, in 60 Hz SCI ticks from play start.
class SciSoundCue {
  final int tick;
  final int signal;

  const SciSoundCue({required this.tick, required this.signal});

  @override
  String toString() => 'SciSoundCue(tick: $tick, signal: $signal)';
}

/// Parsed SCI0 sound data containing cues and translated [AgiSound].
class SciParsedSound {
  final AgiSound sound;
  final List<SciSoundCue> cues;
  final int? loopTick;
  final int totalTicks;

  /// The lossless track this sound was adapted from, when produced by
  /// [Sci0SoundParser.parseSound]; null for hand-built instances.
  final SciMidiTrack? track;

  const SciParsedSound({
    required this.sound,
    required this.cues,
    this.loopTick,
    required this.totalTicks,
    this.track,
  });
}

/// One SCI0 `DoSound` playlist entry.
class SciSoundSlot {
  SciReg obj;
  int resourceId;
  int status;
  int startTick;
  int loop;
  List<SciSoundCue> cues;
  int nextCue;
  SciParsedSound? parsedSound;
  int priority;
  int volume; // 0..15
  final List<int> signalQueue;

  SciSoundSlot({
    required this.obj,
    this.resourceId = 0,
    this.status = SciSoundStatus.initialized,
    this.startTick = 0,
    this.loop = 1,
    List<SciSoundCue>? cues,
    this.nextCue = 0,
    this.parsedSound,
    this.priority = 0,
    this.volume = 15,
    List<int>? signalQueue,
  })  : cues = cues ?? const [],
        signalQueue = signalQueue ?? [];
}

/// Helper to track active notes during MIDI decoding.
class _ActiveNote {
  final int startTick;
  final int noteNumber;
  final int velocity;

  const _ActiveNote({
    required this.startTick,
    required this.noteNumber,
    required this.velocity,
  });
}

/// Parses SCI0 SOUND resources and translates them to [AgiSound].
///
/// Parsing itself is lossless (see [SciMidiParser]); this class only adapts
/// the resulting [SciMidiTrack] into the legacy note representation.
class Sci0SoundParser {
  static const int headerEarly = 0x11; // 17 bytes
  static const int headerLate = 0x21; // 33 bytes
  static const int endOfTrack = 0xFC;
  static const int stretchDelta = 0xF8;
  static const List<int> midiParamCount = [2, 2, 2, 2, 1, 1, 2];

  /// Returns cue points plus a finished-song terminator.
  static List<SciSoundCue> parse(
    Uint8List data, {
    int? headerSize,
    SciMidiSoundFormat soundFormat = SciMidiSoundFormat.sci0,
  }) {
    return parseSound(
      data,
      headerSize: headerSize,
      soundFormat: soundFormat,
    ).cues;
  }

  /// Parses a sound resource and translates the MIDI events for [mode].
  ///
  /// [soundFormat] selects the SCI0 single-stream layout (default) or the
  /// SCI1 multi-track layout. SCI1 bypasses the SCI0 header-length gate and
  /// passes its format through to [SciMidiParser.parse]; a [FormatException]
  /// from the SCI1 parser propagates (callers such as the kernel catch it).
  static SciParsedSound parseSound(
    Uint8List data, {
    PcmPlaybackMode mode = PcmPlaybackMode.tandy3VoiceNoise,
    int? headerSize,
    SciMidiSoundFormat soundFormat = SciMidiSoundFormat.sci0,
  }) {
    final isSci1 = soundFormat == SciMidiSoundFormat.sci1MultiTrack;
    // Detect header size: 0x21 for SCI0_LATE, 0x11 for SCI0_EARLY
    final effectiveHeader = headerSize ??
        (data.length >= headerLate ? headerLate : (data.length >= headerEarly ? headerEarly : data.length));

    if (!isSci1 && data.length <= effectiveHeader) {
      return SciParsedSound(
        sound: AgiSound(voices: [
          ToneChannel(notes: const [
            AgiNote(startTime: 0, duration: 1, frequencyCount: 0, attenuation: 15),
          ]),
        ]),
        cues: [const SciSoundCue(tick: 0, signal: sciSoundFinished)],
        totalTicks: 0,
      );
    }

    final track = SciMidiParser.parse(
      data,
      headerSize: isSci1 ? null : effectiveHeader,
      soundFormat: soundFormat,
    );
    final tick = track.totalTicks;
    final cues = track.cues
        .map((c) => SciSoundCue(tick: c.tick, signal: c.signal))
        .toList();
    final loopTick = track.loopTick;

    // Target channels from header masks. Tandy and Enhanced share the Tandy
    // bits; PC speaker uses its own bits. maskMatches reproduces the old
    // late (mask byte) / early (low 3 device bits) checks exactly.
    final device = mode == PcmPlaybackMode.ibmPcSingleChannel
        ? SciMidiDevice.pcSpeaker
        : SciMidiDevice.tandyPcJr;
    final targetChannels = <int>{};
    for (final init in track.channels) {
      if (init.maskMatches(track.variant, device)) {
        targetChannels.add(init.channel);
      }
    }

    // Legacy fallback when no header bits select a channel: the first
    // channels with note-ons, in first-occurrence order (never 9 or 15).
    if (targetChannels.isEmpty) {
      final channelsWithNotes = <int>{};
      for (final e in track.events) {
        if (e.kind == SciMidiEventKind.noteOn &&
            e.channel != 15 &&
            e.channel != 9) {
          channelsWithNotes.add(e.channel);
        }
      }
      if (mode == PcmPlaybackMode.ibmPcSingleChannel) {
        if (channelsWithNotes.isNotEmpty) {
          targetChannels.add(channelsWithNotes.first);
        }
      } else {
        targetChannels.addAll(channelsWithNotes.take(3));
      }
    }

    // Single active note per channel (legacy flattening): a note-on finishes
    // the previous note, a note-off only lands when the number matches.
    final channelNotes = <int, List<AgiNote>>{};
    final activeNotes = <int, _ActiveNote>{};
    for (final ch in targetChannels) {
      channelNotes[ch] = <AgiNote>[];
    }

    void finishNote(int ch, int endTick) {
      final active = activeNotes[ch];
      if (active == null) return;
      final dur = endTick - active.startTick;
      if (dur > 0) {
        final freq = 440.0 * pow(2.0, (active.noteNumber - 69) / 12.0);
        final div = (AgiNote.tandyClockDiv32 / freq).round().clamp(1, 1023);
        final att = mode == PcmPlaybackMode.ibmPcSingleChannel
            ? 0
            : ((127 - active.velocity) / 8.5).round().clamp(0, 14);
        channelNotes[ch]!.add(AgiNote(
          startTime: active.startTick,
          duration: dur,
          frequencyCount: div,
          attenuation: att,
        ));
      }
      activeNotes.remove(ch);
    }

    for (final e in track.events) {
      if (e.channel < 0 || !targetChannels.contains(e.channel)) continue;
      if (e.kind == SciMidiEventKind.noteOn) {
        finishNote(e.channel, e.tick);
        activeNotes[e.channel] = _ActiveNote(
          startTick: e.tick,
          noteNumber: e.data1,
          velocity: e.data2,
        );
      } else if (e.kind == SciMidiEventKind.noteOff) {
        final active = activeNotes[e.channel];
        if (active != null && active.noteNumber == e.data1) {
          finishNote(e.channel, e.tick);
        }
      }
    }

    // Finish any notes that were still sounding at the end
    for (final ch in targetChannels) {
      finishNote(ch, tick);
    }

    // Ensure cues list ends with sciSoundFinished. The track's totalTicks is
    // the end-of-track tick when present, matching the old break-at-EOT.
    if (cues.isEmpty || cues.last.signal != sciSoundFinished) {
      cues.add(SciSoundCue(tick: tick, signal: sciSoundFinished));
    }

    // Build ToneChannels
    final toneChannels = <ToneChannel>[];
    for (final ch in targetChannels) {
      final notes = channelNotes[ch]!;
      if (notes.isNotEmpty) {
        // Pad trailing silence if needed so channel spans full track length
        if (notes.last.endTime < tick) {
          notes.add(AgiNote(
            startTime: notes.last.endTime,
            duration: tick - notes.last.endTime,
            frequencyCount: 0,
            attenuation: 15,
          ));
        }
        toneChannels.add(ToneChannel(notes: notes));
      }
    }

    // If no notes produced, provide single silent rest channel
    if (toneChannels.isEmpty) {
      toneChannels.add(ToneChannel(notes: [
        AgiNote(
          startTime: 0,
          duration: tick > 0 ? tick : 1,
          frequencyCount: 0,
          attenuation: 15,
        ),
      ]));
    }

    final sound = AgiSound(voices: toneChannels);
    return SciParsedSound(
      sound: sound,
      cues: cues,
      loopTick: loopTick,
      totalTicks: tick,
      track: track,
    );
  }
}
