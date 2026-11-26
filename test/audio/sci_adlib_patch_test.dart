// Stage 3: SCI AdLib patch-bank parser, embedded-driver extractor, and
// loader tests. All fixtures are synthetic (no Sierra bytes asserted).
//
// See doc/sci_adlib_mt32_audio_plan.md (Stages 0 and 3).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

/// Builds one 28-byte instrument record from 28 literal byte values,
/// with positions laid out as the format defines them.
Uint8List recordFrom(List<int> bytes) {
  assert(bytes.length == kSciAdlibRecordSize);
  return Uint8List.fromList(bytes);
}

/// Builds a 1344-byte bank whose record [i] is filled with the value
/// [fill]+i in every byte (distinct per record), except that record
/// [specialIndex] uses the literal [recordFrom] bytes given.
Uint8List buildBank48({
  required int specialIndex,
  required List<int> specialRecord,
  int fill = 0x10,
}) {
  final data = Uint8List(kSciAdlibBank48Size);
  for (var i = 0; i < kSciAdlibInstruments48; i++) {
    final rec = i == specialIndex
        ? recordFrom(specialRecord)
        : Uint8List.fromList(List<int>.filled(28, (fill + i) & 0xff));
    data.setRange(28 * i, 28 * i + 28, rec);
  }
  return data;
}

/// Builds a 2690-byte bank: first half records at 28*i, separator bytes
/// at 1344..1345, second-half records at 2+28*i. Each half's special
/// record is a literal byte list; all other records use [fill].
Uint8List buildBank96({
  required int firstHalfSpecialIndex,
  required List<int> firstHalfSpecialRecord,
  required int secondHalfSpecialIndex,
  required List<int> secondHalfSpecialRecord,
  List<int>? separator,
  int fill = 0x20,
}) {
  final data = Uint8List(kSciAdlibBank96Size);
  for (var i = 0; i < kSciAdlibInstruments48; i++) {
    final rec = i == firstHalfSpecialIndex
        ? recordFrom(firstHalfSpecialRecord)
        : Uint8List.fromList(List<int>.filled(28, (fill + i) & 0xff));
    data.setRange(28 * i, 28 * i + 28, rec);
  }
  final sep = separator ?? const [0xAB, 0xCD];
  data[1344] = sep[0];
  data[1345] = sep[1];
  for (var i = 48; i < kSciAdlibInstruments96; i++) {
    final rec = i == secondHalfSpecialIndex
        ? recordFrom(secondHalfSpecialRecord)
        : Uint8List.fromList(List<int>.filled(28, (fill + i) & 0xff));
    data.setRange(2 + 28 * i, 2 + 28 * i + 28, rec);
  }
  return data;
}

/// A 28-byte record designed so every decoded field has a distinct,
/// hand-checkable expected value, including masking behavior and the
/// inverted algorithm flag (record byte 12 = 0 -> algorithm 1).
const List<int> kSpecialRecordAlg1 = [
  // operator 0 block (bytes 0..12)
  0x07, // [0] kbScaleLevel: 0x07 & 0x3 = 3
  0x1A, // [1] frequencyMult: 0x1A & 0xf = 10
  0x0D, // [2] modulator feedback: 0x0D & 0x7 = 5
  0x2B, // [3] attackRate: 0x2B & 0xf = 11
  0x3C, // [4] sustainLevel: 0x3C & 0xf = 12
  0x05, // [5] envelopeType: raw 5
  0x4E, // [6] decayRate: 0x4E & 0xf = 14
  0x5F, // [7] releaseRate: 0x5F & 0xf = 15
  0x7D, // [8] totalLevel: 0x7D & 0x3f = 61
  0xA1, // [9] amplitudeMod: raw 0xA1
  0xB2, // [10] vibrato: raw 0xB2
  0xC3, // [11] kbScaleRate: raw 0xC3
  0x00, // [12] algorithm flag: 0 -> algorithm 1 (inverted)
  // operator 1 block (bytes 13..25)
  0x03, // [0] kbScaleLevel: 3
  0x0F, // [1] frequencyMult: 15
  0xFF, // [2] NOT decoded (raw byte preserved)
  0x00, // [3] attackRate: 0
  0x01, // [4] sustainLevel: 1
  0x02, // [5] envelopeType: 2
  0x03, // [6] decayRate: 3
  0x04, // [7] releaseRate: 4
  0x15, // [8] totalLevel: 0x15
  0x06, // [9] amplitudeMod: 6
  0x07, // [10] vibrato: 7
  0x08, // [11] kbScaleRate: 8
  0xFE, // [12] NOT decoded (raw byte preserved)
  // waveform bytes
  0x07, // op0 waveForm: 0x07 & 0x3 = 3
  0x06, // op1 waveForm: 0x06 & 0x3 = 2
];

