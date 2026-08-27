import 'dart:io';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("King's Quest 2 Room 33 swimming start does not warp Ego", () async {
    final possiblePaths = [
      r'c:\users\richa\gog\kings-quest-2',
      'reference_games/kings-quest-2',
      '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-2',
    ];
    final path = possiblePaths.firstWhere(
      (p) => Directory(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) return;

    final loader = AgiResourceLoader.fromDirectorySync(path);
    final engine = AgiGameEngine(resourceLoader: loader);
    await engine.initializeGame();

    engine.changeRoom(33);
    await engine.tick();

    // Position Ego at water entry in Room 33: (139, 91)
    engine.ego.x = 139;
    engine.ego.y = 91;
    engine.ego.view = 104; // Wading view
    engine.ego.updateCachedView(loader.loadView(104));
    engine.memory.setVar(95, 1); // Wading state
    engine.memory.setVar(52, 250); // Wading countdown timer

    await engine.tick();
    expect(engine.memory.getFlag(0), isTrue, reason: 'Flag 0 should be true at (139, 91)');
    expect(engine.ego.onLand, isFalse, reason: 'Ego should not be onLand while on water');
    expect(engine.ego.x, equals(139), reason: 'Ego x should remain 139');
    expect(engine.ego.y, equals(91), reason: 'Ego y should remain 91');

    // Player types "swim"
    engine.submitCommand('swim');
    await engine.tick();
    expect(engine.ego.view, equals(97), reason: 'Ego should be in swimming view 97');
    expect(engine.ego.x, equals(139), reason: 'Ego should not jump when switching to swimming view');
    expect(engine.ego.y, equals(91), reason: 'Ego should not jump when switching to swimming view');

    // Player swims East (direction 3)
    engine.setEgoDirection(3);
    for (int i = 0; i < 5; i++) {
      await engine.tick();
    }
    expect(engine.ego.x, greaterThan(139), reason: 'Ego should swim East into the water');
  });
  test("King's Quest 2 Room 9 water detection and swimming transition", () async {
    final possiblePaths = [
      r'c:\users\richa\gog\kings-quest-2',
      'reference_games/kings-quest-2',
      '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-2',
    ];
    final path = possiblePaths.firstWhere(
      (p) => Directory(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) return;

    final loader = AgiResourceLoader.fromDirectorySync(path);
    final engine = AgiGameEngine(resourceLoader: loader);
    await engine.initializeGame();

    const jsonSnapshot = '''{
  "version": "1.0",
  "timestamp": "2026-08-27T17:11:42.987775",
  "label": "Room 9 (Cycle 1991)",
  "roomNumber": 9,
  "pictureNumber": 9,
  "cycleCount": 1991,
  "speedHz": 20.0,
  "score": 0,
  "maxScore": 185,
  "soundOn": true,
  "isPaused": false,
  "isInputEnabled": true,
  "isUserControl": true,
  "isStatusLineEnabled": true,
  "statusRow": 0,
  "lastSubmittedCommand": "look",
  "variables": {
    "0": 9,
    "1": 2,
    "7": 185,
    "8": 10,
    "10": 2,
    "11": 39,
    "12": 1,
    "15": 3,
    "22": 1,
    "23": 3,
    "24": 41,
    "52": 239,
    "62": 18,
    "76": 249,
    "79": 5,
    "80": 3,
    "94": 1,
    "100": 51,
    "101": 82,
    "102": 51,
    "103": 82,
    "105": 50,
    "106": 59
  },
  "activeFlags": [
    8,
    9,
    14,
    55,
    115,
    126,
    146,
    169,
    248
  ],
  "activeControllers": [],
  "itemRooms": {
    "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "9": 0,
    "10": 0, "11": 0, "12": 0, "13": 0, "14": 0, "15": 0, "16": 0, "17": 0, "18": 0, "19": 0,
    "20": 0, "21": 0, "22": 0, "23": 0, "24": 0, "25": 0, "26": 0, "27": 0, "28": 0, "29": 0,
    "30": 0, "31": 0, "32": 0, "33": 0, "34": 0, "35": 0, "36": 0, "37": 0, "38": 0, "39": 0,
    "40": 0, "41": 0, "42": 0, "43": 0, "44": 0, "45": 0, "46": 0, "47": 0, "48": 0, "49": 0,
    "50": 99, "51": 36, "52": 0, "53": 0, "54": 23, "55": 13, "56": 0, "57": 38, "58": 0, "59": 17,
    "60": 40, "61": 0, "62": 3, "63": 0, "64": 0, "65": 0, "66": 0, "67": 0, "68": 0, "69": 0,
    "70": 0, "71": 0, "72": 0, "73": 0, "74": 0, "75": 0, "76": 0, "77": 0, "78": 0, "79": 0,
    "80": 0, "81": 0, "82": 0, "83": 0, "84": 0
  },
  "strings": {
    "0": ">",
    "4": "Version 2.1"
  },
  "objects": [
    {
      "number": 0,
      "x": 51,
      "y": 82,
      "prevX": 52,
      "prevY": 82,
      "view": 0,
      "loop": 1,
      "cel": 4,
      "priority": 7,
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
      "targetX": 40,
      "targetY": 69,
      "stepDistance": 0,
      "ignoreHorizon": false,
      "ignoreBlocks": true,
      "ignoreObjects": false,
      "onWater": false,
      "onLand": true
    }
  ],
  "callStack": [],
  "scanStartIp": 0,
  "scanStarts": {},
  "isRoomTransition": false,
  "horizon": 36,
  "loadedLogics": [
    0,
    9,
    153,
    101,
    158,
    151
  ]
}''';

    GameStateSerializer.deserializeFromJson(jsonSnapshot, engine);

    // Run tick - engine should evaluate Flag 0
    await engine.tick();
    expect(engine.memory.getFlag(0), isTrue);
    expect(engine.ego.view, equals(104), reason: 'Ego should be in wading view 104');

    // Player types "swim"
    engine.submitCommand('swim');
    await engine.tick();
    expect(engine.ego.view, equals(97), reason: 'Ego should be in swimming view 97');

    // Player walks left into the river
    engine.setEgoDirection(7);
    for (int i = 0; i < 5; i++) {
      await engine.tick();
    }
    expect(engine.ego.x, lessThan(40), reason: 'Ego should have moved left into the river');
  });

  test("King's Quest 2 Room 34 swimming movement", () async {
    final possiblePaths = [
      r'c:\users\richa\gog\kings-quest-2',
      'reference_games/kings-quest-2',
      '/Users/rtodd/src/flutter_agigame/reference_games/kings-quest-2',
    ];
    final path = possiblePaths.firstWhere(
      (p) => Directory(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) return;

    final loader = AgiResourceLoader.fromDirectorySync(path);
    final engine = AgiGameEngine(resourceLoader: loader);
    await engine.initializeGame();

    const jsonSnapshot34 = '''{
  "version": "1.0",
  "timestamp": "2026-08-27T17:25:07.314133",
  "label": "Room 34 (Cycle 4309)",
  "roomNumber": 34,
  "pictureNumber": 34,
  "cycleCount": 4309,
  "speedHz": 20.0,
  "score": 2,
  "maxScore": 185,
  "soundOn": true,
  "isPaused": true,
  "isInputEnabled": true,
  "isUserControl": true,
  "isStatusLineEnabled": true,
  "statusRow": 0,
  "lastSubmittedCommand": "get mallet",
  "variables": {
    "0": 34,
    "1": 33,
    "3": 2,
    "7": 185,
    "8": 10,
    "10": 2,
    "11": 35,
    "12": 3,
    "15": 3,
    "16": 97,
    "22": 1,
    "23": 3,
    "24": 41,
    "52": 234,
    "62": 18,
    "76": 249,
    "79": 5,
    "80": 3,
    "94": 1,
    "95": 2,
    "100": 44,
    "101": 94,
    "102": 44,
    "103": 94,
    "106": 114
  },
  "activeFlags": [
    0,
    8,
    9,
    14,
    55,
    84,
    92,
    115,
    126,
    146,
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
    "50": 99,
    "51": 36,
    "52": 0,
    "53": 0,
    "54": 23,
    "55": 13,
    "56": 0,
    "57": 38,
    "58": 0,
    "59": 17,
    "60": 255,
    "61": 0,
    "62": 3,
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
    "84": 0
  },
  "strings": {
    "0": ">",
    "4": "Version 2.1"
  },
  "objects": [
    {
      "number": 0,
      "x": 44,
      "y": 94,
      "prevX": 45,
      "prevY": 94,
      "view": 97,
      "loop": 1,
      "cel": 7,
      "priority": 8,
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
      "cycleMode": 0,
      "motionType": 0,
      "targetX": 35,
      "targetY": 95,
      "stepDistance": 0,
      "ignoreHorizon": false,
      "ignoreBlocks": true,
      "ignoreObjects": false,
      "onWater": false,
      "onLand": true
    }
  ],
  "callStack": [],
  "scanStartIp": 0,
  "scanStarts": {},
  "isRoomTransition": false,
  "horizon": 36,
  "loadedLogics": [
    0,
    34,
    151,
    158,
    101
  ]
}''';

    GameStateSerializer.deserializeFromJson(jsonSnapshot34, engine);
    // Simulating entering Room 34 from Room 33
    engine.ego.resetForNewRoom();
    expect(engine.ego.onLand, isFalse);
    expect(engine.ego.onWater, isFalse);

    final priBuf = engine.currentPic?.priorityBuffer;
    for (int tx = 44; tx >= 30; tx--) {
      final can = CollisionDetector.objectCanBeHere(
        priorityBuffer: priBuf!,
        obj: engine.ego,
        x: tx,
        y: 94,
        width: engine.ego.getCelWidth(),
      );
      expect(can, isTrue, reason: 'Ego should be able to swim at x=$tx, y=94');
    }
  });
}
