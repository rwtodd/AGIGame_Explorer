import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/agi_view.dart';

/// Metadata for a cel packed inside a [ViewTextureAtlas].
class AtlasCelEntry {
  final int viewNumber;
  final int loopNumber;
  final int celNumber;

  /// The sub-rectangle location within the atlas texture.
  final Rect sourceRect;

  final int width;
  final int height;
  final int transparentColor;

  /// True if this cel should be drawn flipped horizontally.
  final bool isMirrored;

  /// The source loop number of the stored pixel data (differs if mirrored).
  final int sourceLoop;

  /// The source cel number of the stored pixel data (differs if mirrored).
  final int sourceCel;

  const AtlasCelEntry({
    required this.viewNumber,
    required this.loopNumber,
    required this.celNumber,
    required this.sourceRect,
    required this.width,
    required this.height,
    required this.transparentColor,
    required this.isMirrored,
    required this.sourceLoop,
    required this.sourceCel,
  });

  String get key => '${viewNumber}_${loopNumber}_$celNumber';

  @override
  String toString() =>
      'AtlasCelEntry(view: $viewNumber, loop: $loopNumber, cel: $celNumber, rect: $sourceRect, mirrored: $isMirrored)';
}

/// A request to draw a sprite using the atlas.
class AtlasSpriteDrawCall {
  final int viewNumber;
  final int loopNumber;
  final int celNumber;
  final Offset position;
  final double scale;
  final double scaleX;
  final double scaleY;
  final bool? forceFlipHorizontal;
  final Paint? paint;

  const AtlasSpriteDrawCall({
    required this.viewNumber,
    required this.loopNumber,
    required this.celNumber,
    required this.position,
    this.scale = 1.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.forceFlipHorizontal,
    this.paint,
  });
}

/// Represents a compiled texture atlas containing cels from one or more [AgiView]s.
class ViewTextureAtlas {
  final int width;
  final int height;
  final Uint8List rgbaPixels;
  final Map<String, AtlasCelEntry> entries;
  ui.Image? _image;

  ViewTextureAtlas({
    required this.width,
    required this.height,
    required this.rgbaPixels,
    required this.entries,
    ui.Image? initialImage,
  }) : _image = initialImage;

  /// The hardware GPU texture image, if generated.
  ui.Image? get image => _image;

  /// Whether the hardware GPU texture image is generated and ready for drawing.
  bool get hasImage => _image != null;

  /// Generates the [ui.Image] asynchronously if not already created.
  Future<ui.Image> ensureImage() async {
    if (_image != null) return _image!;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaPixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    _image = await completer.future;
    return _image!;
  }

  /// Sets the decoded [ui.Image].
  void setImage(ui.Image img) {
    _image = img;
  }

  /// Disposes the cached GPU [ui.Image] texture.
  void dispose() {
    _image?.dispose();
    _image = null;
  }

  /// Look up an entry by (viewNumber, loopNumber, celNumber).
  AtlasCelEntry? getEntry(int viewNumber, int loopNumber, int celNumber) {
    return entries['${viewNumber}_${loopNumber}_$celNumber'];
  }

  /// Check if a cel exists in this atlas.
  bool containsCel(int viewNumber, int loopNumber, int celNumber) {
    return entries.containsKey('${viewNumber}_${loopNumber}_$celNumber');
  }

  /// List of all cel entries in this atlas.
  Iterable<AtlasCelEntry> get allEntries => entries.values;

