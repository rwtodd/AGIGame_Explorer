import 'dart:typed_data';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/picture/pen_pattern.dart';
import 'package:flutter_agigame/picture/pic_pen.dart';
import 'package:flutter_agigame/picture/pic_rasterizer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// A discrete drawing operation decoded from an AGI PICTURE vector stream.
class PicDrawingStep {
  final int stepIndex;
  final int opcode;
  final String commandName;
  final String description;
  final void Function(PicStepContext ctx) action;

  const PicDrawingStep({
    required this.stepIndex,
    required this.opcode,
    required this.commandName,
    required this.description,
    required this.action,
  });

  void execute(PicStepContext ctx) => action(ctx);

  @override
  String toString() => 'Step #$stepIndex [$commandName]: $description';
}

/// Execution context for stepping through picture drawing opcodes.
class PicStepContext {
  final bool isV3;
  final Uint8List visualBuffer;
  final PriorityBuffer priorityBuffer;
  int picColor = -1;
  int priColor = -1;

  late final RectanglePen rectanglePen;
  late final PicPen circlePen;
  late PicPen currentPen;

  late SplatterPattern splatterPattern;
  late PenPattern currentPattern;

  PicStepContext({required this.isV3})
      : visualBuffer = Uint8List(AgiDisplay.nativeWidth * AgiDisplay.pictureHeight),
        priorityBuffer = PriorityBuffer() {
    visualBuffer.fillRange(0, visualBuffer.length, 15);
    rectanglePen = RectanglePen()..size = 0;
    circlePen = (isV3 ? V3CirclePen() : CirclePen())..size = 0;
    currentPen = rectanglePen;
    splatterPattern = SplatterPattern();
    currentPattern = SolidPenPattern.instance;
  }

