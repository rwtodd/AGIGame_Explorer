import 'dart:typed_data';

import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';

class _Point {
  int x;
  int y;
  _Point(this.x, this.y);
}

/// Vector bytecode interpreter for Sierra SCI0 and SCI1-EGA PICTURE resources.
///
/// Draws visual, depth priority, and control maps at native 320x200 resolution,
/// models authentic EGA dithering patterns and undithered 40-color blended palettes,
/// and produces 16-layer Impeller compositor slices via [PictureSlicer].
class SciPicInterpreter {
  static const int scriptWidth = 320;
  static const int scriptHeight = 200;

  /// Default 40-byte EGA dither palette used by Sierra SCI0 pictures.
  static const List<int> defaultEgaPalette = [
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x88,
    0x88, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x88,
    0x88, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
    0x08, 0x19, 0x2a, 0x3b, 0x4c, 0x5d, 0x6e, 0x88,
  ];

  /// Circle bitmaps (sizes 0..7) used by Sierra pattern pens.
  static const List<List<int>> patternCircles = [
    [0x01],
    [0x72, 0x02],
    [0xCE, 0xF7, 0x7D, 0x0E],
    [0x1C, 0x3E, 0x7F, 0x7F, 0x7F, 0x3E, 0x1C, 0x00],
    [0x38, 0xF8, 0xF3, 0xDF, 0x7F, 0xFF, 0xFD, 0xF7, 0x9F, 0x3F, 0x38],
    [0x70, 0xC0, 0x1F, 0xFE, 0xE3, 0x3F, 0xFF, 0xF7, 0x7F, 0xFF, 0xE7, 0x3F, 0xFE, 0xC3, 0x1F, 0xF8, 0x00],
    [0xF0, 0x01, 0xFF, 0xE1, 0xFF, 0xF8, 0x3F, 0xFF, 0xDF, 0xFF, 0xF7, 0xFF, 0xFD, 0x7F, 0xFF, 0x9F, 0xFF, 0xE3, 0xFF, 0xF0, 0x1F, 0xF0, 0x01],
    [0xE0, 0x03, 0xF8, 0x0F, 0xFC, 0x1F, 0xFE, 0x3F, 0xFE, 0x3F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFE, 0x3F, 0xFE, 0x3F, 0xFC, 0x1F, 0xF8, 0x0F, 0xE0, 0x03],
  ];

  /// Bit offsets into [patternTextures] indexed by pattern texture code (0..127).
  static const List<int> patternTextureOffset = [
    0x00, 0x18, 0x30, 0xc4, 0xdc, 0x65, 0xeb, 0x48,
    0x60, 0xbd, 0x89, 0x04, 0x0a, 0xf4, 0x7d, 0x6d,
    0x85, 0xb0, 0x8e, 0x95, 0x1f, 0x22, 0x0d, 0xdf,
    0x2a, 0x78, 0xd5, 0x73, 0x1c, 0xb4, 0x40, 0xa1,
    0xb9, 0x3c, 0xca, 0x58, 0x92, 0x34, 0xcc, 0xce,
    0xd7, 0x42, 0x90, 0x0f, 0x8b, 0x7f, 0x32, 0xed,
    0x5c, 0x9d, 0xc8, 0x99, 0xad, 0x4e, 0x56, 0xa6,
    0xf7, 0x68, 0xb7, 0x25, 0x82, 0x37, 0x3a, 0x51,
    0x69, 0x26, 0x38, 0x52, 0x9e, 0x9a, 0x4f, 0xa7,
    0x43, 0x10, 0x80, 0xee, 0x3d, 0x59, 0x35, 0xcf,
    0x79, 0x74, 0xb5, 0xa2, 0xb1, 0x96, 0x23, 0xe0,
    0xbe, 0x05, 0xf5, 0x6e, 0x19, 0xc5, 0x66, 0x49,
    0xf0, 0xd1, 0x54, 0xa9, 0x70, 0x4b, 0xa4, 0xe2,
    0xe6, 0xe5, 0xab, 0xe4, 0xd2, 0xaa, 0x4c, 0xe3,
    0x06, 0x6f, 0xc6, 0x4a, 0x75, 0xa3, 0x97, 0xe1,
  ];

