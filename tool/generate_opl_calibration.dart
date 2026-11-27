/// Generates an OPL2 calibration kit for SCI0 ScummVM reference captures.
///
/// The kit contains:
/// - `PATCH.003`: a synthetic SCI AdLib patch bank whose 48 instruments vary
///   one synthesis parameter at a time (program 48..95 duplicate 0..47 in
///   96-instrument banks).
/// - `SOUND.990`..`SOUND.993`: labeled SCI0 sound resources that play test
///   segments using those instruments, in both SCI0-early (17-byte) and
///   SCI0-late (33-byte) header formats.
/// - `SOUND.001`: combined intro drop-in track (the four resources above
///   concatenated with 60-tick gaps), for replacing a game's sound
///   resource 1 and simply starting the game (see README below).
///
/// Kit generations: v1 (default, unchanged), v2 (`--kit v2`), and v3
/// (`--kit v3`, state-transition, rare-archetype, and allocation tests
/// found by corpus mining; v3 sound headers use per-channel voice/raw
/// overrides, see [_buildHeader]).
///
/// All data is synthetic. No game patch bytes are copied into this file or
/// its output. The tool is pure Dart (`dart:io`/`dart:typed_data` only) so
/// `dart tool/generate_opl_calibration.dart` runs standalone; the generator
/// functions are importable from tests.
///
/// Usage:
/// ```sh
/// dart tool/generate_opl_calibration.dart --out <dir>
/// ```
///
/// `<dir>` receives three subdirectories (`early/`, `late48/`, `late96/`),
/// each holding `PATCH.003`, `SOUND.990`..`SOUND.993`, `SOUND.001`
/// (combined), and `MANIFEST.md`, plus a root `README.md` with usage
/// instructions.
library;

import 'dart:io';
import 'dart:typed_data';

/// Size in bytes of one Sierra AdLib instrument record.
const int kRecordSize = 28;

/// Size in bytes of the 48-instrument SCI0 bank container.
const int kBank48Size = 1344;

/// Size in bytes of the 96-instrument SCI0 bank container.
const int kBank96Size = 2690;

/// Number of distinct instruments (programs 0..47).
const int kInstrumentCount = 48;

/// SCI tick rate. All segment times are in 60 Hz ticks.
const int kTicksPerSecond = 60;

/// SCI resource type code for an AdLib patch bank.
const int kPatchTypeCode = 9;

/// SCI resource type code for sound resources.
const int kSoundTypeCode = 4;

/// First calibration sound resource number (990..993).
const int kFirstSound = 990;

/// Last calibration sound resource number (990..993).
const int kLastSound = 993;

/// Sound resource number of the combined intro drop-in track.
const int kCombinedSoundNumber = 1;

/// Loose-patch filename of the combined intro drop-in track (`SOUND.001`).
const String kCombinedSoundFile = 'SOUND.001';

/// Silence gap in ticks between former resources in the combined track.
const int kCombinedGapTicks = 60;

/// Early SCI0 sound header size in bytes (flags + 16 channels).
const int kHeaderEarlySize = 17;

/// Late SCI0 sound header size in bytes (flags + 16 channel pairs).
const int kHeaderLateSize = 33;

/// First MIDI channel used by the kit (index 1; header voices 2, AdLib).
const int kChannelA = 1;

/// Second MIDI channel used by the kit (index 2; header voices 2, AdLib).
const int kChannelB = 2;

/// Which calibration kit generation to build.
///
/// v1 is the original kit and remains the default; its outputs are
/// unchanged. v2 is opt-in via `--kit v2` and shares the same record
/// encoding, loose-patch wrapper, sound header/event machinery, and
/// manifest/README conventions. v3 is opt-in via `--kit v3` and adds
/// state-transition, rare-archetype, and allocation tests (new bank
/// builder, new sound builders, and per-channel header voice/raw
/// overrides for all v3 sound resources including the combined track).
enum CalibrationKitVersion { v1, v2, v3 }

/// Parses a `--kit` value case-insensitively (`v1`/`v2`/`v3`).
///
/// Throws [FormatException] for any other value; the CLI maps that to
/// usage + exit code 2.
CalibrationKitVersion parseCalibrationKitVersion(String value) {
  return switch (value.toLowerCase()) {
    'v1' => CalibrationKitVersion.v1,
    'v2' => CalibrationKitVersion.v2,
    'v3' => CalibrationKitVersion.v3,
    _ => throw FormatException('unknown kit version: $value'),
  };
}

/// SCI0 sound header format.
enum SoundHeaderFormat {
  /// 17-byte early header: one byte per channel, `(voices << 4) | deviceBits`.
  early,

  /// 33-byte late header: 16 `[voiceCount, playMask]` pairs.
  late,
}

/// One labeled test segment inside a calibration sound resource.
///
/// Times are in 60 Hz ticks. Segment ranges are contiguous within a
/// resource: `endTick` of one segment is the `startTick` of the next, and
/// the last segment's `endTick` equals the parsed track's `totalTicks`
/// (including trailing silence).
final class CalibrationSegment {
  /// Sound resource number (990..993).
  final int resourceNumber;

  /// 0-based index of this segment within its resource.
  final int segmentIndex;

  /// Absolute start tick (inclusive) of the segment.
  final int startTick;

  /// Absolute end tick (exclusive) of the segment: the next segment's
  /// start, or the end of the track for the last segment.
  final int endTick;

  /// Program (instrument) number used, or -1 when the segment does not
  /// select a single program (duets use program 45 on both channels).
  final int program;

  /// MIDI channel(s) the segment sounds on, e.g. `'1'` or `'1,2'`.
  final String channel;

  /// Note number(s), e.g. `'69'` or `'69/76'` for duets.
  final String note;

  /// Human-readable purpose of the segment.
  final String purpose;

  const CalibrationSegment({
    required this.resourceNumber,
    required this.segmentIndex,
    required this.startTick,
    required this.endTick,
    required this.program,
    required this.channel,
    required this.note,
    required this.purpose,
  });

  /// Start time in seconds.
  double get startSeconds => startTick / kTicksPerSecond;

  /// End time in seconds.
  double get endSeconds => endTick / kTicksPerSecond;
}

/// Result of building one calibration sound resource.
final class SoundResourceData {
  /// Raw sound payload (header + event stream, without the loose-patch
  /// 2-byte wrapper).
  final Uint8List payload;

  /// Segments in play order; the last segment's `endTick` equals
  /// [totalTicks].
  final List<CalibrationSegment> segments;

  /// Total track duration in ticks (tick of end-of-track).
  final int totalTicks;

  /// Header size in bytes (17 for early, 33 for late).
  final int headerSize;

  const SoundResourceData({
    required this.payload,
    required this.segments,
    required this.totalTicks,
    required this.headerSize,
  });
}

/// Result of building a complete calibration kit for one output variant.
final class CalibrationKit {
  /// Loose-patch files as `filename -> bytes` (filenames are uppercase:
  /// `PATCH.003`, `SOUND.990`..`SOUND.993`, `SOUND.001`).
  final Map<String, Uint8List> files;

  /// All segments across the four sound resources, in order.
  final List<CalibrationSegment> segments;

  /// Combined intro drop-in track (`SOUND.001`) built from the four
  /// resources concatenated with 60-tick gaps. Its segments keep their
  /// original resource numbers (990..993) with offset absolute ticks.
  final SoundResourceData combinedSound;

  /// Header format written to the sound resources.
  final SoundHeaderFormat format;

  /// Whether the patch bank holds 96 instruments (48 duplicated).
  final bool ninetySix;

  /// Human-readable manifest (`MANIFEST.md` contents).
  final String manifestMarkdown;

  /// Kit generation this kit was built from (`v1` by default).
  final CalibrationKitVersion kitVersion;

  const CalibrationKit({
    required this.files,
    required this.segments,
    required this.combinedSound,
    required this.format,
    required this.ninetySix,
    required this.manifestMarkdown,
    this.kitVersion = CalibrationKitVersion.v1,
  });

  /// Total duration of one resource's track, if present.
  int totalTicksFor(int resourceNumber) {
    return segments
        .where((s) => s.resourceNumber == resourceNumber)
        .map((s) => s.endTick)
        .fold(0, (a, b) => a > b ? a : b);
  }
}

// ---------------------------------------------------------------------------
// Patch-bank generation (synthetic instruments).
// ---------------------------------------------------------------------------

/// Mutable operator parameters for bank building. Defaults match the brief:
/// AR=15, DR=0, SL=0, RR=4, EG=1, KSR=0, KSL=0, AM=0, VIB=0, wave=0,
/// MULT=1, TL=12 (carrier reference level).
final class _OpSpec {
  int ksl = 0;
  int mult = 1;
  int ar = 15;
  int sl = 0;
  int eg = 1;
  int dr = 0;
  int rr = 4;
  int tl = 12;
  int am = 0;
  int vib = 0;
  int ksr = 0;
  int wave = 0;
}

/// Encodes one 28-byte instrument record from the operator specs.
///
/// Operator 0 is the modulator; operator 1 is the carrier. The algorithm
/// flag (record byte 12, operator-0 block byte 12) is inverted as stored:
/// raw 0 means algorithm 1 (additive), raw nonzero means algorithm 0 (FM).
/// Operator 1's block bytes [2] (record 15) and [12] (record 25) are unused
/// and written as 0.
Uint8List _buildRecord({
  required _OpSpec mod,
  required _OpSpec carrier,
  required int feedback,
  required int algorithm,
}) {
  final r = Uint8List(kRecordSize);
  // Operator 0 block: bytes 0..12. Byte 2 is feedback, byte 12 is the
  // inverted algorithm flag.
  r[0] = mod.ksl & 0xFF;
  r[1] = mod.mult & 0xFF;
  r[2] = feedback & 0xFF;
  r[3] = mod.ar & 0xFF;
  r[4] = mod.sl & 0xFF;
  r[5] = mod.eg & 0xFF;
  r[6] = mod.dr & 0xFF;
  r[7] = mod.rr & 0xFF;
  r[8] = mod.tl & 0xFF;
  r[9] = mod.am & 0xFF;
  r[10] = mod.vib & 0xFF;
  r[11] = mod.ksr & 0xFF;
  r[12] = algorithm == 0 ? 1 : 0;
  // Operator 1 block: bytes 13..25. Bytes 15 and 25 are unused (=0).
  r[13] = carrier.ksl & 0xFF;
  r[14] = carrier.mult & 0xFF;
  r[15] = 0;
  r[16] = carrier.ar & 0xFF;
  r[17] = carrier.sl & 0xFF;
  r[18] = carrier.eg & 0xFF;
  r[19] = carrier.dr & 0xFF;
  r[20] = carrier.rr & 0xFF;
  r[21] = carrier.tl & 0xFF;
  r[22] = carrier.am & 0xFF;
  r[23] = carrier.vib & 0xFF;
  r[24] = carrier.ksr & 0xFF;
  r[25] = 0;
  r[26] = mod.wave & 0xFF;
  r[27] = carrier.wave & 0xFF;
  return r;
}

