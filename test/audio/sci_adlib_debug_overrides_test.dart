// Stage 7: SciAdLibDriver debug-override tests.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

final class RecordingSink implements OplRegisterSink {
  final List<int> addresses = [];
  final List<int> values = [];

  @override
  void writeRegister(int address, int value) {
    addresses.add(address);
    values.add(value);
  }

  @override
  void reset() {
    addresses.clear();
    values.clear();
  }

  int? lastWrite(int address) {
    for (var i = addresses.length - 1; i >= 0; i--) {
      if (addresses[i] == address) return values[i];
    }
    return null;
  }

  void clear() {
    addresses.clear();
    values.clear();
  }
}

Uint8List makeRecord(int tl) {
  final b = Uint8List(28);
  b[0] = 0;
  b[1] = 1;
  b[2] = 0;
  b[3] = 15;
  b[4] = 0;
  b[5] = 1;
  b[6] = 8;
  b[7] = 8;
  b[8] = tl & 0x3f;
  b[13] = 0;
  b[14] = 1;
  b[16] = 15;
  b[18] = 1;
  b[19] = 8;
  b[20] = 8;
  b[21] = tl & 0x3f;
  return b;
}

SciAdlibBank makeBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    // Patch 0 loud (TL 0), patch 7 quiet (TL 60).
    final tl = i == 7 ? 60 : 0;
    data.setRange(28 * i, 28 * i + 28, makeRecord(tl));
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
    events: const [],
    cues: const [],
    loopTick: null,
    totalTicks: 0,
    hasEndOfTrack: false,
    isTruncated: false,
    truncatedTail: Uint8List(0),
  );
}

final class RecordingStereoSink extends StereoOplRegisterSink {
  final List<int> stereoAddresses = [];
  final List<int> stereoLeft = [];
  final List<int> stereoRight = [];

  @override
  void writeRegister(int address, int value) {}

  @override
  void writeRegisterStereo(int address, int leftValue, int rightValue) {
    stereoAddresses.add(address);
    stereoLeft.add(leftValue);
    stereoRight.add(rightValue);
  }

  @override
  void reset() {
    stereoAddresses.clear();
    stereoLeft.clear();
    stereoRight.clear();
  }

  int? lastStereoLeft(int address) {
    for (var i = stereoAddresses.length - 1; i >= 0; i--) {
      if (stereoAddresses[i] == address) return stereoLeft[i];
    }
    return null;
  }

  int? lastStereoRight(int address) {
    for (var i = stereoAddresses.length - 1; i >= 0; i--) {
      if (stereoAddresses[i] == address) return stereoRight[i];
    }
    return null;
  }

  void clear() {
    stereoAddresses.clear();
    stereoLeft.clear();
    stereoRight.clear();
  }
}

SciMidiEvent noteOn(int tick, int ch, int note, int vel) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.noteOn,
      channel: ch,
      status: 0x90 | ch,
      data1: note,
      data2: vel,
    );

SciMidiEvent program(int tick, int ch, int p) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.programChange,
      channel: ch,
      status: 0xC0 | ch,
      data1: p,
    );

SciMidiEvent enableVelocity(int tick, int ch) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.controlChange,
      channel: ch,
      status: 0xB0 | ch,
      data1: 0x4E,
      data2: 1,
    );

({SciAdLibDriver driver, RecordingStereoSink sink}) stereoDriver() {
  final sink = RecordingStereoSink();
  final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
  driver.open();
  driver.initTrack(makeTrack());
  sink.clear();
  return (driver: driver, sink: sink);
}

