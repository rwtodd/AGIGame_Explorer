import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

void main() {
  group('Priority 15 Foreground Occlusion Tests', () {
    test('King\'s Quest II Room 59 has priority 15 foreground pillar/wall in slice 15', () {
      final kq2Dir = Directory('reference_games/kings-quest-2');
      if (!kq2Dir.existsSync()) return;

      final loader = AgiResourceLoader.fromDirectorySync(kq2Dir.path);
      final pic59 = loader.loadPic(59);

      // At x=129, y=159 (where Ego walks), the priority is 15 (foreground wall)
      expect(pic59.priorityBuffer.priorityAt(129, 159), 15);

      final slices = PictureSlicer.slice(
        visualPixels: pic59.visualPixels,
        priorityBuffer: pic59.priorityBuffer,
      );

      final slice15 = slices[15]!;
      expect(slice15.hasVisiblePixels, isTrue, reason: 'Slice 15 must contain foreground wall pixels');

      // The pixel at (129, 159) corresponds to x=258, y=159 in 320x200 slice
      final offset = (159 * 320 + (129 * 2)) * 4;
      final alpha = slice15.rgbaBytes[offset + 3];
      expect(alpha, 255, reason: 'Foreground pillar pixel at (129, 159) must be opaque in slice 15');
    });

    test('PictureSlicer correctly isolates Priority 15 foreground from background depth bands', () {
      final visual = Uint8List(160 * 168);
      final pri = PriorityBuffer();

      // Background horizon at y=20 (pri 4, blue)
      for (int x = 0; x < 160; x++) {
        pri.setPriorityAt(x, 20, 4);
        visual[20 * 160 + x] = 1; // Blue
      }

      // Foreground archway/pillar at (50..60, 100..150) with pri 15 (white)
      for (int y = 100; y <= 150; y++) {
        for (int x = 50; x <= 60; x++) {
          pri.setPriorityAt(x, y, 15);
          visual[y * 160 + x] = 15; // White
        }
      }

      final slices = PictureSlicer.slice(
        visualPixels: visual,
        priorityBuffer: pri,
      );

      expect(slices[4]!.hasVisiblePixels, isTrue);
      expect(slices[15]!.hasVisiblePixels, isTrue);
      expect(slices[14]!.hasVisiblePixels, isFalse);

      // Check that slice 15 contains the pillar pixels
      final slice15Bytes = slices[15]!.rgbaBytes;
      final offset = (120 * 320 + 100) * 4; // (50*2=100, 120)
      expect(slice15Bytes[offset + 3], 255);
    });
  });
}
