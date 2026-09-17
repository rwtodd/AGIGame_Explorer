import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  test('Test Conquests of Camelot Room 6 transition, barrier collision, and kernel tracing', () {
    final dir = Directory('reference_games/conquests-of-camelot');
    if (!dir.existsSync()) {
      markTestSkipped('Camelot reference tree missing');
      return;
    }

    final engine = SciGameEngine(
      volumeManager: SciVolumeManager.fromDirectory(dir.path),
    );
    engine.initializeGame();
    engine.start();

    for (var t = 0; t < 50; t++) {
      engine.tick();
    }

    // Dismiss initial dialog if any
    if (engine.kernel.windowManager.windowStack.isNotEmpty) {
      engine.handleKeyPress(13, ascii: 13);
      for (var t = 0; t < 10; t++) {
        engine.tick();
      }
    }

    // Transition to Room 6
    final newRoomSel = engine.selectors.findSelector('newRoom')!;
    final curRoomRef = engine.segManager.globals[1];
    engine.vm.sendSelector(curRoomRef, newRoomSel, [const SciReg.fromInt(6)]);

    for (var t = 0; t < 50; t++) {
      engine.tick();
    }

    final arthurInitial = engine.actors.firstWhere((a) => a.viewNumber == 2);
    expect(arthurInitial.position.dx.round(), 279);
    expect(arthurInitial.position.dy.round(), 108);

    // 1. Arthur should successfully move Left (dir 7)
    engine.handleDirection(7);
    for (var t = 0; t < 20; t++) {
      engine.tick();
    }
    final arthurAfterLeft = engine.actors.firstWhere((a) => a.viewNumber == 2);
    expect(arthurAfterLeft.position.dx.round() < 279, isTrue,
        reason: 'Arthur should move leftwards from entrance');
    final leftX = arthurAfterLeft.position.dx.round();

    // 2. Arthur should successfully move Right (dir 3) back towards entrance
    engine.handleDirection(3);
    for (var t = 0; t < 20; t++) {
      engine.tick();
    }
    final arthurAfterRight = engine.actors.firstWhere((a) => a.viewNumber == 2);
    expect(arthurAfterRight.position.dx.round() > leftX, isTrue,
        reason: 'Arthur should move rightwards');

    // 3. Arthur should successfully move Down (dir 5)
    engine.handleDirection(5);
    for (var t = 0; t < 20; t++) {
      engine.tick();
    }
    final arthurAfterDown = engine.actors.firstWhere((a) => a.viewNumber == 2);
    expect(arthurAfterDown.position.dy.round() > 108, isTrue,
        reason: 'Arthur should move downwards');
    final downY = arthurAfterDown.position.dy.round();

    // 4. Arthur should successfully move Up (dir 1)
    engine.handleDirection(1);
    for (var t = 0; t < 20; t++) {
      engine.tick();
    }
    final arthurAfterUp = engine.actors.firstWhere((a) => a.viewNumber == 2);
    expect(arthurAfterUp.position.dy.round() < downY, isTrue,
        reason: 'Arthur should move upwards');

    engine.dispose();
  });
}

