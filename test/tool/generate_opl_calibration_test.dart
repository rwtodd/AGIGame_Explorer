import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_opl_calibration.dart' as calib;

void main() {
  group('bank payload', () {
    test('sizes are 1344 (48) and 2690 (96)', () {
      expect(calib.buildBankPayload(instrumentCount: 48).length, 1344);
      expect(calib.buildBankPayload(instrumentCount: 96).length, 2690);
    });

    test('rejects other sizes', () {
      expect(() => calib.buildBankPayload(instrumentCount: 47),
          throwsArgumentError);
    });

    test('96 bank duplicates first 48 after a (0,0) separator', () {
      final b96 = calib.buildBankPayload(instrumentCount: 96);
      expect(b96[1344], 0);
      expect(b96[1345], 0);
      for (var i = 0; i < 1344; i++) {
        expect(b96[1346 + i], b96[i], reason: 'byte $i');
      }
    });

    test('decoder spot-checks PM ladder, feedback ladder, algorithm', () {
      final bank = SciAdlibBank.fromBytes(
          calib.buildBankPayload(instrumentCount: 48));
      expect(bank.instrumentCount, 48);

      // PM ladder 5..11: modulator TL sequence 56,48,40,32,24,16,8.
      const pm = [56, 48, 40, 32, 24, 16, 8];
      for (var i = 0; i < 7; i++) {
        final inst = bank.instruments[5 + i];
        expect(inst.operator0.totalLevel, pm[i],
            reason: 'PM prog ${5 + i}');
        expect(inst.modulator.feedback, 0);
        expect(inst.operator1.totalLevel, 12);
        expect(inst.modulator.algorithm, 0, reason: 'FM prog ${5 + i}');
      }

      // Feedback ladder 12..19: feedback 0..7, only feedback differs.
      SciAdlibInstrument? prev;
      for (var p = 12; p <= 19; p++) {
        final inst = bank.instruments[p];
        expect(inst.modulator.feedback, p - 12, reason: 'feedback prog $p');
        expect(inst.operator0.totalLevel, 16);
        expect(inst.modulator.algorithm, 0);
        if (prev != null) {
          // Operator fields must be identical across the ladder.
          expect(inst.operator0.debugString(),
              equals(prev.operator0.debugString()));
          // Op1 must be identical across the ladder.
          expect(inst.operator1.debugString(),
              equals(prev.operator1.debugString()));
          // Raw records must differ only in byte 2.
          for (var b = 0; b < 28; b++) {
            if (b == 2) {
              expect(inst.rawBytes[b] != prev.rawBytes[b], isTrue);
            } else {
              expect(inst.rawBytes[b], prev.rawBytes[b],
                  reason: 'ladder byte $b');
            }
          }
        }
        prev = inst;
      }

      // Algorithm inversion: program 0 (FM) -> 0, program 1 (additive) -> 1.
      expect(bank.instruments[0].modulator.algorithm, 0);
      expect(bank.instruments[1].modulator.algorithm, 1);
      expect(bank.instruments[0].operator0.totalLevel, 63); // mod silent
      expect(bank.instruments[1].operator0.totalLevel, 63);
      expect(bank.instruments[0].operator1.totalLevel, 12);
      expect(bank.instruments[1].operator1.totalLevel, 12);
      // Waveforms 2..4.
      expect(bank.instruments[2].operator1.waveForm, 1);
      expect(bank.instruments[3].operator1.waveForm, 2);
      expect(bank.instruments[4].operator1.waveForm, 3);
      // Silent control 47: both TL 63.
      expect(bank.instruments[47].operator0.totalLevel, 63);
      expect(bank.instruments[47].operator1.totalLevel, 63);
      // KSR pair shares envelope, differs only in KSR.
      expect(bank.instruments[43].operator1.kbScaleRate, 0);
      expect(bank.instruments[44].operator1.kbScaleRate, 1);
    });
  });

  group('loose-patch wrapper', () {
    test('sound type 4 -> 0x84/0x00, patch type 9 -> 0x89/0x00', () {
      final sound = calib.wrapLoosePatch(
          typeCode: 4, payload: Uint8List.fromList([1, 2, 3]));
      expect(sound, [0x84, 0x00, 1, 2, 3]);
      final patch = calib.wrapLoosePatch(
          typeCode: 9, payload: Uint8List.fromList([4, 5]));
      expect(patch, [0x89, 0x00, 4, 5]);
    });
  });

  group('sound payloads', () {
    for (final format in [calib.SoundHeaderFormat.early, calib.SoundHeaderFormat.late]) {
      final label = format == calib.SoundHeaderFormat.early ? 'early' : 'late';
      test('990 core timbre parses ($label)', () {
        final data = calib.buildSoundResource(resourceNumber: 990, format: format);
        expect(data.segments, hasLength(20));
        expect(data.totalTicks, 2400);
        final track = SciMidiParser.parse(data.payload, headerSize: data.headerSize);
        expect(track.variant, format == calib.SoundHeaderFormat.early
            ? SciMidiHeaderVariant.early
            : SciMidiHeaderVariant.late);
        expect(track.headerSize, format == calib.SoundHeaderFormat.early ? 17 : 33);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, data.totalTicks);
        expect(track.channels[1].requestedVoices, 2);
        expect(track.channels[2].requestedVoices, 2);
        final pcs = track.events
            .where((e) => e.kind == SciMidiEventKind.programChange && e.channel == 1)
            .toList();
        expect(pcs, hasLength(20));
        expect(pcs.map((e) => e.data1), [for (var p = 0; p < 20; p++) p]);
        final ons = track.events
            .where((e) => e.kind == SciMidiEventKind.noteOn && e.channel == 1)
            .toList();
        expect(ons, hasLength(20));
        expect(ons.map((e) => e.data1), List.filled(20, 69));
        expect(ons.map((e) => e.data2).toSet(), {96});
      });

      test('991 envelopes parse ($label)', () {
        final data = calib.buildSoundResource(resourceNumber: 991, format: format);
        expect(data.segments, hasLength(19));
        expect(data.totalTicks, 4110);
        final track = SciMidiParser.parse(data.payload, headerSize: data.headerSize);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, data.totalTicks);
        final pcs = track.events
            .where((e) => e.kind == SciMidiEventKind.programChange && e.channel == 1)
            .toList();
        expect(pcs, hasLength(19));
        expect(pcs.map((e) => e.data1), [for (var p = 20; p <= 38; p++) p]);
        expect(
            track.events.where((e) => e.kind == SciMidiEventKind.noteOn),
            hasLength(19));
      });

      test('992 pitch/KSL/KSR parses ($label)', () {
        final data = calib.buildSoundResource(resourceNumber: 992, format: format);
        expect(data.segments, hasLength(32));
        expect(data.totalTicks, 2640);
        final track = SciMidiParser.parse(data.payload, headerSize: data.headerSize);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, data.totalTicks);
        expect(
            track.events.where((e) => e.kind == SciMidiEventKind.noteOn),
            hasLength(32));
        final pcs = track.events
            .where((e) => e.kind == SciMidiEventKind.programChange)
            .toList();
        expect(pcs, hasLength(32));
      });

      test('993 velocity/pan/bend parses ($label)', () {
        final data = calib.buildSoundResource(resourceNumber: 993, format: format);
        expect(data.segments, hasLength(18));
        expect(data.totalTicks, 1455);
        final track = SciMidiParser.parse(data.payload, headerSize: data.headerSize);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, data.totalTicks);
        // CC 7/10/64 init at tick 0 on used channels.
        final init = track.events
            .where((e) => e.tick == 0 && e.kind == SciMidiEventKind.controlChange)
            .toList();
        expect(init.map((e) => (e.channel, e.data1, e.data2)).toSet(),
            containsAll([
              (1, 7, 127),
              (1, 10, 64),
              (1, 64, 0),
              (2, 7, 127),
              (2, 10, 64),
              (2, 64, 0),
            ]));
        // EnableVelocity CC present with 0 and 127.
        final evCcs = track.events
            .where((e) => e.kind == SciMidiEventKind.controlChange && e.data1 == 0x4E)
            .toList();
        expect(evCcs.map((e) => e.data2), [0, 127]);
        // Velocity groups: velocities present.
        final velocities = track.events
            .where((e) => e.kind == SciMidiEventKind.noteOn && e.channel == 1)
            .map((e) => e.data2)
            .toSet();
        expect(velocities, containsAll([16, 32, 64, 96, 127]));
        // Duets on both channels, note 69/76.
        final duetNotes = track.events
            .where(
                (e) =>
                    e.kind == SciMidiEventKind.noteOn && (e.channel == 1 || e.channel == 2))
            .toList();
        expect(duetNotes.any((e) => e.channel == 2 && e.data1 == 76), isTrue);
        expect(duetNotes.any((e) => e.channel == 2 && e.data1 == 69), isTrue);
        // Bend: program 46, values start 8192, hit 16383, end 0.
        final bends = track.events
            .where((e) => e.kind == SciMidiEventKind.pitchBend)
            .toList();
        expect(bends, hasLength(17));
        expect(bends.first.pitchBendValue, 8192);
        expect(bends.map((e) => e.pitchBendValue), contains(16383));
        expect(bends.last.pitchBendValue, 0);
        expect(bends.map((e) => e.pitchBendValue),
            orderedEquals(
                bends.map((e) => e.pitchBendValue).toList()));
      });
    }

    test('header content differs only in layout', () {
      for (final n in [990, 991, 992, 993]) {
        final early =
            calib.buildSoundResource(resourceNumber: n, format: calib.SoundHeaderFormat.early);
        final late =
            calib.buildSoundResource(resourceNumber: n, format: calib.SoundHeaderFormat.late);
        expect(early.payload[1], 0); // ch0 unused
        expect(early.payload[2], 0x21); // ch1 early byte
        expect(early.payload[3], 0x21); // ch2 early byte
        expect(late.payload[1], 0); // ch0 pair unused
        expect(late.payload[2], 0); // ch0 pair unused
        // Late ch1 at offset 1+1*2=3: [2, 0x04]
        expect(late.payload[3], 2);
        expect(late.payload[4], 0x04);
      }
    });

    test('segments are contiguous and in seconds', () {
      for (final format in calib.SoundHeaderFormat.values) {
        final kit = calib.buildKit(format: format, ninetySix: false);
        for (var n = 990; n <= 993; n++) {
          final segs =
              kit.segments.where((s) => s.resourceNumber == n).toList();
          expect(segs.first.startTick, 0);
          for (var i = 0; i + 1 < segs.length; i++) {
            expect(segs[i].endTick, segs[i + 1].startTick,
                reason: 'resource $n seg $i contiguity');
          }
          for (final s in segs) {
            expect(s.endSeconds, closeTo(s.endTick / 60, 1e-9));
            expect(s.startSeconds, closeTo(s.startTick / 60, 1e-9));
          }
        }
      }
    });
  });

  group('combined track', () {
    for (final format in [calib.SoundHeaderFormat.early, calib.SoundHeaderFormat.late]) {
      final label = format == calib.SoundHeaderFormat.early ? 'early' : 'late';
      test('combined parses ($label)', () {
        final combined =
            calib.buildCombinedSoundResource(format: format);
        final track = SciMidiParser.parse(combined.payload,
            headerSize: combined.headerSize);
        expect(track.variant, format == calib.SoundHeaderFormat.early
            ? SciMidiHeaderVariant.early
            : SciMidiHeaderVariant.late);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, combined.totalTicks);
        expect(combined.segments, hasLength(20 + 19 + 32 + 18));
      });

      test('combined totalTicks is sum of four + 3 gaps ($label)', () {
        final combined =
            calib.buildCombinedSoundResource(format: format);
        var expected = 0;
        for (var n = 990; n <= 993; n++) {
          expected += calib
              .buildSoundResource(resourceNumber: n, format: format)
              .totalTicks;
        }
        expected += 3 * calib.kCombinedGapTicks;
        expect(combined.totalTicks, expected);
        expect(combined.segments.last.endTick, combined.totalTicks);
      });

      test('first former-991 segment offset by 990 total + gap ($label)', () {
        final kit = calib.buildKit(format: format, ninetySix: false);
        final total990 = kit.totalTicksFor(990);
        final first991 = kit.combinedSound.segments
            .firstWhere((s) => s.resourceNumber == 991);
        expect(first991.startTick, total990 + calib.kCombinedGapTicks);
        // Earlier segments (990) keep their original absolute times.
        expect(
            kit.combinedSound.segments
                .firstWhere((s) => s.resourceNumber == 990)
                .startTick,
            0);
        // Manifest lists absolute combined times.
        expect(
            kit.manifestMarkdown,
            contains('## SOUND.001 (combined intro drop-in track'));
        expect(
            kit.manifestMarkdown,
            contains('| 991 | 0 | 20 | 1 | 69 | ${first991.startTick} |'));
      });
    }
  });

  group('kit builder', () {
    test('early/late48/late96 file sets', () {
      final early = calib.buildKit(
          format: calib.SoundHeaderFormat.early, ninetySix: false);
      final late48 =
          calib.buildKit(format: calib.SoundHeaderFormat.late, ninetySix: false);
      final late96 =
          calib.buildKit(format: calib.SoundHeaderFormat.late, ninetySix: true);
      for (final kit in [early, late48, late96]) {
        expect(kit.files.keys,
            containsAll(['PATCH.003', 'SOUND.990', 'SOUND.991', 'SOUND.992', 'SOUND.993', 'SOUND.001']));
        expect(kit.segments, hasLength(20 + 19 + 32 + 18));
        expect(kit.combinedSound.segments, hasLength(20 + 19 + 32 + 18));
        expect(kit.files, hasLength(6));
      }
      expect(early.files['PATCH.003']!.length, 2 + 1344);
      expect(late48.files['PATCH.003']!.length, 2 + 1344);
      expect(late96.files['PATCH.003']!.length, 2 + 2690);
      // Wrappers.
      expect(early.files['PATCH.003']![0], 0x89);
      expect(early.files['PATCH.003']![1], 0x00);
      expect(early.files['SOUND.990']![0], 0x84);
      expect(early.files['SOUND.990']![1], 0x00);
      expect(early.files['SOUND.001']![0], 0x84);
      expect(early.files['SOUND.001']![1], 0x00);
      expect(late96.files['SOUND.001']![0], 0x84);
      // Early vs late sound payload sizes differ by 16 bytes (header).
      for (var n = 990; n <= 993; n++) {
        expect(late48.files['SOUND.$n']!.length - early.files['SOUND.$n']!.length, 16);
      }
      expect(late48.files['SOUND.001']!.length - early.files['SOUND.001']!.length, 16);
      // Manifest mentions header format; tables contain resource headers.
      expect(early.manifestMarkdown, contains('17-byte'));
      expect(late48.manifestMarkdown, contains('33-byte'));
      expect(late96.manifestMarkdown, contains('96 instruments'));
      expect(late48.manifestMarkdown, contains('SOUND.990'));
    });
  });

  group('SciVolumeManager integration', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('opl_calibration_test_');
    });
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('generated files load as loose patches', () {
      final kit = calib.buildKit(
          format: calib.SoundHeaderFormat.late, ninetySix: false);
      // Minimal RESOURCE.MAP with only the sentinel (6 bytes).
      File('${tmp.path}/RESOURCE.MAP')
          .writeAsBytesSync(<int>[0, 0, 0xFF, 0xFF, 0xFF, 0xFF]);
      for (final entry in kit.files.entries) {
        File('${tmp.path}/${entry.key}')
            .writeAsBytesSync(entry.value, flush: true);
      }
      final vm = SciVolumeManager.fromDirectory(tmp.path);
      addTearDown(vm.close);

      final expectedSound990 = Uint8List.sublistView(kit.files['SOUND.990']!, 2);
      final loaded990 = vm.getResource(SciResourceType.sound, 990);
      expect(loaded990, orderedEquals(expectedSound990));

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue);
      expect(result.provenance, SciAdlibBankProvenance.loosePatch);
      expect(result.bank!.instrumentCount, 48);
      expect(result.bank!.containerSize, 1344);
      expect(result.bank!.instruments[1].modulator.algorithm, 1);
      expect(result.bank!.instruments[12].modulator.feedback, 0);
      expect(result.bank!.instruments[19].modulator.feedback, 7);
    });
  });

  group('v2 kit', () {
    test('parser is case-insensitive, rejects unknown', () {
      expect(calib.parseCalibrationKitVersion('v1'),
          calib.CalibrationKitVersion.v1);
      expect(calib.parseCalibrationKitVersion('V1'),
          calib.CalibrationKitVersion.v1);
      expect(calib.parseCalibrationKitVersion('v2'),
          calib.CalibrationKitVersion.v2);
      expect(calib.parseCalibrationKitVersion('V2'),
          calib.CalibrationKitVersion.v2);
      expect(() => calib.parseCalibrationKitVersion('v3'),
          throwsFormatException);
      expect(() => calib.parseCalibrationKitVersion(''),
          throwsFormatException);
    });

    test('bank spot-checks (feedback matrix, wave3, MULT ladder)', () {
      final bank = SciAdlibBank.fromBytes(calib.buildBankPayload(
          instrumentCount: 48,
          kitVersion: calib.CalibrationKitVersion.v2));
      expect(bank.instrumentCount, 48);
      // Reference sine same as v1 program 0.
      expect(bank.instruments[0].operator0.totalLevel, 63);
      expect(bank.instruments[0].operator1.totalLevel, 12);
      expect(bank.instruments[0].operator1.waveForm, 0);
      // Wave3 programs.
      expect(bank.instruments[1].operator1.waveForm, 3);
      expect(bank.instruments[1].operator0.waveForm, 0);
      expect(bank.instruments[1].operator0.totalLevel, 63);
      expect(bank.instruments[2].operator0.waveForm, 3);
      expect(bank.instruments[2].operator1.waveForm, 0);
      expect(bank.instruments[2].operator0.totalLevel, 16);
      expect(bank.instruments[2].modulator.feedback, 0);
      expect(bank.instruments[2].modulator.algorithm, 0);
      // Feedback x mod-TL matrix: fb {5,6,7} x TL {8,24}.
      const fbs = [5, 6, 7];
      const tls = [8, 24];
      for (var p = 3; p <= 8; p++) {
        final i = p - 3;
        final inst = bank.instruments[p];
        expect(inst.modulator.feedback, fbs[i ~/ 2],
            reason: 'feedback prog $p');
        expect(inst.operator0.totalLevel, tls[i % 2],
            reason: 'mod TL prog $p');
        expect(inst.operator1.totalLevel, 12);
        expect(inst.operator0.frequencyMult, 1);
        expect(inst.operator1.frequencyMult, 1);
        expect(inst.modulator.algorithm, 0);
      }
      // Feedback matrix differs only in feedback/mod TL as intended.
      // Programs with same fb share feedback; same TL share TL; operator
      // debug strings equal otherwise (excluding TL/feedback already).
      {
        final a = bank.instruments[3];
        final b = bank.instruments[4];
        expect(a.modulator.feedback, b.modulator.feedback);
        expect(a.operator1.debugString(), b.operator1.debugString());
        for (var byte = 0; byte < 28; byte++) {
          if (byte == 2 || byte == 8) continue;
          expect(a.rawBytes[byte], b.rawBytes[byte],
              reason: 'matrix byte $byte');
        }
      }
      // MULT ladder.
      const mults = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 15];
      for (var p = 31; p <= 42; p++) {
        expect(bank.instruments[p].operator1.frequencyMult,
            mults[p - 31],
            reason: 'MULT prog $p');
        expect(bank.instruments[p].operator0.totalLevel, 63);
      }
      // AM/VIB.
      expect(bank.instruments[43].operator1.amplitudeMod, 1);
      expect(bank.instruments[43].operator1.vibrato, 0);
      expect(bank.instruments[44].operator1.amplitudeMod, 0);
      expect(bank.instruments[44].operator1.vibrato, 1);
      expect(bank.instruments[45].operator1.amplitudeMod, 1);
      expect(bank.instruments[45].operator1.vibrato, 1);
      expect(bank.instruments[47].operator0.totalLevel, 63);
      expect(bank.instruments[47].operator1.totalLevel, 63);
    });

    for (final format in [
      calib.SoundHeaderFormat.early,
      calib.SoundHeaderFormat.late
    ]) {
      final label =
          format == calib.SoundHeaderFormat.early ? 'early' : 'late';
      test('sounds parse ($label)', () {
        final expectedTotals = {990: 2600, 991: 5400, 992: 1890, 993: 1443};
        final expectedSegs = {990: 22, 991: 22, 992: 33, 993: 25};
        for (final n in [990, 991, 992, 993]) {
          final data = calib.buildSoundResource(
              resourceNumber: n,
              format: format,
              kitVersion: calib.CalibrationKitVersion.v2);
          expect(data.totalTicks, expectedTotals[n],
              reason: 'resource $n total');
          expect(data.segments.length, expectedSegs[n],
              reason: 'resource $n segment count');
          final track = SciMidiParser.parse(data.payload,
              headerSize: data.headerSize);
          expect(track.variant,
              format == calib.SoundHeaderFormat.early
                  ? SciMidiHeaderVariant.early
                  : SciMidiHeaderVariant.late);
          expect(track.isTruncated, isFalse);
          expect(track.hasEndOfTrack, isTrue);
          expect(track.totalTicks, data.totalTicks);
        }
        // 990: wave3 programs then matrix programs.
        final d990 = calib.buildSoundResource(
            resourceNumber: 990,
            format: format,
            kitVersion: calib.CalibrationKitVersion.v2);
        expect(d990.segments.map((s) => s.program).toList(),
            [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8]);
        // 991: programs 9..30.
        final d991 = calib.buildSoundResource(
            resourceNumber: 991,
            format: format,
            kitVersion: calib.CalibrationKitVersion.v2);
        expect(d991.segments.map((s) => s.program).toList(),
            [for (var p = 9; p <= 30; p++) p]);
        // 992: MULT ladder + boundary ladder + 9 bend steps.
        final d992 = calib.buildSoundResource(
            resourceNumber: 992,
            format: format,
            kitVersion: calib.CalibrationKitVersion.v2);
        expect(
            d992.segments.take(12).map((s) => s.program).toList(),
            [for (var p = 31; p <= 42; p++) p]);
        expect(d992.segments.skip(12).take(12).map((s) => s.note).toList(),
            ['35', '36', '47', '48', '59', '60', '71', '72', '83', '84', '95', '96']);
        final bends = d992.segments.where((s) => s.purpose.startsWith('bend')).toList();
        expect(bends, hasLength(9));
        expect(bends.map((s) => s.purpose).toList(),
            [0, 2048, 4096, 6144, 8192, 10240, 12288, 14336, 16383].map((v) => 'bend $v').toList());
        final t992 = SciMidiParser.parse(d992.payload,
            headerSize: d992.headerSize);
        final bendEvents = t992.events
            .where((e) => e.kind == SciMidiEventKind.pitchBend)
            .toList();
        expect(bendEvents.map((e) => e.pitchBendValue).toList(),
            [0, 2048, 4096, 6144, 8192, 10240, 12288, 14336, 16383]);
        // First bend is before the note onset at the same tick: a bend
        // and a noteOn share the bend-step start tick, bend first.
        expect(bendEvents.first.tick,
            bends.first.startTick);
        // 993: LFO + polyphony.
        final d993 = calib.buildSoundResource(
            resourceNumber: 993,
            format: format,
            kitVersion: calib.CalibrationKitVersion.v2);
        expect(d993.segments.take(3).map((s) => s.program).toList(), [43, 44, 45]);
        expect(d993.segments[3].purpose, contains('chord'));
        final t993 = SciMidiParser.parse(d993.payload,
            headerSize: d993.headerSize);
        expect(t993.isTruncated, isFalse);
        expect(t993.hasEndOfTrack, isTrue);
        // Pedal events present (CC64 127 then 0).
        final pedals = t993.events
            .where((e) => e.kind == SciMidiEventKind.controlChange && e.data1 == 64)
            .toList();
        expect(pedals.map((e) => e.data2).toList(), containsAllInOrder([127, 0]));
      });

      test('combined v2 totalTicks = sum + 3*60, first 991 offset ($label)',
          () {
        final combined = calib.buildCombinedSoundResource(
            format: format, kitVersion: calib.CalibrationKitVersion.v2);
        var expected = 0;
        for (var n = 990; n <= 993; n++) {
          expected += calib
              .buildSoundResource(
                  resourceNumber: n,
                  format: format,
                  kitVersion: calib.CalibrationKitVersion.v2)
              .totalTicks;
        }
        expected += 3 * calib.kCombinedGapTicks;
        expect(combined.totalTicks, expected);
        expect(combined.segments.last.endTick, combined.totalTicks);
        final total990 = calib
            .buildSoundResource(
                resourceNumber: 990,
                format: format,
                kitVersion: calib.CalibrationKitVersion.v2)
            .totalTicks;
        final first991 = combined.segments
            .firstWhere((s) => s.resourceNumber == 991);
        expect(first991.startTick, total990 + calib.kCombinedGapTicks);
        final track = SciMidiParser.parse(combined.payload,
            headerSize: combined.headerSize);
        expect(track.isTruncated, isFalse);
        expect(track.hasEndOfTrack, isTrue);
        expect(track.totalTicks, combined.totalTicks);
      });
    }

    test('kit file sets include SOUND.001 for v2; manifest states v2', () {
      final early = calib.buildKit(
          format: calib.SoundHeaderFormat.early,
          ninetySix: false,
          kitVersion: calib.CalibrationKitVersion.v2);
      final late96 = calib.buildKit(
          format: calib.SoundHeaderFormat.late,
          ninetySix: true,
          kitVersion: calib.CalibrationKitVersion.v2);
      for (final kit in [early, late96]) {
        expect(kit.kitVersion, calib.CalibrationKitVersion.v2);
        expect(
            kit.files.keys,
            containsAll([
              'PATCH.003',
              'SOUND.990',
              'SOUND.991',
              'SOUND.992',
              'SOUND.993',
              'SOUND.001'
            ]));
        expect(kit.files, hasLength(6));
        expect(kit.manifestMarkdown, contains('Kit version: v2'));
      }
      expect(calib.buildReadmeMarkdown(kitVersion: calib.CalibrationKitVersion.v2),
          contains('Kit version: v2'));
      // v1 manifest/readme unchanged (no v2 stamp).
      final v1kit = calib.buildKit(
          format: calib.SoundHeaderFormat.early, ninetySix: false);
      expect(v1kit.manifestMarkdown, isNot(contains('Kit version: v2')));
      expect(calib.buildReadmeMarkdown(), isNot(contains('Kit version: v2')));
    });
  });
}


