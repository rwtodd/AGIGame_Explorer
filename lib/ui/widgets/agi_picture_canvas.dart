import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

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
  final List<AgiDisplayText> displayedTexts;
  final AgiPictureRenderMode renderMode;
  final ui.Image? flatVisualImage;
  final ui.Image? priorityMapImage;
  final ui.Image? controlMapImage;
  final int? isolatedPrioritySlice;
  final bool showPixelGrid;

  AgiPicturePainter({
    required this.picture,
    this.actors = const [],
    this.displayedTexts = const [],
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.flatVisualImage,
    this.priorityMapImage,
    this.controlMapImage,
    this.isolatedPrioritySlice,
    this.showPixelGrid = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;

    final scaleX = size.width / AgiDisplay.renderedWidth;
    final scaleY = size.height / AgiDisplay.renderedHeight;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (isolatedPrioritySlice != null) {
      final slice = picture.getSlice(isolatedPrioritySlice!);
      if (slice != null && slice.hasVisiblePixels && slice.cachedUiImage != null) {
        canvas.drawImage(slice.cachedUiImage!, Offset.zero, paint);
      }
    } else {
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
    }

    if (displayedTexts.isNotEmpty) {
      _paintDisplayedTexts(canvas);
    }

    if (showPixelGrid) {
      _paintGrid(canvas);
    }

    canvas.restore();
  }

  void _paintDisplayedTexts(Canvas canvas) {
    for (final item in displayedTexts) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: item.message,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 7.0,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Each character cell is 8x8 in 320x200 resolution
      textPainter.paint(canvas, Offset(item.col * 8.0, item.row * 8.0));
    }
  }

  void _paintCompositedSlices(Canvas canvas, Paint paint) {
    bool drawnAny = false;

    // 1. Draw Base Priority 15 (Sky / Unconditional background drawn behind all bands)
    final baseSlice = picture.getSlice(15);
    if (baseSlice != null && baseSlice.hasVisiblePixels && baseSlice.cachedUiImage != null) {
      canvas.drawImage(baseSlice.cachedUiImage!, Offset.zero, paint);
      drawnAny = true;
    }

    // 2. Interleave priority slices (0..14) with actor sprites
    for (int p = 0; p <= 14; p++) {
      final slice = picture.getSlice(p);
      if (slice != null && slice.hasVisiblePixels && slice.cachedUiImage != null) {
        canvas.drawImage(slice.cachedUiImage!, Offset.zero, paint);
        drawnAny = true;
      }

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

    // 4. Seamless fallback to flat visual background if slices are still loading
    if (!drawnAny && flatVisualImage != null) {
      canvas.drawImage(flatVisualImage!, Offset.zero, paint);
    }
  }

  void _paintGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 0.0
      ..style = PaintingStyle.stroke;

    for (int x = 0; x <= AgiDisplay.renderedWidth; x += 2) {
      canvas.drawLine(Offset(x.toDouble(), 0), Offset(x.toDouble(), AgiDisplay.renderedHeight.toDouble()), gridPaint);
    }
    for (int y = 0; y <= AgiDisplay.renderedHeight; y++) {
      canvas.drawLine(Offset(0, y.toDouble()), Offset(AgiDisplay.renderedWidth.toDouble(), y.toDouble()), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AgiPicturePainter oldDelegate) {
    return oldDelegate.picture != picture ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.actors != actors ||
        oldDelegate.flatVisualImage != flatVisualImage ||
        oldDelegate.priorityMapImage != priorityMapImage ||
        oldDelegate.controlMapImage != controlMapImage ||
        oldDelegate.isolatedPrioritySlice != isolatedPrioritySlice ||
        oldDelegate.showPixelGrid != showPixelGrid;
  }
}

/// CustomPainter that renders a retro CRT shader effect (scanlines, phosphor shadow mask, screen curvature & vignette).
class CrtShaderOverlayPainter extends CustomPainter {
  final double scanlineIntensity;
  final double vignetteIntensity;
  final double curvature;

  const CrtShaderOverlayPainter({
    this.scanlineIntensity = 0.22,
    this.vignetteIntensity = 0.35,
    this.curvature = 0.05,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw subtle horizontal scanlines
    final scanlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: scanlineIntensity)
      ..strokeWidth = 1.0;

    const scanlineStep = 2.0;
    for (double y = 0; y < size.height; y += scanlineStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanlinePaint);
    }

    // 2. Phosphor vertical aperture grille micro-tint
    final phosphorPaint = Paint()
      ..color = const Color(0x1100FF55)
      ..strokeWidth = 1.0;
    for (double x = 0; x < size.width; x += 3.0) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), phosphorPaint);
    }

    // 3. Radial vignette for CRT tube curvature & darkening corners
    final center = Offset(size.width / 2, size.height / 2);
    final radius = max(size.width, size.height) * 0.72;
    final vignettePaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: vignetteIntensity * 0.4),
          Colors.black.withValues(alpha: vignetteIntensity),
        ],
        [0.0, 0.75, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vignettePaint);

    // 4. Subtle bezel frame border
    final bezelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(Offset.zero & size, bezelPaint);
  }

  @override
  bool shouldRepaint(covariant CrtShaderOverlayPainter oldDelegate) {
    return oldDelegate.scanlineIntensity != scanlineIntensity ||
        oldDelegate.vignetteIntensity != vignetteIntensity ||
        oldDelegate.curvature != curvature;
  }
}

