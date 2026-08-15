import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:test/test.dart';

void main() {
  group('SoundParser', () {
    // Reference 3-voice polyphonic sound resource from AGI
    final exampleSoundBytes = Uint8List.fromList([
      8, 0, 64, 1, 216, 1, 112, 2, 45, 0, 0, 143, 159, 11, 0, 73, 140, 144,
      11, 0, 0, 143, 159, 8, 0, 77, 128, 144, 4, 0, 0, 143, 159, 7, 0, 73, 140, 144, 4, 0, 0,
      143, 159, 45, 0, 70, 136, 144, 23, 0, 0, 143, 159, 7, 0, 71, 132, 144, 4, 0, 0, 143,
      159, 7, 0, 70, 136, 144, 4, 0, 0, 143, 159, 11, 0, 69, 140, 144, 12, 0, 0, 143, 159, 5,
      0, 70, 136, 144, 6, 0, 0, 143, 159, 7, 0, 71, 132, 144, 4, 0, 0, 143, 159, 150, 0, 70,
      136, 144, 31, 0, 0, 143, 159, 7, 0, 73, 140, 144, 15, 0, 0, 143, 159, 8, 0, 77, 128,
      144, 3, 0, 0, 143, 159, 6, 0, 73, 140, 144, 6, 0, 0, 143, 159, 54, 0, 70, 136, 144, 13,
      0, 0, 143, 159, 8, 0, 73, 140, 144, 4, 0, 0, 143, 159, 5, 0, 70, 136, 144, 6, 0, 0, 143,
      159, 9, 0, 71, 132, 144, 13, 0, 0, 143, 159, 6, 0, 73, 140, 144, 6, 0, 0, 143, 159, 5, 0,
      71, 132, 144, 6, 0, 0, 143, 159, 11, 0, 70, 136, 144, 4, 0, 0, 143, 159, 11, 0, 71, 132,
      144, 4, 0, 0, 143, 159, 11, 0, 73, 140, 144, 4, 0, 0, 143, 159, 11, 0, 71, 132, 144, 4,
      0, 0, 143, 159, 11, 0, 70, 136, 144, 4, 0, 0, 143, 159, 11, 0, 71, 132, 144, 4, 0, 0, 143,
      159, 11, 0, 70, 136, 144, 4, 0, 0, 143, 159, 11, 0, 71, 132, 144, 4, 0, 0, 143, 159, 11, 0,
      73, 140, 144, 4, 0, 0, 143, 159, 11, 0, 71, 132, 144, 12, 0, 70, 136, 144, 11, 0, 0, 143,
      159, 11, 0, 71, 132, 144, 147, 0, 68, 142, 144, 255, 255, 226, 0, 0, 175, 191, 11, 0, 103, 160,
      178, 11, 0, 0, 175, 191, 6, 0, 116, 161, 178, 5, 0, 0, 175, 191, 6, 0, 103, 160, 178, 6, 0, 0, 175,
      191, 45, 0, 90, 160, 178, 22, 0, 0, 175, 191, 6, 0, 103, 160, 178, 6, 0, 0, 175, 191, 5, 0, 90,
      160, 178, 6, 0, 0, 175, 191, 6, 0, 85, 174, 178, 16, 0, 0, 175, 191, 12, 0, 87, 163, 178, 5, 0, 93,
      163, 178, 6, 0, 0, 175, 191, 141, 0, 90, 160, 178, 39, 0, 0, 175, 191, 21, 0, 103, 160, 178, 24,
      0, 0, 175, 191, 21, 0, 116, 161, 178, 25, 0, 0, 175, 191, 20, 0, 103, 160, 178, 25, 0, 0, 175, 191,
      22, 0, 116, 161, 178, 17, 0, 0, 175, 191, 6, 0, 116, 161, 178, 142, 0, 100, 233, 178, 255, 255, 225,
      0, 0, 207, 223, 11, 0, 83, 200, 209, 12, 0, 0, 207, 223, 5, 0, 90, 192, 209, 6, 0, 0, 207, 223, 5,
      0, 83, 200, 209, 6, 0, 0, 207, 223, 45, 0, 77, 192, 209, 23, 0, 0, 207, 223, 5, 0, 83, 200, 209, 6,
      0, 0, 207, 223, 6, 0, 77, 192, 209, 5, 0, 0, 207, 223, 6, 0, 74, 207, 209, 17, 0, 0, 207, 223, 11,
      0, 75, 201, 209, 6, 0, 78, 201, 209, 5, 0, 0, 207, 223, 141, 0, 77, 192, 209, 40, 0, 0, 207, 223,
      20, 0, 83, 200, 209, 25, 0, 0, 207, 223, 20, 0, 90, 192, 209, 25, 0, 0, 207, 223, 21, 0, 83, 200,
      209, 24, 0, 0, 207, 223, 23, 0, 90, 192, 209, 16, 0, 0, 207, 223, 6, 0, 90, 192, 209, 143, 0, 103,
      192, 209, 255, 255, 255, 255,
    ]);

    // Reference sound resource with 1 tone voice + noise channel
    final noisySoundBytes = Uint8List.fromList([
      8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
      149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
      160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
      0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
    ]);

    test('parses 3-voice polyphonic AGI sound correctly', () {
      final s = SoundParser.parse(exampleSoundBytes);

      expect(s.noise, isNull);
      expect(s.voices.length, equals(3));
      expect(s.length, equals(913));
      expect(s.voices[0].length, equals(913));
      expect(s.voices[1].length, equals(909));
      expect(s.voices[2].length, equals(909));

      expect(s.voices[0].notes.length, equals(32));
      expect(s.voices[1].notes.length, equals(16));
      expect(s.voices[2].notes.length, equals(16));

      expect(s.voices[1].notes[7].startTime, equals(383));
      expect(s.voices[1].notes[3].duration, equals(45));

      final maxFreqV1 = s.voices[1].notes.map((n) => n.frequencyCount).reduce((a, b) => a > b ? a : b);
      final minFreqV0 = s.voices[0].notes.map((n) => n.frequencyCount).reduce((a, b) => a < b ? a : b);
      expect(maxFreqV1, equals(833));
      expect(minFreqV0, equals(78));

      // MIDI note calculations
      final firstAudibleNote = s.voices[0].notes[0];
      expect(firstAudibleNote.toMidiNoteNumber(useAgiLegacyFormula: true), equals(78));
      expect(firstAudibleNote.toMidiNoteNumber(useAgiLegacyFormula: false), equals(77));
      expect(firstAudibleNote.toMidiVelocity(), equals(100)); // att = 0 -> 100 - 0 = 100
    });

    test('parses sound with noise channel correctly', () {
      final s = SoundParser.parse(noisySoundBytes);

      expect(s.noise, isNotNull);
      expect(s.voices.length, equals(1));
      expect(s.length, equals(15));

      expect(s.voices[0].length, equals(15));
      expect(s.voices[0].notes.length, equals(5));

      final minFreq = s.voices[0].notes.map((n) => n.frequencyCount).reduce((a, b) => a < b ? a : b);
      expect(minFreq, equals(832));

      expect(s.noise!.length, equals(15));
      expect(s.noise!.noises.length, equals(3));
      expect(s.noise!.noises[0].duration, equals(3));
      expect(s.noise!.noises[0].type, equals(NoiseType.white));
      expect(s.noise!.noises[1].type, equals(NoiseType.white));
      expect(s.noise!.noises[2].type, equals(NoiseType.white));
    });

    test('throws CorruptResourceException when header is truncated', () {
      expect(
        () => SoundParser.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<CorruptResourceException>()),
      );
    });

    test('throws CorruptResourceException when voice length is invalid', () {
      // 8 bytes header pointing to length with bad alignment
      final badData = Uint8List.fromList([
        8, 0, 11, 0, 11, 0, 11, 0,
        1, 2, 3, // len = 3, not divisible by 5 and not ending in 0xFFFF
      ]);
      expect(
        () => SoundParser.parse(badData),
        throwsA(isA<CorruptResourceException>()),
      );
    });
  });
}
