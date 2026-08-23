import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/audio_output_sink.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group('Muted Sound Timing & Completion Flags', () {
    late AgiSoundPlayer player;
    late NullAudioSink sink;

    setUp(() {
      sink = NullAudioSink();
      player = AgiSoundPlayer(sink: sink);
    });

    tearDown(() {
      player.dispose();
    });

    test('AgiSoundPlayer drives position timer and triggers onFinished when muted', () async {
      // 12 ticks sound at 60 Hz = 0.2 seconds
      final sound = AgiSound(
        voices: [
          ToneChannel(notes: const [
            AgiNote(startTime: 0, frequencyCount: 440, attenuation: 0, duration: 12),
          ]),
        ],
      );

      var finishedCalled = false;
      player.onFinished = () {
        finishedCalled = true;
      };

      await player.play(sound, muted: true);
      expect(player.isPlaying, isTrue);
      expect(player.isMuted, isTrue);
      expect(finishedCalled, isFalse);

      // Wait 300 ms for duration + tail to finish
      await Future.delayed(const Duration(milliseconds: 300));

      expect(finishedCalled, isTrue);
      expect(player.isStopped, isTrue);
    });

    test('AgiGameEngine onSound with sound off does not set completion flag immediately', () async {
      const gamePath = '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
      final loader = await AgiResourceLoader.fromDirectory(gamePath);
      final engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
      await engine.initializeGame();

      // Explicitly turn sound OFF
      engine.setSoundMode(AgiSoundMode.off);
      expect(engine.isSoundOn, isFalse);
      expect(engine.memory.getFlag(9), isFalse);

      // Trigger Sound 1 with completion flag 229 (as in Room 96)
      engine.onSound(1, 229);

      // Flag 229 MUST be false initially while sound is driving
      expect(engine.memory.getFlag(229), isFalse);

      engine.dispose();
    });

    test('Room 96 presentation logo remains active when sound is off', () async {
      const gamePath = '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';
      final loader = await AgiResourceLoader.fromDirectory(gamePath);
      final engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
      await engine.initializeGame();

      engine.setSoundMode(AgiSoundMode.off);
      engine.changeRoom(96);
      await engine.tick();

      // After first tick in Room 96 with sound off, engine should still be in Room 96
      expect(engine.currentRoom, 96);
      expect(engine.memory.getFlag(229), isFalse);

      // Run several more ticks; Room 96 should continue animating stars
      for (int i = 0; i < 10; i++) {
        await engine.tick();
        expect(engine.currentRoom, 96);
      }

      engine.dispose();
    });
  });
}
