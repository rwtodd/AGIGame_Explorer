import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';
import 'package:flutter_agigame/picture/pic_pen.dart';
import 'package:flutter_agigame/picture/pic_rasterizer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// Interpreter for Sierra AGI PICTURE vector drawing bytecode.
///
/// Interprets drawing opcodes (0xF0 to 0xFA) into 160x168 visual and priority raster buffers,
/// and decomposes the result into Impeller-ready 320x200 priority slices.
class PicVectorInterpreter {
  final bool isV3;

  PicVectorInterpreter({this.isV3 = false});

  /// Interprets raw PICTURE resource bytes [data] and returns an [AgiPic].
  AgiPic interpret(Uint8List data) {
    const totalPixels = AgiDisplay.nativeWidth * AgiDisplay.pictureHeight; // 26,880

    // Initial state: visual screen clears to white (15), priority clears to 4
    final visualBuffer = Uint8List(totalPixels);
    visualBuffer.fillRange(0, totalPixels, 15);

    final priorityBuffer = PriorityBuffer();

    int picColor = -1; // -1 means visual drawing disabled
    int priColor = -1; // -1 means priority drawing disabled

    final rectanglePen = RectanglePen()..size = 0;
    final circlePen = (isV3 ? V3CirclePen() : CirclePen())..size = 0;
    PicPen currentPen = rectanglePen;

    final splatterPattern = SplatterPattern();
    PenPattern currentPattern = SolidPenPattern.instance;

    void plotPoint(int x, int y) {
      if (x < 0 ||
          x >= AgiDisplay.nativeWidth ||
          y < 0 ||
          y >= AgiDisplay.pictureHeight) {
        return;
      }
      final idx = y * AgiDisplay.nativeWidth + x;
      if (picColor != -1) {
        visualBuffer[idx] = picColor;
      }
      if (priColor != -1) {
        priorityBuffer.pixels[idx] = priColor;
      }
    }

    void drawLine(int x1, int y1, int x2, int y2) {
      PicRasterizer.drawLine(x1, y1, x2, y2, plotPoint);
    }

    void fill(int startX, int startY) {
      PicRasterizer.scanlineFill(
        startX: startX,
        startY: startY,
        visualBuffer: visualBuffer,
        priorityBuffer: priorityBuffer,
        picColor: picColor,
        priColor: priColor,
        plotPoint: plotPoint,
      );
    }

    int clipX(int x) => x < 0
        ? 0
        : (x >= AgiDisplay.nativeWidth ? AgiDisplay.nativeWidth - 1 : x);
    int clipY(int y) => y < 0
        ? 0
        : (y >= AgiDisplay.pictureHeight ? AgiDisplay.pictureHeight - 1 : y);

    int idx = 0;
    while (idx < data.length) {
      final opcode = data[idx++] & 0xFF;
      switch (opcode) {
        case 0xF0: // Set visual color & enable visual draw
          if (idx < data.length) {
            picColor = data[idx++] & 0x0F;
          }
          break;

        case 0xF1: // Disable visual draw
          picColor = -1;
          break;

        case 0xF2: // Set priority color & enable priority draw
          if (idx < data.length) {
            priColor = data[idx++] & 0x0F;
          }
          break;

        case 0xF3: // Disable priority draw
          priColor = -1;
          break;

        case 0xF4: // Draw Y corner (vertical then horizontal alternating)
          {
            if (idx >= data.length) break;
            int x = data[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            x = clipX(x);
            y = clipY(y);

            int x2 = x;
            int y2 = y;
            bool drewLine = false;
            bool changeY = true;

            while (idx < data.length) {
              final nextCoord = data[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              if (changeY) {
                y2 = clipY(nextCoord);
              } else {
                x2 = clipX(nextCoord);
              }
              drawLine(x, y, x2, y2);
              drewLine = true;
              changeY = !changeY;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              plotPoint(x, y);
            }
          }
          break;

        case 0xF5: // Draw X corner (horizontal then vertical alternating)
          {
            if (idx >= data.length) break;
            int x = data[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            x = clipX(x);
            y = clipY(y);

            int x2 = x;
            int y2 = y;
            bool drewLine = false;
            bool changeY = false;

            while (idx < data.length) {
              final nextCoord = data[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              if (changeY) {
                y2 = clipY(nextCoord);
              } else {
                x2 = clipX(nextCoord);
              }
              drawLine(x, y, x2, y2);
              drewLine = true;
              changeY = !changeY;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              plotPoint(x, y);
            }
          }
          break;

        case 0xF6: // Absolute lines
          {
            if (idx >= data.length) break;
            int x = data[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            x = clipX(x);

            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = clipY(y);

            bool drewLine = false;

            while (idx < data.length) {
              int x2 = data[idx++];
              if (x2 >= 0xF0) {
                idx--;
                break;
              }
              x2 = clipX(x2);

              if (idx >= data.length) break;
              int y2 = data[idx++];
              if (y2 >= 0xF0) {
                idx--;
                break;
              }
              y2 = clipY(y2);

              drawLine(x, y, x2, y2);
              drewLine = true;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              plotPoint(x, y);
            }
          }
          break;

        case 0xF7: // Relative lines
          {
            if (idx >= data.length) break;
            int x = data[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            x = clipX(x);

            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = clipY(y);

            bool drewLine = false;

            while (idx < data.length) {
              final relmove = data[idx];
              if (relmove >= 0xF0) break;
              idx++;

              final int dx =
                  ((relmove & 0x80) != 0 ? -1 : 1) * ((relmove >> 4) & 0x07);
              final int dy = ((relmove & 0x08) != 0 ? -1 : 1) * (relmove & 0x07);

              final int x2 = clipX(x + dx);
              final int y2 = clipY(y + dy);

              drawLine(x, y, x2, y2);
              drewLine = true;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              plotPoint(x, y);
            }
          }
          break;

        case 0xF8: // Flood fill
          {
            while (idx < data.length) {
              final x = data[idx++];
              if (x >= 0xF0) {
                idx--;
                break;
              }
              if (idx >= data.length) break;
              final y = data[idx++];
              if (y >= 0xF0) {
                idx--;
                break;
              }
              fill(clipX(x), clipY(y));
            }
          }
          break;

        case 0xF9: // Set pen size and style
          if (idx < data.length) {
            final arg = data[idx++];
            final size = arg & 0x07;
            currentPen = ((arg & 0x10) == 0) ? circlePen : rectanglePen;
            currentPen.size = size;
            currentPattern = ((arg & 0x20) == 0)
                ? SolidPenPattern.instance
                : splatterPattern;
          }
          break;

        case 0xFA: // Plot with pen
          {
            while (idx < data.length) {
              if (currentPattern.takesArgument) {
                if (idx >= data.length) break;
                final pattNumber = data[idx++];
                if (pattNumber >= 0xF0) {
                  idx--;
                  break;
                }
                currentPattern.setPattern(pattNumber);
              }
              if (idx >= data.length) break;
              final x = data[idx++];
              if (x >= 0xF0) {
                idx--;
                break;
              }
              if (idx >= data.length) break;
              final y = data[idx++];
              if (y >= 0xF0) {
                idx--;
                break;
              }
              currentPen.drawAt(plotPoint, x, y, currentPattern);
            }
          }
          break;

        case 0xFF: // End of picture data
          break;

        default:
          throw AgiException('Malformed PIC resource: unrecognized opcode 0x${opcode.toRadixString(16).padLeft(2, '0')} at offset ${idx - 1}');
      }
    }

    // Decompose visual and priority buffers into 320x200 Impeller priority slices
    final slices = PictureSlicer.slice(
      visualPixels: visualBuffer,
      priorityBuffer: priorityBuffer,
    );

    return AgiPic(
      visualPixels: visualBuffer,
      priorityBuffer: priorityBuffer,
      slices: slices,
    );
  }
}
