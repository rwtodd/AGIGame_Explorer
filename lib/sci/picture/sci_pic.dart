import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// Completes a [ui.decodeImageFromPixels] callback without throwing unhandled
/// exceptions if the owner was disposed while GPU texture upload was in flight.
void _completeGpuDecode({
  required bool disposed,
  required Completer<ui.Image> completer,
  required ui.Image image,
  required void Function(ui.Image image) onSuccess,
}) {
  if (disposed) {
    image.dispose();
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('GPU image decode completed after dispose'),
      );
    }
    return;
  }
  onSuccess(image);
  if (!completer.isCompleted) {
    completer.complete(image);
  }
}

/// Represents an interpreted 320x200 SCI0 / SCI1-EGA PICTURE resource.
///
/// Contains:
/// 1. [visualPixels]: 320x200 dithered EGA color indices (0..15).
/// 2. [priorityPixels]: 320x200 pure Z-buffer depth priority map (0..15).
/// 3. [controlPixels]: 320x200 collision and trigger barrier map (0..15).
/// 4. [rawColorPairs]: 320x200 byte buffer storing the decoded EGA color pairs
///    `(c1 << 4) | c2`, supporting non-dithered 40-color visual blending.
/// 5. [slices] and [unditheredSlices]: 16-layer Impeller compositor textures.
class SciPic implements SierraPicture {
  static final List<int> _unditheredPacked = List<int>.generate(256, (byteVal) {
    final c1 = (byteVal >> 4) & 0x0F;
    final c2 = byteVal & 0x0F;
    final p1 = EgaColors.rgbaPacked[c1];
    final p2 = EgaColors.rgbaPacked[c2];
    final r = ((p1 & 0xFF) + (p2 & 0xFF)) >> 1;
    final g = (((p1 >> 8) & 0xFF) + ((p2 >> 8) & 0xFF)) >> 1;
    final b = (((p1 >> 16) & 0xFF) + ((p2 >> 16) & 0xFF)) >> 1;
    return 0xFF000000 | (b << 16) | (g << 8) | r;
  });

  static const int nativeWidth = 320;
  static const int nativeHeight = 200;
  static const int renderedWidth = 320;
  static const int renderedHeight = 200;

  @override
  int get width => nativeWidth;

  @override
  int get height => nativeHeight;

  @override
  int get rasterEpoch => _rasterEpoch;

  @override
  bool get isDisposed => _isDisposed;

  int _rasterEpoch = 0;

  @override
  int effectivePriorityAtPixel(int x, int y) => priorityAtPixel(x, y);

  /// Computes the 40-color blended [ui.Color] for a given raw color pair byte `(c1 << 4) | c2`.
  static ui.Color blendedColorForPair(int byteVal) {
    final c1 = (byteVal >> 4) & 0x0F;
    final c2 = byteVal & 0x0F;
    final b1 = EgaColors.rgbaBytes[c1];
    final b2 = EgaColors.rgbaBytes[c2];
    return ui.Color.fromARGB(
      255,
      (b1[0] + b2[0]) >> 1,
      (b1[1] + b2[1]) >> 1,
      (b1[2] + b2[2]) >> 1,
    );
  }

  @override
  int? picNumber;

  /// Raw 320x200 dithered EGA color buffer (0..15).
  @override
  final Uint8List visualPixels;

  /// Raw 320x200 depth priority buffer (0..15).
  final Uint8List priorityPixels;

  /// Raw 320x200 collision/script control buffer (0..15).
  final Uint8List controlPixels;

  /// Raw 320x200 encoded EGA color pair buffer `(c1 << 4) | c2`.
  final Uint8List rawColorPairs;

  /// Authentic EGA dithered priority slices (0..15).
  Map<int, PictureSlice> _ditheredSlices;

  /// Blended 40-color non-dithered priority slices (0..15).
  Map<int, PictureSlice> _unditheredSlices;

  /// Blended 40-color non-dithered priority slices (0..15).
  Map<int, PictureSlice> get unditheredSlices => _unditheredSlices;

