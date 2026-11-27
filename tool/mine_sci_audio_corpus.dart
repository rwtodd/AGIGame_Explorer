/// SCI audio corpus miner: finds novel OPL patch/control combinations
/// across reference games, to drive calibration-kit v3 design.
///
/// Analysis tooling only. It loads each game under `--root` with
/// [SciVolumeManager], parses every sound resource into a
/// [SciMidiTrack], profiles the patch instruments referenced by each
/// track's program changes (plus a bank-wide census), simulates the
/// track through [SciAdLibDriver] with a recording sink, and ranks
/// sounds by the rarity of their patch feature keys and control-pattern
/// tags.
///
/// Outputs (only under `--out`):
/// - `corpus_report.md`: human summary with per-game load table,
///   compact parameter histograms, top novel sounds (reasons and
///   exemplar windows), rarest patch feature keys described by their
///   parameter summary (never raw bytes), and anomaly lists.
/// - `corpus_features.json`: aggregate counters plus per-sound
///   features and exemplars. No raw patch bytes and no event dumps
///   beyond counts/features/exemplar windows.
///
/// Pure Dart (`dart:io`/`dart:typed_data` only, on top of the pure-Dart
/// app libraries below), so `dart run` works standalone. Analysis
/// functions are importable from tests.
///
/// Usage:
/// ```sh
/// dart run tool/mine_sci_audio_corpus.dart --root reference_games \
///     --out <dir> [--games a,b] [--top N]
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_parser.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

const String minerUsage =
    'Usage: dart run tool/mine_sci_audio_corpus.dart --root <dir> '
    '--out <dir> [--games a,b] [--top N]';

/// Parsed CLI arguments for the miner.
final class MinerArgs {
  /// Directory whose subdirectories are candidate games.
  final String root;

  /// Output directory for `corpus_report.md` / `corpus_features.json`.
  final String out;

  /// Optional game-name filter (subdirectory names, case-insensitive).
  final Set<String>? games;

  /// Number of top novel sounds in the report/console summary.
  final int topN;

  const MinerArgs({
    required this.root,
    required this.out,
    required this.games,
    required this.topN,
  });
}

/// Parses [args] into [MinerArgs].
///
/// Throws [FormatException] on any unknown flag, missing value, or
/// bad number; the CLI maps that to usage + exit code 2.
MinerArgs parseMinerArgs(List<String> args) {
  String? root;
  String? out;
  Set<String>? games;
  var topN = 10;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value() {
      if (i + 1 >= args.length) {
        throw FormatException('missing value for $a');
      }
      return args[++i];
    }

    if (a == '--root') {
      root = value();
    } else if (a.startsWith('--root=')) {
      root = a.substring('--root='.length);
    } else if (a == '--out') {
      out = value();
    } else if (a.startsWith('--out=')) {
      out = a.substring('--out='.length);
    } else if (a == '--games') {
      games = {
        for (final g in value().split(','))
          if (g.trim().isNotEmpty) g.trim().toLowerCase(),
      };
    } else if (a.startsWith('--games=')) {
      games = {
        for (final g in a.substring('--games='.length).split(','))
          if (g.trim().isNotEmpty) g.trim().toLowerCase(),
      };
    } else if (a == '--top') {
      topN = int.parse(value());
    } else if (a.startsWith('--top=')) {
      topN = int.parse(a.substring('--top='.length));
    } else {
      throw FormatException('unknown argument: $a');
    }
  }
  if (root == null || root.isEmpty || out == null || out.isEmpty) {
    throw FormatException('both --root and --out are required');
  }
  if (topN <= 0) {
    throw FormatException('--top must be positive: $topN');
  }
  return MinerArgs(root: root, out: out, games: games, topN: topN);
}

// ---------------------------------------------------------------------------
// Patch feature keys.
// ---------------------------------------------------------------------------

String _opKey(String prefix, SciAdlibOperator op) {
  return '$prefix:'
      'AR=${op.attackRate};DR=${op.decayRate};SL=${op.sustainLevel};'
      'RR=${op.releaseRate};EG=${op.envelopeType};KSR=${op.kbScaleRate};'
      'KSL=${op.kbScaleLevel};TL=${op.totalLevel};AM=${op.amplitudeMod};'
      'VIB=${op.vibrato};wave=${op.waveForm};mult=${op.frequencyMult}';
}

/// Deterministic feature key for [instrument], summarizing algorithm,
/// feedback, and per-operator wave/multiplier plus exact AR, DR, SL,
/// RR, EG, KSR, KSL, TL, AM, VIB integers. Never contains raw bytes.
String patchFeatureKey(SciAdlibInstrument instrument) {
  return 'alg=${instrument.modulator.algorithm},'
      'fb=${instrument.modulator.feedback},'
      '${_opKey('op0', instrument.operator0)}|'
      '${_opKey('op1', instrument.operator1)}';
}

/// Every `(parameter, value)` pair of [instrument] for histogram
/// counting, e.g. `('op0.AR', 3)`. Keys match [patchFeatureKey].
List<({String param, int value})> patchParameterValues(
  SciAdlibInstrument instrument,
) {
  const order = ['AR', 'DR', 'SL', 'RR', 'EG', 'KSR', 'KSL', 'TL', 'AM', 'VIB'];
  List<int> of(SciAdlibOperator op) => [
        op.attackRate,
        op.decayRate,
        op.sustainLevel,
        op.releaseRate,
        op.envelopeType,
        op.kbScaleRate,
        op.kbScaleLevel,
        op.totalLevel,
        op.amplitudeMod,
        op.vibrato,
      ];
  return [
    (param: 'alg', value: instrument.modulator.algorithm),
    (param: 'fb', value: instrument.modulator.feedback),
    for (var i = 0; i < order.length; i++)
      (param: 'op0.${order[i]}', value: of(instrument.operator0)[i]),
    (param: 'op0.wave', value: instrument.operator0.waveForm),
    (param: 'op0.mult', value: instrument.operator0.frequencyMult),
    for (var i = 0; i < order.length; i++)
      (param: 'op1.${order[i]}', value: of(instrument.operator1)[i]),
    (param: 'op1.wave', value: instrument.operator1.waveForm),
    (param: 'op1.mult', value: instrument.operator1.frequencyMult),
  ];
}

