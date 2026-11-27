// SCI1 multi-track sound parsing tests.
//
// All fixtures are synthetic byte streams built by hand; no game data.
// The reference-gated QFG2 tests assert structural facts only.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_renderer.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

/// Builds an SCI1 resource from [tracks]: for each track, one type byte,
/// one 6-byte descriptor per blob (unknown u16 = 0, data offset, data size),
/// a 0xFF list terminator; then the 0xFF header terminator (unless
/// [includeHeaderTerminator] is false), then the blob bytes.
Uint8List buildSci1(
  List<(int trackType, List<List<int>> blobs)> tracks, {
  bool includeHeaderTerminator = true,
}) {
  var headerSize = includeHeaderTerminator ? 1 : 0;
  for (final (_, blobs) in tracks) {
    headerSize += 1 + blobs.length * 6 + 1;
  }

  final blobOffsets = <int>[];
  var offset = headerSize;
  for (final (_, blobs) in tracks) {
    for (final b in blobs) {
      blobOffsets.add(offset);
      offset += b.length;
    }
  }

  final bb = BytesBuilder();
  var blobIndex = 0;
  for (final (type, blobs) in tracks) {
    bb.add([type]);
    for (final b in blobs) {
      final o = blobOffsets[blobIndex++];
      bb.add([
        0, 0, // unknown u16 (ignored)
        o & 0xFF, (o >> 8) & 0xFF, // data offset u16 LE
        b.length & 0xFF, (b.length >> 8) & 0xFF, // data size u16 LE
      ]);
    }
    bb.add([0xFF]);
  }
  if (includeHeaderTerminator) {
    bb.add([0xFF]);
  }
  for (final (_, blobs) in tracks) {
    for (final b in blobs) {
      bb.add(b);
    }
  }
  return bb.toBytes();
}

