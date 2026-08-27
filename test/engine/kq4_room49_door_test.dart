import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KQ4 Room 49 Closet Door & Movement Tests', () {
    final gamePath = Directory('reference_games/kings-quest-4-agi').existsSync()
        ? 'reference_games/kings-quest-4-agi'
        : '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-4-agi';

    test('opening closet door from various X positions (108, 110, 112, 114, 116) enters Room 51', () async {
      if (!Directory(gamePath).existsSync()) return;
      final loader = await AgiResourceLoader.fromDirectory(gamePath);

      for (final startX in [108, 110, 112, 114, 116]) {
        final engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
        await engine.initializeGame();
        engine.changeRoom(49);
        await engine.tick();

        // Position Ego in front of closet door
        engine.ego.x = startX;
        engine.ego.y = 109;
        engine.ego.prevX = startX;
        engine.ego.prevY = 109;

        // Issue command
        engine.submitCommand('open door');

        bool enteredRoom51 = false;
        for (int cycle = 0; cycle < 30; cycle++) {
          await engine.tick();
          if (engine.memory.getVar(0) == 51) {
            enteredRoom51 = true;
            break;
          }
        }

        expect(enteredRoom51, isTrue, reason: 'Failed to enter Room 51 when opening door from X=$startX');
      }
    });

    test('resuming from user snapshot at (114, 109) with move.obj to (114, 105) enters Room 51', () async {
      if (!Directory(gamePath).existsSync()) return;
      final loader = await AgiResourceLoader.fromDirectory(gamePath);
      final engine = AgiGameEngine(resourceLoader: loader, speedHz: 20.0);
      await engine.initializeGame();

      // Snapshot data provided by user
      const snapshotJson = '''
{
  "version": "1.0",
  "label": "Room 49 (Cycle 73560)",
  "roomNumber": 49,
  "pictureNumber": 49,
  "cycleCount": 73560,
  "speedHz": 20.0,
  "score": 111,
  "maxScore": 230,
  "soundOn": true,
  "isPaused": true,
  "isInputEnabled": true,
  "isUserControl": true,
  "isStatusLineEnabled": true,
  "statusRow": 0,
  "lastSubmittedCommand": "open door",
  "lastError": "I don't understand 'shakespeare'",
  "variables": {
    "0": 49,
    "1": 48,
    "3": 111,
    "7": 230,
    "8": 10,
    "10": 2,
    "11": 17,
    "12": 27,
    "22": 1,
    "24": 41,
    "25": 255,
    "31": 6,
    "33": 114,
    "34": 109,
    "35": 114,
    "36": 109,
    "43": 255,
    "45": 187,
    "46": 190,
    "47": 1,
    "48": 3,
    "49": 5,
    "51": 2,
    "54": 99,
    "57": 2,
    "62": 8,
    "63": 49,
    "64": 7,
    "108": 41,
    "111": 27,
    "112": 1,
    "117": 5,
    "119": 11,
    "120": 4,
    "121": 4,
    "122": 4,
    "123": 4,
    "124": 4,
    "125": 4,
    "126": 4,
    "127": 4,
    "128": 4,
    "129": 4,
    "130": 4,
    "131": 4,
    "132": 4,
    "133": 17,
    "137": 4,
    "138": 4,
    "139": 4,
    "140": 4,
    "141": 4,
    "142": 4,
    "143": 4,
    "144": 4,
    "145": 4,
    "146": 4,
    "147": 4,
    "148": 4,
    "149": 4,
    "150": 4,
    "151": 4,
    "152": 0,
    "153": 4,
    "154": 4,
    "155": 4,
    "156": 4,
    "157": 4,
    "158": 4,
    "159": 4,
    "160": 4,
    "161": 4,
    "162": 4,
    "163": 4,
    "164": 4,
    "165": 4,
    "166": 4,
    "167": 4,
    "168": 15,
    "170": 4,
    "171": 4,
    "172": 4,
    "173": 4,
    "174": 4,
    "175": 4,
    "176": 4,
    "177": 4,
    "178": 4,
    "179": 4,
    "180": 4,
    "181": 4,
    "182": 4,
    "183": 4,
    "184": 4,
    "185": 4,
    "186": 4,
    "187": 4,
    "188": 4,
    "189": 4,
    "190": 4,
    "191": 4,
    "192": 4,
    "193": 4,
    "194": 4,
    "195": 4,
    "196": 4,
    "197": 4,
    "198": 4,
    "199": 4,
    "200": 4,
    "201": 4,
    "202": 4,
    "203": 4,
    "204": 4,
    "205": 4,
    "206": 4,
    "207": 4,
    "208": 4,
    "209": 4,
    "210": 4,
    "211": 4,
    "212": 4,
    "213": 4,
    "214": 4,
    "215": 4,
    "216": 4,
    "217": 4,
    "218": 4,
    "219": 4,
    "220": 4,
    "221": 21
  },
  "activeFlags": [
    0,
    1,
    21,
    41,
    57,
    108,
    110,
    111,
    112,
    154,
    223
  ],
  "strings": {},
  "controllers": {},
  "objects": [
    {
      "number": 0,
      "x": 114,
      "y": 109,
      "prevX": 114,
      "prevY": 110,
      "view": 0,
      "loop": 1,
      "cel": 4,
      "priority": 4,
      "direction": 1,
      "motionType": 3,
      "cycleType": 0,
      "stepSize": 1,
      "stepTime": 1,
      "cycleTime": 1,
      "isDrawn": true,
      "isAnimated": true,
      "isCycling": true,
      "isUpdating": true,
      "fixedPriority": false,
      "fixedLoop": false,
      "ignoreBlocks": true,
      "ignoreHorizon": false,
      "ignoreObjects": false,
      "targetX": 114,
      "targetY": 105,
      "targetFlag": 227
    },
    {
      "number": 1,
      "x": 21,
      "y": 119,
      "prevX": 21,
      "prevY": 119,
      "view": 129,
      "loop": 1,
      "cel": 0,
      "priority": 4,
      "direction": 0,
      "motionType": 0,
      "cycleType": 0,
      "stepSize": 1,
      "stepTime": 1,
      "cycleTime": 1,
      "isDrawn": true,
      "isAnimated": true,
      "isCycling": false,
      "isUpdating": false,
      "fixedPriority": true,
      "fixedLoop": false,
      "ignoreBlocks": true,
      "ignoreHorizon": false,
      "ignoreObjects": true
    },
    {
      "number": 2,
      "x": 74,
      "y": 114,
      "prevX": 74,
      "prevY": 114,
      "view": 129,
      "loop": 4,
      "cel": 0,
      "priority": 4,
      "direction": 0,
      "motionType": 0,
      "cycleType": 0,
      "stepSize": 1,
      "stepTime": 1,
      "cycleTime": 4,
      "isDrawn": true,
      "isAnimated": true,
      "isCycling": true,
      "isUpdating": true,
      "fixedPriority": true,
      "fixedLoop": false,
      "ignoreBlocks": false,
      "ignoreHorizon": false,
      "ignoreObjects": false
    },
    {
      "number": 4,
      "x": 102,
      "y": 113,
      "prevX": 102,
      "prevY": 113,
      "view": 129,
      "loop": 2,
      "cel": 3,
      "priority": 4,
      "direction": 0,
      "motionType": 0,
      "cycleType": 0,
      "stepSize": 1,
      "stepTime": 1,
      "cycleTime": 4,
      "isDrawn": true,
      "isAnimated": true,
      "isCycling": false,
      "isUpdating": true,
      "fixedPriority": true,
      "fixedLoop": false,
      "ignoreBlocks": true,
      "ignoreHorizon": false,
      "ignoreObjects": false
    }
  ],
  "inventory": {
    "1": 49,
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
    "33": 0
  },
  "horizon": 40,
  "activeBlock": [
    99,
    106,
    104,
    112
  ]
}
''';

      GameStateSerializer.deserializeFromJson(snapshotJson, engine);

      bool enteredRoom51 = false;
      for (int cycle = 0; cycle < 15; cycle++) {
        await engine.tick();
        if (engine.memory.getVar(0) == 51) {
          enteredRoom51 = true;
          break;
        }
      }

      expect(enteredRoom51, isTrue, reason: 'Failed to transition to Room 51 from snapshot');
    });
  });
}
