import 'dart:typed_data';

import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/sci/picture/sci_pic_canvas.dart';

/// Vector bytecode interpreter for Sierra SCI0 and SCI1-EGA PICTURE resources.
class SciPicInterpreter {
  static const int scriptWidth = SciPicCanvas.scriptWidth;
  static const int scriptHeight = SciPicCanvas.scriptHeight;
  static const List<int> defaultEgaPalette = SciPicCanvas.defaultEgaPalette;
  static const List<bool> patternTextures = SciPicCanvas.patternTextures;
  static const List<int> patternTextureOffset = SciPicCanvas.patternTextureOffset;
  static List<int> get unditheredPalette256 => SciPicCanvas.unditheredPalette256;

  /// Interprets raw SCI0 PICTURE vector bytecode [data] and returns a [SciPic].
  static SciPic interpret(
    Uint8List data, {
    int? picNumber,
    int portTop = 10,
    int paletteNo = 0,
    bool mirrored = false,
    bool computeSlices = true,
    bool computeUnditheredSlices = false,
  }) {
    final canvas = SciPicCanvas(
      portTop: portTop,
      paletteNo: paletteNo,
      mirrored: mirrored,
    );

    int curPos = 0;
    int patternTexture = 0;
    final coords = [0, 0];

    int getPaletteEntry(int colorIndex) => canvas.getPaletteEntry(colorIndex);

    void getAbsCoords(List<int> out, {bool mirror = true}) {
      final p = data[curPos++];
      out[0] = data[curPos++] + ((p & 0xF0) << 4);
      out[1] = data[curPos++] + ((p & 0x0F) << 8);
      if (mirror && mirrored) out[0] = 319 - out[0];
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

    void getPatternTexture() {
      if ((canvas.patternCode & 0x20) != 0) {
        patternTexture = (data[curPos++] >> 1) & 0x7F;
      }
    }

    void stamp(int x, int y) {
      canvas.drawPattern(
        x,
        y,
        canvas.picColor,
        canvas.picPriority,
        canvas.picControl,
        canvas.patternCode,
        patternTexture,
      );
    }

    void line(int x1, int y1, int x2, int y2) {
      canvas.drawLine(
        x1,
        y1 + portTop,
        x2,
        y2 + portTop,
        canvas.picColor,
        canvas.picPriority,
        canvas.picControl,
      );
    }

    while (curPos < data.length) {
      final op = data[curPos++];
      switch (op) {
        case 0xF0:
          final rawColor = data[curPos++];
          final palColor = getPaletteEntry(rawColor);
          canvas.picColor = (palColor ^ (palColor << 4)) & 0xFF;
          break;
        case 0xF1:
          canvas.picColor = 255;
          break;
        case 0xF2:
          canvas.picPriority = data[curPos++] & 0x0F;
          break;
        case 0xF3:
          canvas.picPriority = 255;
          break;
        case 0xF4:
          getPatternTexture();
          getAbsCoords(coords);
          stamp(coords[0], coords[1]);
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoords(coords);
            stamp(coords[0], coords[1]);
          }
          break;
        case 0xF5:
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoordsMed(coords);
            line(oldX, oldY, coords[0], coords[1]);
          }
          break;
        case 0xF6:
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getAbsCoords(coords);
            line(oldX, oldY, coords[0], coords[1]);
          }
          break;
        case 0xF7:
          getAbsCoords(coords);
          while (curPos < data.length && data[curPos] < 0xF0) {
            final oldX = coords[0];
            final oldY = coords[1];
            getRelCoords(coords);
            line(oldX, oldY, coords[0], coords[1]);
          }
          break;
        case 0xF8:
          while (curPos < data.length && data[curPos] < 0xF0) {
            getAbsCoords(coords);
            canvas.floodFill(coords[0], coords[1], canvas.picColor, canvas.picPriority, canvas.picControl);
          }
          break;
        case 0xF9:
          canvas.patternCode = data[curPos++];
          break;
        case 0xFA:
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getAbsCoords(coords);
            stamp(coords[0], coords[1]);
          }
          break;
        case 0xFB:
          canvas.picControl = data[curPos++] & 0x0F;
          break;
        case 0xFC:
          canvas.picControl = 255;
          break;
        case 0xFD:
          getPatternTexture();
          getAbsCoords(coords);
          stamp(coords[0], coords[1]);
          while (curPos < data.length && data[curPos] < 0xF0) {
            getPatternTexture();
            getRelCoordsMed(coords);
            stamp(coords[0], coords[1]);
          }
          break;
        case 0xFE:
          final subOp = data[curPos++];
          switch (subOp) {
            case 0:
              while (curPos < data.length && data[curPos] < 0xF0) {
                final pix = data[curPos++];
                if (pix < canvas.egaPalettes.length) {
                  canvas.egaPalettes[pix] = data[curPos++];
                } else {
                  curPos++;
                }
              }
              break;
            case 1:
              final pIdx = data[curPos++];
              if (pIdx < 4) {
                final base = pIdx * 40;
                for (int i = 0; i < 40; i++) {
                  canvas.egaPalettes[base + i] = data[curPos++];
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
            case 7:
              getAbsCoords(coords, mirror: false);
              final size = data[curPos] | (data[curPos + 1] << 8);
              curPos += 2;
              canvas.drawEmbeddedView(data, curPos, coords[0], coords[1]);
              curPos += size;
              break;
            case 8:
              curPos += 14;
              break;
          }
          break;
        case 0xFF:
          break;
      }
      if (op == 0xFF) break;
    }

    return canvas.toSciPic(
      picNumber: picNumber,
      computeSlices: computeSlices,
      computeUnditheredSlices: computeUnditheredSlices,
    );
  }
}
