import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';

/// Completes a [ui.decodeImageFromPixels] callback without hanging if the
/// owner was disposed while the GPU upload was in flight.
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
  bool _isDisposed = false;

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
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed PictureSlice.');
    }
    if (_cachedUiImage != null) return _cachedUiImage!;

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) {
        _completeGpuDecode(
          disposed: _isDisposed,
          completer: completer,
          image: image,
          onSuccess: (img) => _cachedUiImage = img,
        );
      },
    );
    return completer.future;
  }

  /// Drops the cached GPU texture without disposing it (caller owns the image).
  ui.Image? detachCachedImage() {
    final image = _cachedUiImage;
    _cachedUiImage = null;
    return image;
  }

  /// Disposes the cached GPU texture without discarding [rgbaBytes].
  void invalidateCachedImage() {
    detachCachedImage()?.dispose();
  }

  /// Disposes cached GPU textures.
  void dispose() {
    _isDisposed = true;
    invalidateCachedImage();
  }
}

/// Common interface for Sierra background pictures (both AGI and SCI).
///
/// Enables UI components (like [PicBrowserScreen] and [AgiPictureCanvas]) to
/// inspect, composite, and render pictures without coupling to engine-specific
/// internal buffer layouts.
abstract class SierraPicture {
  /// The picture resource number, if known.
  int? get picNumber;

  /// Map of priority slices keyed by priority level (0..15).
  Map<int, PictureSlice> get slices;

  /// Gets the priority slice for the given priority level (0..15), if present.
  PictureSlice? getSlice(int priority);

  /// List of all priority slices that contain visible pixels.
  List<PictureSlice> get activeSlices;

  /// Raw visual buffer of color indices.
  Uint8List get visualPixels;

  /// Renders a complete 320x200 RGBA flat visual background.
  Uint8List renderFlatVisualRgba({bool? undithered});

  /// Decodes and returns the flat visual background as a Flutter [ui.Image].
  Future<ui.Image> toFlatVisualUiImage({bool? undithered});

  /// Renders a 320x200 RGBA buffer visualizing the depth priority map.
  Uint8List renderPriorityMapRgba();

  /// Decodes and returns the depth priority map as a Flutter [ui.Image].
  Future<ui.Image> toPriorityMapUiImage();

  /// Renders a 320x200 RGBA buffer visualizing the control map.
  Uint8List renderControlMapRgba();

  /// Decodes and returns the control map as a Flutter [ui.Image].
  Future<ui.Image> toControlMapUiImage();

  /// Renders a 320x200 RGBA value-encoded priority texture: R =
  /// effectivePriority * 17, G/B = 0, A = 255. AGI is horizontally doubled
  /// from 160x168 effective priorities (rows 168..199 have R = 0); SCI is
  /// 1:1 from `(priorityPixels[i] & 0x0F)`.
  Uint8List renderPriorityTextureRgba();

  /// Decodes and returns the priority texture as a Flutter [ui.Image].
  Future<ui.Image> toPriorityTextureUiImage();

  /// Cached Flutter [ui.Image] for the flat visual background, if decoded.
  ui.Image? get cachedFlatVisualImage;

  /// Cached Flutter [ui.Image] for the depth priority map, if decoded.
  ui.Image? get cachedPriorityMapImage;

  /// Cached Flutter [ui.Image] for the control barrier map, if decoded.
  ui.Image? get cachedControlMapImage;

  /// Cached Flutter [ui.Image] for the value-encoded priority texture.
  ui.Image? get cachedPriorityTextureImage;

  /// Drops the flat/priority-map/control-map/priority-texture GPU caches
  /// without touching slices and without marking disposed.
  void invalidateCachedImages();

  /// Preloads GPU textures for all active slices asynchronously.
  FutureOr<void> preloadGpuTextures({bool includeDiagnosticMaps = false, bool includeShaderTextures = false});

  /// Disposes GPU resources held by this picture.
  void dispose();

  /// Picture pixel width (160 for AGI, 320 for SCI).
  int get width;

  /// Picture pixel height (168 for AGI, 200 for SCI).
  int get height;

  /// Bumped when in-place raster contents change (vector replay).
  int get rasterEpoch;

  /// Whether [dispose] has been called.
  bool get isDisposed => false;

  /// Gets the raw depth priority at pixel `(x, y)`.
  int priorityAtPixel(int x, int y);

  /// Gets the control line/barrier value at pixel `(x, y)`.
  int controlAtPixel(int x, int y);

  /// Gets the visual EGA color index at pixel `(x, y)`.
  int visualAtPixel(int x, int y);

  /// Gets the effective depth priority (4..15) at `(x, y)`.
  int effectivePriorityAtPixel(int x, int y);

  /// Whether this picture is from a 320x200 SCI engine.
  bool get isSci;
}

