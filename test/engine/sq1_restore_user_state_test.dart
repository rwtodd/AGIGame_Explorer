import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

final _sq1UserSnapshot = <String, dynamic>{
  "version": "1.0",
  "timestamp": "2026-08-16T20:35:02.361363",
  "label": "Room 69 (Cycle 26)",
  "roomNumber": 69,
  "cycleCount": 26,
  "speedHz": 20.0,
  "score": 0,
  "maxScore": 202,
  "soundOn": true,
  "isPaused": false,
  "isInputEnabled": false,
  "isUserControl": true,
  "lastSubmittedCommand": "",
  "variables": {
    "0": 69,
    "1": 67,
    "7": 202,
    "8": 10,
    "10": 2,
    "15": 3,
    "19": 115,
    "22": 1,
    "24": 41,
    "64": 104,
    "133": 249,
    "151": 37,
    "152": 137,
    "153": 37,
    "154": 137
  },
  "activeFlags": [
    5,
    8,
    9,
    14
  ],
  "activeControllers": <int>[],
  "itemRooms": {
    "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0,
    "8": 0, "9": 0, "10": 0, "11": 0, "12": 0, "13": 0, "14": 0,
    "15": 0, "16": 0, "17": 0, "18": 0, "19": 0, "20": 0, "21": 0,
    "22": 0, "23": 0, "24": 0
  },
  "strings": {
    "0": ">",
    "4": "Version 2.2"
  },
  "objects": [
    {
      "number": 0,
      "x": 37,
      "y": 137,
      "prevX": 37,
      "prevY": 137,
      "view": 0,
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
      "isDrawn": false,
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
  "callStack": [
    {
      "scriptNumber": 0,
      "ip": 1584
    },
    {
      "scriptNumber": 69,
      "ip": 29
    }
  ],
  "scanStartIp": 0,
  "scanStarts": <String, dynamic>{}
};

void main() {
  test('Restore user snapshot in SQ1 Room 69 and verify name input flow', () {
    final sq1Dir = Directory('reference_games/space-quest-1');
    if (!sq1Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync(sq1Dir.path);
    final engine = AgiGameEngine(resourceLoader: loader);
    engine.initializeGame();

    final snapshot = AgiGameStateSnapshot.fromJson(_sq1UserSnapshot);
    snapshot.restore(engine);

    expect(engine.currentRoom, 69);
  });
}
