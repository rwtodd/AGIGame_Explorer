import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';
import 'package:flutter_agigame/domain/agi_view.dart';

/// Parser for Sierra AGI VIEW resources.
class ViewParser {
  const ViewParser._();

  /// Parses raw byte data into an [AgiView] model.
  static AgiView parse(Uint8List data, {int viewNumber = 0}) {
    if (data.length < 5) {
      throw AgiException('VIEW data is too short (${data.length} bytes, minimum 5 required).');
    }

    try {
      final loopCount = data[2];
      final descLoc = data[3] | (data[4] << 8);

      final description = (descLoc > 0 && descLoc < data.length)
          ? CryptoUtils.asciizString(data, descLoc)
          : null;

      if (data.length < 5 + (loopCount * 2)) {
        throw AgiException(
          'Corrupted VIEW header: loop directory extends past EOF (need ${5 + loopCount * 2} bytes, have ${data.length}).',
        );
      }

      var loopDirectoryIdx = 5;
      final loops = <AgiViewLoop>[];

      for (var loopNo = 0; loopNo < loopCount; loopNo++) {
        final loopOffset = data[loopDirectoryIdx] | (data[loopDirectoryIdx + 1] << 8);
        loopDirectoryIdx += 2;

        if (loopOffset >= data.length) {
          throw AgiException(
            'Corrupted VIEW loop #$loopNo: offset $loopOffset exceeds data length ${data.length}.',
          );
        }

        final cellCount = data[loopOffset];
        var cellDirectoryIdx = loopOffset + 1;

        if (data.length < cellDirectoryIdx + (cellCount * 2)) {
          throw AgiException(
            'Corrupted VIEW loop #$loopNo: cel directory extends past EOF.',
          );
        }

        final cels = <AgiViewCel>[];

        for (var cellNo = 0; cellNo < cellCount; cellNo++) {
          final celRelOffset =
              data[cellDirectoryIdx] | (data[cellDirectoryIdx + 1] << 8);
          cellDirectoryIdx += 2;

          final celOffset = loopOffset + celRelOffset;
          if (celOffset + 3 > data.length) {
            throw AgiException(
              'Corrupted VIEW loop #$loopNo cel #$cellNo: header offset $celOffset exceeds data length ${data.length}.',
            );
          }

          var idx = celOffset;
          final cellWidth = data[idx++];
          final cellHeight = data[idx++];
          final transAndMirror = data[idx++];
          final transparentColor = transAndMirror & 0x0F;
          final mirroring = (transAndMirror >> 4) & 0x0F;

          final isMirrored =
              ((mirroring & 0x08) == 0x08) && ((mirroring & 0x07) != loopNo);
          final mirrorLoop = mirroring & 0x07;

          if (isMirrored) {
            cels.add(
              AgiViewCel.mirrored(
                width: cellWidth,
                height: cellHeight,
                transparentColor: transparentColor,
                mirrorLoop: mirrorLoop,
              ),
            );
          } else {
            final pixels = Uint8List(cellWidth * cellHeight);

            for (var y = 0; y < cellHeight; y++) {
              final base = y * cellWidth;
              var x = 0;

              while (true) {
                if (idx >= data.length) {
                  // Fill remaining row pixels with transparent color on unexpected EOF
                  for (; x < cellWidth; x++) {
                    pixels[base + x] = transparentColor;
                  }
                  break;
                }

                final nextB = data[idx++];
                var count = nextB & 0x0F;
                final color = (nextB >> 4) & 0x0F;

                if (nextB == 0) {
                  // Fill the rest of the line with transparent color
                  for (; x < cellWidth; x++) {
                    pixels[base + x] = transparentColor;
                  }
                  break;
                } else {
                  while (count-- > 0) {
                    if (x < cellWidth) {
                      pixels[base + x] = color;
                      x++;
                    }
                  }
                }
              }
            }

            cels.add(
              AgiViewCel.forward(
                width: cellWidth,
                height: cellHeight,
                transparentColor: transparentColor,
                rawPixels: pixels,
              ),
            );
          }
        }

        loops.add(
          AgiViewLoop(
            loopNumber: loopNo,
            cels: cels,
          ),
        );
      }

      return AgiView(
        viewNumber: viewNumber,
        description: description,
        loops: loops,
      );
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Error parsing VIEW resource #$viewNumber: $e', e);
    }
  }
}
