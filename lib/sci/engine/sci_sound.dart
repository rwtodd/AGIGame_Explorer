// SCI0 sound slots and cue timelines. Playback is silent; scripts still need
// signal / end-of-track updates that Sierra posted from the MIDI driver.

import 'dart:typed_data';
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

/// One MIDI-channel-15 cue or the terminator, in 60 Hz SCI ticks from play start.
class SciSoundCue {
  final int tick;
  final int signal;

  const SciSoundCue({required this.tick, required this.signal});
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

  SciSoundSlot({
    required this.obj,
    this.resourceId = 0,
    this.status = SciSoundStatus.initialized,
    this.startTick = 0,
    this.loop = 1,
    List<SciSoundCue>? cues,
    this.nextCue = 0,
  }) : cues = cues ?? const [];
}

/// Parses SCI0-late SOUND resources (0x21-byte header, one interleaved MIDI stream).
///
/// Channel-15 program-change events are script signals. `0xFC` ends the track.
class Sci0SoundParser {
  static const int headerLate = 0x21;
  static const int endOfTrack = 0xFC;
  static const int stretchDelta = 0xF8;
  static const List<int> midiParamCount = [2, 2, 2, 2, 1, 1, 2];

  /// Returns cue points plus a finished-song terminator.
  static List<SciSoundCue> parse(Uint8List data, {int headerSize = headerLate}) {
    final cues = <SciSoundCue>[];
    if (data.length <= headerSize) {
      return const [SciSoundCue(tick: 0, signal: sciSoundFinished)];
    }

    var i = headerSize;
    var tick = 0;
    var running = 0;

    while (i < data.length) {
      var b = data[i++];
      if (b == endOfTrack) {
        cues.add(SciSoundCue(tick: tick, signal: sciSoundFinished));
        return cues;
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
        return cues;
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
      i += n;

      final channel = status & 0x0F;
      if (channel == 0x0F && cmd == 4 && p1 != 0x7F) {
        // Program change on channel 15, excluding kSetSignalLoop (127).
        cues.add(SciSoundCue(tick: tick, signal: p1));
      }
    }

    cues.add(SciSoundCue(tick: tick, signal: sciSoundFinished));
    return cues;
  }
}