  /// Sierra pattern textures (duplicated to prevent modulo wrap boundary issues).
  static const List<bool> patternTextures = [
    false, false,  true, false, false, false, false, false, // 0x04
     true, false, false,  true, false,  true, false, false, // 0x29
    false, false, false, false, false, false,  true, false, // 0x40
    false, false,  true, false, false,  true, false, false, // 0x24
     true, false, false,  true, false, false, false, false, // 0x09
     true, false, false, false, false, false,  true, false, // 0x41
     true, false,  true, false, false,  true, false, false, // 0x25
     true, false,  true, false, false, false,  true, false, // 0x45
     true, false, false, false, false, false,  true, false, // 0x41
    false, false, false, false,  true, false, false,  true, // 0x90
    false, false, false, false,  true, false,  true, false, // 0x50
    false, false,  true, false, false, false,  true, false, // 0x44
    false, false, false,  true, false, false,  true, false, // 0x48
    false, false, false,  true, false, false, false, false, // 0x08
    false,  true, false, false, false, false,  true, false, // 0x42
    false, false, false,  true, false,  true, false, false, // 0x28
     true, false, false,  true, false, false, false,  true, // 0x89
    false,  true, false, false,  true, false,  true, false, // 0x52
     true, false, false,  true, false, false, false,  true, // 0x89
    false, false, false,  true, false, false, false,  true, // 0x88
    false, false, false, false,  true, false, false, false, // 0x10
    false, false, false,  true, false, false,  true, false, // 0x48
    false, false,  true, false, false,  true, false,  true, // 0xA4
    false, false, false,  true, false, false, false, false, // 0x08
    false, false,  true, false, false, false,  true, false, // 0x44
     true, false,  true, false,  true, false, false, false, // 0x15
    false, false, false,  true, false,  true, false, false, // 0x28
    false, false,  true, false, false,  true, false, false, // 0x24
    false, false, false, false, false, false, false, false, // 0x00
    false,  true, false,  true, false, false, false, false, // 0x0A
    false, false,  true, false, false,  true, false, false, // 0x24
    false, false, false, false, false,  true, false, false, // 0x20
    // Duplicated table
    false, false,  true, false, false, false, false, false,
     true, false, false,  true, false,  true, false, false,
    false, false, false, false, false, false,  true, false,
    false, false,  true, false, false,  true, false, false,
     true, false, false,  true, false, false, false, false,
     true, false, false, false, false, false,  true, false,
     true, false,  true, false, false,  true, false, false,
     true, false,  true, false, false, false,  true, false,
     true, false, false, false, false, false,  true, false,
    false, false, false, false,  true, false, false,  true,
    false, false, false, false,  true, false,  true, false,
    false, false,  true, false, false, false,  true, false,
    false, false, false,  true, false, false,  true, false,
    false, false, false,  true, false, false, false, false,
    false,  true, false, false, false, false,  true, false,
    false, false, false,  true, false,  true, false, false,
     true, false, false,  true, false, false, false,  true,
    false,  true, false, false,  true, false,  true, false,
     true, false, false,  true, false, false, false,  true,
    false, false, false,  true, false, false, false,  true,
    false, false, false, false,  true, false, false, false,
    false, false, false,  true, false, false,  true, false,
    false, false,  true, false, false,  true, false,  true,
    false, false, false,  true, false, false, false, false,
    false, false,  true, false, false, false,  true, false,
     true, false,  true, false,  true, false, false, false,
    false, false, false,  true, false,  true, false, false,
    false, false,  true, false, false,  true, false, false,
    false, false, false, false, false, false, false, false,
    false,  true, false,  true, false, false, false, false,
    false, false,  true, false, false,  true, false, false,
    false, false, false, false, false,  true, false, false,
  ];

  /// Precomputed 256-entry packed 32-bit RGBA lookup table for non-dithered 40-color blending.
  static final List<int> unditheredPalette256 = List<int>.generate(256, (byteVal) {
    final c1 = (byteVal >> 4) & 0x0F;
    final c2 = byteVal & 0x0F;
    final p1 = EgaColors.rgbaPacked[c1];
    final p2 = EgaColors.rgbaPacked[c2];
    final r = ((p1 & 0xFF) + (p2 & 0xFF)) >> 1;
    final g = (((p1 >> 8) & 0xFF) + ((p2 >> 8) & 0xFF)) >> 1;
    final b = (((p1 >> 16) & 0xFF) + ((p2 >> 16) & 0xFF)) >> 1;
    return 0xFF000000 | (b << 16) | (g << 8) | r;
  });

