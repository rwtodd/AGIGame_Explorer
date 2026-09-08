import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

void main() {
  group('SciGameEngine Lifecycle & Session', () {
    test('initializes and executes tick cycles', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);

      expect(engine.displayProfile, DisplayProfile.sci0);
      expect(engine.isRunning, isFalse);
      expect(engine.cycleCount, 0);

      engine.initializeGame();
      expect(engine.statusLine, isNotEmpty);

      // Start engine (runs first tick and starts periodic timer)
      engine.start();
      expect(engine.isRunning, isTrue);
      expect(engine.isPaused, isFalse);

      // Execute some ticks directly
      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      expect(engine.cycleCount, greaterThanOrEqualTo(5));
      expect(engine.currentPic, isNotNull);
      expect(engine.actors, isNotEmpty);

      // Direction event handling
      engine.handleDirection(3); // East
      expect(engine.kernel.eventQueue, isNotEmpty);

      // Key event handling
      engine.handleKeyPress(0x0D, ascii: 0x0D); // Enter
      expect(engine.kernel.eventQueue, isNotEmpty);

      // Pause and resume
      engine.pause();
      expect(engine.isPaused, isTrue);

      engine.resume();
      expect(engine.isPaused, isFalse);

      engine.dispose();
      expect(engine.isRunning, isFalse);
    });

    test('exportState and exportStateJson return structured engine snapshot', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();

      final state = engine.exportState(label: 'Test State');
      expect(state['engine'], 'SCI0');
      expect(state['label'], 'Test State');
      expect(state['vm'], isNotNull);
      expect(state['globals'], isA<Map>());
      expect(state['loadedScripts'], isA<List>());

      final jsonStr = engine.exportStateJson();
      expect(jsonStr, contains('"engine": "SCI0"'));

      engine.dispose();
    });

    test('clone method lookup resolves to owning script segment and executes without stack leak', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final engine = SciGameEngine(volumeManager: volumeMgr);
      engine.initializeGame();

      // 1. Verify that cloning a class keeps method resolution pointing to script segment
      final scr998 = engine.segManager.instantiateScript(998, engine.volumeManager);
      final actClass = scr998.getObject(0x0b06)!;
      final cloneObj = engine.segManager.cloneObject(actClass);

      expect(cloneObj.isClone, isTrue);
      expect(cloneObj.pos.segment, SciSegManager.cloneSegmentId);
      final methodInfo = cloneObj.lookupMethod(engine.segManager, engine.selectors.init);
      expect(methodInfo, isNotNull);
      final (methodObj, _) = methodInfo!;
      expect(methodObj.pos.segment, isNot(SciSegManager.cloneSegmentId));
      expect(methodObj.pos.segment, scr998.segmentId);

      // 2. Start engine and run multiple ticks, ensuring stackDepth does not leak
      engine.start();
      for (int i = 0; i < 20; i++) {
        engine.tick();
      }
      final initialDepth = engine.vm.stack.length;
      for (int i = 0; i < 30; i++) {
        engine.tick();
      }
      expect(engine.vm.stack.length, initialDepth);
      expect(engine.vm.executionStack.length, lessThanOrEqualTo(4));

      engine.dispose();
    });
  });
}