  /// Whether undithered visual slices are actively exposed via [slices].
  bool isUndithered;

  ui.Image? _cachedFlatVisualImage;
  ui.Image? _cachedUnditheredVisualImage;
  ui.Image? _cachedPriorityMapImage;
  ui.Image? _cachedControlMapImage;
  final List<ui.Image> _detachedGpuImages = [];
  bool _isDisposed = false;

  @override
  ui.Image? get cachedFlatVisualImage => _cachedFlatVisualImage;

  ui.Image? get cachedUnditheredVisualImage => _cachedUnditheredVisualImage;

  @override
  ui.Image? get cachedPriorityMapImage => _cachedPriorityMapImage;

  @override
  ui.Image? get cachedControlMapImage => _cachedControlMapImage;

  /// Custom priority bands from opcode 0xFE 0x08, if defined by this picture.
  final List<int>? priorityBands;

  SciPic({
    this.picNumber,
    required this.visualPixels,
    required this.priorityPixels,
    required this.controlPixels,
    required this.rawColorPairs,
    required Map<int, PictureSlice> slices,
    required Map<int, PictureSlice> unditheredSlices,
    this.isUndithered = false,
    this.priorityBands,
  })  : _ditheredSlices = slices,
        // ignore: prefer_initializing_formals
        _unditheredSlices = unditheredSlices {
    const totalPixels = nativeWidth * nativeHeight;
    if (visualPixels.length != totalPixels) {
      throw ArgumentError('visualPixels must have $totalPixels bytes');
    }
    if (priorityPixels.length != totalPixels) {
      throw ArgumentError('priorityPixels must have $totalPixels bytes');
    }
    if (controlPixels.length != totalPixels) {
      throw ArgumentError('controlPixels must have $totalPixels bytes');
    }
    if (rawColorPairs.length != totalPixels) {
      throw ArgumentError('rawColorPairs must have $totalPixels bytes');
    }
  }

  @override
  bool get isSci => true;

  @override
  Map<int, PictureSlice> get slices =>
      isUndithered ? unditheredSlices : _ditheredSlices;

  @override
  PictureSlice? getSlice(int priority) => slices[priority];

  @override
  List<PictureSlice> get activeSlices =>
      slices.values.where((s) => s.hasVisiblePixels).toList();

  @override
  int priorityAtPixel(int x, int y) {
    if (x < 0 || x >= nativeWidth || y < 0 || y >= nativeHeight) return 0;
    return priorityPixels[y * nativeWidth + x];
  }

  @override
  int controlAtPixel(int x, int y) {
    if (x < 0 || x >= nativeWidth || y < 0 || y >= nativeHeight) return 0;
    return controlPixels[y * nativeWidth + x];
  }

  @override
  int visualAtPixel(int x, int y) {
    if (x < 0 || x >= nativeWidth || y < 0 || y >= nativeHeight) return 0;
    return visualPixels[y * nativeWidth + x];
  }

  /// Gets the raw color pair `(c1 << 4) | c2` at `(x, y)` for undithered inspection.
  int rawColorPairAtPixel(int x, int y) {
    if (x < 0 || x >= nativeWidth || y < 0 || y >= nativeHeight) return 0;
    return rawColorPairs[y * nativeWidth + x];
  }

  @override
  Uint8List renderFlatVisualRgba({bool? undithered}) {
    final useUndithered = undithered ?? isUndithered;
    final outBytes = Uint8List(renderedWidth * renderedHeight * 4);

    if (!useUndithered) {
      for (int i = 0; i < visualPixels.length; i++) {
        final colIdx = visualPixels[i] & 0x0F;
        final col = EgaColors.rgbaBytes[colIdx];
        final outIdx = i * 4;
        outBytes[outIdx + 0] = col[0];
        outBytes[outIdx + 1] = col[1];
        outBytes[outIdx + 2] = col[2];
        outBytes[outIdx + 3] = col[3];
      }
    } else {
      for (int i = 0; i < rawColorPairs.length; i++) {
        final byteVal = rawColorPairs[i];
        final c1 = (byteVal >> 4) & 0x0F;
        final c2 = byteVal & 0x0F;
        final col1 = EgaColors.rgbaBytes[c1];
        final col2 = EgaColors.rgbaBytes[c2];
        final outIdx = i * 4;
        outBytes[outIdx + 0] = (col1[0] + col2[0]) >> 1;
        outBytes[outIdx + 1] = (col1[1] + col2[1]) >> 1;
        outBytes[outIdx + 2] = (col1[2] + col2[2]) >> 1;
        outBytes[outIdx + 3] = 255;
      }
    }
    return outBytes;
  }

