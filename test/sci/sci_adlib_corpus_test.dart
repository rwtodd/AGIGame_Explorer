// Stage 6b: corpus end-to-end test — PQ2 title music through the real
// SCI engine with the AdLib device selected. Mirrors the 'PQ2 title
// BegLoop' timing loop in test/sci/sci_sound_test.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

/// Audio sink that records the peak absolute sample and the number of
/// frames written, overriding storage so the queue stays bounded.
/// [NullAudioSink.playedFrames] only advances in real time via the
/// streaming player's stopwatch term, which is sufficient here.
class CapturingSink extends NullAudioSink {
  int peak = 0;
  int framesWritten = 0;

  @override
  void writePcm(Int16List samples) {
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    framesWritten += samples.length ~/ 2;
  }
}

void main() {
  test('PQ2 title plays through AdLib (OPL2) end-to-end', () async {
    if (skipIfReferenceGameMissing('police-quest-2')) return;
    final pq2Dir = Directory(referenceGamePath('police-quest-2'));
    final sink = CapturingSink();
    final player = AgiSoundPlayer(sink: sink);
    final engine = SciGameEngine(
      volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      soundPlayer: player,
    );
    engine.setSciMusicDevice(SciMusicDevice.adLibOpl2);
    engine.initializeGame();
    engine.start();
    final stateSel = engine.selectors.findSelector('state') ?? -1;
    expect(stateSel, greaterThan(0));

    var sawTitle = false;
    var advanced = false;
    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      engine.tick();
      if (engine.currentPic?.picNumber != 0) continue;
      sawTitle = true;
      final intro = engine.segManager.loadedScripts.values
          .where((s) => s.scriptNumber == 200)
          .expand((s) => s.objects.values)
          .where((o) => o.nameString == 'IntroScript')
          .firstOrNull;
      // The AdLib source must have started (title music reached the
      // player) for this to prove cues work under AdLib.
      if (intro != null &&
          intro.getProp(engine.segManager, stateSel).toSint16() > 1) {
        advanced = true;
        // Keep the engine (and the player refill timer) running a bit
        // past the cue: the track's first audible note lands ~0.3 s in,
        // and the player only writes as much audio as real time has
        // elapsed, so a few more seconds of run time are needed before
        // the capture holds actual FM samples.
        for (var k = 0; k < 40; k++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          engine.tick();
        }
        break;
      }
    }
    final peak = sink.peak;
    final frames = sink.framesWritten;
    debugPrint('PQ2 AdLib e2e: sawTitle=$sawTitle advanced=$advanced '
        'peak=$peak frames=$frames');
    engine.dispose();
    expect(sawTitle, isTrue);
    expect(advanced, isTrue);
    expect(peak, greaterThan(500));
  }, timeout: const Timeout(Duration(seconds: 15)));
}
