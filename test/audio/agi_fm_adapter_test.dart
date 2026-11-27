// Stage 9: AGI FM adapter tests (preset registry, translation rules,
// dynamics, noise mixing, determinism, sizing, seek/reset, and the
// per-preset 3rd-harmonic comparison). All fixtures are synthetic
// (no game bytes asserted).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_agigame/audio/agi_fm_adapter.dart';
import 'package:flutter_agigame/audio/agi_pcm_source.dart';
import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/pcm_source.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:test/test.dart';

import '../support/reference_games.dart';

SynthesizerConfig fmConfig({
  int sampleRate = 44100,
  String fmPresetId = 'neutralKeys',
  double masterVolume = 0.75,
  AgiFmNoiseSource fmNoiseSource = AgiFmNoiseSource.tandy,
  double voice1Gain = 1.0,
  double voice2Gain = 1.0,
  double voice3Gain = 1.0,
  double voice1Pan = 0.35,
  double voice2Pan = 0.65,
  double voice3Pan = 0.50,
  double noisePan = 0.50,
}) =>
    SynthesizerConfig(
      sampleRate: sampleRate,
      mode: PcmPlaybackMode.fmPresets,
      masterVolume: masterVolume,
      fmPresetId: fmPresetId,
      fmNoiseSource: fmNoiseSource,
      voice1Gain: voice1Gain,
      voice2Gain: voice2Gain,
      voice3Gain: voice3Gain,
      voice1Pan: voice1Pan,
      voice2Pan: voice2Pan,
      voice3Pan: voice3Pan,
      noisePan: noisePan,
    );

/// Single sustained voice, no noise. [start: [freqCount, dur, att]...].
AgiSound oneVoice(List<List<int>> notes) => AgiSound(voices: [
      ToneChannel(
        notes: [
          for (final n in notes)
            AgiNote(
              startTime: n[0],
              frequencyCount: n[1],
              duration: n[2],
              attenuation: n[3],
            ),
        ],
      ),
    ]);

/// Three voices sounding together; voice 1 carries the interesting
/// translation fixtures (contiguous attenuation change, pitch change,
/// gap), voices 2/3 sustain.
AgiSound threeVoices() => AgiSound(voices: [
      ToneChannel(notes: [
        // Contiguous same-pitch attenuation change (levels-only).
        AgiNote(startTime: 0, frequencyCount: 120, duration: 10, attenuation: 2),
        AgiNote(startTime: 10, frequencyCount: 120, duration: 10, attenuation: 6),
        // Contiguous pitch change (legato).
        AgiNote(startTime: 20, frequencyCount: 100, duration: 10, attenuation: 3),
        // Gap, then a fresh note.
        AgiNote(startTime: 35, frequencyCount: 80, duration: 25, attenuation: 4),
      ]),
      ToneChannel(notes: [
        AgiNote(startTime: 0, frequencyCount: 160, duration: 60, attenuation: 8),
      ]),
      ToneChannel(notes: [
        AgiNote(startTime: 0, frequencyCount: 75, duration: 60, attenuation: 5),
      ]),
    ]);

AgiSound noiseOnlySound() => AgiSound(
      voices: [
        ToneChannel(notes: const [
          AgiNote(startTime: 0, duration: 1, frequencyCount: 0, attenuation: 15),
        ]),
      ],
      noise: const NoiseChannel(noises: [
        AgiNoise(startTime: 0, duration: 60, frequencyCount: 0x10, attenuation: 4, type: NoiseType.white),
      ]),
    );

Int16List drain(PcmSource source, int blockSize) {
  final total = source.totalFrames ?? 0;
  final out = Int16List(total * 2);
  final scratch = Int16List(blockSize * 2);
  var frames = 0;
  while (!source.isFinished) {
    final n = source.renderInto(scratch, blockSize);
    expect(n, greaterThan(0));
    out.setRange(frames * 2, frames * 2 + n * 2, scratch);
    frames += n;
  }
  expect(frames, equals(total));
  return out;
}