  /// Interprets raw SCI0 PICTURE vector bytecode [data] and returns a [SciPic].
  ///
  /// [portTop] specifies the top vertical offset for picture port (usually 10 for
  /// rooms with menu bars, or 0 for title screens and cutscenes).
  static SciPic interpret(
    Uint8List data, {
    int? picNumber,
    int portTop = 10,
    int paletteNo = 0,
    bool mirrored = false,
  }) {
    const totalPixels = scriptWidth * scriptHeight;
    final visual = Uint8List(totalPixels);
    final priority = Uint8List(totalPixels);
    final control = Uint8List(totalPixels);

    // Initial clear: rows [portTop..199] are cleared to 15 (white), priority 0, control 0
    final clearStart = portTop * scriptWidth;
    visual.fillRange(clearStart, totalPixels, 15);

    int curPos = 0;
    int picColor = 0; // Black default
    int picPriority = 255;
    int picControl = 255;

    // 4 palettes * 40 bytes
    final egaPalettes = Uint8List(4 * 40);
    for (int p = 0; p < 4; p++) {
      for (int i = 0; i < 40; i++) {
        egaPalettes[p * 40 + i] = defaultEgaPalette[i];
      }
    }

    int getPaletteEntry(int colorIndex) {
      if (colorIndex >= 40) colorIndex = colorIndex & 0x0F;
      final offset = (paletteNo.clamp(0, 3) * 40) + colorIndex;
      return egaPalettes[offset];
    }

    void putPixel(int x, int y, int mask, int col, int pri, int ctl) {
      if (x < 0 || x >= scriptWidth || y < 0 || y >= scriptHeight) return;
      final idx = y * scriptWidth + x;
      if ((mask & 1) != 0) visual[idx] = col;
      if ((mask & 2) != 0) priority[idx] = pri;
      if ((mask & 4) != 0) control[idx] = ctl;
    }

    int getDrawingMask(int col, int pri, int ctl) {
      int m = 0;
      if (col != 255) m |= 1;
      if (pri != 255) m |= 2;
      if (ctl != 255) m |= 4;
      return m;
    }

    void drawLine(int x1, int y1, int x2, int y2, int col, int pri, int ctl) {
      int left = x1.clamp(0, scriptWidth - 1);
      int top = y1.clamp(0, scriptHeight - 1);
      int right = x2.clamp(0, scriptWidth - 1);
      int bottom = y2.clamp(0, scriptHeight - 1);

      final mask = getDrawingMask(col, pri, ctl);
      if (mask == 0) return;

      if (top == bottom) {
        if (right < left) {
          final tmp = right; right = left; left = tmp;
        }
        for (int i = left; i <= right; i++) {
          putPixel(i, top, mask, col, pri, ctl);
        }
        return;
      }
      if (left == right) {
        if (top > bottom) {
          final tmp = top; top = bottom; bottom = tmp;
        }
        for (int i = top; i <= bottom; i++) {
          putPixel(left, i, mask, col, pri, ctl);
        }
        return;
      }

      int dy = bottom - top;
      int dx = right - left;
      final stepy = dy < 0 ? -1 : 1;
      final stepx = dx < 0 ? -1 : 1;
      dy = dy.abs() << 1;
      dx = dx.abs() << 1;

      putPixel(left, top, mask, col, pri, ctl);
      putPixel(right, bottom, mask, col, pri, ctl);

      if (dx > dy) {
        int fraction = dy - (dx >> 1);
        while (left != right) {
          if (fraction >= 0) {
            top += stepy;
            fraction -= dx;
          }
          left += stepx;
          fraction += dy;
          putPixel(left, top, mask, col, pri, ctl);
        }
      } else {
        int fraction = dx - (dy >> 1);
        while (top != bottom) {
          if (fraction >= 0) {
            left += stepx;
            fraction -= dy;
          }
          top += stepy;
          fraction += dx;
          putPixel(left, top, mask, col, pri, ctl);
        }
      }
    }

    void patternBoxPixel(int x, int y, int mask, int col, int pri, int ctl, int clipBottom) {
      if (x < 0 || y < 0 || y >= clipBottom) return;
      if (x < scriptWidth) {
        putPixel(x, y, mask, col, pri, ctl);
      } else if (y < clipBottom - 1) {
        // Sierra wrap-around quirk for rectangle pattern pens
        var wrapCol = col;
        if ((wrapCol & 0xF0) != 0) {
          wrapCol = (wrapCol ^ (wrapCol << 4)) & 0xFF;
          wrapCol = ((wrapCol << 4) | (wrapCol >> 4)) & 0xFF;
          wrapCol = (wrapCol ^ (wrapCol << 4)) & 0xFF;
        }
        putPixel(0, y + 1, mask, wrapCol, pri, ctl);
      }
    }

    void drawPattern(int x, int y, int col, int pri, int ctl, int code, int texture) {
      final size = code & 0x07;
      int boxLeft = x - size;
      int boxTop = y - size;
      final boxWidth = 2 * size + 2;
      final boxHeight = 2 * size + 1;
      int boxRight = boxLeft + boxWidth;
      int boxBottom = boxTop + boxHeight;

      if (boxLeft < 0) {
        boxLeft = 0;
        boxRight = boxWidth;
      }
      if (boxTop < 0) {
        boxTop = 0;
        boxBottom = boxHeight;
      }

      boxTop += portTop;
      boxBottom += portTop;

      if (boxRight > scriptWidth + 1) {
        final shift = boxRight - (scriptWidth + 1);
        boxLeft -= shift;
        boxRight -= shift;
      }
      if (boxBottom > scriptHeight) {
        final shift = boxBottom - scriptHeight;
        boxTop -= shift;
        boxBottom -= shift;
      }

      final mask = getDrawingMask(col, pri, ctl);
      if (mask == 0) return;

      final isRect = (code & 0x10) != 0;
      final isTextured = (code & 0x20) != 0;
      int texOffset = isTextured ? patternTextureOffset[texture.clamp(0, 127)] : 0;

      if (isRect) {
        for (int py = boxTop; py < boxBottom; py++) {
          for (int px = boxLeft; px < boxRight; px++) {
            if (!isTextured || patternTextures[texOffset % patternTextures.length]) {
              patternBoxPixel(px, py, mask, col, pri, ctl, scriptHeight);
            }
            if (isTextured) texOffset++;
          }
        }
      } else {
        // Circle
        final circleData = patternCircles[size];
        int cByteIdx = 0;
        int bitmap = circleData[0];
        int bitNo = 0;

        for (int py = boxTop; py < boxBottom; py++) {
          for (int px = boxLeft; px < boxRight; px++) {
            if (bitNo == 8) {
              cByteIdx++;
              bitmap = cByteIdx < circleData.length ? circleData[cByteIdx] : 0;
              bitNo = 0;
            }
            if ((bitmap & 1) != 0) {
              if (!isTextured || patternTextures[texOffset % patternTextures.length]) {
                if (px >= 0 && px < scriptWidth && py >= 0 && py < scriptHeight) {
                  putPixel(px, py, mask, col, pri, ctl);
                }
              }
              if (isTextured) texOffset++;
            }
            bitNo++;
            bitmap >>= 1;
          }
        }
      }
    }

    bool isFillMatch(int x, int y, int matchMask, int sCol, int sPri, int sCtl) {
      final idx = y * scriptWidth + x;
      if ((matchMask & 1) != 0) {
        var egaColor = visual[idx];
        if (((x ^ y) & 1) != 0) {
          egaColor = (egaColor ^ (egaColor >> 4)) & 0x0F;
        } else {
          egaColor = egaColor & 0x0F;
        }
        return egaColor == sCol;
      }
      if ((matchMask & 2) != 0) {
        return priority[idx] == sPri;
      }
      if ((matchMask & 4) != 0) {
        return control[idx] == sCtl;
      }
      return false;
    }

    void floodFill(int startX, int startY, int col, int pri, int ctl) {
      final px = startX;
      final py = startY + portTop;
      if (px < 0 || px >= scriptWidth || py < portTop || py >= scriptHeight) return;

      int screenMask = getDrawingMask(col, pri, ctl);
      if (screenMask == 0) return;

      final pIdx = py * scriptWidth + px;
      int searchColor = visual[pIdx];
      if (((px ^ py) & 1) != 0) {
        searchColor = (searchColor ^ (searchColor >> 4)) & 0x0F;
      } else {
        searchColor = searchColor & 0x0F;
      }
      final searchPriority = priority[pIdx];
      final searchControl = control[pIdx];

      // Sierra flood fill abort rules
      if ((screenMask & 1) != 0) {
        if (col == 15 || searchColor != 15) return;
      } else if ((screenMask & 2) != 0) {
        if (pri == 0 || searchPriority != 0) return;
      } else if ((screenMask & 4) != 0) {
        if (ctl == 0 || searchControl != 0) return;
      }

      if ((screenMask & 1) != 0 && searchColor == col) screenMask &= ~1;
      if ((screenMask & 2) != 0 && searchPriority == pri) screenMask &= ~2;
      if ((screenMask & 4) != 0 && searchControl == ctl) screenMask &= ~4;
      if (screenMask == 0) return;

      final int matchMask;
      if ((screenMask & 1) != 0) {
        matchMask = 1;
      } else if ((screenMask & 2) != 0) {
        matchMask = 2;
      } else {
        matchMask = 4;
      }

      const borderLeft = 0;
      final borderTop = portTop;
      const borderRight = scriptWidth - 1;
      const borderBottom = scriptHeight - 1;

      final stack = <_Point>[_Point(px, py)];
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        if (!isFillMatch(p.x, p.y, matchMask, searchColor, searchPriority, searchControl)) continue;

        putPixel(p.x, p.y, screenMask, col, pri, ctl);
        var curToLeft = p.x;
        var curToRight = p.x;

        while (curToLeft > borderLeft && isFillMatch(curToLeft - 1, p.y, matchMask, searchColor, searchPriority, searchControl)) {
          curToLeft--;
          putPixel(curToLeft, p.y, screenMask, col, pri, ctl);
        }
        while (curToRight < borderRight && isFillMatch(curToRight + 1, p.y, matchMask, searchColor, searchPriority, searchControl)) {
          curToRight++;
          putPixel(curToRight, p.y, screenMask, col, pri, ctl);
        }

        int aSet = 0;
        int bSet = 0;
        for (int checkX = curToLeft; checkX <= curToRight; checkX++) {
          if (p.y > borderTop && isFillMatch(checkX, p.y - 1, matchMask, searchColor, searchPriority, searchControl)) {
            if (aSet == 0) {
              stack.add(_Point(checkX, p.y - 1));
              aSet = 1;
            }
          } else {
            aSet = 0;
          }

          if (p.y < borderBottom && isFillMatch(checkX, p.y + 1, matchMask, searchColor, searchPriority, searchControl)) {
            if (bSet == 0) {
              stack.add(_Point(checkX, p.y + 1));
              bSet = 1;
            }
          } else {
            bSet = 0;
          }
        }
      }
    }

