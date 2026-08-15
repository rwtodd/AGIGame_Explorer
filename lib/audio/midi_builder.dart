import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// Builder for converting an [AgiSound] resource into a Standard MIDI File (SMF Format 1).
class MidiBuilder {
  const MidiBuilder._();

  /// Converts [sound] into Standard MIDI File (Format 1) binary data.
  ///
  /// [soundNumber]: The resource index for metadata tagging.
  /// [programNumber]: Optional General MIDI instrument patch (0 = Acoustic Grand Piano).
  /// [useAgiLegacyFormula]: Whether to use legacy formula for MIDI note conversion.
  static Uint8List buildMidi({
    required AgiSound sound,
    int soundNumber = 0,
    int programNumber = 0,
    bool useAgiLegacyFormula = false,
  }) {
    if (sound.voices.isEmpty) {
      throw const AgiException(
        'Sound has no tone voices (noise-only); cannot create standard MIDI file.',
      );
    }

    final tracks = <Uint8List>[];

    // Track 0: Tempo and Sound Name
    tracks.add(_buildTempoTrack(soundNumber));

    // Tracks 1..N: One track per tone voice
    for (var i = 0; i < sound.voices.length; i++) {
      final voice = sound.voices[i];
      tracks.add(_buildVoiceTrack(
        voice: voice,
        channel: i,
        voiceNumber: i + 1,
        programNumber: programNumber,
        useAgiLegacyFormula: useAgiLegacyFormula,
      ));
    }

    // Build Header Chunk
    final numTracks = tracks.length;
    final header = BytesBuilder();
    header.add([0x4D, 0x54, 0x68, 0x64]); // "MThd"
    header.add([0x00, 0x00, 0x00, 0x06]); // Chunk size = 6
    header.add([0x00, 0x01]);             // Format 1 (multi-track synchronous)
    header.add([(numTracks >> 8) & 0xFF, numTracks & 0xFF]);
    header.add([0x00, 0x3C]);             // Division = 60 ticks per quarter note (PPQ)

    final output = BytesBuilder();
    output.add(header.toBytes());
    for (final trk in tracks) {
      output.add(trk);
    }

    return output.toBytes();
  }

  static Uint8List _buildTempoTrack(int soundNumber) {
    final trackData = BytesBuilder();

    // Delta time 0: Track Name
    final nameBytes = utf8.encode('AGI Sound Resource $soundNumber');
    _writeVlq(trackData, 0);
    trackData.add([0xFF, 0x03]);
    _writeVlq(trackData, nameBytes.length);
    trackData.add(nameBytes);

    // Delta time 0: Set Tempo to 120 BPM (500,000 microseconds per beat)
    // 60,000,000 / 120 = 500,000 = 0x07A120
    _writeVlq(trackData, 0);
    trackData.add([0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]);

    // Delta time 0: End of Track
    _writeVlq(trackData, 0);
    trackData.add([0xFF, 0x2F, 0x00]);

    return _wrapTrackChunk(trackData.toBytes());
  }

  static Uint8List _buildVoiceTrack({
    required ToneChannel voice,
    required int channel,
    required int voiceNumber,
    required int programNumber,
    required bool useAgiLegacyFormula,
  }) {
    final trackData = BytesBuilder();

    // Delta time 0: Track Name
    final nameBytes = utf8.encode('AGI Voice $voiceNumber');
    _writeVlq(trackData, 0);
    trackData.add([0xFF, 0x03]);
    _writeVlq(trackData, nameBytes.length);
    trackData.add(nameBytes);

    // Delta time 0: Program Change (Instrument)
    if (programNumber >= 0 && programNumber <= 127) {
      _writeVlq(trackData, 0);
      trackData.add([0xC0 | (channel & 0x0F), programNumber & 0x7F]);
    }

    // Collect all Note-On and Note-Off events
    final events = <_MidiRawEvent>[];

    for (final note in voice.notes) {
      if (note.isSilent) continue;

      final noteNum = note.toMidiNoteNumber(useAgiLegacyFormula: useAgiLegacyFormula);
      if (noteNum <= 0) continue;

      final velocity = note.toMidiVelocity();
      // AGI timing: 60 ticks/sec. At 120 BPM with 60 PPQ, 1 beat = 0.5s = 60 ticks.
      // Therefore, 1 second = 120 MIDI ticks. Multiplying AGI ticks by 2 gives exact timing!
      final startTick = note.startTime * 2;
      final endTick = (note.startTime + note.duration) * 2;

      events.add(_MidiRawEvent(
        tick: startTick,
        isNoteOff: false,
        status: 0x90 | (channel & 0x0F),
        data1: noteNum,
        data2: velocity,
      ));

      events.add(_MidiRawEvent(
        tick: endTick,
        isNoteOff: true,
        status: 0x80 | (channel & 0x0F),
        data1: noteNum,
        data2: 0,
      ));
    }

    // Sort events by tick (Note-Off before Note-On if at same tick)
    events.sort((a, b) {
      if (a.tick != b.tick) return a.tick.compareTo(b.tick);
      if (a.isNoteOff && !b.isNoteOff) return -1;
      if (!a.isNoteOff && b.isNoteOff) return 1;
      return 0;
    });

    var currentTick = 0;
    for (final ev in events) {
      final delta = ev.tick - currentTick;
      _writeVlq(trackData, delta);
      trackData.add([ev.status, ev.data1, ev.data2]);
      currentTick = ev.tick;
    }

    // End of Track
    _writeVlq(trackData, 0);
    trackData.add([0xFF, 0x2F, 0x00]);

    return _wrapTrackChunk(trackData.toBytes());
  }

  static Uint8List _wrapTrackChunk(Uint8List data) {
    final chunk = BytesBuilder();
    chunk.add([0x4D, 0x54, 0x72, 0x6B]); // "MTrk"
    final len = data.length;
    chunk.add([
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ]);
    chunk.add(data);
    return chunk.toBytes();
  }

  static void _writeVlq(BytesBuilder builder, int value) {
    var buffer = value & 0x7F;
    final bytes = <int>[];

    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= (value & 0x7F) | 0x80;
    }

    while (true) {
      bytes.add(buffer & 0xFF);
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        break;
      }
    }

    builder.add(bytes);
  }
}

class _MidiRawEvent {
  final int tick;
  final bool isNoteOff;
  final int status;
  final int data1;
  final int data2;

  const _MidiRawEvent({
    required this.tick,
    required this.isNoteOff,
    required this.status,
    required this.data1,
    required this.data2,
  });
}