  @override
  Future<ui.Image> toFlatVisualUiImage({bool? undithered}) async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed SciPic.');
    }
    final useUndithered = undithered ?? isUndithered;
    if (useUndithered && _cachedUnditheredVisualImage != null) {
      return _cachedUnditheredVisualImage!;
    }
    if (!useUndithered && _cachedFlatVisualImage != null) {
      return _cachedFlatVisualImage!;
    }

    final flatRgba = renderFlatVisualRgba(undithered: useUndithered);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      flatRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _completeGpuDecode(
          disposed: _isDisposed,
          completer: completer,
          image: image,
          onSuccess: (img) {
            if (useUndithered) {
              _cachedUnditheredVisualImage = img;
            } else {
              _cachedFlatVisualImage = img;
            }
          },
        );
      },
    );
    return completer.future;
  }

  @override
  Uint8List renderPriorityMapRgba() {
    final outBytes = Uint8List(renderedWidth * renderedHeight * 4);
    for (int i = 0; i < priorityPixels.length; i++) {
      final pri = priorityPixels[i] & 0x0F;
      final col = EgaColors.rgbaBytes[pri];
      final outIdx = i * 4;
      outBytes[outIdx + 0] = col[0];
      outBytes[outIdx + 1] = col[1];
      outBytes[outIdx + 2] = col[2];
      outBytes[outIdx + 3] = col[3];
    }
    return outBytes;
  }

  @override
  Future<ui.Image> toPriorityMapUiImage() async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed SciPic.');
    }
    if (_cachedPriorityMapImage != null) return _cachedPriorityMapImage!;

    final priRgba = renderPriorityMapRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      priRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _completeGpuDecode(
          disposed: _isDisposed,
          completer: completer,
          image: image,
          onSuccess: (img) => _cachedPriorityMapImage = img,
        );
      },
    );
    return completer.future;
  }

  @override
  Uint8List renderControlMapRgba() {
    final outBytes = Uint8List(renderedWidth * renderedHeight * 4);
    for (int i = 0; i < controlPixels.length; i++) {
      final ctl = controlPixels[i] & 0x0F;
      final outIdx = i * 4;
      if (ctl == 0) {
        // Non-control: transparent
        outBytes[outIdx + 0] = 0;
        outBytes[outIdx + 1] = 0;
        outBytes[outIdx + 2] = 0;
        outBytes[outIdx + 3] = 0;
      } else {
        final col = EgaColors.rgbaBytes[ctl];
        outBytes[outIdx + 0] = col[0];
        outBytes[outIdx + 1] = col[1];
        outBytes[outIdx + 2] = col[2];
        outBytes[outIdx + 3] = col[3];
      }
    }
    return outBytes;
  }

  @override
  Future<ui.Image> toControlMapUiImage() async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed SciPic.');
    }
    if (_cachedControlMapImage != null) return _cachedControlMapImage!;

    final ctrlRgba = renderControlMapRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      ctrlRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _completeGpuDecode(
          disposed: _isDisposed,
          completer: completer,
          image: image,
          onSuccess: (img) => _cachedControlMapImage = img,
        );
      },
    );
    return completer.future;
  }

  @override
  FutureOr<void> preloadGpuTextures({bool includeDiagnosticMaps = false}) {
    final futures = <Future<ui.Image>>[];
    final activeSliceMap = isUndithered ? unditheredSlices : _ditheredSlices;
    for (final slice in activeSliceMap.values) {
      if (slice.hasVisiblePixels && slice.cachedUiImage == null) {
        futures.add(slice.toUiImage());
      }
    }
    if (includeDiagnosticMaps) {
      if (_cachedFlatVisualImage == null) futures.add(toFlatVisualUiImage(undithered: false));
      if (_cachedUnditheredVisualImage == null) futures.add(toFlatVisualUiImage(undithered: true));
      if (_cachedPriorityMapImage == null) futures.add(toPriorityMapUiImage());
      if (_cachedControlMapImage == null) futures.add(toControlMapUiImage());
    }
    if (futures.isEmpty) return null;
    return Future.wait<ui.Image?>([
      for (final f in futures)
        f.then<ui.Image?>((img) => img, onError: (Object _, StackTrace _) => null),
    ]).then((_) {});
  }

  void _stashGpuImage(ui.Image? image) {
    if (image != null) _detachedGpuImages.add(image);
  }

  /// Drops GPU image handles without disposing them so the current frame can
  /// still paint. Call [disposeDetachedGpuImages] on the next frame.
  void detachGpuCache() {
    _stashGpuImage(_cachedFlatVisualImage);
    _cachedFlatVisualImage = null;
    _stashGpuImage(_cachedUnditheredVisualImage);
    _cachedUnditheredVisualImage = null;
    _stashGpuImage(_cachedPriorityMapImage);
    _cachedPriorityMapImage = null;
    _stashGpuImage(_cachedControlMapImage);
    _cachedControlMapImage = null;
    for (final slice in _ditheredSlices.values) {
      _stashGpuImage(slice.detachCachedImage());
    }
    for (final slice in _unditheredSlices.values) {
      _stashGpuImage(slice.detachCachedImage());
    }
  }

  void disposeDetachedGpuImages() {
    for (final image in _detachedGpuImages) {
      image.dispose();
    }
    _detachedGpuImages.clear();
  }

  void invalidateGpuCache() {
    detachGpuCache();
    disposeDetachedGpuImages();
  }

  void replaceSlices({
    Map<int, PictureSlice>? dithered,
    Map<int, PictureSlice>? undithered,
  }) {
    if (dithered != null) {
      for (final slice in _ditheredSlices.values) {
        _stashGpuImage(slice.detachCachedImage());
      }
      _ditheredSlices = dithered;
    }
    if (undithered != null) {
      for (final slice in _unditheredSlices.values) {
        _stashGpuImage(slice.detachCachedImage());
      }
      _unditheredSlices = undithered;
    }
    detachGpuCache();
  }

  void ensureSlices({bool undithered = false}) {
    if (undithered) {
      if (_unditheredSlices.isEmpty) {
        _unditheredSlices = PictureSlicer.slice(
          visualPixels: rawColorPairs,
          priorityPixels: priorityPixels,
          profile: DisplayProfile.sci0,
          paletteRgbaPacked: _unditheredPacked,
        );
      }
    } else if (_ditheredSlices.isEmpty) {
      _ditheredSlices = PictureSlicer.slice(
        visualPixels: visualPixels,
        priorityPixels: priorityPixels,
        profile: DisplayProfile.sci0,
        paletteRgbaPacked: EgaColors.rgbaPacked,
      );
    }
  }

  void bumpRasterEpoch() {
    detachGpuCache();
    _rasterEpoch++;
  }

  @override
  void dispose() {
    _isDisposed = true;
    disposeDetachedGpuImages();
    _cachedFlatVisualImage?.dispose();
    _cachedFlatVisualImage = null;
    _cachedUnditheredVisualImage?.dispose();
    _cachedUnditheredVisualImage = null;
    _cachedPriorityMapImage?.dispose();
    _cachedPriorityMapImage = null;
    _cachedControlMapImage?.dispose();
    _cachedControlMapImage = null;
    for (final slice in _ditheredSlices.values) {
      slice.dispose();
    }
    for (final slice in _unditheredSlices.values) {
      slice.dispose();
    }
    _ditheredSlices = {};
    _unditheredSlices = {};
  }
}
