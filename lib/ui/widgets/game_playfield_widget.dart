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
  final bool renderBlackTextBackgrounds;
  final bool correctAspectRatio;
  final bool strictIntegerScaling;
  final int? isolatedPrioritySlice;
  final String currentInputText;
  final ValueChanged<Offset>? onCanvasTap;

  const GamePlayfieldWidget({
    super.key,
    required this.engine,
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.showCrtShader = false,
    this.showPixelGrid = false,
    this.renderBlackTextBackgrounds = false,
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
    this.isolatedPrioritySlice,
    this.currentInputText = '',
    this.onCanvasTap,
  });

  @override
  State<GamePlayfieldWidget> createState() => _GamePlayfieldWidgetState();
}

class _GamePlayfieldWidgetState extends State<GamePlayfieldWidget> {
  final Map<String, ui.Image> _spriteTextureCache = {};
  final Set<String> _pendingDecodes = {};
  final ValueNotifier<bool> _cursorBlink = ValueNotifier<bool>(true);
  Timer? _blinkTimer;
  late Listenable _repaint;
  AgiPic? _trackedPic;
  AgiPictureRenderMode? _trackedMode;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([widget.engine, _cursorBlink]);
    widget.engine.addListener(_onEngineNotify);
    widget.engine.atlasManager.onAtlasUpdated = () {
      if (mounted) setState(() {});
    };
    widget.engine.atlasManager.prepareAtlasAsync();
    _onEngineNotify();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _cursorBlink.value = !_cursorBlink.value;
    });
  }

  @override
  void didUpdateWidget(covariant GamePlayfieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.removeListener(_onEngineNotify);
      oldWidget.engine.atlasManager.onAtlasUpdated = null;
      widget.engine.addListener(_onEngineNotify);
      _repaint = Listenable.merge([widget.engine, _cursorBlink]);
      widget.engine.atlasManager.onAtlasUpdated = () {
        if (mounted) setState(() {});
      };
      widget.engine.atlasManager.prepareAtlasAsync();
    }
    if (oldWidget.renderMode != widget.renderMode ||
        oldWidget.engine.currentPic != widget.engine.currentPic) {
      _onEngineNotify();
    }
  }

  void _onEngineNotify() {
    final pic = widget.engine.currentPic;
    final mode = widget.renderMode;
    if (pic == _trackedPic && mode == _trackedMode) return;
    _trackedPic = pic;
    _trackedMode = mode;
    _ensureRenderModeTextureLoaded(pic, mode);
  }

  void _ensureRenderModeTextureLoaded(AgiPic? pic, AgiPictureRenderMode mode) {
    if (pic == null) return;
    switch (mode) {
      case AgiPictureRenderMode.compositedSlices:
        if (pic.slices.values.any((s) => s.hasVisiblePixels && s.cachedUiImage == null)) {
          final f = pic.preloadGpuTextures();
          if (f is Future) {
            f.then((_) {
              if (mounted) setState(() {});
            });
          }
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
    widget.engine.removeListener(_onEngineNotify);
    widget.engine.atlasManager.onAtlasUpdated = null;
    _blinkTimer?.cancel();
    for (final img in _spriteTextureCache.values) {
      img.dispose();
    }
    _spriteTextureCache.clear();
    super.dispose();
    _cursorBlink.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _GamePlayfieldPainter(
                          engine: widget.engine,
                          renderMode: widget.renderMode,
                          showPixelGrid: widget.showPixelGrid,
                          renderBlackTextBackgrounds: widget.renderBlackTextBackgrounds,
                          isolatedPrioritySlice: widget.isolatedPrioritySlice,
                          cursorBlink: _cursorBlink,
                          buildActors: _buildActorSprites,
                          repaint: _repaint,
                        ),
                        isComplex: true,
                        willChange: true,
                        child: const SizedBox.expand(),
                      ),
                    ),

                    // Optional CRT retro shader overlay
                    if (widget.showCrtShader)
                      const CrtShaderOverlay(),

                    // Command prompt is cheap chrome; keep it off the picture painter.
                    ListenableBuilder(
                      listenable: _repaint,
                      builder: (context, _) {
                        if (!widget.engine.isInputEnabled) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: (widget.engine.inputRow.clamp(0, 24) / 25.0) * playfieldHeight,
                          left: (1.0 / 40.0) * playfieldWidth,
                          right: (1.0 / 40.0) * playfieldWidth,
                          child: _buildIntegratedPrompt(
                            prompt: widget.engine.memory.getString(0).isNotEmpty
                                ? widget.engine.memory.getString(0)
                                : '>',
                            text: widget.currentInputText,
                            showCursor: _cursorBlink.value,
                            fontSize: math.max(11.0, playfieldWidth / 48.0),
                            playfieldWidth: playfieldWidth,
                          ),
                        );
                      },
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

  Widget _buildIntegratedPrompt({
    required String prompt,
    required String text,
    required bool showCursor,
    required double fontSize,
    required double playfieldWidth,
  }) {
    final promptText = prompt.endsWith(' ') ? prompt : '$prompt ';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          promptText,
          style: TextStyle(
            color: const Color(0xFF55FFFF),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
            letterSpacing: 0.1,
          ),
        ),
        if (text.isNotEmpty)
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              height: 1.0,
              letterSpacing: 0.1,
            ),
          ),
        if (showCursor)
          Container(
            width: math.max(2.0, fontSize * 0.45),
            height: fontSize * 0.9,
            margin: const EdgeInsets.only(left: 1),
            color: const Color(0xFF55FFFF),
          ),
      ],
    );
  }

  List<AgiActorSprite> _buildActorSprites() {
    final actors = <AgiActorSprite>[];
    final atlasMgr = widget.engine.atlasManager;

    for (final obj in widget.engine.animatedObjects) {
      if (!obj.isDrawn) continue;

      try {
        final viewRes = obj.cachedView ?? widget.engine.getView(obj.view);
        if (obj.cachedView == null && viewRes != null) {
          obj.updateCachedView(viewRes);
        }
        final loop = viewRes?.getLoop(obj.loop);
        final safeCel = (loop != null && loop.celCount > 0 && obj.cel >= loop.celCount) ? 0 : obj.cel;
        final celHeight = obj.getCelHeight(null, safeCel, viewRes);
        final renderX = (obj.x * 2).toDouble();
        final renderY = (obj.y - celHeight + 1).toDouble();

        final targetAtlas = atlasMgr.getAtlasForCel(obj.view, obj.loop, safeCel) ?? atlasMgr.primaryAtlas;
        final cel = loop?.getCel(safeCel);

        if (targetAtlas != null && targetAtlas.containsCel(obj.view, obj.loop, safeCel) && targetAtlas.hasImage) {
          actors.add(
            AgiActorSprite(
              priority: obj.effectivePriority,
              baselineY: obj.effectiveSortY,
              objectNumber: obj.number,
              isUpdating: obj.isUpdating,
              position: Offset(renderX, renderY),
              viewNumber: obj.view,
              loopNumber: obj.loop,
              celNumber: safeCel,
              atlas: targetAtlas,
            ),
          );
        } else {
          // If not in atlas or atlas image is decoding, trigger atlas build/side-atlas
          if (viewRes != null) {
            atlasMgr.registerView(viewRes);
            atlasMgr.prepareAtlasAsync();
          }

          final cacheKey = 'v${obj.view}_l${obj.loop}_c$safeCel';
          final cachedImage = _spriteTextureCache[cacheKey];

          actors.add(
            AgiActorSprite(
              priority: obj.effectivePriority,
              baselineY: obj.effectiveSortY,
              objectNumber: obj.number,
              isUpdating: obj.isUpdating,
              position: Offset(renderX, renderY),
              viewNumber: obj.view,
              loopNumber: obj.loop,
              celNumber: safeCel,
              image: cachedImage,
              atlas: (targetAtlas != null && targetAtlas.hasImage && targetAtlas.containsCel(obj.view, obj.loop, safeCel))
                  ? targetAtlas
                  : null,
            ),
          );
          if (cachedImage == null && cel != null && viewRes != null) {
            _decodeSpriteCel(cacheKey, cel, viewRes, safeCel);
          }
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

/// Paints the live engine playfield. Subscribed to [repaint] (engine + cursor
/// blink) so AGI ticks call [paint] without rebuilding the surrounding widgets.
class _GamePlayfieldPainter extends CustomPainter {
  final AgiGameEngine engine;
  final AgiPictureRenderMode renderMode;
  final bool showPixelGrid;
  final bool renderBlackTextBackgrounds;
  final int? isolatedPrioritySlice;
  final ValueNotifier<bool> cursorBlink;
  final List<AgiActorSprite> Function() buildActors;

  _GamePlayfieldPainter({
    required this.engine,
    required this.renderMode,
    required this.showPixelGrid,
    required this.renderBlackTextBackgrounds,
    required this.isolatedPrioritySlice,
    required this.cursorBlink,
    required this.buildActors,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final pic = engine.currentPic;
    final prompt = engine.activeInputPrompt;

    canvas.save();
    canvas.translate(engine.shakeOffsetX, engine.shakeOffsetY);
    AgiPicturePainter(
      picture: pic,
      actors: buildActors(),
      displayedTexts: engine.displayedTexts,
      textScreenBuffer: engine.textScreenBuffer,
      isTextScreen: engine.isTextScreen,
      textFgColor: engine.textFgColor,
      textBgColor: engine.textBgColor,
      playfieldRow: engine.playfieldRow,
      showCursor: cursorBlink.value && prompt?.row != null,
      cursorRow: prompt?.row,
      cursorCol: prompt?.col ?? 0,
      cursorPromptText: (prompt != null && prompt.row != null)
          ? '${prompt.prompt}${prompt.currentText}'
          : null,
      renderMode: renderMode,
      flatVisualImage: pic?.cachedFlatVisualImage,
      priorityMapImage: pic?.cachedPriorityMapImage,
      controlMapImage: pic?.cachedControlMapImage,
      isolatedPrioritySlice: isolatedPrioritySlice,
      showPixelGrid: showPixelGrid,
      renderBlackTextBackgrounds: renderBlackTextBackgrounds,
      menuManager: engine.menuManager,
    ).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePlayfieldPainter oldDelegate) {
    return oldDelegate.engine != engine ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.showPixelGrid != showPixelGrid ||
        oldDelegate.renderBlackTextBackgrounds != renderBlackTextBackgrounds ||
        oldDelegate.isolatedPrioritySlice != isolatedPrioritySlice;
  }
}
