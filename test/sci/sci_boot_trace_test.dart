import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  test('Trace PQ2 boot through SciGameEngine', () {
    final pq2Dir = Directory('reference_games/police-quest-2');
    if (!pq2Dir.existsSync()) {
      markTestSkipped('PQ2 reference tree missing');
      return;
    }

    final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
    final engine = SciGameEngine(volumeManager: volumeMgr);

    engine.initializeGame();

    final logs = <String>[];
    engine.vm.addObserver(
      SciVmBaseObserver(
        onKernel: (id, name, argc, argv, res) {
          logs.add('Kernel: $name(argc=$argc, argv=$argv)');
        },
      ),
    );

    engine.start();

    // Run 10 ticks
    for (int i = 0; i < 10; i++) {
      engine.tick();
    }

    expect(engine.currentPic?.picNumber, isNotNull);
    expect(engine.actors, isNotEmpty);
    expect(engine.isInputEnabled, isFalse);
  });
}
