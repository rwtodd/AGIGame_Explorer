// Stage 5a: Sierra SCI0 AdLib software driver tests.
//
// Tests run against a recording fake [OplRegisterSink] (no chip), with a
// synthetic patch bank built via [SciAdlibBank.fromBytes] (byte-built
// records with distinctive fields) and synthetic [SciMidiTrack] /
// [SciMidiChannelInit] / [SciMidiEvent] objects constructed directly.
// See doc/sci_adlib_mt32_audio_plan.md, Stage 5.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

/// Recording fake [OplRegisterSink]: keeps the ordered write trace.
final class RecordingSink implements OplRegisterSink {
  final List<int> addresses = [];
  final List<int> values = [];

  int get writeCount => addresses.length;

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

  /// Values written to [address], in order.
  List<int> writesTo(int address) => [
        for (var i = 0; i < addresses.length; i++)
          if (addresses[i] == address) values[i],
      ];

  /// Most recent value written to [address], or null.
  int? lastWrite(int address) {
    for (var i = addresses.length - 1; i >= 0; i--) {
      if (addresses[i] == address) return values[i];
    }
    return null;
  }

  int countOf(int address) => writesTo(address).length;

  void clear() {
    addresses.clear();
    values.clear();
  }
}

/// One 28-byte instrument record built from decoded-field values.
Uint8List makeRecord({
  required int kb0,
  required int mult0,
  required int feedback,
  required int attack0,
  required int sustain0,
  required int env0,
  required int decay0,
  required int release0,
  required int tl0,
  required int am0,
  required int vib0,
  required int ksr0,
  required int kb1,
  required int mult1,
  required int attack1,
  required int sustain1,
  required int env1,
  required int decay1,
  required int release1,
  required int tl1,
  required int am1,
  required int vib1,
  required int ksr1,
  required int wave0,
  required int wave1,
  required int algorithmByte,
}) {
  final b = Uint8List(28);
  b[0] = kb0 & 0x3;
  b[1] = mult0 & 0xf;
  b[2] = feedback & 0x7;
  b[3] = attack0 & 0xf;
  b[4] = sustain0 & 0xf;
  b[5] = env0 & 0xff;
  b[6] = decay0 & 0xf;
  b[7] = release0 & 0xf;
  b[8] = tl0 & 0x3f;
  b[9] = am0 & 0xff;
  b[10] = vib0 & 0xff;
  b[11] = ksr0 & 0xff;
  b[12] = algorithmByte & 0xff;
  b[13] = kb1 & 0x3;
  b[14] = mult1 & 0xf;
  b[15] = 0;
  b[16] = attack1 & 0xf;
  b[17] = sustain1 & 0xf;
  b[18] = env1 & 0xff;
  b[19] = decay1 & 0xf;
  b[20] = release1 & 0xf;
  b[21] = tl1 & 0x3f;
  b[22] = am1 & 0xff;
  b[23] = vib1 & 0xff;
  b[24] = ksr1 & 0xff;
  b[25] = 0;
  b[26] = wave0 & 0x3;
  b[27] = wave1 & 0x3;
  return b;
}

/// Generic per-instrument filler: distinct decoded fields per index so
/// replaced records are easy to distinguish by their register bytes.
Uint8List genericRecord(int i) => makeRecord(
      kb0: i & 3,
      mult0: (i * 3) & 15,
      feedback: i & 7,
      attack0: (i * 5) & 15,
      sustain0: (i * 7) & 15,
      env0: i & 1,
      decay0: (i * 11) & 15,
      release0: (i * 13) & 15,
      tl0: (i * 17) & 63,
      am0: i & 1,
      vib0: (i >> 1) & 1,
      ksr0: (i >> 2) & 1,
      kb1: (i >> 2) & 3,
      mult1: (i * 7) & 15,
      attack1: (i * 3) & 15,
      sustain1: (i * 5) & 15,
      env1: (i >> 1) & 1,
      decay1: (i * 7) & 15,
      release1: (i * 11) & 15,
      tl1: (i * 19) & 63,
      am1: (i >> 2) & 1,
      vib1: (i >> 1) & 1,
      ksr1: i & 1,
      wave0: i & 3,
      wave1: (i >> 2) & 3,
      algorithmByte: i.isOdd ? 1 : 0,
    );

