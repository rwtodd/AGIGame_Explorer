import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

/// A single Impeller-ready 320x200 RGBA texture layer corresponding to a specific AGI priority level.
///
/// In this modern rendering pipeline:
/// - Priority 15 is the background base layer (Sky / unconditional background drawn first).
/// - Priorities 0 to 14 are depth bands drawn in Z-order along with active VIEW sprites.
/// - Slices are 320x200 (pixel-doubled horizontally from 160 units).
/// - Empty pixels are RGBA `(0, 0, 0, 0)` (fully transparent).
class PictureSlice {
  /// The AGI priority level for this slice (0 to 15).
  final int priority;

  /// Width in rendered screen pixels (320).
  final int width;

  /// Height in rendered screen pixels (200).
  final int height;

  /// Raw 32-bit RGBA pixel bytes (width * height * 4).
  final Uint8List rgbaBytes;

  /// Whether this slice contains at least one non-transparent pixel.
  /// Used by the compositor to bypass empty draw calls.
  final bool hasVisiblePixels;

  ui.Image? _cachedUiImage;

  PictureSlice({
    required this.priority,
    required this.width,
    required this.height,
    required this.rgbaBytes,
    required this.hasVisiblePixels,
  });

  /// Cached Flutter [ui.Image] if already decoded, or null if not yet prepared.
  ui.Image? get cachedUiImage => _cachedUiImage;

  /// Decodes and caches the GPU [ui.Image] for direct drawing in Flutter / Impeller canvas passes.
  Future<ui.Image> toUiImage() async {
    if (_cachedUiImage != null) return _cachedUiImage!;

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedUiImage = image;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  /// Disposes cached GPU textures.
  void dispose() {
    _cachedUiImage?.dispose();
    _cachedUiImage = null;
  }
}

/// Represents an interpreted AGI PICTURE resource.
///
/// Contains:
/// 1. The raw 160x168 [visualPixels] EGA buffer (colors 0..15).
/// 2. The 160x168 [priorityBuffer] (depth priorities 0..15 and control barriers).
/// 3. The pre-sliced [slices] bundle (320x200 transparent RGBA images for Impeller compositing).
class AgiPic {
  /// Native AGI picture width (160).
  static const int nativeWidth = AgiDisplay.nativeWidth;

  /// Native AGI picture height (168).
  static const int nativeHeight = AgiDisplay.pictureHeight;

  /// Rendered screen width (320).
  static const int renderedWidth = AgiDisplay.renderedWidth;

  /// Rendered screen height (200).
  static const int renderedHeight = AgiDisplay.renderedHeight;

  /// Raw visual buffer: 160x168 EGA color indices (0..15).
  final Uint8List visualPixels;

  /// Priority screen memory buffer: 160x168 priority & control lines.
  final PriorityBuffer priorityBuffer;

  /// Bundle of priority slices (keyed by priority level 0 to 15).
  final Map<int, PictureSlice> slices;

  ui.Image? _cachedFlatVisualImage;
  ui.Image? _cachedPriorityMapImage;
  ui.Image? _cachedControlMapImage;

  AgiPic({
    required this.visualPixels,
    required this.priorityBuffer,
    required this.slices,
  }) {
    if (visualPixels.length != nativeWidth * nativeHeight) {
      throw ArgumentError(
        'AgiPic visualPixels must have ${nativeWidth * nativeHeight} bytes, got ${visualPixels.length}',
      );
    }
  }

  /// Cached Flutter [ui.Image] for the flat visual background, if decoded.
  ui.Image? get cachedFlatVisualImage => _cachedFlatVisualImage;

  /// Cached Flutter [ui.Image] for the depth priority map, if decoded.
  ui.Image? get cachedPriorityMapImage => _cachedPriorityMapImage;

  /// Cached Flutter [ui.Image] for the control barrier map, if decoded.
  ui.Image? get cachedControlMapImage => _cachedControlMapImage;

  /// Gets the priority slice for the given priority level (0..15), if present.
  PictureSlice? getSlice(int priority) => slices[priority];

