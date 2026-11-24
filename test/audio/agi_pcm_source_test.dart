import 'dart:typed_data';

import 'package:flutter_agigame/audio/agi_pcm_source.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:test/test.dart';

/// FNV-1a 32-bit hash over the PCM samples (each offset by +32768).
/// The expected values below were captured from the legacy one-shot
/// renderer before it became a facade over [AgiPcmSource], so they
/// pin byte-for-byte identical output, not just self-consistency.
String fnv(Int16List s) {
  var h = 0x811c9dc5;
  for (final v in s) {
    final x = v + 32768;
    h ^= x & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
    h ^= (x >> 8) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

final _exampleSoundBytes = Uint8List.fromList([
  8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
  149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
  160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
  0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
]);

/// Multi-voice sound with a noise channel, exercising: 3 tone voices,
/// a silent note, a same-frequency attenuation change, periodic and
/// white noise, and the tone-3-linked noise clock (0x00).
AgiSound multiVoiceSound() => AgiSound(
      voices: [
        ToneChannel(notes: [
          AgiNote(startTime: 0, duration: 30, frequencyCount: 120, attenuation: 2),
          AgiNote(startTime: 30, duration: 20, frequencyCount: 120, attenuation: 6),
          AgiNote(startTime: 50, duration: 15, frequencyCount: 200, attenuation: 15),
          AgiNote(startTime: 65, duration: 25, frequencyCount: 90, attenuation: 4),
        ]),
        ToneChannel(notes: [
          AgiNote(startTime: 0, duration: 45, frequencyCount: 160, attenuation: 8),
          AgiNote(startTime: 45, duration: 45, frequencyCount: 110, attenuation: 3),
        ]),
        ToneChannel(notes: [
          AgiNote(startTime: 10, duration: 40, frequencyCount: 75, attenuation: 5),
          AgiNote(startTime: 50, duration: 40, frequencyCount: 75, attenuation: 5),
        ]),
      ],
      noise: NoiseChannel(noises: [
        AgiNoise(startTime: 0, duration: 40, frequencyCount: 0x00, attenuation: 7, type: NoiseType.white),
        AgiNoise(startTime: 40, duration: 25, frequencyCount: 0x10, attenuation: 9, type: NoiseType.periodic),
        AgiNoise(startTime: 65, duration: 25, frequencyCount: 0x40, attenuation: 11, type: NoiseType.white),
      ]),
    );

Int16List drain(AgiPcmSource source, int blockSize) {
  final total = source.totalFrames ?? 0;
  final out = Int16List(total * 2);
  var frames = 0;
  final scratch = Int16List(blockSize * 2);
  while (!source.isFinished) {
    final n = source.renderInto(scratch, blockSize);
    expect(n, greaterThan(0));
    out.setRange(frames * 2, frames * 2 + n * 2, scratch);
    frames += n;
  }
  expect(frames, equals(total));
  return out;
}

void main() {
  group('AgiPcmSource', () {
    late AgiSound parserSound;
    late AgiSound sound;

    setUp(() {
      parserSound = SoundParser.parse(_exampleSoundBytes);
      sound = multiVoiceSound();
    });

    group('golden equality with PcmSynthesizer.renderPcm', () {
      final configs = <String, SynthesizerConfig>{
        'pcSpeaker': SynthesizerConfig.ibmPc(),
        'pcJr': SynthesizerConfig.tandy(),
        'enhanced+reverb': SynthesizerConfig.enhanced(),
        'enhancedSine': SynthesizerConfig.enhanced(waveform: WaveformType.sine),
        'enhancedSawtooth': SynthesizerConfig.enhanced(waveform: WaveformType.sawtooth),
        'enhancedTriangle': SynthesizerConfig.enhanced(waveform: WaveformType.triangle),
        'tandy+reverb': SynthesizerConfig.tandy().copyWith(enableReverb: true, reverbMix: 0.4),
      };

      for (final entry in configs.entries) {
        test('${entry.key} (parser sound)', () {
          final expected = PcmSynthesizer(entry.value).renderPcm(parserSound);
          final actual = drain(AgiPcmSource(parserSound, config: entry.value), 4096);
          expect(actual.length, equals(expected.length));
          expect(actual, equals(expected));
        });

        test('${entry.key} (multi-voice sound)', () {
          final expected = PcmSynthesizer(entry.value).renderPcm(sound);
          final actual = drain(AgiPcmSource(sound, config: entry.value), 4096);
          expect(actual.length, equals(expected.length));
          expect(actual, equals(expected));
        });
      }

      test('matches legacy golden hashes (pre-refactor output)', () {
        final expectations = <String, String>{
          'parser/ibmPc': '2a4768b5',
          'parser/tandy': 'd122b6dd',
          'parser/enhanced': '3bbde6e2',
          'parser/enhancedSine': '52a9f20b',
          'parser/enhancedSaw': '22cfb9ba',
          'parser/enhancedTri': 'cb389970',
          'parser/tandyReverb': 'ec1be23f',
          'constructed/ibmPc': '3ea5a319',
          'constructed/tandy': 'a30080b6',
          'constructed/enhanced': 'eb5bfd52',
          'constructed/enhancedSine': '35396083',
          'constructed/enhancedSaw': 'de122957',
          'constructed/enhancedTri': '135d44a0',
          'constructed/tandyReverb': '754b7189',
        };
        final cfgByName = <String, SynthesizerConfig>{
          'ibmPc': SynthesizerConfig.ibmPc(),
          'tandy': SynthesizerConfig.tandy(),
          'enhanced': SynthesizerConfig.enhanced(),
          'enhancedSine': SynthesizerConfig.enhanced(waveform: WaveformType.sine),
          'enhancedSaw': SynthesizerConfig.enhanced(waveform: WaveformType.sawtooth),
          'enhancedTri': SynthesizerConfig.enhanced(waveform: WaveformType.triangle),
          'tandyReverb': SynthesizerConfig.tandy().copyWith(enableReverb: true, reverbMix: 0.4),
        };
        final sounds = <String, AgiSound>{'parser': parserSound, 'constructed': sound};
        for (final s in sounds.entries) {
          for (final c in cfgByName.entries) {
            final key = '${s.key}/${c.key}';
            final actual = PcmSynthesizer(c.value).renderPcm(s.value);
            expect(fnv(actual), equals(expectations[key]), reason: key);
          }
        }
      });
    });

    group('block-size invariance', () {
      final configs = <String, SynthesizerConfig>{
        'pcSpeaker': SynthesizerConfig.ibmPc(),
        'pcJr': SynthesizerConfig.tandy(),
        'enhanced+reverb': SynthesizerConfig.enhanced(),
        'tandy+reverb': SynthesizerConfig.tandy().copyWith(enableReverb: true, reverbMix: 0.4),
      };

      for (final entry in configs.entries) {
        test('${entry.key} (multi-voice sound)', () {
          final reference = drain(AgiPcmSource(sound, config: entry.value), 4096);
          for (final block in [1, 17, 512]) {
            final actual = drain(AgiPcmSource(sound, config: entry.value), block);
            expect(actual, equals(reference), reason: 'block size $block');
          }
        });

        test('${entry.key} (parser sound)', () {
          final reference = drain(AgiPcmSource(parserSound, config: entry.value), 4096);
          for (final block in [1, 17, 512]) {
            final actual = drain(AgiPcmSource(parserSound, config: entry.value), block);
            expect(actual, equals(reference), reason: 'block size $block');
          }
        });
      }
    });

    group('seek', () {
      for (final entry in <String, SynthesizerConfig>{
        'pcJr': SynthesizerConfig.tandy(),
        'enhanced+reverb': SynthesizerConfig.enhanced(),
      }.entries) {
        test('${entry.key}: seek matches continuous render', () {
          // Continuous render: capture frames [3000, 3500).
          final continuous = AgiPcmSource(sound, config: entry.value);
          final buffer = Int16List(4096 * 2);
          const captureStart = 3000;
          const captureFrames = 500;
          while (continuous.positionFrames < captureStart) {
            final chunk = (captureStart - continuous.positionFrames).clamp(1, 4096);
            continuous.renderInto(buffer, chunk);
          }
          final continuousBlock = Int16List(captureFrames * 2);
          continuous.renderInto(
            Int16List.sublistView(continuousBlock, 0),
            captureFrames,
          );

          // Sought render: fresh source, seek, then read the same range.
          final sought = AgiPcmSource(sound, config: entry.value);
          sought.seekToFrame(captureStart);
          expect(sought.positionFrames, equals(captureStart));
          final soughtBlock = Int16List(captureFrames * 2);
          final written = sought.renderInto(soughtBlock, captureFrames);
          expect(written, equals(captureFrames));
          expect(soughtBlock, equals(continuousBlock));
        });
      }

      test('seek with noise sound preserves LFSR continuity', () {
        final continuous = AgiPcmSource(sound, config: SynthesizerConfig.tandy());
        final buffer = Int16List(4096 * 2);
        const captureStart = 3000;
        while (continuous.positionFrames < captureStart) {
          continuous.renderInto(buffer, (captureStart - continuous.positionFrames).clamp(1, 4096));
        }
        final continuousBlock = Int16List(500 * 2);
        continuous.renderInto(continuousBlock, 500);

        final sought = AgiPcmSource(sound, config: SynthesizerConfig.tandy());
        sought.seekToFrame(captureStart);
        final soughtBlock = Int16List(500 * 2);
        sought.renderInto(soughtBlock, 500);
        expect(soughtBlock, equals(continuousBlock));
      });
    });

    test('totalFrames, isFinished and reset', () {
      final config = SynthesizerConfig.tandy();
      final source = AgiPcmSource(sound, config: config);
      final expected = PcmSynthesizer(config).renderPcm(sound);

      expect(source.sampleRate, equals(44100));
      expect(source.channels, equals(2));
      expect(source.totalFrames, equals(expected.length ~/ 2));
      expect(source.positionFrames, equals(0));
      expect(source.isFinished, isFalse);

      final scratch = Int16List(4096 * 2);
      final firstBlock = Int16List(4096 * 2);
      source.renderInto(firstBlock, 4096);
      expect(source.positionFrames, equals(4096));
      expect(firstBlock, equals(Int16List.sublistView(expected, 0, 4096 * 2)));

      // Render to the end: isFinished becomes true and renderInto
      // returns 0.
      while (!source.isFinished) {
        source.renderInto(scratch, 4096);
      }
      expect(source.positionFrames, equals(source.totalFrames));
      expect(source.renderInto(scratch, 4096), equals(0));

      // Reset reproduces the first block identically.
      source.reset();
      expect(source.positionFrames, equals(0));
      expect(source.isFinished, isFalse);
      final firstBlockAgain = Int16List(4096 * 2);
      source.renderInto(firstBlockAgain, 4096);
      expect(firstBlockAgain, equals(firstBlock));
    });

    test('empty sound', () {
      final empty = AgiSound(voices: []);
      final source = AgiPcmSource(empty);
      expect(source.totalFrames, equals(0));
      expect(source.isFinished, isTrue);
      expect(source.renderInto(Int16List(16), 8), equals(0));
      expect(PcmSynthesizer().renderPcm(empty), isEmpty);

      source.reset();
      expect(source.isFinished, isTrue);
    });

    test('renderInto rejects an undersized destination', () {
      final source = AgiPcmSource(sound, config: SynthesizerConfig.tandy());
      expect(() => source.renderInto(Int16List(10), 100), throwsArgumentError);
      expect(source.positionFrames, equals(0));
    });

    test('short return only at end-of-stream', () {
      final source = AgiPcmSource(parserSound, config: SynthesizerConfig.tandy());
      final total = source.totalFrames!;
      final scratch = Int16List(4096 * 2);
      while (!source.isFinished) {
        final before = source.positionFrames;
        final n = source.renderInto(scratch, 4096);
        expect(
          n,
          equals((4096).clamp(0, total - before)),
          reason: 'short block before end-of-stream at frame $before',
        );
      }
    });
  });
}