Uint8List _buildInstrument(int program) {
  final mod = _OpSpec();
  final carrier = _OpSpec();
  var feedback = 0;
  var algorithm = 0;

  if (program == 0) {
    mod.tl = 63;
    carrier.tl = 12;
  } else if (program == 1) {
    mod.tl = 63;
    carrier.tl = 12;
    algorithm = 1;
  } else if (program >= 2 && program <= 4) {
    mod.tl = 63;
    carrier.tl = 12;
    carrier.wave = program - 1;
  } else if (program >= 5 && program <= 11) {
    const tl = [56, 48, 40, 32, 24, 16, 8];
    mod.tl = tl[program - 5];
    carrier.tl = 12;
  } else if (program >= 12 && program <= 19) {
    feedback = program - 12;
    mod.tl = 16;
    carrier.tl = 12;
  } else if (program >= 20 && program <= 26) {
    const ar = [1, 4, 6, 8, 10, 12, 15];
    mod.tl = 63;
    carrier.ar = ar[program - 20];
    carrier.dr = 0;
    carrier.sl = 0;
    carrier.eg = 1;
    carrier.rr = 8;
  } else if (program >= 27 && program <= 30) {
    const dr = [1, 4, 8, 12];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = dr[program - 27];
    carrier.sl = 12;
    carrier.eg = 1;
    carrier.rr = 8;
  } else if (program >= 31 && program <= 34) {
    const rr = [1, 3, 6, 10];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = 12;
    carrier.sl = 0;
    carrier.eg = 0;
    carrier.rr = rr[program - 31];
  } else if (program >= 35 && program <= 38) {
    const rr = [1, 4, 8, 12];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = 0;
    carrier.sl = 0;
    carrier.eg = 1;
    carrier.rr = rr[program - 35];
  } else if (program >= 39 && program <= 42) {
    mod.tl = 63;
    carrier.ksl = program - 39;
  } else if (program == 43 || program == 44) {
    mod.tl = 63;
    carrier.tl = 12;
    mod.ar = 6;
    mod.dr = 4;
    mod.sl = 8;
    mod.rr = 6;
    mod.eg = 1;
    carrier.ar = 6;
    carrier.dr = 4;
    carrier.sl = 8;
    carrier.rr = 6;
    carrier.eg = 1;
    mod.ksr = program == 43 ? 0 : 1;
    carrier.ksr = program == 43 ? 0 : 1;
  } else if (program == 45) {
    feedback = 2;
    mod.tl = 16;
    carrier.tl = 0;
    mod.eg = 1;
    carrier.eg = 1;
  } else if (program == 46) {
    feedback = 6;
    mod.tl = 20;
    mod.ar = 12;
    mod.dr = 6;
    mod.sl = 4;
    mod.rr = 6;
    mod.eg = 1;
    carrier.tl = 8;
    carrier.ar = 12;
    carrier.dr = 4;
    carrier.sl = 3;
    carrier.rr = 6;
    carrier.eg = 1;
  } else if (program == 47) {
    mod.tl = 63;
    carrier.tl = 63;
  } else {
    throw ArgumentError.value(program, 'program', 'must be 0..47');
  }

  return _buildRecord(
    mod: mod,
    carrier: carrier,
    feedback: feedback,
    algorithm: algorithm,
  );
}

Uint8List _buildInstrumentV2(int program) {
  final mod = _OpSpec();
  final carrier = _OpSpec();
  var feedback = 0;
  var algorithm = 0;

  if (program == 0) {
    // Reference sine: same as v1 program 0.
    mod.tl = 63;
    carrier.tl = 12;
  } else if (program == 1) {
    // Waveform-3 carrier, mod silent.
    mod.tl = 63;
    carrier.tl = 12;
    carrier.wave = 3;
  } else if (program == 2) {
    // Waveform-3 modulator + sine carrier (FM, mod TL16, fb0).
    mod.tl = 16;
    mod.wave = 3;
    carrier.tl = 12;
  } else if (program >= 3 && program <= 8) {
    // Feedback x modulator-TL matrix: fb {5,6,7} x mod TL {8,24}.
    const fbs = [5, 6, 7];
    const modTls = [8, 24];
    final i = program - 3;
    feedback = fbs[i ~/ 2];
    mod.tl = modTls[i % 2];
    carrier.tl = 12;
  } else if (program >= 9 && program <= 14) {
    // Attack fill-in AR = 2,3,5,7,9,11 (carrier-only, EG1, DR0 SL0 RR8).
    const ar = [2, 3, 5, 7, 9, 11];
    mod.tl = 63;
    carrier.ar = ar[program - 9];
    carrier.dr = 0;
    carrier.sl = 0;
    carrier.eg = 1;
    carrier.rr = 8;
    carrier.tl = 12;
  } else if (program >= 15 && program <= 20) {
    // Decay fill-in DR = 2,3,5,6,7,9 (AR15, SL12, EG1, RR8).
    const dr = [2, 3, 5, 6, 7, 9];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = dr[program - 15];
    carrier.sl = 12;
    carrier.eg = 1;
    carrier.rr = 8;
    carrier.tl = 12;
  } else if (program >= 21 && program <= 26) {
    // Percussive RR fine ladder RR = 2,3,4,5,6,8 (AR15, DR12, SL0, EG0).
    const rr = [2, 3, 4, 5, 6, 8];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = 12;
    carrier.sl = 0;
    carrier.eg = 0;
    carrier.rr = rr[program - 21];
    carrier.tl = 12;
  } else if (program >= 27 && program <= 30) {
    // Key-off release RR = 2,5,7,10 (AR15, DR0, SL0, EG1).
    const rr = [2, 5, 7, 10];
    mod.tl = 63;
    carrier.ar = 15;
    carrier.dr = 0;
    carrier.sl = 0;
    carrier.eg = 1;
    carrier.rr = rr[program - 27];
    carrier.tl = 12;
  } else if (program >= 31 && program <= 42) {
    // Carrier MULT ladder, mod silent: registers 0,1,2,3,4,5,6,8,10,12,14,15.
    const mults = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 15];
    mod.tl = 63;
    carrier.mult = mults[program - 31];
    carrier.tl = 12;
  } else if (program == 43) {
    // AM on (carrier AM=1, sustained), sine carrier, mod silent.
    mod.tl = 63;
    carrier.tl = 12;
    carrier.am = 1;
  } else if (program == 44) {
    // VIB on (carrier VIB=1), sine carrier, mod silent.
    mod.tl = 63;
    carrier.tl = 12;
    carrier.vib = 1;
  } else if (program == 45) {
    // AM+VIB on, sine carrier, mod silent.
    mod.tl = 63;
    carrier.tl = 12;
    carrier.am = 1;
    carrier.vib = 1;
  } else if (program == 46) {
    // Velocity/pan reference: same spec as v1 program 45.
    feedback = 2;
    mod.tl = 16;
    carrier.tl = 0;
    mod.eg = 1;
    carrier.eg = 1;
  } else if (program == 47) {
    // Silent control: both TL63.
    mod.tl = 63;
    carrier.tl = 63;
  } else {
    throw ArgumentError.value(program, 'program', 'must be 0..47');
  }

  return _buildRecord(
    mod: mod,
    carrier: carrier,
    feedback: feedback,
    algorithm: algorithm,
  );
}

