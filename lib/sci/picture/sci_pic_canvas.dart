import 'dart:typed_data';

import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';

class _Point {
  int x;
  int y;
  _Point(this.x, this.y);
}

/// Mutable 320x200 visual/priority/control raster used by both the full
/// SCI0 interpreter and vector-step replay.
class SciPicCanvas {
  static const int scriptWidth = 320;
  static const int scriptHeight = 200;

  static const List<int> defaultEgaPalette = [
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x88,
    0x88, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x88,
    0x88, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
    0x08, 0x19, 0x2a, 0x3b, 0x4c, 0x5d, 0x6e, 0x88,
  ];

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

  /// ScummVM `vectorPatternTextures`: 255 bits, then duplicated (510).
  /// The last bit of the `0x20` row is omitted — Sierra ignored bit 256.
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
    false, false, false, false, false,  true, false, // 0x20, last bit ignored
    // Duplicate so sequential stamps never wrap.
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
    false, false, false, false, false,  true, false,
  ];

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

  final int portTop;
  final int paletteNo;
  final bool mirrored;

  final Uint8List visual;
  final Uint8List priority;
  final Uint8List control;
  final Uint8List egaPalettes;

  int picColor = 0;
  int picPriority = 255;
  int picControl = 255;
  int patternCode = 0;

  SciPicCanvas({
    this.portTop = 10,
    this.paletteNo = 0,
    this.mirrored = false,
  })  : visual = Uint8List(scriptWidth * scriptHeight),
        priority = Uint8List(scriptWidth * scriptHeight),
        control = Uint8List(scriptWidth * scriptHeight),
        egaPalettes = Uint8List(4 * 40) {
    final totalPixels = scriptWidth * scriptHeight;
    final clearStart = portTop * scriptWidth;
    visual.fillRange(clearStart, totalPixels, 15);
    for (int p = 0; p < 4; p++) {
      for (int i = 0; i < 40; i++) {
        egaPalettes[p * 40 + i] = defaultEgaPalette[i];
      }
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

  /// ScummVM `vectorPatternBoxPixel`: wrap only when `x >= 320`.
  void patternBoxPixel(int x, int y, int mask, int col, int pri, int ctl, int clipBottom) {
    if (x < 0 || y < 0 || y >= clipBottom) return;
    if (x < scriptWidth) {
      putPixel(x, y, mask, col, pri, ctl);
    } else if (y < clipBottom - 1) {
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

    bool textureBit() {
      if (texOffset < 0 || texOffset >= patternTextures.length) return false;
      return patternTextures[texOffset];
    }

    if (isRect) {
      for (int py = boxTop; py < boxBottom; py++) {
        for (int px = boxLeft; px < boxRight; px++) {
          if (!isTextured || textureBit()) {
            patternBoxPixel(px, py, mask, col, pri, ctl, scriptHeight);
          }
          if (isTextured) texOffset++;
        }
      }
    } else {
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
            if (!isTextured || textureBit()) {
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
      if (!isFillMatch(p.x, p.y, matchMask, searchColor, searchPriority, searchControl)) {
        continue;
      }

      putPixel(p.x, p.y, screenMask, col, pri, ctl);
      var curToLeft = p.x;
      var curToRight = p.x;

      while (curToLeft > borderLeft &&
          isFillMatch(curToLeft - 1, p.y, matchMask, searchColor, searchPriority, searchControl)) {
        curToLeft--;
        putPixel(curToLeft, p.y, screenMask, col, pri, ctl);
      }
      while (curToRight < borderRight &&
          isFillMatch(curToRight + 1, p.y, matchMask, searchColor, searchPriority, searchControl)) {
        curToRight++;
        putPixel(curToRight, p.y, screenMask, col, pri, ctl);
      }

      int aSet = 0;
      int bSet = 0;
      for (int checkX = curToLeft; checkX <= curToRight; checkX++) {
        if (p.y > borderTop &&
            isFillMatch(checkX, p.y - 1, matchMask, searchColor, searchPriority, searchControl)) {
          if (aSet == 0) {
            stack.add(_Point(checkX, p.y - 1));
            aSet = 1;
          }
        } else {
          aSet = 0;
        }

        if (p.y < borderBottom &&
            isFillMatch(checkX, p.y + 1, matchMask, searchColor, searchPriority, searchControl)) {
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

  void drawLine(int x1, int y1, int x2, int y2, int col, int pri, int ctl) {
    int left = x1.clamp(0, scriptWidth - 1);
    int top = y1.clamp(0, scriptHeight - 1);
    int right = x2.clamp(0, scriptWidth - 1);
    int bottom = y2.clamp(0, scriptHeight - 1);

    final mask = getDrawingMask(col, pri, ctl);
    if (mask == 0) return;

    if (top == bottom) {
      if (right < left) {
        final tmp = right;
        right = left;
        left = tmp;
      }
      for (int i = left; i <= right; i++) {
        putPixel(i, top, mask, col, pri, ctl);
      }
      return;
    }
    if (left == right) {
      if (top > bottom) {
        final tmp = top;
        top = bottom;
        bottom = tmp;
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

  /// SCI0 EGA embedded view (`FE 07`): visual-only blit, no priority test.
  void drawEmbeddedView(Uint8List data, int headerPos, int drawX, int drawY) {
    if (headerPos + 8 > data.length) return;
    final width = data[headerPos] | (data[headerPos + 1] << 8);
    final height = data[headerPos + 2] | (data[headerPos + 3] << 8);
    if (width <= 0 || height <= 0) return;
    final clearKey = data[headerPos + 6];
    var rlePos = headerPos + 8;
    var pixelNr = 0;
    final pixelCount = width * height;
    final destY0 = drawY + portTop;

    while (pixelNr < pixelCount && rlePos < data.length) {
      final curByte = data[rlePos++];
      final runLength = curByte >> 4;
      final color = curByte & 0x0F;
      for (int i = 0; i < runLength && pixelNr < pixelCount; i++) {
        if (color != clearKey) {
          final px = drawX + (pixelNr % width);
          final py = destY0 + (pixelNr ~/ width);
          putPixel(px, py, 1, color, 0, 0);
        }
        pixelNr++;
      }
    }
  }

  void ditherInto(Uint8List ditheredVisual, Uint8List rawColorPairs) {
    final totalPixels = scriptWidth * scriptHeight;
    for (int i = 0; i < totalPixels; i++) {
      final x = i % scriptWidth;
      final y = i ~/ scriptWidth;
      final c = visual[i];
      if ((c & 0xF0) != 0) {
        final decoded = (c ^ (c << 4)) & 0xFF;
        final c1 = (decoded >> 4) & 0x0F;
        final c2 = decoded & 0x0F;
        rawColorPairs[i] = (c1 << 4) | c2;
        ditheredVisual[i] = (((x ^ y) & 1) != 0) ? c1 : c2;
      } else {
        final cVal = c & 0x0F;
        rawColorPairs[i] = (cVal << 4) | cVal;
        ditheredVisual[i] = cVal;
      }
    }
  }

  SciPic toSciPic({
    int? picNumber,
    bool computeSlices = false,
    bool computeUnditheredSlices = false,
    bool isUndithered = false,
    List<int>? priorityBands,
  }) {
    const totalPixels = scriptWidth * scriptHeight;
    final ditheredVisual = Uint8List(totalPixels);
    final rawColorPairs = Uint8List(totalPixels);
    ditherInto(ditheredVisual, rawColorPairs);

    final ditheredSlices = computeSlices
        ? PictureSlicer.slice(
            visualPixels: ditheredVisual,
            priorityPixels: priority,
            profile: DisplayProfile.sci0,
            paletteRgbaPacked: EgaColors.rgbaPacked,
          )
        : <int, PictureSlice>{};
    final unditheredSlices = computeUnditheredSlices
        ? PictureSlicer.slice(
            visualPixels: rawColorPairs,
            priorityPixels: priority,
            profile: DisplayProfile.sci0,
            paletteRgbaPacked: unditheredPalette256,
          )
        : <int, PictureSlice>{};

    final pic = SciPic(
      picNumber: picNumber,
      visualPixels: ditheredVisual,
      priorityPixels: Uint8List.fromList(priority),
      controlPixels: Uint8List.fromList(control),
      rawColorPairs: rawColorPairs,
      slices: ditheredSlices,
      unditheredSlices: unditheredSlices,
      priorityBands: priorityBands,
    );
    pic.isUndithered = isUndithered;
    return pic;
  }

  void writeInto(
    SciPic pic, {
    bool computeSlices = false,
    bool computeUnditheredSlices = false,
    bool isUndithered = false,
  }) {
    ditherInto(pic.visualPixels, pic.rawColorPairs);
    pic.priorityPixels.setAll(0, priority);
    pic.controlPixels.setAll(0, control);
    pic.isUndithered = isUndithered;
    pic.replaceSlices(
      dithered: computeSlices
          ? PictureSlicer.slice(
              visualPixels: pic.visualPixels,
              priorityPixels: pic.priorityPixels,
              profile: DisplayProfile.sci0,
              paletteRgbaPacked: EgaColors.rgbaPacked,
            )
          : null,
      undithered: computeUnditheredSlices
          ? PictureSlicer.slice(
              visualPixels: pic.rawColorPairs,
              priorityPixels: pic.priorityPixels,
              profile: DisplayProfile.sci0,
              paletteRgbaPacked: unditheredPalette256,
            )
          : null,
    );
    pic.bumpRasterEpoch();
  }
}