/// Represents an interpreted AGI PICTURE resource.
///
/// Contains:
/// 1. The raw 160x168 [visualPixels] EGA buffer (colors 0..15).
/// 2. The 160x168 [priorityBuffer] (depth priorities 0..15 and control barriers).
/// 3. The pre-sliced [slices] bundle (320x200 transparent RGBA images for Impeller compositing).
class AgiPic implements SierraPicture {
  /// Native AGI picture width (160).
  static const int nativeWidth = AgiDisplay.nativeWidth;

  /// Native AGI picture height (168).
  static const int nativeHeight = AgiDisplay.pictureHeight;

  @override
  int get width => nativeWidth;

  @override
  int get height => nativeHeight;

  /// Rendered screen width (320).
  static const int renderedWidth = AgiDisplay.renderedWidth;

  /// Rendered screen height (200).
  static const int renderedHeight = AgiDisplay.renderedHeight;

  @override
  int get rasterEpoch => 0;

  @override
  bool get isDisposed => _isDisposed;

  /// Raw visual buffer: 160x168 EGA color indices (0..15).
  @override
  final Uint8List visualPixels;

  /// Priority screen memory buffer: 160x168 priority & control lines.
  final PriorityBuffer priorityBuffer;

  /// Bundle of priority slices (keyed by priority level 0 to 15).
  @override
  final Map<int, PictureSlice> slices;

  ui.Image? _cachedFlatVisualImage;
  ui.Image? _cachedPriorityMapImage;
  ui.Image? _cachedControlMapImage;
  ui.Image? _cachedPriorityTextureImage;
  bool _isDisposed = false;

  /// The AGI picture resource number, if known.
  @override
  int? picNumber;

  @override
  bool get isSci => false;

  AgiPic({
    this.picNumber,
    required this.visualPixels,
    required this.priorityBuffer,
    required this.slices,
  }) {
    if (visualPixels.length != nativeWidth * nativeHeight) {
      throw ArgumentError(
        'Invalid visual buffer size: ${visualPixels.length}. Expected ${nativeWidth * nativeHeight}.',
      );
    }
  }

  /// Cached Flutter [ui.Image] for the flat visual background, if decoded.
  @override
  ui.Image? get cachedFlatVisualImage => _cachedFlatVisualImage;

  /// Cached Flutter [ui.Image] for the depth priority map, if decoded.
  @override
  ui.Image? get cachedPriorityMapImage => _cachedPriorityMapImage;

  /// Cached Flutter [ui.Image] for the control barrier map, if decoded.
  @override
  ui.Image? get cachedControlMapImage => _cachedControlMapImage;

  /// Cached Flutter [ui.Image] for the value-encoded priority texture.
  @override
  ui.Image? get cachedPriorityTextureImage => _cachedPriorityTextureImage;

  /// Gets the priority slice for the given priority level (0..15), if present.
  @override
  PictureSlice? getSlice(int priority) => slices[priority];

  /// List of all priority slices that contain visible pixels.
  @override
  List<PictureSlice> get activeSlices =>
      slices.values.where((s) => s.hasVisiblePixels).toList();

  /// Gets the raw priority value at `(x, y)`.
  @override
  int priorityAtPixel(int x, int y) => priorityBuffer.priorityAt(x, y);

  /// Gets the control value at `(x, y)`.
  @override
  int controlAtPixel(int x, int y) => priorityBuffer.controlAt(x, y);

  /// Gets the visual EGA color index at `(x, y)`.
  @override
  int visualAtPixel(int x, int y) {
    if (x < 0 || x >= nativeWidth || y < 0 || y >= nativeHeight) return 0;
    return visualPixels[y * nativeWidth + x];
  }

  /// Gets the effective depth priority (4..15) at `(x, y)`.
  @override
  int effectivePriorityAtPixel(int x, int y) =>
      priorityBuffer.effectivePriorityAt(x, y);

  /// Preloads GPU textures for all active slices asynchronously.
  @override
  FutureOr<void> preloadGpuTextures({bool includeDiagnosticMaps = false, bool includeShaderTextures = false}) {
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
    if (includeShaderTextures) {
      if (_cachedFlatVisualImage == null) futures.add(toFlatVisualUiImage());
      if (_cachedPriorityTextureImage == null) futures.add(toPriorityTextureUiImage());
    }
    if (futures.isEmpty) return null;
    // Ignore decode errors from slices disposed while upload was in flight.
    return Future.wait<ui.Image?>([
      for (final f in futures)
        f.then<ui.Image?>((img) => img, onError: (Object _, StackTrace _) => null),
    ]).then((_) {});
  }

  /// Renders a complete 320x200 RGBA flat visual background (for diagnostic views or single-texture shaders).
  @override
  Uint8List renderFlatVisualRgba({bool? undithered}) {
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
  @override
  Future<ui.Image> toFlatVisualUiImage({bool? undithered}) async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed AgiPic.');
    }
    if (_cachedFlatVisualImage != null) return _cachedFlatVisualImage!;

