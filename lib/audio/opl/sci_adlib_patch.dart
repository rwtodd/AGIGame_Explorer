// Sierra SCI AdLib patch-bank parser and loader (Stage 3).
//
// Clean-room implementation of the Sierra 28-byte instrument record and
// SCI0 patch-bank container formats. Semantics are defined by the Sierra
// instrument data itself and the FM hardware model; no third-party
// emulator source was copied. The two SCI0 container sizes are 1344
// (48 instruments) and 2690 (96 instruments); the 5382-byte SCI1.1 form
// is deliberately rejected as unsupported in this SCI0 stage.
//
// Record layout (28 bytes):
//   operator 0 block: bytes 0..12  (13 bytes)
//   operator 1 block: bytes 13..25 (13 bytes)
//   waveform op0: byte 26, waveform op1: byte 27 (both masked & 0x3)
//
// Per-operator fields within its 13-byte block:
//   [0] & 0x3  key-scale level
//   [1] & 0xf  frequency multiplier
//   [3] & 0xf  attack rate
//   [4] & 0xf  sustain level
//   [5]        envelope type (raw byte)
//   [6] & 0xf  decay rate
//   [7] & 0xf  release rate
//   [8] & 0x3f total level
//   [9]        amplitude modulation enable (raw byte)
//   [10]       vibrato enable (raw byte)
//   [11]       key-scale rate (raw byte)
//
// Operator 0's [2] and [12] positions carry the modulator settings
// instead (feedback and the inverted algorithm flag); operator 1's
// [2] and [12] positions (record bytes 15 and 25) are present as raw
// bytes in the record but are not decoded into operator fields, since
// the modulator model owns those two bytes of operator 0's block only.
// The full raw record is always retained so nothing is lost.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';
import 'package:path/path.dart' as p;

/// Size in bytes of one Sierra AdLib instrument record.
const int kSciAdlibRecordSize = 28;

/// Size in bytes of the 48-instrument SCI0 bank container.
const int kSciAdlibBank48Size = 1344;

/// Size in bytes of the 96-instrument SCI0 bank container.
const int kSciAdlibBank96Size = 2690;

/// Size in bytes of the SCI1.1 bank container (unsupported in SCI0 stage).
const int kSciAdlibBankSci11Size = 5382;

/// Number of instruments in the 48-instrument container.
const int kSciAdlibInstruments48 = 48;

/// Number of instruments in the 96-instrument container.
const int kSciAdlibInstruments96 = 96;

/// Offset of the embedded 1344-byte bank inside a recognized early
/// `ADL.DRV` driver file.
const int kSciEmbeddedAdlDrvBankOffset = 0x45a;

/// Size of the bank embedded inside a recognized `ADL.DRV` file.
const int kSciEmbeddedAdlDrvBankSize = 1344;

/// Exact `ADL.DRV` file sizes whose embedded bank is recognized.
const Set<int> kSciEmbeddedAdlDrvFileSizes = {5684, 5720, 5727};

/// Name of the early driver file carrying the embedded bank.
const String kSciAdlDrvFileName = 'ADL.DRV';

/// Which SCI0 container form a parsed bank came from.
enum SciAdlibBankKind {
  /// 1344 bytes: 48 back-to-back records.
  instruments48,

  /// 2690 bytes: 48 records, a 2-byte separator, then 48 more records.
  instruments96,
}

/// Immutable decoded operator (one 13-byte block of a 28-byte record).
final class SciAdlibOperator {
  /// Key-scale level, 0..3 (block byte 0, masked & 0x3).
  final int kbScaleLevel;

  /// Frequency multiplier, 0..15 (block byte 1, masked & 0xf).
  final int frequencyMult;

  /// Attack rate, 0..15 (block byte 3, masked & 0xf).
  final int attackRate;

  /// Sustain level, 0..15 (block byte 4, masked & 0xf).
  final int sustainLevel;

  /// Envelope type, raw byte (block byte 5).
  final int envelopeType;

  /// Decay rate, 0..15 (block byte 6, masked & 0xf).
  final int decayRate;

  /// Release rate, 0..15 (block byte 7, masked & 0xf).
  final int releaseRate;

  /// Total level, 0..63 (block byte 8, masked & 0x3f).
  final int totalLevel;