Uint8List _buildInstrumentV3(int program) {
  final mod = _OpSpec();
  final carrier = _OpSpec();
  var feedback = 0;
  var algorithm = 0;

  // Default carrier env is AR15 DR0 SL0 RR4 EG1 (from _OpSpec); programs
  // that need RR6 set it explicitly. Silent op = TL63.
  switch (program) {
    case 0:
      // Reference sine: same as v1/v2 program 0.
      mod.tl = 63;
      carrier.tl = 12;
    case 1:
      // Wave3 carrier: same as v2 program 1.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.wave = 3;
    case 2:
      // Wave3 modulator + sine carrier: same as v2 program 2.
      mod.tl = 16;
      mod.wave = 3;
      carrier.tl = 12;
    case 3:
      // Feedback brass archetype A: alg0 fb7.
      feedback = 7;
      mod.mult = 0;
      mod.tl = 24;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 4;
      mod.eg = 1;
      mod.ksr = 1;
      mod.wave = 0;
      carrier.mult = 0;
      carrier.tl = 4;
      carrier.ar = 12;
      carrier.dr = 2;
      carrier.sl = 3;
      carrier.rr = 6;
      carrier.eg = 1;
      carrier.vib = 1;
    case 4:
      // Feedback archetype B: alg0 fb5.
      feedback = 5;
      mod.mult = 3;
      mod.tl = 16;
      mod.ar = 15;
      mod.dr = 1;
      mod.sl = 2;
      mod.rr = 4;
      mod.eg = 0;
      mod.wave = 0;
      carrier.mult = 1;
      carrier.tl = 8;
      carrier.ar = 12;
      carrier.dr = 4;
      carrier.sl = 3;
      carrier.rr = 6;
      carrier.eg = 1;
    case 5:
      // Additive silent-carrier: alg1 fb0; op0 sounding sine TL10; op1 silent.
      algorithm = 1;
      mod.tl = 10;
      carrier.tl = 63;
    case 6:
      // Additive both sounding: alg1 fb0.
      algorithm = 1;
      mod.mult = 2;
      mod.tl = 12;
      carrier.mult = 1;
      carrier.tl = 12;
    case 7:
      // Extreme mult pair: alg0 fb7.
      feedback = 7;
      mod.mult = 14;
      mod.wave = 2;
      mod.tl = 12;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 4;
      mod.eg = 0;
      carrier.mult = 10;
      carrier.wave = 3;
      carrier.tl = 10;
      carrier.ar = 15;
      carrier.dr = 2;
      carrier.sl = 0;
      carrier.rr = 4;
      carrier.eg = 0;
    case 8:
      // Zero-decay modulator: alg0 fb2.
      feedback = 2;
      mod.mult = 1;
      mod.tl = 18;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 0;
      mod.eg = 0;
      mod.ksr = 1;
      carrier.mult = 1;
      carrier.tl = 6;
      carrier.ar = 12;
      carrier.dr = 2;
      carrier.sl = 3;
      carrier.rr = 6;
      carrier.eg = 1;
    case 9:
      // Silent attack control: carrier AR0, mod silent.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 0;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 4;
      carrier.eg = 1;
      carrier.ksr = 1;
    case 10:
      // Slow swell: carrier-only AR1.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 1;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 3;
      carrier.eg = 1;
      carrier.ksr = 1;
    case 11:
      // Fast percussive deep: carrier-only AR15 DR15 SL15 RR15 EG0.
      mod.ar = 15;
      mod.dr = 15;
      mod.sl = 15;
      mod.rr = 15;
      mod.eg = 0;
      mod.tl = 63;
      carrier.ar = 15;
      carrier.dr = 15;
      carrier.sl = 15;
      carrier.rr = 15;
      carrier.eg = 0;
      carrier.tl = 12;
    case 12:
      // Percussive nonzero-SL: carrier-only AR15 DR8 SL8 RR3 EG0.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 15;
      carrier.dr = 8;
      carrier.sl = 8;
      carrier.rr = 3;
      carrier.eg = 0;
    case 13:
      // Long release.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 1;
      carrier.eg = 1;
    case 14:
      // Short release.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 15;
      carrier.eg = 1;
    case 15:
      // KSL3 both ops (carrier sounding; mod silent but KSL3 too).
      mod.ksl = 3;
      mod.tl = 63;
      carrier.ksl = 3;
      carrier.tl = 12;
    case 16:
      // KSL1 carrier (mod silent).
      mod.tl = 63;
      carrier.ksl = 1;
      carrier.tl = 12;
    case 17:
      // AM on FM: alg0 fb2, mod/car AM1, both AR15 DR0 SL0 RR6 EG1.
      feedback = 2;
      mod.mult = 1;
      mod.tl = 16;
      mod.am = 1;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.mult = 1;
      carrier.tl = 8;
      carrier.am = 1;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
    case 18:
      // VIB on FM: alg0 fb2, mod/car VIB1, both AR15 DR0 SL0 RR6 EG1.
      feedback = 2;
      mod.mult = 1;
      mod.tl = 16;
      mod.vib = 1;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.mult = 1;
      carrier.tl = 8;
      carrier.vib = 1;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
    case 19:
      // Bend-sensitive FM: alg0 fb4, mod mult2 TL16, car mult1 TL8, RR6 both.
      feedback = 4;
      mod.mult = 2;
      mod.tl = 16;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.mult = 1;
      carrier.tl = 8;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
    case 20:
      // Env mid all.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 6;
      carrier.dr = 6;
      carrier.sl = 6;
      carrier.rr = 6;
      carrier.eg = 1;
    case 21:
      // Env mid long-release.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 6;
      carrier.dr = 6;
      carrier.sl = 6;
      carrier.rr = 1;
      carrier.eg = 1;
    case 22:
      // Env mid short-release.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 6;
      carrier.dr = 6;
      carrier.sl = 6;
      carrier.rr = 15;
      carrier.eg = 1;
    case 23:
      // Slow percussive.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 2;
      carrier.dr = 2;
      carrier.sl = 4;
      carrier.rr = 2;
      carrier.eg = 0;
    case 24:
      // Fast percussive.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 14;
      carrier.dr = 14;
      carrier.sl = 14;
      carrier.rr = 14;
      carrier.eg = 0;
    case 25:
      // Zero-decay release-only.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 10;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 10;
      carrier.eg = 0;
    case 26:
      // Frozen release.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 10;
      carrier.dr = 10;
      carrier.sl = 0;
      carrier.rr = 0;
      carrier.eg = 0;
    case 27:
      // Slow attack zero-decay.
      mod.tl = 63;
      carrier.tl = 12;
      carrier.ar = 3;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 3;
      carrier.eg = 1;
      carrier.ksr = 1;
    case 28 || 29 || 30 || 31 || 33 || 34 || 35:
      // Allocation timbres: simple sustained patches, AR15 DR0 SL0 RR6 EG1,
      // carrier TL12; mod silent except 33 (additive).
      mod.tl = 63;
      carrier.tl = 12;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
      switch (program) {
        case 28:
          carrier.wave = 0;
          carrier.mult = 1;
        case 29:
          carrier.wave = 1;
        case 30:
          carrier.wave = 2;
        case 31:
          carrier.wave = 3;
        case 33:
          algorithm = 1;
          mod.tl = 12;
          mod.mult = 1;
          carrier.mult = 1;
        case 34:
          carrier.mult = 0;
        case 35:
          carrier.mult = 2;
        default:
          throw StateError('unreachable allocation program $program');
      }
    case 32:
      // FM bright fb4: mod TL16 sounding.
      feedback = 4;
      mod.tl = 16;
      mod.mult = 1;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.tl = 12;
      carrier.mult = 1;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
    case 36 || 37 || 38 || 39 || 40 || 41 || 42:
      // MULT ladder carrier-only: mults 0,1,2,4,8,12,15.
      const mults = [0, 1, 2, 4, 8, 12, 15];
      mod.tl = 63;
      carrier.tl = 12;
      carrier.mult = mults[program - 36];
    case 43:
      // Low bass: alg0 fb7.
      feedback = 7;
      mod.mult = 0;
      mod.tl = 18;
      mod.ar = 12;
      mod.dr = 2;
      mod.sl = 4;
      mod.rr = 5;
      mod.eg = 1;
      carrier.mult = 0;
      carrier.tl = 6;
      carrier.ar = 12;
      carrier.dr = 3;
      carrier.sl = 4;
      carrier.rr = 5;
      carrier.eg = 1;
    case 44:
      // High alias: alg0 fb3.
      feedback = 3;
      mod.mult = 14;
      mod.tl = 20;
      mod.wave = 0;
      mod.ar = 15;
      mod.dr = 0;
      mod.sl = 0;
      mod.rr = 6;
      mod.eg = 1;
      carrier.mult = 12;
      carrier.tl = 10;
      carrier.wave = 0;
      carrier.ar = 15;
      carrier.dr = 0;
      carrier.sl = 0;
      carrier.rr = 6;
      carrier.eg = 1;
    case 45:
      // Velocity/pan reference: same as v2 program 46.
      feedback = 2;
      mod.mult = 1;
      mod.tl = 16;
      mod.eg = 1;
      carrier.mult = 1;
      carrier.tl = 0;
      carrier.eg = 1;
    case 46:
      // Generic brass: alg0 fb6; mod TL20 AR12 DR6 SL4 RR6; car TL8 AR12 DR4 SL3 RR6.
      feedback = 6;
      mod.mult = 1;
      mod.tl = 20;
      mod.ar = 12;
      mod.dr = 6;
      mod.sl = 4;
      mod.rr = 6;
      mod.eg = 1;
      carrier.mult = 1;
      carrier.tl = 8;
      carrier.ar = 12;
      carrier.dr = 4;
      carrier.sl = 3;
      carrier.rr = 6;
      carrier.eg = 1;
    case 47:
      // Silent control: both TL63.
      mod.tl = 63;
      carrier.tl = 63;
    default:
      throw ArgumentError.value(program, 'program', 'must be 0..47');
  }

  return _buildRecord(
    mod: mod,
    carrier: carrier,
    feedback: feedback,
    algorithm: algorithm,
  );
}