// ---------------------------------------------------------------------------
// Track feature extraction.
// ---------------------------------------------------------------------------

/// Aggregate features extracted from one parsed [SciMidiTrack].
final class TrackFeatures {
  final int totalTicks;
  final int noteOns;
  final List<int> usedPrograms;
  final List<int> usedChannels;
  final int maxSimultaneousNotes;
  final Map<int, int> maxSimultaneousPerChannel;
  final int sameTickChordMax;
  final int gateMinTicks;
  final int gateMedianTicks;
  final int retriggerCount;
  final int pedalOverlapCount;
  final int pedalMaxStack;
  final int pitchBendCount;
  final int pitchBendMin;
  final int pitchBendMax;
  final int cc7WhileActiveCount;
  final int programWhileActiveCount;
  final int cc75Count;
  final int cc78Count;
  final int sysExCount;
  final bool hasDigitalSample;
  final int outOfBankProgramCount;
  final int cueCount;
  final int pitchMin;
  final int pitchMax;

  /// Distinct programs referenced, in first-seen order.
  final List<int> referencedPrograms;

  /// Distinct patch feature keys for [referencedPrograms] in range.
  final List<String> patchKeys;

  /// Control/patch tags, e.g. `chord_ge_6`, `retrigger`, `fb_ge_5`.
  final List<String> tags;

