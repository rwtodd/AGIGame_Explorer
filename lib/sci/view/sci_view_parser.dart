import 'dart:typed_data';
import 'package:flutter_agigame/sci/sci_exceptions.dart';
import 'package:flutter_agigame/sci/view/sci_view.dart';

/// Parser for Sierra SCI0 EGA VIEW resources (`kViewEga`).
///
/// Header (ScummVM `GfxView::initData`):
/// ```
/// [0]     loopCount       BYTE
/// [1]     flags           BYTE   0x40 uncompressed (VGA); 0x80 VGA-in-EGA
/// [2..3]  mirrorBits      WORD   LSB = loop 0 is a mirror
/// [4..5]  version         WORD   1 = SCI1.1 view
/// [6..7]  paletteOffset   WORD   ignored for true SCI0 EGA
/// [8..]   loopOffset[i]   WORD   one per loop
/// ```
///
/// Loop:
/// ```
/// [0..1]  celCount        WORD
/// [2..3]  unknown         WORD
/// [4..]   celOffset[j]    WORD   absolute offset from start of resource
/// ```
///
/// Cel:
/// ```
/// [0..1]  width           WORD
/// [2..3]  height          WORD
/// [4]     displaceX       signed BYTE
/// [5]     displaceY       BYTE
/// [6]     clearKey        BYTE
/// [7..]   RLE: high nibble = count, low nibble = color (inverse of AGI)
/// ```
class SciViewParser {
  const SciViewParser._();

  static SciView parse(Uint8List data, {int viewNumber = 0}) {
    if (data.length < 8) {
      throw SciCorruptResourceException(
        'VIEW data is too short (${data.length} bytes, minimum 8 required).',
      );
    }

    final loopCount = data[0];
    final flags = data[1];
    final mirrorBits = data[2] | (data[3] << 8);
    final version = data[4] | (data[5] << 8);
    final paletteOffset = data[6] | (data[7] << 8);

    if (flags == 0x80) {
      throw SciCorruptResourceException(
        'VIEW #$viewNumber is a VGA view (flags=0x80) in an EGA game; not supported.',
      );
    }
    if (version == 1) {
      throw SciCorruptResourceException(
        'VIEW #$viewNumber is SCI1.1 format (version=1); EGA parser supports kViewEga only.',
      );
    }

    final loopDirEnd = 8 + loopCount * 2;
    if (data.length < loopDirEnd) {
      throw SciCorruptResourceException(
        'Corrupted VIEW header: loop directory extends past EOF '
        '(need $loopDirEnd bytes, have ${data.length}).',
      );
    }

    try {
      final loopOffsets = List<int>.generate(
        loopCount,
        (i) => data[8 + i * 2] | (data[8 + i * 2 + 1] << 8),
      );

      // First unmirrored loop at each shared directory offset is the mirror source.
      final sourceLoopByOffset = <int, int>{};
      final loops = <SciViewLoop>[];

      for (var loopNo = 0; loopNo < loopCount; loopNo++) {
        final loopOffset = loopOffsets[loopNo];
        final isMirrorLoop = (mirrorBits & (1 << loopNo)) != 0;

        if (isMirrorLoop) {
          final sourceLoopNo = sourceLoopByOffset[loopOffset];
          if (sourceLoopNo != null) {
            final sourceLoop = loops[sourceLoopNo];
            final mirroredCels = <SciViewCel>[
              for (final sourceCel in sourceLoop.cels)
                SciViewCel.mirrored(
                  width: sourceCel.width,
                  height: sourceCel.height,
                  transparentColor: sourceCel.transparentColor,
                  mirrorLoop: sourceLoopNo,
                  displaceX: -sourceCel.displaceX,
                  displaceY: sourceCel.displaceY,
                ),
            ];
            loops.add(
              SciViewLoop(
                loopNumber: loopNo,
                cels: mirroredCels,
                isMirrorLoop: true,
              ),
            );
            continue;
          }
        }

        if (loopOffset + 4 > data.length) {
          throw SciCorruptResourceException(
            'Corrupted VIEW loop #$loopNo: offset $loopOffset exceeds data length ${data.length}.',
          );
        }

        final celCount = data[loopOffset] | (data[loopOffset + 1] << 8);
        final celDirStart = loopOffset + 4;
        if (data.length < celDirStart + celCount * 2) {
          throw SciCorruptResourceException(
            'Corrupted VIEW loop #$loopNo: cel directory extends past EOF.',
          );
        }

        final cels = <SciViewCel>[];
        for (var celNo = 0; celNo < celCount; celNo++) {
          final celOffset =
              data[celDirStart + celNo * 2] | (data[celDirStart + celNo * 2 + 1] << 8);
          cels.add(
            _parseCel(
              data,
              celOffset: celOffset,
              loopNo: loopNo,
              celNo: celNo,
              isMirrored: isMirrorLoop && sourceLoopByOffset[loopOffset] == null,
              mirrorLoop: loopNo,
            ),
          );
        }

        if (!isMirrorLoop) {
          sourceLoopByOffset.putIfAbsent(loopOffset, () => loopNo);
        }

        loops.add(
          SciViewLoop(
            loopNumber: loopNo,
            cels: cels,
            isMirrorLoop: isMirrorLoop,
          ),
        );
      }

      return SciView(
        viewNumber: viewNumber,
        loops: loops,
        flags: flags,
        mirrorBits: mirrorBits,
        version: version,
        paletteOffset: paletteOffset,
      );
    } on SciException {
      rethrow;
    } catch (e) {
      throw SciCorruptResourceException(
        'Error parsing VIEW resource #$viewNumber: $e',
        e,
      );
    }
  }

