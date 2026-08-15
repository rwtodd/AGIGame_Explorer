import 'dart:typed_data';
import 'package:flutter_agigame/audio/midi_builder.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:test/test.dart';

void main() {
  group('MidiBuilder', () {
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

    late AgiSound sound;

    setUp(() {
      sound = SoundParser.parse(exampleSoundBytes);
    });

    test('generates valid Standard MIDI File (SMF Format 1)', () {
      final midiBytes = MidiBuilder.buildMidi(
        sound: sound,
        soundNumber: 1,
        programNumber: 0,
      );

      expect(midiBytes.length, greaterThan(14));

      // Header chunk
      expect(String.fromCharCodes(midiBytes.sublist(0, 4)), equals('MThd'));

      final byteData = ByteData.sublistView(midiBytes);
      final headerSize = byteData.getUint32(4, Endian.big);
      final format = byteData.getUint16(8, Endian.big);
      final numTracks = byteData.getUint16(10, Endian.big);
      final division = byteData.getUint16(12, Endian.big);

      expect(headerSize, equals(6));
      expect(format, equals(1));
      expect(numTracks, equals(4)); // 1 Tempo track + 3 voice tracks
      expect(division, equals(60));  // 60 ticks per quarter note

      // Search for Track header markers "MTrk"
      var mtrkCount = 0;
      for (var i = 0; i <= midiBytes.length - 4; i++) {
        if (midiBytes[i] == 0x4D &&
            midiBytes[i + 1] == 0x54 &&
            midiBytes[i + 2] == 0x72 &&
            midiBytes[i + 3] == 0x6B) {
          mtrkCount++;
        }
      }
      expect(mtrkCount, equals(4));
    });

    test('throws AgiException when trying to build MIDI for sound with no voices', () {
      final noiseOnlySound = AgiSound(
        voices: [],
        noise: NoiseChannel(noises: [
          AgiNoise(
            startTime: 0,
            duration: 10,
            frequencyCount: 0x10,
            attenuation: 0,
            type: NoiseType.white,
          ),
        ]),
      );

      expect(
        () => MidiBuilder.buildMidi(sound: noiseOnlySound),
        throwsA(isA<AgiException>()),
      );
    });
  });
}