  const TrackFeatures({
    required this.totalTicks,
    required this.noteOns,
    required this.usedPrograms,
    required this.usedChannels,
    required this.maxSimultaneousNotes,
    required this.maxSimultaneousPerChannel,
    required this.sameTickChordMax,
    required this.gateMinTicks,
    required this.gateMedianTicks,
    required this.retriggerCount,
    required this.pedalOverlapCount,
    required this.pedalMaxStack,
    required this.pitchBendCount,
    required this.pitchBendMin,
    required this.pitchBendMax,
    required this.cc7WhileActiveCount,
    required this.programWhileActiveCount,
    required this.cc75Count,
    required this.cc78Count,
    required this.sysExCount,
    required this.hasDigitalSample,
    required this.outOfBankProgramCount,
    required this.cueCount,
    required this.pitchMin,
    required this.pitchMax,
    required this.referencedPrograms,
    required this.patchKeys,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'totalTicks': totalTicks,
        'noteOns': noteOns,
        'usedPrograms': usedPrograms,
        'usedChannels': usedChannels,
        'maxSimultaneousNotes': maxSimultaneousNotes,
        'maxSimultaneousPerChannel': {
          for (final e in maxSimultaneousPerChannel.entries)
            '${e.key}': e.value,
        },
        'sameTickChordMax': sameTickChordMax,
        'gateMinTicks': gateMinTicks,
        'gateMedianTicks': gateMedianTicks,
        'retriggerCount': retriggerCount,
        'pedalOverlapCount': pedalOverlapCount,
        'pedalMaxStack': pedalMaxStack,
        'pitchBendCount': pitchBendCount,
        'pitchBendMin': pitchBendMin,
        'pitchBendMax': pitchBendMax,
        'cc7WhileActiveCount': cc7WhileActiveCount,
        'programWhileActiveCount': programWhileActiveCount,
        'cc75Count': cc75Count,
        'cc78Count': cc78Count,
        'sysExCount': sysExCount,
        'hasDigitalSample': hasDigitalSample,
        'outOfBankProgramCount': outOfBankProgramCount,
        'cueCount': cueCount,
        'pitchMin': pitchMin,
        'pitchMax': pitchMax,
        'referencedPrograms': referencedPrograms,
        'patchKeys': patchKeys,
        'tags': tags,
      };
}

int _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Extracts all track/control features from [track].
///
/// [bank] (when present) supplies patch keys for referenced programs
/// and the out-of-range program count.
TrackFeatures analyzeTrackFeatures(
  SciMidiTrack track, {
  SciAdlibBank? bank,
}) {
  var noteOns = 0;
  final usedPrograms = <int>[];
  final usedProgramsSet = <int>{};
  final usedChannels = <int>[];
  final usedChannelsSet = <int>{};
  final active = <int, Map<int, int>>{}; // channel -> pitch -> onTick
  final lastOff = <int, Map<int, int>>{}; // channel -> pitch -> offTick
  final maxPerChannel = <int, int>{};
  var maxSimultaneous = 0;
  final chordByTick = <int, int>{};
  final gates = <int>[];
  var retrigger = 0;
  final pedal = <int, int>{}; // channel -> pedal value
  var pedalOverlap = 0;
  var pedalStack = 0;
  var pedalMaxStack = 0;
  var bendCount = 0;
  var bendMin = 1 << 30;
  var bendMax = -1;
  var cc7Active = 0;
  var programActive = 0;
  var cc75 = 0;
  var cc78 = 0;
  var sysex = 0;
  var outOfBank = 0;
  final referenced = <int>[];
  final referencedSet = <int>{};
  var pitchMin = 1 << 30;
  var pitchMax = -1;

  bool channelActive(int ch) =>
      active[ch] != null && active[ch]!.isNotEmpty;

  for (final e in track.events) {
    switch (e.kind) {
      case SciMidiEventKind.noteOn:
        noteOns++;
        if (e.channel >= 0) {
          if (usedChannelsSet.add(e.channel)) {
            usedChannels.add(e.channel);
          }
          final map = active.putIfAbsent(e.channel, () => <int, int>{});
          // Retrigger: same channel+pitch still gated, or off <= 15 ticks ago.
          final pitch = e.data1;
          if (map.containsKey(pitch)) {
            retrigger++;
          } else {
            final off = lastOff[e.channel]?[pitch];
            if (off != null && e.tick - off <= 15) retrigger++;
          }
          map[pitch] = e.tick;
          chordByTick[e.tick] = (chordByTick[e.tick] ?? 0) + 1;
          final total = active.values.fold(0, (s, m) => s + m.length);
          if (total > maxSimultaneous) maxSimultaneous = total;
          if (map.length > (maxPerChannel[e.channel] ?? 0)) {
            maxPerChannel[e.channel] = map.length;
          }
          if (pitch < pitchMin) pitchMin = pitch;
          if (pitch > pitchMax) pitchMax = pitch;
        }
      case SciMidiEventKind.noteOff:
        if (e.channel >= 0) {
          final map = active[e.channel];
          final onTick = map?.remove(e.data1);
          if (onTick != null) {
            gates.add(e.tick - onTick);
            lastOff.putIfAbsent(e.channel, () => <int, int>{})[e.data1] =
                e.tick;
            if ((pedal[e.channel] ?? 0) != 0) {
              pedalOverlap++;
              pedalStack++;
              if (pedalStack > pedalMaxStack) pedalMaxStack = pedalStack;
            }
          }
        }
      case SciMidiEventKind.programChange:
        if (e.channel >= 0 && e.channel != 15) {
          // Channel-15 program changes are cues, not instrument
          // selections (the driver never receives them); cue counts
          // come from track.cues.
          if (usedProgramsSet.add(e.data1)) usedPrograms.add(e.data1);
          if (referencedSet.add(e.data1)) referenced.add(e.data1);
          if (channelActive(e.channel)) programActive++;
          if (bank != null &&
              (e.data1 < 0 || e.data1 >= bank.instrumentCount)) {
            outOfBank++;
          }
        }
      case SciMidiEventKind.controlChange:
        if (e.channel >= 0) {
          if (e.data1 == 0x07 && channelActive(e.channel)) cc7Active++;
          if (e.data1 == 0x40) {
            pedal[e.channel] = e.data2;
            if (e.data2 == 0) pedalStack = 0;
          } else if (e.data1 == 0x4B) {
            cc75++;
          } else if (e.data1 == 0x4E) {
            cc78++;
          }
        }
      case SciMidiEventKind.pitchBend:
        bendCount++;
        final v = e.pitchBendValue;
        if (v < bendMin) bendMin = v;
        if (v > bendMax) bendMax = v;
      case SciMidiEventKind.sysEx:
        sysex++;
      default:
        break;
    }
  }

  var chordMax = 0;
  for (final v in chordByTick.values) {
    if (v > chordMax) chordMax = v;
  }

  // Patch keys + tags from referenced programs.
  final patchKeys = <String>[];
  final tags = <String>{
    if (retrigger > 0) 'retrigger',
    if (chordMax >= 6) 'chord_ge_6',
    if (pedalOverlap > 0) 'pedal_overlap',
    if (bendCount > 0) 'pitch_bend',
    if (cc7Active > 0) 'cc7_while_active',
    if (programActive > 0) 'program_while_active',
    if (cc75 > 0) 'cc75',
    if (cc78 > 0) 'cc78',
    if (sysex > 0) 'sysex',
    if (track.hasDigitalSample) 'digital_sample',
    if (outOfBank > 0) 'out_of_bank_program',
    if (track.cues.isNotEmpty) 'channel15_cue',
  };
  if (bank != null) {
    final seenKeys = <String>{};
    for (final p in referenced) {
      if (p < 0 || p >= bank.instrumentCount) continue;
      final ins = bank.instruments[p];
      final key = patchFeatureKey(ins);
      if (seenKeys.add(key)) patchKeys.add(key);
      if (ins.modulator.feedback >= 5) tags.add('fb_ge_5');
      if (ins.operator0.waveForm == 3 || ins.operator1.waveForm == 3) {
        tags.add('wave3');
      }
      if (ins.operator0.frequencyMult == 0 ||
          ins.operator1.frequencyMult == 0) {
        tags.add('mult_zero');
      }
      if (ins.operator0.frequencyMult != ins.operator1.frequencyMult) {
        tags.add('mult_ratio');
      }
      for (final pv in patchParameterValues(ins)) {
        if (pv.value == 0 &&
            (pv.param.endsWith('.AR') ||
                pv.param.endsWith('.DR') ||
                pv.param.endsWith('.RR'))) {
          tags.add('zero_rate');
        }
      }
    }
  }

  return TrackFeatures(
    totalTicks: track.totalTicks,
    noteOns: noteOns,
    usedPrograms: usedPrograms,
    usedChannels: usedChannels,
    maxSimultaneousNotes: maxSimultaneous,
    maxSimultaneousPerChannel: maxPerChannel,
    sameTickChordMax: chordMax,
    gateMinTicks: gates.isEmpty ? 0 : gates.reduce(math.min),
    gateMedianTicks: _median(gates),
    retriggerCount: retrigger,
    pedalOverlapCount: pedalOverlap,
    pedalMaxStack: pedalMaxStack,
    pitchBendCount: bendCount,
    pitchBendMin: bendCount == 0 ? 0 : bendMin,
    pitchBendMax: bendCount == 0 ? 0 : bendMax,
    cc7WhileActiveCount: cc7Active,
    programWhileActiveCount: programActive,
    cc75Count: cc75,
    cc78Count: cc78,
    sysExCount: sysex,
    hasDigitalSample: track.hasDigitalSample,
    outOfBankProgramCount: outOfBank,
    cueCount: track.cues.length,
    pitchMin: noteOns == 0 ? 0 : pitchMin,
    pitchMax: noteOns == 0 ? 0 : pitchMax,
    referencedPrograms: referenced,
    patchKeys: patchKeys,
    tags: tags.toList()..sort(),
  );
}

// ---------------------------------------------------------------------------
// Driver simulation.
// ---------------------------------------------------------------------------

/// [OplRegisterSink] that records every register write, in order.
final class RecordingRegisterSink implements OplRegisterSink {
  /// `(address, value)` pairs in write order.
  final List<({int address, int value})> writes = [];