  /// Draws a single sprite cel onto the [canvas].
  ///
  /// Automatically accounts for mirrored cels by flipping horizontally.
  /// If [forceFlipHorizontal] is provided, it overrides the cel's mirror setting.
  void drawCel(
    Canvas canvas, {
    required int viewNumber,
    required int loopNumber,
    required int celNumber,
    required Offset position,
    double scale = 1.0,
    double scaleX = 1.0,
    double scaleY = 1.0,
    bool? forceFlipHorizontal,
    Paint? paint,
  }) {
    if (_image == null) {
      throw const AgiException(
        'Cannot render cel: Texture atlas ui.Image is not loaded. Call ensureImage() before rendering.',
      );
    }

    final entry = getEntry(viewNumber, loopNumber, celNumber);
    if (entry == null) {
      throw AgiException(
        'Cel view $viewNumber loop $loopNumber cel $celNumber is not present in this atlas.',
      );
    }

    final shouldFlip = forceFlipHorizontal ?? entry.isMirrored;
    final p = paint ?? (Paint()..filterQuality = FilterQuality.none);
    final finalScaleX = scale * scaleX;
    final finalScaleY = scale * scaleY;

    if (!shouldFlip) {
      final dstRect = Rect.fromLTWH(
        position.dx,
        position.dy,
        entry.width * finalScaleX,
        entry.height * finalScaleY,
      );
      canvas.drawImageRect(_image!, entry.sourceRect, dstRect, p);
    } else {
      canvas.save();
      canvas.translate(position.dx + (entry.width * finalScaleX), position.dy);
      canvas.scale(-finalScaleX, finalScaleY);
      final dstRect = Rect.fromLTWH(
        0,
        0,
        entry.width.toDouble(),
        entry.height.toDouble(),
      );
      canvas.drawImageRect(_image!, entry.sourceRect, dstRect, p);
      canvas.restore();
    }
  }

  /// Batch render multiple sprites.
  void drawSprites(
    Canvas canvas,
    List<AtlasSpriteDrawCall> sprites, {
    Paint? defaultPaint,
  }) {
    for (final call in sprites) {
      drawCel(
        canvas,
        viewNumber: call.viewNumber,
        loopNumber: call.loopNumber,
        celNumber: call.celNumber,
        position: call.position,
        scale: call.scale,
        scaleX: call.scaleX,
        scaleY: call.scaleY,
        forceFlipHorizontal: call.forceFlipHorizontal,
        paint: call.paint ?? defaultPaint,
      );
    }
  }
}

/// A pending unmirrored cel item to pack into the atlas.
class _CelPackItem {
  final int viewNumber;
  final int loopNumber;
  final int celNumber;
  final AgiViewCel cel;
  final List<AtlasCelEntry> dependentEntries;

  _CelPackItem({
    required this.viewNumber,
    required this.loopNumber,
    required this.celNumber,
    required this.cel,
    required this.dependentEntries,
  });

  int get width => cel.width;
  int get height => cel.height;
}

/// Builder that packs multiple VIEW cels into a single [ViewTextureAtlas].
class ViewAtlasBuilder {
  final int padding;
  final List<Color> palette;
  final Map<int, AgiView> _views = {};
  final List<_CelPackItem> _unmirroredItems = [];
  final List<AtlasCelEntry> _allEntries = [];

  ViewAtlasBuilder({
    this.padding = 1,
    List<Color>? palette,
  }) : palette = palette ?? EgaColors.palette;

  /// Add an entire [AgiView] to the atlas.
  void addView(AgiView view) {
    _views[view.viewNumber] = view;
  }

  /// Add multiple [AgiView]s to the atlas.
  void addViews(Iterable<AgiView> views) {
    for (final v in views) {
      addView(v);
    }
  }

  /// Prepares and clusters all cels, separating unmirrored source cels from mirrored references.
  void _preparePackItems() {
    _unmirroredItems.clear();
    _allEntries.clear();

    // Map: 'view_sourceLoop_sourceCel' -> _CelPackItem
    final sourceMap = <String, _CelPackItem>{};

    for (final view in _views.values) {
      // First pass: collect all forward (unmirrored) cels
      for (final loop in view.loops) {
        for (var cIdx = 0; cIdx < loop.cels.length; cIdx++) {
          final cel = loop.cels[cIdx];
          if (!cel.isMirrored) {
            final key = '${view.viewNumber}_${loop.loopNumber}_$cIdx';
            final item = _CelPackItem(
              viewNumber: view.viewNumber,
              loopNumber: loop.loopNumber,
              celNumber: cIdx,
              cel: cel,
              dependentEntries: [],
            );
            sourceMap[key] = item;
            _unmirroredItems.add(item);
          }
        }
      }
    }

    // Second pass: handle mirrored cels referencing their sources
    for (final view in _views.values) {
      for (final loop in view.loops) {
        for (var cIdx = 0; cIdx < loop.cels.length; cIdx++) {
          final cel = loop.cels[cIdx];
          if (cel.isMirrored) {
            final sourceKey = '${view.viewNumber}_${cel.mirrorLoop}_$cIdx';
            var sourceItem = sourceMap[sourceKey];
            if (sourceItem == null) {
              // If source loop wasn't parsed as forward or is missing, try resolving directly
              final sourceCel = view.resolveSourceCel(loop.loopNumber, cIdx);
              if (sourceCel != null && !sourceCel.isMirrored) {
                sourceItem = _CelPackItem(
                  viewNumber: view.viewNumber,
                  loopNumber: cel.mirrorLoop,
                  celNumber: cIdx,
                  cel: sourceCel,
                  dependentEntries: [],
                );
                sourceMap[sourceKey] = sourceItem;
                _unmirroredItems.add(sourceItem);
              }
            }
          }
        }
      }
    }
  }

