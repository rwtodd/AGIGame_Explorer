import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

final _userStateRoom2Json = <String, dynamic>{
  "version": "1.0",
  "timestamp": "2026-08-16T20:50:15.395804",
  "label": "Room 2 (Cycle 207)",
  "roomNumber": 2,
  "cycleCount": 207,
  "speedHz": 20.0,
  "score": 0,
  "maxScore": 202,
  "soundOn": true,
  "isPaused": false,
  "isInputEnabled": true,
  "isUserControl": true,
  "lastSubmittedCommand": "look door",
  "lastError": "I don't understand 'rich'",
  "variables": {
    "0": 2, "1": 69, "7": 202, "8": 10, "10": 2, "11": 9, "15": 3,
    "16": 1, "19": 13, "22": 1, "24": 41, "64": 70, "73": 9, "74": 3,
    "75": 8, "76": 6, "77": 1, "133": 249, "135": 44, "136": 66,
    "151": 44, "152": 66, "153": 44, "154": 66
  },
  "activeFlags": [2, 4, 8, 9, 14, 86, 163],
  "activeControllers": <int>[],
  "itemRooms": {
    "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0,
    "8": 0, "9": 0, "10": 0, "11": 0, "12": 0, "13": 0, "14": 0,
    "15": 0, "16": 0, "17": 0, "18": 0, "19": 0, "20": 0, "21": 0,
    "22": 0, "23": 0, "24": 0
  },
  "strings": {
    "0": ">",
    "1": "Rich",
    "4": "Version 2.2"
  },
  "objects": [
    {
      "number": 0,
      "x": 44, "y": 66, "prevX": 43, "prevY": 66,
      "view": 1, "loop": 0, "cel": 6, "priority": 6,
      "fixedPriority": false, "fixedLoop": false, "direction": 0,
      "stepSize": 1, "stepTime": 1, "stepTimer": 1,
      "cycleTime": 1, "cycleTimer": 1,
      "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
      "cycleMode": 0, "motionType": 0, "targetX": 97, "targetY": 66, "stepDistance": 0,
      "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": true,
      "onWater": false, "onLand": false
    }
  ],
  "callStack": [
    {
      "scriptNumber": 0,
      "ip": 1584
    },
    {
      "scriptNumber": 2,
      "ip": 703
    }
  ],
  "scanStartIp": 0,
  "scanStarts": <String, dynamic>{}
};

void main() {
  group('Space Quest 1 - Room 2 Look Door Single-Shot Query', () {
    late Directory sq1Dir;

    setUp(() {
      sq1Dir = Directory('reference_games/space-quest-1');
    });

    test('restoring user state in Room 2 and typing look door answers once and resets flag 2', () {
      if (!sq1Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq1Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      engine.initializeGame();

      final snapshot = AgiGameStateSnapshot.fromJson(_userStateRoom2Json);
      snapshot.restore(engine);

      expect(engine.currentRoom, 2);

      // Dismiss any dialog currently open in the restored snapshot
      if (engine.activeDialog != null) {
        engine.dismissDialog();
      }

      // Now submit command "look door"
      engine.submitCommand('look door');
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1

      // Run cycle where logic responds to "look door"
      engine.tick();
      expect(engine.activeDialog, isNotNull, reason: 'Dialog should appear in response to look door');
      expect(engine.activeDialog!.message, contains('Data Archive'));

      // Dismiss dialog
      engine.dismissDialog();
      expect(engine.activeDialog, isNull);
      expect(engine.memory.getFlag(2), isFalse, reason: 'Flag 2 must be reset after dialog dismissal');
      expect(engine.memory.getFlag(4), isFalse, reason: 'Flag 4 must be reset after dialog dismissal');

      // Run a few ticks: "look door" response must NOT reappear
      for (int i = 0; i < 5; i++) {
        engine.tick();
        // Ensure it is not the look door response
        if (engine.activeDialog != null) {
          expect(engine.activeDialog!.message.contains("door"), isFalse);
        }
      }

      engine.dispose();
    });
  });
}
