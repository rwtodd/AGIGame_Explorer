import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

export 'package:flutter_agigame/core/display_profile.dart';

/// Decomposes visual and priority buffers into 320x200 Impeller-ready priority slices.
///
/// Supports both:
/// - Authentic 160x168 AGI ([DisplayProfile.agi]): horizontally doubled to 320x200,
///   where control lines (< 4) scan downwards to find underlying depth band.
/// - 320x200 SCI0 ([DisplayProfile.sci0]): 1:1 direct pixel writes, pure Z-buffer
///   indexing (`0..15`), with control lines kept in a separate third buffer.
class PictureSlicer {
  const PictureSlicer._();

  /// Slices the visual and priority buffers into a map of [PictureSlice] keyed by priority level.
  ///
  /// Either [priorityBuffer] or [priorityPixels] must be provided.
  /// Uses packed 32-bit writes and skips allocating full 256KB RGBA buffers for unused priority levels.
  static Map<int, PictureSlice> slice({
    required Uint8List visualPixels,
    PriorityBuffer? priorityBuffer,
    Uint8List? priorityPixels,
    DisplayProfile profile = DisplayProfile.agi,
    List<int> paletteRgbaPacked = EgaColors.rgbaPacked,
  }) {
    final priBytes = priorityPixels ?? priorityBuffer?.pixels;
    if (priBytes == null) {
      throw ArgumentError(
        'Either priorityBuffer or priorityPixels must be provided to PictureSlicer.slice',
      );
    }

    final srcWidth = profile.nativeWidth;
    final srcHeight = profile.nativeHeight;
    final dstWidth = profile.renderedWidth;
    final dstHeight = profile.renderedHeight;
    final horizontalDouble = profile.horizontalDouble;
    final scanControl = profile.scanControlLines;
    final bandCount = profile.priorityBandCount;

    // Lazily allocate 32-bit pixel views for active priority levels
    final sliceViews = List<Uint32List?>.filled(bandCount, null);

    // Optimized Path 1: Authentic AGI (160x168 -> 320x200, horizontal 2x doubling, downward scan)
    if (horizontalDouble && scanControl && priorityBuffer != null) {
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

          final packed = paletteRgbaPacked[vColor];
          final dstPixelOffset = dstRowOffset + (x * 2);
          targetView[dstPixelOffset] = packed;
          targetView[dstPixelOffset + 1] = packed;
        }
      }
    }
    // Optimized Path 2: Authentic SCI0 (320x200 1:1, pure Z-buffer, no downward scan)
    else if (!horizontalDouble && !scanControl) {
      for (int y = 0; y < srcHeight; y++) {
        final rowOffset = y * srcWidth;
        final dstRowOffset = y * dstWidth;

        for (int x = 0; x < srcWidth; x++) {
          final srcIdx = rowOffset + x;
          final targetPri = priBytes[srcIdx] & 0x0F;

          var targetView = sliceViews[targetPri];
          if (targetView == null) {
            targetView = Uint32List(dstWidth * dstHeight);
            sliceViews[targetPri] = targetView;
          }

          final rawColor = visualPixels[srcIdx];
          final vColor = rawColor < paletteRgbaPacked.length
              ? rawColor
              : (rawColor & 0x0F);
          targetView[dstRowOffset + x] = paletteRgbaPacked[vColor];
        }
      }
    }
    // Generalized Path: arbitrary profile combinations
    else {
      for (int y = 0; y < srcHeight; y++) {
        final rowOffset = y * srcWidth;
        final dstRowOffset = y * dstWidth;

        for (int x = 0; x < srcWidth; x++) {
          final srcIdx = rowOffset + x;
          final int rawPri;
          if (scanControl && priorityBuffer != null) {
            rawPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);
          } else {
            rawPri = priBytes[srcIdx] & 0x0F;
          }
          final targetPri = rawPri.clamp(0, bandCount - 1);

          var targetView = sliceViews[targetPri];
          if (targetView == null) {
            targetView = Uint32List(dstWidth * dstHeight);
            sliceViews[targetPri] = targetView;
          }

          final rawColor = visualPixels[srcIdx];
          final vColor = rawColor < paletteRgbaPacked.length
              ? rawColor
              : (rawColor & 0x0F);
          final packed = paletteRgbaPacked[vColor];

          if (horizontalDouble) {
            final dstPixelOffset = dstRowOffset + (x * 2);
            targetView[dstPixelOffset] = packed;
            targetView[dstPixelOffset + 1] = packed;
          } else {
            targetView[dstRowOffset + x] = packed;
          }
        }
      }
    }

    final resultMap = <int, PictureSlice>{};
    for (int p = 0; p < bandCount; p++) {
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
    PriorityBuffer? priorityBuffer,
    Uint8List? priorityPixels,
    required int priority,
    DisplayProfile profile = DisplayProfile.agi,
    List<int> paletteRgbaPacked = EgaColors.rgbaPacked,
  }) {
    final priBytes = priorityPixels ?? priorityBuffer?.pixels;
    if (priBytes == null) {
      throw ArgumentError(
        'Either priorityBuffer or priorityPixels must be provided to PictureSlicer.sliceSinglePriority',
      );
    }

    final srcWidth = profile.nativeWidth;
    final srcHeight = profile.nativeHeight;
    final dstWidth = profile.renderedWidth;
    final dstHeight = profile.renderedHeight;
    final horizontalDouble = profile.horizontalDouble;
    final scanControl = profile.scanControlLines;

    Uint32List? targetView;

    // Fast path: Authentic AGI
    if (horizontalDouble && scanControl && priorityBuffer != null) {
      for (int y = 0; y < srcHeight; y++) {
        final rowOffset = y * srcWidth;
        final dstRowOffset = y * dstWidth;

        for (int x = 0; x < srcWidth; x++) {
          final srcIdx = rowOffset + x;
          final targetPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);
          if (targetPri == priority) {
            targetView ??= Uint32List(dstWidth * dstHeight);
            final vColor = visualPixels[srcIdx] & 0x0F;
            final packed = paletteRgbaPacked[vColor];
            final dstPixelOffset = dstRowOffset + (x * 2);
            targetView[dstPixelOffset] = packed;
            targetView[dstPixelOffset + 1] = packed;
          }
        }
      }
    }
    // Fast path: Authentic SCI0
    else if (!horizontalDouble && !scanControl) {
      for (int y = 0; y < srcHeight; y++) {
        final rowOffset = y * srcWidth;
        final dstRowOffset = y * dstWidth;

        for (int x = 0; x < srcWidth; x++) {
          final srcIdx = rowOffset + x;
          final targetPri = priBytes[srcIdx] & 0x0F;
          if (targetPri == priority) {
            targetView ??= Uint32List(dstWidth * dstHeight);
            final rawColor = visualPixels[srcIdx];
            final vColor = rawColor < paletteRgbaPacked.length
                ? rawColor
                : (rawColor & 0x0F);
            targetView[dstRowOffset + x] = paletteRgbaPacked[vColor];
          }
        }
      }
    }
    // Generalized path
    else {
      for (int y = 0; y < srcHeight; y++) {
        final rowOffset = y * srcWidth;
        final dstRowOffset = y * dstWidth;

        for (int x = 0; x < srcWidth; x++) {
          final srcIdx = rowOffset + x;
          final int rawPri;
          if (scanControl && priorityBuffer != null) {
            rawPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);
          } else {
            rawPri = priBytes[srcIdx] & 0x0F;
          }

          if (rawPri == priority) {
            targetView ??= Uint32List(dstWidth * dstHeight);
            final rawColor = visualPixels[srcIdx];
            final vColor = rawColor < paletteRgbaPacked.length
                ? rawColor
                : (rawColor & 0x0F);
            final packed = paletteRgbaPacked[vColor];
            if (horizontalDouble) {
              final dstPixelOffset = dstRowOffset + (x * 2);
              targetView[dstPixelOffset] = packed;
              targetView[dstPixelOffset + 1] = packed;
            } else {
              targetView[dstRowOffset + x] = packed;
            }
          }
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