  static SciViewCel _parseCel(
    Uint8List data, {
    required int celOffset,
    required int loopNo,
    required int celNo,
    required bool isMirrored,
    required int mirrorLoop,
  }) {
    if (celOffset + 7 > data.length) {
      throw SciCorruptResourceException(
        'Corrupted VIEW loop #$loopNo cel #$celNo: header offset $celOffset exceeds data length ${data.length}.',
      );
    }

    final width = data[celOffset] | (data[celOffset + 1] << 8);
    final height = data[celOffset + 2] | (data[celOffset + 3] << 8);
    var displaceX = data[celOffset + 4].toSigned(8);
    final displaceY = data[celOffset + 5];
    final clearKey = data[celOffset + 6];

    if (isMirrored) {
      displaceX = -displaceX;
    }

    if (width <= 0 || height <= 0) {
      throw SciCorruptResourceException(
        'Corrupted VIEW loop #$loopNo cel #$celNo: invalid size ${width}x$height.',
      );
    }

    final pixels = _decodeEgaRle(
      data,
      offset: celOffset + 7,
      width: width,
      height: height,
      clearKey: clearKey,
    );

    return SciViewCel(
      width: width,
      height: height,
      transparentColor: clearKey,
      isMirrored: isMirrored,
      mirrorLoop: mirrorLoop,
      rawPixels: pixels,
      displaceX: displaceX,
      displaceY: displaceY,
    );
  }

  /// SCI0 EGA RLE: each byte is `(count << 4) | color`. Inverse of AGI.
  ///
  /// Matches ScummVM `unpackCelData` `kViewEga`. The output buffer is not
  /// pre-filled; transparent runs write [clearKey] like any other color.
  static Uint8List _decodeEgaRle(
    Uint8List data, {
    required int offset,
    required int width,
    required int height,
    required int clearKey,
  }) {
    final pixelCount = width * height;
    final pixels = Uint8List(pixelCount);
    var pixelNr = 0;
    var idx = offset;

    while (pixelNr < pixelCount) {
      if (idx >= data.length) {
        for (; pixelNr < pixelCount; pixelNr++) {
          pixels[pixelNr] = clearKey;
        }
        break;
      }

      final curByte = data[idx++];
      final runLength = curByte >> 4;
      final color = curByte & 0x0F;
      if (runLength == 0) {
        continue;
      }

      final remaining = pixelCount - pixelNr;
      final n = runLength < remaining ? runLength : remaining;
      for (var i = 0; i < n; i++) {
        pixels[pixelNr++] = color;
      }
      // ScummVM advances by the full run even when it would pass pixelCount.
      if (runLength > n) {
        pixelNr = pixelCount;
      }
    }

    return pixels;
  }
}