/// Instruments used by hand-computed golden assertions.
const int kSpecialFm = 5;
const int kSpecialAdditive = 6;

/// Hand-specified instrument record (FM, algorithm 0 since byte 12 != 0).
/// Fields chosen so every encoded register byte is hand-checkable,
/// including the raw-byte flag fields.
Uint8List specialFmRecord() => makeRecord(
      kb0: 2,
      mult0: 3,
      feedback: 4,
      attack0: 9,
      sustain0: 10,
      env0: 0xFF,
      decay0: 6,
      release0: 7,
      tl0: 20,
      am0: 0x02,
      vib0: 0,
      ksr0: 1,
      kb1: 1,
      mult1: 1,
      attack1: 12,
      sustain1: 3,
      env1: 0,
      decay1: 4,
      release1: 5,
      tl1: 10,
      am1: 0,
      vib1: 0x80,
      ksr1: 0,
      wave0: 2,
      wave1: 1,
      algorithmByte: 1,
    );

/// Hand-specified instrument record (additive, algorithm 1 since byte
/// 12 == 0).
Uint8List specialAdditiveRecord() => makeRecord(
      kb0: 0,
      mult0: 1,
      feedback: 2,
      attack0: 15,
      sustain0: 0,
      env0: 0,
      decay0: 1,
      release0: 2,
      tl0: 0,
      am0: 0,
      vib0: 0,
      ksr0: 0,
      kb1: 3,
      mult1: 2,
      attack1: 1,
      sustain1: 2,
      env1: 1,
      decay1: 3,
      release1: 4,
      tl1: 30,
      am1: 1,
      vib1: 1,
      ksr1: 1,
      wave0: 0,
      wave1: 3,
      algorithmByte: 0,
    );

SciAdlibBank makeBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    final rec = i == kSpecialFm
        ? specialFmRecord()
        : i == kSpecialAdditive
            ? specialAdditiveRecord()
            : genericRecord(i);
    data.setRange(28 * i, 28 * i + 28, rec);
  }
  return SciAdlibBank.fromBytes(data);
}

