import 'dart:typed_data';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/audio/wav_encoder.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:test/test.dart';

void main() {
  group('PcmSynthesizer & WavEncoder', () {
    final exampleSoundBytes = Uint8List.fromList([
      8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
      149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
      160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
      0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
    ]);

    late AgiSound sound;

    setUp(() {
      sound = SoundParser.parse(exampleSoundBytes);
    });

    test('renders Tandy 3-voice + Noise PCM successfully', () {
      final synth = PcmSynthesizer(SynthesizerConfig.tandy());
      final samples = synth.renderPcm(sound);

      expect(samples.isNotEmpty, isTrue);
      // Verify interleaved stereo
      expect(samples.length % 2, equals(0));

      // Verify that samples are not all zeroes
      final hasAudibleSignal = samples.any((s) => s.abs() > 100);
      expect(hasAudibleSignal, isTrue);
    });

    test('renders IBM PC single channel mode', () {
      final synth = PcmSynthesizer(SynthesizerConfig.ibmPc());
      final samples = synth.renderPcm(sound);

      expect(samples.isNotEmpty, isTrue);
      final hasAudibleSignal = samples.any((s) => s.abs() > 100);
      expect(hasAudibleSignal, isTrue);
    });

    test('renders Enhanced mode with all waveforms and reverb', () {
      for (final wave in WaveformType.values) {
        final synth = PcmSynthesizer(SynthesizerConfig.enhanced(
          waveform: wave,
          reverbMix: 0.3,
        ));
        final samples = synth.renderPcm(sound);

        expect(samples.isNotEmpty, isTrue);
        final hasAudibleSignal = samples.any((s) => s.abs() > 100);
        expect(hasAudibleSignal, isTrue);
      }
    });

    test('renders valid WAV container file', () {
      final synth = PcmSynthesizer(SynthesizerConfig.tandy(sampleRate: 44100));
      final wavBytes = synth.renderWav(sound);

      expect(wavBytes.length, greaterThan(44));

      // RIFF header
      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wavBytes.sublist(12, 16)), equals('fmt '));

      final byteData = ByteData.sublistView(wavBytes);
      final audioFormat = byteData.getUint16(20, Endian.little);
      final numChannels = byteData.getUint16(22, Endian.little);
      final sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);

      expect(audioFormat, equals(1)); // PCM
      expect(numChannels, equals(2)); // Stereo
      expect(sampleRate, equals(44100));
      expect(bitsPerSample, equals(16));

      expect(String.fromCharCodes(wavBytes.sublist(36, 40)), equals('data'));
      final dataSize = byteData.getUint32(40, Endian.little);
      expect(dataSize, equals(wavBytes.length - 44));
    });

    test('WavEncoder encodes mono audio properly', () {
      final monoSamples = Int16List.fromList([1000, -1000, 2000, -2000]);
      final wav = WavEncoder.encode(samples: monoSamples, sampleRate: 22050, numChannels: 1);

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint16(22, Endian.little), equals(1));
      expect(byteData.getUint32(24, Endian.little), equals(22050));
      expect(byteData.getUint32(40, Endian.little), equals(8));
    });

    test('handles empty sound gracefully', () {
      final emptySound = AgiSound(voices: []);
      final synth = PcmSynthesizer();
      final samples = synth.renderPcm(emptySound);
      expect(samples.isEmpty, isTrue);
    });
  });
}
