// Stage 5b: offline SCI0 AdLib audition renderer tests.
//
// Synthetic tracks are built with the model constructors (late 33-byte
// headers with the AdLib mask bit) and a synthetic 1344-byte bank whose
// every instrument is a loud sustained additive sine (modulator total
// level at max so the carrier dominates). Corpus tests skip when the
// reference games are absent and assert structural facts only (no
// copyrighted bytes are asserted).
//
// See doc/sci_adlib_mt32_audio_plan.md, Stage 5b.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_renderer.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

// --- Synthetic bank: every instrument a loud sustained sine. ---

Uint8List sineRecord() {
  final b = Uint8List(28);
  // Operator 0 (modulator): total level 63 (silent) so the carrier
  // dominates; attack 15 (instant), sustain 0 (full level).
  b[0] = 0; // kbScaleLevel 0
  b[1] = 1; // frequencyMult 1
  b[2] = 0; // feedback 0
  b[3] = 15; // attack 15
  b[4] = 0; // sustain 0
  b[5] = 1; // envelopeType 1 (sustain hold)
  b[6] = 8; // decay 8
  b[7] = 8; // release 8 (fast release so the tail test is robust)
  b[8] = 63; // totalLevel 63 (silent modulator)
  b[9] = 0;
  b[10] = 0;
  b[11] = 0;
  b[12] = 0; // algorithm 1 (additive)
  // Operator 1 (carrier): total level 0 (loud).
  b[13] = 0;
  b[14] = 1;
  b[15] = 0;
  b[16] = 15;
  b[17] = 0;
  b[18] = 1;
  b[19] = 8;
  b[20] = 8;
  b[21] = 0; // totalLevel 0
  b[22] = 0;
  b[23] = 0;
  b[24] = 0;
  b[25] = 0;
  b[26] = 0; // waveform 0 (sine)
  b[27] = 0;
  return b;
}

SciAdlibBank makeSineBank() {
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    data.setRange(28 * i, 28 * i + 28, sineRecord());
  }
  return SciAdlibBank.fromBytes(data);
}

// --- Synthetic tracks. ---

SciMidiChannelInit chLate(int channel, {int voices = 0, int mask = 0}) =>
    SciMidiChannelInit(
      channel: channel,
      rawBytes: [voices, mask],
      requestedVoices: voices,
      playMask: mask,
    );

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

SciMidiEvent endEv(int tick) => SciMidiEvent(
      tick: tick,
      kind: SciMidiEventKind.endOfTrack,
      channel: -1,
      status: 0xFC,
    );

SciMidiTrack makeRendererTrack({
  required List<SciMidiEvent> events,
  required int totalTicks,
  int channel = 0,
  bool masked = true,
}) {
  final channels = [for (var i = 0; i < 16; i++) chLate(i)];
  channels[channel] = chLate(channel,
      voices: masked ? 2 : 2, mask: masked ? 0x04 : 0x00);
  return SciMidiTrack(
    variant: SciMidiHeaderVariant.late,
    headerSize: 33,
    flagsByte: 0,
    hasDigitalSample: false,
    sampleFlagSetButNoData: false,
    sample: null,
    channels: channels,
    events: events,
    cues: const [],
    loopTick: null,
    totalTicks: totalTicks,
    hasEndOfTrack: true,
    isTruncated: false,
    truncatedTail: Uint8List(0),
  );
}

/// A 2-second A4 (note 69) on the masked channel, then end-of-track.
/// Includes a program change at tick 0: the driver only programs an
/// instrument when the channel's program differs from the initTrack
/// default (13) — a bare noteOn would leave chip operators at reset
/// state. All bank instruments are the same sine, so program 5 is used.
SciMidiTrack sustainedA4Track({bool masked = true, int channel = 0}) =>
    makeRendererTrack(
      masked: masked,
      channel: channel,
      totalTicks: 120,
      events: [
        programEv(0, channel, 5),
        noteOnEv(0, channel, 69, 100),
        noteOffEv(120, channel, 69),
        endEv(120),
      ],
    );

double rmsWindow(Int16List pcm, int startFrame, int frameCount) {
  var sum = 0.0;
  for (var i = startFrame; i < startFrame + frameCount && i < pcm.length; i++) {
    final s = pcm[i].toDouble();
    sum += s * s;
  }
  return math.sqrt(sum / frameCount);
}

int peakAbsOf(Int16List pcm) {
  var peak = 0;
  for (final s in pcm) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  return peak;
}

