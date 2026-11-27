// Stage 7: chip write-log bound, PcmSource debug surface, audition track.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_pcm_source.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_renderer.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

Uint8List makeRecord() {
  final b = Uint8List(28);
  b[0] = 0;
  b[1] = 1;
  b[2] = 0;
  b[3] = 15;
  b[4] = 0;
  b[5] = 1;
  b[6] = 8;
  b[7] = 8;
  b[8] = 0;
  b[13] = 0;
  b[14] = 1;
  b[16] = 15;
  b[18] = 1;
  b[19] = 8;
  b[20] = 8;
  b[21] = 0;
  return b;
}

SciAdlibBank makeBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    data.setRange(28 * i, 28 * i + 28, makeRecord());
  }
  return SciAdlibBank.fromBytes(data);
}

SciMidiTrack makeTrack() {
  final channels = <SciMidiChannelInit>[
    for (var i = 0; i < 16; i++)
      SciMidiChannelInit(
        channel: i,
        rawBytes: i == 0 ? const [2, 0x04] : const [0, 0],
        requestedVoices: i == 0 ? 2 : 0,
        playMask: i == 0 ? 0x04 : 0,
      ),
  ];
  return SciMidiTrack(
    variant: SciMidiHeaderVariant.late,
    headerSize: 33,
    flagsByte: 0,
    hasDigitalSample: false,
    sampleFlagSetButNoData: false,
    sample: null,
    channels: channels,
    events: [
      const SciMidiEvent(
        tick: 0,
        kind: SciMidiEventKind.programChange,
        channel: 0,
        status: 0xC0,
        data1: 0,
      ),
      const SciMidiEvent(
        tick: 0,
        kind: SciMidiEventKind.noteOn,
        channel: 0,
        status: 0x90,
        data1: 60,
        data2: 100,
      ),
    ],
    cues: const [],
    loopTick: null,
    totalTicks: 30,
    hasEndOfTrack: true,
    isTruncated: false,
    truncatedTail: Uint8List(0),
  );
}

void main() {
  group('Opl2Chip write log bound', () {
    test('disabled by default: no records', () {
      final chip = Opl2Chip();
      chip.writeRegister(0x40, 7);
      expect(chip.writeLog, isEmpty);
      expect(chip.writeLogCount, 0);
    });

    test('capacity 4096 with chronological order after wrap', () {
      final chip = Opl2Chip();
      chip.writeLogEnabled = true;
      const cap = Opl2Chip.writeLogCapacity;
      expect(cap, 4096);
      for (var i = 0; i < cap + 5; i++) {
        chip.writeRegister(0x40, i % 256);
      }
      final log = chip.writeLog;
      expect(log.length, cap);
      // Oldest retained is record 5 (records 0..4 dropped).
      expect(log.first.value, 5 % 256);
      expect(log.first.address, 0x40);
      expect(log.last.value, (cap + 4) % 256);
      // Chronological: values increase by 1 modulo 256.
      for (var i = 1; i < log.length; i++) {
        expect(log[i].value, ((i + 5) % 256), reason: 'index $i');
      }
      chip.clearWriteLog();
      expect(chip.writeLog, isEmpty);
      chip.writeRegister(0x40, 9);
      expect(chip.writeLog.length, 1);
      expect(chip.writeLog.first.value, 9);
    });

    test('reset clears the log', () {
      final chip = Opl2Chip();
      chip.writeLogEnabled = true;
      chip.writeRegister(0x40, 1);
      chip.reset();
      expect(chip.writeLog, isEmpty);
    });
  });

  group('SciAdLibPcmSource Stage 7 surface', () {
    test('constructor overrides survive reset', () {
      final bank = makeBank();
      final source = SciAdLibPcmSource(
        makeTrack(),
        bank,
        debugOverrides: SciAdLibDebugOverrides(gainSteps: {0: 5}),
      );
      expect(source.debugOverrides.gainSteps, {0: 5});
      source.reset();
      expect(source.debugOverrides.gainSteps, {0: 5});
      expect(source.debugDriver.debugOverrides.gainSteps, {0: 5});
      source.seekToFrame(10);
      expect(source.debugOverrides.gainSteps, {0: 5});
    });

    test('applyDebugOverrides delegates to driver', () {
      final source = SciAdLibPcmSource(makeTrack(), makeBank());
      source.applyDebugOverrides(
        SciAdLibDebugOverrides(mutedChannels: {0}),
      );
      expect(source.debugDriver.debugOverrides.mutedChannels, {0});
    });

    test('debugSnapshots has 1 entry mono, 2 stereo', () {
      final mono = SciAdLibPcmSource(makeTrack(), makeBank());
      expect(mono.debugSnapshots().length, 1);
      expect(mono.debugSnapshot(), isNotNull);
      final stereo =
          SciAdLibPcmSource(makeTrack(), makeBank(), stereoDualOpl2: true);
      expect(stereo.debugSnapshots().length, 2);
    });

    test('write-log forwarding to both chips', () {
      final stereo =
          SciAdLibPcmSource(makeTrack(), makeBank(), stereoDualOpl2: true);
      expect(stereo.writeLogEnabled, isFalse);
      stereo.writeLogEnabled = true;
      expect(stereo.writeLogEnabled, isTrue);
      stereo.clearWriteLogs();
      expect(stereo.writeLogs, isEmpty);
    });
  });

  group('sciAdLibPatchAuditionTrack', () {
    test('structure: 4 channels, staggered chord, sorted events', () {
      final track = sciAdLibPatchAuditionTrack(3);
      expect(track.variant, SciMidiHeaderVariant.late);
      expect(track.headerSize, 33);
      expect(track.totalTicks, 210);
      expect(track.hasEndOfTrack, isTrue);
      for (final ch in [1, 2, 3, 4]) {
        expect(track.channels[ch].requestedVoices, 2);
        expect(track.channels[ch].playMask, 0x04);
      }
      final noteOns =
          track.events.where((e) => e.kind == SciMidiEventKind.noteOn).toList();
      expect(noteOns.length, 4);
      expect(noteOns.map((e) => e.channel).toList(), [1, 2, 3, 4]);
      expect(noteOns.map((e) => e.data1).toList(), [60, 64, 67, 72]);
      expect(noteOns.map((e) => e.tick).toList(), [0, 30, 60, 90]);
      final noteOffs =
          track.events.where((e) => e.kind == SciMidiEventKind.noteOff).toList();
      expect(noteOffs.length, 4);
      expect(noteOffs.every((e) => e.tick == 210), isTrue);
      final eot =
          track.events.where((e) => e.kind == SciMidiEventKind.endOfTrack).toList();
      expect(eot.length, 1);
      expect(eot.first.tick, 210);
      // Tick-sorted.
      final ticks = track.events.map((e) => e.tick).toList();
      final sorted = [...ticks]..sort();
      expect(ticks, sorted);
      // Program 3 on all four channels.
      final programs = track.events
          .where((e) => e.kind == SciMidiEventKind.programChange)
          .toList();
      expect(programs.length, 4);
      expect(programs.every((e) => e.data1 == 3), isTrue);
    });

    test('negative patch throws', () {
      expect(() => sciAdLibPatchAuditionTrack(-1), throwsArgumentError);
    });

    test('audition renders non-silent audio', () {
      final bank = makeBank();
      final result = sciAdLibRenderTrack(
        sciAdLibPatchAuditionTrack(0),
        bank,
      );
      expect(result.peakAbs, greaterThan(0));
    });
  });
}
