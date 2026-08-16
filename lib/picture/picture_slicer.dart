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
  static Map<int, PictureSlice> slice({
    required Uint8List visualPixels,
    required PriorityBuffer priorityBuffer,
  }) {
    const srcWidth = AgiDisplay.nativeWidth; // 160
    const srcHeight = AgiDisplay.pictureHeight; // 168
    const dstWidth = AgiDisplay.renderedWidth; // 320
    const dstHeight = AgiDisplay.renderedHeight; // 200
    const sliceByteCount = dstWidth * dstHeight * 4;

    // Allocate RGBA buffers for all 16 priority levels (0 to 15)
    final sliceBuffers = List<Uint8List>.generate(
      16,
      (_) => Uint8List(sliceByteCount),
      growable: false,
    );
    final hasVisible = List<bool>.filled(16, false);

    // Decompose pixels into priority slices
    for (int y = 0; y < srcHeight; y++) {
      final rowOffset = y * srcWidth;
      final dstRowOffset = y * dstWidth * 4;

      for (int x = 0; x < srcWidth; x++) {
        final srcIdx = rowOffset + x;
        final vColor = visualPixels[srcIdx] & 0x0F;
        final targetPri = priorityBuffer.effectivePriorityAtIndex(srcIdx);

        final targetBuffer = sliceBuffers[targetPri];
        hasVisible[targetPri] = true;

        final col = EgaColors.rgbaBytes[vColor];

        // Pixel-doubling: write two 4-byte RGBA pixels horizontally
        final dstOffset1 = dstRowOffset + (x * 2 * 4);
        final dstOffset2 = dstOffset1 + 4;

        targetBuffer[dstOffset1 + 0] = col[0];
        targetBuffer[dstOffset1 + 1] = col[1];
        targetBuffer[dstOffset1 + 2] = col[2];
        targetBuffer[dstOffset1 + 3] = col[3];

        targetBuffer[dstOffset2 + 0] = col[0];
        targetBuffer[dstOffset2 + 1] = col[1];
        targetBuffer[dstOffset2 + 2] = col[2];
        targetBuffer[dstOffset2 + 3] = col[3];
      }
    }

    final resultMap = <int, PictureSlice>{};
    for (int p = 0; p < 16; p++) {
      resultMap[p] = PictureSlice(
        priority: p,
        width: dstWidth,
        height: dstHeight,
        rgbaBytes: sliceBuffers[p],
        hasVisiblePixels: hasVisible[p],
      );
    }

    return resultMap;
  }
}