bool int16ListEquals(Int16List a, Int16List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('synthetic renders', () {
    test('simple note renders non-silent PCM with exact frame math', () {
      final result = sciAdLibRenderTrack(sustainedA4Track(), makeSineBank());
      const totalTicks = 120;
      const tailTicks = 30;
      final expectedFrames =
          ((totalTicks + tailTicks) * kOpl2SampleRate / 60).round();
      expect(result.totalFrames, expectedFrames);
      expect(result.pcm.length, expectedFrames);
      expect(result.renderedTicks, totalTicks);
      expect(result.sampleRate, kOpl2SampleRate);
      expect(result.sampleRate, 49716);
      expect(peakAbsOf(result.pcm), greaterThan(1000));
      expect(rmsWindow(result.pcm, kOpl2SampleRate ~/ 2, kOpl2SampleRate ~/ 2),
          greaterThan(500));
    });

    test('two renders are byte-identical (deterministic)', () {
      final bank = makeSineBank();
      final track = sustainedA4Track();
      final a = sciAdLibRenderTrack(track, bank);
      final b = sciAdLibRenderTrack(track, bank);
      expect(int16ListEquals(a.pcm, b.pcm), isTrue);
    });

    test('empty/end-only track renders silence of expected length', () {
      final track = makeRendererTrack(
        totalTicks: 60,
        events: [endEv(60)],
      );
      final result = sciAdLibRenderTrack(track, makeSineBank());
      final expectedFrames = ((60 + 30) * kOpl2SampleRate / 60).round();
      expect(result.totalFrames, expectedFrames);
      expect(result.pcm.length, expectedFrames);
      expect(peakAbsOf(result.pcm), 0);
    });

    test('channel filtering: unmasked channel is silent', () {
      final silent = sciAdLibRenderTrack(
          sustainedA4Track(masked: false), makeSineBank());
      final audible = sciAdLibRenderTrack(
          sustainedA4Track(masked: true), makeSineBank());
      expect(peakAbsOf(silent.pcm), 0);
      expect(peakAbsOf(audible.pcm), greaterThan(1000));
    });

    test('channel-15 program changes do not alter output', () {
      final base = sciAdLibRenderTrack(sustainedA4Track(), makeSineBank());
      final withCue = sciAdLibRenderTrack(
          makeRendererTrack(
            totalTicks: 120,
            events: [
              programEv(0, 15, 5),
              programEv(0, 0, 5),
              noteOnEv(0, 0, 69, 100),
              programEv(60, 15, 99),
              noteOffEv(120, 0, 69),
              endEv(120),
            ],
          ),
          makeSineBank());
      expect(withCue.totalFrames, base.totalFrames);
      expect(int16ListEquals(withCue.pcm, base.pcm), isTrue);
    });

    test('maxTicks caps duration', () {
      final track = makeRendererTrack(
        totalTicks: 120,
        events: [
          programEv(0, 0, 5),
          noteOnEv(0, 0, 69, 100),
          noteOffEv(120, 0, 69),
          endEv(120),
        ],
      );
      final result =
          sciAdLibRenderTrack(track, makeSineBank(), maxTicks: 60);
      expect(result.renderedTicks, 60);
      final expectedFrames = ((60 + 30) * kOpl2SampleRate / 60).round();
      expect(result.totalFrames, expectedFrames);
      expect(result.pcm.length, expectedFrames);
    });

    test('tail releases: final 0.25s RMS below sustained middle RMS', () {
      // A 3 s sustained note (no explicit off): allNotesOff at the end
      // releases it into the 0.5 s tail.
      final track = makeRendererTrack(
        totalTicks: 180,
        events: [
          programEv(0, 0, 5),
          noteOnEv(0, 0, 69, 100),
          endEv(180),
        ],
      );
      final result = sciAdLibRenderTrack(track, makeSineBank());
      final middle = rmsWindow(
          result.pcm, kOpl2SampleRate ~/ 2, kOpl2SampleRate ~/ 2);
      final tailQuarter = kOpl2SampleRate ~/ 4;
      final tail = rmsWindow(
          result.pcm, result.totalFrames - tailQuarter, tailQuarter);
      expect(middle, greaterThan(500));
      expect(tail, lessThan(middle * 0.5));
    });

    test('pitch sanity: sustained A4 zero-crossing rate near 440 Hz', () {
      final result = sciAdLibRenderTrack(sustainedA4Track(), makeSineBank());
      final start = kOpl2SampleRate ~/ 2; // 0.5 s (steady state)
      final frames = kOpl2SampleRate; // 1 s window
      var crossings = 0;
      var prevSign = result.pcm[start] >= 0 ? 1 : -1;
      for (var i = start + 1; i < start + frames; i++) {
        final sign = result.pcm[i] >= 0 ? 1 : -1;
        if (sign != prevSign) crossings++;
        prevSign = sign;
      }
      final freq = (crossings / 2) / (frames / kOpl2SampleRate);
      expect(freq, closeTo(440, 440 * 0.03));
    });
  });

  group('volume convenience', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sci_adlib_renderer_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    void writeMap(List<(int id, int offset)> entries) {
      final mapFile = File('${tempDir.path}/RESOURCE.MAP');
      final mapData = Uint8List((entries.length + 1) * 6);
      final bd = ByteData.sublistView(mapData);
      for (var i = 0; i < entries.length; i++) {
        bd.setUint16(i * 6, entries[i].$1, Endian.little);
        bd.setUint32(i * 6 + 2, entries[i].$2, Endian.little);
      }
      bd.setUint32(entries.length * 6 + 2, 0xFFFFFFFF, Endian.little);
      mapFile.writeAsBytesSync(mapData);
    }

    void writeVolumeRecord(List<int> payload, int recordId) {
      final volFile = File('${tempDir.path}/RESOURCE.000');
      final volData = Uint8List(8 + payload.length);
      final bd = ByteData.sublistView(volData);
      bd.setUint16(0, recordId, Endian.little);
      bd.setUint16(2, payload.length + 4, Endian.little);
      bd.setUint16(4, payload.length, Endian.little);
      bd.setUint16(6, 0, Endian.little);
      volData.setRange(8, 8 + payload.length, payload);
      volFile.writeAsBytesSync(volData);
    }

    test('missing sound resource returns unavailable', () {
      writeMap([]); // sentinel only: no resources at all.
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);
      final result = sciAdLibRenderSound(vm, 42);
      expect(result.isAvailable, isFalse);
      expect(result.render, isNull);
      expect(result.unavailableReason, isNotNull);
      expect(result.provenance, SciAdlibBankProvenance.unavailable);
    });

    test('sound present but no bank and no ADL.DRV is unavailable', () {
      // Late 33-byte header (channel 0 masked) + end-of-track.
      final sound = Uint8List(34);
      sound[0] = 0;
      sound[1] = 2; // channel 0: 2 requested voices
      sound[2] = 0x04; // channel 0: AdLib mask
      sound[33] = 0xFC; // end of track
      final id = (SciResourceType.sound.typeCode << 11) | 5;
      writeMap([(id, 0)]);
      writeVolumeRecord(sound, id);
      final vm = SciVolumeManager.fromDirectory(tempDir.path);
      addTearDown(vm.close);
      final result = sciAdLibRenderSound(vm, 5);
      expect(result.isAvailable, isFalse);
      expect(result.render, isNull);
      expect(result.unavailableReason, contains('bank unavailable'));
      expect(result.provenance, SciAdlibBankProvenance.unavailable);
    });
  });

  group('WAV helper', () {
    test('RIFF header with 49716 Hz mono and matching data size', () {
      final result = sciAdLibRenderTrack(sustainedA4Track(), makeSineBank());
      final wav = sciAdLibRenderToWav(result);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(24, Endian.little), 49716);
      expect(bd.getUint16(22, Endian.little), 1);
      final dataSize = bd.getUint32(40, Endian.little);
      expect(dataSize, result.pcm.length * 2);
      expect(wav.length, 44 + dataSize);
    });
  });

  group('corpus', () {
    // Iterates sound numbers ascending, renders each capped at 300 ticks
    // (5 s), and returns the first render with peak above threshold.
    (SciAdLibVolumeRenderResult, int)? firstAudible(
        String gameDir, int peakThreshold, int limit) {
      final vm = SciVolumeManager.fromDirectory(referenceGamePath(gameDir));
      addTearDown(vm.close);
      final numbers = vm.resourceMap.entriesForType(SciResourceType.sound);
      var checked = 0;
      for (final entry in numbers) {
        if (checked >= limit) break;
        checked++;
        final result = sciAdLibRenderSound(vm, entry.id.number, maxTicks: 300);
        if (!result.isAvailable) continue;
        if (result.render!.peakAbs > peakThreshold) {
          return (result, entry.id.number);
        }
      }
      return null;
    }

    double rmsOf(SciAdLibRenderResult render) =>
        rmsWindow(render.pcm, 0, render.pcm.length);

    test('PQ2: an early sound renders non-silent via AdLib', () {
      if (skipIfReferenceGameMissing('police-quest-2')) return;
      final found = firstAudible('police-quest-2', 500, 12);
      expect(found, isNotNull,
          reason: 'no non-silent sound among first 12 PQ2 sounds');
      final (result, number) = found!;
      // ignore: avoid_print
      print('PQ2 sound.$number peak=${result.render!.peakAbs} '
          'rms=${rmsOf(result.render!).toStringAsFixed(1)} '
          'provenance=${result.provenance}');
    });

    test('KQ4 SCI: embedded bank renders non-silent', () {
      if (skipIfReferenceGameMissing('kings-quest-4-sci')) return;
      final found = firstAudible('kings-quest-4-sci', 500, 12);
      expect(found, isNotNull,
          reason: 'no non-silent sound among first 12 KQ4 sounds');
      final (result, number) = found!;
      expect(result.provenance, SciAdlibBankProvenance.embeddedAdlDrv);
      // ignore: avoid_print
      print('KQ4 sound.$number peak=${result.render!.peakAbs} '
          'rms=${rmsOf(result.render!).toStringAsFixed(1)} '
          'provenance=${result.provenance}');
    });

    test('SQ3: an early sound renders non-silent via AdLib', () {
      if (skipIfReferenceGameMissing('space-quest-3')) return;
      final found = firstAudible('space-quest-3', 500, 12);
      expect(found, isNotNull,
          reason: 'no non-silent sound among first 12 SQ3 sounds');
      final (result, number) = found!;
      // ignore: avoid_print
      print('SQ3 sound.$number peak=${result.render!.peakAbs} '
          'rms=${rmsOf(result.render!).toStringAsFixed(1)} '
          'provenance=${result.provenance}');
    });
  });
}