/// Builds the raw patch-bank payload (without the loose-patch wrapper).
///
/// `instrumentCount` must be 48 (1344 bytes) or 96 (2690 bytes). The 96 form
/// is the 48 records, two separator bytes (0, 0), then the same 48 records
/// again for programs 48..95.
///
/// [kitVersion] selects the v1 (default), v2, or v3 instrument bank; the v1
/// bank is byte-identical regardless of this parameter's default.
Uint8List buildBankPayload({
  required int instrumentCount,
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  if (instrumentCount != 48 && instrumentCount != 96) {
    throw ArgumentError.value(
      instrumentCount,
      'instrumentCount',
      'must be 48 or 96',
    );
  }
  final builderFor = switch (kitVersion) {
    CalibrationKitVersion.v1 => _buildInstrument,
    CalibrationKitVersion.v2 => _buildInstrumentV2,
    CalibrationKitVersion.v3 => _buildInstrumentV3,
  };
  final first = <Uint8List>[for (var p = 0; p < 48; p++) builderFor(p)];
  final builder = BytesBuilder(copy: false);
  if (instrumentCount == 48) {
    for (final record in first) {
      builder.add(record);
    }
  } else {
    for (final record in first) {
      builder.add(record);
    }
    builder.add(const [0, 0]);
    for (final record in first) {
      builder.add(record);
    }
  }
  return builder.toBytes();
}

// ---------------------------------------------------------------------------
// Loose-patch wrapper.
// ---------------------------------------------------------------------------

/// Wraps a raw resource payload as a loose patch file: byte 0 is the Sierra
/// resource type OR'd with 0x80 (sound=4 -> 0x84, patch=9 -> 0x89), byte 1
/// is the extra header length (0), followed by the payload.
Uint8List wrapLoosePatch({required int typeCode, required Uint8List payload}) {
  final wrapped = Uint8List(2 + payload.length);
  wrapped[0] = (typeCode | 0x80) & 0xFF;
  wrapped[1] = 0;
  wrapped.setRange(2, 2 + payload.length, payload);
  return wrapped;
}

// ---------------------------------------------------------------------------
// Sound payload building.
// ---------------------------------------------------------------------------

/// Early-format raw channel bytes for v3 (one byte per channel at
/// `header[1 + ch]`): `(voices << 4) | deviceBits`. Ch1/2 keep v1/v2
/// defaults (0x21 = voices 2 + AdLib); ch3 0xF1 = voices 15 + AdLib
/// (KQ4-style nibble-15 pattern); ch4 0x01 = voices 0 + AdLib; ch5
/// 0x11 = voices 1 + AdLib; ch9 0x09 = voices 0 + control flag +
/// AdLib; ch12 0x11 = voices 1 + AdLib. Unlisted channels are 0.
const Map<int, int> _kV3EarlyRaw = {
  1: 0x21,
  2: 0x21,
  3: 0xF1,
  4: 0x01,
  5: 0x11,
  9: 0x09,
  12: 0x11,
};

/// Late-format voice counts for v3 (pair `[voices, 0x04]` per channel).
/// Unlisted channels are `[0, 0]`.
const Map<int, int> _kV3LateVoices = {
  1: 2,
  2: 2,
  3: 15,
  4: 0,
  5: 1,
  9: 1,
  12: 1,
};

/// Per-channel override map for v3 headers, selected by format: early
/// values are full raw bytes, late values are voice counts (play mask
/// is always 0x04 AdLib for listed channels).
Map<int, int> _v3OverridesFor(SoundHeaderFormat format) {
  return format == SoundHeaderFormat.early ? _kV3EarlyRaw : _kV3LateVoices;
}

/// Builds an SCI0 sound header. Without [channelOverrides] (the v1/v2
/// default) channels 1 and 2 get voices=2 + AdLib and every other
/// channel is 0. With [channelOverrides] (v3 only) each listed channel
/// is written exactly: early uses the raw byte, late uses the voice
/// count with AdLib play mask 0x04; unlisted channels are 0.
Uint8List _buildHeader(
  SoundHeaderFormat format, {
  Map<int, int>? channelOverrides,
}) {
  final header = format == SoundHeaderFormat.early
      ? Uint8List(kHeaderEarlySize)
      : Uint8List(kHeaderLateSize);
  header[0] = 0; // flags: no digital sample.
  if (channelOverrides != null) {
    if (format == SoundHeaderFormat.early) {
      for (final entry in channelOverrides.entries) {
        header[1 + entry.key] = entry.value & 0xFF;
      }
    } else {
      for (final entry in channelOverrides.entries) {
        header[1 + entry.key * 2] = entry.value & 0xFF;
        header[1 + entry.key * 2 + 1] = 0x04; // AdLib play mask.
      }
    }
    return header;
  }
  if (format == SoundHeaderFormat.early) {
    for (var ch = 0; ch < 16; ch++) {
      if (ch == kChannelA || ch == kChannelB) {
        header[1 + ch] = (2 << 4) | 0x01; // voices=2, AdLib device bit.
      }
    }
  } else {
    for (var ch = 0; ch < 16; ch++) {
      if (ch == kChannelA || ch == kChannelB) {
        header[1 + ch * 2] = 2; // voice count
        header[1 + ch * 2 + 1] = 0x04; // AdLib play mask.
      }
    }
  }
  return header;
}

void _writeDelta(List<int> out, int gap) {
  var d = gap;
  while (d >= 240) {
    out.add(0xF8);
    d -= 240;
  }
  out.add(d & 0xFF);
}

/// Stateful SCI0 sound-stream writer: absolute-tick event placement with
/// delta encoding per the brief (0xF8 advances 240 ticks, then one delta
/// byte 0..239). Always writes the status byte.
final class _SoundWriter {
  final List<int> out = [];
  int currentTick = 0;

  _SoundWriter(Uint8List header) {
    out.addAll(header);
  }

  void event(int tick, List<int> statusAndData) {
    if (tick < currentTick) {
      throw StateError(
        'event ticks must be non-decreasing: $tick < $currentTick',
      );
    }
    _writeDelta(out, tick - currentTick);
    out.addAll(statusAndData);
    currentTick = tick;
  }

  void noteOn(int tick, int channel, int note, int velocity) {
    event(tick, [0x90 | channel, note, velocity]);
  }

  void noteOff(int tick, int channel, int note) {
    event(tick, [0x80 | channel, note, 0]);
  }

  void program(int tick, int channel, int program) {
    event(tick, [0xC0 | channel, program]);
  }

  void control(int tick, int channel, int cc, int value) {
    event(tick, [0xB0 | channel, cc, value]);
  }

  void pitchBend(int tick, int channel, int value) {
    final v = value.clamp(0, 16383);
    event(tick, [0xE0 | channel, v & 0x7F, (v >> 7) & 0x7F]);
  }

  /// Finishes the stream: writes [trailingTicks] of trailing silence and
  /// the end-of-track byte. Returns the total tick count.
  int finish({int trailingTicks = 0}) {
    _writeDelta(out, trailingTicks);
    out.add(0xFC);
    currentTick += trailingTicks;
    return currentTick;
  }

  Uint8List bytes() => Uint8List.fromList(out);
}

void _initialControllers(
  _SoundWriter w, {
  bool includeChannelB = false,
  List<int> extraChannels = const [],
}) {
  w.control(0, kChannelA, 7, 127);
  w.control(0, kChannelA, 10, 64);
  w.control(0, kChannelA, 64, 0);
  if (includeChannelB) {
    w.control(0, kChannelB, 7, 127);
    w.control(0, kChannelB, 10, 64);
    w.control(0, kChannelB, 64, 0);
  }
  for (final ch in extraChannels) {
    w.control(0, ch, 7, 127);
    w.control(0, ch, 10, 64);
    w.control(0, ch, 64, 0);
  }
}

SoundResourceData _buildSound990(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 990;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  for (var p = 0; p < 20; p++) {
    final end = start + 120; // 90 hold + 30 silence.
    w.program(start, kChannelA, p);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(start + 90, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: p,
        startTick: start,
        endTick: end,
        program: p,
        channel: '1',
        note: '69',
        purpose: 'core timbre program $p',
      ),
    );
    start = end;
  }
  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound991(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 991;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addSegment({
    required int program,
    required int hold,
    required int gap,
    required String purpose,
    required int gate,
  }) {
    final noteOffTick = start + gate;
    final end = start + hold + gap;
    w.program(start, kChannelA, program);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(noteOffTick, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: program,
        channel: '1',
        note: '69',
        purpose: purpose,
      ),
    );
    start = end;
  }

  // Programs 20..26: attack ladder, held 180 + 30 silence.
  const attackAr = [1, 4, 6, 8, 10, 12, 15];
  for (var i = 0; i < 7; i++) {
    addSegment(
      program: 20 + i,
      hold: 180,
      gap: 30,
      gate: 180,
      purpose: 'attack AR=${attackAr[i]}',
    );
  }
  // Programs 27..30: decay-to-sustain AR15 SL12, held 240 + 30 silence.
  const decayDr = [1, 4, 8, 12];
  for (var i = 0; i < 4; i++) {
    addSegment(
      program: 27 + i,
      hold: 240,
      gap: 30,
      gate: 240,
      purpose: 'decay-to-sustain DR=${decayDr[i]} SL=12',
    );
  }
  // Programs 31..34: percussive EG0, held 180 + 30 silence.
  const percRr = [1, 3, 6, 10];
  for (var i = 0; i < 4; i++) {
    addSegment(
      program: 31 + i,
      hold: 180,
      gap: 30,
      gate: 180,
      purpose: 'percussive EG0 RR=${percRr[i]}',
    );
  }
  // Programs 35..38: release, gate 30 + 150 silence.
  const relRr = [1, 4, 8, 12];
  for (var i = 0; i < 4; i++) {
    addSegment(
      program: 35 + i,
      hold: 30,
      gap: 150,
      gate: 30,
      purpose: 'release RR=${relRr[i]} gate 30',
    );
  }

  // The last segment's trailing silence ends at [start]; the writer
  // currently sits at the last noteOff. When terminating, write the
  // silence delta; otherwise leave it to the next appended chunk.
  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound992(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 992;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addNote({
    required int program,
    required int note,
    required int hold,
    required int gap,
    required String purpose,
  }) {
    final end = start + hold + gap;
    w.program(start, kChannelA, program);
    w.noteOn(start, kChannelA, note, 96);
    w.noteOff(start + hold, kChannelA, note);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: program,
        channel: '1',
        note: '$note',
        purpose: purpose,
      ),
    );
    start = end;
  }

  // Programs 39..42 KSL ladder: notes 36,48,60,72,84,96, hold 45 gap 15.
  const kslNotes = [36, 48, 60, 72, 84, 96];
  for (var p = 39; p <= 42; p++) {
    for (final note in kslNotes) {
      addNote(
        program: p,
        note: note,
        hold: 45,
        gap: 15,
        purpose: 'KSL=${p - 39} note $note',
      );
    }
  }
  // Programs 43 (KSR0) then 44 (KSR1): notes 36,60,84,96, hold 120 gap 30.
  const ksrNotes = [36, 60, 84, 96];
  for (final p in [43, 44]) {
    for (final note in ksrNotes) {
      addNote(
        program: p,
        note: note,
        hold: 120,
        gap: 30,
        purpose: 'KSR ${p == 43 ? 'off' : 'on'} note $note',
      );
    }
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound993(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 993;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w, includeChannelB: true);
  var start = tickOffset;
  var index = 0;

  void addVelocityGroup({
    required int enableVelocity,
    required String purposePrefix,
  }) {
    const velocities = [16, 32, 64, 96, 127];
    // CC 0x4E once before the group.
    w.control(start, kChannelA, 0x4E, enableVelocity);
    for (final velocity in velocities) {
      final end = start + 60; // held 45 + gap 15.
      w.program(start, kChannelA, 45);
      w.noteOn(start, kChannelA, 69, velocity);
      w.noteOff(start + 45, kChannelA, 69);
      segments.add(
        CalibrationSegment(
          resourceNumber: resource,
          segmentIndex: index++,
          startTick: start,
          endTick: end,
          program: 45,
          channel: '1',
          note: '69',
          purpose: '$purposePrefix vel $velocity',
        ),
      );
      start = end;
    }
  }

  addVelocityGroup(enableVelocity: 0, purposePrefix: 'velocity (disabled)');
  addVelocityGroup(enableVelocity: 127, purposePrefix: 'velocity (enabled)');

  // Pan sweep on ch1: values 0,32,64,96,127, held 60 + gap 15.
  const pans = [0, 32, 64, 96, 127];
  for (final pan in pans) {
    final end = start + 75;
    w.program(start, kChannelA, 45);
    w.control(start, kChannelA, 10, pan);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(start + 60, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: 45,
        channel: '1',
        note: '69',
        purpose: 'pan $pan',
      ),
    );
    start = end;
  }

  // Duet: two halves, back-to-back (gap 0 at the join).
  for (var half = 0; half < 2; half++) {
    final end = start + 120;
    final chANote = half == 0 ? 69 : 76;
    final chBNote = half == 0 ? 76 : 69;
    final chAPan = half == 0 ? 0 : 127;
    final chBPan = half == 0 ? 127 : 0;
    w.program(start, kChannelA, 45);
    w.program(start, kChannelB, 45);
    w.control(start, kChannelA, 10, chAPan);
    w.control(start, kChannelB, 10, chBPan);
    w.noteOn(start, kChannelA, chANote, 96);
    w.noteOn(start, kChannelB, chBNote, 96);
    w.noteOff(start + 120, kChannelA, chANote);
    w.noteOff(start + 120, kChannelB, chBNote);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: 45,
        channel: '1,2',
        note: '$chANote/$chBNote',
        purpose:
            'duet ${half == 0 ? 'A' : 'B'} (ch1 note $chANote pan $chAPan, ch2 note $chBNote pan $chBPan)',
      ),
    );
    start = end;
  }

  // Bend: program 46, note 69 held 240 with bend every 15 ticks:
  // 8192 -> 16383 over 120 ticks, then -> 0 over 120 ticks (17 points).
  {
    final noteStart = start;
    final end = start + 240;
    w.program(noteStart, kChannelA, 46);
    w.noteOn(noteStart, kChannelA, 69, 96);
    for (var offset = 0; offset <= 240; offset += 15) {
      final double value;
      if (offset <= 120) {
        value = 8192 + (16383 - 8192) * offset / 120;
      } else {
        value = 16383 - 16383 * (offset - 120) / 120;
      }
      w.pitchBend(noteStart + offset, kChannelA, value.round());
    }
    w.noteOff(noteStart + 240, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: noteStart,
        endTick: end,
        program: 46,
        channel: '1',
        note: '69',
        purpose: 'bend sweep 8192->16383->0',
      ),
    );
    start = end;
  }

  final total = terminate ? w.finish(trailingTicks: 0) : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound990V2(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 990;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addNote({
    required int program,
    required int note,
    required int hold,
    required int gap,
    required String purpose,
  }) {
    final end = start + hold + gap;
    w.program(start, kChannelA, program);
    w.noteOn(start, kChannelA, note, 96);
    w.noteOff(start + hold, kChannelA, note);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: program,
        channel: '1',
        note: '$note',
        purpose: purpose,
      ),
    );
    start = end;
  }

  // Programs 1..2: wave3 carrier / wave3 modulator, notes held 60 + 20 gap.
  const waveNotes = [45, 57, 69, 81, 93];
  for (final p in [1, 2]) {
    for (final note in waveNotes) {
      addNote(
        program: p,
        note: note,
        hold: 60,
        gap: 20,
        purpose: 'wave3 ${p == 1 ? 'carrier' : 'modulator'} prog $p note $note',
      );
    }
  }
  // Feedback matrix 3..8: note 69 held 120+30, then note 57 held 120+30.
  for (var p = 3; p <= 8; p++) {
    addNote(
      program: p,
      note: 69,
      hold: 120,
      gap: 30,
      purpose: 'feedback matrix prog $p note 69',
    );
    addNote(
      program: p,
      note: 57,
      hold: 120,
      gap: 30,
      purpose: 'feedback matrix prog $p note 57',
    );
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound991V2(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 991;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addSegment({
    required int program,
    required int hold,
    required int gap,
    required String purpose,
    required int gate,
  }) {
    final noteOffTick = start + gate;
    final end = start + hold + gap;
    w.program(start, kChannelA, program);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(noteOffTick, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: program,
        channel: '1',
        note: '69',
        purpose: purpose,
      ),
    );
    start = end;
  }

  const attackAr = [2, 3, 5, 7, 9, 11];
  for (var i = 0; i < 6; i++) {
    addSegment(
      program: 9 + i,
      hold: 210,
      gap: 30,
      gate: 210,
      purpose: 'attack AR=${attackAr[i]}',
    );
  }
  const decayDr = [2, 3, 5, 6, 7, 9];
  for (var i = 0; i < 6; i++) {
    addSegment(
      program: 15 + i,
      hold: 270,
      gap: 30,
      gate: 270,
      purpose: 'decay-to-sustain DR=${decayDr[i]} SL=12',
    );
  }
  const percRr = [2, 3, 4, 5, 6, 8];
  for (var i = 0; i < 6; i++) {
    addSegment(
      program: 21 + i,
      hold: 210,
      gap: 30,
      gate: 210,
      purpose: 'percussive EG0 RR=${percRr[i]}',
    );
  }
  const relRr = [2, 5, 7, 10];
  for (var i = 0; i < 4; i++) {
    addSegment(
      program: 27 + i,
      hold: 30,
      gap: 150,
      gate: 30,
      purpose: 'release RR=${relRr[i]} gate 30',
    );
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound992V2(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 992;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addNote({
    required int program,
    required int note,
    required int hold,
    required int gap,
    required String purpose,
  }) {
    final end = start + hold + gap;
    w.program(start, kChannelA, program);
    w.noteOn(start, kChannelA, note, 96);
    w.noteOff(start + hold, kChannelA, note);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: program,
        channel: '1',
        note: '$note',
        purpose: purpose,
      ),
    );
    start = end;
  }

  // MULT ladder 31..42: each note 60 held 60 + 15 gap.
  const mults = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 15];
  for (var p = 31; p <= 42; p++) {
    addNote(
      program: p,
      note: 60,
      hold: 60,
      gap: 15,
      purpose: 'MULT=${mults[p - 31]} note 60',
    );
  }
  // Program 0 pitch-boundary ladder: notes held 45 + 15 gap.
  const boundaryNotes = [35, 36, 47, 48, 59, 60, 71, 72, 83, 84, 95, 96];
  for (final note in boundaryNotes) {
    addNote(
      program: 0,
      note: note,
      hold: 45,
      gap: 15,
      purpose: 'pitch boundary note $note',
    );
  }
  // Bend steps: program 0, note 69 held 270 with pitch-bend every 30
  // ticks; the first bend is set BEFORE the note onset (so a capture
  // sees the value in force for the whole step).
  const bendValues = [0, 2048, 4096, 6144, 8192, 10240, 12288, 14336, 16383];
  {
    final noteStart = start;
    w.program(noteStart, kChannelA, 0);
    w.pitchBend(noteStart, kChannelA, bendValues[0]);
    w.noteOn(noteStart, kChannelA, 69, 96);
    for (var step = 0; step < bendValues.length; step++) {
      final stepStart = noteStart + step * 30;
      if (step > 0) {
        w.pitchBend(stepStart, kChannelA, bendValues[step]);
      }
      segments.add(
        CalibrationSegment(
          resourceNumber: resource,
          segmentIndex: index++,
          startTick: stepStart,
          endTick: stepStart + 30,
          program: 0,
          channel: '1',
          note: '69',
          purpose: 'bend ${bendValues[step]}',
        ),
      );
    }
    w.noteOff(noteStart + 270, kChannelA, 69);
    start = noteStart + 270;
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound993V2(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 993;
  final segments = <CalibrationSegment>[];
  final w = writer ?? _SoundWriter(_buildHeader(format));
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  // LFO programs 43..45: note 69 held 300 each.
  const lfoPurposes = {43: 'AM on', 44: 'VIB on', 45: 'AM+VIB on'};
  for (final p in [43, 44, 45]) {
    final end = start + 300;
    w.program(start, kChannelA, p);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(start + 300, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: p,
        channel: '1',
        note: '69',
        purpose: lfoPurposes[p]!,
      ),
    );
    start = end;
  }

  // (a) Polyphony chord: 10 notes same tick, held 120.
  {
    const notes = [60, 64, 67, 72, 76, 79, 84, 88, 91, 96];
    final end = start + 120;
    w.program(start, kChannelA, 46);
    for (final note in notes) {
      w.noteOn(start, kChannelA, note, 96);
    }
    for (final note in notes) {
      w.noteOff(start + 120, kChannelA, note);
    }
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: 46,
        channel: '1',
        note: notes.join('/'),
        purpose: 'polyphony chord (10 notes) held 120',
      ),
    );
    start = end;
  }
  // (b) Same-tick triplet repeated 4x every 30 ticks (notes 69,76,81).
  {
    const notes = [69, 76, 81];
    for (var rep = 0; rep < 4; rep++) {
      final end = start + 30;
      w.program(start, kChannelA, 46);
      for (final note in notes) {
        w.noteOn(start, kChannelA, note, 96);
      }
      for (final note in notes) {
        w.noteOff(start + 30, kChannelA, note);
      }
      segments.add(
        CalibrationSegment(
          resourceNumber: resource,
          segmentIndex: index++,
          startTick: start,
          endTick: end,
          program: 46,
          channel: '1',
          note: notes.join('/'),
          purpose: 'polyphony triplet rep $rep',
        ),
      );
      start = end;
    }
  }
  // (c) Rapid retrigger note 69 every 8 ticks x16 (gate 6).
  for (var rep = 0; rep < 16; rep++) {
    final end = start + 8;
    w.program(start, kChannelA, 46);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(start + 6, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: 46,
        channel: '1',
        note: '69',
        purpose: 'rapid retrigger rep $rep gate 6',
      ),
    );
    start = end;
  }
  // (d) Pedal stack: CC64=127, notes 60,64,67,72,76,79,84 each gate 20
  // stagger 25, then CC64=0. One segment covering the whole stack.
  {
    const notes = [60, 64, 67, 72, 76, 79, 84];
    final stackStart = start;
    w.control(stackStart, kChannelA, 64, 127);
    w.program(stackStart, kChannelA, 46);
    for (final note in notes) {
      w.noteOn(start, kChannelA, note, 96);
      w.noteOff(start + 20, kChannelA, note);
      start += 25;
    }
    // start now sits one stagger slot past the last onset; release
    // the pedal there, 5 ticks after the last noteOff.
    w.control(start, kChannelA, 64, 0);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: stackStart,
        endTick: start,
        program: 46,
        channel: '1',
        note: notes.join('/'),
        purpose:
            'pedal stack CC64=127 notes ${notes.join('/')} gate 20 stagger 25 CC64=0',
      ),
    );
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound990V3(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 990;
  final segments = <CalibrationSegment>[];
  final w =
      writer ??
      _SoundWriter(
        _buildHeader(format, channelOverrides: _v3OverridesFor(format)),
      );
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  // Retrigger series per program: note69 gate60, then repeats with
  // off-gaps [1,2,5,15,60] between noteOff and next noteOn (6 notes),
  // plus a 30-tick tail. One segment per program.
  const retriggerGaps = [1, 2, 5, 15, 60];
  for (final p in [20, 21, 22, 23, 24, 26]) {
    final segStart = start;
    w.program(segStart, kChannelA, p);
    var cursor = segStart;
    for (var i = 0; i < 6; i++) {
      w.noteOn(cursor, kChannelA, 69, 96);
      w.noteOff(cursor + 60, kChannelA, 69);
      if (i < 5) {
        cursor += 60 + retriggerGaps[i];
      } else {
        cursor += 60;
      }
    }
    final end = cursor + 30;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: p,
        channel: '1',
        note: '69',
        purpose: 'retrigger off-gaps 1,2,5,15,60 prog $p',
      ),
    );
    start = end;
  }

  // Key-off-during-attack: gates [3,10,30,90] with 60 silence between,
  // one segment per program, plus a 30-tick tail.
  const keyOffGates = [3, 10, 30, 90];
  for (final p in [10, 27]) {
    final segStart = start;
    w.program(segStart, kChannelA, p);
    var cursor = segStart;
    for (var i = 0; i < keyOffGates.length; i++) {
      w.noteOn(cursor, kChannelA, 69, 96);
      w.noteOff(cursor + keyOffGates[i], kChannelA, 69);
      if (i < keyOffGates.length - 1) {
        cursor += keyOffGates[i] + 60;
      } else {
        cursor += keyOffGates[i];
      }
    }
    final end = cursor + 30;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: p,
        channel: '1',
        note: '69',
        purpose: 'key-off-during-attack gates 3,10,30,90 prog $p',
      ),
    );
    start = end;
  }

  // Program-change-while-sounding: prog0 note69 held to +180 with a
  // program change to 11 at +60 (no noteOff), 30 silence, then retrigger
  // on prog11 held 120. Program is -1: the segment selects two programs.
  {
    final segStart = start;
    w.program(segStart, kChannelA, 0);
    w.noteOn(segStart, kChannelA, 69, 96);
    w.program(segStart + 60, kChannelA, 11);
    w.noteOff(segStart + 180, kChannelA, 69);
    w.noteOn(segStart + 210, kChannelA, 69, 96);
    w.noteOff(segStart + 330, kChannelA, 69);
    final end = segStart + 330;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: -1,
        channel: '1',
        note: '69',
        purpose: 'program-change-while-sounding 0->11 at +60 held 180, retrigger held 120',
      ),
    );
    start = end;
  }

  // Bend-during-attack/release on program 19: note71 held 240 with bend
  // steps every 30 ticks (8 steps cover attack+sustain), then bend reset.
  const bendSteps = [8192, 12288, 16383, 12288, 8192, 4096, 0, 4096];
  {
    final segStart = start;
    w.program(segStart, kChannelA, 19);
    w.pitchBend(segStart, kChannelA, bendSteps[0]);
    w.noteOn(segStart, kChannelA, 71, 96);
    for (var step = 1; step < bendSteps.length; step++) {
      w.pitchBend(segStart + step * 30, kChannelA, bendSteps[step]);
    }
    w.noteOff(segStart + 240, kChannelA, 71);
    w.pitchBend(segStart + 240, kChannelA, 8192);
    final end = segStart + 240;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 19,
        channel: '1',
        note: '71',
        purpose: 'bend-during-attack/release steps 8192,12288,16383,12288,8192,4096,0,4096 held 240',
      ),
    );
    start = end;
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound991V3(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 991;
  final segments = <CalibrationSegment>[];
  final w =
      writer ??
      _SoundWriter(
        _buildHeader(format, channelOverrides: _v3OverridesFor(format)),
      );
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  void addSegment({
    required int program,
    required List<int> notes,
    required String purpose,
  }) {
    final segStart = start;
    w.program(segStart, kChannelA, program);
    var cursor = segStart;
    for (final note in notes) {
      w.noteOn(cursor, kChannelA, note, 96);
      w.noteOff(cursor + 90, kChannelA, note);
      cursor += 120; // held 90 + 30 gap (also after the last note).
    }
    final end = cursor;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: program,
        channel: '1',
        note: notes.join('/'),
        purpose: purpose,
      ),
    );
    start = end;
  }

  // Program 9 (silent attack control) near the start: notes 36 and 96.
  addSegment(
    program: 9,
    notes: const [36, 96],
    purpose: 'rare archetype silent-attack-control prog 9 notes 36/96',
  );
  // Rare timbres: notes 57 then 81 held 90 each (+30 gap).
  for (final p in [1, 2, 3, 4, 5, 6, 7, 8, 43, 44]) {
    addSegment(
      program: p,
      notes: const [57, 81],
      purpose: 'rare archetype prog $p notes 57/81',
    );
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound992V3(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 992;
  final segments = <CalibrationSegment>[];
  final w =
      writer ??
      _SoundWriter(
        _buildHeader(format, channelOverrides: _v3OverridesFor(format)),
      );
  if (writer == null) _initialControllers(w);
  var start = tickOffset;
  var index = 0;

  // MULT ladder 36..42: note60 held 60 + 15 gap.
  const mults = [0, 1, 2, 4, 8, 12, 15];
  for (var p = 36; p <= 42; p++) {
    final end = start + 75;
    w.program(start, kChannelA, p);
    w.noteOn(start, kChannelA, 60, 96);
    w.noteOff(start + 60, kChannelA, 60);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: p,
        channel: '1',
        note: '60',
        purpose: 'MULT=${mults[p - 36]} note 60',
      ),
    );
    start = end;
  }

  // Semitone ladder 60..72 on programs 15 then 16 (KSL3 / KSL1),
  // each held 40 + 10 gap, one segment per program.
  for (final p in [15, 16]) {
    final segStart = start;
    w.program(segStart, kChannelA, p);
    var cursor = segStart;
    for (var note = 60; note <= 72; note++) {
      w.noteOn(cursor, kChannelA, note, 96);
      w.noteOff(cursor + 40, kChannelA, note);
      cursor += 50; // held 40 + 10 gap (also after the last note).
    }
    final end = cursor;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: p,
        channel: '1',
        note: '60-72',
        purpose: 'KSL${p == 15 ? '3' : '1'} semitone ladder 60..72',
      ),
    );
    start = end;
  }

  // Program 19 bend statics: notes 71 and 72, each with bend values
  // [0,4096,8192,12288,16383] as separate 40-tick notes (bend set before
  // each noteOn, reset to 8192 after each noteOff).
  const bendValues = [0, 4096, 8192, 12288, 16383];
  for (final note in [71, 72]) {
    for (final bend in bendValues) {
      final end = start + 40;
      w.program(start, kChannelA, 19);
      w.pitchBend(start, kChannelA, bend);
      w.noteOn(start, kChannelA, note, 96);
      w.noteOff(start + 40, kChannelA, note);
      w.pitchBend(start + 40, kChannelA, 8192);
      segments.add(
        CalibrationSegment(
          resourceNumber: resource,
          segmentIndex: index++,
          startTick: start,
          endTick: end,
          program: 19,
          channel: '1',
          note: '$note',
          purpose: 'bend static note $note bend $bend',
        ),
      );
      start = end;
    }
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

SoundResourceData _buildSound993V3(
  SoundHeaderFormat format, {
  int tickOffset = 0,
  _SoundWriter? writer,
  bool terminate = true,
}) {
  const resource = 993;
  final segments = <CalibrationSegment>[];
  final w =
      writer ??
      _SoundWriter(
        _buildHeader(format, channelOverrides: _v3OverridesFor(format)),
      );
  if (writer == null) {
    _initialControllers(
      w,
      includeChannelB: true,
      extraChannels: const [3, 4, 5, 9, 12],
    );
  }
  var start = tickOffset;
  var index = 0;

  // LFO programs 17 (AM in FM) and 18 (VIB in FM): note69 held 300 each.
  for (final p in [17, 18]) {
    final end = start + 300;
    w.program(start, kChannelA, p);
    w.noteOn(start, kChannelA, 69, 96);
    w.noteOff(start + 300, kChannelA, 69);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: start,
        endTick: end,
        program: p,
        channel: '1',
        note: '69',
        purpose: p == 17 ? 'AM in FM context' : 'VIB in FM context',
      ),
    );
    start = end;
  }

  // (a) CC75 sustain-while-active: ch1 prog28 notes 69+76 sustained
  // (gate 240), at +60 CC75 voices=1, at +120 add note 81, at +180
  // CC75 voices=2, noteOff all at +240.
  {
    final segStart = start;
    w.program(segStart, kChannelA, 28);
    w.noteOn(segStart, kChannelA, 69, 96);
    w.noteOn(segStart, kChannelA, 76, 96);
    w.control(segStart + 60, kChannelA, 0x4B, 1); // CC75 sustain.
    w.noteOn(segStart + 120, kChannelA, 81, 96);
    w.control(segStart + 180, kChannelA, 0x4B, 2); // CC75 sustain.
    w.noteOff(segStart + 240, kChannelA, 69);
    w.noteOff(segStart + 240, kChannelA, 76);
    w.noteOff(segStart + 240, kChannelA, 81);
    final end = segStart + 240;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 28,
        channel: '1',
        note: '69/76/81',
        purpose: 'CC75 sustain-while-active voices 1 at +60, note 81 at +120, voices 2 at +180',
      ),
    );
    start = end;
  }

  // (b) CC7 fade-while-active: ch1 prog29 note69 held 240, CC7 steps
  // [127,96,64,32,64,127] every 40 ticks.
  {
    final segStart = start;
    const cc7Steps = [127, 96, 64, 32, 64, 127];
    w.program(segStart, kChannelA, 29);
    w.noteOn(segStart, kChannelA, 69, 96);
    for (var i = 0; i < cc7Steps.length; i++) {
      w.control(segStart + i * 40, kChannelA, 7, cc7Steps[i]);
    }
    w.noteOff(segStart + 240, kChannelA, 69);
    final end = segStart + 240;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 29,
        channel: '1',
        note: '69',
        purpose: 'CC7 volume-fade-while-active steps 127,96,64,32,64,127',
      ),
    );
    start = end;
  }

  // (c) CC78 toggle-while-active: ch1 prog45 note69 vel40 held 120 with
  // CC78=1 at +60 (no retrigger), then the same note vel40 held 120 (now
  // velocity-enabled), CC78=0 after.
  {
    final segStart = start;
    w.program(segStart, kChannelA, 45);
    w.noteOn(segStart, kChannelA, 69, 40);
    w.control(segStart + 60, kChannelA, 0x4E, 1); // CC78 velocity enable.
    w.noteOff(segStart + 120, kChannelA, 69);
    w.noteOn(segStart + 120, kChannelA, 69, 40);
    w.noteOff(segStart + 240, kChannelA, 69);
    w.control(segStart + 240, kChannelA, 0x4E, 0); // CC78 velocity enable.
    final end = segStart + 240;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 45,
        channel: '1',
        note: '69',
        purpose: 'CC78 velocity-enable-toggle-while-active at +60, second vel40 note enabled',
      ),
    );
    start = end;
  }

  // (d) Zero-voice/control channels: notes on ch4 (header voices=0) and
  // ch9 at the same tick where ch1 plays a marker note.
  {
    final segStart = start;
    w.program(segStart, kChannelA, 28);
    w.program(segStart, 4, 28);
    w.program(segStart, 9, 28);
    w.noteOn(segStart, kChannelA, 60, 96);
    w.noteOn(segStart, 4, 69, 96);
    w.noteOn(segStart, 9, 72, 96);
    w.noteOff(segStart + 90, kChannelA, 60);
    w.noteOff(segStart + 90, 4, 69);
    w.noteOff(segStart + 90, 9, 72);
    final end = segStart + 120;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 28,
        channel: '1,4,9',
        note: '60/69/72',
        purpose: 'zero-voice/control channels ch4 voices=0, ch9 with ch1 marker note 60',
      ),
    );
    start = end;
  }

  // (e) Same-tick chord of 6 notes on ch3 (early raw nibble 15 / late
  // voices=15) prog30, held 120.
  {
    const notes = [60, 64, 67, 72, 76, 79];
    final segStart = start;
    w.program(segStart, 3, 30);
    for (final note in notes) {
      w.noteOn(segStart, 3, note, 96);
    }
    for (final note in notes) {
      w.noteOff(segStart + 120, 3, note);
    }
    final end = segStart + 120;
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: segStart,
        endTick: end,
        program: 30,
        channel: '3',
        note: notes.join('/'),
        purpose:
            'same-tick 6-note chord on ch3 nibble-15/voices-15 header prog 30',
      ),
    );
    start = end;
  }

  // (f) Pedal stack on ch5 prog31: CC64=127, staggered notes
  // [60,64,67,72] gate20 stagger25, then CC64=0 (header voices=1 forces
  // steal-on-pedal behavior).
  {
    const notes = [60, 64, 67, 72];
    final stackStart = start;
    w.control(stackStart, 5, 64, 127);
    w.program(stackStart, 5, 31);
    for (final note in notes) {
      w.noteOn(start, 5, note, 96);
      w.noteOff(start + 20, 5, note);
      start += 25;
    }
    w.control(start, 5, 64, 0);
    segments.add(
      CalibrationSegment(
        resourceNumber: resource,
        segmentIndex: index++,
        startTick: stackStart,
        endTick: start,
        program: 31,
        channel: '5',
        note: notes.join('/'),
        purpose: 'pedal stack steal-on-pedal on ch5 voices=1 CC64 gate 20 stagger 25',
      ),
    );
  }

  final total = terminate
      ? w.finish(trailingTicks: start - w.currentTick)
      : start;
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

