import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

final _vohaulSnapshotJson = <String, dynamic>{
  "version": "1.0",
  "timestamp": "2026-08-16T19:03:33.905056",
  "label": "Room 6 (Cycle 4228)",
  "roomNumber": 6,
  "cycleCount": 4228,
  "speedHz": 20.0,
  "score": 10,
  "maxScore": 250,
  "soundOn": true,
  "isPaused": false,
  "isInputEnabled": false,
  "isUserControl": true,
  "lastSubmittedCommand": "close locker",
  "lastError": "I don't understand 'cubby'",
  "variables": {
    "0": 6, "1": 5, "3": 10, "6": 1, "7": 250, "8": 10, "10": 2, "11": 31,
    "12": 3, "15": 3, "21": 20, "22": 1, "24": 41, "31": 42, "32": 10,
    "33": 55, "34": 31, "36": 5, "37": 22, "38": 46, "39": 71, "40": 123,
    "41": 1, "42": 38, "43": 4, "47": 10, "50": 2, "51": 100, "52": 72,
    "54": 57, "55": 19, "64": 2, "68": 249, "70": 27, "71": 114, "73": 31,
    "74": 1, "75": 76, "76": 109, "77": 76, "78": 109, "86": 1, "87": 2,
    "88": 3, "90": 4, "91": 5, "108": 3, "112": 6
  },
  "activeFlags": [7, 8, 9, 14, 15, 32, 57, 58, 61, 71, 73, 201],
  "activeControllers": <int>[],
  "itemRooms": {
    "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "9": 0,
    "10": 0, "11": 0, "12": 0, "13": 0, "14": 0, "15": 0, "16": 0, "17": 0, "18": 0, "19": 0,
    "20": 255, "21": 255, "22": 0, "23": 0, "24": 0, "25": 0, "26": 0, "27": 0, "28": 0, "29": 0,
    "30": 0, "31": 0, "32": 0, "33": 0, "34": 0, "35": 255, "36": 0, "37": 255, "38": 0, "39": 0
  },
  "strings": {
    "0": ">",
    "1": "BUCKY",
    "4": "Ver. 2.0F"
  },
  "objects": [
    {
      "number": 0,
      "x": 76, "y": 109, "prevX": 76, "prevY": 110,
      "view": 0, "loop": 3, "cel": 4, "priority": 0,
      "fixedPriority": false, "fixedLoop": false, "direction": 1,
      "stepSize": 1, "stepTime": 1, "stepTimer": 1,
      "cycleTime": 1, "cycleTimer": 1,
      "isAnimated": true, "isDrawn": false, "isUpdating": true, "isCycling": true,
      "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
      "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
      "onWater": false, "onLand": false
    },
    {
      "number": 1,
      "x": 87, "y": 54, "prevX": 87, "prevY": 54,
      "view": 36, "loop": 0, "cel": 0, "priority": 6,
      "fixedPriority": true, "fixedLoop": false, "direction": 0,
      "stepSize": 1, "stepTime": 1, "stepTimer": 1,
      "cycleTime": 2, "cycleTimer": 1,
      "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
      "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
      "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
      "onWater": false, "onLand": false
    },
    {
      "number": 2,
      "x": 129, "y": 79, "prevX": 129, "prevY": 79,
      "view": 36, "loop": 2, "cel": 0, "priority": 6,
      "fixedPriority": true, "fixedLoop": false, "direction": 0,
      "stepSize": 1, "stepTime": 1, "stepTimer": 1,
      "cycleTime": 2, "cycleTimer": 2,
      "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
      "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
      "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
      "onWater": false, "onLand": false
    },
    {
      "number": 3,
      "x": 46, "y": 79, "prevX": 46, "prevY": 79,
      "view": 36, "loop": 3, "cel": 0, "priority": 6,
      "fixedPriority": true, "fixedLoop": false, "direction": 0,
      "stepSize": 1, "stepTime": 1, "stepTimer": 1,
      "cycleTime": 3, "cycleTimer": 3,
      "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
      "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
      "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
      "onWater": false, "onLand": false
    }
  ],
  "callStack": <dynamic>[],
  "scanStartIp": 0,
  "scanStarts": <String, dynamic>{}
};