    final flatRgba = renderFlatVisualRgba(undithered: undithered);
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
          onSuccess: (img) => _cachedFlatVisualImage = img,
        );
      },
    );
    return completer.future;
  }

  /// Renders the depth priority map as 320x200 RGBA bytes.
  @override
  Uint8List renderPriorityMapRgba() => priorityBuffer.renderPriorityMapRgba();

  /// Decodes and returns the depth priority map as a Flutter [ui.Image].
  @override
  Future<ui.Image> toPriorityMapUiImage() async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed AgiPic.');
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

  /// Renders the control map (triggers and barriers) as 320x200 RGBA bytes.
  @override
  Uint8List renderControlMapRgba() => priorityBuffer.renderControlMapRgba();

  /// Decodes and returns the control map as a Flutter [ui.Image].
  @override
  Future<ui.Image> toControlMapUiImage() async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed AgiPic.');
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

  /// Renders the value-encoded priority texture as 320x200 RGBA bytes:
  /// R = effectivePriority * 17, G/B = 0, A = 255, horizontally doubled
  /// from the 160x168 effective priorities. Rows 168..199 have R = 0.
  @override
  Uint8List renderPriorityTextureRgba() {
    final effective = priorityBuffer.computeEffectivePriorities();
    final outBytes = Uint8List(renderedWidth * renderedHeight * 4);
    for (int y = 0; y < nativeHeight; y++) {
      for (int x = 0; x < nativeWidth; x++) {
        final r = effective[y * nativeWidth + x] * 17;
        final outIdx1 = (y * renderedWidth + (x * 2)) * 4;
        final outIdx2 = outIdx1 + 4;
        outBytes[outIdx1 + 0] = r;
        outBytes[outIdx1 + 1] = 0;
        outBytes[outIdx1 + 2] = 0;
        outBytes[outIdx1 + 3] = 255;
        outBytes[outIdx2 + 0] = r;
        outBytes[outIdx2 + 1] = 0;
        outBytes[outIdx2 + 2] = 0;
        outBytes[outIdx2 + 3] = 255;
      }
    }
    for (int y = nativeHeight; y < renderedHeight; y++) {
      for (int x = 0; x < renderedWidth; x++) {
        final outIdx = (y * renderedWidth + x) * 4;
        outBytes[outIdx + 0] = 0;
        outBytes[outIdx + 1] = 0;
        outBytes[outIdx + 2] = 0;
        outBytes[outIdx + 3] = 255;
      }
    }
    return outBytes;
  }

  /// Decodes and returns the priority texture as a Flutter [ui.Image].
  @override
  Future<ui.Image> toPriorityTextureUiImage() async {
    if (_isDisposed) {
      throw StateError('Cannot decode ui.Image on a disposed AgiPic.');
    }
    if (_cachedPriorityTextureImage != null) return _cachedPriorityTextureImage!;

    final rgba = renderPriorityTextureRgba();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      renderedWidth,
      renderedHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _completeGpuDecode(
          disposed: _isDisposed,
          completer: completer,
          image: image,
          onSuccess: (img) => _cachedPriorityTextureImage = img,
        );
      },
    );
    return completer.future;
  }

  /// Drops the flat/priority-map/control-map/priority-texture GPU caches
  /// without touching slices and without marking disposed.
  @override
  void invalidateCachedImages() {
    _cachedFlatVisualImage?.dispose();
    _cachedFlatVisualImage = null;
    _cachedPriorityMapImage?.dispose();
    _cachedPriorityMapImage = null;
    _cachedControlMapImage?.dispose();
    _cachedControlMapImage = null;
    _cachedPriorityTextureImage?.dispose();
    _cachedPriorityTextureImage = null;
  }

  /// Disposes GPU resources held by this picture and its slices.
  @override
  void dispose() {
    _isDisposed = true;
    _cachedFlatVisualImage?.dispose();
    _cachedFlatVisualImage = null;
    _cachedPriorityMapImage?.dispose();
    _cachedPriorityMapImage = null;
    _cachedControlMapImage?.dispose();
    _cachedControlMapImage = null;
    _cachedPriorityTextureImage?.dispose();
    _cachedPriorityTextureImage = null;
    for (final slice in slices.values) {
      slice.dispose();
    }
  }
}

/// Diagnostic metadata describing a single discrete drawing operation in a vector stream.
abstract class PicStepInfo {
  int get stepIndex;
  int get opcode;
  String get commandName;
  String get description;
}

/// Common interface for step-by-step vector replay across Sierra engine picture formats (AGI and SCI).
abstract class SierraPicStepInterpreter {
  int get totalSteps;
  List<PicStepInfo> get steps;
  SierraPicture renderUpToStep(int stepIndex, {bool computeSlices = false, bool isUndithered = false});
}