  /// Builds the atlas synchronously into an RGBA pixel buffer and metadata entries.
  ViewTextureAtlas buildSync({int maxAtlasDimension = 2048}) {
    _preparePackItems();

    if (_unmirroredItems.isEmpty) {
      return ViewTextureAtlas(
        width: 1,
        height: 1,
        rgbaPixels: Uint8List(4),
        entries: {},
      );
    }

    // Sort items by height descending for efficient shelf packing
    _unmirroredItems.sort((a, b) {
      final hCmp = b.height.compareTo(a.height);
      if (hCmp != 0) return hCmp;
      return b.width.compareTo(a.width);
    });

    // Estimate atlas size
    final totalArea = _unmirroredItems.fold<int>(
      0,
      (sum, item) => sum + (item.width + padding * 2) * (item.height + padding * 2),
    );

    var targetWidth = 64;
    while (targetWidth * targetWidth < totalArea * 1.3 && targetWidth < maxAtlasDimension) {
      targetWidth *= 2;
    }

    // Shelf packing algorithm
    var currentX = padding;
    var currentY = padding;
    var currentShelfHeight = 0;
    var maxPackedX = 0;
    var maxPackedY = 0;

    final placements = <_CelPackItem, Rect>{};

    for (final item in _unmirroredItems) {
      final paddedW = item.width + padding;

      if (currentX + paddedW > targetWidth) {
        // Move to next shelf
        currentX = padding;
        currentY += currentShelfHeight + padding;
        currentShelfHeight = 0;
      }

      final rect = Rect.fromLTWH(
        currentX.toDouble(),
        currentY.toDouble(),
        item.width.toDouble(),
        item.height.toDouble(),
      );
      placements[item] = rect;

      if (item.height > currentShelfHeight) {
        currentShelfHeight = item.height;
      }

      currentX += paddedW;
      if (currentX > maxPackedX) maxPackedX = currentX;
      final bottomY = (rect.top + rect.height).toInt() + padding;
      if (bottomY > maxPackedY) maxPackedY = bottomY;
    }

    // Fit final dimensions to power-of-two
    var atlasWidth = 64;
    while (atlasWidth < maxPackedX && atlasWidth < maxAtlasDimension) {
      atlasWidth *= 2;
    }
    if (atlasWidth < maxPackedX) atlasWidth = maxPackedX;

    var atlasHeight = 64;
    while (atlasHeight < maxPackedY && atlasHeight < maxAtlasDimension) {
      atlasHeight *= 2;
    }
    if (atlasHeight < maxPackedY) atlasHeight = maxPackedY;

    // Rasterize all unmirrored cels into RGBA buffer
    final rgbaBuffer = Uint8List(atlasWidth * atlasHeight * 4);
    final resultMap = <String, AtlasCelEntry>{};

    for (final item in _unmirroredItems) {
      final rect = placements[item]!;
      final destX = rect.left.toInt();
      final destY = rect.top.toInt();

      final entry = AtlasCelEntry(
        viewNumber: item.viewNumber,
        loopNumber: item.loopNumber,
        celNumber: item.celNumber,
        sourceRect: rect,
        width: item.width,
        height: item.height,
        transparentColor: item.cel.transparentColor,
        isMirrored: false,
        sourceLoop: item.loopNumber,
        sourceCel: item.celNumber,
      );
      resultMap[entry.key] = entry;

      // Copy pixels into RGBA buffer
      final rawPixels = item.cel.getUnflippedPixels();
      for (var y = 0; y < item.height; y++) {
        final srcRowOffset = y * item.width;
        final dstRowOffset = (destY + y) * atlasWidth;

        for (var x = 0; x < item.width; x++) {
          final colorIdx = rawPixels[srcRowOffset + x] & 0x0F;
          final dstPixelOffset = (dstRowOffset + (destX + x)) * 4;

          if (colorIdx == item.cel.transparentColor) {
            rgbaBuffer[dstPixelOffset] = 0;
            rgbaBuffer[dstPixelOffset + 1] = 0;
            rgbaBuffer[dstPixelOffset + 2] = 0;
            rgbaBuffer[dstPixelOffset + 3] = 0;
          } else {
            final col = (colorIdx < EgaColors.rgbaBytes.length)
                ? EgaColors.rgbaBytes[colorIdx]
                : EgaColors.rgbaBytes[0];
            rgbaBuffer[dstPixelOffset] = col[0];
            rgbaBuffer[dstPixelOffset + 1] = col[1];
            rgbaBuffer[dstPixelOffset + 2] = col[2];
            rgbaBuffer[dstPixelOffset + 3] = 255;
          }
        }
      }
    }

    // Now populate entries for all mirrored cels
    for (final view in _views.values) {
      for (final loop in view.loops) {
        for (var cIdx = 0; cIdx < loop.cels.length; cIdx++) {
          final cel = loop.cels[cIdx];
          final key = '${view.viewNumber}_${loop.loopNumber}_$cIdx';
          if (resultMap.containsKey(key)) continue;

          if (cel.isMirrored) {
            final sourceEntry = resultMap['${view.viewNumber}_${cel.mirrorLoop}_$cIdx'];
            if (sourceEntry != null) {
              final mirroredEntry = AtlasCelEntry(
                viewNumber: view.viewNumber,
                loopNumber: loop.loopNumber,
                celNumber: cIdx,
                sourceRect: sourceEntry.sourceRect, // Shares the same atlas rect!
                width: cel.width,
                height: cel.height,
                transparentColor: cel.transparentColor,
                isMirrored: true,
                sourceLoop: cel.mirrorLoop,
                sourceCel: cIdx,
              );
              resultMap[key] = mirroredEntry;
            }
          }
        }
      }
    }

    return ViewTextureAtlas(
      width: atlasWidth,
      height: atlasHeight,
      rgbaPixels: rgbaBuffer,
      entries: resultMap,
    );
  }

