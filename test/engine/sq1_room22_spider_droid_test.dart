import 'dart:io';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// User-captured SQ1 Room 22 state one tick before Ego is erased.
/// The spider droid (o16) is `follow.ego` at x=164 — fully off the 160-wide
/// playfield — while Ego is ~80px to the west.
final _room22Json = <String, dynamic>{
  "version": "1.0",
  "timestamp": "2026-08-20T23:51:38.351901",
  "label": "Room 22 (Cycle 102)",
  "roomNumber": 22,
  "pictureNumber": 22,
  "cycleCount": 102,
  "speedHz": 10.0,
  "score": 51,
  "maxScore": 180,
  "soundOn": true,
  "isPaused": true,
  "isInputEnabled": true,
  "isUserControl": true,
  "isStatusLineEnabled": true,
  "statusRow": 0,
  "lastSubmittedCommand": "",
  "variables": {
    "0": 22,
    "1": 23,
    "3": 51,
    "6": 7,
    "7": 180,
    "8": 10,
    "10": 3,
    "11": 56,
    "12": 7,
    "15": 3,
    "22": 1,
    "24": 41,
    "50": 3,
    "52": 1,
    "62": 153,
    "63": 144,
    "65": 82,
    "69": 3,
    "70": 3,
    "73": 2,
    "75": 7,
    "76": 7,
    "77": 1,
    "81": 1,
    "82": 1,
    "93": 172,
    "94": 1,
    "95": 1,
    "98": 153,
    "99": 144,
    "100": 23,
    "112": 3,
    "133": 249,
    "135": 153,
    "136": 42,
    "147": 95,
    "148": 44,
    "150": 7,
    "151": 81,
    "152": 144,
    "153": 81,
    "154": 144,
    "235": 1,
    "237": 2,
    "239": 181
  },
  "activeFlags": [
    8, 9, 14, 53, 54, 79, 80, 81, 84, 97, 102, 121, 153, 154, 155, 160, 162,
    163, 164, 177, 178, 182, 188, 191, 192, 193, 194, 198, 241
  ],
  "activeControllers": <int>[],
  "itemRooms": {
    "0": 0, "1": 255, "2": 0, "3": 255, "4": 0, "5": 255, "6": 255, "7": 0,
    "8": 0, "9": 0, "10": 0, "11": 0, "12": 255, "13": 0, "14": 0, "15": 0,
    "16": 0, "17": 0, "18": 0, "19": 255, "20": 0, "21": 0, "22": 255, "23": 0,
    "24": 0
  },
  "strings": {"0": ">", "1": "Richie", "2": "astral body", "4": "Version 2.2"},
  "objects": [
    {
      "number": 0,
      "x": 81,
      "y": 144,
      "prevX": 82,
      "prevY": 144,
      "view": 0,
      "loop": 1,
      "cel": 3,
      "priority": 13,
      "fixedPriority": false,
      "fixedLoop": false,
      "direction": 7,
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
      "number": 16,
      "x": 164,
      "y": 139,
      "prevX": 153,
      "prevY": 144,
      "view": 46,
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
      "cycleMode": 0,
      "motionType": 2,
      "targetX": 0,
      "targetY": 0,
      "stepDistance": 10,
      "targetFlag": 235,
      "ignoreHorizon": false,
      "ignoreBlocks": false,
      "ignoreObjects": false,
      "onWater": false,
      "onLand": false
    }
  ],
  "callStack": <dynamic>[],
  "scanStartIp": 0,
  "scanStarts": <String, dynamic>{},
  "isRoomTransition": false,
  "horizon": 70,
  "loadedLogics": [0, 22, 112, 110]
};

void main() {
  test('SQ1 room 22 spider droid off the right edge does not instantly catch Ego', () async {
    final sq1Dir = Directory('reference_games/space-quest-1');
    if (!sq1Dir.existsSync()) {
      markTestSkipped('SQ1 reference game not present');
      return;
    }

    final loader = AgiResourceLoader.fromDirectorySync(sq1Dir.path);
    final engine = AgiGameEngine(
      resourceLoader: loader,
      speedHz: 20,
      randomSeed: 42,
    );
    await engine.initializeGame();

    final snapshot = AgiGameStateSnapshot.fromJson(_room22Json);
    snapshot.restore(engine, preservePauseState: false);
    engine.resume();

    final ego = engine.ego;
    final droid = engine.animatedObjects[16];
    expect(ego.isDrawn, isTrue);
    expect(droid.isDrawn, isTrue);
    expect(droid.motionType, 2);
    expect(droid.x, 164, reason: 'captured state is fully off the 160-wide playfield');
    expect(droid.x + droid.getCelWidth(), greaterThan(160));
    expect(engine.memory.getFlag(235), isFalse);
    expect(engine.memory.getFlag(158), isFalse);

    await engine.tick();

    expect(
      engine.memory.getFlag(158),
      isFalse,
      reason: 'LOGIC 110 must not see a false follow.ego catch from the screen edge',
    );
    expect(ego.isDrawn, isTrue, reason: 'Ego must not be erased while 80px away');
    expect(droid.view, 46, reason: 'droid must not switch to explosion view 69');
    expect(droid.motionType, 2);
    expect(droid.x, greaterThanOrEqualTo(0));
    expect(
      droid.x + droid.getCelWidth(),
      lessThanOrEqualTo(160),
      reason: 'clamping onto the right edge should make the droid visible',
    );

    engine.dispose();
  });
}