SciMidiTrack makeTrack({
  required SciMidiHeaderVariant variant,
  int flags = 0,
  required List<SciMidiChannelInit> channels,
}) {
  assert(channels.length == 16);
  return SciMidiTrack(
    variant: variant,
    headerSize: variant == SciMidiHeaderVariant.late ? 33 : 17,
    flagsByte: flags,
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

SciMidiChannelInit chLate(int channel, {int voices = 0, int mask = 0}) =>
    SciMidiChannelInit(
      channel: channel,
      rawBytes: [voices, mask],
      requestedVoices: voices,
      playMask: mask,
    );

SciMidiChannelInit chEarly(int channel,
        {int voices = 0, int mask = 0, bool control = false}) =>
    SciMidiChannelInit(
      channel: channel,
      rawBytes: [(voices << 4) | mask | (control ? 0x08 : 0)],
      requestedVoices: voices,
      playMask: mask,
      hasControlFlag: control,
    );

List<SciMidiChannelInit> silentChannels16() => [
      for (var i = 0; i < 16; i++) chLate(i),
    ];

List<SciMidiChannelInit> silentEarlyChannels16() => [
      for (var i = 0; i < 16; i++) chEarly(i),
    ];

SciMidiEvent noteOnEv(int tick, int channel, int note, int velocity) =>
    SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.noteOn,
      channel: channel,
      status: 0x90 | channel,
      data1: note,
      data2: velocity,
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

/// A driver with a one-voice late layout on channel 0 (2 voices), opened.
({SciAdLibDriver driver, RecordingSink sink}) lateDriverWithVoices(
    {int channel = 0, int voices = 2, int flags = 0}) {
  final sink = RecordingSink();
  final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
  driver.open();
  final channels = silentChannels16();
  channels[channel] = chLate(channel, voices: voices, mask: 0x04);
  driver.initTrack(makeTrack(variant: SciMidiHeaderVariant.late, flags: flags, channels: channels));
  sink.clear();
  return (driver: driver, sink: sink);
}

void main() {
  group('open/reset', () {
    test('writes the open register sequence 0xBD=0, 0x08=0, 0x01=0x20',
        () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      expect(
        sink.addresses,
        [0xBD, 0x08, 0x01],
      );
      expect(sink.values, [0, 0, 0x20]);
    });

    test('resets channel/voice state to reference defaults', () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      // Constructor (pre-open, pre-initTrack) defaults.
      expect(driver.channelPatch(0), 0);
      expect(driver.channelVolume(0), 63);
      expect(driver.channelPan(0), 64);
      expect(driver.channelHoldPedal(0), 0);
      expect(driver.channelPitchWheel(0), 8192);
      expect(driver.channelEnableVelocity(0), isFalse);
      expect(driver.masterVolume, 15);
      expect(driver.voiceMappedChannel(0), -1);
      expect(driver.voiceNote(0), -1);
    });
  });

  group('initTrack late', () {
    void trackSetup(
        SciAdLibDriver driver, RecordingSink sink, List<SciMidiChannelInit> channels,
        {int flags = 0}) {
      driver.initTrack(makeTrack(
          variant: SciMidiHeaderVariant.late, flags: flags, channels: channels));
    }

    test('assigns voices for AdLib-masked channels honoring counts', () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      final channels = silentChannels16();
      channels[0] = chLate(0, voices: 3, mask: 0x04);
      channels[1] = chLate(1, voices: 2, mask: 0x10); // PCjr, not AdLib
      channels[2] = chLate(2, voices: 0, mask: 0x04); // zero count: none
      trackSetup(driver, sink, channels);
      expect(driver.channelMappedVoices(0), 3);
      expect(driver.channelMappedVoices(1), 0);
      expect(driver.channelMappedVoices(2), 0);
      expect(driver.voiceMappedChannel(0), 0);
      expect(driver.voiceMappedChannel(1), 0);
      expect(driver.voiceMappedChannel(2), 0);
      expect(driver.voiceMappedChannel(3), -1);
      expect(driver.channelPatch(0), 13);
      expect(driver.channelPatch(5), 13);
    });

    test('caps late assignment at 9 voices', () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      final channels = silentChannels16();
      channels[0] = chLate(0, voices: 6, mask: 0x04);
      channels[1] = chLate(1, voices: 6, mask: 0x04);
      trackSetup(driver, sink, channels);
      var total = 0;
      for (var v = 0; v < 9; v++) {
        if (driver.voiceMappedChannel(v) != -1) total++;
      }
      expect(total, 9);
      expect(driver.channelMappedVoices(0), 6);
      expect(driver.channelMappedVoices(1), 3);
    });

    test('flags byte 2 still assigns for late headers', () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      final channels = silentChannels16();
      channels[0] = chLate(0, voices: 2, mask: 0x04);
      trackSetup(driver, sink, channels, flags: 2);
      expect(driver.channelMappedVoices(0), 2);
    });
  });

  group('initTrack early', () {
    SciAdLibDriver earlyDriver(List<SciMidiChannelInit> channels) {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(
        bank: makeBank(),
        sink: sink,
        profile: SciAdlibProfile.sci0Early,
      );
      driver.open();
      driver.initTrack(makeTrack(
          variant: SciMidiHeaderVariant.early, channels: channels));
      return driver;
    }

    test('bit 0 selects AdLib; upper nibble is the voice count', () {
      final channels = silentEarlyChannels16();
      channels[0] = chEarly(0, voices: 3, mask: 0x01);
      channels[1] = chEarly(1, voices: 2, mask: 0x02); // not AdLib
      final driver = earlyDriver(channels);
      expect(driver.channelMappedVoices(0), 3);
      expect(driver.channelMappedVoices(1), 0);
      expect(driver.voiceMappedChannel(0), 0);
      expect(driver.voiceMappedChannel(2), 0);
      expect(driver.voiceMappedChannel(3), -1);
    });

    test('capped at 8 voices for the early profile', () {
      final channels = silentEarlyChannels16();
      channels[0] = chEarly(0, voices: 6, mask: 0x01);
      channels[1] = chEarly(1, voices: 6, mask: 0x01);
      final driver = earlyDriver(channels);
      var total = 0;
      for (var v = 0; v < 9; v++) {
        if (driver.voiceMappedChannel(v) != -1) total++;
      }
      expect(total, 8);
      expect(driver.channelMappedVoices(0), 6);
      expect(driver.channelMappedVoices(1), 2);
    });

    test('voice count 0x0F assigns nothing', () {
      final channels = silentEarlyChannels16();
      channels[0] = chEarly(0, voices: 0x0F, mask: 0x01);
      final driver = earlyDriver(channels);
      expect(driver.channelMappedVoices(0), 0);
    });

    test('control flag with AdLib bit assigns nothing; control-only '
        'channels get no voices', () {
      final channels = silentEarlyChannels16();
      channels[0] = chEarly(0, voices: 4, mask: 0x01, control: true);
      channels[15] = chEarly(15, voices: 2, mask: 0x00, control: true);
      final driver = earlyDriver(channels);
      expect(driver.channelMappedVoices(0), 0);
      expect(driver.channelMappedVoices(15), 0);
      expect(driver.voiceMappedChannel(0), -1);
    });
  });

  group('initTrack caps rule', () {
    test('nonzero flags byte skips assignment and leaves state untouched',
        () {
      final sink = RecordingSink();
      final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
      driver.open();
      // First, a valid late track assigns voices.
      final channels = silentChannels16();
      channels[0] = chLate(0, voices: 2, mask: 0x04);
      driver.initTrack(
          makeTrack(variant: SciMidiHeaderVariant.late, channels: channels));
      expect(driver.channelMappedVoices(0), 2);

      // Flags byte 1 (late) is not 2: no assignment, no reset.
      final channels2 = silentChannels16();
      channels2[3] = chLate(3, voices: 4, mask: 0x04);
      driver.initTrack(makeTrack(
          variant: SciMidiHeaderVariant.late,
          flags: 1,
          channels: channels2));
      expect(driver.channelMappedVoices(0), 2);
      expect(driver.channelMappedVoices(3), 0);
      expect(driver.voiceMappedChannel(0), 0);
    });
  });

  group('noteOn golden registers', () {
    // One mapped voice (voice 0) so register expectations pin to voice 0.
    test('patch operator bytes for FM instrument (algorithm 0)', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(programEv(0, 0, kSpecialFm));
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      // Operator 0 (mod offset 0) for voice 0. Its 0x40 TL keeps the patch
      // value because FM patches have no modulator velocity write.
      expect(sink.lastWrite(0x40), (2 << 6) | 20);
      expect(sink.countOf(0x40), 1);
      expect(sink.lastWrite(0x60), (9 << 4) | 6);
      expect(sink.lastWrite(0x80), (10 << 4) | 7);
      expect(sink.lastWrite(0x20), 0x80 | 0x20 | 0x10 | 3);
      expect(sink.lastWrite(0xE0), 2);
      // Operator 1 (carrier offset 3): 0x63..0xE3 keep patch values, while
      // 0x43 is the velocity TL ((1<<6)|(63-53), see velocity tests).
      expect(sink.countOf(0x43), 2);
      expect(sink.lastWrite(0x43), (1 << 6) | (63 - 53));
      expect(sink.lastWrite(0x63), (12 << 4) | 4);
      expect(sink.lastWrite(0x83), (3 << 4) | 5);
      expect(sink.lastWrite(0x23), 0x40 | 1);
      expect(sink.lastWrite(0xE3), 1);
      // Feedback/algorithm: feedback 4, algorithm 0 -> 8.
      expect(sink.lastWrite(0xC0), (4 << 1) | 0);
    });

    test('additive instrument (algorithm 1) writes modulator velocity TL',
        () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(programEv(0, 0, kSpecialAdditive));
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      expect(sink.lastWrite(0xC0), (2 << 1) | 1);
      // Modulator TL: patch TL first (0x40 once from setOperator), then
      // overwritten by the additive velocity write.
      // kb0=0, tl0=0 -> vel (0<<6)|(63 - (63 - 0)) = 0.
      expect(sink.countOf(0x40), 2);
      expect(sink.lastWrite(0x40), 0);
      // Carrier TL: patch TL then velocity TL.
      // kb1=3, tl1=30 -> insVel 33 -> TL (3<<6) | (63 - 33).
      expect(sink.countOf(0x43), 2);
      expect(sink.lastWrite(0x43), (3 << 6) | (63 - 33));
    });

    test('A4 (69) pitch: block follows the rule, fnum near formula', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      final a0 = sink.lastWrite(0xA0)!;
      final b0 = sink.lastWrite(0xB0)!;
      final fnum = a0 | ((b0 & 0x03) << 8);
      final block = (b0 >> 2) & 0x07;
      final expectedFnum =
          (440 * math.pow(2, 20 - block) / 49716).round();
      expect(block, 4); // floor(69/12) - 1
      expect((fnum - expectedFnum).abs(), lessThanOrEqualTo(4));
      expect(b0 & 0x20, 0x20); // key on
    });

    test('C4 (60) pitch: block follows the rule, fnum near formula', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 60, 100));
      final a0 = sink.lastWrite(0xA0)!;
      final b0 = sink.lastWrite(0xB0)!;
      final fnum = a0 | ((b0 & 0x03) << 8);
      final block = (b0 >> 2) & 0x07;
      final freq = 440 * math.pow(2, (60 - 69) / 12);
      final expectedFnum = (freq * math.pow(2, 20 - block) / 49716).round();
      expect(block, 4); // floor(60/12) - 1
      expect((fnum - expectedFnum).abs(), lessThanOrEqualTo(4));
      expect(b0 & 0x20, 0x20);
    });

    test('carrier TL velocity with velocity enable off', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(programEv(0, 0, kSpecialFm));
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      // master 15 -> v = 18 -> capped 15; insVel = 63 - 10 = 53;
      // result = 15 * 53 ~/ 15 = 53. TL reg = (1<<6) | (63 - 53).
      expect(sink.lastWrite(0x43), (1 << 6) | (63 - 53));
    });
  });

  group('velocity behavior', () {
    test('CC 0x4E enables note velocity in the TL register', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      // Default patch 13 (genericRecord(13)): carrier kb = (13>>2)&3 = 3,
      // carrier tl = (13*19)&63 = 247&63 = 55, insVel = 63-55 = 8,
      // result = 15*8~/15 = 8; TL = (3<<6) | (63 - 8).
      expect(sink.lastWrite(0x43), (3 << 6) | (63 - 8));

      // Enable velocity; note vel 100 -> stored 50.
      driver.handleEvent(ccEv(1, 0, 0x4E, 1));
      sink.clear();
      driver.handleEvent(noteOnEv(2, 0, 70, 60));
      // insVel = 30; result = 15*30~/15 = 30; TL = (3<<6) | (63-30).
      expect(sink.lastWrite(0x43), (3 << 6) | (63 - 30));

      // Disable again.
      driver.handleEvent(ccEv(3, 0, 0x4E, 0));
      sink.clear();
      driver.handleEvent(noteOnEv(4, 0, 71, 60));
      // insVel = 63 - 55 = 8; result = 15*8~/15 = 8.
      expect(sink.lastWrite(0x43), (3 << 6) | (63 - 8));
    });

    test('master volume change renews the TL register', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      sink.clear();
      driver.setMasterVolume(0);
      // v = 0 -> result 0 -> TL = (3<<6) | 63.
      expect(sink.lastWrite(0x43), (3 << 6) | 63);
      // Pitch registers are rewritten too (renew).
      expect(sink.countOf(0xA0), 1);
      expect(sink.countOf(0xB0), 1);
    });

    test('CC 0x07 stores volume >> 1', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      sink.clear();
      driver.handleEvent(ccEv(1, 0, 0x07, 100));
      expect(driver.channelVolume(0), 50);
      // Renewal rewrote the active note.
      expect(sink.countOf(0xB0), 1);
    });
  });

  group('allocation', () {
    test('round-robin across mapped voices', () {
      final (:driver, :sink) = lateDriverWithVoices();
      // Reference scan starts at lastVoice+1: 60 lands on voice 1,
      // 62 on voice 0.
      driver.handleEvent(noteOnEv(0, 0, 60, 100));
      expect(driver.voiceNote(1), 60);
      driver.handleEvent(noteOnEv(1, 0, 62, 100));
      expect(driver.voiceNote(0), 62);
      driver.handleEvent(noteOffEv(2, 0, 60));
      // Next free voice scanning from voice 0: voice 1 again.
      driver.handleEvent(noteOnEv(3, 0, 64, 100));
      expect(driver.voiceNote(1), 64);
    });

    test('retrigger of the same note reuses the voice, key off then on',
        () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      sink.clear();
      driver.handleEvent(noteOnEv(1, 0, 69, 100));
      expect(driver.voiceNote(1), 69);
      expect(driver.voiceNote(0), -1);
      final b1Writes = sink.writesTo(0xB1);
      expect(b1Writes.length, 2);
      expect(b1Writes[0] & 0x20, 0); // key off
      expect(b1Writes[1] & 0x20, 0x20); // key on
    });

    test('stealing picks the oldest voice when all mapped voices are busy',
        () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 0, 60, 100)); // voice 1 at tick 0
      driver.handleEvent(noteOnEv(1, 0, 62, 100)); // voice 0 at tick 1
      driver.handleEvent(noteOnEv(5, 0, 64, 100)); // steals voice 1 (oldest)
      expect(driver.voiceNote(1), 64);
      expect(driver.voiceNote(0), 62);
    });

    test('same-tick notes are never stolen (second note dropped)', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(10, 0, 60, 100));
      sink.clear();
      driver.handleEvent(noteOnEv(10, 0, 62, 100));
      expect(driver.voiceNote(0), 60);
      expect(sink.writeCount, 0);
    });

    test('unmapped channel notes find no voice and write nothing', () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 3, 69, 100));
      expect(sink.writeCount, 0);
    });

    test('notes 11 and 108 are ignored; 12 and 107 are accepted', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 11, 100));
      driver.handleEvent(noteOnEv(0, 0, 108, 100));
      expect(sink.writeCount, 0);
      driver.handleEvent(noteOnEv(1, 0, 12, 100));
      expect(driver.voiceNote(0), 12);
      driver.handleEvent(noteOffEv(2, 0, 12));
      driver.handleEvent(noteOnEv(2, 0, 107, 100));
      expect(driver.voiceNote(0), 107);
    });
  });

  group('sustain pedal', () {
    test('noteOff with pedal holds the note; pedal release keys off', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      driver.handleEvent(ccEv(1, 0, 0x40, 127));
      sink.clear();
      driver.handleEvent(noteOffEv(2, 0, 69));
      expect(driver.voiceSustained(0), isTrue);
      expect(driver.voiceNote(0), 69);
      expect(sink.countOf(0xB0), 0);

      sink.clear();
      driver.handleEvent(ccEv(3, 0, 0x40, 0));
      final b0 = sink.lastWrite(0xB0)!;
      expect(b0 & 0x20, 0);
      expect(driver.voiceNote(0), -1);
      expect(driver.voiceSustained(0), isFalse);
    });
  });

  group('pitch bend', () {
    test('bend up raises the pitch registers; center restores', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      final baseB0 = sink.lastWrite(0xB0)!;
      final baseFnum = sink.lastWrite(0xA0)! | ((baseB0 & 0x03) << 8);
      final baseBlock = (baseB0 >> 2) & 0x07;

      sink.clear();
      final bentValue = 8192 + 4096; // +6 semitones
      driver.handleEvent(pitchBendEv(1, 0, bentValue));
      expect(driver.channelPitchWheel(0), bentValue);
      final bentB0 = sink.lastWrite(0xB0)!;
      final bentFnum = sink.lastWrite(0xA0)! | ((bentB0 & 0x03) << 8);
      final bentBlock = (bentB0 >> 2) & 0x07;
      // Higher effective pitch: block rises and the derived frequency
      // (fnum scaled by block) exceeds the base.
      expect(bentBlock, baseBlock + 1);
      double derivedFrequency(int fnum, int block) =>
          fnum * 49716 / math.pow(2, 20 - block);
      expect(
        derivedFrequency(bentFnum, bentBlock),
        greaterThan(derivedFrequency(baseFnum, baseBlock)),
      );

      sink.clear();
      driver.handleEvent(pitchBendEv(2, 0, 8192));
      final centerFnum =
          sink.lastWrite(0xA0)! | ((sink.lastWrite(0xB0)! & 0x03) << 8);
      expect(centerFnum, baseFnum);
      final centerBlock = (sink.lastWrite(0xB0)! >> 2) & 0x07;
      expect(centerBlock, baseBlock);
    });
  });

  group('CC 0x4B voice mapping', () {
    test('increase grows and decrease shrinks the mapped voice count', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      expect(driver.channelMappedVoices(0), 1);
      driver.handleEvent(ccEv(0, 0, 0x4B, 3));
      expect(driver.channelMappedVoices(0), 3);
      expect(driver.voiceMappedChannel(1), 0);
      expect(driver.voiceMappedChannel(2), 0);

      driver.handleEvent(ccEv(1, 0, 0x4B, 1));
      expect(driver.channelMappedVoices(0), 1);
    });

    test('release keys off a sounding voice when shrinking past free ones',
        () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 2);
      driver.handleEvent(noteOnEv(0, 0, 69, 100)); // on voice 1
      sink.clear();
      driver.handleEvent(ccEv(1, 0, 0x4B, 1));
      expect(driver.channelMappedVoices(0), 1);
      // The free voice (voice 0) was released first; the sounding voice
      // stays mapped.
      expect(driver.voiceMappedChannel(1), 0);
      expect(driver.voiceMappedChannel(0), -1);
      expect(driver.voiceNote(1), 69);

      driver.handleEvent(ccEv(2, 0, 0x4B, 0));
      expect(driver.channelMappedVoices(0), 0);
      expect(driver.voiceNote(1), -1);
    });
  });

  group('all notes off', () {
    test('CC 0x7B keys off all notes on the channel', () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 0, 60, 100)); // voice 1
      driver.handleEvent(noteOnEv(1, 0, 62, 100)); // voice 0
      sink.clear();
      driver.handleEvent(ccEv(2, 0, 0x7B, 0));
      expect(driver.voiceNote(0), -1);
      expect(driver.voiceNote(1), -1);
      expect(sink.countOf(0xB0) + sink.countOf(0xB1), 2);
      for (final v in [...sink.writesTo(0xB0), ...sink.writesTo(0xB1)]) {
        expect(v & 0x20, 0);
      }
    });

    test('allNotesOff() keys off every sounding voice', () {
      final (:driver, :sink) = lateDriverWithVoices();
      // (allocation detail covered by the 0x7B test above)
      driver.handleEvent(noteOnEv(0, 0, 60, 100));
      driver.handleEvent(noteOnEv(1, 0, 62, 100));
      sink.clear();
      driver.allNotesOff();
      expect(driver.voiceNote(0), -1);
      expect(driver.voiceNote(1), -1);
      expect(sink.countOf(0xB0) + sink.countOf(0xB1), 2);
    });
  });

  group('invalid program', () {
    test('program beyond the bank substitutes instrument 0', () {
      final (:driver, :sink) = lateDriverWithVoices(voices: 1);
      driver.handleEvent(programEv(0, 0, 100));
      driver.handleEvent(noteOnEv(1, 0, 69, 100));
      expect(driver.voicePatch(0), 0);
      final bank = driver.bank;
      final expectedC0 = (bank.instruments[0].modulator.feedback << 1) |
          bank.instruments[0].modulator.algorithm;
      expect(sink.lastWrite(0xC0), expectedC0);
    });
  });

  group('playEnabled', () {
    test('false: patch not switched, velocity registers written as 63',
        () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(programEv(0, 0, kSpecialFm));
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      // Reference allocation: this note sounds on voice 1.
      expect(driver.voicePatch(1), kSpecialFm);

      driver.playEnabled = false;
      sink.clear();
      // A new note on voice 0 would require a patch switch
      // (program 6 != current patch 13) that must be skipped.
      driver.handleEvent(programEv(1, 0, kSpecialAdditive));
      driver.handleEvent(noteOnEv(2, 0, 70, 100));
      expect(driver.voicePatch(0), 13);
      // No patch operator writes for the skipped setPatch.
      expect(sink.countOf(0x60), 0);
      // Velocity writes use velocity 0 -> 63 - 0 in the TL field.
      // Default patch 13 carrier kb = 3.
      expect(sink.lastWrite(0x43), (3 << 6) | 63);

      driver.playEnabled = true;
    });
  });

  group('ignored events', () {
    test('aftertouch, SysEx, system, and end-of-track write nothing',
        () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 0, 69, 100));
      sink.clear();
      driver.handleEvent(SciMidiEvent(
          tick: 1,
          kind: SciMidiEventKind.polyPressure,
          channel: 0,
          status: 0xA0,
          data1: 69,
          data2: 50));
      driver.handleEvent(SciMidiEvent(
          tick: 1,
          kind: SciMidiEventKind.channelPressure,
          channel: 0,
          status: 0xD0,
          data1: 50));
      driver.handleEvent(SciMidiEvent(
          tick: 1,
          kind: SciMidiEventKind.sysEx,
          channel: -1,
          status: 0xF0,
          sysExBytes: const [0xF0, 0x43, 0xF7]));
      driver.handleEvent(SciMidiEvent(
          tick: 1,
          kind: SciMidiEventKind.endOfTrack,
          channel: -1,
          status: 0xFC));
      expect(sink.writeCount, 0);
    });

    test('channel 15 events are safe (no unmapped voice)', () {
      final (:driver, :sink) = lateDriverWithVoices();
      driver.handleEvent(noteOnEv(0, 15, 69, 100));
      expect(sink.writeCount, 0);
    });
  });

  group('chip adapter', () {
    test('Opl2ChipRegisterSink forwards writes to the chip', () {
      chipTest();
    });
  });
}

/// Exercises the Opl2Chip adapter with a real chip.
void chipTest() {
  final chip = Opl2Chip();
  final sink = Opl2ChipRegisterSink(chip);
  final driver = SciAdLibDriver(bank: makeBank(), sink: sink);
  driver.open();
  expect(chip.readRegister(0xBD), 0);
  expect(chip.readRegister(0x08), 0);
  expect(chip.readRegister(0x01), 0x20);
  final channels = silentChannels16();
  channels[0] = chLate(0, voices: 2, mask: 0x04);
  driver.initTrack(
      makeTrack(variant: SciMidiHeaderVariant.late, channels: channels));
  driver.handleEvent(noteOnEv(0, 0, 69, 100));
  // The note sounded on voice 1 (reference round-robin starts there).
  expect(chip.readRegister(0xB1) & 0x20, 0x20);
  expect(chip.snapshot().channels[1].keyOn, isTrue);
}