/// Same structuring as [kSpecialRecordAlg1] but with a nonzero algorithm
/// byte, which must decode to algorithm 0 (the inversion).
const List<int> kSpecialRecordAlg0 = [
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C,
  0x7F, // [12] nonzero -> algorithm 0
  0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B,
  0x1C,
  0x00, 0x01, // waveform bytes
];

/// Asserts every decoded operator/modulator field of an instrument
/// decoded from [kSpecialRecordAlg1].
void expectAlg1Fields(SciAdlibInstrument ins) {
  final op0 = ins.operator0;
  expect(op0.kbScaleLevel, 3);
  expect(op0.frequencyMult, 10);
  expect(op0.attackRate, 11);
  expect(op0.sustainLevel, 12);
  expect(op0.envelopeType, 5);
  expect(op0.decayRate, 14);
  expect(op0.releaseRate, 15);
  expect(op0.totalLevel, 61);
  expect(op0.amplitudeMod, 0xA1);
  expect(op0.vibrato, 0xB2);
  expect(op0.kbScaleRate, 0xC3);
  expect(op0.waveForm, 3);

  final op1 = ins.operator1;
  expect(op1.kbScaleLevel, 3);
  expect(op1.frequencyMult, 15);
  expect(op1.attackRate, 0);
  expect(op1.sustainLevel, 1);
  expect(op1.envelopeType, 2);
  expect(op1.decayRate, 3);
  expect(op1.releaseRate, 4);
  expect(op1.totalLevel, 0x15);
  expect(op1.amplitudeMod, 6);
  expect(op1.vibrato, 7);
  expect(op1.kbScaleRate, 8);
  expect(op1.waveForm, 2);

  expect(ins.modulator.feedback, 5);
  expect(ins.modulator.algorithm, 1);

  // Raw-byte round trip: nothing is lost, including the undecoded bytes
  // at positions 15 and 25 and the waveform bytes.
  expect(ins.rawBytes, orderedEquals(kSpecialRecordAlg1));
}

/// Asserts every decoded field of an instrument decoded from
/// [kSpecialRecordAlg0], including algorithm 0 for a nonzero byte.
void expectAlg0Fields(SciAdlibInstrument ins) {
  final op0 = ins.operator0;
  expect(op0.kbScaleLevel, 1);
  expect(op0.frequencyMult, 2);
  expect(op0.attackRate, 4);
  expect(op0.sustainLevel, 5);
  expect(op0.envelopeType, 6);
  expect(op0.decayRate, 7);
  expect(op0.releaseRate, 8);
  expect(op0.totalLevel, 9);
  expect(op0.amplitudeMod, 0x0A);
  expect(op0.vibrato, 0x0B);
  expect(op0.kbScaleRate, 0x0C);
  expect(op0.waveForm, 0);

  final op1 = ins.operator1;
  expect(op1.kbScaleLevel, 0x10 & 0x3);
  expect(op1.frequencyMult, 0x11 & 0xf);
  expect(op1.attackRate, 0x13 & 0xf);
  expect(op1.sustainLevel, 0x14 & 0xf);
  expect(op1.envelopeType, 0x15);
  expect(op1.decayRate, 0x16 & 0xf);
  expect(op1.releaseRate, 0x17 & 0xf);
  expect(op1.totalLevel, 0x18 & 0x3f);
  expect(op1.amplitudeMod, 0x19);
  expect(op1.vibrato, 0x1A);
  expect(op1.kbScaleRate, 0x1B);
  expect(op1.waveForm, 1);

  expect(ins.modulator.feedback, 3);
  expect(ins.modulator.algorithm, 0);

  expect(ins.rawBytes, orderedEquals(kSpecialRecordAlg0));
}