  /// Amplitude modulation enable, raw byte (block byte 9).
  final int amplitudeMod;

  /// Vibrato enable, raw byte (block byte 10).
  final int vibrato;

  /// Key-scale rate, raw byte (block byte 11).
  final int kbScaleRate;

  /// Waveform selection, 0..3 (record byte 26 for operator 0 and 27 for
  /// operator 1, each masked & 0x3).
  final int waveForm;

  const SciAdlibOperator({
    required this.kbScaleLevel,
    required this.frequencyMult,
    required this.attackRate,
    required this.sustainLevel,
    required this.envelopeType,
    required this.decayRate,
    required this.releaseRate,
    required this.totalLevel,
    required this.amplitudeMod,
    required this.vibrato,
    required this.kbScaleRate,
    required this.waveForm,
  });

  /// Deterministic single-line debug rendering of every decoded field.
  String debugString() =>
      'kbScaleLevel=$kbScaleLevel frequencyMult=$frequencyMult '
      'attackRate=$attackRate sustainLevel=$sustainLevel '
      'envelopeType=$envelopeType decayRate=$decayRate '
      'releaseRate=$releaseRate totalLevel=$totalLevel '
      'amplitudeMod=$amplitudeMod vibrato=$vibrato '
      'kbScaleRate=$kbScaleRate waveForm=$waveForm';
}

/// Immutable modulator settings decoded from operator 0's block positions
/// [2] and [12] of the record (record bytes 2 and 12).
final class SciAdlibModulator {
  /// Modulator feedback, 0..7 (record byte 2, masked & 0x7).
  final int feedback;

  /// FM algorithm flag. Exposed exactly as stored after applying the
  /// inversion: the raw record byte is inverted before it reaches this
  /// field, so `raw byte == 0` means [algorithm] is 1.
  final int algorithm;

  const SciAdlibModulator({required this.feedback, required this.algorithm});

  /// Deterministic single-line debug rendering of every decoded field.
  String debugString() => 'feedback=$feedback algorithm=$algorithm';
}

/// Immutable decoded instrument: two operators, modulator settings, and
/// the original 28 raw bytes (unmodifiable) for debug/golden use.
final class SciAdlibInstrument {
  /// Operator 0 (record bytes 0..12 plus waveform byte 26).
  final SciAdlibOperator operator0;

  /// Operator 1 (record bytes 13..25 plus waveform byte 27).
  final SciAdlibOperator operator1;

  /// Modulator settings (record bytes 2 and 12).
  final SciAdlibModulator modulator;

  /// The original 28 raw record bytes, unmodifiable.
  final Uint8List rawBytes;

  SciAdlibInstrument._({
    required this.operator0,
    required this.operator1,
    required this.modulator,
    required this.rawBytes,
  });

  /// Decodes one 28-byte [record].
  ///
  /// Throws a [FormatException] when [record] is shorter than 28 bytes.
  factory SciAdlibInstrument.fromRecord(Uint8List record) {
    if (record.length < kSciAdlibRecordSize) {
      throw FormatException(
        'SciAdlibInstrument record too short: ${record.length} bytes '
        '(need $kSciAdlibRecordSize)',
      );
    }
    final raw = Uint8List.fromList(
      Uint8List.sublistView(record, 0, kSciAdlibRecordSize),
    );

    SciAdlibOperator decodeOperator(int blockStart, int waveByte) {
      final b = blockStart;
      return SciAdlibOperator(
        kbScaleLevel: raw[b] & 0x3,
        frequencyMult: raw[b + 1] & 0xf,
        attackRate: raw[b + 3] & 0xf,
        sustainLevel: raw[b + 4] & 0xf,
        envelopeType: raw[b + 5],
        decayRate: raw[b + 6] & 0xf,
        releaseRate: raw[b + 7] & 0xf,
        totalLevel: raw[b + 8] & 0x3f,
        amplitudeMod: raw[b + 9],
        vibrato: raw[b + 10],
        kbScaleRate: raw[b + 11],
        waveForm: raw[waveByte] & 0x3,
      );
    }

    return SciAdlibInstrument._(
      operator0: decodeOperator(0, 26),
      operator1: decodeOperator(13, 27),
      modulator: SciAdlibModulator(
        feedback: raw[2] & 0x7,
        // The stored flag is inverted: a zero byte means algorithm 1.
        algorithm: raw[12] == 0 ? 1 : 0,
      ),
      rawBytes: raw,
    );
  }

