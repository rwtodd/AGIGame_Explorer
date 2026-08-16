import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/engine/motion/collision_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CollisionDetector', () {
    late PriorityBuffer priorityBuffer;
    late CollisionDetector detector;
    late AgiMemory memory;
    late AnimatedObject ego;
    late AnimatedObject npc;

    setUp(() {
      priorityBuffer = PriorityBuffer(); // Default priority 4
      detector = CollisionDetector(
        priorityBuffer: priorityBuffer,
        horizon: 36,
      );
      memory = AgiMemory();
      ego = AnimatedObject(number: 0)
        ..isAnimated = true
        ..isDrawn = true;
      npc = AnimatedObject(number: 1)
        ..isAnimated = true
        ..isDrawn = true;
    });

    group('Priority Buffer Barrier Collision', () {
      test('unconditional barrier (priority 0) blocks baseline', () {
        // Draw priority 0 line at y=50, x=10..20
        for (var x = 10; x <= 20; x++) {
          priorityBuffer.setPriorityAt(x, 50, 0);
        }
        // Draw priority 2 (trigger) line at y=60, x=10..20
        for (var x = 10; x <= 20; x++) {
          priorityBuffer.setPriorityAt(x, 60, 2);
        }

        // Test over priority 0 (unconditional obstacle -> blocked)
        expect(
          detector.isBaselineBlocked(x: 12, y: 50, width: 4),
          isTrue,
        );

        // Test over priority 2 (trigger line -> NOT blocked)
        expect(
          detector.isBaselineBlocked(x: 12, y: 60, width: 4),
          isFalse,
        );

        // Test clear area (default priority 4)
        expect(
          detector.isBaselineBlocked(x: 12, y: 55, width: 4),
          isFalse,
        );
      });

      test('conditional barrier (priority 1) blocks unless ignoreBlocks is active', () {
        for (var x = 10; x <= 20; x++) {
          priorityBuffer.setPriorityAt(x, 50, 1);
        }

        // With ignoreBlocks = false -> blocked
        expect(
          detector.isBaselineBlocked(x: 12, y: 50, width: 4, ignoreBlocks: false),
          isTrue,
        );

        // With ignoreBlocks = true -> allowed
        expect(
          detector.isBaselineBlocked(x: 12, y: 50, width: 4, ignoreBlocks: true),
          isFalse,
        );
      });

      test('ignoreBlocks bypasses conditional barriers and script blocks', () {
        for (var x = 10; x <= 20; x++) {
          priorityBuffer.setPriorityAt(x, 50, 1);
        }
        detector.setBlock(10, 70, 30, 80);

        expect(
          detector.isBaselineBlocked(x: 12, y: 50, width: 4, ignoreBlocks: true),
          isFalse,
        );
        expect(
          detector.isBaselineBlocked(x: 15, y: 75, width: 4, ignoreBlocks: true),
          isFalse,
        );
      });

      test('unconditional barrier (priority 0) blocks even when ignoreBlocks is true', () {
        for (var x = 10; x <= 20; x++) {
          priorityBuffer.setPriorityAt(x, 50, 0);
        }

        // Even with ignoreBlocks = true, priority 0 MUST block!
        expect(
          detector.isBaselineBlocked(x: 12, y: 50, width: 4, ignoreBlocks: true),
          isTrue,
        );

        // Also via isPositionBlocked
        ego.ignoreBlocks = true;
        expect(
          detector.isPositionBlocked(obj: ego, x: 12, y: 50, width: 4, height: 10),
          isTrue,
        );
      });
    });

    group('Script Block Area (block and unblock)', () {
      test('setBlock and unblock dynamically restricts walkability', () {
        detector.setBlock(20, 40, 60, 80);

        expect(
          detector.isBaselineBlocked(x: 25, y: 50, width: 4),
          isTrue,
        );
        // Outside the block area
        expect(
          detector.isBaselineBlocked(x: 10, y: 50, width: 4),
          isFalse,
        );

        detector.unblock();
        expect(
          detector.isBaselineBlocked(x: 25, y: 50, width: 4),
          isFalse,
        );
      });
    });

    group('Screen Boundaries & Horizon', () {
      test('clamps coordinates to valid screen boundaries and horizon', () {
        ego.x = -10;
        ego.y = 20; // Above horizon (36)
        final (clampedX, clampedY) = detector.clampToScreenBounds(
          obj: ego,
          x: ego.x,
          y: ego.y,
          width: 8,
        );

        expect(clampedX, equals(0));
        expect(clampedY, equals(36));

        // Right / bottom overflow
        ego.x = 200;
        ego.y = 200;
        final (clampedX2, clampedY2) = detector.clampToScreenBounds(
          obj: ego,
          x: ego.x,
          y: ego.y,
          width: 8,
        );

        expect(clampedX2, equals(160 - 8)); // 152
        expect(clampedY2, equals(167));
      });

      test('ignoreHorizon allows moving above horizon', () {
        ego.ignoreHorizon = true;
        final (clampedX, clampedY) = detector.clampToScreenBounds(
          obj: ego,
          x: 50,
          y: 10,
          width: 8,
        );

        expect(clampedX, equals(50));
        expect(clampedY, equals(10));
      });

      test('isPositionBlocked checks horizon and screen bounds', () {
        expect(
          detector.isPositionBlocked(
            obj: ego,
            x: 50,
            y: 30, // Above horizon (36)
            width: 8,
            height: 10,
          ),
          isTrue,
        );

        ego.ignoreHorizon = true;
        expect(
          detector.isPositionBlocked(
            obj: ego,
            x: 50,
            y: 30,
            width: 8,
            height: 10,
          ),
          isFalse,
        );
      });
    });

    group('Screen Border Edge Detection and Memory Variables', () {
      test('detects border hits in order of AGI edge codes', () {
        // Top (1)
        expect(
          detector.checkBorderHit(x: 50, y: 36, width: 8),
          equals(AgiBorderEdge.top),
        );
        // Right (2)
        expect(
          detector.checkBorderHit(x: 152, y: 80, width: 8),
          equals(AgiBorderEdge.right),
        );
        // Bottom (3)
        expect(
          detector.checkBorderHit(x: 50, y: 167, width: 8),
          equals(AgiBorderEdge.bottom),
        );
        // Left (4)
        expect(
          detector.checkBorderHit(x: 0, y: 80, width: 8),
          equals(AgiBorderEdge.left),
        );
        // None (0)
        expect(
          detector.checkBorderHit(x: 50, y: 80, width: 8),
          equals(AgiBorderEdge.none),
        );
      });

      test('processBorderHit updates variable 2 for Ego', () {
        ego.x = 152;
        ego.y = 80;
        detector.processBorderHit(obj: ego, memory: memory, width: 8);
        expect(memory.getVar(2), equals(AgiBorderEdge.right));

        ego.x = 0;
        detector.processBorderHit(obj: ego, memory: memory, width: 8);
        expect(memory.getVar(2), equals(AgiBorderEdge.left));
      });

      test('processBorderHit updates variables 4 and 5 for NPC objects', () {
        npc.x = 50;
        npc.y = 167;
        detector.processBorderHit(obj: npc, memory: memory, width: 8);

        expect(memory.getVar(4), equals(1)); // NPC Object 1
        expect(memory.getVar(5), equals(AgiBorderEdge.bottom)); // Bottom (3)
      });
    });

    group('Object-to-Object Collisions', () {
      test('detects collision when two actors overlap', () {
        ego.x = 50;
        ego.y = 80;
        npc.x = 52;
        npc.y = 80;

        expect(
          detector.checkObjectCollision(ego, 50, 80, 8, 12, npc, 52, 80, 8, 12),
          isTrue,
        );

        // When far away
        expect(
          detector.checkObjectCollision(ego, 50, 80, 8, 12, npc, 100, 80, 8, 12),
          isFalse,
        );
      });

      test('ignoreObjects bypasses actor collision', () {
        ego.x = 50;
        ego.y = 80;
        npc.x = 50;
        npc.y = 80;
        ego.ignoreObjects = true;

        expect(
          detector.checkObjectCollision(ego, 50, 80, 8, 12, npc, 50, 80, 8, 12),
          isFalse,
        );
      });
    });

    group('Water & Signal Detection', () {
      test('isWaterAtBaseline detects when baseline is entirely on priority 3 water', () {
        // Draw water from x=15..25, y=100
        for (var x = 15; x <= 25; x++) {
          priorityBuffer.setPriorityAt(x, 100, 3);
        }

        // Entirely on water (x=16..20, width=5)
        expect(
          detector.isWaterAtBaseline(x: 16, y: 100, width: 5),
          isTrue,
        );
        // Partially on water (x=12..16, width=5 -> x=12, 13, 14 not water)
        expect(
          detector.isWaterAtBaseline(x: 12, y: 100, width: 5),
          isFalse,
        );
        // Completely off water
        expect(
          detector.isWaterAtBaseline(x: 30, y: 100, width: 5),
          isFalse,
        );
      });

      test('isSignalAtBaseline detects trigger control lines (priority 2)', () {
        priorityBuffer.setPriorityAt(40, 120, 2);

        expect(
          detector.isSignalAtBaseline(x: 38, y: 120, width: 5),
          isTrue,
        );
        expect(
          detector.isSignalAtBaseline(x: 50, y: 120, width: 5),
          isFalse,
        );
      });
    });
  });
}