  @override
  void writeRegister(int address, int value) {
    writes.add((address: address, value: value));
  }

  @override
  void reset() => writes.clear();

  /// Number of key-on writes (0xB0..0xB8 with the 0x20 key bit set) at
  /// or after write index [start].
  int keyOnWriteCountFrom(int start) {
    var n = 0;
    for (var i = start; i < writes.length; i++) {
      final w = writes[i];
      if (w.address >= 0xB0 && w.address <= 0xB8 && (w.value & 0x20) != 0) {
        n++;
      }
    }
    return n;
  }
}

/// Result of simulating one track through [SciAdLibDriver].
final class DriverSimResult {
  final int dispatchedNoteOns;
  final int keyOnWrites;

  /// Note-ons that produced no key-on register write (out of range,
  /// no mapped voice, same-tick non-steal).
  final int inferredDrops;

  /// Note-ons that evicted a different active note from a voice.
  final int steals;

  /// Note-ons re-triggering the same voice+pitch.
  final int retriggers;

  final int maxActiveVoices;

  /// Voices still sounding at track end (before allNotesOff).
  final int voicesAtEnd;

  const DriverSimResult({
    required this.dispatchedNoteOns,
    required this.keyOnWrites,
    required this.inferredDrops,
    required this.steals,
    required this.retriggers,
    required this.maxActiveVoices,
    required this.voicesAtEnd,
  });

  Map<String, dynamic> toJson() => {
        'dispatchedNoteOns': dispatchedNoteOns,
        'keyOnWrites': keyOnWrites,
        'inferredDrops': inferredDrops,
        'steals': steals,
        'retriggers': retriggers,
        'maxActiveVoices': maxActiveVoices,
        'voicesAtEnd': voicesAtEnd,
      };
}

/// Simulates [track] through a fresh [SciAdLibDriver] over [bank],
/// dispatching exactly like [SciAdLibRenderer]: channel-15 events are
/// skipped, non-AdLib-masked channels (>= 0, not in the AdLib mask) are
/// skipped, and channel -1 events are forwarded (the driver ignores
/// them). Event counts are taken from the driver's observable state
/// (per-voice channel/note) around each dispatched note-on.
DriverSimResult simulateDriver(
  SciMidiTrack track,
  SciAdlibBank bank, {
  SciAdlibProfile profile = SciAdlibProfile.sci0Late,
}) {
  final sink = RecordingRegisterSink();
  final driver = SciAdLibDriver(bank: bank, sink: sink, profile: profile);
  driver.open();
  driver.initTrack(track);

  final mask = track.channelMaskFor(SciMidiDevice.adLib);
  var dispatched = 0;
  var drops = 0;
  var steals = 0;
  var retriggers = 0;
  var maxActive = 0;

  int activeVoiceCount() {
    var n = 0;
    for (var v = 0; v < 9; v++) {
      if (driver.voiceNote(v) != -1) n++;
    }
    return n;
  }

  void observeActive() {
    final n = activeVoiceCount();
    if (n > maxActive) maxActive = n;
  }

  for (final event in track.events) {
    if (event.channel == 15) continue;
    if (event.channel >= 0 && !mask.contains(event.channel)) continue;
    if (event.kind != SciMidiEventKind.noteOn) {
      driver.handleEvent(event);
      observeActive();
      continue;
    }
    // Snapshot voice state before handling this note-on.
    final beforeNotes = List<int>.generate(9, driver.voiceNote);
    final beforeChannels = List<int>.generate(9, driver.voiceChannel);
    final writeStart = sink.writes.length;
    driver.handleEvent(event);
    dispatched++;
    final keyOns = sink.keyOnWriteCountFrom(writeStart);
    if (keyOns == 0) {
      drops++;
    } else {
      for (var v = 0; v < 9; v++) {
        if (driver.voiceNote(v) == event.data1 &&
            driver.voiceChannel(v) == event.channel) {
          if (beforeNotes[v] != -1 &&
              beforeChannels[v] == event.channel &&
              beforeNotes[v] == event.data1) {
            retriggers++;
          } else if (beforeNotes[v] != -1 && beforeNotes[v] != event.data1) {
            steals++;
          }
          break;
        }
      }
    }
    observeActive();
  }
  final voicesAtEnd = activeVoiceCount();
  return DriverSimResult(
    dispatchedNoteOns: dispatched,
    keyOnWrites: sink.keyOnWriteCountFrom(0),
    inferredDrops: drops,
    steals: steals,
    retriggers: retriggers,
    maxActiveVoices: maxActive,
    voicesAtEnd: voicesAtEnd,
  );
}

// ---------------------------------------------------------------------------
// Novelty ranking.
// ---------------------------------------------------------------------------

/// Novelty score formula (documented in the report):
///
/// score = (sum over the sound's distinct patch feature keys of
///         1/sqrt(globalKeyCount)) +
///        (sum over the sound's distinct control-pattern tags of
///         1/sqrt(globalTagCount)) +
///        anomaly bumps, where each present anomaly adds 1.0:
///        dropped notes (sim drops > 0), stuck voices at end
///        (voicesAtEnd > 0), out-of-bank programs, digital sample,
///        SysEx, max chord >= 6.
///
/// [globalKeyCounts] maps each patch feature key to the number of
/// per-sound usages across the corpus; [globalTagCounts] likewise for
/// tags.
double noveltyScore({
  required List<String> patchKeys,
  required List<String> tags,
  required Map<String, int> globalKeyCounts,
  required Map<String, int> globalTagCounts,
  required TrackFeatures features,
  DriverSimResult? sim,
}) {
  var score = 0.0;
  for (final key in patchKeys.toSet()) {
    final count = globalKeyCounts[key] ?? 1;
    score += 1.0 / math.sqrt(count);
  }
  for (final tag in tags.toSet()) {
    final count = globalTagCounts[tag] ?? 1;
    score += 1.0 / math.sqrt(count);
  }
  if (sim != null && sim.inferredDrops > 0) score += 1.0;
  if (sim != null && sim.voicesAtEnd > 0) score += 1.0;
  if (features.outOfBankProgramCount > 0) score += 1.0;
  if (features.hasDigitalSample) score += 1.0;
  if (features.sysExCount > 0) score += 1.0;
  if (features.sameTickChordMax >= 6) score += 1.0;
  return score;
}

// ---------------------------------------------------------------------------
// Exemplars.
// ---------------------------------------------------------------------------

/// One exemplar window: tick range (+ seconds), channel/program context,
/// and why it matters. Windows only; no event dumps.
final class CorpusExemplar {
  final int tickStart;
  final int tickEnd;
  final int channel;
  final int program;
  final String reason;