  /// Builds the atlas and generates its GPU [ui.Image] asynchronously.
  Future<ViewTextureAtlas> buildAsync({int maxAtlasDimension = 2048}) async {
    final atlas = buildSync(maxAtlasDimension: maxAtlasDimension);
    await atlas.ensureImage();
    return atlas;
  }
}

/// Runtime manager for Sierra AGI VIEW texture atlases.
///
/// Coordinates primary and secondary texture atlases for all loaded [AgiView]s,
/// ensuring all sprite cels are compiled and pre-warmed on the GPU before render.
class ViewAtlasManager {
  final Map<int, AgiView> _registeredViews = {};
  ViewTextureAtlas? _primaryAtlas;
  final Map<int, ViewTextureAtlas> _sideAtlases = {};
  bool _isDirty = false;
  Future<ViewTextureAtlas>? _pendingBuild;
  void Function()? onAtlasUpdated;

  ViewTextureAtlas? get primaryAtlas => _primaryAtlas;
  Map<int, AgiView> get registeredViews => Map.unmodifiable(_registeredViews);

  /// Registers an [AgiView] with the atlas manager.
  void registerView(AgiView view) {
    if (_registeredViews[view.viewNumber] != view) {
      _registeredViews[view.viewNumber] = view;
      _isDirty = true;
    }
  }

  /// Registers multiple [AgiView]s with the atlas manager.
  void registerViews(Iterable<AgiView> views) {
    for (final v in views) {
      registerView(v);
    }
  }