  /// Project-authored instrument from decoded fields.
  ///
  /// Synthesizes a coherent 28-byte [rawBytes] record by encoding the
  /// fields with the same record layout [SciAdlibInstrument.fromRecord]
  /// decodes, so `fromRecord(fromFields(...).rawBytes)` round-trips
  /// field-for-field. Field ranges are masked to the record widths
  /// (kbScaleLevel & 0x3, frequencyMult & 0xf, attack/decay/sustain/
  /// release & 0xf, totalLevel & 0x3f, feedback & 0x7, waveforms & 0x3);
  /// envelopeType/amplitudeMod/vibrato/kbScaleRate are stored raw.
  /// The algorithm flag uses the first-class inverse convention: the
  /// stored record byte is 0 when [SciAdlibModulator.algorithm] is 1
  /// and 1 when it is 0.
  factory SciAdlibInstrument.fromFields({
    required SciAdlibOperator operator0,
    required SciAdlibOperator operator1,
    required SciAdlibModulator modulator,
  }) {
    final raw = Uint8List(kSciAdlibRecordSize);

    void writeOperator(int b, SciAdlibOperator op) {
      raw[b] = op.kbScaleLevel & 0x3;
      raw[b + 1] = op.frequencyMult & 0xf;
      raw[b + 3] = op.attackRate & 0xf;
      raw[b + 4] = op.sustainLevel & 0xf;
      raw[b + 5] = op.envelopeType & 0xff;
      raw[b + 6] = op.decayRate & 0xf;
      raw[b + 7] = op.releaseRate & 0xf;
      raw[b + 8] = op.totalLevel & 0x3f;
      raw[b + 9] = op.amplitudeMod & 0xff;
      raw[b + 10] = op.vibrato & 0xff;
      raw[b + 11] = op.kbScaleRate & 0xff;
    }

    writeOperator(0, operator0);
    writeOperator(13, operator1);
    // Modulator-owned bytes of operator 0's block; operator 1's
    // corresponding positions (15 and 25) stay 0.
    raw[2] = modulator.feedback & 0x7;
    raw[12] = modulator.algorithm == 1 ? 0 : 1;
    raw[26] = operator0.waveForm & 0x3;
    raw[27] = operator1.waveForm & 0x3;
    return SciAdlibInstrument._(
      operator0: _maskedOperator(operator0),
      operator1: _maskedOperator(operator1),
      modulator: SciAdlibModulator(
        feedback: modulator.feedback & 0x7,
        algorithm: modulator.algorithm == 1 ? 1 : 0,
      ),
      rawBytes: raw,
    );
  }

  /// Deterministic multi-line debug rendering for tests and debug UI.
  String debugString() =>
      'op0[${operator0.debugString()}] '
      'op1[${operator1.debugString()}] '
      'mod[${modulator.debugString()}] '
      'raw[${rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]';

  /// Normalizes an operator into the exact values [fromRecord] would
  /// decode from the encoded bytes, so field equality round-trips.
  static SciAdlibOperator _maskedOperator(SciAdlibOperator op) {
    return SciAdlibOperator(
      kbScaleLevel: op.kbScaleLevel & 0x3,
      frequencyMult: op.frequencyMult & 0xf,
      attackRate: op.attackRate & 0xf,
      sustainLevel: op.sustainLevel & 0xf,
      envelopeType: op.envelopeType & 0xff,
      decayRate: op.decayRate & 0xf,
      releaseRate: op.releaseRate & 0xf,
      totalLevel: op.totalLevel & 0x3f,
      amplitudeMod: op.amplitudeMod & 0xff,
      vibrato: op.vibrato & 0xff,
      kbScaleRate: op.kbScaleRate & 0xff,
      waveForm: op.waveForm & 0x3,
    );
  }
}

/// Immutable parsed SCI0 AdLib bank: the exact instruments present in the
/// container (48 or 96; never padded by this parser) plus container facts.
final class SciAdlibBank {
  /// Decoded instruments in bank order.
  final List<SciAdlibInstrument> instruments;

