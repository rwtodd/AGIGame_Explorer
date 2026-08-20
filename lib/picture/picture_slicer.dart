import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

/// Decomposes flat 160x168 AGI visual and priority buffers into 320x200 Impeller-ready priority slices.
///
/// In accordance with the Impeller Painter's Algorithm strategy:
/// 1. Slices are standardized on 320x200 (pixel-doubled horizontally from 160 units).
/// 2. Playfield occupies lines 0 to 167; lines 168 to 199 remain transparent.
/// 3. Priorities 4 to 14 represent progressive depth bands from background (4) to foreground (14).
/// 4. Priority 15 represents the absolute foreground overlay band (pillars, foreground walls, overlays).
/// 5. Control line pixels (< 4) have their visual color assigned to the underlying effective
///    depth priority slice so actors walking near or over them are occluded accurately.
class PictureSlicer {
  const PictureSlicer._();

  /// Slices the visual and priority buffers into a map of [PictureSlice] keyed by priority level (0..15).
  ///
  /// Uses packed 32-bit writes and skips allocating full 256KB RGBA buffers for unused priority levels.
  static Map<int, PictureSlice> slice({
    required Uint8List visualPixels,
    required PriorityBuffer priorityBuffer,
  }) {
    const srcWidth = AgiDisplay.nativeWidth; // 160
    const srcHeight = AgiDisplay.pictureHeight; // 168
    const dstWidth = AgiDisplay.renderedWidth; // 320
    const dstHeight = AgiDisplay.renderedHeight; // 200

    // Lazily allocate 32-bit pixel views for active priority levels
    final sliceViews = List<Uint32List?>.filled(16, null);

    // Decompose pixels into priority slices with 32-bit packed writes
    for (int y = 0; y < srcHeight; y++) {
      final rowOffset = y * srcWidth;
      final dstRowOffset = y * dstWidth;

      for (int x = 0; x < srcWidth; x++) {
        final srcIdx = rowOffset + x;
        final vColor = visualPixels[srcIdx] & 0x0F;
        final targetPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);

        var targetView = sliceViews[targetPri];
        if (targetView == null) {
          targetView = Uint32List(dstWidth * dstHeight);
          sliceViews[targetPri] = targetView;
        }

        final packed = EgaColors.rgbaPacked[vColor];

        // Pixel-doubling: write two 32-bit packed RGBA values horizontally
        final dstPixelOffset = dstRowOffset + (x * 2);
        targetView[dstPixelOffset] = packed;
        targetView[dstPixelOffset + 1] = packed;
      }
    }

    final resultMap = <int, PictureSlice>{};
    for (int p = 0; p < 16; p++) {
      final view = sliceViews[p];
      if (view != null) {
        resultMap[p] = PictureSlice(
          priority: p,
          width: dstWidth,
          height: dstHeight,
          rgbaBytes: Uint8List.view(view.buffer),
          hasVisiblePixels: true,
        );
      } else {
        resultMap[p] = PictureSlice(
          priority: p,
          width: dstWidth,
          height: dstHeight,
          rgbaBytes: Uint8List(0),
          hasVisiblePixels: false,
        );
      }
    }

    return resultMap;
  }

  /// Slices a single priority level from visual and priority buffers.
  /// Used by incremental `add.to.pic` to avoid full 16-layer reslicing.
  static PictureSlice sliceSinglePriority({
    required Uint8List visualPixels,
    required PriorityBuffer priorityBuffer,
    required int priority,
  }) {
    const srcWidth = AgiDisplay.nativeWidth; // 160
    const srcHeight = AgiDisplay.pictureHeight; // 168
    const dstWidth = AgiDisplay.renderedWidth; // 320
    const dstHeight = AgiDisplay.renderedHeight; // 200

    Uint32List? targetView;
    for (int y = 0; y < srcHeight; y++) {
      final rowOffset = y * srcWidth;
      final dstRowOffset = y * dstWidth;

      for (int x = 0; x < srcWidth; x++) {
        final srcIdx = rowOffset + x;
        final targetPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);
        if (targetPri == priority) {
          targetView ??= Uint32List(dstWidth * dstHeight);
          final vColor = visualPixels[srcIdx] & 0x0F;
          final packed = EgaColors.rgbaPacked[vColor];
          final dstPixelOffset = dstRowOffset + (x * 2);
          targetView[dstPixelOffset] = packed;
          targetView[dstPixelOffset + 1] = packed;
        }
      }
    }

    if (targetView == null) {
      return PictureSlice(
        priority: priority,
        width: dstWidth,
        height: dstHeight,
        rgbaBytes: Uint8List(0),
        hasVisiblePixels: false,
      );
    }

    return PictureSlice(
      priority: priority,
      width: dstWidth,
      height: dstHeight,
      rgbaBytes: Uint8List.view(targetView.buffer),
      hasVisiblePixels: true,
    );
  }
}
