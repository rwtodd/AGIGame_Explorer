import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

void main() {
  const userSnapshotJson = '''
{
  "version": "1.0",
  "timestamp": "2026-08-16T13:06:47.198030",
  "label": "Room 62 (Cycle 16597)",
  "roomNumber": 62,
  "cycleCount": 16597,
  "speedHz": 20.0,
  "score": 139,
  "maxScore": 185,
  "soundOn": true,
  "isPaused": false,
  "isInputEnabled": true,
  "isUserControl": true,
  "lastSubmittedCommand": "close chest",
  "variables": {
    "0": 62,
    "1": 63,
    "3": 139,
    "7": 185,
    "8": 10,
    "10": 2,
    "11": 20,
    "12": 32,
    "15": 3,
    "22": 1,
    "23": 3,
    "24": 41,
    "52": 249,
    "54": 5,
    "56": 6,
    "62": 40,
    "64": 2,
    "65": 1,
    "66": 11,
    "67": 11,
    "76": 249,
    "79": 5,
    "80": 3,
    "84": 3,
    "87": 3,
    "89": 114,
    "90": 30,
    "91": 2,
    "92": 2,
    "93": 1,
    "100": 127,
    "101": 126,
    "102": 127,
    "103": 126,
    "105": 80,
    "106": 81,
    "108": 2,
    "114": 43,
    "115": 91,
    "116": 51,
    "117": 103,
    "118": 3,
    "120": 117,
    "121": 117
  },
  "activeFlags": [
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
    68,
    69,
    70,
    72,
    73,
    74,
    75,
    82,
    84,
    85,
    86,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    104,
    106,
    109,
    110,
    111,
    112,
    126,
    129,
    133,
    134,
    137,
    138,
    139,
    140,
    141,
    143,
    146,
    151,
    153,
    154,
    156,
    157,
    158,
    159,
    160,
    169,
    176,
    230
  ],
  "activeControllers": [],
  "itemRooms": {},
  "strings": {},
  "objects": [
    {
      "number": 0,
      "x": 127,
      "y": 126,
      "prevX": 126,
      "prevY": 126,
      "view": 0,
      "loop": 0,
      "cel": 5,
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
      "ignoreBlocks": false,
      "ignoreObjects": true,
      "onWater": false,
      "onLand": true
    },
    {
      "number": 3,
      "x": 124,
      "y": 126,
      "prevX": 124,
      "prevY": 126,
      "view": 54,
      "loop": 0,
      "cel": 0,
      "priority": 11,
      "fixedPriority": true,
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
      "ignoreBlocks": false,
      "ignoreObjects": false,
      "onWater": false,
      "onLand": false
    }
  ],
  "callStack": [],
  "scanStartIp": 0
}
''';

  group('Sprite Z-Order & Sorting Tests', () {
    test('effectiveSortY maps fixed priority objects to top of priority band per Sierra OBJLIST.C', () {
      final objFixed = AnimatedObject(number: 3)
        ..priority = 11
        ..fixedPriority = true
        ..y = 126;

      final objAuto = AnimatedObject(number: 0)
        ..priority = 0
        ..fixedPriority = false
        ..y = 126;

      expect(objFixed.effectivePriority, 11);
      expect(objAuto.effectivePriority, 11);

      // Fixed priority 11 maps to Y = (11 - 5) * 12 + 48 = 120
      expect(objFixed.effectiveSortY, 120);
      // Auto priority uses actual baseline Y = 126
      expect(objAuto.effectiveSortY, 126);

      // Sorting order: objFixed (120) is drawn first (in back), objAuto (126) is drawn after (in front)
      expect(objFixed.effectiveSortY < objAuto.effectiveSortY, isTrue);
    });

    test('Room 62 restored snapshot has Ego sorting in front of fixed-priority chest', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final engine = AgiGameEngine(resourceLoader: loader);

      final snapshot = AgiGameStateSnapshot.fromJson(jsonDecode(userSnapshotJson) as Map<String, dynamic>);
      engine.restoreSnapshot(snapshot);

      final ego = engine.ego;
      final chest = engine.animatedObjects[3];

      expect(ego.effectiveSortY, 126);
      expect(chest.effectiveSortY, 120);
      expect(chest.effectiveSortY < ego.effectiveSortY, isTrue,
          reason: 'Chest must be drawn before Ego so Ego is rendered in front');
    });
  });
}