void main() {
  group('SciAdLibDebugOverrides normalization', () {
    test('empty is const-default with width 1', () {
      const o = SciAdLibDebugOverrides.empty();
      expect(o.stereoWidth, 1.0);
      expect(o.isEmpty, isTrue);
      expect(o.gainSteps, isEmpty);
    });

    test('clamps and drops invalid channels', () {
      final o = SciAdLibDebugOverrides(
        stereoWidth: 1.5,
        gainSteps: {0: 99, 1: -99, 16: 5, -1: 3},
        panOverrides: {0: 200, 1: -5},
        patchOverrides: {0: -7, 2: 30},
        mutedChannels: {0, 99},
        soloChannels: {-2, 3},
      );
      expect(o.stereoWidth, 1.0);
      expect(o.gainSteps, {0: 16, 1: -32});
      expect(o.panOverrides, {0: 127, 1: 0});
      expect(o.patchOverrides, {0: 0, 2: 30});
      expect(o.mutedChannels, {0});
      expect(o.soloChannels, {3});
    });

    test('collections are unmodifiable; copyWith preserves rest', () {
      final o = SciAdLibDebugOverrides(gainSteps: {0: 3});
      expect(() => o.gainSteps[0] = 9, throwsUnsupportedError);
      final copied = o.copyWith(stereoWidth: 0.2);
      expect(copied.stereoWidth, 0.2);
      expect(copied.gainSteps, {0: 3});
    });

    test('equal overrides compare equal with equal hashCodes', () {
      final a = SciAdLibDebugOverrides(
        gainSteps: {1: 4, 2: -3},
        mutedChannels: {5},
      );
      final b = SciAdLibDebugOverrides(
        gainSteps: {2: -3, 1: 4},
        mutedChannels: {5},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('gain/mute/solo', () {
    test('gain steps shift velocity register and renew', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      // Carrier 0x40+0+3 = 0x43. TL 0 => velocity = 15*50? ins velocity
      // is note velocity 50 (100>>1) => 15*50~/15 = 50 => reg 63-50=13.
      expect(sink.lastStereoLeft(0x44), 13);
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(gainSteps: {0: 10}),
      );
      // 50+10 clamped => 60 => reg 3.
      expect(sink.lastStereoLeft(0x44), 3);
    });

    test('gain clamps at 63 and 0', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(gainSteps: {0: 16}),
      );
      // 50+16=66 -> clamp 63 => reg 0.
      expect(sink.lastStereoLeft(0x44), 0);
      expect(driver.voiceVelocity(1), 50);
    });

    test('mute silences and gain cannot revive it', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(gainSteps: {0: 16}, mutedChannels: {0}),
      );
      expect(sink.lastStereoLeft(0x44), 63);
    });

    test('solo non-empty silences other channels', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(soloChannels: {1}),
      );
      expect(sink.lastStereoLeft(0x44), 63);
    });

    test('empty overrides reproduce default trace', () {
      final (driver: first, sink: sinkA) = stereoDriver();
      first.handleEvent(program(0, 0, 0));
      first.handleEvent(enableVelocity(0, 0));
      first.handleEvent(noteOn(0, 0, 60, 100));
      final aLeft = sinkA.lastStereoLeft(0x44);
      final (driver: driver2, sink: sinkB) = stereoDriver();
      driver2.applyDebugOverrides(const SciAdLibDebugOverrides.empty());
      driver2.handleEvent(program(0, 0, 0));
      driver2.handleEvent(enableVelocity(0, 0));
      driver2.handleEvent(noteOn(0, 0, 60, 100));
      expect(sinkB.lastStereoLeft(0x44), aLeft);
    });
  });

  group('pan override and stereo width', () {
    test('pan override hard-left differs sides', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(panOverrides: {0: 0}),
      );
      // pan 0 => right scaled 0 => right reg = 63, left unchanged.
      expect(sink.lastStereoLeft(0x44), 13);
      expect(sink.lastStereoRight(0x44), 63);
    });

    test('stereo width 0 collapses stereo velocity regs', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(SciMidiEvent(
        tick: 0,
        kind: SciMidiEventKind.controlChange,
        channel: 0,
        status: 0xB0,
        data1: 0x0A,
        data2: 0,
      ));
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      sink.clear();
      driver.applyDebugOverrides(SciAdLibDebugOverrides(stereoWidth: 0.0));
      expect(sink.lastStereoLeft(0x44), sink.lastStereoRight(0x44));
    });
  });

  group('patch override', () {
    test('effective patch used for new notes', () {
      final (:driver, :sink) = stereoDriver();
      driver.handleEvent(program(0, 0, 0));
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(patchOverrides: {0: 7}),
      );
      expect(driver.effectivePatch(0), 7);
      driver.handleEvent(noteOn(0, 0, 60, 100));
      // Effective patch 7 selected; quieter timbre still programs.
      expect(driver.voicePatch(1), 7);
      expect(sink.lastStereoLeft(0x44), isNotNull);
    });

    test('active voice reprogrammed without key-off first', () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      driver.initTrack(makeTrack());
      sink.clear();
      driver.handleEvent(program(0, 0, 0));
      driver.handleEvent(enableVelocity(0, 0));
      driver.handleEvent(noteOn(0, 0, 60, 100));
      expect(driver.voicePatch(1), 0);
      sink.clear();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(patchOverrides: {0: 7}),
      );
      expect(driver.voicePatch(1), 7);
      // Pitch/velocity rewritten: a key-on write exists for voice 0.
      final keyOns = sink.values
          .asMap()
          .entries
          .where((e) => sink.addresses[e.key] == 0xB1 && (e.value & 0x20) != 0)
          .length;
      expect(keyOns, greaterThan(0));
      // Clearing reverts.
      sink.clear();
      driver.applyDebugOverrides(const SciAdLibDebugOverrides.empty());
      expect(driver.voicePatch(1), 0);
    });

    test('overrides survive initTrack and open', () {
      final (:driver, :sink) = stereoDriver();
      driver.applyDebugOverrides(
        SciAdLibDebugOverrides(gainSteps: {0: 5}),
      );
      driver.initTrack(makeTrack());
      expect(driver.debugOverrides.gainSteps, {0: 5});
      driver.open();
      expect(driver.debugOverrides.gainSteps, {0: 5});
    });
  });
}
