import 'dart:typed_data';

import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_canvas.dart';

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
  final void Function(SciPicCanvas ctx) action;

  const SciPicDrawingStep({
    required this.stepIndex,
    required this.opcode,
    required this.commandName,
    required this.description,
    required this.action,
  });

  void execute(SciPicCanvas ctx) => action(ctx);

  @override
  String toString() => 'Step #$stepIndex [$commandName]: $description';
}

/// Step-by-step vector bytecode interpreter for Sierra SCI0 pictures.
class SciPicStepInterpreter implements SierraPicStepInterpreter {
  final Uint8List rawData;
  final int? picNumber;
  final int portTop;
  final int paletteNo;
  final bool mirrored;

  @override
  final List<SciPicDrawingStep> steps = [];

  SciPicCanvas? _canvas;
  SciPic? _pic;
  int _appliedSteps = 0;

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

    void getAbsCoords(List<int> out, {bool mirror = true}) {
      final p = rawData[curPos++];
      out[0] = rawData[curPos++] + ((p & 0xF0) << 4);
      out[1] = rawData[curPos++] + ((p & 0x0F) << 8);
      if (mirror && mirrored) out[0] = 319 - out[0];
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
        case 0xF0:
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
        case 0xF1:
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF1,
            commandName: 'Disable Visual Draw',
            description: 'Turn off visual buffer drawing',
            action: (ctx) => ctx.picColor = 255,
          ));
          break;
        case 0xF2:
          final pri = rawData[curPos++] & 0x0F;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF2,
            commandName: 'Set Priority Color',
            description: 'Priority depth band $pri',
            action: (ctx) => ctx.picPriority = pri,
          ));
          break;
        case 0xF3:
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF3,
            commandName: 'Disable Priority Draw',
            description: 'Turn off priority buffer drawing',
            action: (ctx) => ctx.picPriority = 255,
          ));
          break;
        case 0xF4:
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
        case 0xF5:
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
        case 0xF6:
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
        case 0xF7:
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
        case 0xF8:
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
        case 0xF9:
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
        case 0xFA:
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
        case 0xFB:
          final ctl = rawData[curPos++] & 0x0F;
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFB,
            commandName: 'Set Control Color',
            description: 'Control line $ctl',
            action: (ctx) => ctx.picControl = ctl,
          ));
          break;
        case 0xFC:
          steps.add(SciPicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFC,
            commandName: 'Disable Control Draw',
            description: 'Turn off control buffer drawing',
            action: (ctx) => ctx.picControl = 255,
          ));
          break;
        case 0xFD:
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
        case 0xFE:
          final subOp = rawData[curPos++];
          switch (subOp) {
            case 0:
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
            case 1:
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
            case 7:
              getAbsCoords(coords, mirror: false);
              final size = rawData[curPos] | (rawData[curPos + 1] << 8);
              curPos += 2;
              final headerPos = curPos;
              final vx = coords[0];
              final vy = coords[1];
              curPos += size;
              steps.add(SciPicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xFE,
                commandName: 'Embedded View',
                description: 'Embedded sprite view ($size bytes) at ($vx, $vy)',
                action: (ctx) => ctx.drawEmbeddedView(rawData, headerPos, vx, vy),
              ));
              break;
            case 8:
              curPos += 14;
              break;
          }
          break;
        case 0xFF:
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

  @override
  SciPic renderUpToStep(int stepIndex, {bool computeSlices = false, bool isUndithered = false}) {
    final limit = stepIndex.clamp(0, steps.length);
    if (_canvas == null || limit < _appliedSteps) {
      _canvas = SciPicCanvas(
        portTop: portTop,
        paletteNo: paletteNo,
        mirrored: mirrored,
      );
      _appliedSteps = 0;
      _pic = null;
    }
    for (var i = _appliedSteps; i < limit; i++) {
      steps[i].execute(_canvas!);
    }
    _appliedSteps = limit;

    final wantUnditheredSlices = computeSlices && isUndithered;
    if (_pic == null) {
      _pic = _canvas!.toSciPic(
        picNumber: picNumber,
        computeSlices: computeSlices && !isUndithered,
        computeUnditheredSlices: wantUnditheredSlices,
        isUndithered: isUndithered,
      );
    } else {
      _canvas!.writeInto(
        _pic!,
        computeSlices: computeSlices && !isUndithered,
        computeUnditheredSlices: wantUnditheredSlices,
        isUndithered: isUndithered,
      );
    }
    return _pic!;
  }
}