  void plotPoint(int x, int y) {
    if (x < 0 || x >= AgiDisplay.nativeWidth || y < 0 || y >= AgiDisplay.pictureHeight) {
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

  AgiPic toAgiPic({bool computeSlices = true}) {
    final slices = computeSlices
        ? PictureSlicer.slice(
            visualPixels: visualBuffer,
            priorityBuffer: priorityBuffer,
          )
        : <int, PictureSlice>{};

    return AgiPic(
      visualPixels: Uint8List.fromList(visualBuffer),
      priorityBuffer: priorityBuffer.clone(),
      slices: slices,
    );
  }
}

/// Interpreter that decodes PICTURE vector commands into individual steps
/// and allows rendering up to any step index.
class PicStepInterpreter {
  final Uint8List rawData;
  final bool isV3;
  final List<PicDrawingStep> steps = [];

  PicStepInterpreter(this.rawData, {this.isV3 = false}) {
    _decodeSteps();
  }

  int get totalSteps => steps.length;

  int _clipX(int x) => x < 0 ? 0 : (x >= AgiDisplay.nativeWidth ? AgiDisplay.nativeWidth - 1 : x);
  int _clipY(int y) => y < 0 ? 0 : (y >= AgiDisplay.pictureHeight ? AgiDisplay.pictureHeight - 1 : y);

  void _decodeSteps() {
    int idx = 0;
    int stepCounter = 0;
    bool takesPatternArg = false;

    while (idx < rawData.length) {
      final opcode = rawData[idx++] & 0xFF;
      switch (opcode) {
        case 0xF0: // Set visual color
          if (idx < rawData.length) {
            final col = rawData[idx++] & 0x0F;
            final colName = col < EgaColors.colorNames.length ? EgaColors.colorNames[col] : '$col';
            steps.add(PicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF0,
              commandName: 'Set Visual Color',
              description: 'Color $col ($colName)',
              action: (ctx) => ctx.picColor = col,
            ));
          }
          break;

        case 0xF1: // Disable visual draw
          steps.add(PicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF1,
            commandName: 'Disable Visual Draw',
            description: 'Turn off visual buffer drawing',
            action: (ctx) => ctx.picColor = -1,
          ));
          break;

        case 0xF2: // Set priority color
          if (idx < rawData.length) {
            final pri = rawData[idx++] & 0x0F;
            final desc = pri < 4
                ? 'Priority $pri (Control Line: ${EgaColors.controlNames[pri]})'
                : 'Priority $pri (Depth Band $pri)';
            steps.add(PicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF2,
              commandName: 'Set Priority Color',
              description: desc,
              action: (ctx) => ctx.priColor = pri,
            ));
          }
          break;

        case 0xF3: // Disable priority draw
          steps.add(PicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xF3,
            commandName: 'Disable Priority Draw',
            description: 'Turn off priority buffer drawing',
            action: (ctx) => ctx.priColor = -1,
          ));
          break;

        case 0xF4: // Draw Y-Corner
          {
            if (idx >= rawData.length) break;
            int x = rawData[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            if (idx >= rawData.length) break;
            int y = rawData[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            x = _clipX(x);
            y = _clipY(y);

            final lines = <List<int>>[];
            int curX = x;
            int curY = y;
            bool changeY = true;

            while (idx < rawData.length) {
              final nextCoord = rawData[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              int nextX = curX;
              int nextY = curY;
              if (changeY) {
                nextY = _clipY(nextCoord);
              } else {
                nextX = _clipX(nextCoord);
              }
              lines.add([curX, curY, nextX, nextY]);
              changeY = !changeY;
              curX = nextX;
              curY = nextY;
            }

            if (lines.isEmpty) {
              final ptX = x;
              final ptY = y;
              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xF4,
                commandName: 'Plot Point',
                description: 'Point at ($ptX, $ptY)',
                action: (ctx) => ctx.plotPoint(ptX, ptY),
              ));
            } else {
              for (final l in lines) {
                final x1 = l[0], y1 = l[1], x2 = l[2], y2 = l[3];
                steps.add(PicDrawingStep(
                  stepIndex: stepCounter++,
                  opcode: 0xF4,
                  commandName: 'Y-Corner Line',
                  description: '($x1, $y1) -> ($x2, $y2)',
                  action: (ctx) => ctx.drawLine(x1, y1, x2, y2),
                ));
              }
            }
          }
          break;

        case 0xF5: // Draw X-Corner
          {
            if (idx >= rawData.length) break;
            int x = rawData[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            if (idx >= rawData.length) break;
            int y = rawData[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            x = _clipX(x);
            y = _clipY(y);

            final lines = <List<int>>[];
            int curX = x;
            int curY = y;
            bool changeY = false;

            while (idx < rawData.length) {
              final nextCoord = rawData[idx];
              if (nextCoord >= 0xF0) break;
              idx++;

              int nextX = curX;
              int nextY = curY;
              if (changeY) {
                nextY = _clipY(nextCoord);
              } else {
                nextX = _clipX(nextCoord);
              }
              lines.add([curX, curY, nextX, nextY]);
              changeY = !changeY;
              curX = nextX;
              curY = nextY;
            }

            if (lines.isEmpty) {
              final ptX = x;
              final ptY = y;
              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xF5,
                commandName: 'Plot Point',
                description: 'Point at ($ptX, $ptY)',
                action: (ctx) => ctx.plotPoint(ptX, ptY),
              ));
            } else {
              for (final l in lines) {
                final x1 = l[0], y1 = l[1], x2 = l[2], y2 = l[3];
                steps.add(PicDrawingStep(
                  stepIndex: stepCounter++,
                  opcode: 0xF5,
                  commandName: 'X-Corner Line',
                  description: '($x1, $y1) -> ($x2, $y2)',
                  action: (ctx) => ctx.drawLine(x1, y1, x2, y2),
                ));
              }
            }
          }
          break;

        case 0xF6: // Absolute Lines
          {
            if (idx >= rawData.length) break;
            int x = rawData[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            x = _clipX(x);

            if (idx >= rawData.length) break;
            int y = rawData[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = _clipY(y);

            final lines = <List<int>>[];
            int curX = x;
            int curY = y;

            while (idx < rawData.length) {
              int x2 = rawData[idx++];
              if (x2 >= 0xF0) {
                idx--;
                break;
              }
              x2 = _clipX(x2);

              if (idx >= rawData.length) break;
              int y2 = rawData[idx++];
              if (y2 >= 0xF0) {
                idx--;
                break;
              }
              y2 = _clipY(y2);

              lines.add([curX, curY, x2, y2]);
              curX = x2;
              curY = y2;
            }

            if (lines.isEmpty) {
              final ptX = x;
              final ptY = y;
              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xF6,
                commandName: 'Plot Point',
                description: 'Point at ($ptX, $ptY)',
                action: (ctx) => ctx.plotPoint(ptX, ptY),
              ));
            } else {
              for (final l in lines) {
                final x1 = l[0], y1 = l[1], x2 = l[2], y2 = l[3];
                steps.add(PicDrawingStep(
                  stepIndex: stepCounter++,
                  opcode: 0xF6,
                  commandName: 'Absolute Line',
                  description: '($x1, $y1) -> ($x2, $y2)',
                  action: (ctx) => ctx.drawLine(x1, y1, x2, y2),
                ));
              }
            }
          }
          break;

        case 0xF7: // Relative Lines
          {
            if (idx >= rawData.length) break;
            int x = rawData[idx++];
            if (x >= 0xF0) {
              idx--;
              break;
            }
            x = _clipX(x);

            if (idx >= rawData.length) break;
            int y = rawData[idx++];
            if (y >= 0xF0) {
              idx--;
              break;
            }
            y = _clipY(y);

            final lines = <List<int>>[];
            int curX = x;
            int curY = y;

            while (idx < rawData.length) {
              final relmove = rawData[idx];
              if (relmove >= 0xF0) break;
              idx++;

              final int dx = ((relmove & 0x80) != 0 ? -1 : 1) * ((relmove >> 4) & 0x07);
              final int dy = ((relmove & 0x08) != 0 ? -1 : 1) * (relmove & 0x07);

              final int nextX = _clipX(curX + dx);
              final int nextY = _clipY(curY + dy);

              lines.add([curX, curY, nextX, nextY]);
              curX = nextX;
              curY = nextY;
            }

            if (lines.isEmpty) {
              final ptX = x;
              final ptY = y;
              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xF7,
                commandName: 'Plot Point',
                description: 'Point at ($ptX, $ptY)',
                action: (ctx) => ctx.plotPoint(ptX, ptY),
              ));
            } else {
              for (final l in lines) {
                final x1 = l[0], y1 = l[1], x2 = l[2], y2 = l[3];
                steps.add(PicDrawingStep(
                  stepIndex: stepCounter++,
                  opcode: 0xF7,
                  commandName: 'Relative Line',
                  description: '($x1, $y1) -> ($x2, $y2)',
                  action: (ctx) => ctx.drawLine(x1, y1, x2, y2),
                ));
              }
            }
          }
          break;

