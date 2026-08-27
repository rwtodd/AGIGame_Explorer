import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group("King's Quest 2 Room 32 Poison Lake Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Stepping into poisoned lake in Room 32 triggers Flag 0 and drowning sequence', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      final snapshotJson = {
        "version": "1.0",
        "timestamp": "2026-08-16T12:07:44.438430",
        "label": "Room 32 (Cycle 6311)",
        "roomNumber": 32,
        "cycleCount": 6311,
        "speedHz": 40.0,
        "score": 111,
        "maxScore": 185,
        "soundOn": true,
        "isPaused": false,
        "isInputEnabled": true,
        "isUserControl": true,
        "lastSubmittedCommand": "get out of boat",
        "variables": {
          "0": 32, "1": 33, "3": 111, "7": 185, "8": 10, "10": 2, "12": 25, "15": 3, "22": 1,
          "23": 3, "24": 41, "52": 249, "56": 6, "62": 40, "64": 2, "65": 1, "76": 249,
          "79": 5, "80": 3, "87": 3, "89": 114, "90": 30, "94": 3, "100": 75, "101": 112,
          "102": 75, "103": 112, "105": 154, "106": 109, "108": 2, "114": 43, "115": 91,
          "116": 51, "117": 103, "118": 3, "120": 117, "121": 117
        },
        "activeFlags": [
          8, 9, 11, 14, 35, 36, 55, 57, 59, 62, 64, 65, 66, 67, 68, 69, 70, 72, 73, 74, 75,
          82, 84, 85, 86, 94, 95, 96, 97, 98, 99, 100, 101, 104, 109, 110, 111, 112, 115,
          126, 133, 134, 146, 151, 153, 154, 156, 159, 160, 169
        ],
        "activeControllers": [],
        "itemRooms": {
          "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "9": 0,
          "10": 0, "11": 0, "12": 0, "13": 0, "14": 0, "15": 0, "16": 0, "17": 0, "18": 0, "19": 0,
          "20": 0, "21": 0, "22": 0, "23": 0, "24": 0, "25": 0, "26": 0, "27": 0, "28": 0, "29": 0,
          "30": 0, "31": 0, "32": 0, "33": 0, "34": 0, "35": 0, "36": 0, "37": 0, "38": 0, "39": 0,
          "40": 0, "41": 0, "42": 0, "43": 0, "44": 0, "45": 0, "46": 0, "47": 0, "48": 0, "49": 0,
          "50": 255, "51": 0, "52": 255, "53": 0, "54": 255, "55": 255, "56": 0, "57": 38, "58": 255, "59": 255,
          "60": 255, "61": 0, "62": 3, "63": 0, "64": 0, "65": 255, "66": 0, "67": 0, "68": 255, "69": 255,
          "70": 0, "71": 0, "72": 0, "73": 255, "74": 0, "75": 0, "76": 255, "77": 0, "78": 0, "79": 255,
          "80": 0, "81": 0, "82": 255, "83": 0, "84": 0
        },
        "strings": {
          "0": ">"
        },
        "objects": [
          {
            "number": 0,
            "x": 75,
            "y": 112,
            "prevX": 75,
            "prevY": 113,
            "view": 0,
            "loop": 3,
            "cel": 0,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 0,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 1,
            "cycleTimer": 1,
            "isAnimated": true,
            "isDrawn": true,
            "isUpdating": true,
            "isCycling": false,
            "cycleMode": 0,
            "motionType": 0,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 1,
            "ignoreHorizon": false,
            "ignoreBlocks": true,
            "ignoreObjects": false,
            "onWater": false,
            "onLand": false
          },
          {
            "number": 2,
            "x": 88,
            "y": 126,
            "prevX": 88,
            "prevY": 126,
            "view": 24,
            "loop": 0,
            "cel": 0,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 0,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 3,
            "cycleTimer": 1,
            "isAnimated": true,
            "isDrawn": true,
            "isUpdating": false,
            "isCycling": true,
            "cycleMode": 0,
            "motionType": 0,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 1,
            "ignoreHorizon": false,
            "ignoreBlocks": false,
            "ignoreObjects": false,
            "onWater": false,
            "onLand": false
          }
        ],
        "callStack": [],
        "scanStartIp": 0
      };

      AgiGameStateSnapshot.fromJson(snapshotJson).restore(engine);
      await engine.onDrawPic(32);

      // On first tick, Flag 0 should be set because Ego's baseline (75..78, 112) is on water (priority 3)
      await engine.tick();
      expect(engine.memory.getFlag(0), isTrue, reason: 'Flag 0 must be set when baseline is on priority 3 water');
      expect(engine.ego.view, 104, reason: 'Ego should change to view 104 (drowning/sinking animation)');
      expect(engine.memory.getVar(95), 1);
      expect(engine.memory.getVar(86), 24);

      // Count down to death
      for (int i = 0; i < 15; i++) {
        await engine.tick();
        if (engine.activeDialog != null) {
          await engine.dismissDialog();
        }
      }

      for (int i = 0; i < 10; i++) {
        await engine.tick();
      }

      expect(engine.ego.isDrawn, isFalse, reason: 'Ego should be erased upon drowning');
      engine.dispose();
    });
  });
}