  const CorpusExemplar({
    required this.tickStart,
    required this.tickEnd,
    required this.channel,
    required this.program,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'tickStart': tickStart,
        'tickEnd': tickEnd,
        'secondStart': tickStart / 60,
        'secondEnd': tickEnd / 60,
        'channel': channel,
        'program': program,
        'reason': reason,
      };
}

/// Builds up to 3 exemplar windows around the first use of the sound's
/// rarest patch keys/tags, ranked by global count ascending.
List<CorpusExemplar> buildExemplars(
  SciMidiTrack track,
  TrackFeatures features,
  SciAdlibBank? bank, {
  required Map<String, int> globalKeyCounts,
  required Map<String, int> globalTagCounts,
}) {
  final candidates = <({int rarity, CorpusExemplar exemplar})>[];
  if (bank != null) {
    final firstProgramEvent = <int, SciMidiEvent>{};
    for (final e in track.events) {
      if (e.kind == SciMidiEventKind.programChange) {
        firstProgramEvent.putIfAbsent(e.data1, () => e);
      }
    }
    final keysByProgram = <int, String>{};
    for (final p in features.referencedPrograms) {
      if (p >= 0 && p < bank.instrumentCount) {
        keysByProgram[p] = patchFeatureKey(bank.instruments[p]);
      }
    }
    for (final p in features.referencedPrograms) {
      final key = keysByProgram[p];
      final event = firstProgramEvent[p];
      if (key == null || event == null) continue;
      candidates.add((
        rarity: globalKeyCounts[key] ?? 1 << 30,
        exemplar: CorpusExemplar(
          tickStart: event.tick,
          tickEnd: event.tick + 120,
          channel: event.channel,
          program: p,
          reason: 'first use of patch key (count=${globalKeyCounts[key]})',
        ),
      ));
    }
  }
  // Tag exemplars: first event that exhibits each rare tag.
  final tagEvents = <String, SciMidiEvent>{};
  for (final tag in features.tags) {
    SciMidiEvent? found;
    for (final e in track.events) {
      final hit = switch (tag) {
        'sysex' => e.kind == SciMidiEventKind.sysEx,
        'pitch_bend' => e.kind == SciMidiEventKind.pitchBend,
        'cc75' => e.kind == SciMidiEventKind.controlChange && e.data1 == 0x4B,
        'cc78' => e.kind == SciMidiEventKind.controlChange && e.data1 == 0x4E,
        'channel15_cue' => e.kind == SciMidiEventKind.programChange &&
            e.channel == 15,
        'program_while_active' =>
          e.kind == SciMidiEventKind.programChange && e.channel >= 0,
        'cc7_while_active' =>
          e.kind == SciMidiEventKind.controlChange && e.data1 == 0x07,
        _ => false,
      };
      if (hit) {
        found = e;
        break;
      }
    }
    if (found != null) tagEvents[tag] = found;
  }
  for (final entry in tagEvents.entries) {
    candidates.add((
      rarity: globalTagCounts[entry.key] ?? 1 << 30,
      exemplar: CorpusExemplar(
        tickStart: entry.value.tick,
        tickEnd: entry.value.tick + 120,
        channel: entry.value.channel,
        program: entry.value.isProgramChange ? entry.value.data1 : -1,
        reason: 'first ${entry.key} (count=${globalTagCounts[entry.key]})',
      ),
    ));
  }
  candidates.sort((a, b) => a.rarity.compareTo(b.rarity));
  return [for (final c in candidates.take(3)) c.exemplar];
}

// ---------------------------------------------------------------------------
// Corpus scan.
// ---------------------------------------------------------------------------

/// One parsed sound's miner record.
final class MinedSound {
  final String game;
  final int resourceNumber;
  final int totalTicks;
  final TrackFeatures features;
  final DriverSimResult? sim;
  final List<CorpusExemplar> exemplars;
  double novelty;

  MinedSound({
    required this.game,
    required this.resourceNumber,
    required this.totalTicks,
    required this.features,
    required this.sim,
    required this.exemplars,
    this.novelty = 0,
  });

