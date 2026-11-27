// Stage 8: SciMidiSample playable-window helpers (SCI0 null start/end,
// SCI1 start/end decode, ScummVM window math, durationTicks).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

SciMidiSample makeSample({
  int? rate = 11025,
  int? length,
  int? start,
  int? end,
  int pcmLen = 100,
}) {
  return SciMidiSample(
    rawHeaderBytes: Uint8List(44),
    sampleRate: rate,
    sampleLength: length ?? pcmLen,
    sampleStart: start,
    sampleEnd: end,
    payloadOffset: 0,
    pcmBytes: Uint8List(pcmLen),
  );
}

Uint8List lateResource(List<int> events, {int flags = 0}) {
  final header = Uint8List(33);
  header[0] = flags;
  final bb = BytesBuilder()
    ..add(header)
    ..add(events);
  return bb.toBytes();
}

/// SCI1 resource: one type-0 (AdLib) track; descriptor table has a MIDI
/// descriptor (silent, end-of-track only) and a 0xFE digital descriptor
/// whose 10-byte header carries rate/length/start/end.
Uint8List sci1WithSample({
  required int rate,
  required int length,
  required int start,
  required int end,
  required int pcmLen,
  int midiSize = 4,
}) {
  // Layout: type byte, two 6-byte descriptors, 0xFF list terminator,
  // 0xFF header terminator = 15 bytes. MIDI data at 15, sample after it.
  const headerLen = 15;
  final midiOffset = headerLen;
  final sampleOffset = headerLen + midiSize;
  final total = sampleOffset + 10 + pcmLen;
  final data = Uint8List(total);
  final bd = ByteData.sublistView(data);
  data[0] = 0x00; // type-0 track
  // descriptor 1: unknown u16, offset, size -> MIDI at midiOffset
  bd.setUint16(1 + 2, midiOffset, Endian.little);
  bd.setUint16(1 + 4, midiSize, Endian.little);
  // descriptor 2: unknown u16, offset, size -> sample at sampleOffset
  bd.setUint16(7 + 2, sampleOffset, Endian.little);
  bd.setUint16(7 + 4, 10 + pcmLen, Endian.little);
  data[13] = 0xFF; // end of descriptor list
  data[14] = 0xFF; // end of header
  // MIDI descriptor: [chan 0, poly 0] then delta 0, end-of-track.
  data[midiOffset] = 0;
  data[midiOffset + 1] = 0;
  data[midiOffset + 2] = 0; // delta
  data[midiOffset + 3] = 0xFC;
  // Digital descriptor: raw byte 0xFE, byte1 0, then 4 u16 words.
  data[sampleOffset] = 0xFE;
  data[sampleOffset + 1] = 0;
  bd.setUint16(sampleOffset + 2, rate, Endian.little);
  bd.setUint16(sampleOffset + 4, length, Endian.little);
  bd.setUint16(sampleOffset + 6, start, Endian.little);
  bd.setUint16(sampleOffset + 8, end, Endian.little);
  for (var i = 0; i < pcmLen; i++) {
    data[sampleOffset + 10 + i] = 200;
  }
  return data;
}