double rms(Int16List pcm) {
  if (pcm.isEmpty) return 0.0;
  var sum = 0.0;
  for (final v in pcm) {
    sum += v * v;
  }
  return sqrt(sum / pcm.length);
}

/// Key-edge counts on 0xB0+[voice] from a source write log: rising
/// edges (0x20 bit newly set), falling edges (bit newly clear).
({int rising, int falling, int keyWrites}) keyEdges(
    List<OplWriteRecord> log, int voice) {
  final addr = 0xB0 + voice;
  var rising = 0;
  var falling = 0;
  var keyWrites = 0;
  var keyed = false;
  for (final r in log) {
    if (r.address != addr) continue;
    final keyedNow = (r.value & 0x20) != 0;
    keyWrites++;
    if (keyedNow && !keyed) rising++;
    if (!keyedNow && keyed) falling++;
    keyed = keyedNow;
  }
  return (rising: rising, falling: falling, keyWrites: keyWrites);
}

AgiFmPcmSource fmSource(AgiSound sound, SynthesizerConfig config) =>
    AgiFmPcmSource(sound, config: config);

void main() {
  group('preset registry', () {
    test('five presets, unique ids, lookup falls back to first', () {
      expect(kAgiFmPresets.length, equals(5));
      final ids = kAgiFmPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, equals(5));
      expect(ids, containsAll(<String>[
        'neutralKeys',
        'brightBrass',
        'softOrgan',
        'bassLeadSplit',
        'nearSquare',
      ]));
      for (final id in ids) {
        expect(agiFmPresetForId(id).id, equals(id));
      }
      expect(agiFmPresetForId('no-such-preset').id, equals(kAgiFmPresets.first.id));
      expect(agiFmPresetForId('').id, equals(kAgiFmPresets.first.id));
      for (final p in kAgiFmPresets) {
        expect(p.lead, isNotNull);
        expect(p.harmony, isNotNull);
        expect(p.bass, isNotNull);
        expect(p.outputTrim, greaterThan(0));
      }
    });
  });

  group('SciAdlibInstrument.fromFields', () {
    test('round-trip fromRecord(fromFields) field equality', () {
      final instrument = SciAdlibInstrument.fromFields(
        operator0: const SciAdlibOperator(
          kbScaleLevel: 1,
          frequencyMult: 3,
          attackRate: 9,
          sustainLevel: 7,
          envelopeType: 1,
          decayRate: 8,
          releaseRate: 11,
          totalLevel: 22,
          amplitudeMod: 0,
          vibrato: 0,
          kbScaleRate: 0,
          waveForm: 2,
        ),
        operator1: const SciAdlibOperator(
          kbScaleLevel: 2,
          frequencyMult: 1,
          attackRate: 6,
          sustainLevel: 4,
          envelopeType: 1,
          decayRate: 5,
          releaseRate: 9,
          totalLevel: 12,
          amplitudeMod: 0,
          vibrato: 0,
          kbScaleRate: 0,
          waveForm: 1,
        ),
        modulator: const SciAdlibModulator(feedback: 2, algorithm: 0),
      );
      expect(instrument.rawBytes.length, equals(kSciAdlibRecordSize));
      final roundTripped =
          SciAdlibInstrument.fromRecord(instrument.rawBytes);
      expect(roundTripped.debugString(), equals(instrument.debugString()));
    });
  });

  group('translation rules (write log)', () {
    test('attenuation-only contiguous change: no second key-on', () {
      // Contiguous same-pitch attenuation change in voice 1.
      final sound = oneVoice([
        [0, 120, 10, 2],
        [10, 120, 10, 6],
      ]);
      final source = fmSource(sound, fmConfig());
      source.writeLogEnabled = true;
      drain(source, 4096);
      final edges = keyEdges(source.leftWriteLogs, 0);
      // One key-on for the first segment, key-off at track end.
      expect(edges.rising, equals(1));
      expect(edges.falling, equals(1));
      // Levels-only update writes no 0xB0 at all: exactly two key
      // writes on the left chip (key-on + track-end key-off).
      expect(edges.keyWrites, equals(2));
    });

    test('pitch change: pitch rewrite without key-off first', () {
      final sound = oneVoice([
        [0, 120, 10, 2],
        [10, 100, 10, 3],
      ]);
      final source = fmSource(sound, fmConfig());
      source.writeLogEnabled = true;
      drain(source, 4096);
      final edges = keyEdges(source.leftWriteLogs, 0);
      expect(edges.rising, equals(1));
      expect(edges.falling, equals(1));
      // Key-on + legato rewrite (key bit still set) + final key-off.
      expect(edges.keyWrites, equals(3));
    });

    test('gap produces key-off then a fresh key-on', () {
      final sound = oneVoice([
        [0, 120, 10, 2],
        [20, 120, 10, 2],
      ]);
      final source = fmSource(sound, fmConfig());
      source.writeLogEnabled = true;
      drain(source, 4096);
      final edges = keyEdges(source.leftWriteLogs, 0);
      expect(edges.rising, equals(2));
      expect(edges.falling, equals(2));
    });

    test('silent segment keys off at its start (Tandy quiet frame)', () {
      final sound = oneVoice([
        [0, 120, 10, 2],
        [10, 120, 10, 15],
      ]);
      final source = fmSource(sound, fmConfig());
      source.writeLogEnabled = true;
      drain(source, 4096);
      final edges = keyEdges(source.leftWriteLogs, 0);
      expect(edges.rising, equals(1));
      expect(edges.falling, equals(1));
    });
  });

  group('dynamics', () {
    test('attenuation 0 vs 8: RMS ratio between -10 and -22 dB', () {
      final loud = oneVoice([
        [0, 120, 60, 0],
      ]);
      final quiet = oneVoice([
        [0, 120, 60, 8],
      ]);
      final loudRms = rms(drain(fmSource(loud, fmConfig()), 4096));
      final quietRms = rms(drain(fmSource(quiet, fmConfig()), 4096));
      expect(loudRms, greaterThan(0));
      expect(quietRms, greaterThan(0));
      // log() is ln: dB = 20 * ln(ratio) / ln(10).
      final db = 20 * log(loudRms / quietRms) / 2.302585093;
      expect(db, greaterThan(10));
      expect(db, lessThan(22));
    });
  });

  group('noise mixing', () {
    test('tandy: noise-only fixture is non-silent', () {
      final pcm = drain(fmSource(noiseOnlySound(), fmConfig()), 4096);
      expect(rms(pcm), greaterThan(0));
    });

    test('off: noise-only fixture is silent', () {
      final pcm = drain(
        fmSource(
          noiseOnlySound(),
          fmConfig(fmNoiseSource: AgiFmNoiseSource.off),
        ),
        4096,
      );
      expect(rms(pcm), equals(0));
    });
  });

  group('rendering', () {
    test('block-split determinism at 44100', () {
      Int16List? reference;
      for (final block in [1, 7, 255, 1023, 1024, 4096]) {
        final pcm = drain(fmSource(threeVoices(), fmConfig()), block);
        reference ??= pcm;
        expect(pcm, equals(reference));
      }
    });

    test('totalFrames equals tick length + 30-tick tail (no noise)', () {
      final sound = threeVoices();
      final source = fmSource(sound, fmConfig());
      expect(
        source.totalFrames,
        equals(((sound.length + 30) * 44100 / 60).round()),
      );
    });

    test('zero-length sound has zero totalFrames', () {
      final sound = oneVoice([
        [0, 120, 0, 0],
      ]);
      expect(sound.length, equals(0));
      final source = fmSource(sound, fmConfig());
      expect(source.totalFrames, equals(0));
      expect(source.isFinished, isTrue);
      expect(source.renderInto(Int16List(16), 8), equals(0));
    });

    test('renderInto rejects an undersized destination', () {
      final source = fmSource(threeVoices(), fmConfig());
      expect(() => source.renderInto(Int16List(10), 100), throwsArgumentError);
      expect(source.positionFrames, equals(0));
    });

    test('short return only at end-of-stream', () {
      final source = fmSource(threeVoices(), fmConfig());
      final total = source.totalFrames!;
      final scratch = Int16List(4096 * 2);
      while (!source.isFinished) {
        final before = source.positionFrames;
        final n = source.renderInto(scratch, 4096);
        expect(n, equals((4096).clamp(0, total - before)));
      }
    });

    test('seek and reset equivalence', () {
      const captureStart = 5000;
      const captureFrames = 1200;
      final continuous = fmSource(threeVoices(), fmConfig());
      final buffer = Int16List(4096 * 2);
      while (continuous.positionFrames < captureStart) {
        continuous.renderInto(
          buffer,
          (captureStart - continuous.positionFrames).clamp(1, 4096),
        );
      }
      final continuousBlock = Int16List(captureFrames * 2);
      continuous.renderInto(continuousBlock, captureFrames);

      final sought = fmSource(threeVoices(), fmConfig());
      sought.seekToFrame(captureStart);
      final soughtBlock = Int16List(captureFrames * 2);
      sought.renderInto(soughtBlock, captureFrames);
      expect(soughtBlock, equals(continuousBlock));

      sought.reset();
      expect(sought.positionFrames, equals(0));
      final resetBlock = Int16List(captureFrames * 2);
      sought.renderInto(resetBlock, captureFrames);
      final fresh = fmSource(threeVoices(), fmConfig());
      final freshBlock = Int16List(captureFrames * 2);
      fresh.renderInto(freshBlock, captureFrames);
      expect(resetBlock, equals(freshBlock));
    });

    test('unknown preset id falls back without throwing', () {
      final source = fmSource(threeVoices(), fmConfig(fmPresetId: 'bogus'));
      expect(rms(drain(source, 4096)), greaterThan(0));
    });
  });

  group('presets', () {
    test('every preset renders non-silent on a 3-voice fixture', () {
      for (final preset in kAgiFmPresets) {
        final pcm = drain(fmSource(threeVoices(), fmConfig(fmPresetId: preset.id)), 4096);
        expect(rms(pcm), greaterThan(0), reason: 'preset ${preset.id}');
      }
    });

    test('nearSquare has stronger 3rd harmonic than softOrgan', () {
      // 440 Hz: count64 = 111860.78 / 440 ~= 254.
      final sound = oneVoice([
        [0, 254, 60, 0],
      ]);
      double measure(String presetId) {
        final pcm = drain(
          fmSource(sound, fmConfig(fmPresetId: presetId)),
          4096,
        );
        // Measure the sustain region only (skip attack/decay settle).
        const rate = 44100;
        final start = (0.3 * rate).toInt();
        final end = (0.9 * rate).toInt();
        final freq = AgiNote.tandyClockDiv32 / 254;
        double goertzel(double f) {
          var re = 0.0;
          var im = 0.0;
          for (var i = start; i < end; i++) {
            final phase = 2 * pi * f * i / rate;
            final s = pcm[i * 2] / 32768;
            re += s * cos(phase);
            im += s * sin(phase);
          }
          return sqrt(re * re + im * im);
        }

        return goertzel(3 * freq) / max(1e-9, goertzel(freq));
      }

      final squareRatio = measure('nearSquare');
      final organRatio = measure('softOrgan');
      // Observed (deterministic renders): ~0.43 vs ~0.02.
      expect(squareRatio, greaterThan(3 * organRatio));
      expect(squareRatio, greaterThan(0.15));
    });
  });

  group('voice gains', () {
    test('voice gain 0 silences only that voice', () {
      final sound = threeVoices();
      final full = rms(drain(fmSource(sound, fmConfig()), 4096));
      final silenced =
          rms(drain(fmSource(sound, fmConfig(voice1Gain: 0.0)), 4096));
      expect(full, greaterThan(0));
      // Other voices keep sounding...
      expect(silenced, greaterThan(0));
      // ...but removing voice 1 reduces the mix.
      expect(silenced, lessThan(full));

      final single = oneVoice([
        [0, 120, 60, 0],
      ]);
      final zeroed =
          rms(drain(fmSource(single, fmConfig(voice1Gain: 0.0)), 4096));
      expect(zeroed, equals(0));
    });
  });

  group('factory', () {
    test('createAgiPcmSource routes fmPresets to the adapter', () {
      final sound = threeVoices();
      final fm = createAgiPcmSource(sound, fmConfig());
      expect(fm, isA<AgiFmPcmSource>());
      final tandy = createAgiPcmSource(
        sound,
        const SynthesizerConfig(mode: PcmPlaybackMode.tandy3VoiceNoise),
      );
      expect(tandy, isA<AgiPcmSource>());
      final enhanced = createAgiPcmSource(
        sound,
        const SynthesizerConfig(mode: PcmPlaybackMode.enhanced),
      );
      expect(enhanced, isA<AgiPcmSource>());
    });

    test('PcmSynthesizer renders FM through the factory', () {
      final sound = threeVoices();
      final viaSynth = PcmSynthesizer(fmConfig()).renderPcm(sound);
      final viaSource = drain(fmSource(sound, fmConfig()), 4096);
      expect(viaSynth, equals(viaSource));
      expect(rms(viaSynth), greaterThan(0));
    });
  });

  group('corpus (kings-quest-1-agi)', skip: referenceGameSkip('kings-quest-1-agi'),
      () {
    const game = 'kings-quest-1-agi';
      test('music fixture: Tandy vs FM both non-silent, RMS within 0.25x..4x',
          () async {
        if (skipIfReferenceGameMissing(game)) return;
        final loader = await AgiResourceLoader.fromDirectory(
          referenceGamePath(game),
        );
        AgiSound? music;
        for (final n in loader.presentSoundNumbers) {
          AgiSound snd;
          try {
            snd = loader.loadSound(n);
          } catch (_) {
            continue;
          }
          if (snd.voices.length >= 3 &&
              snd.voices.every((v) => v.notes.any((note) => !note.isSilent))) {
            music = snd;
            break;
          }
        }
        expect(music, isNotNull, reason: 'no 3-voice sound in $game');
        final sound = music!;
        final len = sound.length;
        expect(len, greaterThan(0));
        final tandy = PcmSynthesizer(
          const SynthesizerConfig(mode: PcmPlaybackMode.tandy3VoiceNoise),
        ).renderPcm(sound);
        final fm = PcmSynthesizer(fmConfig()).renderPcm(sound);
        final tandyRms = rms(tandy);
        final fmRms = rms(fm);
        expect(tandyRms, greaterThan(0));
        expect(fmRms, greaterThan(0));
        expect(fmRms, greaterThanOrEqualTo(0.25 * tandyRms));
        expect(fmRms, lessThanOrEqualTo(4.0 * tandyRms));
      });

      test('noise fixture: FM mixes noise non-silent and off is silent-routed',
          () async {
        if (skipIfReferenceGameMissing(game)) return;
        final loader = await AgiResourceLoader.fromDirectory(
          referenceGamePath(game),
        );
        AgiSound? noiseSound;
        for (final n in loader.presentSoundNumbers) {
          AgiSound snd;
          try {
            snd = loader.loadSound(n);
          } catch (_) {
            continue;
          }
          if (snd.noise != null && snd.noise!.noises.any((x) => !x.isSilent)) {
            noiseSound = snd;
            break;
          }
        }
        expect(noiseSound, isNotNull, reason: 'no noise sound in $game');
        final sound = noiseSound!;
        // Same tick length on both routes.
        expect(sound.length, greaterThan(0));
        final fm = drain(fmSource(sound, fmConfig()), 4096);
        expect(rms(fm), greaterThan(0));
        final offSource =
            fmSource(sound, fmConfig(fmNoiseSource: AgiFmNoiseSource.off));
        final off = drain(offSource, 4096);
        expect(
          offSource.totalFrames,
          equals(((sound.length + 30) * 44100 / 60).round()),
        );
        expect(off.length, equals(offSource.totalFrames! * 2));
      });
    });
}

