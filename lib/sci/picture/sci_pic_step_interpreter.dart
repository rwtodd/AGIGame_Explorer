import 'dart:typed_data';

import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_interpreter.dart';

class _Point {
  int x;
  int y;
  _Point(this.x, this.y);
}

/// A discrete drawing operation decoded from an SCI0 PICTURE vector stream.
class SciPicDrawingStep implements PicStepInfo {
  @override
  final int stepIndex;
  @override
  final int opcode;
  @override
  final String commandName;
  @override
  final String description;
  final void Function(SciPicStepContext ctx) action;

  const SciPicDrawingStep({
    required this.stepIndex,
    required this.opcode,
    required this.commandName,
    required this.description,
    required this.action,
  });

  void execute(SciPicStepContext ctx) => action(ctx);

  @override
  String toString() => 'Step #$stepIndex [$commandName]: $description';
}

/// Execution context for stepping through SCI0 picture drawing opcodes.
class SciPicStepContext {
  static const int scriptWidth = 320;
  static const int scriptHeight = 200;

  final int portTop;
  final int paletteNo;
  final bool mirrored;

  final Uint8List visual;
  final Uint8List priority;
  final Uint8List control;
  final Uint8List egaPalettes;

  int picColor = 0; // Black default
  int picPriority = 255;
  int picControl = 255;
  int patternCode = 0;

