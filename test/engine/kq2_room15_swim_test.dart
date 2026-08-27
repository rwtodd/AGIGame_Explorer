import 'dart:io';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("King's Quest 2 Room 15 Ocean Water & Swimming Tests", () {
    late Directory kq2Dir;

    setUp(() {
      kq2Dir = Directory('reference_games/kings-quest-2');
    });

    test('Walking into ocean water in Room 15 and typing swim succeeds', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.changeRoom(15);

      final ego = engine.ego;
      ego.x = 90;
      ego.y = 100;

      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Walk West into water until Ego splashes (view 104)
      engine.setEgoDirection(7);
      for (var i = 0; i < 20; i++) {
        await engine.tick();
        if (ego.view == 104) break;
      }

      expect(ego.view, 104);
      expect(engine.memory.getVar(95), 1);
      expect(engine.memory.getFlag(0), isTrue);

      // Now type swim while splashing
      engine.submitCommand('swim');
      await engine.tick();

      expect(engine.activeDialog, isNull);
      expect(ego.view, 97); // View 97 = Swimming
      expect(engine.memory.getVar(95), 2); // v95 = 2 (swimming)
      expect(engine.memory.getFlag(0), isTrue);
      engine.dispose();
    });

    test('Restoring user snapshot in Room 15 and submitting swim starts swimming', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();

      final snapshotJson = {
        "version": "1.0",
        "timestamp": "2026-08-16T01:26:42.558689",
        "label": "Room 15 (Cycle 12950)",
        "roomNumber": 15,
        "cycleCount": 12950,
        "speedHz": 20.0,
        "score": 20,
        "maxScore": 185,
        "soundOn": true,
        "isPaused": false,
        "isInputEnabled": true,
        "isUserControl": false,
        "lastSubmittedCommand": "swim",
        "variables": {
          "0": 15,
          "1": 16,
          "3": 20,
          "7": 185,
          "8": 10,
          "10": 2,
          "11": 16,
          "12": 10,
          "15": 3,
          "22": 1,
          "23": 3,
          "24": 41,
          "52": 123,
          "56": 2,
          "58": 1,
          "76": 249,
          "79": 5,
          "80": 3,
          "94": 2,
          "95": 1,
          "100": 78,
          "101": 86,
          "102": 78,
          "103": 86,
          "105": 175,
          "106": 167,
          "108": 2
        },
        "activeFlags": [
          8,
          9,
          11,
          14,
          33,
          55,
          57,
          59,
          62,
          65,
          66,
          67,
          72,
          73,
          82,
          92,
          115,
          126,
          146,
          153,
          156,
          169
        ],
        "activeControllers": [],
        "itemRooms": {
          "0": 0,
          "1": 0,
          "2": 0,
          "3": 0,
          "4": 0,
          "5": 0,
          "6": 0,
          "7": 0,
          "8": 0,
          "9": 0,
          "10": 0,
          "11": 0,
          "12": 0,
          "13": 0,
          "14": 0,
          "15": 0,
          "16": 0,
          "17": 0,
          "18": 0,
          "19": 0,
          "20": 0,
          "21": 0,
          "22": 0,
          "23": 0,
          "24": 0,
          "25": 0,
          "26": 0,
          "27": 0,
          "28": 0,
          "29": 0,
          "30": 0,
          "31": 0,
          "32": 0,
          "33": 0,
          "34": 0,
          "35": 0,
          "36": 0,
          "37": 0,
          "38": 0,
          "39": 0,
          "40": 0,
          "41": 0,
          "42": 0,
          "43": 0,
          "44": 0,
          "45": 0,
          "46": 0,
          "47": 0,
          "48": 0,
          "49": 0,
          "50": 0,
          "51": 0,
          "52": 0,
          "53": 0,
          "54": 0,
          "55": 0,
          "56": 0,
          "57": 0,
          "58": 0,
          "59": 0,
          "60": 0,
          "61": 0,
          "62": 0,
          "63": 0,
          "64": 0,
          "65": 0,
          "66": 0,
          "67": 0,
          "68": 0,
          "69": 0,
          "70": 0,
          "71": 0,
          "72": 0,
          "73": 0,
          "74": 0,
          "75": 0,
          "76": 0,
          "77": 0,
          "78": 0,
          "79": 0,
          "80": 0,
          "81": 0,
          "82": 0,
          "83": 0,
          "84": 0,
          "85": 0,
          "86": 0,
          "87": 0,
          "88": 0,
          "89": 0,
          "90": 0,
          "91": 0,
          "92": 0,
          "93": 0,
          "94": 0,
          "95": 0,
          "96": 0,
          "97": 0,
          "98": 0,
          "99": 0,
          "100": 0,
          "101": 0,
          "102": 0,
          "103": 0,
          "104": 0,
          "105": 0,
          "106": 0,
          "107": 0,
          "108": 0,
          "109": 0,
          "110": 0,
          "111": 0,
          "112": 0,
          "113": 0,
          "114": 0,
          "115": 0,
          "116": 0,
          "117": 0,
          "118": 0,
          "119": 0,
          "120": 0
        },
        "strings": {},
        "objects": [
          {
            "number": 0,
            "x": 78,
            "y": 86,
            "prevX": 79,
            "prevY": 86,
            "view": 104,
            "loop": 0,
            "cel": 1,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 0,
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
            "endOfLoopFlag": null,
            "motionType": 0,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 1,
            "targetFlag": null,
            "ignoreHorizon": false,
            "ignoreBlocks": false,
            "ignoreObjects": false
          }
        ]
      };

      AgiGameStateSnapshot.fromJson(snapshotJson).restore(engine);
      // Because Ego was in splashing state (v95 == 1, view 104), object.on.water is active and in water
      engine.ego.onWater = true;
      engine.memory.setFlag(0);

      // Submit swim
      engine.submitCommand('swim');
      await engine.tick();

      expect(engine.activeDialog, isNull);
      expect(engine.ego.view, 97);
      expect(engine.memory.getVar(95), 2);
      engine.dispose();
    });

    test('Swimming across multiple rooms in KQ2 retains swimming view 97', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();
      engine.changeRoom(15);

      // Ego walks into water in Room 15
      engine.ego.x = 90;
      engine.ego.y = 100;
      for (var i = 0; i < 5; i++) {
        await engine.tick();
      }

      // Walk West into water to splash
      engine.setEgoDirection(7);
      for (var i = 0; i < 20; i++) {
        await engine.tick();
        if (engine.ego.view == 104) break;
      }

      // Type swim
      engine.submitCommand('swim');
      await engine.tick();

      expect(engine.ego.view, 97);
      expect(engine.memory.getVar(16), 97);
      expect(engine.memory.getVar(95), 2);

      // Swim North across the border into Room 8. View 97 is 13 pixels wide and
      // object.on.water requires the whole baseline on priority 3, so we steer
      // to keep the swim cel inside the shrinking water channel.
      engine.ego.x = 45;
      engine.setEgoDirection(1); // North
      for (var i = 0; i < 200; i++) {
        await engine.tick();
        if (engine.memory.getVar(0) == 8) break;
        if (engine.ego.direction == 0) {
          final pri = engine.currentPic!.priorityBuffer;
          final w = engine.ego.getCelWidth();
          final y = engine.ego.y;
          final ny = y - 1;
          var bestX = engine.ego.x;
          var bestDist = 999;
          for (var x = 0; x <= 160 - w; x++) {
            var water = true;
            for (var bx = x; bx < x + w; bx++) {
              if (pri.priorityAt(bx, ny) != 3) {
                water = false;
                break;
              }
            }
            if (!water) continue;
            final dist = (x - engine.ego.x).abs();
            if (dist < bestDist) {
              bestDist = dist;
              bestX = x;
            }
          }
          engine.ego.x = bestX;
          engine.setEgoDirection(1);
        }
      }

      expect(engine.memory.getVar(0), 8, reason: 'Ego should have crossed into Room 8');
      expect(engine.ego.view, 97, reason: 'Ego must retain swimming view 97 in Room 8');
      expect(engine.memory.getVar(16), 97);
      expect(engine.memory.getVar(95), 2);

      // Swim South back from Room 8 into Room 15
      engine.setEgoDirection(5); // South
      for (var i = 0; i < 100; i++) {
        await engine.tick();
        if (engine.memory.getVar(0) == 15) break;
      }

      expect(engine.memory.getVar(0), 15, reason: 'Ego should have crossed back into Room 15');
      expect(engine.ego.view, 97, reason: 'Ego must retain swimming view 97 in Room 15');
      expect(engine.memory.getVar(16), 97);
      expect(engine.memory.getVar(95), 2);
      engine.dispose();
    });

    test('Restoring user state after seahorse in Room 15 allows Ego to move freely', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      await engine.initializeGame();

      final snapshotJson = {
        "version": "1.0",
        "timestamp": "2026-08-16T02:06:16.999009",
        "label": "Stuck after seahorse",
        "roomNumber": 15,
        "cycleCount": 1299,
        "speedHz": 20.0,
        "score": 31,
        "maxScore": 185,
        "soundOn": true,
        "isPaused": false,
        "isInputEnabled": true,
        "isUserControl": true,
        "lastSubmittedCommand": "get key",
        "variables": {
          "0": 15,
          "1": 54,
          "3": 31,
          "7": 185,
          "8": 10,
          "10": 2,
          "11": 48,
          "12": 10,
          "15": 3,
          "16": 97,
          "22": 1,
          "23": 3,
          "24": 41,
          "52": 249,
          "56": 2,
          "64": 2,
          "76": 249,
          "79": 5,
          "80": 3,
          "95": 2,
          "100": 20,
          "101": 100,
          "102": 20,
          "103": 100,
          "105": 175,
          "106": 167,
          "108": 2
        },
        "activeFlags": [
          0,
          8,
          9,
          11,
          14,
          55,
          57,
          59,
          62,
          65,
          66,
          67,
          72,
          73,
          82,
          92,
          94,
          95,
          96,
          97,
          115,
          126,
          146,
          153,
          156,
          169
        ],
        "activeControllers": [],
        "itemRooms": {
          "0": 0
        },
        "strings": {},
        "objects": [
          {
            "number": 0,
            "x": 20,
            "y": 100,
            "prevX": 20,
            "prevY": 100,
            "view": 97,
            "loop": 0,
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
            "isCycling": true,
            "cycleMode": 3,
            "endOfLoopFlag": 36,
            "motionType": 0,
            "targetX": 0,
            "targetY": 0,
            "stepDistance": 1,
            "ignoreHorizon": false,
            "ignoreBlocks": false,
            "ignoreObjects": false,
            "onWater": true,
            "onLand": false
          },
          {
            "number": 2,
            "x": 7,
            "y": 60,
            "prevX": 7,
            "prevY": 60,
            "view": 10,
            "loop": 0,
            "cel": 0,
            "priority": 14,
            "fixedPriority": true,
            "fixedLoop": false,
            "direction": 0,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 2,
            "cycleTimer": 1,
            "isAnimated": true,
            "isDrawn": false,
            "isUpdating": true,
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
          },
          {
            "number": 3,
            "x": 0,
            "y": 100,
            "prevX": 0,
            "prevY": 100,
            "view": 12,
            "loop": 1,
            "cel": 0,
            "priority": 0,
            "fixedPriority": false,
            "fixedLoop": false,
            "direction": 0,
            "stepSize": 1,
            "stepTime": 1,
            "stepTimer": 1,
            "cycleTime": 2,
            "cycleTimer": 2,
            "isAnimated": true,
            "isDrawn": true,
            "isUpdating": true,
            "isCycling": true,
            "cycleMode": 2,
            "endOfLoopFlag": 37,
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
        ]
      };

      AgiGameStateSnapshot.fromJson(snapshotJson).restore(engine);
      engine.ego.onWater = true;

      // Run tick 0 to let the seahorse drop-off script complete
      await engine.tick();
      expect(engine.ego.cycleMode, 0);
      expect(engine.ego.endOfLoopFlag, isNull);

      // Player presses East arrow (direction 3) towards the beach
      engine.setEgoDirection(3);

      for (var i = 0; i < 20; i++) {
        await engine.tick();
      }

      expect(engine.ego.x, greaterThan(20), reason: 'Ego must move East towards the beach');
      expect(engine.memory.getFlag(36), isFalse, reason: 'Flag 36 must not re-trigger');
      engine.dispose();
    });

    test('King\'s Quest 2 Room 8 Ocean: Walking west into ocean wades and typing swim swims', () async {
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);
      await engine.initializeGame();

      engine.changeRoom(8);
      await engine.tick();

      // Start Graham on the beach at x=40, y=69 facing West (direction 7)
      engine.ego.x = 40;
      engine.ego.y = 69;
      engine.ego.view = 0;
      engine.memory.setVar(95, 0); // walking

      for (int i = 0; i < 40; i++) {
        engine.memory.setVar(6, 7); // West
        await engine.tick();
        if (engine.ego.view == 104) {
          break;
        }
      }

      expect(engine.ego.view, 104);
      expect(engine.memory.getVar(95), 1);
      expect(engine.memory.getFlag(0), isTrue, reason: 'Flag 0 must be true while wading in ocean');

      // Type "swim"
      engine.submitCommand('swim');
      await engine.tick();

      expect(engine.ego.view, 97, reason: 'Ego should have switched to swimming view 97');
      expect(engine.memory.getVar(95), 2, reason: 'v95 should be 2 (swimming)');
      expect(engine.memory.getFlag(0), isTrue);

      engine.dispose();
    });
  });
}
