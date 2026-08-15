import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/sound.dart';

/// Parser for Sierra AGI SND (Sound) resources.
class SoundParser {
  const SoundParser._();

  /// Parses raw byte data of an AGI sound resource into an [AgiSound] structure.
  static AgiSound parse(Uint8List data) {
    if (data.length < 8) {
      throw const CorruptResourceException('Sound resource too short for header.');
    }

    try {
      final voices = <ToneChannel>[];

      for (var which = 1; which <= 3; ++which) {
        final ch = _streamVoice(data, which);
        if (ch != null) {
          voices.add(ch);
        }
      }

      final nc = _streamNoise(data);

      return AgiSound(
        voices: voices,
        noise: nc,
      );
    } catch (e, stackTrace) {
      if (e is AgiException) rethrow;
      throw CorruptResourceException('Error while parsing sound resource: $e', stackTrace);
    }
  }

  static void _checkVoiceLength(Uint8List data, int offset, int len) {
    if (len < 0 || offset + len > data.length) {
      throw CorruptResourceException('Sound channel offset out of bounds (offset: $offset, len: $len, total: ${data.length})');
    }
    final remainder = len % 5;
    if (remainder == 0 ||
        (remainder == 2 &&
            len >= 2 &&
            data[offset + len - 1] == 0xFF &&
            data[offset + len - 2] == 0xFF)) {
      return;
    }
    throw CorruptResourceException('Sound has irregular voice length: $len at offset $offset');
  }

  static ToneChannel? _streamVoice(Uint8List data, int num) {
    var curTime = 0;
    List<AgiNote>? noteList;

    final base = (num - 1) * 2;
    var idx = data[base] | (data[base + 1] << 8);
    final end = data[base + 2] | (data[base + 3] << 8);

    if (idx > end || end > data.length) {
      throw CorruptResourceException('Invalid voice $num offsets: start=$idx, end=$end');
    }

    _checkVoiceLength(data, idx, end - idx);

    while ((idx + 4) < end) {
      final duration = data[idx] | (data[idx + 1] << 8);
      if (duration == 0xFFFF) {
        // End-of-track marker
        break;
      }

      final startTime = curTime;
      final attenuation = data[idx + 4] & 0x0F;
      curTime += duration;

      if (attenuation < 15) {
        final freq = ((data[idx + 2] & 0x3F) << 4) | (data[idx + 3] & 0x0F);
        noteList ??= <AgiNote>[];
        noteList.add(AgiNote(
          startTime: startTime,
          duration: duration,
          frequencyCount: freq,
          attenuation: attenuation,
        ));
      }

      idx += 5;
    }

    return (noteList != null && noteList.isNotEmpty) ? ToneChannel(notes: noteList) : null;
  }

  static NoiseChannel? _streamNoise(Uint8List data) {
    var curTime = 0;
    var idx = data[6] | (data[7] << 8);
    final end = data.length;

    if (idx > end) {
      throw CorruptResourceException('Invalid noise offset: start=$idx, total=${data.length}');
    }

    _checkVoiceLength(data, idx, end - idx);
    List<AgiNoise>? noiseList;

    while ((idx + 4) < end) {
      final duration = data[idx] | (data[idx + 1] << 8);
      if (duration == 0xFFFF) {
        // End-of-track marker
        break;
      }

      final type = ((data[idx + 3] & 0x04) == 0)
          ? NoiseType.periodic
          : NoiseType.white;

      final startTime = curTime;
      final attenuation = data[idx + 4] & 0x0F;
      curTime += duration;

      if (attenuation < 15) {
        final freq = switch (data[idx + 3] & 0x03) {
          0 => 0x10,
          1 => 0x20,
          2 => 0x40,
          _ => 0x00,
        };

        noiseList ??= <AgiNoise>[];
        noiseList.add(AgiNoise(
          startTime: startTime,
          duration: duration,
          frequencyCount: freq,
          attenuation: attenuation,
          type: type,
        ));
      }

      idx += 5;
    }

    return (noiseList != null && noiseList.isNotEmpty) ? NoiseChannel(noises: noiseList) : null;
  }
}