/// Flutter Widget that renders an [AgiPic] with full view controls, CRT shader, integer scaling, and aspect ratio correction.
class AgiPictureWidget extends StatefulWidget {
  final AgiPic picture;
  final AgiPictureRenderMode renderMode;
  final List<AgiActorSprite> actors;
  final bool showToolbar;
  final bool enableCrtShader;
  final bool enableIntegerScaling;
  final bool enableAspectRatioCorrection;
  final bool showPixelGrid;
  final int? isolatedPrioritySlice;
  final void Function(int x, int y)? onHoverPixel;
  final void Function()? onExitHover;

  const AgiPictureWidget({
    super.key,
    required this.picture,
    AgiPictureRenderMode renderMode = AgiPictureRenderMode.compositedSlices,
    AgiPictureRenderMode? initialMode,
    this.actors = const [],
    this.showToolbar = false,
    this.enableCrtShader = false,
    this.enableIntegerScaling = false,
    this.enableAspectRatioCorrection = true,
    this.showPixelGrid = false,
    this.isolatedPrioritySlice,
    this.onHoverPixel,
    this.onExitHover,
  }) : renderMode = initialMode ?? renderMode;

  @override
  State<AgiPictureWidget> createState() => _AgiPictureWidgetState();
}

class _AgiPictureWidgetState extends State<AgiPictureWidget> {
  late AgiPictureRenderMode _internalMode;
  AgiPic? _displayedPic;
  ui.Image? _flatImage;
  ui.Image? _priImage;
  ui.Image? _ctrlImage;
  int _loadToken = 0;

  AgiPictureRenderMode get _effectiveMode => widget.showToolbar ? _internalMode : widget.renderMode;

  @override
  void initState() {
    super.initState();
    _internalMode = widget.renderMode;
    _displayedPic = widget.picture;
    _loadAllTexturesFor(widget.picture);
  }