/// Builds one calibration sound resource payload and its segments.
SoundResourceData buildSoundResource({
  required int resourceNumber,
  required SoundHeaderFormat format,
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  if (kitVersion == CalibrationKitVersion.v2) {
    return switch (resourceNumber) {
      990 => _buildSound990V2(format),
      991 => _buildSound991V2(format),
      992 => _buildSound992V2(format),
      993 => _buildSound993V2(format),
      _ => throw ArgumentError.value(
        resourceNumber,
        'resourceNumber',
        'must be 990..993',
      ),
    };
  }
  if (kitVersion == CalibrationKitVersion.v3) {
    return switch (resourceNumber) {
      990 => _buildSound990V3(format),
      991 => _buildSound991V3(format),
      992 => _buildSound992V3(format),
      993 => _buildSound993V3(format),
      _ => throw ArgumentError.value(
        resourceNumber,
        'resourceNumber',
        'must be 990..993',
      ),
    };
  }
  return switch (resourceNumber) {
    990 => _buildSound990(format),
    991 => _buildSound991(format),
    992 => _buildSound992(format),
    993 => _buildSound993(format),
    _ => throw ArgumentError.value(
      resourceNumber,
      'resourceNumber',
      'must be 990..993',
    ),
  };
}

/// Builds the combined intro drop-in track: the four calibration
/// resources (990 core, 991 envelopes, 992 pitch/KSL/KSR, 993 velocity/
/// pan/bend) concatenated in that order into one sound payload with a
/// [kCombinedGapTicks] silence gap between former resources. The final
/// segment's `endTick` equals [SoundResourceData.totalTicks]. Segments
/// keep their original resource numbers with offset absolute ticks.
SoundResourceData buildCombinedSoundResource({
  required SoundHeaderFormat format,
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  final isV3 = kitVersion == CalibrationKitVersion.v3;
  final w = _SoundWriter(
    _buildHeader(
      format,
      channelOverrides: isV3 ? _v3OverridesFor(format) : null,
    ),
  );
  _initialControllers(
    w,
    includeChannelB: true,
    extraChannels: isV3 ? const [3, 4, 5, 9, 12] : const [],
  );
  final segments = <CalibrationSegment>[];
  var offset = 0;
  final parts = switch (kitVersion) {
    CalibrationKitVersion.v2 => <SoundResourceData Function(int, _SoundWriter)>[
      (o, writer) => _buildSound990V2(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound991V2(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound992V2(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound993V2(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
    ],
    CalibrationKitVersion.v3 => <SoundResourceData Function(int, _SoundWriter)>[
      (o, writer) => _buildSound990V3(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound991V3(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound992V3(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound993V3(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
    ],
    CalibrationKitVersion.v1 => <SoundResourceData Function(int, _SoundWriter)>[
      (o, writer) => _buildSound990(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound991(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound992(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
      (o, writer) => _buildSound993(
        format,
        tickOffset: o,
        writer: writer,
        terminate: false,
      ),
    ],
  };
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i](offset, w);
    segments.addAll(part.segments);
    // part.totalTicks is the absolute end of this chunk; the next chunk
    // starts after the gap.
    offset = part.totalTicks + kCombinedGapTicks;
  }
  // Strip the trailing gap added after the last chunk: the writer sits
  // at the last noteOff, so finishing with 0 trailing ticks lands the
  // end-of-track at the last segment's endTick.
  final total = w.finish(trailingTicks: 0);
  return SoundResourceData(
    payload: w.bytes(),
    segments: segments,
    totalTicks: total,
    headerSize: format == SoundHeaderFormat.early ? 17 : 33,
  );
}

/// Builds a complete kit for one output variant: the four wrapped sound
/// files, the wrapped combined `SOUND.001` drop-in track, and the wrapped
/// patch bank, all segment manifest data, and the human-readable
/// `MANIFEST.md` contents.
CalibrationKit buildKit({
  required SoundHeaderFormat format,
  required bool ninetySix,
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  final bank = buildBankPayload(
    instrumentCount: ninetySix ? 96 : 48,
    kitVersion: kitVersion,
  );
  final files = <String, Uint8List>{};
  files['PATCH.003'] = wrapLoosePatch(typeCode: kPatchTypeCode, payload: bank);
  final segments = <CalibrationSegment>[];
  for (var n = kFirstSound; n <= kLastSound; n++) {
    final data = buildSoundResource(
      resourceNumber: n,
      format: format,
      kitVersion: kitVersion,
    );
    files['SOUND.$n'] = wrapLoosePatch(
      typeCode: kSoundTypeCode,
      payload: data.payload,
    );
    segments.addAll(data.segments);
  }
  final combined = buildCombinedSoundResource(
    format: format,
    kitVersion: kitVersion,
  );
  files[kCombinedSoundFile] = wrapLoosePatch(
    typeCode: kSoundTypeCode,
    payload: combined.payload,
  );
  final manifest = buildManifestMarkdown(
    segments: segments,
    combinedSegments: combined.segments,
    combinedTotalTicks: combined.totalTicks,
    format: format,
    ninetySix: ninetySix,
    kitVersion: kitVersion,
  );
  return CalibrationKit(
    files: files,
    segments: segments,
    combinedSound: combined,
    format: format,
    ninetySix: ninetySix,
    manifestMarkdown: manifest,
    kitVersion: kitVersion,
  );
}

// ---------------------------------------------------------------------------
// Manifest / README text.
// ---------------------------------------------------------------------------

String _formatName(SoundHeaderFormat format, bool ninetySix) {
  return switch ((format, ninetySix)) {
    (SoundHeaderFormat.early, _) => 'early (17-byte header, 48 instruments)',
    (SoundHeaderFormat.late, false) =>
      'late48 (33-byte header, 48 instruments)',
    (SoundHeaderFormat.late, true) => 'late96 (33-byte header, 96 instruments)',
  };
}

/// Builds the human-readable `MANIFEST.md` for one kit. The segment tables
/// are identical across formats except the header-format note.
String buildManifestMarkdown({
  required List<CalibrationSegment> segments,
  List<CalibrationSegment> combinedSegments = const [],
  int combinedTotalTicks = 0,
  required SoundHeaderFormat format,
  required bool ninetySix,
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  final b = StringBuffer();
  b.writeln('# OPL calibration kit — segment manifest');
  b.writeln();
  b.writeln('Format: ${_formatName(format, ninetySix)}.');
  if (kitVersion == CalibrationKitVersion.v2) {
    b.writeln();
    b.writeln('Kit version: v2 (opt-in via --kit v2).');
  }
  if (kitVersion == CalibrationKitVersion.v3) {
    b.writeln();
    b.writeln('Kit version: v3 (opt-in via --kit v3).');
  }
  b.writeln();
  if (kitVersion == CalibrationKitVersion.v3) {
    if (format == SoundHeaderFormat.early) {
      b.writeln(
        'Sound headers are SCI0-early (17 bytes): flags + 16 channel bytes, '
        'channels 1,2,3,4,5,9,12 with raw bytes 0x21,0x21,0xF1,0x01,0x11,0x09,0x11. '
        'Bank: 48 instruments (1344 bytes).',
      );
    } else if (ninetySix) {
      b.writeln(
        'Sound headers are SCI0-late (33 bytes): flags + 16 [voiceCount, '
        'playMask] pairs, channels 1,2,3,4,5,9,12 with voice counts 2,2,15,0,1,1,1 '
        'and AdLib play mask 0x04. Bank: 96 instruments (2690 bytes; programs '
        '48..95 duplicate 0..47).',
      );
    } else {
      b.writeln(
        'Sound headers are SCI0-late (33 bytes): flags + 16 [voiceCount, '
        'playMask] pairs, channels 1,2,3,4,5,9,12 with voice counts 2,2,15,0,1,1,1 '
        'and AdLib play mask 0x04. Bank: 48 instruments (1344 bytes).',
      );
    }
  } else if (format == SoundHeaderFormat.early) {
    b.writeln(
      'Sound headers are SCI0-early (17 bytes): flags + 16 channel bytes, '
      'channels 1,2 with (2<<4)|AdLib = 0x21. Bank: 48 instruments (1344 bytes).',
    );
  } else if (ninetySix) {
    b.writeln(
      'Sound headers are SCI0-late (33 bytes): flags + 16 [voiceCount, '
      'playMask] pairs, channels 1,2 with [2, 0x04]. Bank: 96 instruments '
      '(2690 bytes; programs 48..95 duplicate 0..47).',
    );
  } else {
    b.writeln(
      'Sound headers are SCI0-late (33 bytes): flags + 16 [voiceCount, '
      'playMask] pairs, channels 1,2 with [2, 0x04]. Bank: 48 instruments '
      '(1344 bytes).',
    );
  }
  b.writeln();
  b.writeln('Ticks are 60 Hz (seconds = tick / 60).');
  b.writeln();
  for (var n = kFirstSound; n <= kLastSound; n++) {
    final resourceSegments = segments
        .where((s) => s.resourceNumber == n)
        .toList();
    if (resourceSegments.isEmpty) continue;
    b.writeln(
      '## SOUND.$n (${resourceSegments.length} segments, '
      '${resourceSegments.last.endTick} ticks = '
      '${(resourceSegments.last.endTick / 60).toStringAsFixed(2)} s)',
    );
    b.writeln();
    b.writeln(
      '| seg | program | ch | note | start tick | end tick | '
      'start s | end s | purpose |',
    );
    b.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final s in resourceSegments) {
      b.writeln(
        '| ${s.segmentIndex} | ${s.program} | ${s.channel} | '
        '${s.note} | ${s.startTick} | ${s.endTick} | '
        '${s.startSeconds.toStringAsFixed(2)} | '
        '${s.endSeconds.toStringAsFixed(2)} | ${s.purpose} |',
      );
    }
    b.writeln();
  }
  if (combinedSegments.isNotEmpty) {
    final total = combinedTotalTicks > 0
        ? combinedTotalTicks
        : combinedSegments.last.endTick;
    b.writeln(
      '## $kCombinedSoundFile (combined intro drop-in track, '
      '${combinedSegments.length} segments, $total ticks = '
      '${(total / 60).toStringAsFixed(2)} s)',
    );
    b.writeln();
    if (kitVersion == CalibrationKitVersion.v3) {
      b.writeln(
        'The four resources above concatenated in order '
        '(990 transitions, 991 rare timbres, 992 pitch/mult/KSL, 993 '
        'allocation/LFO) with a $kCombinedGapTicks-tick silence gap '
        'between former resources. Segment times below are absolute '
        'across the whole combined track; `origin` is the former '
        'resource number. There are no faked channel-15 cues or loop '
        'markers; end-of-track only, like the individual resources.',
      );
    } else {
      b.writeln(
        'The four resources above concatenated in order '
        '(990 core, 991 envelopes, 992 pitch/KSL/KSR, 993 velocity/pan/'
        'bend) with a $kCombinedGapTicks-tick silence gap between former '
        'resources. Segment times below are absolute across the whole '
        'combined track; `origin` is the former resource number. There are '
        'no faked channel-15 cues or loop markers; end-of-track only, '
        'like the individual resources.',
      );
    }
    b.writeln();
    b.writeln(
      '| origin | seg | program | ch | note | start tick | '
      'end tick | start s | end s | purpose |',
    );
    b.writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final s in combinedSegments) {
      b.writeln(
        '| ${s.resourceNumber} | ${s.segmentIndex} | ${s.program} | '
        '${s.channel} | ${s.note} | ${s.startTick} | ${s.endTick} | '
        '${s.startSeconds.toStringAsFixed(2)} | '
        '${s.endSeconds.toStringAsFixed(2)} | ${s.purpose} |',
      );
    }
    b.writeln();
  }
  if (kitVersion == CalibrationKitVersion.v3) {
    b.writeln(
      'Bank: 48 distinct synthetic instruments (programs 0..47); '
      'programs in order: 0 reference sine, 1 wave3 carrier, 2 wave3 '
      'modulator, 3 feedback brass A, 4 feedback B, 5 additive '
      'silent-carrier, 6 additive both, 7 extreme mult pair, 8 zero-decay '
      'modulator, 9 silent attack control, 10 slow swell, 11 fast '
      'percussive deep, 12 percussive nonzero-SL, 13 long release, 14 short '
      'release, 15 KSL3 both ops, 16 KSL1 carrier, 17 AM in FM, 18 VIB in '
      'FM, 19 bend-sensitive FM, 20..22 env mid (RR ladder), 23 slow '
      'percussive, 24 fast percussive, 25 zero-decay release-only, 26 '
      'frozen release, 27 slow attack zero-decay, 28..35 allocation '
      'timbres, 36..42 carrier MULT ladder, 43 low bass, 44 high alias, '
      '45 velocity/pan reference, 46 generic brass, 47 silent control.',
    );
  } else if (kitVersion == CalibrationKitVersion.v2) {
    b.writeln(
      'Bank: 48 distinct synthetic instruments (programs 0..47); '
      'programs in order: 0 reference sine, 1 wave3 carrier, 2 wave3 '
      'modulator, 3..8 feedback x mod-TL matrix, 9..14 attack fill-in, '
      '15..20 decay fill-in, 21..26 percussive RR ladder, 27..30 key-off '
      'release, 31..42 carrier MULT ladder, 43 AM on, 44 VIB on, '
      '45 AM+VIB on, 46 velocity/pan reference, 47 silent control.',
    );
  } else {
    b.writeln(
      'Bank: 48 distinct synthetic instruments (programs 0..47); '
      'programs in order: 0 reference sine FM, 1 additive sine, 2..4 carrier '
      'waveforms, 5..11 PM-depth ladder, 12..19 feedback ladder, 20..26 '
      'attack, 27..30 decay-to-sustain, 31..34 percussive, 35..38 release, '
      '39..42 KSL, 43 KSR off, 44 KSR on, 45 velocity/pan, 46 brass-ish, '
      '47 silent control.',
    );
  }
  b.writeln();
  return b.toString();
}

/// Builds the root `README.md` explaining how to use the kit.
String buildReadmeMarkdown({
  CalibrationKitVersion kitVersion = CalibrationKitVersion.v1,
}) {
  final b = StringBuffer();
  b.writeln('# OPL calibration kit (SCI0)');
  b.writeln();
  if (kitVersion == CalibrationKitVersion.v2) {
    b.writeln('Kit version: v2 (opt-in via --kit v2).');
    b.writeln();
  }
  if (kitVersion == CalibrationKitVersion.v3) {
    b.writeln('Kit version: v3 (opt-in via --kit v3).');
    b.writeln();
    b.writeln('## v3 (state transitions, rare archetypes, allocation)');
    b.writeln();
    b.writeln(
      'v3 targets state-transition and rare-archetype residuals '
      'found by corpus mining and game spot-checks: retrigger series, '
      'key-off-during-attack, program-change-while-sounding, '
      'bend-during-attack/release, feedback/additive archetypes, extreme '
      'multiplier pairs, and voice-allocation probes (CC75/CC7/CC78 while '
      'active, zero-voice/control channels, nibble-15 chords, '
      'steal-on-pedal). It supersets the v2 topics (wave3, feedback, '
      'attack/decay/release ladders, MULT ladder, LFO).',
    );
    b.writeln();
    b.writeln(
      'Note: early-format v3 sound headers intentionally include '
      'KQ4-style header patterns on channels 3, 4, and 9 (early raw '
      'bytes 0xF1 nibble-15 and 0x01/0x09 zero-voice channels; late '
      'voice counts 15/0/1) to observe early- and late-driver voice '
      'allocation against the same event stream.',
    );
    b.writeln();
  }
  b.writeln(
    'Synthetic AdLib patch bank + labeled sound resources for '
    'ScummVM reference captures. All instruments and segments are '
    'synthetic; no game patch bytes are included.',
  );
  b.writeln();
  b.writeln('## Contents');
  b.writeln();
  b.writeln('- `early/`: SCI0-early (17-byte) headers, 48-instrument bank.');
  b.writeln('- `late48/`: SCI0-late (33-byte) headers, 48-instrument bank.');
  b.writeln(
    '- `late96/`: SCI0-late (33-byte) headers, 96-instrument bank '
    '(programs 48..95 duplicate 0..47).',
  );
  b.writeln();
  b.writeln(
    'Each subdirectory holds `PATCH.003`, `SOUND.990`..`SOUND.993`, '
    '`SOUND.001` (combined drop-in track), and `MANIFEST.md` '
    '(per-segment start/end ticks + seconds, including absolute times '
    'for the combined track).',
  );
  b.writeln();
  b.writeln('## Usage');
  b.writeln();
  b.writeln(
    '1. Copy a game folder to a scratch location (do not use your '
    'only copy).',
  );
  b.writeln(
    '2. Copy the files from one subdirectory (`early/`, `late48/`, '
    'or `late96/`) into the scratch game folder.',
  );
  b.writeln(
    '3. Start the game with ScummVM and open its debug menu; play '
    'sound resources 990, 991, 992, and 993 in turn.',
  );
  b.writeln(
    '4. Capture the audio output and analyze it against '
    '`MANIFEST.md` (segment times in 60 Hz ticks).',
  );
  b.writeln(
    '5. When done, remove `PATCH.003` (and `SOUND.990`..`SOUND.993`) '
    'from the scratch folder. `PATCH.003` replaces ALL of the game\'s '
    'AdLib instruments while present.',
  );
  b.writeln();
  b.writeln('## ScummVM capture (macOS, proven template)');
  b.writeln();
  b.writeln(
    'SDL\'s disk audio driver writes raw s16le stereo at the '
    'output rate. Use a ScummVM target whose path is the scratch copy '
    '(or add `--path=<SCRATCH_GAME_DIR>`), quit ScummVM to stop the '
    'capture, then convert:',
  );
  b.writeln();
  b.writeln('```sh');
  b.writeln('SDL_AUDIODRIVER=disk SDL_DISKAUDIOFILE=/tmp/scumm.raw \\');
  b.writeln(
    '  /Applications/ScummVM.app/Contents/MacOS/scummvm '
    '-e adlib --opl-driver=nuked --output-rate=44100 -m 255 -s 0 -r 0 '
    '<target>',
  );
  b.writeln();
  b.writeln(
    'ffmpeg -f s16le -ar 44100 -ac 2 -i /tmp/scumm.raw '
    'scummvm_ref.flac',
  );
  b.writeln('```');
  b.writeln();
  b.writeln('## SQ3 drop-in (combined `SOUND.001`)');
  b.writeln();
  b.writeln(
    'Space Quest 3 plays sound resource 1 as its intro/title '
    'music, so the combined calibration track (all four resources '
    'concatenated, about 3 minutes) can be heard by simply starting '
    'the game — no debug menu needed.',
  );
  b.writeln();
  b.writeln(
    '1. Copy the SQ3 game folder to a scratch location (do not '
    'use your only copy).',
  );
  b.writeln(
    '2. Copy `late96/PATCH.003` and `late96/SOUND.001` into the '
    'scratch copy.',
  );
  b.writeln(
    '3. Launch ScummVM with the disk-audio capture template '
    'above, using the scratch folder as the game path.',
  );
  b.writeln(
    '4. Just start the game and record. The full combined track '
    'runs about 3 minutes; the most valuable tests are first, so even '
    '60–90 seconds of capture is useful.',
  );
  b.writeln(
    '5. When done, remove BOTH `PATCH.003` and `SOUND.001` from '
    'the scratch folder. `PATCH.003` replaces ALL of the game\'s AdLib '
    'instruments while present.',
  );
  b.writeln();
  b.writeln(
    'Caveats: the title animation may sit still because no script '
    'cues are faked — only the sound is replaced. If the game preempts '
    'the intro sound at a scene change, fall back to debug-menu '
    'playback of `SOUND.990`..`SOUND.993`. The same drop-in trick works '
    'for other games only if their intro sound is resource 1 (PQ2 yes; '
    'verify before relying on it for others).',
  );
  b.writeln();
  return b.toString();
}

// ---------------------------------------------------------------------------
// CLI.
// ---------------------------------------------------------------------------

const String _usage =
    'Usage: dart tool/generate_opl_calibration.dart --out <dir> [--kit v1|v2|v3]';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    if (args.isEmpty) {
      exitCode = 2;
    }
    return;
  }
  String? outDir;
  var kitVersion = CalibrationKitVersion.v1;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      outDir = args[++i];
    } else if (args[i] == '--kit' && i + 1 < args.length) {
      try {
        kitVersion = parseCalibrationKitVersion(args[++i]);
      } on FormatException {
        stderr.writeln(_usage);
        exitCode = 2;
        return;
      }
    } else if (args[i].startsWith('--kit=')) {
      try {
        kitVersion = parseCalibrationKitVersion(args[i].substring(6));
      } on FormatException {
        stderr.writeln(_usage);
        exitCode = 2;
        return;
      }
    } else {
      stderr.writeln(_usage);
      exitCode = 2;
      return;
    }
  }
  if (outDir == null || outDir.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final root = Directory(outDir);
  root.createSync(recursive: true);

  final kits = <String, CalibrationKit>{
    'early': buildKit(
      format: SoundHeaderFormat.early,
      ninetySix: false,
      kitVersion: kitVersion,
    ),
    'late48': buildKit(
      format: SoundHeaderFormat.late,
      ninetySix: false,
      kitVersion: kitVersion,
    ),
    'late96': buildKit(
      format: SoundHeaderFormat.late,
      ninetySix: true,
      kitVersion: kitVersion,
    ),
  };

  for (final entry in kits.entries) {
    final dir = Directory('${root.path}/${entry.key}');
    dir.createSync(recursive: true);
    for (final fileEntry in entry.value.files.entries) {
      File('${dir.path}/${fileEntry.key}')
          .writeAsBytesSync(fileEntry.value, flush: true);
    }
    File('${dir.path}/MANIFEST.md')
        .writeAsStringSync(entry.value.manifestMarkdown, flush: true);
    stdout.writeln(
      'wrote ${entry.value.files.length} files + MANIFEST.md -> ${dir.path}',
    );
  }
  File(
    '${root.path}/README.md',
  ).writeAsStringSync(buildReadmeMarkdown(kitVersion: kitVersion), flush: true);
  stdout.writeln('wrote README.md -> ${root.path}/README.md');
}