    void getAbsCoords(List<int> out) {
      final p = data[curPos++];
      out[0] = data[curPos++] + ((p & 0xF0) << 4);
      out[1] = data[curPos++] + ((p & 0x0F) << 8);
      if (mirrored) out[0] = 319 - out[0];
    }

    void getRelCoords(List<int> out) {
      final p = data[curPos++];
      if ((p & 0x80) != 0) {
        out[0] -= ((p >> 4) & 7) * (mirrored ? -1 : 1);
      } else {
        out[0] += (p >> 4) * (mirrored ? -1 : 1);
      }
      if ((p & 0x08) != 0) {
        out[1] -= (p & 7);
      } else {
        out[1] += (p & 7);
      }
    }

    void getRelCoordsMed(List<int> out) {
      final py = data[curPos++];
      if ((py & 0x80) != 0) {
        out[1] -= (py & 0x7F);
      } else {
        out[1] += py;
      }
      final px = data[curPos++];
      if ((px & 0x80) != 0) {
        out[0] -= (128 - (px & 0x7F)) * (mirrored ? -1 : 1);
      } else {
        out[0] += px * (mirrored ? -1 : 1);
      }
    }

    int patternCode = 0;
    int patternTexture = 0;

    void getPatternTexture() {
      if ((patternCode & 0x20) != 0) {
        patternTexture = (data[curPos++] >> 1) & 0x7F;
      }
    }