  SciPicStepContext({
    this.portTop = 10,
    this.paletteNo = 0,
    this.mirrored = false,
  })  : visual = Uint8List(scriptWidth * scriptHeight),
        priority = Uint8List(scriptWidth * scriptHeight),
        control = Uint8List(scriptWidth * scriptHeight),
        egaPalettes = Uint8List(4 * 40) {
    const totalPixels = scriptWidth * scriptHeight;
    final clearStart = portTop * scriptWidth;
    visual.fillRange(clearStart, totalPixels, 15);

    for (int p = 0; p < 4; p++) {
      for (int i = 0; i < 40; i++) {
        egaPalettes[p * 40 + i] = SciPicInterpreter.defaultEgaPalette[i];
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

  void patternBoxPixel(int x, int y, int mask, int col, int pri, int ctl, int maxH) {
    if (x < 0 || x >= scriptWidth || y < 0 || y >= maxH) return;
    putPixel(x, y, mask, col, pri, ctl);
    if (x == 319 && y < maxH - 1) {
      var wrapCol = col;
      if (wrapCol != 255) {
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
    int texOffset = isTextured ? SciPicInterpreter.patternTextureOffset[texture.clamp(0, 127)] : 0;

    if (isRect) {
      for (int py = boxTop; py < boxBottom; py++) {
        for (int px = boxLeft; px < boxRight; px++) {
          if (!isTextured || SciPicInterpreter.patternTextures[texOffset % SciPicInterpreter.patternTextures.length]) {
            patternBoxPixel(px, py, mask, col, pri, ctl, scriptHeight);
          }
          if (isTextured) texOffset++;
        }
      }
    } else {
      final circleData = SciPicInterpreter.patternCircles[size];
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
            if (!isTextured || SciPicInterpreter.patternTextures[texOffset % SciPicInterpreter.patternTextures.length]) {
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

  SciPic toSciPic({int? picNumber, bool computeSlices = false, bool isUndithered = false}) {
    const totalPixels = scriptWidth * scriptHeight;
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

    final Map<int, PictureSlice> ditheredSlices;
    final Map<int, PictureSlice> unditheredSlices;

    if (computeSlices) {
      ditheredSlices = PictureSlicer.slice(
        visualPixels: ditheredVisual,
        priorityPixels: priority,
        profile: DisplayProfile.sci0,
        paletteRgbaPacked: EgaColors.rgbaPacked,
      );
      unditheredSlices = PictureSlicer.slice(
        visualPixels: rawColorPairs,
        priorityPixels: priority,
        profile: DisplayProfile.sci0,
        paletteRgbaPacked: SciPicInterpreter.unditheredPalette256,
      );
    } else {
      ditheredSlices = <int, PictureSlice>{};
      unditheredSlices = <int, PictureSlice>{};
    }

    final pic = SciPic(
      picNumber: picNumber,
      visualPixels: ditheredVisual,
      priorityPixels: priority,
      controlPixels: control,
      rawColorPairs: rawColorPairs,
      slices: ditheredSlices,
      unditheredSlices: unditheredSlices,
    );
    pic.isUndithered = isUndithered;
    return pic;
  }
}

/// Step-by-step vector bytecode interpreter for Sierra SCI0 pictures.
///
/// Decodes drawing opcodes into discrete [SciPicDrawingStep] instances,
/// enabling scrubbable step playback, animated command-by-command rendering,
/// and live opcode inspection in the workbench UI.
class SciPicStepInterpreter implements SierraPicStepInterpreter {
  final Uint8List rawData;
  final int? picNumber;
  final int portTop;
  final int paletteNo;
  final bool mirrored;

  @override
  final List<SciPicDrawingStep> steps = [];

  SciPicStepInterpreter(
    this.rawData, {
    this.picNumber,
    this.portTop = 10,
    this.paletteNo = 0,
    this.mirrored = false,
  }) {
    _decodeSteps();
  }

  @override
  int get totalSteps => steps.length;

  void _decodeSteps() {
    int curPos = 0;
    int stepCounter = 0;
    int patternCode = 0;
    int patternTexture = 0;
    final coords = [0, 0];

    void getAbsCoords(List<int> out) {
      final p = rawData[curPos++];
      out[0] = rawData[curPos++] + ((p & 0xF0) << 4);
      out[1] = rawData[curPos++] + ((p & 0x0F) << 8);
      if (mirrored) out[0] = 319 - out[0];
    }

    void getRelCoords(List<int> out) {
      final p = rawData[curPos++];
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
      final py = rawData[curPos++];
      if ((py & 0x80) != 0) {
        out[1] -= (py & 0x7F);
      } else {
        out[1] += py;
      }
      final px = rawData[curPos++];
      if ((px & 0x80) != 0) {
        out[0] -= (128 - (px & 0x7F)) * (mirrored ? -1 : 1);
      } else {
        out[0] += px * (mirrored ? -1 : 1);
      }
    }

    void getPatternTexture() {
      if ((patternCode & 0x20) != 0) {
        patternTexture = (rawData[curPos++] >> 1) & 0x7F;
      }
    }

    while (curPos < rawData.length) {
      final op = rawData[curPos++];
      switch (op) {
        case 0xF0: // Set visual color
          final rawColor = rawData[curPos++];
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF0,
            commandName: 'Set Visual Color',
            description: 'Palette entry 0x${rawColor.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            action: (ctx) {
              final palColor = ctx.getPaletteEntry(rawColor);
              ctx.picColor = (palColor ^ (palColor << 4)) & 0xFF;
            },
          ));
          break;

        case 0xF1: // Disable visual
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF1,
            commandName: 'Disable Visual Draw',
            description: 'Turn off visual buffer drawing',
            action: (ctx) => ctx.picColor = 255,
          ));
          break;

        case 0xF2: // Set priority
          final pri = rawData[curPos++] & 0x0F;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF2,
            commandName: 'Set Priority Color',
            description: 'Priority depth band $pri',
            action: (ctx) => ctx.picPriority = pri,
          ));
          break;

        case 0xF3: // Disable priority
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF3,
            commandName: 'Disable Priority Draw',
            description: 'Turn off priority buffer drawing',
            action: (ctx) => ctx.picPriority = 255,
          ));
          break;

        case 0xF4: // Short patterns
          getPatternTexture();
          getAbsCoords(coords);
          final pX0 = coords[0];
          final pY0 = coords[1];
          final pTex0 = patternTexture;
          final pCode0 = patternCode;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF4,
            commandName: 'Short Pattern',
            description: 'Pattern at ($pX0, $pY0)',
            action: (ctx) => ctx.drawPattern(pX0, pY0, ctx.picColor, ctx.picPriority, ctx.picControl, pCode0, pTex0),
          ));
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoords(coords);
            final pX = coords[0];
            final pY = coords[1];
            final pTex = patternTexture;
            final pCode = patternCode;
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF4,
              commandName: 'Short Pattern',
              description: 'Pattern at ($pX, $pY)',
              action: (ctx) => ctx.drawPattern(pX, pY, ctx.picColor, ctx.picPriority, ctx.picControl, pCode, pTex),
            ));
          }
          break;

        case 0xF5: // Medium lines
          getAbsCoords(coords);
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoordsMed(coords);
            final newX = coords[0];
            final newY = coords[1];
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF5,
              commandName: 'Medium Line',
              description: 'Line from ($oldX, $oldY) to ($newX, $newY)',
              action: (ctx) => ctx.drawLine(oldX, oldY + ctx.portTop, newX, newY + ctx.portTop, ctx.picColor, ctx.picPriority, ctx.picControl),
            ));
          }
          break;

        case 0xF6: // Long lines
          getAbsCoords(coords);
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getAbsCoords(coords);
            final newX = coords[0];
            final newY = coords[1];
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF6,
              commandName: 'Long Line',
              description: 'Line from ($oldX, $oldY) to ($newX, $newY)',
              action: (ctx) => ctx.drawLine(oldX, oldY + ctx.portTop, newX, newY + ctx.portTop, ctx.picColor, ctx.picPriority, ctx.picControl),
            ));
          }
          break;

        case 0xF7: // Short lines
          getAbsCoords(coords);
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoords(coords);
            final newX = coords[0];
            final newY = coords[1];
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF7,
              commandName: 'Short Line',
              description: 'Line from ($oldX, $oldY) to ($newX, $newY)',
              action: (ctx) => ctx.drawLine(oldX, oldY + ctx.portTop, newX, newY + ctx.portTop, ctx.picColor, ctx.picPriority, ctx.picControl),
            ));
          }
          break;

        case 0xF8: // Fill
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            getAbsCoords(coords);
            final fX = coords[0];
            final fY = coords[1];
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF8,
              commandName: 'Flood Fill',
              description: 'Fill at ($fX, $fY)',
              action: (ctx) => ctx.floodFill(fX, fY, ctx.picColor, ctx.picPriority, ctx.picControl),
            ));
          }
          break;

        case 0xF9: // Set pattern
          final code = rawData[curPos++];
          patternCode = code;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF9,
            commandName: 'Set Pattern Style',
            description: 'Size ${code & 7}, ${(code & 0x10) != 0 ? "Rect" : "Circle"}${(code & 0x20) != 0 ? ", Textured" : ""}',
            action: (ctx) => ctx.patternCode = code,
          ));
          break;

        case 0xFA: // Absolute pattern
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            getPatternTexture();
            getAbsCoords(coords);
            final pX = coords[0];
            final pY = coords[1];
            final pTex = patternTexture;
            final pCode = patternCode;
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xFA,
              commandName: 'Absolute Pattern',
              description: 'Pattern at ($pX, $pY)',
              action: (ctx) => ctx.drawPattern(pX, pY, ctx.picColor, ctx.picPriority, ctx.picControl, pCode, pTex),
            ));
          }
          break;

        case 0xFB: // Set control
          final ctl = rawData[curPos++] & 0x0F;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFB,
            commandName: 'Set Control Color',
            description: 'Control line $ctl',
            action: (ctx) => ctx.picControl = ctl,
          ));
          break;

        case 0xFC: // Disable control
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFC,
            commandName: 'Disable Control Draw',
            description: 'Turn off control buffer drawing',
            action: (ctx) => ctx.picControl = 255,
          ));
          break;

        case 0xFD: // Medium patterns
          getPatternTexture();
          getAbsCoords(coords);
          final mX0 = coords[0];
          final mY0 = coords[1];
          final mTex0 = patternTexture;
          final mCode0 = patternCode;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFD,
            commandName: 'Medium Pattern',
            description: 'Pattern at ($mX0, $mY0)',
            action: (ctx) => ctx.drawPattern(mX0, mY0, ctx.picColor, ctx.picPriority, ctx.picControl, mCode0, mTex0),
          ));
          while (curPos < rawData.length && rawData[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoordsMed(coords);
            final mX = coords[0];
            final mY = coords[1];
            final mTex = patternTexture;
            final mCode = patternCode;
            steps.add(SciPicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xFD,
              commandName: 'Medium Pattern',
              description: 'Pattern at ($mX, $mY)',
              action: (ctx) => ctx.drawPattern(mX, mY, ctx.picColor, ctx.picPriority, ctx.picControl, mCode, mTex),
            ));
          }
          break;

        case 0xFE: // Extended opcodes
          final subOp = rawData[curPos++];
          switch (subOp) {
            case 0: // Set palette entries
              final entries = <int, int>{};
              while (curPos < rawData.length && rawData[curPos] < 0xF0) {
                final pix = rawData[curPos++];
                final val = rawData[curPos++];
                entries[pix] = val;
              }
              steps.add(SciPicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xFE,
                commandName: 'Set Palette Entries',
                description: 'Update ${entries.length} palette mapping entries',
                action: (ctx) {
                  for (final entry in entries.entries) {
                    if (entry.key < ctx.egaPalettes.length) {
                      ctx.egaPalettes[entry.key] = entry.value;
                    }
                  }
                },
              ));
              break;

            case 1: // Set palette (40 bytes)
              final pIdx = rawData[curPos++];
              final pBytes = (pIdx < 4 && curPos + 40 <= rawData.length)
                  ? Uint8List.fromList(rawData.sublist(curPos, curPos + 40))
                  : null;
              curPos += 40;
              steps.add(SciPicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xFE,
                commandName: 'Set Palette',
                description: 'Set palette $pIdx (40 bytes)',
                action: (ctx) {
                  if (pBytes != null && pIdx < 4) {
                    ctx.egaPalettes.setRange(pIdx * 40, pIdx * 40 + 40, pBytes);
                  }
                },
              ));
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
              final size = rawData[curPos] | (rawData[curPos + 1] << 8);
              curPos += 2 + size;
              steps.add(SciPicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xFE,
                commandName: 'Embedded View',
                description: 'Embedded sprite view ($size bytes) at (${coords[0]}, ${coords[1]})',
                action: (_) {},
              ));
              break;

            case 8: // Priority table
              curPos += 14;
              break;
          }
          break;

        case 0xFF: // Terminate
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFF,
            commandName: 'End of Picture',
            description: 'Vector bytecode stream terminated',
            action: (_) {},
          ));
          break;
      }

      if (op == 0xFF) break;
    }
  }

  /// Executes steps from index 0 up to [stepIndex] (exclusive) and returns the resulting [SciPic].
  @override
  SciPic renderUpToStep(int stepIndex, {bool computeSlices = false, bool isUndithered = false}) {
    final ctx = SciPicStepContext(
      portTop: portTop,
      paletteNo: paletteNo,
      mirrored: mirrored,
    );
    final limit = stepIndex.clamp(0, steps.length);

    for (var i = 0; i < limit; i++) {
      steps[i].execute(ctx);
    }

    return ctx.toSciPic(
      picNumber: picNumber,
      computeSlices: computeSlices,
      isUndithered: isUndithered,
    );
  }
}
