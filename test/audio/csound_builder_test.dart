import 'dart:typed_data';
import 'package:flutter_agigame/audio/csound_builder.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:test/test.dart';

void main() {
  group('CSoundBuilder', () {
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

    final noisySoundBytes = Uint8List.fromList([
      8, 0, 40, 0, 47, 0, 54, 0, 3, 0, 60, 128, 154, 3, 0, 58, 128, 152, 3, 0, 56, 128,
      149, 3, 0, 54, 128, 150, 3, 0, 52, 128, 150, 3, 0, 63, 128, 159, 255, 255, 18, 0, 63,
      160, 191, 255, 255, 18, 0, 63, 192, 223, 255, 255, 3, 0, 0, 230, 248, 6, 0, 0, 229, 244, 6, 0,
      0, 228, 240, 3, 0, 0, 230, 255, 255, 255,
    ]);

    test('generates expected CSound score (.sco) for 3-voice sound', () {
      final sound = SoundParser.parse(exampleSoundBytes);
      final sco = CSoundBuilder.buildScore(sound: sound, soundNumber: 10);

      expect(sco.contains(';; AGI Sound Resource 10'), isTrue);
      expect(sco.contains('t 0 3600'), isTrue);
      expect(sco.contains(';; Start of voice 1 (instrument 11)'), isTrue);
      expect(sco.contains(';; Start of voice 2 (instrument 12)'), isTrue);
      expect(sco.contains(';; Start of voice 3 (instrument 13)'), isTrue);
      expect(sco.contains(';; No noise channel in this sound.'), isTrue);
      expect(sco.contains('i99\t0\t973\t0.9\t1.0\t1.0'), isTrue); // 913 + 60 = 973
    });

    test('generates expected CSound score (.sco) for noise sound', () {
      final sound = SoundParser.parse(noisySoundBytes);
      final sco = CSoundBuilder.buildScore(sound: sound, soundNumber: 5);

      expect(sco.contains(';; AGI Sound Resource 5'), isTrue);
      expect(sco.contains(';; Start of voice 1 (instrument 11)'), isTrue);
      expect(sco.contains(';; Start of noise channel (instrument 21 and 31)'), isTrue);
      expect(sco.contains('i21\t'), isTrue); // White noise instrument 21
    });

    test('embedded orchestras are non-empty and well-formed', () {
      expect(CSoundBuilder.tandyOrchestra.contains('sr = 48000'), isTrue);
      expect(CSoundBuilder.tandyOrchestra.contains('instr 21'), isTrue);
      expect(CSoundBuilder.pwmOrchestra.contains('sr = 48000'), isTrue);
      expect(CSoundBuilder.pwmOrchestra.contains(RegExp(r'instr\s+11')), isTrue);
    });
  });
}
