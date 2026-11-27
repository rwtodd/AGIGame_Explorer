import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/mine_sci_audio_corpus.dart' as miner;

Uint8List recordWithFeedback(int feedback) {
  final rec = Uint8List(kSciAdlibRecordSize);
  for (var i = 0; i < rec.length; i++) {
    rec[i] = 0x11;
  }
  rec[2] = feedback & 0x7;
  rec[12] = 0;
  return rec;
}

SciAdlibInstrument instrumentWithFeedback(int feedback) =>
    SciAdlibInstrument.fromRecord(recordWithFeedback(feedback));

List<SciMidiChannelInit> channels16() => [
      for (var i = 0; i < 16; i++)
        SciMidiChannelInit(
          channel: i,
          rawBytes: [0, 0],
          requestedVoices: 0,
          playMask: 0,
        ),
    ];

SciMidiEvent noteOnEv(int tick, int channel, int note) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.noteOn,
      channel: channel,
      status: 0x90 | channel,
      data1: note,
      data2: 100,
    );

SciMidiEvent noteOffEv(int tick, int channel, int note) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.noteOff,
      channel: channel,
      status: 0x80 | channel,
      data1: note,
      data2: 0,
    );

SciMidiEvent programEv(int tick, int channel, int program) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.programChange,
      channel: channel,
      status: 0xC0 | channel,
      data1: program,
    );

SciMidiEvent ccEv(int tick, int channel, int controller, int value) =>
    SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.controlChange,
      channel: channel,
      status: 0xB0 | channel,
      data1: controller,
      data2: value,
    );

SciMidiEvent pitchBendEv(int tick, int channel, int value) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.pitchBend,
      channel: channel,
      status: 0xE0 | channel,
      data1: value & 0x7F,
      data2: (value >> 7) & 0x7F,
    );

SciMidiTrack trackWithEvents(List<SciMidiEvent> events,
    {int totalTicks = 600}) {
  return SciMidiTrack(
    variant: SciMidiHeaderVariant.late,
    headerSize: 33,
    flagsByte: 0,
    hasDigitalSample: false,
    sampleFlagSetButNoData: false,
    sample: null,
    channels: channels16(),
    events: events,
    cues: const [],
    loopTick: null,
    totalTicks: totalTicks,
    hasEndOfTrack: true,
    isTruncated: false,
    truncatedTail: Uint8List(0),
  );
}

void main() {
  group('patchFeatureKey', () {
    test('identical specs produce equal keys', () {
      expect(
        miner.patchFeatureKey(instrumentWithFeedback(3)),
        miner.patchFeatureKey(instrumentWithFeedback(3)),
      );
    });

    test('instruments differing only in feedback differ in key', () {
      final a = miner.patchFeatureKey(instrumentWithFeedback(0));
      final b = miner.patchFeatureKey(instrumentWithFeedback(5));
      expect(a, isNot(b));
      expect(a, contains('fb=0'));
      expect(b, contains('fb=5'));
    });
  });

  group('analyzeTrackFeatures', () {
    test('detects retrigger, chord, pedal overlap, bend, CC7-waiting-active',
        () {
      final track = trackWithEvents([
        // 6-note chord at tick 0.
        for (var i = 0; i < 6; i++) noteOnEv(0, 0, 60 + i),
        // Pedal down, then a note-off while pedal is held.
        ccEv(10, 0, 0x40, 127),
        noteOffEv(10, 0, 60),
        // CC7 while notes are active on channel 0.
        ccEv(20, 0, 0x07, 100),
        // Pitch bend.
        pitchBendEv(30, 0, 9000),
        // Release the pedal, then retrigger: same channel+pitch 5 ticks
        // after its note-off.
        ccEv(35, 0, 0x40, 0),
        noteOffEv(40, 0, 61),
        noteOnEv(45, 0, 61),
      ]);
      final features = miner.analyzeTrackFeatures(track);
      expect(features.retriggerCount, 1);
      expect(features.sameTickChordMax, 6);
      expect(features.maxSimultaneousNotes, 6);
      expect(features.pedalOverlapCount, 1);
      expect(features.pedalMaxStack, 1);
      expect(features.pitchBendCount, 1);
      expect(features.pitchBendMin, 9000);
      expect(features.pitchBendMax, 9000);
      expect(features.cc7WhileActiveCount, 1);
      expect(features.tags, contains('retrigger'));
      expect(features.tags, contains('chord_ge_6'));
      expect(features.tags, contains('pedal_overlap'));
      expect(features.tags, contains('pitch_bend'));
      expect(features.tags, contains('cc7_while_active'));
    });

    test('program changes while notes active and CC75/CC78 are counted',
        () {
      final track = trackWithEvents([
        noteOnEv(0, 1, 60),
        programEv(10, 1, 7),
        ccEv(20, 1, 0x4B, 2),
        ccEv(30, 1, 0x4E, 1),
      ]);
      final features = miner.analyzeTrackFeatures(track);
      expect(features.programWhileActiveCount, 1);
      expect(features.cc75Count, 1);
      expect(features.cc78Count, 1);
      expect(features.usedPrograms, [7]);
      expect(features.usedChannels, [1]);
      expect(features.tags, contains('program_while_active'));
      expect(features.tags, contains('cc75'));
      expect(features.tags, contains('cc78'));
    });
  });

  group('parseMinerArgs', () {
    test('parses root/out/games/top', () {
      final args = miner.parseMinerArgs([
        '--root',
        'reference_games',
        '--out',
        '/tmp/out',
        '--games',
        'a,b',
        '--top',
        '5',
      ]);
      expect(args.root, 'reference_games');
      expect(args.out, '/tmp/out');
      expect(args.games, {'a', 'b'});
      expect(args.topN, 5);
    });

    test('bad flag path throws FormatException', () {
      expect(
        () => miner.parseMinerArgs([
          '--root',
          'reference_games',
          '--out',
          '/tmp/out',
          '--bogus',
        ]),
        throwsFormatException,
      );
    });

    test('missing out throws FormatException', () {
      expect(
        () => miner.parseMinerArgs(['--root', 'reference_games']),
        throwsFormatException,
      );
    });
  });
}
