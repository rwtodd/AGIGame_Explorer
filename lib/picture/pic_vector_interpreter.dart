import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';
import 'package:flutter_agigame/picture/pic_canvas.dart';

/// Interpreter for Sierra AGI PICTURE vector drawing bytecode.
///
/// Draws into an [AgiPicCanvas] (same object step replay uses) and returns an
/// [AgiPic]. Counterpart of [SciPicInterpreter].
class PicVectorInterpreter {
  final bool isV3;

  PicVectorInterpreter({this.isV3 = false});

  /// Interprets raw PICTURE resource bytes [data] and returns an [AgiPic].
  AgiPic interpret(Uint8List data) {
    final canvas = AgiPicCanvas(isV3: isV3);

    int idx = 0;
    while (idx < data.length) {
      final opcode = data[idx++] & 0xFF;
      switch (opcode) {
        case 0xF0: // Set visual color & enable visual draw
          if (idx < data.length) {
            canvas.picColor = data[idx++] & 0x0F;
          }
          break;

        case 0xF1: // Disable visual draw
          canvas.picColor = -1;
          break;

        case 0xF2: // Set priority color & enable priority draw
          if (idx < data.length) {
            canvas.priColor = data[idx++] & 0x0F;
          }
          break;

        case 0xF3: // Disable priority draw
          canvas.priColor = -1;
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
            x = AgiPicCanvas.clipX(x);
            y = AgiPicCanvas.clipY(y);

            int x2 = x;
            int y2 = y;
            bool drewLine = false;
            bool changeY = true;

            while (idx < data.length) {
              final nextCoord = data[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              if (changeY) {
                y2 = AgiPicCanvas.clipY(nextCoord);
              } else {
                x2 = AgiPicCanvas.clipX(nextCoord);
              }
              canvas.drawLine(x, y, x2, y2);
              drewLine = true;
              changeY = !changeY;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              canvas.plotPoint(x, y);
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
            x = AgiPicCanvas.clipX(x);
            y = AgiPicCanvas.clipY(y);

            int x2 = x;
            int y2 = y;
            bool drewLine = false;
            bool changeY = false;

            while (idx < data.length) {
              final nextCoord = data[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              if (changeY) {
                y2 = AgiPicCanvas.clipY(nextCoord);
              } else {
                x2 = AgiPicCanvas.clipX(nextCoord);
              }
              canvas.drawLine(x, y, x2, y2);
              drewLine = true;
              changeY = !changeY;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              canvas.plotPoint(x, y);
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
            x = AgiPicCanvas.clipX(x);

            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = AgiPicCanvas.clipY(y);

            bool drewLine = false;

            while (idx < data.length) {
              int x2 = data[idx++];
              if (x2 >= 0xF0) {
                idx--;
                break;
              }
              x2 = AgiPicCanvas.clipX(x2);

              if (idx >= data.length) break;
              int y2 = data[idx++];
              if (y2 >= 0xF0) {
                idx--;
                break;
              }
              y2 = AgiPicCanvas.clipY(y2);

              canvas.drawLine(x, y, x2, y2);
              drewLine = true;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              canvas.plotPoint(x, y);
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
            x = AgiPicCanvas.clipX(x);

            if (idx >= data.length) break;
            int y = data[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = AgiPicCanvas.clipY(y);

            bool drewLine = false;

            while (idx < data.length) {
              final relmove = data[idx];
              if (relmove >= 0xF0) break;
              idx++;

              final int dx =
                  ((relmove & 0x80) != 0 ? -1 : 1) * ((relmove >> 4) & 0x07);
              final int dy = ((relmove & 0x08) != 0 ? -1 : 1) * (relmove & 0x07);

              final int x2 = AgiPicCanvas.clipX(x + dx);
              final int y2 = AgiPicCanvas.clipY(y + dy);

              canvas.drawLine(x, y, x2, y2);
              drewLine = true;
              x = x2;
              y = y2;
            }

            if (!drewLine) {
              canvas.plotPoint(x, y);
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
              canvas.fill(AgiPicCanvas.clipX(x), AgiPicCanvas.clipY(y));
            }
          }
          break;

        case 0xF9: // Set pen size and style
          if (idx < data.length) {
            final arg = data[idx++];
            final size = arg & 0x07;
            canvas.currentPen =
                ((arg & 0x10) == 0) ? canvas.circlePen : canvas.rectanglePen;
            canvas.currentPen.size = size;
            canvas.currentPattern = ((arg & 0x20) == 0)
                ? SolidPenPattern.instance
                : canvas.splatterPattern;
          }
          break;

        case 0xFA: // Plot with pen
          {
            while (idx < data.length) {
              if (canvas.currentPattern.takesArgument) {
                if (idx >= data.length) break;
                final pattNumber = data[idx++];
                if (pattNumber >= 0xF0) {
                  idx--;
                  break;
                }
                canvas.currentPattern.setPattern(pattNumber);
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
              canvas.plotPen(x, y);
            }
          }
          break;

        case 0xFF: // End of picture data
          break;

        default:
          throw AgiException(
            'Malformed PIC resource: unrecognized opcode 0x${opcode.toRadixString(16).padLeft(2, '0')} at offset ${idx - 1}',
          );
      }
    }

    return canvas.toAgiPic(copyBuffers: false);
  }
}