  Map<String, dynamic> toJson() => {
        'game': game,
        'resourceNumber': resourceNumber,
        'totalTicks': totalTicks,
        'features': features.toJson(),
        'simulation': sim?.toJson(),
        'exemplars': [for (final e in exemplars) e.toJson()],
        'noveltyScore': novelty,
      };
}

/// Per-game load summary.
final class GameLoadInfo {
  final String game;
  final bool skipped;
  final String? skipReason;
  final String? error;
  final bool isEarlySci0;
  final bool usesPostSci01;
  final String bankProvenance;
  final int bankInstrumentCount;
  final int soundsFound;
  final int soundsParsed;
  final int soundsFailed;
  final List<String> soundErrors;

  const GameLoadInfo({
    required this.game,
    required this.skipped,
    this.skipReason,
    this.error,
    required this.isEarlySci0,
    required this.usesPostSci01,
    required this.bankProvenance,
    required this.bankInstrumentCount,
    required this.soundsFound,
    required this.soundsParsed,
    required this.soundsFailed,
    this.soundErrors = const [],
  });

  Map<String, dynamic> toJson() => {
        'game': game,
        'skipped': skipped,
        'skipReason': skipReason,
        'error': error,
        'isEarlySci0': isEarlySci0,
        'usesPostSci01': usesPostSci01,
        'bankProvenance': bankProvenance,
        'bankInstrumentCount': bankInstrumentCount,
        'soundsFound': soundsFound,
        'soundsParsed': soundsParsed,
        'soundsFailed': soundsFailed,
        'soundErrors': soundErrors,
      };
}

bool _hasResourceMap(String dirPath) {
  try {
    for (final entity in Directory(dirPath).listSync()) {
      if (entity is File &&
          entity.path.split(Platform.pathSeparator).last.toUpperCase() ==
              'RESOURCE.MAP') {
        return true;
      }
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// Runs the full corpus scan. Production code path for the CLI; the
/// analysis functions above are the testable units.
Future<void> runMiner(MinerArgs args) async {
  final rootDir = Directory(args.root);
  if (!rootDir.existsSync()) {
    stderr.writeln('root not found: ${args.root}');
    exitCode = 2;
    return;
  }

  final games = <String>[
    for (final e in rootDir.listSync())
      if (e is Directory) e.path.split(Platform.pathSeparator).last,
  ]..sort();
  final selected = args.games == null
      ? games
      : games.where((g) => args.games!.contains(g.toLowerCase())).toList();

  final gameLoads = <GameLoadInfo>[];
  final sounds = <MinedSound>[];
  final rawTracks = <MinedSound, SciMidiTrack>{};
  final censusHistograms = <String, Map<int, int>>{};
  final referencedHistograms = <String, Map<int, int>>{};
  final globalKeyCounts = <String, int>{};
  final globalTagCounts = <String, int>{};
  final bankKeyCounts = <String, int>{};

  void bumpHist(Map<String, Map<int, int>> hist, SciAdlibInstrument ins) {
    for (final pv in patchParameterValues(ins)) {
      final m = hist.putIfAbsent(pv.param, () => <int, int>{});
      m[pv.value] = (m[pv.value] ?? 0) + 1;
    }
  }

  for (final game in selected) {
    final dirPath = '${args.root}${Platform.pathSeparator}$game';
    if (!_hasResourceMap(dirPath)) {
      gameLoads.add(GameLoadInfo(
        game: game,
        skipped: true,
        skipReason: 'no RESOURCE.MAP (AGI or non-SCI directory)',
        isEarlySci0: false,
        usesPostSci01: false,
        bankProvenance: 'unavailable',
        bankInstrumentCount: 0,
        soundsFound: 0,
        soundsParsed: 0,
        soundsFailed: 0,
      ));
      continue;
    }
    SciVolumeManager volumes;
    try {
      volumes = SciVolumeManager.fromDirectory(dirPath);
    } catch (e) {
      gameLoads.add(GameLoadInfo(
        game: game,
        skipped: false,
        error: '$e',
        isEarlySci0: false,
        usesPostSci01: false,
        bankProvenance: 'unavailable',
        bankInstrumentCount: 0,
        soundsFound: 0,
        soundsParsed: 0,
        soundsFailed: 0,
      ));
      continue;
    }

    var isEarly = false;
    var postSci01 = false;
    try {
      isEarly = volumes.isEarlySci0;
    } catch (_) {}
    try {
      postSci01 = volumes.usesPostSci01Compression;
    } catch (_) {}

    SciAdlibBank? bank;
    var bankProvenance = 'unavailable';
    try {
      final result = sciLoadAdlibBank(volumes);
      bank = result.bank;
      bankProvenance = result.bank?.debugSummary() ??
          'unavailable (${result.reason})';
      if (bank != null) {
        for (final ins in bank.instruments) {
          bumpHist(censusHistograms, ins);
          final key = patchFeatureKey(ins);
          bankKeyCounts[key] = (bankKeyCounts[key] ?? 0) + 1;
        }
      }
    } catch (e) {
      bankProvenance = 'unavailable (loader error: $e)';
    }

    final soundEntries = volumes.resourceMap.entriesForType(
      SciResourceType.sound,
    );
    var parsed = 0;
    var failed = 0;
    final soundErrors = <String>[];
    final referencedSeenThisGame = <int>{};
    for (final entry in soundEntries) {
      final number = entry.id.number;
      SciMidiTrack track;
      try {
        final bytes = volumes.getResource(SciResourceType.sound, number);
        track = SciMidiParser.parse(
          bytes,
          headerSize: postSci01
              ? null
              : (isEarly ? SciMidiParser.headerEarly : SciMidiParser.headerLate),
          soundFormat: postSci01
              ? SciMidiSoundFormat.sci1MultiTrack
              : SciMidiSoundFormat.sci0,
        );
      } catch (e) {
        failed++;
        soundErrors.add('sound $number: $e');
        continue;
      }
      parsed++;
      final features = analyzeTrackFeatures(track, bank: bank);
      if (bank != null) {
        for (final p in features.referencedPrograms) {
          if (p >= 0 &&
              p < bank.instrumentCount &&
              referencedSeenThisGame.add(p)) {
            bumpHist(referencedHistograms, bank.instruments[p]);
          }
        }
      }
      for (final key in features.patchKeys) {
        globalKeyCounts[key] = (globalKeyCounts[key] ?? 0) + 1;
      }
      for (final tag in features.tags) {
        globalTagCounts[tag] = (globalTagCounts[tag] ?? 0) + 1;
      }
      DriverSimResult? sim;
      if (bank != null) {
        try {
          sim = simulateDriver(
            track,
            bank,
            profile: (isEarly && !postSci01)
                ? SciAdlibProfile.sci0Early
                : SciAdlibProfile.sci0Late,
          );
        } catch (e) {
          sim = null;
          soundErrors.add('sound $number simulation: $e');
        }
      }
      final mined = MinedSound(
        game: game,
        resourceNumber: number,
        totalTicks: track.totalTicks,
        features: features,
        sim: sim,
        exemplars: <CorpusExemplar>[],
      );
      sounds.add(mined);
      rawTracks[mined] = track;
    }
    gameLoads.add(GameLoadInfo(
      game: game,
      skipped: false,
      isEarlySci0: isEarly,
      usesPostSci01: postSci01,
      bankProvenance: bankProvenance,
      bankInstrumentCount: bank?.instrumentCount ?? 0,
      soundsFound: soundEntries.length,
      soundsParsed: parsed,
      soundsFailed: failed,
      soundErrors: soundErrors,
    ));
  }

  // Novelty scores + exemplars (need global counts first).
  for (final sound in sounds) {
    sound.novelty = noveltyScore(
      patchKeys: sound.features.patchKeys,
      tags: sound.features.tags,
      globalKeyCounts: globalKeyCounts,
      globalTagCounts: globalTagCounts,
      features: sound.features,
      sim: sound.sim,
    );
  }
  // Rebuild exemplars with global counts. Re-run per-sound: exemplar
  // construction needs the bank; recover it per game below via a second
  // pass is unnecessary — exemplars were deferred; build them here using
  // stored tracks and per-game banks reloaded from globalKeyCounts? The
  // bank is not retained per sound, so exemplars are built during the
  // scan in a follow-up field assignment: we rebuild them now by
  // re-resolving the bank from the scan (kept in rawTracks keys).
  //
  // Note: banks are re-resolved cheaply from the volume cache per game.
  final bankByGame = <String, ({SciAdlibBank? bank})>{};
  for (final game in selected) {
    final dirPath = '${args.root}${Platform.pathSeparator}$game';
    try {
      final volumes = SciVolumeManager.fromDirectory(dirPath);
      bankByGame[game] = (bank: sciLoadAdlibBank(volumes).bank);
    } catch (_) {
      bankByGame[game] = (bank: null);
    }
  }
  for (final sound in sounds) {
    final track = rawTracks[sound];
    if (track == null) continue;
    sound.exemplars.addAll(buildExemplars(
      track,
      sound.features,
      bankByGame[sound.game]?.bank,
      globalKeyCounts: globalKeyCounts,
      globalTagCounts: globalTagCounts,
    ));
  }
  sounds.sort((a, b) => b.novelty.compareTo(a.novelty));

  final outDir = Directory(args.out);
  outDir.createSync(recursive: true);

  final json = {
    'games': [for (final g in gameLoads) g.toJson()],
    'aggregate': {
      'gamesScanned': gameLoads.where((g) => !g.skipped).length,
      'gamesSkipped': gameLoads.where((g) => g.skipped).length,
      'soundsParsed': sounds.length,
      'soundsFailed':
          gameLoads.fold(0, (s, g) => s + g.soundsFailed),
      'patchKeyCounts': globalKeyCounts,
      'tagCounts': globalTagCounts,
      'bankKeyCounts': bankKeyCounts,
      'censusHistograms': {
        for (final e in censusHistograms.entries)
          e.key: {for (final v in e.value.entries) '${v.key}': v.value},
      },
      'referencedHistograms': {
        for (final e in referencedHistograms.entries)
          e.key: {for (final v in e.value.entries) '${v.key}': v.value},
      },
    },
    'sounds': [for (final s in sounds) s.toJson()],
  };
  File(
    '${args.out}${Platform.pathSeparator}corpus_features.json',
  ).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(json),
  );

  File('${args.out}${Platform.pathSeparator}corpus_report.md')
      .writeAsStringSync(_buildReport(
    args: args,
    gameLoads: gameLoads,
    sounds: sounds,
    globalKeyCounts: globalKeyCounts,
    globalTagCounts: globalTagCounts,
    censusHistograms: censusHistograms,
    referencedHistograms: referencedHistograms,
  ));

  final scanned = gameLoads.where((g) => !g.skipped).length;
  final skipped = gameLoads.where((g) => g.skipped).length;
  final failedSounds = gameLoads.fold(0, (s, g) => s + g.soundsFailed);
  stdout.writeln(
    'Games scanned: $scanned, skipped: $skipped, '
    'sounds parsed: ${sounds.length}, failed: $failedSounds',
  );
  for (final s in sounds.take(3)) {
    stdout.writeln(
      '  novel: ${s.game} sound ${s.resourceNumber} '
      'score=${s.novelty.toStringAsFixed(2)} tags=${s.features.tags.join(',')}',
    );
  }
}

String _histogramText(Map<String, Map<int, int>> hist) {
  if (hist.isEmpty) return '(no patch data)';
  final params = hist.keys.toList()..sort();
  final lines = <String>[];
  for (final p in params) {
    final values = hist[p]!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final total = values.fold(0, (s, e) => s + e.value);
    lines.add('- $p (n=$total): ${values.map((e) => '${e.key}:${e.value}').join(' ')}');
  }
  return lines.join('\n');
}

String _buildReport({
  required MinerArgs args,
  required List<GameLoadInfo> gameLoads,
  required List<MinedSound> sounds,
  required Map<String, int> globalKeyCounts,
  required Map<String, int> globalTagCounts,
  required Map<String, Map<int, int>> censusHistograms,
  required Map<String, Map<int, int>> referencedHistograms,
}) {
  final b = StringBuffer();
  b.writeln('# SCI Audio Corpus Report');
  b.writeln();
  b.writeln('Root: `${args.root}`');
  b.writeln();
  b.writeln('## Novelty score formula');
  b.writeln();
  b.writeln('score = sum(1/sqrt(globalKeyCount)) over distinct patch feature '
      'keys + sum(1/sqrt(globalTagCount)) over distinct control tags + '
      '1.0 per present anomaly (sim drops>0, voices at end>0, out-of-bank '
      'program, digital sample, SysEx, same-tick chord>=6). Counts are '
      'per-sound usages across the corpus.');
  b.writeln();
  b.writeln('## Per-game load table');
  b.writeln();
  b.writeln('| game | skipped | early | post-SCI01 | bank | sounds '
      'found/parsed/failed |');
  b.writeln('|---|---|---|---|---|---|');
  for (final g in gameLoads) {
    b.writeln('| ${g.game} | ${g.skipped ? 'yes' : 'no'} | '
        '${g.isEarlySci0} | ${g.usesPostSci01} | ${g.bankProvenance} | '
        '${g.soundsFound}/${g.soundsParsed}/${g.soundsFailed} |');
    if (g.error != null) b.writeln('|  | | | error: ${g.error} | | |');
    if (g.skipped) b.writeln('|  | skip: ${g.skipReason} | | | | |');
    for (final e in g.soundErrors.take(10)) {
      b.writeln('|  | | | | | $e |');
    }
  }
  b.writeln();
  b.writeln('## Patch parameter histograms (bank-wide census)');
  b.writeln();
  b.writeln(_histogramText(censusHistograms));
  b.writeln();
  b.writeln('## Patch parameter histograms (referenced, deduped per game)');
  b.writeln();
  b.writeln(_histogramText(referencedHistograms));
  b.writeln();
  b.writeln('## Top ${args.topN} novel sounds');
  b.writeln();
  for (final s in sounds.take(args.topN)) {
    b.writeln('- ${s.game} sound ${s.resourceNumber}: '
        'score=${s.novelty.toStringAsFixed(2)}');
    b.writeln('  tags: ${s.features.tags.join(', ')}');
    b.writeln('  notes=${s.features.noteOns} '
        'maxChordTick=${s.features.sameTickChordMax} '
        'retrigger=${s.features.retriggerCount} '
        'drops=${s.sim?.inferredDrops ?? 'n/a'} '
        'stuck=${s.sim?.voicesAtEnd ?? 'n/a'} '
        'programs=${s.features.usedPrograms}');
    b.writeln('  patch keys (rarest first):');
    final keys = [...s.features.patchKeys]
      ..sort((a, c) => (globalKeyCounts[a] ?? 1).compareTo(
            globalKeyCounts[c] ?? 1,
          ));
    for (final key in keys.take(3)) {
      b.writeln('  - count=${globalKeyCounts[key]} $key');
    }
    for (final ex in s.exemplars) {
      b.writeln('  exemplar: ticks ${ex.tickStart}..${ex.tickEnd} '
          '(${ex.tickStart / 60}..${ex.tickEnd / 60}s) '
          'ch=${ex.channel} prog=${ex.program} — ${ex.reason}');
    }
  }
  b.writeln();
  b.writeln('## Rarest patch feature keys');
  b.writeln();
  final rare = globalKeyCounts.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  for (final e in rare.take(15)) {
    b.writeln('- count=${e.value} ${e.key}');
  }
  b.writeln();
  b.writeln('## Rarest control-pattern tags');
  b.writeln();
  final rareTags = globalTagCounts.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  for (final e in rareTags.take(15)) {
    b.writeln('- ${e.key}: ${e.value} sounds');
  }
  b.writeln();
  b.writeln('## Anomalies: dropped notes / stuck voices');
  b.writeln();
  for (final s in sounds) {
    if ((s.sim?.inferredDrops ?? 0) > 0 || (s.sim?.voicesAtEnd ?? 0) > 0) {
      b.writeln('- ${s.game} sound ${s.resourceNumber}: '
          'drops=${s.sim!.inferredDrops} '
          'stuck=${s.sim!.voicesAtEnd} '
          'steals=${s.sim!.steals} '
          'maxVoices=${s.sim!.maxActiveVoices}');
    }
  }
  b.writeln();
  b.writeln('## Anomalies: out-of-bank programs, digital, SysEx');
  b.writeln();
  for (final s in sounds) {
    if (s.features.outOfBankProgramCount > 0 ||
        s.features.hasDigitalSample ||
        s.features.sysExCount > 0) {
      b.writeln('- ${s.game} sound ${s.resourceNumber}: '
          'outOfBank=${s.features.outOfBankProgramCount} '
          'digital=${s.features.hasDigitalSample} '
          'sysex=${s.features.sysExCount}');
    }
  }
  return b.toString();
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.writeln(minerUsage);
    if (args.isEmpty) exitCode = 2;
    return;
  }
  late final MinerArgs minerArgs;
  try {
    minerArgs = parseMinerArgs(args);
  } on FormatException {
    stderr.writeln(minerUsage);
    exitCode = 2;
    return;
  }
  await runMiner(minerArgs);
}

