import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Interactive composite playfield viewport for the running AGI Game Engine.
///
/// Composites 16 Impeller priority depth slices with active actor sprites
/// in authentic Z-order, with optional CRT shader overlays and diagnostic maps.
class GamePlayfieldWidget extends StatefulWidget {
  final AgiGameEngine engine;
  final AgiPictureRenderMode renderMode;
  final bool showCrtShader;
  final bool showPixelGrid;
  final bool correctAspectRatio;
  final bool strictIntegerScaling;
  final int? isolatedPrioritySlice;
  final ValueChanged<Offset>? onCanvasTap;

  const GamePlayfieldWidget({
    super.key,
    required this.engine,
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.showCrtShader = false,
    this.showPixelGrid = false,
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
    this.isolatedPrioritySlice,
    this.onCanvasTap,
  });

  @override
  State<GamePlayfieldWidget> createState() => _GamePlayfieldWidgetState();
}

class _GamePlayfieldWidgetState extends State<GamePlayfieldWidget> {
  final Map<String, ui.Image> _spriteTextureCache = {};
  final Set<String> _pendingDecodes = {};
  Timer? _blinkTimer;
  bool _cursorBlink = true;

  @override
  void initState() {
    super.initState();
    _ensureRenderModeTextureLoaded(widget.engine.currentPic, widget.renderMode);
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && widget.engine.activeInputPrompt?.row != null) {
        setState(() {
          _cursorBlink = !_cursorBlink;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant GamePlayfieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderMode != widget.renderMode ||
        oldWidget.engine.currentPic != widget.engine.currentPic) {
      _ensureRenderModeTextureLoaded(widget.engine.currentPic, widget.renderMode);
    }
  }

  void _ensureRenderModeTextureLoaded(AgiPic? pic, AgiPictureRenderMode mode) {
    if (pic == null) return;
    switch (mode) {
      case AgiPictureRenderMode.compositedSlices:
        if (pic.activeSlices.any((s) => s.cachedUiImage == null)) {
          pic.preloadGpuTextures().then((_) {
            if (mounted) setState(() {});
          });
        }
        break;
      case AgiPictureRenderMode.flatVisual:
        if (pic.cachedFlatVisualImage == null) {
          pic.toFlatVisualUiImage().then((_) {
            if (mounted) setState(() {});
          });
        }
        break;
      case AgiPictureRenderMode.priorityMap:
        if (pic.cachedPriorityMapImage == null) {
          pic.toPriorityMapUiImage().then((_) {
            if (mounted) setState(() {});
          });
        }
        break;
      case AgiPictureRenderMode.controlMap:
        if (pic.cachedFlatVisualImage == null) {
          pic.toFlatVisualUiImage().then((_) {
            if (mounted) setState(() {});
          });
        }
        if (pic.cachedControlMapImage == null) {
          pic.toControlMapUiImage().then((_) {
            if (mounted) setState(() {});
          });
        }
        break;
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    for (final img in _spriteTextureCache.values) {
      img.dispose();
    }
    _spriteTextureCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPic = widget.engine.currentPic;
    if (currentPic != null) {
      _ensureRenderModeTextureLoaded(currentPic, widget.renderMode);
    }

    final targetAspect = widget.correctAspectRatio ? (4.0 / 3.0) : (320.0 / 200.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        if (availableWidth <= 0 || availableHeight <= 0) {
          return const SizedBox.shrink();
        }

        double playfieldWidth;
        double playfieldHeight;

        if (widget.strictIntegerScaling) {
          final int baseWidth = 320;
          final int baseHeight = widget.correctAspectRatio ? 240 : 200;

          final maxScaleX = availableWidth ~/ baseWidth;
          final maxScaleY = availableHeight ~/ baseHeight;
          final scale = math.max(1, math.min(maxScaleX, maxScaleY));

          playfieldWidth = (baseWidth * scale).toDouble();
          playfieldHeight = (baseHeight * scale).toDouble();
        } else {
          // Smooth aspect-fit scaling
          final containerAspect = availableWidth / availableHeight;
          if (containerAspect > targetAspect) {
            // Container is wider than target aspect ratio -> height-constrained
            playfieldHeight = availableHeight;
            playfieldWidth = availableHeight * targetAspect;
          } else {
            // Container is taller than target aspect ratio -> width-constrained
            playfieldWidth = availableWidth;
            playfieldHeight = availableWidth / targetAspect;
          }
        }

        return Center(
          child: SizedBox(
            width: playfieldWidth,
            height: playfieldHeight,
            child: GestureDetector(
              onTapUp: (details) {
                if (playfieldWidth > 0 && playfieldHeight > 0) {
                  // 0. If full text screen is active (e.g. Help or About screen), tap dismisses it
                  if (widget.engine.isTextScreen) {
                    widget.engine.handleKeyPress(13);
                    widget.engine.tick();
                    return;
                  }

                  final localPos = details.localPosition;
                  final normX = localPos.dx / playfieldWidth;
                  final normY = localPos.dy / playfieldHeight;
                  final screenX = normX * AgiDisplay.renderedWidth;
                  final screenY = normY * AgiDisplay.renderedHeight;
                  final charCol = (screenX / 8.0).floor();
                  final charRow = (screenY / 8.0).floor();

                  // 1. Top Bar Tap Handling (Row 0: Status Line / Menu Bar)
                  if (charRow == 0) {
                    if (!widget.engine.isMenuOpen) {
                      if (widget.engine.menuManager.isAvailable && widget.engine.memory.getFlag(14)) {
                        int targetMenu = 0;
                        for (int i = 0; i < widget.engine.menuManager.menus.length; i++) {
                          final m = widget.engine.menuManager.menus[i];
                          if (charCol >= m.column - 1 && charCol < m.column + m.name.length + 1) {
                            targetMenu = i;
                            break;
                          }
                        }
                        widget.engine.openMenu(menuIndex: targetMenu);
                      }
                    } else {
                      bool tappedHeader = false;
                      for (int i = 0; i < widget.engine.menuManager.menus.length; i++) {
                        final m = widget.engine.menuManager.menus[i];
                        if (charCol >= m.column - 1 && charCol < m.column + m.name.length + 1) {
                          widget.engine.menuManager.setActiveMenu(i);
                          tappedHeader = true;
                          break;
                        }
                      }
                      if (!tappedHeader) {
                        widget.engine.closeMenu();
                      }
                    }
                    return;
                  }

                  // 2. Dropdown Menu Tap Handling (when menu is active)
                  if (charRow > 0 && widget.engine.isMenuOpen) {
                    final activeMenu = widget.engine.menuManager.activeMenu;
                    if (activeMenu != null && activeMenu.items.isNotEmpty) {
                      final maxLen = math.max(activeMenu.maxItemTextLength, 10);
                      final col = activeMenu.items.first.column;
                      final boxWidth = (maxLen + 2) * 8.0;
                      final boxHeight = (activeMenu.items.length + 1) * 8.0;
                      final left = ((col - 1) * 8.0).clamp(0.0, 320.0 - boxWidth);
                      final right = left + boxWidth;
                      const top = 8.0;
                      final bottom = top + boxHeight;

                      if (screenX >= left && screenX <= right && screenY >= top && screenY <= bottom) {
                        final itemIndex = ((screenY - top) / 8.0).floor();
                        if (itemIndex >= 0 && itemIndex < activeMenu.items.length) {
                          final item = activeMenu.items[itemIndex];
                          if (!item.isSeparator && item.isEnabled) {
                            widget.engine.menuManager.setSelectedItemIndex(itemIndex);
                            widget.engine.selectMenuItem();
                            return;
                          }
                        }
                      } else {
                        widget.engine.closeMenu();
                        return;
                      }
                    } else {
                      widget.engine.closeMenu();
                      return;
                    }
                  }

                  // 3. Playfield Canvas Tap
                  if (widget.onCanvasTap != null) {
                    final agiX = (screenX / 2.0).clamp(0.0, (AgiPic.nativeWidth - 1).toDouble());
                    final agiY = (screenY - widget.engine.playfieldRow * 8.0).clamp(0.0, (AgiPic.nativeHeight - 1).toDouble());
                    widget.onCanvasTap!(Offset(agiX, agiY));
                  }
                }
              },
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.engine.isTextScreen || currentPic != null)
                      CustomPaint(
                        painter: AgiPicturePainter(
                          picture: currentPic,
                          actors: _buildActorSprites(),
                          displayedTexts: widget.engine.displayedTexts,
                          textScreenBuffer: widget.engine.textScreenBuffer,
                          isTextScreen: widget.engine.isTextScreen,
                          textFgColor: widget.engine.textFgColor,
                          textBgColor: widget.engine.textBgColor,
                          playfieldRow: widget.engine.playfieldRow,
                          showCursor: _cursorBlink && (widget.engine.activeInputPrompt?.row != null),
                          cursorRow: widget.engine.activeInputPrompt?.row,
                          cursorCol: widget.engine.activeInputPrompt?.col ?? 0,
                          cursorPromptText: (widget.engine.activeInputPrompt != null && widget.engine.activeInputPrompt!.row != null)
                              ? '${widget.engine.activeInputPrompt!.prompt}${widget.engine.activeInputPrompt!.currentText}'
                              : null,
                          renderMode: widget.renderMode,
                          flatVisualImage: currentPic?.cachedFlatVisualImage,
                          priorityMapImage: currentPic?.cachedPriorityMapImage,
                          controlMapImage: currentPic?.cachedControlMapImage,
                          isolatedPrioritySlice: widget.isolatedPrioritySlice,
                          showPixelGrid: widget.showPixelGrid,
                          menuManager: widget.engine.menuManager,
                        ),
                      )
                    else
                      const Center(
                        child: Text(
                          'NO PICTURE LOADED',
                          style: TextStyle(
                            color: Color(0xFF55FFFF),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),

                    // Optional CRT retro shader overlay
                    if (widget.showCrtShader)
                      const IgnorePointer(
                        child: CustomPaint(
                          painter: CrtShaderOverlayPainter(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<AgiActorSprite> _buildActorSprites() {
    final actors = <AgiActorSprite>[];
    final loader = widget.engine.resourceLoader;
    if (loader == null) return actors;

    for (final obj in widget.engine.animatedObjects) {
      if (!obj.isDrawn) continue;
      if (obj.view == 0 && obj.number != 0) continue;

      try {
        final viewRes = loader.loadView(obj.view);
        final cel = viewRes.getCel(obj.loop, obj.cel);
        if (cel == null) continue;

        final cacheKey = 'v${obj.view}_l${obj.loop}_c${obj.cel}';
        final cachedImage = _spriteTextureCache[cacheKey];

        if (cachedImage != null) {
          // In AGI coordinate system:
          // obj.x is left (0..159), obj.y is baseline (0..167).
          // Rendered canvas is 320x200 (pixel doubled horizontally).
          final renderX = (obj.x * 2).toDouble();
          final renderY = (obj.y - cel.height + 1).toDouble();

          actors.add(
            AgiActorSprite(
              priority: obj.effectivePriority,
              baselineY: obj.effectiveSortY,
              objectNumber: obj.number,
              image: cachedImage,
              position: Offset(renderX, renderY),
            ),
          );
        } else {
          _decodeSpriteCel(cacheKey, cel, viewRes, obj.cel);
        }
      } catch (_) {}
    }

    return actors;
  }

  void _decodeSpriteCel(
    String cacheKey,
    dynamic cel,
    dynamic parentView,
    int celIndex,
  ) {
    if (_pendingDecodes.contains(cacheKey)) return;
    _pendingDecodes.add(cacheKey);

    final rgbaBytes = cel.toRgba(
      parentView: parentView,
      celIndex: celIndex,
      scaleX: 2,
      scaleY: 1,
    ) as Uint8List;

    ui.decodeImageFromPixels(
      rgbaBytes,
      cel.width * 2,
      cel.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) {
          setState(() {
            _spriteTextureCache[cacheKey] = image;
            _pendingDecodes.remove(cacheKey);
          });
        } else {
          image.dispose();
        }
      },
    );
  }
}
