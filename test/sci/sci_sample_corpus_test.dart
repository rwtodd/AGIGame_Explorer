// Stage 8: corpus sample tests (gated: SKIPPED without reference_games).
//
// SQ3 sound 100 ("Where am I?") is sample-only: 11000 Hz, 7415 PCM
// bytes, 0 notes. QFG2 (SCI1) sound 754 is sample-only as well.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/sci_digital_sample_source.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

void main() {
  group('corpus digital samples', () {
    test('SQ3 sound 100 parses sample-only and renders non-silent stereo',
        () {
      if (skipIfReferenceGameMissing('space-quest-3')) return;
      final vol = SciVolumeManager.fromDirectory(referenceGamePath('space-quest-3'));
      try {
        final bytes = vol.getResource(SciResourceType.sound, 100);
        final isSci1 = vol.usesPostSci01Compression;
        final parsed = Sci0SoundParser.parseSound(
          bytes,
          headerSize: isSci1
              ? null
              : (vol.isEarlySci0
                  ? Sci0SoundParser.headerEarly
                  : Sci0SoundParser.headerLate),
          soundFormat: isSci1
              ? SciMidiSoundFormat.sci1MultiTrack
              : SciMidiSoundFormat.sci0,
        );
        final track = parsed.track!;
        expect(track.sample, isNotNull);
        expect(track.hasAudibleNotes, isFalse);
        expect(track.sample!.sampleRate, 11000);
        expect(track.sample!.pcmBytes.length, 7415);
        expect(track.sample!.isPlayable, isTrue);

        final source = SciDigitalSamplePcmSource(
          track.sample!,
          outputSampleRate: 44100,
        );
        // 7415 bytes at 11000 Hz -> round(7415*44100/11000) = 29727 frames.
        expect(source.totalFrames, 29727);
        final total = source.totalFrames!;
        final buf = Int16List(total * 2);
        final written = source.renderInto(buf, total);
        expect(written, total);
        var peak = 0;
        var silentFrames = 0;
        for (var i = 0; i < total; i++) {
          final l = buf[i * 2].abs();
          final r = buf[i * 2 + 1].abs();
          if (l > peak) peak = l;
          if (r > peak) peak = r;
          if (l == 0 && r == 0) silentFrames++;
        }
        expect(peak, greaterThan(1000));
        // Speech is mostly non-silent; allow generous silent padding.
        expect(silentFrames, lessThan(total ~/ 2));
      } finally {
        vol.close();
      }
    });

    test('QFG2 sound 754 parses sample-only and renders non-silent', () {
      if (skipIfReferenceGameMissing('quest-for-glory-2')) return;
      final vol = SciVolumeManager.fromDirectory(referenceGamePath('quest-for-glory-2'));
      try {
        final bytes = vol.getResource(SciResourceType.sound, 754);
        final isSci1 = vol.usesPostSci01Compression;
        final parsed = Sci0SoundParser.parseSound(
          bytes,
          headerSize: isSci1
              ? null
              : (vol.isEarlySci0
                  ? Sci0SoundParser.headerEarly
                  : Sci0SoundParser.headerLate),
          soundFormat: isSci1
              ? SciMidiSoundFormat.sci1MultiTrack
              : SciMidiSoundFormat.sci0,
        );
        final track = parsed.track!;
        expect(track.sample, isNotNull);
        expect(track.sample!.isPlayable, isTrue);
        final source = SciDigitalSamplePcmSource(
          track.sample!,
          outputSampleRate: 44100,
        );
        expect(source.totalFrames, greaterThan(0));
        final total = source.totalFrames!;
        final buf = Int16List(total * 2);
        expect(source.renderInto(buf, total), total);
        var peak = 0;
        for (final s in buf) {
          if (s.abs() > peak) peak = s.abs();
        }
        expect(peak, greaterThan(1000));
      } finally {
        vol.close();
      }
    });
  });
}