  /// Which container form was parsed.
  final SciAdlibBankKind kind;

  /// Total size in bytes of the parsed container.
  final int containerSize;

  SciAdlibBank._({
    required this.instruments,
    required this.kind,
    required this.containerSize,
  });

  /// Number of decoded instruments (48 or 96).
  int get instrumentCount => instruments.length;

  /// Single-line bank summary for debug UI.
  String debugSummary() => 'SciAdlibBank(${kind.name}, '
      'containerSize=$containerSize, instruments=${instruments.length})';

  /// Parses [data] as an SCI0 patch bank.
  ///
  /// Accepts exactly 1344-byte (48 instruments) and 2690-byte (96
  /// instruments) containers. The 2690-byte form has its two separator
  /// bytes BETWEEN the halves: records 48..95 start at offset 1346
  /// (2 + 28*i for i in 48..95), so the bytes at 1344..1345 are never
  /// part of any record.
  ///
  /// Throws a [FormatException] for unsupported sizes (including the
  /// 5382-byte SCI1.1 form, which names itself as unsupported-for-SCI0 in
  /// the message) and never throws [RangeError] on adversarial lengths.
  factory SciAdlibBank.fromBytes(Uint8List data) {
    return switch (data.length) {
      kSciAdlibBank48Size => SciAdlibBank._(
          instruments: List.unmodifiable([
            for (var i = 0; i < kSciAdlibInstruments48; i++)
              SciAdlibInstrument.fromRecord(
                Uint8List.sublistView(data, 28 * i, 28 * i + 28),
              ),
          ]),
          kind: SciAdlibBankKind.instruments48,
          containerSize: data.length,
        ),
      kSciAdlibBank96Size => SciAdlibBank._(
          instruments: List.unmodifiable([
            for (var i = 0; i < kSciAdlibInstruments48; i++)
              SciAdlibInstrument.fromRecord(
                Uint8List.sublistView(data, 28 * i, 28 * i + 28),
              ),
            // Second half: the 2 separator bytes (offsets 1344..1345)
            // sit between the halves; record i starts at 2 + 28*i.
            for (var i = 48; i < kSciAdlibInstruments96; i++)
              SciAdlibInstrument.fromRecord(
                Uint8List.sublistView(data, 2 + 28 * i, 2 + 28 * i + 28),
              ),
          ]),
          kind: SciAdlibBankKind.instruments96,
          containerSize: data.length,
        ),
      kSciAdlibBankSci11Size => throw FormatException(
          'Unsupported SCI AdLib patch bank size: 5382 bytes is the '
          'SCI1.1 form (unsupported for SCI0)',
        ),
      _ => throw FormatException(
          'Unsupported SCI AdLib patch bank size: ${data.length} bytes '
          '(expected $kSciAdlibBank48Size or $kSciAdlibBank96Size)',
        ),
    };
  }
}

/// Extracts the embedded 1344-byte bank from raw `ADL.DRV` file bytes.
///
/// Returns null unless [fileBytes] is exactly one of the allowlisted file
/// sizes and the bank slice at offset 0x45a fits. Pure: no filesystem
/// access, so it is unit-testable from raw bytes alone.
Uint8List? sciExtractEmbeddedAdlDrvBank(Uint8List fileBytes) {
  if (!kSciEmbeddedAdlDrvFileSizes.contains(fileBytes.length)) {
    return null;
  }
  final start = kSciEmbeddedAdlDrvBankOffset;
  final end = start + kSciEmbeddedAdlDrvBankSize;
  if (end > fileBytes.length) {
    return null;
  }
  return Uint8List.fromList(
    Uint8List.sublistView(fileBytes, start, end),
  );
}

/// Finds `ADL.DRV` (case-insensitive) inside [gameDirectory] and returns
/// its raw file bytes, or null when no such file exists.
Uint8List? sciReadAdlDrvFile(String gameDirectory) {
  final dir = Directory(gameDirectory);
  if (!dir.existsSync()) {
    return null;
  }
  for (final entity in dir.listSync()) {
    if (entity is File &&
        p.basename(entity.path).toUpperCase() == kSciAdlDrvFileName) {
      return entity.readAsBytesSync();
    }
  }
  return null;
}

