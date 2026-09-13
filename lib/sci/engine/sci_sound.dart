// SCI0 sound slots, cue timelines, and MIDI translation.
//
// Translates SCI0 MIDI streams into AgiSound domain models for playback via
// PcmSynthesizer and AgiSoundPlayer (IBM PC Speaker, Tandy 1000, and Enhanced modes).

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';

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

  const SciParsedSound({
    required this.sound,
    required this.cues,
    this.loopTick,
    required this.totalTicks,
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
class Sci0SoundParser {
  static const int headerEarly = 0x11; // 17 bytes
  static const int headerLate = 0x21;  // 33 bytes
  static const int endOfTrack = 0xFC;
  static const int stretchDelta = 0xF8;
  static const List<int> midiParamCount = [2, 2, 2, 2, 1, 1, 2];

  /// Returns cue points plus a finished-song terminator.
  static List<SciSoundCue> parse(Uint8List data, {int? headerSize}) {
    return parseSound(data, headerSize: headerSize).cues;
  }

  /// Parses an SCI0 sound resource and translates the MIDI events for [mode].
  static SciParsedSound parseSound(
    Uint8List data, {
    PcmPlaybackMode mode = PcmPlaybackMode.tandy3VoiceNoise,
    int? headerSize,
  }) {
    final cues = <SciSoundCue>[];
    int? loopTick;

    // Detect header size: 0x21 for SCI0_LATE, 0x11 for SCI0_EARLY
    final effectiveHeader = headerSize ??
        (data.length >= headerLate ? headerLate : (data.length >= headerEarly ? headerEarly : data.length));

    if (data.length <= effectiveHeader) {
      cues.add(const SciSoundCue(tick: 0, signal: sciSoundFinished));
      return SciParsedSound(
        sound: AgiSound(voices: [
          ToneChannel(notes: const [
            AgiNote(startTime: 0, duration: 1, frequencyCount: 0, attenuation: 15),
          ]),
        ]),
        cues: cues,
        totalTicks: 0,
      );
    }

    // Determine target hardware mask based on mode
    final isLate = effectiveHeader >= headerLate;
    final targetChannels = <int>{};

    if (isLate) {
      for (var ch = 0; ch < 16; ch++) {
        final mask = data[1 + ch * 2 + 1];
        if (mode == PcmPlaybackMode.ibmPcSingleChannel) {
          if ((mask & SciSoundHardwareMask.pcSpeaker) != 0) {
            targetChannels.add(ch);
          }
        } else {
          // Tandy and Enhanced use Tandy channels
          if ((mask & SciSoundHardwareMask.tandy) != 0) {
            targetChannels.add(ch);
          }
        }
      }
    } else {
      for (var ch = 0; ch < 16; ch++) {
        final flags = data[1 + ch] & 0x07;
        if (mode == PcmPlaybackMode.ibmPcSingleChannel) {
          if ((flags & 0x04) != 0) {
            targetChannels.add(ch);
          }
        } else {
          if ((flags & 0x02) != 0) {
            targetChannels.add(ch);
          }
        }
      }
    }

    // First pass to discover channels if targetChannels is empty
    final channelsWithNotes = <int>{};
    {
      var i = effectiveHeader;
      var running = 0;
      while (i < data.length) {
        final b = data[i++];
        if (b == endOfTrack) break;
        if (b == stretchDelta) continue;
        if (i >= data.length) break;
        var status = data[i];
        if (status & 0x80 != 0) {
          running = status;
          i++;
        } else {
          status = running;
        }
        if (status == endOfTrack) break;
        if (status == 0xF0) {
          while (i < data.length && data[i] != 0xF7) {
            i++;
          }
          if (i < data.length) i++;
          continue;
        }
        final cmd = (status >> 4) & 0x7;
        if (cmd >= midiParamCount.length) continue;
        final n = midiParamCount[cmd];
        if (i + n > data.length) break;
        final p2 = (n > 1 && i + 1 < data.length) ? data[i + 1] : 0;
        i += n;
        final ch = status & 0x0F;
        if (ch != 15 && ch != 9 && (cmd == 1 && p2 > 0)) {
          channelsWithNotes.add(ch);
        }
      }
    }

    if (targetChannels.isEmpty) {
      if (mode == PcmPlaybackMode.ibmPcSingleChannel) {
        if (channelsWithNotes.isNotEmpty) {
          targetChannels.add(channelsWithNotes.first);
        }
      } else {
        targetChannels.addAll(channelsWithNotes.take(3));
      }
    }

    // Prepare note accumulation
    final channelNotes = <int, List<AgiNote>>{};
    final activeNotes = <int, _ActiveNote>{};
    for (final ch in targetChannels) {
      channelNotes[ch] = <AgiNote>[];
    }

    var i = effectiveHeader;
    var tick = 0;
    var running = 0;

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

    while (i < data.length) {
      final b = data[i++];
      if (b == endOfTrack) {
        cues.add(SciSoundCue(tick: tick, signal: sciSoundFinished));
        break;
      }
      if (b == stretchDelta) {
        tick += 240;
        continue;
      }
      tick += b;
      if (i >= data.length) break;

      var status = data[i];
      if (status & 0x80 != 0) {
        running = status;
        i++;
      } else {
        status = running;
      }

      if (status == endOfTrack) {
        cues.add(SciSoundCue(tick: tick, signal: sciSoundFinished));
        break;
      }
      if (status == 0xF0) {
        while (i < data.length && data[i] != 0xF7) {
          i++;
        }
        if (i < data.length) i++;
        continue;
      }

      final cmd = (status >> 4) & 0x7;
      if (cmd >= midiParamCount.length) continue;
      final n = midiParamCount[cmd];
      if (i + n > data.length) break;
      final p1 = data[i];
      final p2 = n > 1 ? data[i + 1] : 0;
      i += n;

      final channel = status & 0x0F;

      // Channel 15 cues
      if (channel == 0x0F && cmd == 4) {
        if (p1 == kSetSignalLoop) {
          loopTick = tick;
        } else {
          cues.add(SciSoundCue(tick: tick, signal: p1));
        }
      }

      // Target note events
      if (targetChannels.contains(channel)) {
        final isNoteOn = (cmd == 1 && p2 > 0);
        final isNoteOff = (cmd == 0 || (cmd == 1 && p2 == 0));

        if (isNoteOn) {
          finishNote(channel, tick);
          activeNotes[channel] = _ActiveNote(
            startTick: tick,
            noteNumber: p1,
            velocity: p2,
          );
        } else if (isNoteOff) {
          final active = activeNotes[channel];
          if (active != null && active.noteNumber == p1) {
            finishNote(channel, tick);
          }
        }
      }
    }

    // Finish any notes that were still sounding at the end
    for (final ch in targetChannels) {
      finishNote(ch, tick);
    }

    // Ensure cues list ends with sciSoundFinished
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
    );
  }
}