void main() {
  group('SciAdlibBank parsing', () {
    test('1344-byte bank decodes 48 instruments, every field checked', () {
      final bank = SciAdlibBank.fromBytes(
        buildBank48(specialIndex: 7, specialRecord: kSpecialRecordAlg1),
      );
      expect(bank.kind, SciAdlibBankKind.instruments48);
      expect(bank.containerSize, 1344);
      expect(bank.instrumentCount, 48);
      expectAlg1Fields(bank.instruments[7]);
      expect(bank.debugSummary(), contains('instruments48'));
      expect(bank.debugSummary(), contains('containerSize=1344'));
      final dbg = bank.instruments[7].debugString();
      expect(dbg, contains('frequencyMult=10'));
      expect(dbg, contains('feedback=5'));
      expect(dbg, contains('algorithm=1'));
    });

    test('non-special records decode from their fill bytes sanely', () {
      final bank = SciAdlibBank.fromBytes(
        buildBank48(specialIndex: 7, specialRecord: kSpecialRecordAlg1),
      );
      // Record 0 is filled with 0x10 in every byte.
      final ins = bank.instruments[0];
      expect(ins.operator0.kbScaleLevel, 0x10 & 0x3);
      expect(ins.rawBytes.every((b) => b == 0x10), isTrue);
    });

    test('2690-byte bank decodes 96 instruments with separator between halves', () {
      final bank = SciAdlibBank.fromBytes(
        buildBank96(
          firstHalfSpecialIndex: 5,
          firstHalfSpecialRecord: kSpecialRecordAlg1,
          secondHalfSpecialIndex: 90,
          secondHalfSpecialRecord: kSpecialRecordAlg0,
        ),
      );
      expect(bank.kind, SciAdlibBankKind.instruments96);
      expect(bank.containerSize, 2690);
      expect(bank.instrumentCount, 96);
      expectAlg1Fields(bank.instruments[5]);
      expectAlg0Fields(bank.instruments[90]);
      // Separator bytes (1344..1345) are never part of a record: record 48
      // starts at 1346, so its raw bytes must be the second-half fill.
      expect(bank.instruments[48].rawBytes.every((b) => b == (0x20 + 48) & 0xff),
          isTrue);
    });

    test('second-half offset: bytes at 1344..1345 are skipped, not record data', () {
      // Separator 0xEE 0xEE would corrupt the first record of the second
      // half if the parser started the second half at 1344 instead of 1346.
      final bank = SciAdlibBank.fromBytes(
        buildBank96(
          firstHalfSpecialIndex: 0,
          firstHalfSpecialRecord: kSpecialRecordAlg1,
          secondHalfSpecialIndex: 48,
          secondHalfSpecialRecord: kSpecialRecordAlg0,
          separator: const [0xEE, 0xEE],
        ),
      );
      expectAlg0Fields(bank.instruments[48]);
      expect(bank.instruments[48].rawBytes[0], 0x01);
    });

    test('waveform bytes mask to 2 bits and algorithm inversion is exposed', () {
      final ins1 = SciAdlibInstrument.fromRecord(
        recordFrom(kSpecialRecordAlg1),
      );
      expect(ins1.operator0.waveForm, 3);
      expect(ins1.operator1.waveForm, 2);
      expect(ins1.modulator.algorithm, 1);
      final ins0 = SciAdlibInstrument.fromRecord(
        recordFrom(kSpecialRecordAlg0),
      );
      expect(ins0.modulator.algorithm, 0);
      expect(ins0.modulator.feedback, 3);
    });

    test('unsupported and truncated sizes throw FormatException, never RangeError', () {
      for (final size in [0, 1, 27, 28, 1343, 1345, 2689, 2691, 10000]) {
        expect(
          () => SciAdlibBank.fromBytes(Uint8List(size)),
          throwsA(isA<FormatException>()),
          reason: 'size $size must throw FormatException',
        );
      }
    });

    test('5382-byte SCI1.1 form is rejected with an SCI1.1-labeled error', () {
      try {
        SciAdlibBank.fromBytes(Uint8List(kSciAdlibBankSci11Size));
        fail('expected FormatException for 5382-byte bank');
      } on FormatException catch (e) {
        expect(e.message, contains('unsupported'));
        expect(e.message, contains('SCI1.1'));
      }
    });

    test('truncated single record throws FormatException', () {
      expect(
        () => SciAdlibInstrument.fromRecord(Uint8List(27)),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty input throws FormatException, not RangeError', () {
      expect(
        () => SciAdlibBank.fromBytes(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Embedded ADL.DRV extractor', () {
    Uint8List fakeDriver(int size, {int markerIndex = 0x45a}) {
      final data = Uint8List(size);
      for (var i = 0; i < size; i++) {
        data[i] = i & 0xff;
      }
      // Distinct marker at the bank start so extraction is verifiable.
      data[markerIndex] = 0x5A;
      data[markerIndex + 1] = 0xA5;
      return data;
    }

    test('each allowlisted size extracts at 0x45a', () {
      for (final size in [5684, 5720, 5727]) {
        final extracted = sciExtractEmbeddedAdlDrvBank(fakeDriver(size));
        expect(extracted, isNotNull, reason: 'size $size');
        expect(extracted!.length, 1344);
        expect(extracted[0], 0x5A);
        expect(extracted[1], 0xA5);
      }
    });

    test('near-miss sizes are rejected', () {
      for (final size in [5683, 5728, 8803]) {
        expect(
          sciExtractEmbeddedAdlDrvBank(Uint8List(size)),
          isNull,
          reason: 'size $size must be rejected',
        );
      }
    });

    test('truncated data is rejected', () {
      expect(sciExtractEmbeddedAdlDrvBank(Uint8List(0)), isNull);
      expect(sciExtractEmbeddedAdlDrvBank(Uint8List(100)), isNull);
    });
  });

  group('Loader with synthetic volume', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sci_adlib_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Writes RESOURCE.MAP plus RESOURCE.000 holding one uncompressed
    /// patch.3 record with [payload] bytes.
    void writeVolumePatch(Uint8List payload) {
      final mapFile = File('${tempDir.path}/RESOURCE.MAP');
      final mapData = Uint8List(12);
      final mapBd = ByteData.sublistView(mapData);
      mapBd.setUint16(0, (SciResourceType.patch.typeCode << 11) | 3, Endian.little);
      mapBd.setUint32(2, 0, Endian.little); // volume 0, offset 0
      mapBd.setUint32(8, 0xFFFFFFFF, Endian.little); // sentinel
      mapFile.writeAsBytesSync(mapData);

      final volFile = File('${tempDir.path}/RESOURCE.000');
      final volData = Uint8List(8 + payload.length);
      final volBd = ByteData.sublistView(volData);
      volBd.setUint16(0, (SciResourceType.patch.typeCode << 11) | 3, Endian.little);
      volBd.setUint16(2, payload.length + 4, Endian.little);
      volBd.setUint16(4, payload.length, Endian.little);
      volBd.setUint16(6, 0, Endian.little); // method 0 (none)
      volData.setRange(8, 8 + payload.length, payload);
      volFile.writeAsBytesSync(volData);
    }

    /// Writes a bare RESOURCE.MAP with no patch3 entries (for the
    /// embedded-driver and empty cases following a volume case, or
    /// stand-alone). No volume file is created.
    void writeEmptyMap() {
      final mapFile = File('${tempDir.path}/RESOURCE.MAP');
      final mapData = Uint8List(8);
      final mapBd = ByteData.sublistView(mapData);
      mapBd.setUint32(0, 0xFFFFFFFF, Endian.little);
      mapBd.setUint32(4, 0xFFFFFFFF, Endian.little);
      mapFile.writeAsBytesSync(mapData);
    }

    void writeDriver(String name, Uint8List bytes) {
      File('${tempDir.path}/$name').writeAsBytesSync(bytes);
    }

    test('packed-volume patch 3 loads with volume provenance', () {
      final payload = buildBank48(
        specialIndex: 3,
        specialRecord: kSpecialRecordAlg1,
      );
      writeVolumePatch(payload);
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.provenance, SciAdlibBankProvenance.volume);
      expect(result.bank!.instrumentCount, 48);
      expectAlg1Fields(result.bank!.instruments[3]);
    });

    test('loose patch.003 decodes to the same instruments, loose provenance', () {
      final payload = buildBank48(
        specialIndex: 3,
        specialRecord: kSpecialRecordAlg1,
      );
      // Minimal valid map (one sound-ish entry is not needed; empty map
      // plus loose patch is enough for the loader).
      writeEmptyMap();
      // Loose patch file: 2-byte wrapper header (byte1 = extra header
      // length 4, followed by 4 filler bytes), then the bank payload.
      final loose = Uint8List(2 + 4 + payload.length);
      loose[0] = 0x89; // patch typecode 9 with high bit set
      loose[1] = 4;
      loose.setRange(2, 6, Uint8List.fromList([0x11, 0x22, 0x33, 0x44]));
      loose.setRange(6, 6 + payload.length, payload);
      writeDriver('patch.003', loose);

      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.provenance, SciAdlibBankProvenance.loosePatch);
      expect(result.bank!.instrumentCount, 48);
      expectAlg1Fields(result.bank!.instruments[3]);
    });

    test('no patch 3 + allowlisted ADL.DRV loads embedded bank', () {
      writeEmptyMap();
      final bankBytes = buildBank48(
        specialIndex: 9,
        specialRecord: kSpecialRecordAlg1,
      );
      final driver = Uint8List(5720);
      driver.setRange(0x45a, 0x45a + bankBytes.length, bankBytes);
      // Lowercase name variant must still match.
      writeDriver('adl.drv', driver);

      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.provenance, SciAdlibBankProvenance.embeddedAdlDrv);
      expect(result.bank!.instrumentCount, 48);
      expectAlg1Fields(result.bank!.instruments[9]);
    });

    test('no patch 3 + non-allowlisted ADL.DRV size -> unavailable with reason', () {
      writeEmptyMap();
      writeDriver('ADL.DRV', Uint8List(1000));
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isFalse);
      expect(result.bank, isNull);
      expect(result.provenance, SciAdlibBankProvenance.unavailable);
      expect(result.reason, contains('not allowlisted'));
    });

    test('nothing present -> unavailable, no throw', () {
      writeEmptyMap();
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isFalse);
      expect(result.provenance, SciAdlibBankProvenance.unavailable);
      expect(result.reason, isNotNull);
    });

    test('unsupported patch size -> unavailable result, not a throw', () {
      writeVolumePatch(Uint8List(100));
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);

      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isFalse);
      expect(result.provenance, SciAdlibBankProvenance.unavailable);
      expect(result.reason, contains('parse error'));
    });
  });

  group('Corpus gates (reference games)', () {
    test('PQ2 bank decodes to 48 instruments via loader', () {
      if (skipIfReferenceGameMissing('police-quest-2')) return;
      final vm = SciVolumeManager.fromDirectory(
        referenceGamePath('police-quest-2'),
      );
      addTearDown(vm.close);
      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.bank!.instrumentCount, 48);
      expect(
        result.provenance,
        anyOf(
          SciAdlibBankProvenance.volume,
          SciAdlibBankProvenance.loosePatch,
        ),
      );
    });

    test('SQ3 bank decodes to 96 instruments via loader', () {
      if (skipIfReferenceGameMissing('space-quest-3')) return;
      final vm = SciVolumeManager.fromDirectory(
        referenceGamePath('space-quest-3'),
      );
      addTearDown(vm.close);
      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.bank!.instrumentCount, 96);
      expect(
        result.provenance,
        anyOf(
          SciAdlibBankProvenance.volume,
          SciAdlibBankProvenance.loosePatch,
        ),
      );
    });

    test('KQ4 (no patch 3) decodes 48 via embedded ADL.DRV', () {
      if (skipIfReferenceGameMissing('kings-quest-4-sci')) return;
      final vm = SciVolumeManager.fromDirectory(
        referenceGamePath('kings-quest-4-sci'),
      );
      addTearDown(vm.close);
      expect(vm.findResource(SciResourceType.patch, 3), isNull,
          reason: 'KQ4 should have no patch 3 per the plan');
      final result = sciLoadAdlibBank(vm);
      expect(result.isAvailable, isTrue, reason: result.reason);
      expect(result.provenance, SciAdlibBankProvenance.embeddedAdlDrv);
      expect(result.bank!.instrumentCount, 48);
    });
  });
}