        case 0xF8: // Flood Fill
          {
            while (idx < rawData.length) {
              final x = rawData[idx++];
              if (x >= 0xF0) {
                idx--;
                break;
              }
              if (idx >= rawData.length) break;
              final y = rawData[idx++];
              if (y >= 0xF0) {
                idx--;
                break;
              }
              final fillX = _clipX(x);
              final fillY = _clipY(y);
              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xF8,
                commandName: 'Flood Fill',
                description: 'Fill at ($fillX, $fillY)',
                action: (ctx) => ctx.fill(fillX, fillY),
              ));
            }
          }
          break;

        case 0xF9: // Set Pen
          if (idx < rawData.length) {
            final arg = rawData[idx++];
            final size = arg & 0x07;
            final isRect = (arg & 0x10) != 0;
            final isSplatter = (arg & 0x20) != 0;
            takesPatternArg = isSplatter;

            steps.add(PicDrawingStep(
              stepIndex: stepCounter++,
              opcode: 0xF9,
              commandName: 'Set Pen',
              description:
                  '${isRect ? "Rectangle" : "Circle"} size $size, ${isSplatter ? "Splatter" : "Solid"}',
              action: (ctx) {
                ctx.currentPen = isRect ? ctx.rectanglePen : ctx.circlePen;
                ctx.currentPen.size = size;
                ctx.currentPattern =
                    isSplatter ? ctx.splatterPattern : SolidPenPattern.instance;
              },
            ));
          }
          break;

        case 0xFA: // Plot Pen
          {
            while (idx < rawData.length) {
              int? pattNumber;
              if (takesPatternArg) {
                if (idx >= rawData.length) break;
                final b = rawData[idx++];
                if (b >= 0xF0) {
                  idx--;
                  break;
                }
                pattNumber = b;
              }

              if (idx >= rawData.length) break;
              final x = rawData[idx++];
              if (x >= 0xF0) {
                idx--;
                break;
              }

              if (idx >= rawData.length) break;
              final y = rawData[idx++];
              if (y >= 0xF0) {
                idx--;
                break;
              }

              final ptX = _clipX(x);
              final ptY = _clipY(y);
              final capturedPatt = pattNumber;

              steps.add(PicDrawingStep(
                stepIndex: stepCounter++,
                opcode: 0xFA,
                commandName: 'Plot Pen',
                description: capturedPatt != null
                    ? 'Pattern $capturedPatt at ($ptX, $ptY)'
                    : 'Pen at ($ptX, $ptY)',
                action: (ctx) {
                  if (capturedPatt != null) {
                    ctx.currentPattern.setPattern(capturedPatt);
                  }
                  ctx.currentPen.drawAt(ctx.plotPoint, ptX, ptY, ctx.currentPattern);
                },
              ));
            }
          }
          break;

        case 0xFF: // End of picture
          steps.add(PicDrawingStep(
            stepIndex: stepCounter++,
            opcode: 0xFF,
            commandName: 'End of Picture',
            description: 'Vector bytecode stream terminated',
            action: (_) {},
          ));
          break;

        default:
          break;
      }
    }
  }

  /// Executes steps from index 0 up to [stepIndex] (inclusive) and returns the resulting [AgiPic].
  AgiPic renderUpToStep(int stepIndex, {bool computeSlices = false}) {
    final ctx = PicStepContext(isV3: isV3);
    final limit = stepIndex.clamp(0, steps.length);

    for (var i = 0; i < limit; i++) {
      steps[i].execute(ctx);
    }

    return ctx.toAgiPic(computeSlices: computeSlices);
  }
}