void main() {
  group('Space Quest 2 - Vohaul Capture in Room 6', () {
    late Directory sq2Dir;

    setUp(() {
      sq2Dir = Directory('reference_games/space-quest-2');
    });

    test('Full Room 6 Vohaul speech sequence displays all dialogs', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      final snapshot = AgiGameStateSnapshot.fromJson(_vohaulSnapshotJson);
      snapshot.restore(engine);

      final dialogsSeen = <String>[];

      for (int i = 0; i < 500; i++) {
        if (engine.memory.getFlag(32)) {
          engine.handleKeyPress(13); // Enter to advance speech
        }
        await engine.tick();
        if (engine.activeDialog != null) {
          final msg = engine.activeDialog!.message;
          if (dialogsSeen.isEmpty || dialogsSeen.last != msg) {
            dialogsSeen.add(msg);
          }
          await engine.dismissDialog();
        }
        if (engine.currentRoom != 6) {
          break;
        }
      }

      // Verify key speech boxes from Vohaul
      expect(dialogsSeen.any((d) => d.contains("I've decided I would get much more enjoyment")), isTrue);
      expect(dialogsSeen.any((d) => d.contains("watching you suffer")), isTrue);
      expect(engine.currentRoom, 7);
    });

    test('Restore Vohaul capture snapshot in Room 6 and verify dialog sequence', () async {
      if (!sq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(sq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      final snapshotJson = {
        "version": "1.0",
        "timestamp": "2026-08-16T19:03:33.905056",
        "label": "Room 6 (Cycle 4228)",
        "roomNumber": 6,
        "cycleCount": 4228,
        "speedHz": 20.0,
        "score": 10,
        "maxScore": 250,
        "soundOn": true,
        "isPaused": false,
        "isInputEnabled": false,
        "isUserControl": true,
        "lastSubmittedCommand": "close locker",
        "lastError": "I don't understand 'cubby'",
        "variables": {
          "0": 6, "1": 5, "3": 10, "6": 1, "7": 250, "8": 10, "10": 2, "11": 31,
          "12": 3, "15": 3, "21": 20, "22": 1, "24": 41, "31": 42, "32": 10,
          "33": 55, "34": 31, "36": 5, "37": 22, "38": 46, "39": 71, "40": 123,
          "41": 1, "42": 38, "43": 4, "47": 10, "50": 2, "51": 100, "52": 72,
          "54": 57, "55": 19, "64": 2, "68": 249, "70": 27, "71": 114, "73": 31,
          "74": 1, "75": 76, "76": 109, "77": 76, "78": 109, "86": 1, "87": 2,
          "88": 3, "90": 4, "91": 5, "108": 3, "112": 6
        },
        "activeFlags": [7, 8, 9, 14, 15, 32, 57, 58, 61, 71, 73, 201],
        "activeControllers": [],
        "itemRooms": {
          "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "9": 0,
          "10": 0, "11": 0, "12": 0, "13": 0, "14": 0, "15": 0, "16": 0, "17": 0, "18": 0, "19": 0,
          "20": 255, "21": 255, "22": 0, "23": 0, "24": 0, "25": 0, "26": 0, "27": 0, "28": 0, "29": 0,
          "30": 0, "31": 0, "32": 0, "33": 0, "34": 0, "35": 255, "36": 0, "37": 255, "38": 0, "39": 0
        },
        "strings": {
          "0": ">",
          "1": "BUCKY",
          "4": "Ver. 2.0F"
        },
        "objects": [
          {
            "number": 0,
            "x": 76, "y": 109, "prevX": 76, "prevY": 110,
            "view": 0, "loop": 3, "cel": 4, "priority": 0,
            "fixedPriority": false, "fixedLoop": false, "direction": 1,
            "stepSize": 1, "stepTime": 1, "stepTimer": 1,
            "cycleTime": 1, "cycleTimer": 1,
            "isAnimated": true, "isDrawn": false, "isUpdating": true, "isCycling": true,
            "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
            "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
            "onWater": false, "onLand": false
          },
          {
            "number": 1,
            "x": 87, "y": 54, "prevX": 87, "prevY": 54,
            "view": 36, "loop": 0, "cel": 0, "priority": 6,
            "fixedPriority": true, "fixedLoop": false, "direction": 0,
            "stepSize": 1, "stepTime": 1, "stepTimer": 1,
            "cycleTime": 2, "cycleTimer": 1,
            "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
            "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
            "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
            "onWater": false, "onLand": false
          },
          {
            "number": 2,
            "x": 129, "y": 79, "prevX": 129, "prevY": 79,
            "view": 36, "loop": 2, "cel": 0, "priority": 6,
            "fixedPriority": true, "fixedLoop": false, "direction": 0,
            "stepSize": 1, "stepTime": 1, "stepTimer": 1,
            "cycleTime": 2, "cycleTimer": 2,
            "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
            "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
            "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
            "onWater": false, "onLand": false
          },
          {
            "number": 3,
            "x": 46, "y": 79, "prevX": 46, "prevY": 79,
            "view": 36, "loop": 3, "cel": 0, "priority": 6,
            "fixedPriority": true, "fixedLoop": false, "direction": 0,
            "stepSize": 1, "stepTime": 1, "stepTimer": 1,
            "cycleTime": 3, "cycleTimer": 3,
            "isAnimated": true, "isDrawn": true, "isUpdating": true, "isCycling": false,
            "cycleMode": 0, "motionType": 0, "targetX": 0, "targetY": 0, "stepDistance": 1,
            "ignoreHorizon": false, "ignoreBlocks": false, "ignoreObjects": false,
            "onWater": false, "onLand": false
          }
        ],
        "callStack": [],
        "scanStartIp": 0,
        "scanStarts": {}
      };

      final snapshot = AgiGameStateSnapshot.fromJson(snapshotJson);
      snapshot.restore(engine);

      final dialogsSeen = <String>[];

      for (int i = 0; i < 500; i++) {
        if (engine.memory.getFlag(32)) {
          engine.handleKeyPress(13); // Enter
        }
        await engine.tick();
        if (engine.activeDialog != null) {
          dialogsSeen.add(engine.activeDialog!.message);
          await engine.dismissDialog();
        }
        if (engine.currentRoom != 6) {
          break;
        }
      }

      expect(dialogsSeen.any((d) => d.contains("I've decided I would get much more enjoyment")), isTrue);
      expect(engine.currentRoom, 7);
    });
  });
}