void main() {
  group('SciMidiSample window helpers', () {
    test('SCI0 (null start/end): whole payload is playable', () {
      final s = makeSample(rate: 11000, length: 7415, pcmLen: 7415);
      expect(s.sampleStart, isNull);
      expect(s.sampleEnd, isNull);
      expect(s.effectiveStart, 0);
      expect(s.playableLength, 7415);
      expect(s.playableOffset, 0);
      expect(s.isPlayable, isTrue);
      // ceil(7415*60/11000) = ceil(40.445..) = 41
      expect(s.durationTicks, 41);
    });

    test('declared length clamps to the payload actually present', () {
      final s = makeSample(length: 500, pcmLen: 100);
      expect(s.playableLength, 100);
      final tiny = makeSample(length: 10, pcmLen: 100);
      expect(tiny.playableLength, 10);
    });

    test('null/zero sampleLength falls back to payload length', () {
      expect(makeSample(length: null, pcmLen: 64).playableLength, 64);
      expect(makeSample(length: 0, pcmLen: 64).playableLength, 64);
    });

    test('SCI1 start skips leading bytes; end word excludes trailing bytes', () {
      // base 100, start 10, end 90 -> 100-10-(100-90)=80
      final s = makeSample(start: 10, end: 90, pcmLen: 100);
      expect(s.effectiveStart, 10);
      expect(s.playableOffset, 10);
      expect(s.playableLength, 80);
    });

    test('end word 0 or outside the window excludes nothing', () {
      expect(makeSample(start: 0, end: 0, pcmLen: 100).playableLength, 100);
      expect(makeSample(start: 0, end: 100, pcmLen: 100).playableLength, 100);
      expect(makeSample(start: 0, end: 250, pcmLen: 100).playableLength, 100);
      expect(makeSample(start: 0, end: null, pcmLen: 100).playableLength, 100);
    });

    test('start beyond the window clamps to empty (not playable)', () {
      final s = makeSample(start: 200, pcmLen: 100);
      expect(s.effectiveStart, 100);
      expect(s.playableLength, 0);
      expect(s.isPlayable, isFalse);
      expect(s.durationTicks, 0);
    });

    test('durationTicks: ceil(length*60/rate), 0 for invalid rate', () {
      expect(makeSample(rate: 6000, length: 100, pcmLen: 100).durationTicks, 1);
      // ceil(101*60/6000) = ceil(1.01) = 2
      expect(makeSample(rate: 6000, length: 101, pcmLen: 101).durationTicks, 2);
      expect(makeSample(rate: null).durationTicks, 0);
      expect(makeSample(rate: 0).durationTicks, 0);
      expect(makeSample(rate: -5).durationTicks, 0);
      expect(makeSample(rate: 11025, length: 0, pcmLen: 0).isPlayable, isFalse);
    });

    test('total and pure: degenerate inputs never throw', () {
      final s = makeSample(rate: null, length: null, start: -9, end: -3, pcmLen: 10);
      expect(s.playableLength, 10);
      expect(s.isPlayable, isFalse);
      expect(s.durationTicks, 0);
    });
  });

  group('SCI0 sample decode', () {
    test('SCI0 sample leaves start/end null', () {
      final sampleHeader = Uint8List(44);
      sampleHeader[14] = 0x40; // rate low
      sampleHeader[15] = 0x1F; // rate high -> 8000
      sampleHeader[32] = 0x0A; // length 10
      final track = SciMidiParser.parse(lateResource(
        [0x00, 0xFC, ...sampleHeader, ...List.filled(10, 200)],
        flags: 2,
      ));
      final s = track.sample!;
      expect(s.sampleStart, isNull);
      expect(s.sampleEnd, isNull);
      expect(s.playableLength, 10);
      expect(s.isPlayable, isTrue);
    });
  });

  group('SCI1 sample decode', () {
    test('start/end words are decoded from the 10-byte header', () {
      final track = SciMidiParser.parse(
        sci1WithSample(rate: 22050, length: 200, start: 10, end: 180, pcmLen: 200),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      final s = track.sample!;
      expect(s.sampleRate, 22050);
      expect(s.sampleLength, 200);
      expect(s.sampleStart, 10);
      expect(s.sampleEnd, 180);
      // 200 - 10 - (200-180) = 170
      expect(s.playableLength, 170);
    });

    test('zero start/end words decode as 0 (present), not null', () {
      final track = SciMidiParser.parse(
        sci1WithSample(rate: 22050, length: 50, start: 0, end: 0, pcmLen: 50),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      final s = track.sample!;
      expect(s.sampleStart, 0);
      expect(s.sampleEnd, 0);
      expect(s.playableLength, 50);
    });
  });

  group('hasAudibleNotes', () {
    test('true only with a velocity>0 note-on', () {
      final withNotes = SciMidiParser.parse(lateResource([
        0x00, 0x90, 60, 100, 0x00, 0xFC,
      ]));
      expect(withNotes.hasAudibleNotes, isTrue);
      final silent = SciMidiParser.parse(lateResource([
        0x00, 0xFC,
      ]));
      expect(silent.hasAudibleNotes, isFalse);
    });
  });
}