    final coords = [0, 0];

    while (curPos < data.length) {
      final op = data[curPos++];
      switch (op) {
        case 0xF0: // Set visual color
          final rawColor = data[curPos++];
          final palColor = getPaletteEntry(rawColor);
          picColor = (palColor ^ (palColor << 4)) & 0xFF;
          break;

        case 0xF1: // Disable visual
          picColor = 255;
          break;

        case 0xF2: // Set priority
          picPriority = data[curPos++] & 0x0F;
          break;

        case 0xF3: // Disable priority
          picPriority = 255;
          break;

        case 0xF4: // Short patterns
          getPatternTexture();
          getAbsCoords(coords);
          drawPattern(coords[0], coords[1], picColor, picPriority, picControl, patternCode, patternTexture);
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoords(coords);
            drawPattern(coords[0], coords[1], picColor, picPriority, picControl, patternCode, patternTexture);
          }
          break;

        case 0xF5: // Medium lines
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoordsMed(coords);
            drawLine(oldX, oldY + portTop, coords[0], coords[1] + portTop, picColor, picPriority, picControl);
          }
          break;

        case 0xF6: // Long lines
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getAbsCoords(coords);
            drawLine(oldX, oldY + portTop, coords[0], coords[1] + portTop, picColor, picPriority, picControl);
          }
          break;

        case 0xF7: // Short lines
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoords(coords);
            drawLine(oldX, oldY + portTop, coords[0], coords[1] + portTop, picColor, picPriority, picControl);
          }
          break;

        case 0xF8: // Fill
          while (curPos < data.length && data[curPos] < 0xF0) {
            getAbsCoords(coords);
            floodFill(coords[0], coords[1], picColor, picPriority, picControl);
          }
          break;

        case 0xF9: // Set pattern
          patternCode = data[curPos++];
          break;

        case 0xFA: // Absolute pattern
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getAbsCoords(coords);
            drawPattern(coords[0], coords[1], picColor, picPriority, picControl, patternCode, patternTexture);
          }
          break;

        case 0xFB: // Set control
          picControl = data[curPos++] & 0x0F;
          break;

        case 0xFC: // Disable control
          picControl = 255;
          break;

        case 0xFD: // Medium patterns
          getPatternTexture();
          getAbsCoords(coords);
          drawPattern(coords[0], coords[1], picColor, picPriority, picControl, patternCode, patternTexture);
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoordsMed(coords);
            drawPattern(coords[0], coords[1], picColor, picPriority, picControl, patternCode, patternTexture);
          }
          break;

        case 0xFE: // Extended opcodes
          final subOp = data[curPos++];
          switch (subOp) {
            case 0: // Set palette entries
              while (curPos < data.length && data[curPos] < 0xF0) {
                final pix = data[curPos++];
                if (pix < egaPalettes.length) {
                  egaPalettes[pix] = data[curPos++];
                } else {
                  curPos++;
                }
              }
              break;

            case 1: // Set palette (40 bytes)
              final pIdx = data[curPos++];
              if (pIdx < 4) {
                final base = pIdx * 40;
                for (int i = 0; i < 40; i++) {
                  egaPalettes[base + i] = data[curPos++];
                }
              } else {
                curPos += 40;
              }
              break;

            case 2:
              curPos += 41;
              break;

            case 3:
            case 5:
              curPos++;
              break;

            case 4:
            case 6:
              break;

            case 7: // Embedded view
              getAbsCoords(coords);
              final size = data[curPos] | (data[curPos + 1] << 8);
              curPos += 2 + size;
              break;

            case 8: // Priority table
              curPos += 14;
              break;
          }
          break;

        case 0xFF: // Terminate
          break;
      }

      if (op == 0xFF) break;
    }

    // Post-process visual buffers:
    // 1. ditheredVisual: authentic EGA checkerboard dither (0..15).
    // 2. rawColorPairs: decoded (c1 << 4) | c2 for 40-color blended display.
    final ditheredVisual = Uint8List(totalPixels);
    final rawColorPairs = Uint8List(totalPixels);

    for (int y = 0; y < scriptHeight; y++) {
      for (int x = 0; x < scriptWidth; x++) {
        final idx = y * scriptWidth + x;
        final c = visual[idx];
        if ((c & 0xF0) != 0) {
          final decoded = (c ^ (c << 4)) & 0xFF;
          final c1 = (decoded >> 4) & 0x0F;
          final c2 = decoded & 0x0F;
          rawColorPairs[idx] = (c1 << 4) | c2;
          ditheredVisual[idx] = (((x ^ y) & 1) != 0) ? c1 : c2;
        } else {
          final cVal = c & 0x0F;
          rawColorPairs[idx] = (cVal << 4) | cVal;
          ditheredVisual[idx] = cVal;
        }
      }
    }

    // Generate Impeller priority slices: authentic dithered and undithered
    final ditheredSlices = PictureSlicer.slice(
      visualPixels: ditheredVisual,
      priorityPixels: priority,
      profile: DisplayProfile.sci0,
      paletteRgbaPacked: EgaColors.rgbaPacked,
    );

    final unditheredSlices = PictureSlicer.slice(
      visualPixels: rawColorPairs,
      priorityPixels: priority,
      profile: DisplayProfile.sci0,
      paletteRgbaPacked: unditheredPalette256,
    );

    return SciPic(
      picNumber: picNumber,
      visualPixels: ditheredVisual,
      priorityPixels: priority,
      controlPixels: control,
      rawColorPairs: rawColorPairs,
      slices: ditheredSlices,
      unditheredSlices: unditheredSlices,
    );
  }
}