  @override
  void didUpdateWidget(covariant AgiPictureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.picture != widget.picture) {
      _loadAllTexturesFor(widget.picture);
    } else if (oldWidget.renderMode != widget.renderMode) {
      _internalMode = widget.renderMode;
      _ensureModeImageLoaded(widget.renderMode);
    }
  }

  Future<void> _loadAllTexturesFor(AgiPic pic) async {
    final token = ++_loadToken;
    final flatFuture = pic.toFlatVisualUiImage();
    final priFuture = _decodeRgba(pic.renderPriorityMapRgba());
    final ctrlFuture = _decodeRgba(pic.renderControlMapRgba());
    final slicesFuture = pic.preloadGpuTextures();

    final results = await Future.wait([slicesFuture, flatFuture, priFuture, ctrlFuture]);

    if (!mounted || token != _loadToken) return;

    setState(() {
      _displayedPic = pic;
      _flatImage = results[1] as ui.Image;
      _priImage = results[2] as ui.Image;
      _ctrlImage = results[3] as ui.Image;
    });
  }

  Future<void> _ensureModeImageLoaded(AgiPictureRenderMode mode) async {
    final targetPic = _displayedPic ?? widget.picture;
    switch (mode) {
      case AgiPictureRenderMode.compositedSlices:
        await targetPic.preloadGpuTextures();
        break;
      case AgiPictureRenderMode.flatVisual:
        _flatImage ??= await targetPic.toFlatVisualUiImage();
        break;
      case AgiPictureRenderMode.priorityMap:
        _priImage ??= await _decodeRgba(targetPic.renderPriorityMapRgba());
        break;
      case AgiPictureRenderMode.controlMap:
        _ctrlImage ??= await _decodeRgba(targetPic.renderControlMapRgba());
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

  void _handlePointerHover(PointerEvent event, Size canvasSize) {
    if (widget.onHoverPixel == null || canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }
    final normX = (event.localPosition.dx / canvasSize.width).clamp(0.0, 0.999);
    final normY = (event.localPosition.dy / canvasSize.height).clamp(0.0, 0.999);

    final agiX = (normX * AgiDisplay.nativeWidth).floor().clamp(0, AgiDisplay.nativeWidth - 1);
    final agiY = (normY * AgiDisplay.screenHeight).floor().clamp(0, AgiDisplay.screenHeight - 1);

    widget.onHoverPixel!(agiX, agiY);
  }

  @override
  Widget build(BuildContext context) {
    final targetAspect = widget.enableAspectRatioCorrection ? (4.0 / 3.0) : (320.0 / 200.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        double displayWidth;
        double displayHeight;

        if (widget.enableIntegerScaling) {
          // Native base unit: 320 x (240 in 4:3 mode or 200 in 16:10 mode)
          final baseW = 320.0;
          final baseH = widget.enableAspectRatioCorrection ? 240.0 : 200.0;

          final maxScaleX = (constraints.maxWidth / baseW).floor();
          final maxScaleY = (constraints.maxHeight / baseH).floor();
          final scale = max(1, min(maxScaleX, maxScaleY)).toDouble();

          displayWidth = baseW * scale;
          displayHeight = baseH * scale;
        } else {
          // Fit into container while maintaining target aspect ratio
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;

          if (maxW / maxH > targetAspect) {
            displayHeight = maxH;
            displayWidth = maxH * targetAspect;
          } else {
            displayWidth = maxW;
            displayHeight = maxW / targetAspect;
          }
        }

        final canvasSize = Size(displayWidth, displayHeight);

        final canvasWidget = Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: MouseRegion(
              onHover: (event) => _handlePointerHover(event, canvasSize),
              onExit: (_) => widget.onExitHover?.call(),
              cursor: SystemMouseCursors.precise,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Main Picture Canvas
                  Container(
                    color: Colors.black,
                    child: CustomPaint(
                      painter: AgiPicturePainter(
                        picture: _displayedPic ?? widget.picture,
                        renderMode: _effectiveMode,
                        actors: widget.actors,
                        flatVisualImage: _flatImage,
                        priorityMapImage: _priImage,
                        controlMapImage: _ctrlImage,
                        isolatedPrioritySlice: widget.isolatedPrioritySlice,
                        showPixelGrid: widget.showPixelGrid,
                      ),
                    ),
                  ),

                  // Optional CRT Shader Overlay
                  if (widget.enableCrtShader)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CrtShaderOverlayPainter(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        if (widget.showToolbar) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolbar(),
              const SizedBox(height: 8),
              Expanded(child: canvasWidget),
            ],
          );
        }

        return canvasWidget;
      },
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
      selected: {_internalMode},
      onSelectionChanged: (set) {
        final newMode = set.first;
        setState(() => _internalMode = newMode);
        _ensureModeImageLoaded(newMode);
      },
    );
  }
}