/// How a loaded bank was found. `unavailable` is not a source: it is the
/// provenance carried by a failed [SciAdlibLoadResult].
enum SciAdlibBankProvenance {
  /// Packed inside a `RESOURCE.xxx` volume.
  volume,

  /// Loose `patch.003` file overriding the volume resource.
  loosePatch,

  /// Embedded bank inside `ADL.DRV`.
  embeddedAdlDrv,

  /// No bank could be loaded; see [SciAdlibLoadResult.reason].
  unavailable,
}

/// Result of loading an SCI0 AdLib bank. Never throws for the ordinary
/// unavailable case: [bank] is null and [reason] explains why.
final class SciAdlibLoadResult {
  /// The decoded bank, or null when unavailable.
  final SciAdlibBank? bank;

  /// Where the bank came from (or [SciAdlibBankProvenance.unavailable]).
  final SciAdlibBankProvenance provenance;

  /// Human-readable reason; null when [bank] loaded successfully.
  final String? reason;

  const SciAdlibLoadResult({
    required this.bank,
    required this.provenance,
    required this.reason,
  });

  /// True when a bank was loaded.
  bool get isAvailable => bank != null;
}

/// Loads the SCI0 AdLib bank for a game directory.
///
/// Order: (a) patch resource 3 via [SciVolumeManager] (which includes the
/// loose `patch.003` override and its header stripping), (b) the embedded
/// `ADL.DRV` bank when the driver size is allowlisted, (c) unavailable.
///
/// Volume vs. loose is distinguished via `findResource(...).isPatch` before
/// fetching, which is the same flag the volume manager itself uses to
/// decide header stripping, so the distinction is reliable within this
/// codebase. Ordinary failures (missing resource, unsupported size,
/// unreadable driver, parse error) return an unavailable result rather
/// than throwing; only genuine unexpected errors propagate.
SciAdlibLoadResult sciLoadAdlibBank(SciVolumeManager volumes) {
  final entry = volumes.findResource(SciResourceType.patch, 3);
  if (entry != null) {
    final provenance = entry.isPatch
        ? SciAdlibBankProvenance.loosePatch
        : SciAdlibBankProvenance.volume;
    late final Uint8List patchBytes;
    try {
      patchBytes = volumes.getResource(SciResourceType.patch, 3);
    } on SciException catch (e) {
      return SciAdlibLoadResult(
        bank: null,
        provenance: SciAdlibBankProvenance.unavailable,
        reason: 'Patch resource 3 unreadable: ${e.message}',
      );
    }
    try {
      return SciAdlibLoadResult(
        bank: SciAdlibBank.fromBytes(patchBytes),
        provenance: provenance,
        reason: null,
      );
    } on FormatException catch (e) {
      return SciAdlibLoadResult(
        bank: null,
        provenance: SciAdlibBankProvenance.unavailable,
        reason: 'Patch resource 3 parse error: ${e.message}',
      );
    }
  }

  // No patch resource 3: try the embedded ADL.DRV bank.
  final driverBytes = sciReadAdlDrvFile(volumes.gameDirectory);
  if (driverBytes == null) {
    return const SciAdlibLoadResult(
      bank: null,
      provenance: SciAdlibBankProvenance.unavailable,
      reason: 'Missing patch resource 3 and no ADL.DRV driver',
    );
  }
  final embedded = sciExtractEmbeddedAdlDrvBank(driverBytes);
  if (embedded == null) {
    return SciAdlibLoadResult(
      bank: null,
      provenance: SciAdlibBankProvenance.unavailable,
      reason: 'ADL.DRV size ${driverBytes.length} not allowlisted '
          '(expected one of {5684, 5720, 5727})',
    );
  }
  try {
    return SciAdlibLoadResult(
      bank: SciAdlibBank.fromBytes(embedded),
      provenance: SciAdlibBankProvenance.embeddedAdlDrv,
      reason: null,
    );
  } on FormatException catch (e) {
    return SciAdlibLoadResult(
      bank: null,
      provenance: SciAdlibBankProvenance.unavailable,
      reason: 'Embedded ADL.DRV bank parse error: ${e.message}',
    );
  }
}
