import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  group("King's Quest 2 Room 18 Castle Door & Actor Collision Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Walking into closed castle door (Object 4) in Room 18 blocks Ego motion', () {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      engine.initializeGame();
      engine.changeRoom(18);

      // Run a few ticks for room initialization
      for (int i = 0; i < 5; i++) {
        engine.tick();
      }

      // Door is Object 4 at (68, 142)
      final door = engine.animatedObjects[4];
      expect(door.isDrawn, isTrue);
      expect(door.x, 68);
      expect(door.y, 142);

      // Place Ego right in front of the closed door
      final ego = engine.ego;
      ego.x = 75;
      ego.y = 143;
      ego.prevX = 75;
      ego.prevY = 144;

      // Try to walk North into the closed door
      engine.setEgoDirection(1); // North (dy = -1)
      engine.tick();

      expect(ego.y, 143, reason: 'Ego must be blocked by closed door at y=142');
      expect(ego.direction, 0, reason: 'Ego stops on collision with door');
    });

    test('Restored user state in Room 18 cannot walk through castle door', () {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      final snapshotJson = {
        "version": "1.0",
        "timestamp": "2026-08-16T12:16:18.858353",
        "label": "Room 18 (Cycle 20417)",
        "roomNumber": 18,
        "cycleCount": 20417,
        "speedHz": 40.0,
        "score": 112,
        "maxScore": 185,
        "soundOn": true,
        "isPaused": false,
        "isInputEnabled": true,
        "isUserControl": true,
        "lastSubmittedCommand": "eat sugar cube",
        "variables": {
          "0": 18, "1": 25, "3": 112, "7": 185, "8": 10, "10": 2, "11": 25, "12": 24, "15": 3,
          "22": 1, "23": 3, "24": 41, "52": 249, "54": 15, "56": 6, "62": 40, "64": 2, "65": 1,
          "66": 73, "76": 249, "79": 5, "80": 3, "87": 3, "89": 114, "90": 30, "94": 2,
          "100": 78, "101": 121, "102": 78, "103": 121, "105": 154, "106": 109, "108": 2,
          "114": 43, "115": 91, "116": 51, "117": 103, "118": 3, "120": 117, "121": 117
        },
        "activeFlags": [
          8, 9, 11, 14, 55, 57, 59, 62, 65, 66, 67, 68, 69, 70, 72, 73, 74, 75, 82, 84, 85, 86,
          94, 95, 96, 97, 98, 99, 100, 101, 104, 109, 110, 111, 112, 126, 129, 133, 134, 146,
          151, 153, 154, 156, 157, 159, 160, 169, 176
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
          "70": 0, "71": 0, "72": 0, "73": 255, "74": 0, "75": 0, "76": 255, "77": 0, "78": 0, "79": 0,
          "80": 0, "81": 0, "82": 255, "83": 0, "84": 0
        },
        "strings": {
          "0": ">"
        },
        "objects": [
          {
            "number": 0,
            "x": 78,
            "y": 144,
            "prevX": 78,
            "prevY": 145,
            "view": 0,
            "loop": 3,
            "cel": 6,
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
            "x": 76,
            "y": 145,
            "prevX": 75,
            "prevY": 146,
            "view": 16,
            "loop": 0,
            "cel": 2,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 2,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 2,
            "cycleTimer": 2,
            "isAnimated": true,
            "isDrawn": true,
            "isUpdating": true,
            "isCycling": true,
            "cycleMode": 0,
            "motionType": 2,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 10,
            "targetFlag": 30,
            "ignoreHorizon": false,
            "ignoreBlocks": false,
            "ignoreObjects": false,
            "onWater": false,
            "onLand": false
          },
          {
            "number": 3,
            "x": 53,
            "y": 100,
            "prevX": 54,
            "prevY": 101,
            "view": 16,
            "loop": 0,
            "cel": 2,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 8,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 2,
            "cycleTimer": 2,
            "isAnimated": true,
            "isDrawn": true,
            "isUpdating": true,
            "isCycling": true,
            "cycleMode": 0,
            "motionType": 1,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 1,
            "ignoreHorizon": false,
            "ignoreBlocks": false,
            "ignoreObjects": false,
            "onWater": false,
            "onLand": false
          },
          {
            "number": 4,
            "x": 68,
            "y": 142,
            "prevX": 68,
            "prevY": 142,
            "view": 15,
            "loop": 0,
            "cel": 0,
            "priority": 5,
            "fixedPriority": true,
            "fixedLoop": false,
            "direction": 0,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 2,
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

      // Step North from y=144 to y=143
      engine.setEgoDirection(1);
      engine.tick();
      expect(engine.ego.y, 143);

      // Step North from y=143 towards door at y=142 -> blocked
      engine.setEgoDirection(1);
      engine.tick();
      expect(engine.ego.y, 143, reason: 'Ego must be blocked by closed castle door at y=142');
      expect(engine.ego.direction, 0);
    });
  });
}
