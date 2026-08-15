import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';

/// Render modes for visualizing AGI pictures in game and diagnostic views.
enum AgiPictureRenderMode {
  /// Impeller-driven multi-layer composited priority slices (Painter's Algorithm).
  compositedSlices,

  /// Flat visual 16-color EGA background image.
  flatVisual,

  /// Depth priority buffer map (color-coded bands 0 to 14 + base 15).
  priorityMap,

  /// Collision and script trigger control map (triggers, conditional/unconditional barriers, water).
  controlMap,
}

/// Simple descriptor for an active actor/sprite in the Z-order stack.
class AgiActorSprite {
  final int priority;
  final int baselineY;
  final ui.Image image;
  final Offset position;

  const AgiActorSprite({
    required this.priority,
    required this.baselineY,
    required this.image,
    required this.position,
  });
}

/// Impeller-optimized CustomPainter that renders AGI backgrounds using the Painter's Algorithm across priority slices.
class AgiPicturePainter extends CustomPainter {
  final AgiPic picture;
  final List<AgiActorSprite> actors;
  final AgiPictureRenderMode renderMode;
  final ui.Image? flatVisualImage;
  final ui.Image? priorityMapImage;
  final ui.Image? controlMapImage;

  AgiPicturePainter({
    required this.picture,
    this.actors = const [],
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.flatVisualImage,
    this.priorityMapImage,
    this.controlMapImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;

    final scaleX = size.width / AgiDisplay.renderedWidth;
    final scaleY = size.height / AgiDisplay.renderedHeight;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    switch (renderMode) {
      case AgiPictureRenderMode.compositedSlices:
        _paintCompositedSlices(canvas, paint);
        break;

      case AgiPictureRenderMode.flatVisual:
        if (flatVisualImage != null) {
          canvas.drawImage(flatVisualImage!, Offset.zero, paint);
        }
        break;

      case AgiPictureRenderMode.priorityMap:
        if (priorityMapImage != null) {
          canvas.drawImage(priorityMapImage!, Offset.zero, paint);
        }
        break;

      case AgiPictureRenderMode.controlMap:
        if (controlMapImage != null) {
          canvas.drawImage(controlMapImage!, Offset.zero, paint);
        }
        break;
    }

    canvas.restore();
  }

  void _paintCompositedSlices(Canvas canvas, Paint paint) {
    // 1. Draw Base Priority 15 (Sky / Unconditional background drawn behind all bands)
    final baseSlice = picture.getSlice(15);
    if (baseSlice != null && baseSlice.hasVisiblePixels) {
      final img = baseSlice.cachedUiImage;
      if (img != null) {
        canvas.drawImage(img, Offset.zero, paint);
      }
    }

    // 2. Interleave priority slices (0..14) with actor sprites
    for (int p = 0; p <= 14; p++) {
      // Draw background slice for depth band p (ground / lower terrain of this band)
      final slice = picture.getSlice(p);
      if (slice != null && slice.hasVisiblePixels) {
        final img = slice.cachedUiImage;
        if (img != null) {
          canvas.drawImage(img, Offset.zero, paint);
        }
      }

      // Draw actors with priority p (sorted by baseline Y ascending: further back first)
      if (actors.isNotEmpty) {
        final bandActors = actors.where((a) => a.priority == p).toList()
          ..sort((a, b) => a.baselineY.compareTo(b.baselineY));

        for (final actor in bandActors) {
          canvas.drawImage(actor.image, actor.position, paint);
        }
      }
    }

    // 3. Draw any actors assigned to unconditional priority 15
    if (actors.isNotEmpty) {
      final pri15Actors = actors.where((a) => a.priority == 15).toList()
        ..sort((a, b) => a.baselineY.compareTo(b.baselineY));
      for (final actor in pri15Actors) {
        canvas.drawImage(actor.image, actor.position, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AgiPicturePainter oldDelegate) {
    return oldDelegate.picture != picture ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.actors != actors ||
        oldDelegate.flatVisualImage != flatVisualImage ||
        oldDelegate.priorityMapImage != priorityMapImage ||
        oldDelegate.controlMapImage != controlMapImage;
  }
}

/// Flutter Widget that renders an [AgiPic] with optional layer switching controls.
class AgiPictureWidget extends StatefulWidget {
  final AgiPic picture;
  final AgiPictureRenderMode initialMode;
  final List<AgiActorSprite> actors;
  final bool showToolbar;

  const AgiPictureWidget({
    super.key,
    required this.picture,
    this.initialMode = AgiPictureRenderMode.compositedSlices,
    this.actors = const [],
    this.showToolbar = false,
  });

  @override
  State<AgiPictureWidget> createState() => _AgiPictureWidgetState();
}

class _AgiPictureWidgetState extends State<AgiPictureWidget> {
  late AgiPictureRenderMode _renderMode;
  ui.Image? _flatImage;
  ui.Image? _priImage;
  ui.Image? _ctrlImage;

  @override
  void initState() {
    super.initState();
    _renderMode = widget.initialMode;
    _preloadTextures();
  }

  @override
  void didUpdateWidget(covariant AgiPictureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.picture != widget.picture) {
      _flatImage = null;
      _priImage = null;
      _ctrlImage = null;
      _preloadTextures();
    }
  }

  Future<void> _preloadTextures() async {
    await widget.picture.preloadGpuTextures();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _ensureModeImageLoaded(AgiPictureRenderMode mode) async {
    switch (mode) {
      case AgiPictureRenderMode.compositedSlices:
        await widget.picture.preloadGpuTextures();
        break;
      case AgiPictureRenderMode.flatVisual:
        _flatImage ??= await widget.picture.toFlatVisualUiImage();
        break;
      case AgiPictureRenderMode.priorityMap:
        _priImage ??= await _decodeRgba(widget.picture.renderPriorityMapRgba());
        break;
      case AgiPictureRenderMode.controlMap:
        _ctrlImage ??=
            await _decodeRgba(widget.picture.renderControlMapRgba());
        break;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<ui.Image> _decodeRgba(Uint8List rgba) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      AgiDisplay.renderedWidth,
      AgiDisplay.renderedHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showToolbar) ...[
          _buildToolbar(),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: AspectRatio(
            aspectRatio: 4 / 3, // Sierra 4:3 display ratio
            child: Container(
              color: Colors.black,
              child: CustomPaint(
                painter: AgiPicturePainter(
                  picture: widget.picture,
                  renderMode: _renderMode,
                  actors: widget.actors,
                  flatVisualImage: _flatImage,
                  priorityMapImage: _priImage,
                  controlMapImage: _ctrlImage,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return SegmentedButton<AgiPictureRenderMode>(
      segments: const [
        ButtonSegment(
          value: AgiPictureRenderMode.compositedSlices,
          label: Text('Composited'),
        ),
        ButtonSegment(
          value: AgiPictureRenderMode.flatVisual,
          label: Text('Visual'),
        ),
        ButtonSegment(
          value: AgiPictureRenderMode.priorityMap,
          label: Text('Priority'),
        ),
        ButtonSegment(
          value: AgiPictureRenderMode.controlMap,
          label: Text('Control'),
        ),
      ],
      selected: {_renderMode},
      onSelectionChanged: (set) {
        final newMode = set.first;
        setState(() => _renderMode = newMode);
        _ensureModeImageLoaded(newMode);
      },
    );
  }
}