void main() {
  group('SCI1 multi-track (synthetic)', () {
    // Shared blobs for the main merge test.
    // A (ch0, poly 2): F8 expansion, then noteOn @240, noteOff @256, FC.
    const blobA = [
      0x00, 0x02, 0xF8, 0x00, 0x90, 60, 100, 0x10, 0x80, 60, 0x00, 0x00, 0xFC
    ];
    // B (ch1, poly 3): noteOn @0, running-status noteOn @10, FC.
    const blobB = [0x01, 0x03, 0x00, 0x91, 64, 90, 0x0A, 65, 80, 0x00, 0xFC];
    // C (ch15, poly 1): cue 42 @0, loop 127 @5, cue 7 @10, FC.
    const blobC = [
      0x0F, 0x01, 0x00, 0xCF, 42, 0x05, 0xCF, 127, 0x05, 0xCF, 7, 0x00, 0xFC
    ];
    // D (ch0, poly 1): noteOn @0, FC.
    const blobD = [0x00, 0x01, 0x00, 0x90, 67, 88, 0x00, 0xFC];
    // E (digital 0xFE, rate 8000, length 1000, PCM [1, 2, 3]).
    const blobE = [
      0xFE, 0x00, 0x40, 0x1F, 0xE8, 0x03, 0, 0, 0, 0, 1, 2, 3
    ];

    Uint8List mainResource() => buildSci1([
          (5, [
            [1, 2, 3, 4]
          ]),
          (0, [blobA, blobB, blobC, blobD, blobE]),
          (7, [
            [9, 9, 9]
          ]),
        ]);

    test('merges descriptors in tick order with running status and cues', () {
      final track = SciMidiParser.parse(
        mainResource(),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );

      expect(track.soundFormat, SciMidiSoundFormat.sci1MultiTrack);
      expect(track.variant, SciMidiHeaderVariant.late);
      expect(track.flagsByte, 0);
      // Header: 8 (track 5) + 32 (track 0) + 8 (track 7) + 1 terminator.
      expect(track.headerSize, 49);

      // Merged events: B/C/D tie at tick 0 in descriptor order, then C,
      // B, C, then A after the F8 expansion (240 ticks).
      expect(track.events.length, 9);
      final e = track.events;
      expect(e[0].kind, SciMidiEventKind.noteOn);
      expect(e[0].tick, 0);
      expect(e[0].channel, 1);
      expect(e[0].status, 0x91);
      expect(e[0].data1, 64);
      expect(e[0].data2, 90);
      expect(e[1].kind, SciMidiEventKind.programChange);
      expect(e[1].tick, 0);
      expect(e[1].channel, 15);
      expect(e[1].data1, 42);
      expect(e[2].kind, SciMidiEventKind.noteOn);
      expect(e[2].tick, 0);
      expect(e[2].channel, 0);
      expect(e[2].data1, 67);
      expect(e[3].kind, SciMidiEventKind.programChange);
      expect(e[3].tick, 5);
      expect(e[3].channel, 15);
      expect(e[3].data1, 127);
      expect(e[4].kind, SciMidiEventKind.noteOn);
      expect(e[4].tick, 10);
      expect(e[4].channel, 1);
      expect(e[4].data1, 65);
      expect(e[4].status, 0x91);
      expect(e[4].usedRunningStatus, isTrue);
      expect(e[5].kind, SciMidiEventKind.programChange);
      expect(e[5].tick, 10);
      expect(e[5].channel, 15);
      expect(e[5].data1, 7);
      expect(e[6].kind, SciMidiEventKind.noteOn);
      expect(e[6].tick, 240);
      expect(e[6].channel, 0);
      expect(e[6].data1, 60);
      expect(e[7].kind, SciMidiEventKind.noteOff);
      expect(e[7].tick, 256);
      expect(e[7].channel, 0);
      expect(e[7].data1, 60);
      expect(e[8].kind, SciMidiEventKind.endOfTrack);
      expect(e[8].tick, 256);

      expect(track.cues.map((c) => '${c.signal}@${c.tick}'), ['42@0', '7@10']);
      expect(track.loopTick, 5);
      expect(track.totalTicks, 256);
      expect(track.hasEndOfTrack, isTrue);
      expect(track.isTruncated, isFalse);
      expect(track.truncatedTail, isEmpty);

      // Synthesized late-equivalent inits: ch0 sums poly 2 + 1.
      expect(track.channels[0].requestedVoices, 3);
      expect(track.channels[0].playMask, 0x04);
      expect(track.channels[0].rawBytes, [3, 0x04]);
      expect(track.channels[0].hasControlFlag, isFalse);
      expect(track.channels[1].requestedVoices, 3);
      expect(track.channels[1].playMask, 0x04);
      expect(track.channels[15].requestedVoices, 1);
      expect(track.channels[15].playMask, 0x04);
      expect(track.channels[2].requestedVoices, 0);
      expect(track.channels[2].playMask, 0x00);
      expect(track.channelMaskFor(SciMidiDevice.adLib), {0, 1, 15});

      // Digital descriptor captured as a sample, never as MIDI.
      expect(track.hasDigitalSample, isTrue);
      expect(track.sampleFlagSetButNoData, isFalse);
      expect(track.sample, isNotNull);
      expect(track.sample!.sampleRate, 8000);
      expect(track.sample!.sampleLength, 1000);
      // Blob layout: 49 + 4 (track5) + 13 (A) + 11 (B) + 13 (C) + 8 (D) = 98.
      expect(track.sample!.payloadOffset, 98);
      expect(track.sample!.rawHeaderBytes.length, 10);
      expect(track.sample!.pcmBytes, [1, 2, 3]);
    });

    test('0xF0 digital/priority pseudo-track is skipped', () {
      final track = SciMidiParser.parse(
        buildSci1([
          (0xF0, [
            [5, 0, 0, 0, 0, 0] // priority 5 plus padding
          ]),
          (0, [
            [0x00, 0x02, 0x00, 0x90, 60, 100, 0x00, 0xFC]
          ]),
        ]),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      expect(track.flagsByte, 0);
      // Header: 8 (F0 track) + 8 (track 0) + 1 = 17.
      expect(track.headerSize, 17);
      final noteOns = track.events.where((e) => e.kind == SciMidiEventKind.noteOn);
      expect(noteOns, hasLength(1));
      expect(noteOns.single.data1, 60);
      expect(track.hasEndOfTrack, isTrue);
    });

    test('missing type-0 track throws FormatException', () {
      final data = buildSci1([
        (5, [
          [1, 2]
        ]),
        (7, [
          [3, 4]
        ]),
      ]);
      expect(
        () => SciMidiParser.parse(
          data,
          soundFormat: SciMidiSoundFormat.sci1MultiTrack,
        ),
        throwsFormatException,
      );
    });

    test('truncated header throws FormatException', () {
      // Unterminated track: type byte, descriptor, then EOF.
      expect(
        () => SciMidiParser.parse(
          Uint8List.fromList([0x00, 0, 0, 0, 0, 0, 0]),
          soundFormat: SciMidiSoundFormat.sci1MultiTrack,
        ),
        throwsFormatException,
      );
      // Incomplete descriptor: track type then 2 bytes only.
      expect(
        () => SciMidiParser.parse(
          Uint8List.fromList([0x00, 1, 2]),
          soundFormat: SciMidiSoundFormat.sci1MultiTrack,
        ),
        throwsFormatException,
      );
      // No header terminator after a complete track.
      expect(
        () => SciMidiParser.parse(
          buildSci1([
            (0, [
              [0x00, 0x02, 0x00, 0xFC]
            ])
          ], includeHeaderTerminator: false),
          soundFormat: SciMidiSoundFormat.sci1MultiTrack,
        ),
        throwsFormatException,
      );
    });

    test('unterminated SysEx plus a mid-event truncation keeps SysEx', () {
      final track = SciMidiParser.parse(
        buildSci1([
          (0, [
            // SysEx F0 43 12 F7, then delta 0x0A note-off 60 with no velocity.
            [0x00, 0x02, 0x00, 0xF0, 0x43, 0x12, 0xF7, 0x0A, 0x80, 60]
          ]),
        ]),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      expect(track.hasEndOfTrack, isFalse);
      expect(track.isTruncated, isTrue);
      expect(track.totalTicks, 10);
      expect(track.events.length, 1);
      expect(track.events.single.kind, SciMidiEventKind.sysEx);
      expect(track.events.single.sysExBytes, [0xF0, 0x43, 0x12, 0xF7]);
      expect(track.truncatedTail, [0x80, 60]);
    });

    test('running-status data before any status truncates that descriptor',
        () {
      final track = SciMidiParser.parse(
        buildSci1([
          (0, [
            [0x00, 0x02, 0x00, 60, 100]
          ]),
        ]),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      expect(track.isTruncated, isTrue);
      expect(track.hasEndOfTrack, isFalse);
      expect(track.events, isEmpty);
      expect(track.truncatedTail, [60, 100]);
      expect(track.totalTicks, 0);
    });

    test('invalid-offset and zero-size descriptors are skipped', () {
      // Hand-built header: track 0 with an offset-beyond descriptor, a
      // zero-size descriptor, and one good ch0 descriptor (noteOn + FC).
      final header = Uint8List(1 + 6 * 3 + 1 + 1);
      header[0] = 0x00;
      final bd = ByteData.sublistView(header);
      // desc0: unknown 0, offset 0xFF00, size 10.
      bd.setUint16(3, 0xFF00, Endian.little);
      bd.setUint16(5, 10, Endian.little);
      // desc1: unknown 0, offset 0, size 0.
      bd.setUint16(9, 0, Endian.little);
      bd.setUint16(11, 0, Endian.little);
      // desc2: unknown 0, offset 21 (header size), size 8.
      bd.setUint16(15, 21, Endian.little);
      bd.setUint16(17, 8, Endian.little);
      header[19] = 0xFF;
      header[20] = 0xFF;
      const goodBlob = [0x00, 0x02, 0x00, 0x90, 60, 100, 0x00, 0xFC];
      final data = BytesBuilder()
        ..add(header)
        ..add(goodBlob);
      final track = SciMidiParser.parse(
        data.toBytes(),
        soundFormat: SciMidiSoundFormat.sci1MultiTrack,
      );
      expect(track.headerSize, 21);
      // The offset-beyond descriptor claimed data, so the parse is truncated.
      expect(track.isTruncated, isTrue);
      // The good descriptor still parses and ended via 0xFC.
      expect(track.events.where((e) => e.kind == SciMidiEventKind.noteOn),
          hasLength(1));
      expect(track.hasEndOfTrack, isTrue);
      expect(track.totalTicks, 0);
    });
  });

  group('Quest for Glory 2 reference', () {
    const qfg2 = 'quest-for-glory-2';

    SciVolumeManager volume() =>
        SciVolumeManager.fromDirectory(referenceGamePath(qfg2));

    test('detects post-SCI01 compression and a 96-instrument volume bank',
        () {
      if (skipIfReferenceGameMissing(qfg2)) return;
      final vm = volume();
      addTearDown(vm.close);

      expect(vm.usesPostSci01Compression, isTrue);
      final bank = sciLoadAdlibBank(vm);
      expect(bank.isAvailable, isTrue);
      expect(bank.bank?.instrumentCount, 96);
    });

    test('sounds 10/12/50 parse as sci1MultiTrack with note-ons', () {
      if (skipIfReferenceGameMissing(qfg2)) return;
      final vm = volume();
      addTearDown(vm.close);

      for (final n in [10, 12, 50]) {
        final bytes = vm.getResource(SciResourceType.sound, n);
        final track = SciMidiParser.parse(
          bytes,
          soundFormat: SciMidiSoundFormat.sci1MultiTrack,
        );
        expect(track.soundFormat, SciMidiSoundFormat.sci1MultiTrack,
            reason: 'sound $n');
        expect(
          track.events.where((e) => e.kind == SciMidiEventKind.noteOn),
          isNotEmpty,
          reason: 'sound $n has no note-ons',
        );
      }
    });

    test('one candidate sound renders non-silent stereo audio', () {
      if (skipIfReferenceGameMissing(qfg2)) return;
      final vm = volume();
      addTearDown(vm.close);

      final result = sciAdLibRenderSound(vm, 10, maxTicks: 300, stereo: true);
      expect(result.isAvailable, isTrue);
      expect(result.render!.channels, 2);
      expect(result.render!.pcm.length, result.render!.totalFrames * 2);
      expect(result.render!.peakAbs, greaterThan(1000));
    });
  });
}
