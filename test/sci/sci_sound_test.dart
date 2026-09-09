import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

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

    // After leaving room 99, Wait(0) must not extra-pump (PQ2 intro stays at
    // speed 0). Event new/dispose stay balanced instead of leaking clones.
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