  /// List of all priority slices that contain visible pixels.
  List<PictureSlice> get activeSlices =>
      slices.values.where((s) => s.hasVisiblePixels).toList();

  /// Gets the raw priority value at `(x, y)`.
  int priorityAtPixel(int x, int y) => priorityBuffer.priorityAt(x, y);

  /// Gets the effective depth priority (4..15) at `(x, y)`.
  int effectivePriorityAtPixel(int x, int y) =>
      priorityBuffer.effectivePriorityAt(x, y);

  /// Preloads GPU textures for all active slices asynchronously.
  FutureOr<void> preloadGpuTextures({bool includeDiagnosticMaps = false}) {
    final futures = <Future<ui.Image>>[];
    for (final slice in slices.values) {
      if (slice.hasVisiblePixels && slice.cachedUiImage == null) {
        futures.add(slice.toUiImage());
      }
    }
    if (includeDiagnosticMaps) {
      if (_cachedFlatVisualImage == null) futures.add(toFlatVisualUiImage());
      if (_cachedPriorityMapImage == null) futures.add(toPriorityMapUiImage());
      if (_cachedControlMapImage == null) futures.add(toControlMapUiImage());
    }
    if (futures.isEmpty) return null;
    return Future.wait(futures).then((_) {});
  }

  /// Renders a complete 320x200 RGBA flat visual background (for diagnostic views or single-texture shaders).
  Uint8List renderFlatVisualRgba() {
    final outBytes = Uint8List(renderedWidth * renderedHeight * 4);

    for (int y = 0; y < nativeHeight; y++) {
      for (int x = 0; x < nativeWidth; x++) {
        final colorIndex = visualPixels[y * nativeWidth + x];
        final col = EgaColors.rgbaBytes[colorIndex];

        // Pixel-doubling to 320x200
        final outIdx1 = (y * renderedWidth + (x * 2)) * 4;
        final outIdx2 = outIdx1 + 4;

        outBytes[outIdx1 + 0] = col[0];
        outBytes[outIdx1 + 1] = col[1];
        outBytes[outIdx1 + 2] = col[2];
        outBytes[outIdx1 + 3] = col[3];

        outBytes[outIdx2 + 0] = col[0];
        outBytes[outIdx2 + 1] = col[1];
        outBytes[outIdx2 + 2] = col[2];
        outBytes[outIdx2 + 3] = col[3];
      }
    }
    return outBytes;
  }

  /// Decodes and returns the flat visual background as a Flutter [ui.Image].
  Future<ui.Image> toFlatVisualUiImage() async {
    if (_cachedFlatVisualImage != null) return _cachedFlatVisualImage!;

    final flatRgba = renderFlatVisualRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      flatRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedFlatVisualImage = image;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  /// Renders the depth priority map as 320x200 RGBA bytes.
  Uint8List renderPriorityMapRgba() => priorityBuffer.renderPriorityMapRgba();

  /// Decodes and returns the depth priority map as a Flutter [ui.Image].
  Future<ui.Image> toPriorityMapUiImage() async {
    if (_cachedPriorityMapImage != null) return _cachedPriorityMapImage!;

    final priRgba = renderPriorityMapRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      priRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedPriorityMapImage = image;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  /// Renders the control map (triggers and barriers) as 320x200 RGBA bytes.
  Uint8List renderControlMapRgba() => priorityBuffer.renderControlMapRgba();

  /// Decodes and returns the control map as a Flutter [ui.Image].
  Future<ui.Image> toControlMapUiImage() async {
    if (_cachedControlMapImage != null) return _cachedControlMapImage!;

    final ctrlRgba = renderControlMapRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      ctrlRgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedControlMapImage = image;
        completer.complete(image);
      },
    );
    return completer.future;
  }

  /// Disposes GPU resources held by this picture and its slices.
  void dispose() {
    _cachedFlatVisualImage?.dispose();
    _cachedFlatVisualImage = null;
    _cachedPriorityMapImage?.dispose();
    _cachedPriorityMapImage = null;
    _cachedControlMapImage?.dispose();
    _cachedControlMapImage = null;
    for (final slice in slices.values) {
      slice.dispose();
    }
  }
}
