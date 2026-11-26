import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';

/// All fixtures here are synthetic byte streams built by hand; no game data.
Uint8List lateResource(List<int> channelPairs, List<int> events, {int flags = 0}) {
  final header = Uint8List(33);
  header[0] = flags;
  for (var c = 0; c < 16; c++) {
    header[1 + c * 2] = channelPairs[c * 2];
    header[1 + c * 2 + 1] = channelPairs[c * 2 + 1];
  }
  final bb = BytesBuilder()
    ..add(header)
    ..add(events);
  return bb.toBytes();
}

Uint8List earlyResource(List<int> channelBytes, List<int> events, {int flags = 0}) {
  final header = Uint8List(17);
  header[0] = flags;
  for (var c = 0; c < 16; c++) {
    header[1 + c] = channelBytes[c];
  }
  final bb = BytesBuilder()
    ..add(header)
    ..add(events);
  return bb.toBytes();
}

List<int> pairsWith(Map<int, List<int>> byChannel) {
  final pairs = List.filled(32, 0);
  byChannel.forEach((ch, v) {
    pairs[ch * 2] = v[0];
    pairs[ch * 2 + 1] = v[1];
  });
  return pairs;
}

void main() {
  group('headers and channel records', () {
    test('late header decodes voices and play masks', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({
          0: [2, 0x10],
          9: [1, 0x04],
          15: [0, 0x10],
        }),
        [0x00, 0xFC],
      ));
      expect(track.variant, SciMidiHeaderVariant.late);
      expect(track.headerSize, 33);
      expect(track.flagsByte, 0);
      expect(track.channels, hasLength(16));
      expect(track.channels[0].rawBytes, [2, 0x10]);
      expect(track.channels[0].requestedVoices, 2);
      expect(track.channels[0].playMask, 0x10);
      expect(track.channels[0].hasControlFlag, isFalse);
      expect(track.channels[9].requestedVoices, 1);
      expect(track.channels[9].playMask, 0x04);
      // Late voice byte ignores the top bit (AdLib initTrack semantics).
      final masked = SciMidiParser.parse(lateResource(
        pairsWith({
          0: [0x82, 0x04],
        }),
        [0x00, 0xFC],
      ));
      expect(masked.channels[0].requestedVoices, 2);
      expect(masked.channels[0].rawBytes, [0x82, 0x04]);
    });

    test('early header decodes nibbles and control classifications', () {
      final track = SciMidiParser.parse(earlyResource(
        [0x21, 0x22, 0x24, 0x31, 0, 0, 0, 0, 0, 0x29, 0, 0, 0, 0, 0, 0x08],
        [0x00, 0xFC],
      ));
      expect(track.variant, SciMidiHeaderVariant.early);
      expect(track.headerSize, 17);
      expect(track.channels[0].rawBytes, [0x21]);
      expect(track.channels[0].requestedVoices, 2);
      expect(track.channels[0].playMask & 0x07, 0x01); // AdLib bit
      expect(track.channels[1].playMask & 0x07, 0x02); // PCjr bit
      expect(track.channels[2].playMask & 0x07, 0x04); // PC speaker bit
      expect(track.channels[3].playMask & 0x07, 0x01); // MT-32 bit
      expect(track.channels[9].isRhythmPort, isTrue); // bit3 + bit0
      expect(track.channels[15].isControlChannel, isTrue); // bit3, no bit0
      expect(track.channels[15].hasControlFlag, isTrue);
      expect(track.channels[0].isControlChannel, isFalse);
    });

    test('headerSize override selects the early layout on a long resource', () {
      final data = earlyResource(List.filled(16, 0), [
        0x00, 0x90, 60, 100, 0x00, 0xFC,
      ]);
      final track = SciMidiParser.parse(data, headerSize: SciMidiParser.headerEarly);
      expect(track.variant, SciMidiHeaderVariant.early);
      expect(track.headerSize, 17);
      final notes = track.events.where((e) => e.kind == SciMidiEventKind.noteOn);
      expect(notes, hasLength(1));
      expect(notes.single.data1, 60);
    });

    test('resource shorter than its header throws a controlled error', () {
      expect(() => SciMidiParser.parse(Uint8List(10)), throwsFormatException);
      expect(() => SciMidiParser.parse(Uint8List(0)), throwsFormatException);
    });
  });

  group('device channel masks', () {
    test('late play bits follow the driver mask values', () {
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.late, SciMidiDevice.adLib), 0x04);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.late, SciMidiDevice.tandyPcJr), 0x10);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.late, SciMidiDevice.pcSpeaker), 0x20);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.late, SciMidiDevice.mt32), 0x01);
    });

    test('early play bits reduce to the low device bits', () {
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.early, SciMidiDevice.adLib), 0x01);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.early, SciMidiDevice.tandyPcJr), 0x02);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.early, SciMidiDevice.pcSpeaker), 0x04);
      expect(SciMidiChannelInit.devicePlayMask(SciMidiHeaderVariant.early, SciMidiDevice.mt32), 0x01);
    });

    test('late channelMaskFor selects devices, always channel 15', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({
          0: [1, 0x04], // AdLib
          1: [1, 0x10], // Tandy
          2: [1, 0x20], // PC speaker
          3: [1, 0x01], // MT-32
          9: [1, 0x04], // AdLib rhythm port candidate
        }),
        [0x00, 0xFC],
      ));
      expect(track.channelMaskFor(SciMidiDevice.adLib), {0, 9, 15});
      expect(track.channelMaskFor(SciMidiDevice.tandyPcJr), {1, 15});
      expect(track.channelMaskFor(SciMidiDevice.pcSpeaker), {2, 15});
      expect(track.channelMaskFor(SciMidiDevice.mt32), {3, 15});
      // Channel 9 needs the rhythm request for devices without its bit.
      expect(track.channelMaskFor(SciMidiDevice.tandyPcJr, wantsRhythm: true), {1, 9, 15});
    });

    test('early channelMaskFor uses device bits and ignores control flag', () {
      final track = SciMidiParser.parse(earlyResource(
        [0x25, 0x26, 0x2C, 0x21, 0, 0, 0, 0, 0, 0x21, 0, 0, 0, 0, 0, 0x08],
        [0x00, 0xFC],
      ));
      // ch0: bits 0x05 (AdLib+PCspk); ch1: 0x06 (PCjr+PCspk); ch2: 0x04 (PCspk)
      // ch3: 0x01 (AdLib/MT-32); ch9: 0x01 (AdLib/MT-32)
      expect(track.channelMaskFor(SciMidiDevice.adLib), {0, 3, 9, 15});
      expect(track.channelMaskFor(SciMidiDevice.tandyPcJr), {1, 15});
      expect(track.channelMaskFor(SciMidiDevice.pcSpeaker), {0, 1, 2, 15});
      expect(track.channelMaskFor(SciMidiDevice.mt32), {0, 3, 9, 15});
    });

    test('eventsFor filters the stream by device mask', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({
          0: [1, 0x10],
          1: [1, 0x04],
        }),
        [0x00, 0x90, 60, 100, 0x00, 0x91, 64, 90, 0x00, 0xFC],
      ));
      final tandy = track.eventsFor(SciMidiDevice.tandyPcJr);
      expect(tandy.where((e) => e.isNoteOn).map((e) => e.channel), [0]);
      final adLib = track.eventsFor(SciMidiDevice.adLib);
      expect(adLib.where((e) => e.isNoteOn).map((e) => e.channel), [1]);
    });
  });

  group('event stream', () {
    test('note on/off ticks and velocity-0 note-off', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0x90, 60, 100,
          0x0A, 0x90, 62, 0, // velocity-0 note-on is a note-off
          0x00, 0xFC,
        ],
      ));
      expect(track.events, hasLength(3));
      expect(track.events[0].kind, SciMidiEventKind.noteOn);
      expect(track.events[0].tick, 0);
      expect(track.events[0].status, 0x90);
      expect(track.events[1].kind, SciMidiEventKind.noteOff);
      expect(track.events[1].tick, 10);
      expect(track.events[1].data1, 62);
      expect(track.events[2].kind, SciMidiEventKind.endOfTrack);
      expect(track.totalTicks, 10);
      expect(track.hasEndOfTrack, isTrue);
      expect(track.isTruncated, isFalse);
    });

    test('running status expands and is flagged', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0x90, 60, 100,
          0x05, 64, 90, // running status: note 64 on ch0
          0x00, 0xFC,
        ],
      ));
      expect(track.events[1].kind, SciMidiEventKind.noteOn);
      expect(track.events[1].tick, 5);
      expect(track.events[1].channel, 0);
      expect(track.events[1].status, 0x90);
      expect(track.events[1].data1, 64);
      expect(track.events[1].data2, 90);
      expect(track.events[1].usedRunningStatus, isTrue);
      expect(track.events[0].usedRunningStatus, isFalse);
    });

    test('0xF8 deltas add 240 ticks each', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [0xF8, 0xF8, 0x00, 0x90, 60, 100, 0x00, 0xFC],
      ));
      expect(track.events[0].tick, 480);
      expect(track.totalTicks, 480);
    });

    test('polyphony: simultaneous notes on one channel are both kept', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0x90, 60, 100,
          0x00, 64, 90,
          0x00, 67, 80,
          0x00, 0xFC,
        ],
      ));
      final ons = track.events.where((e) => e.isNoteOn).toList();
      expect(ons.map((e) => e.data1), [60, 64, 67]);
      expect(ons.every((e) => e.tick == 0), isTrue);
    });

    test('program change, control, pressure, and pitch bend survive', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0xC3, 17, // program ch3
          0x00, 0xB3, 7, 100, // volume ch3
          0x00, 0xE3, 0x7F, 0x40, // pitch bend ch3 (8191)
          0x00, 0xD3, 55, // channel pressure ch3
          0x00, 0xA3, 60, 44, // poly pressure ch3
          0x00, 0xFC,
        ],
      ));
      expect(track.events[0].kind, SciMidiEventKind.programChange);
      expect(track.events[0].channel, 3);
      expect(track.events[0].data1, 17);
      expect(track.events[1].kind, SciMidiEventKind.controlChange);
      expect(track.events[1].data1, 7);
      expect(track.events[1].data2, 100);
      expect(track.events[2].kind, SciMidiEventKind.pitchBend);
      expect(track.events[2].pitchBendValue, 0x207F); // (0x40 << 7) | 0x7F
      expect(track.events[3].kind, SciMidiEventKind.channelPressure);
      expect(track.events[3].data1, 55);
      expect(track.events[4].kind, SciMidiEventKind.polyPressure);
      expect(track.events[4].data1, 60);
      expect(track.events[4].data2, 44);
      // No channel-15 program change means no cue and no loop.
      expect(track.cues, isEmpty);
      expect(track.loopTick, isNull);
    });

    test('channel-15 program changes become cues and the loop marker', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0xCF, 42,
          0x05, 0xCF, 127, // loop marker at tick 5
          0x05, 0xCF, 7,
          0x00, 0xFC,
        ],
      ));
      expect(track.cues.map((c) => c.signal), [42, 7]);
      expect(track.cues.map((c) => c.tick), [0, 10]);
      expect(track.loopTick, 5);
    });

    test('SysEx payload is preserved verbatim including high-bit bytes', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [
          0x00, 0xF0, 0x43, 0x80, 0xFF, 0x01, 0xF7,
          0x00, 0xFC,
        ],
      ));
      final sysex = track.events.singleWhere((e) => e.kind == SciMidiEventKind.sysEx);
      expect(sysex.tick, 0);
      expect(sysex.channel, -1);
      expect(sysex.status, 0xF0);
      expect(sysex.sysExBytes, [0xF0, 0x43, 0x80, 0xFF, 0x01, 0xF7]);
    });

    test('end-of-track as status byte after a delta', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [0x00, 0x90, 60, 100, 0x05, 0xFC],
      ));
      expect(track.events.last.kind, SciMidiEventKind.endOfTrack);
      expect(track.events.last.tick, 5);
      expect(track.totalTicks, 5);
    });
  });

  group('digital samples', () {
    test('sample payload is split from the MIDI stream', () {
      final sampleHeader = Uint8List(44);
      sampleHeader[14] = 0x40; // rate low
      sampleHeader[15] = 0x1F; // rate high -> 8000
      sampleHeader[32] = 0x2C; // length low
      sampleHeader[33] = 0x01; // length high -> 300
      final data = lateResource(
        pairsWith({}),
        [
          0x00, 0x90, 60, 100,
          0x0A, 0xFC, 0xFC, // end-of-track run
          ...sampleHeader,
          0xFC, 0x90, 0x11, 0x22, // PCM that looks like MIDI
        ],
        flags: 2,
      );
      final track = SciMidiParser.parse(data);
      expect(track.flagsByte, 2);
      expect(track.hasDigitalSample, isTrue);
      expect(track.sampleFlagSetButNoData, isFalse);
      expect(track.sample, isNotNull);
      expect(track.sample!.sampleRate, 8000);
      expect(track.sample!.sampleLength, 300);
      expect(track.sample!.hasCompleteHeader, isTrue);
      expect(track.sample!.rawHeaderBytes.length, 44);
      // Payload starts right after the 0xFC run: 33 + 7 = 40.
      expect(track.sample!.payloadOffset, 40);
      expect(track.sample!.pcmBytes, [0xFC, 0x90, 0x11, 0x22]);
      // MIDI sees only the note-on (tick 0) and the end-of-track (tick 10).
      expect(track.events.map((e) => e.kind),
          [SciMidiEventKind.noteOn, SciMidiEventKind.endOfTrack]);
      expect(track.events[1].tick, 10);
      expect(track.totalTicks, 10);
      expect(track.hasEndOfTrack, isTrue);
    });

    test('flags byte 2 with no data after the FC run parses whole stream', () {
      final data = lateResource(
        pairsWith({}),
        [0x00, 0x90, 60, 100, 0x0A, 0xFC],
        flags: 2,
      );
      final track = SciMidiParser.parse(data);
      expect(track.hasDigitalSample, isFalse);
      expect(track.sampleFlagSetButNoData, isTrue);
      expect(track.sample, isNull);
      expect(track.events.map((e) => e.kind),
          [SciMidiEventKind.noteOn, SciMidiEventKind.endOfTrack]);
    });

    test('truncated sample header exposes raw bytes and null fields', () {
      final data = lateResource(
        pairsWith({}),
        [0x00, 0xFC, 0x01, 0x02, 0x03],
        flags: 2,
      );
      final track = SciMidiParser.parse(data);
      expect(track.hasDigitalSample, isTrue);
      expect(track.sample!.rawHeaderBytes.length, 3);
      expect(track.sample!.sampleRate, isNull);
      expect(track.sample!.sampleLength, isNull);
      expect(track.sample!.pcmBytes, isEmpty);
    });
  });

  group('truncation', () {
    test('truncated event stops parsing without throwing', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [0x00, 0x90, 60, 100, 0x0A, 0x80, 60], // note-off missing velocity
      ));
      expect(track.events.map((e) => e.kind), [SciMidiEventKind.noteOn]);
      expect(track.isTruncated, isTrue);
      expect(track.truncatedTail, [0x80, 60]);
      expect(track.hasEndOfTrack, isFalse);
      expect(track.totalTicks, 10);
    });

    test('unterminated SysEx is kept and marked truncated', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [0x00, 0xF0, 0x43, 0x12],
      ));
      final sysex = track.events.single;
      expect(sysex.kind, SciMidiEventKind.sysEx);
      expect(sysex.sysExBytes, [0xF0, 0x43, 0x12]);
      expect(track.isTruncated, isTrue);
    });

    test('missing end-of-track is tolerated with hasEndOfTrack false', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({}),
        [0x00, 0x90, 60, 100, 0x05],
      ));
      expect(track.hasEndOfTrack, isFalse);
      expect(track.totalTicks, 5);
      expect(track.isTruncated, isFalse);
    });
  });

  group('debug dump', () {
    test('stable text for a small track', () {
      final track = SciMidiParser.parse(lateResource(
        pairsWith({
          0: [2, 0x10],
        }),
        [
          0x00, 0x90, 60, 100,
          0x0A, 0x80, 60, 0,
          0x00, 0xCF, 42,
          0x0A, 0xFC,
        ],
      ));
      final expected = [
        'SCI0 variant=late headerSize=33 flags=0x00 sample=false',
        '  ch0 raw=02 10 voices=2 mask=0x10 ctrl=false',
        for (var c = 1; c < 16; c++)
          '  ch$c raw=00 00 voices=0 mask=0x00 ctrl=false',
        '  @0 noteOn ch=0 note=60 vel=100 status=0x90',
        '  @10 noteOff ch=0 note=60 vel=0 status=0x80',
        '  @10 programChange ch=15 program=42 status=0xcf',
        '  @20 endOfTrack',
        'cues: 42@10',
        'loopTick: null',
        'totalTicks: 20 endOfTrack: true truncated: false',
      ].join('\n');
      expect(track.toDebugString(), expected);
    });
  });

  group('legacy regression (adapter note-for-note)', () {
    List<String> notes(SciParsedSound p) => p.sound.voices
        .map((v) => '[${v.notes.map((n) => '${n.startTime}+${n.duration}f${n.frequencyCount}a${n.attenuation}').join(',')}]')
        .toList();

    test('rich late stream: tandy and PC speaker match frozen output', () {
      final pairs = pairsWith({
        0: [2, 0x10],
        1: [1, 0x10],
        2: [3, 0x30],
        9: [1, 0x30],
      });
      final data = lateResource(pairs, [
        0x00, 0x90, 60, 100,
        0x00, 0x91, 64, 90,
        0x05, 64, 80, // running status
        0x05, 0x80, 64, 0, // mismatched note-off on ch0: ignored
        0x05, 60, 0, // running status note-off ch0
        0xF8, 0x00, 0x92, 65, 77, // stretch: tick 255
        0x00, 0xF0, 0x43, 0x12, 0xF7,
        0x00, 0xE0, 0x00, 0x40,
        0x00, 0xB0, 7, 100,
        0x00, 0xC0, 5,
        0x00, 0xD0, 33,
        0x00, 0xA0, 60, 44,
        0x00, 0x99, 40, 90, // ch9
        0x00, 0x9F, 41, 90, // ch15 (not a tandy/pc target here)
        0x05, 0xCF, 127,
        0x05, 0xCF, 42,
        0x00, 0x93, 62, 80, // ch3: not targeted
        0x0A, 0xFC,
      ]);
      final tandy = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(notes(tandy), [
        '[0+15f428a3,15+260f0a15]',
        '[0+5f339a4,5+270f339a6]',
        '[255+20f320a6]',
        '[255+20f1023a4]',
      ]);
      expect(tandy.cues.map((c) => '${c.signal}@${c.tick}'), ['42@265', '65535@275']);
      expect(tandy.loopTick, 260);
      expect(tandy.totalTicks, 275);
      expect(tandy.track, isNotNull);
      expect(tandy.track!.events,
          contains(predicate<SciMidiEvent>((e) => e.kind == SciMidiEventKind.sysEx)));

      final pc = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.ibmPcSingleChannel);
      expect(notes(pc), [
        '[255+20f320a0]',
        '[255+20f1023a0]',
      ]);
      expect(pc.cues.map((c) => '${c.signal}@${c.tick}'), ['42@265', '65535@275']);
    });

    test('no header masks: fallback takes channels in first-note order', () {
      final data = lateResource(pairsWith({}), [
        0x00, 0x90, 60, 100,
        0x00, 0x91, 64, 90,
        0x00, 0x92, 65, 77,
        0x0A, 0x80, 60, 0,
        0x00, 0xFC,
      ]);
      final tandy = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(tandy.sound.voices, hasLength(3));
      final pc = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.ibmPcSingleChannel);
      expect(pc.sound.voices, hasLength(1));
      expect(pc.sound.voices.single.notes.first.startTime, 0);
      expect(pc.sound.voices.single.notes.first.duration, 10);
      expect(pc.sound.voices.single.notes.first.frequencyCount, 428);
    });

    test('early header stream in all modes', () {
      final data = earlyResource(
        [0x22, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0F],
        [0x00, 0x90, 60, 100, 0x0A, 0x80, 60, 0, 0x00, 0xCF, 7, 0x0A, 0xFC],
      );
      final tandy = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(notes(tandy), ['[0+10f428a3,10+10f0a15]']);
      final pc = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.ibmPcSingleChannel);
      // ch1 has the PC speaker bit but no notes; ch0 note falls through the
      // silent fallback (targets nonempty, no notes produced on ch1).
      expect(notes(pc), ['[0+20f0a15]']);
      expect(tandy.cues.map((c) => '${c.signal}@${c.tick}'), ['7@10', '65535@20']);
    });

    test('retrigger and velocity-0 note-off flatten as before', () {
      final data = lateResource(pairsWith({
        0: [2, 0x10],
      }), [
        0x00, 0x90, 60, 100,
        0x03, 0x90, 62, 90,
        0x03, 0x90, 62, 0,
        0x00, 0x90, 65, 77,
        0x00, 0xFC,
      ]);
      final tandy = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(notes(tandy), ['[0+3f428a3,3+3f381a4]']);
      expect(tandy.totalTicks, 6);
    });

    test('truncated and header-only streams keep legacy output', () {
      final truncated = lateResource(pairsWith({
        0: [2, 0x10],
      }), [
        0x00, 0x90, 60, 100,
        0x0A, 0x80, 60, // truncated note-off
      ]);
      final t = Sci0SoundParser.parseSound(truncated, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(notes(t), ['[0+10f428a3]']);
      expect(t.cues.map((c) => '${c.signal}@${c.tick}'), ['65535@10']);

      final headerOnly = Sci0SoundParser.parseSound(
        Uint8List(Sci0SoundParser.headerLate),
        mode: PcmPlaybackMode.tandy3VoiceNoise,
      );
      expect(notes(headerOnly), ['[0+1f0a15]']);
      expect(headerOnly.totalTicks, 0);
      expect(headerOnly.cues.single.signal, sciSoundFinished);
    });
  });
}
