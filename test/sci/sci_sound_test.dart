import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

Uint8List createSyntheticSci0Sound({
  int digitalChannels = 0x10,
  List<int>? midiEvents,
}) {
  final header = Uint8List(33);
  header[0] = 0x21; // Late SCI0 header
  header[1] = 1; // 1 track
  header[2] = digitalChannels & 0xFF;
  header[3] = (digitalChannels >> 8) & 0xFF;

  final events = midiEvents ?? [
    0x00, 0x90, 60, 100, // Delta 0, Note On C4 (60), vel 100 on ch 0
    0x0A, 0x80, 60, 0, // Delta 10, Note Off C4
    0x00, 0xCF, 42, // Delta 0, Program Change ch 15 (cue 42)
    0x0A, 0xFC, // Delta 10, End of track
  ];

  final bb = BytesBuilder();
  bb.add(header);
  bb.add(events);
  return bb.toBytes();
}

void main() {
  group('SCI0 sound cues and Wait', () {
    test('parses channel-15 program changes and end-of-track', () {
      final data = Uint8List(Sci0SoundParser.headerLate + 6);
      data[Sci0SoundParser.headerLate] = 0; // delta
      data[Sci0SoundParser.headerLate + 1] = 0xCF; // program change, ch 15
      data[Sci0SoundParser.headerLate + 2] = 5; // signal
      data[Sci0SoundParser.headerLate + 3] = 10; // delta
      data[Sci0SoundParser.headerLate + 4] = 0xFC; // end

      final cues = Sci0SoundParser.parse(data);
      expect(cues, hasLength(2));
      expect(cues[0].tick, 0);
      expect(cues[0].signal, 5);
      expect(cues[1].tick, 10);
      expect(cues[1].signal, sciSoundFinished);
    });

    test('skips kSetSignalLoop (127) and still terminates', () {
      final data = Uint8List(Sci0SoundParser.headerLate + 6);
      data[Sci0SoundParser.headerLate] = 4;
      data[Sci0SoundParser.headerLate + 1] = 0xCF;
      data[Sci0SoundParser.headerLate + 2] = 0x7F;
      data[Sci0SoundParser.headerLate + 3] = 0;
      data[Sci0SoundParser.headerLate + 4] = 0xFC;

      final cues = Sci0SoundParser.parse(data);
      expect(cues.where((c) => c.signal == 0x7F), isEmpty);
      expect(cues.last.signal, sciSoundFinished);
    });

    test('Wait returns elapsed 60 Hz ticks', () async {
      final kernel = SciKernel();
      final vm = SciVM(
        segManager: SciSegManager(),
        kernel: kernel,
        selectors: SciSelectors(),
      );
      kernel.call(vm, 0x45, 1, [const SciReg.fromInt(0)]);
      expect(kernel.lastWaitTicks, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final delta = kernel.call(vm, 0x45, 1, [const SciReg.fromInt(6)]);
      expect(kernel.lastWaitTicks, 6);
      expect(delta.toUint16(), greaterThanOrEqualTo(2));
    });

    test('PQ2 SOUND 1 has an end-of-track cue', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final vol = SciVolumeManager.fromDirectory(pq2Dir.path);
      final data = vol.getResource(SciResourceType.sound, 1);
      final cues = Sci0SoundParser.parse(data);
      expect(cues, isNotEmpty);
      expect(cues.last.signal, sciSoundFinished);
      expect(cues.last.tick, greaterThan(0));
    });
  });

  group('Sci0SoundParser translation & playback modes', () {
    test('parses notes, dividers, and cues for Tandy mode', () {
      final data = createSyntheticSci0Sound(digitalChannels: 0x10);
      final parsed = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(parsed, isNotNull);
      expect(parsed.sound.voices, isNotEmpty);
      expect(parsed.sound.voices[0].notes, isNotEmpty);
      final note = parsed.sound.voices[0].notes.first;
      expect(note.startTime, 0);
      expect(note.duration, 10);
      // MIDI 60 (261.63 Hz) -> divider 111860.78125 / 261.63 ~ 427
      expect(note.frequencyCount, closeTo(427, 2));
      expect(parsed.cues, hasLength(2));
      expect(parsed.cues[0].signal, 42);
      expect(parsed.cues[0].tick, 10);
      expect(parsed.cues[1].signal, sciSoundFinished);
      expect(parsed.cues[1].tick, 20);
    });

    test('parses single channel for IBM PC Speaker mode', () {
      final data = createSyntheticSci0Sound(digitalChannels: 0x20);
      final parsed = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.ibmPcSingleChannel);
      expect(parsed, isNotNull);
      expect(parsed.sound.voices.length, 1);
      expect(parsed.sound.voices[0].notes, isNotEmpty);
      expect(parsed.sound.voices[0].notes.first.duration, 10);
    });

    test('parses polyphonic tracks for Enhanced mode', () {
      final data = createSyntheticSci0Sound(digitalChannels: 0x10);
      final parsed = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.enhanced);
      expect(parsed, isNotNull);
      expect(parsed.sound.voices, isNotEmpty);
    });

    test('detects loop marker kSetSignalLoop (127)', () {
      final data = createSyntheticSci0Sound(
        digitalChannels: 0x10,
        midiEvents: [
          0x00, 0x90, 60, 100,
          0x05, 0xCF, 127, // Loop marker at tick 5
          0x05, 0x80, 60, 0,
          0x0A, 0xFC,
        ],
      );
      final parsed = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(parsed, isNotNull);
      expect(parsed.loopTick, 5);
      // Cue 127 should not be added as a game signal
      expect(parsed.cues.where((c) => c.signal == 127), isEmpty);
    });

    test('parses Police Quest 2 SOUND resources across all modes', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final vol = SciVolumeManager.fromDirectory(pq2Dir.path);
      final data = vol.getResource(SciResourceType.sound, 1);

      final tandy = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.tandy3VoiceNoise);
      expect(tandy, isNotNull);
      expect(tandy.sound.voices.expand((v) => v.notes).length, greaterThan(0));
      expect(tandy.cues, isNotEmpty);

      final pc = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.ibmPcSingleChannel);
      expect(pc, isNotNull);
      expect(pc.sound.voices.length, 1);
      expect(pc.sound.voices.expand((v) => v.notes).length, greaterThan(0));

      final enhanced = Sci0SoundParser.parseSound(data, mode: PcmPlaybackMode.enhanced);
      expect(enhanced, isNotNull);
      expect(enhanced.sound.voices.expand((v) => v.notes).length, greaterThan(0));
    });
  });

  group('SciKernel DoSound & Sound Cues', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciSelectors selectors;
    late SciVM vm;
    late AgiSoundPlayer player;
    late SciObject soundObj;
    late int stateSel;
    late int sigSel;
    late int handleSel;

    setUp(() {
      segMan = SciSegManager();
      kernel = SciKernel();
      selectors = SciSelectors();
      kernel.selectors = selectors;
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
      player = AgiSoundPlayer();
      kernel.soundPlayer = player;

      selectors.registerSelector('number', 100);
      selectors.registerSelector('loop', 101);
      selectors.registerSelector('priority', 102);
      selectors.registerSelector('state', 103);
      selectors.registerSelector('signal', 104);
      selectors.registerSelector('handle', 105);
      selectors.registerSelector('nodePtr', 106);

      stateSel = 103;
      sigSel = 104;
      handleSel = 105;

      final template = SciObject(
        pos: SciReg.nullReg,
        variables: [
          const SciReg.fromInt(1), // number = 1
          const SciReg.fromInt(1), // loop = 1
          const SciReg.fromInt(0), // priority = 0
          const SciReg.fromInt(0), // state = 0
          const SciReg.fromInt(0), // signal = 0
          SciReg.nullReg, // handle
          SciReg.nullReg, // nodePtr
        ],
        baseVars: [100, 101, 102, 103, 104, 105, 106],
      );
      soundObj = segMan.cloneObject(template);
    });

    tearDown(() {
      player.dispose();
      kernel.dispose();
    });

    test('DoSound subops: init, play, pause, masterVolume, polyphony, stop, dispose', () {
      // 1. _sndInit (subop 0)
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(0), soundObj.pos]);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.initialized);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), 0);

      // 2. _sndPolyphony (subop 11)
      final polyTandy = kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]);
      expect(polyTandy.toUint16(), 3);
      kernel.soundMode = PcmPlaybackMode.ibmPcSingleChannel;
      final polyPc = kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]);
      expect(polyPc.toUint16(), 1);
      kernel.soundMode = PcmPlaybackMode.enhanced;
      final polyEnh = kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]);
      expect(polyEnh.toUint16(), 16);
      kernel.soundMode = PcmPlaybackMode.tandy3VoiceNoise;

      // 3. _sndMasterVolume (subop 8)
      final prevVol = kernel.call(vm, 0x31, 2, [const SciReg.fromInt(8), const SciReg.fromInt(10)]);
      expect(prevVol.toUint16(), 15);
      expect(player.volume, closeTo(10.0 / 15.0, 0.01));

      // 4. _sndPlay (subop 1)
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(1), soundObj.pos]);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.playing);
      expect(soundObj.getProp(segMan, handleSel), soundObj.pos);

      // 5. _sndPause (subop 6)
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(6), const SciReg.fromInt(1)]);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.paused);
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(6), const SciReg.fromInt(0)]);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.playing);

      // 6. _sndStop (subop 5)
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.stopped);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), sciSoundFinished);

      // 7. _sndDispose (subop 3)
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(3), soundObj.pos]);
      expect(kernel.soundSlots.containsKey(soundObj.pos), isFalse);
    });

    test('updateSci0Cues queues signals and completes sound with 0xFFFF', () {
      final parsed = Sci0SoundParser.parseSound(
        createSyntheticSci0Sound(),
        mode: PcmPlaybackMode.tandy3VoiceNoise,
      );
      expect(parsed, isNotNull);

      final slot = SciSoundSlot(
        obj: soundObj.pos,
        resourceId: 1,
        status: SciSoundStatus.playing,
        loop: 1,
        priority: 0,
        parsedSound: parsed,
        cues: parsed.cues,
      );
      kernel.soundSlots[soundObj.pos] = slot;
      soundObj.setProp(segMan, stateSel, const SciReg.fromInt(SciSoundStatus.playing));

      // Clock at 0: no cue fired yet
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), 0);

      // Clock advances to tick 12: cue 42 fires
      kernel.advanceSciClock(hostHz: 20); // 3 ticks
      kernel.advanceSciClock(hostHz: 20); // 6 ticks
      kernel.advanceSciClock(hostHz: 20); // 9 ticks
      kernel.advanceSciClock(hostHz: 20); // 12 ticks
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), 42);

      // Reset signal to 0 (game script acknowledged it)
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));

      // Clock advances past tick 20: end cue fires
      for (var i = 0; i < 4; i++) {
        kernel.advanceSciClock(hostHz: 20);
      }
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), sciSoundFinished);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.stopped);
    });

    test('looping sound resets cues and continues playing', () {
      final parsed = Sci0SoundParser.parseSound(
        createSyntheticSci0Sound(),
        mode: PcmPlaybackMode.tandy3VoiceNoise,
      );
      final slot = SciSoundSlot(
        obj: soundObj.pos,
        resourceId: 1,
        status: SciSoundStatus.playing,
        loop: -1, // Infinite loop
        priority: 0,
        parsedSound: parsed,
        cues: parsed.cues,
      );
      kernel.soundSlots[soundObj.pos] = slot;

      // Fast forward past all cues
      for (var i = 0; i < 10; i++) {
        kernel.advanceSciClock(hostHz: 20);
      }
      // Drain cues
      kernel.updateSci0Cues(vm); // cue 42
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));
      kernel.updateSci0Cues(vm); // end cue

      // Sound should still be playing and cues reset
      expect(slot.status, SciSoundStatus.playing);
      expect(slot.nextCue, 0);
    });
  });

  group('SciGameEngine sound integration', () {
    test('soundMode and synthesizerConfig updates work and pause/resume correctly', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference tree missing');
        return;
      }
      final engine = SciGameEngine(
        volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
      );

      // Defaults
      expect(engine.soundMode, AgiSoundMode.pcJr);
      expect(engine.isSoundOn, isTrue);

      // Switch to IBM PC Speaker
      engine.setSoundMode(AgiSoundMode.ibmPc);
      expect(engine.soundMode, AgiSoundMode.ibmPc);
      expect(engine.kernel.soundMode, PcmPlaybackMode.ibmPcSingleChannel);

      // Switch to Enhanced
      engine.setSoundMode(AgiSoundMode.enhanced);
      expect(engine.soundMode, AgiSoundMode.enhanced);
      expect(engine.kernel.soundMode, PcmPlaybackMode.enhanced);

      // Switch to Off (mute)
      engine.setSoundMode(AgiSoundMode.off);
      expect(engine.soundMode, AgiSoundMode.off);
      expect(engine.soundPlayer.isMuted, isTrue);

      // Synthesizer config
      const config = SynthesizerConfig(
        mode: PcmPlaybackMode.tandy3VoiceNoise,
        waveform: WaveformType.sine,
        enableReverb: true,
        reverbMix: 0.35,
      );
      engine.setSynthesizerConfig(config);
      expect(engine.kernel.synthesizerConfig.enableReverb, isTrue);
      expect(engine.kernel.synthesizerConfig.reverbMix, 0.35);

      // Pause & Resume
      engine.pause();
      expect(engine.isPaused, isTrue);
      engine.resume();
      expect(engine.isPaused, isFalse);

      engine.dispose();
    });
  });

  test('Wait(0) pumps multiple Animate calls in one engine tick', () {
    final pq2Dir = Directory('reference_games/police-quest-2');
    if (!pq2Dir.existsSync()) {
      markTestSkipped('PQ2 reference tree missing');
      return;
    }
    final engine = SciGameEngine(
      volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
    );
    engine.initializeGame();
    engine.start();

    var animates = 0;
    engine.vm.addObserver(
      SciVmBaseObserver(
        onKernel: (id, name, argc, argv, res) {
          if (name == 'Animate') animates++;
        },
      ),
    );
    engine.tick();
    expect(engine.kernel.lastWaitTicks, 0);
    expect(animates, greaterThan(1));

    // Wait(0) still extra-pumps at AT throughput (3/tick at 20 Hz). Event
    // new/dispose must stay balanced instead of leaking clones.
    final clonesBefore = engine.segManager.clones.length;
    engine.segManager.globals[11] = const SciReg.fromInt(200);
    engine.tick();
    expect(engine.segManager.clones.length, lessThan(clonesBefore + 16));
    engine.dispose();
  });

  test('PQ2 title BegLoop cues IntroScript past state 1', () async {
    final pq2Dir = Directory('reference_games/police-quest-2');
    if (!pq2Dir.existsSync()) {
      markTestSkipped('PQ2 reference tree missing');
      return;
    }
    final engine = SciGameEngine(
      volumeManager: SciVolumeManager.fromDirectory(pq2Dir.path),
    );
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
      if (intro != null &&
          intro.getProp(engine.segManager, stateSel).toSint16() > 1) {
        advanced = true;
        break;
      }
    }
    engine.dispose();
    expect(sawTitle, isTrue);
    expect(advanced, isTrue);
  }, timeout: const Timeout(Duration(seconds: 15)));
}