  /// Removes an [AgiView] from the atlas manager.
  void unregisterView(int viewNumber) {
    if (_registeredViews.containsKey(viewNumber)) {
      _registeredViews.remove(viewNumber);
      _sideAtlases.remove(viewNumber)?.dispose();
      _isDirty = true;
    }
  }

  /// Clears all registered views and disposes GPU textures.
  void clear() {
    _primaryAtlas?.dispose();
    _primaryAtlas = null;
    for (final atlas in _sideAtlases.values) {
      atlas.dispose();
    }
    _sideAtlases.clear();
    _registeredViews.clear();
    _isDirty = false;
    _pendingBuild = null;
  }

  /// Look up which atlas (primary or side-atlas) contains the specified cel.
  ViewTextureAtlas? getAtlasForCel(int viewNumber, int loopNumber, int celNumber) {
    if (_primaryAtlas != null && _primaryAtlas!.containsCel(viewNumber, loopNumber, celNumber)) {
      return _primaryAtlas;
    }
    final side = _sideAtlases[viewNumber];
    if (side != null && side.containsCel(viewNumber, loopNumber, celNumber)) {
      return side;
    }
    return null;
  }

  /// Checks if the manager contains a registered view and has compiled its texture atlas.
  bool containsView(int viewNumber) {
    return !_isDirty && _registeredViews.containsKey(viewNumber) && (_primaryAtlas?.hasImage == true);
  }

  /// Checks if any loaded atlas contains the specified cel.
  bool containsCel(int viewNumber, int loopNumber, int celNumber) {
    return getAtlasForCel(viewNumber, loopNumber, celNumber) != null;
  }

  /// Builds or refreshes the primary atlas for all registered views asynchronously.
  FutureOr<ViewTextureAtlas> prepareAtlasAsync() {
    if (!_isDirty && _primaryAtlas != null && _primaryAtlas!.hasImage) {
      return _primaryAtlas!;
    }
    if (_registeredViews.isEmpty) {
      _isDirty = false;
      return _primaryAtlas ??= ViewTextureAtlas(
        width: 1,
        height: 1,
        rgbaPixels: Uint8List(4),
        entries: const {},
      );
    }
    if (_pendingBuild != null) {
      return _pendingBuild!;
    }
    return _buildAtlasAsync();
  }

  Future<ViewTextureAtlas> _buildAtlasAsync() async {
    final completer = Completer<ViewTextureAtlas>();
    _pendingBuild = completer.future;

    try {
      do {
        _isDirty = false;
        if (_registeredViews.isEmpty) {
          final emptyAtlas = ViewTextureAtlas(
            width: 1,
            height: 1,
            rgbaPixels: Uint8List(4),
            entries: {},
          );
          await emptyAtlas.ensureImage();
          final oldAtlas = _primaryAtlas;
          _primaryAtlas = emptyAtlas;
          oldAtlas?.dispose();
          onAtlasUpdated?.call();
          break;
        }

        final builder = ViewAtlasBuilder();
        builder.addViews(_registeredViews.values);
        final newAtlas = await builder.buildAsync();

        final oldAtlas = _primaryAtlas;
        _primaryAtlas = newAtlas;
        oldAtlas?.dispose();
        onAtlasUpdated?.call();
      } while (_isDirty);

      completer.complete(_primaryAtlas!);
      return _primaryAtlas!;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingBuild = null;
    }
  }

  /// Immediately creates and preloads a side-atlas for a single [AgiView] if missing from primary.
  Future<ViewTextureAtlas> ensureSideAtlasAsync(AgiView view) async {
    final existing = _sideAtlases[view.viewNumber];
    if (existing != null && existing.hasImage) {
      return existing;
    }
    final builder = ViewAtlasBuilder();
    builder.addView(view);
    final sideAtlas = await builder.buildAsync();
    _sideAtlases[view.viewNumber]?.dispose();
    _sideAtlases[view.viewNumber] = sideAtlas;
    onAtlasUpdated?.call();
    return sideAtlas;
  }

  /// Disposes all managed texture atlases.
  void dispose() {
    clear();
  }
}
