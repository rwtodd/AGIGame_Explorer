import 'dart:io';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// User-captured SQ1 Room 16 state: spider droid has already finished its
/// priority-15 drop-in (`release.priority` + `object.on.land` + `wander`).
final _room16Json = <String, dynamic>{
  "version": "1.0",
  "timestamp": "2026-08-20T22:35:00.458500",
  "label": "Room 16 (Cycle 8428)",
  "roomNumber": 16,
  "pictureNumber": 16,
  "cycleCount": 8428,
  "speedHz": 20.0,
  "score": 37,
  "maxScore": 180,
  "soundOn": true,
  "isPaused": true,
  "isInputEnabled": true,
  "isUserControl": true,
  "isStatusLineEnabled": true,
  "statusRow": 0,
  "lastSubmittedCommand": "get rock",
  "variables": {
    "0": 16,
    "1": 15,
    "3": 37,
    "7": 180,
    "8": 10,
    "10": 2,
    "11": 55,
    "12": 5,
    "15": 3,
    "22": 1,
    "24": 41,
    "50": 3,
    "52": 1,
    "62": 153,
    "63": 76,
    "65": 82,
    "69": 3,
    "70": 3,
    "73": 2,
    "75": 7,
    "76": 7,
    "77": 1,
    "79": 9,
    "81": 1,
    "93": 137,
    "94": 1,
    "95": 1,
    "98": 1,
    "99": 77,
    "112": 1,
    "133": 249,
    "135": 55,
    "136": 103,
    "147": 147,
    "148": 52,
    "151": 95,
    "152": 59,
    "153": 95,
    "154": 59,
    "235": 67,
    "236": 1,
    "237": 2,
    "239": 166
  },
  "activeFlags": [
    8, 9, 14, 53, 54, 79, 80, 81, 92, 97, 101, 102, 153, 154, 155, 160, 162,
    163, 164, 182, 188, 191, 192, 193, 238, 241
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
      "x": 95,
      "y": 59,
      "prevX": 94,
      "prevY": 59,
      "view": 0,
      "loop": 0,
      "cel": 6,
      "priority": 5,
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
    },
    {
      "number": 16,
      "x": 104,
      "y": 111,
      "prevX": 96,
      "prevY": 119,
      "view": 46,
      "loop": 0,
      "cel": 2,
      "priority": 15,
      "fixedPriority": false,
      "fixedLoop": false,
      "direction": 2,
      "stepSize": 8,
      "stepTime": 1,
      "stepTimer": 1,
      "cycleTime": 1,
      "cycleTimer": 1,
      "isAnimated": true,
      "isDrawn": true,
      "isUpdating": true,
      "isCycling": true,
      "cycleMode": 0,
      "motionType": 1,
      "targetX": 80,
      "targetY": 155,
      "stepDistance": 8,
      "ignoreHorizon": false,
      "ignoreBlocks": false,
      "ignoreObjects": false,
      "onWater": false,
      "onLand": true
    }
  ],
  "callStack": <dynamic>[],
  "scanStartIp": 0,
  "scanStarts": <String, dynamic>{},
  "isRoomTransition": false,
  "horizon": 36,
  "loadedLogics": [0, 16, 107, 112, 110]
};

void main() {
  test('SQ1 room 16 spider droid observes control lines and screen bounds after release.priority',
      () async {
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

    final snapshot = AgiGameStateSnapshot.fromJson(_room16Json);
    snapshot.restore(engine, preservePauseState: false);
    engine.resume();

    final droid = engine.animatedObjects[16];
    expect(droid.isDrawn, isTrue);
    expect(droid.fixedPriority, isFalse);
    expect(droid.onLand, isTrue);
    expect(droid.motionType, 1);

    await engine.tick();
    expect(
      droid.priority,
      AnimatedObject.calculatePriorityForY(droid.y),
      reason: 'auto-priority must follow Y after the pri-15 drop-in',
    );
    expect(droid.priority, isNot(15));

    final priBuf = engine.currentPic!.priorityBuffer;
    var moved = false;
    final startX = droid.x;
    final startY = droid.y;

    for (var i = 0; i < 80; i++) {
      await engine.tick();
      if (droid.x != startX || droid.y != startY) moved = true;

      expect(droid.x, inInclusiveRange(0, 159), reason: 'tick $i x=${droid.x}');
      expect(
        droid.y,
        inInclusiveRange(engine.horizon + 1, 167),
        reason: 'tick $i y=${droid.y}',
      );

      final w = droid.getCelWidth();
      var onBarrier = false;
      var entirelyWater = true;
      var sawPixel = false;
      for (var bx = droid.x; bx < droid.x + w; bx++) {
        if (bx < 0 || bx >= 160) continue;
        sawPixel = true;
        final p = priBuf.priorityAt(bx, droid.y);
        if (p == 0 || (p == 1 && !droid.ignoreBlocks)) onBarrier = true;
        if (p != 3) entirelyWater = false;
      }
      expect(sawPixel, isTrue, reason: 'droid baseline fully off-screen at (${droid.x},${droid.y}) w=$w tick $i');
      expect(
        onBarrier,
        isFalse,
        reason: 'droid walked onto a control line at (${droid.x},${droid.y}) tick $i',
      );
      expect(
        entirelyWater,
        isFalse,
        reason: 'on.land droid stood entirely on water at (${droid.x},${droid.y}) tick $i',
      );
    }

    expect(moved, isTrue, reason: 'wander should still move the droid on land');
    engine.dispose();
  });
}
