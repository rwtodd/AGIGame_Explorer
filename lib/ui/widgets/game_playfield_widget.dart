import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/domain/sierra_game_session.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/picture/sci_pic.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Interactive composite playfield viewport for the running Sierra Game Engine.
///
/// Composites Impeller priority depth slices with active actor sprites
/// in authentic Z-order, with optional CRT shader overlays and diagnostic maps.
class GamePlayfieldWidget extends StatefulWidget {
  final AgiGameEngine? engine;
  final SierraGameSession? session;
  final AgiPictureRenderMode renderMode;
  final bool showCrtShader;
  final bool showPixelGrid;
  final bool renderBlackTextBackgrounds;
  final bool correctAspectRatio;
  final bool strictIntegerScaling;
  final int? isolatedPrioritySlice;
  final String currentInputText;
  final ValueChanged<Offset>? onCanvasTap;

  /// Display resolution, viewport, and priority geometry profile.
  final DisplayProfile? displayProfile;

  /// Active Sierra in-game mouse cursor.
  final SierraCursor? mouseCursor;

  /// Whether to render the custom in-game mouse cursor on the playfield.
  final bool showMouseCursor;

  /// Top-level SCI Window overlays (dialog boxes, message boxes, text controls).
  final List<SciWindowOverlay> sciWindows;

  const GamePlayfieldWidget({
    super.key,
    this.engine,
    this.session,
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.showCrtShader = false,
    this.showPixelGrid = false,
    this.renderBlackTextBackgrounds = false,
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
    this.isolatedPrioritySlice,
    this.currentInputText = '',
    this.onCanvasTap,
    this.displayProfile,
    this.mouseCursor,
    this.showMouseCursor = false,
    this.sciWindows = const [],
  }) : assert(engine != null || session != null, 'Either engine or session must be provided');

  @override
  State<GamePlayfieldWidget> createState() => _GamePlayfieldWidgetState();
}

class _GamePlayfieldWidgetState extends State<GamePlayfieldWidget> {
  final Map<int, ui.Image> _spriteTextureCache = {};
  final Set<int> _pendingDecodes = {};
  final ValueNotifier<bool> _cursorBlink = ValueNotifier<bool>(true);
  Timer? _blinkTimer;
  late Listenable _repaint;
  SierraPicture? _trackedPic;
  AgiPictureRenderMode? _trackedMode;
  Offset? _mousePosition;

  SierraGameSession get _session => widget.session ?? widget.engine!;
  AgiGameEngine? get _agiEngine =>
      widget.engine ?? (widget.session is AgiGameEngine ? widget.session as AgiGameEngine : null);

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([_session, _cursorBlink]);
    _session.addListener(_onEngineNotify);
    if (_agiEngine != null) {
      _agiEngine!.atlasManager.onAtlasUpdated = () {
        if (mounted) setState(() {});
      };
      _agiEngine!.atlasManager.prepareAtlasAsync();
    } else if (_session is SciGameEngine) {
      (_session as SciGameEngine).atlasManager.onAtlasUpdated = () {
        if (mounted) setState(() {});
      };
    }
    _onEngineNotify();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _cursorBlink.value = !_cursorBlink.value;
    });
  }

  @override
  void didUpdateWidget(covariant GamePlayfieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSession = oldWidget.session ?? oldWidget.engine!;
    final curSession = _session;
    if (oldSession != curSession) {
      oldSession.removeListener(_onEngineNotify);
      if (oldWidget.engine != null) {
        oldWidget.engine!.atlasManager.onAtlasUpdated = null;
      }
      curSession.addListener(_onEngineNotify);
      _repaint = Listenable.merge([curSession, _cursorBlink]);
      if (_agiEngine != null) {
        _agiEngine!.atlasManager.onAtlasUpdated = () {
          if (mounted) setState(() {});
        };
        _agiEngine!.atlasManager.prepareAtlasAsync();
      } else if (curSession is SciGameEngine) {
        curSession.atlasManager.onAtlasUpdated = () {
          if (mounted) setState(() {});
        };
      }
    }
    if (oldWidget.renderMode != widget.renderMode ||
        oldSession.currentPic != curSession.currentPic) {
      _onEngineNotify();
    }
  }

  void _onEngineNotify() {
    final pic = _session.currentPic;
    final mode = widget.renderMode;
    if (pic == _trackedPic && mode == _trackedMode) return;
    _trackedPic = pic;
    _trackedMode = mode;
    if (pic != null) {
      _ensureRenderModeTextureLoaded(pic, mode);
    }
  }

  void _ensureRenderModeTextureLoaded(SierraPicture? pic, AgiPictureRenderMode mode) {
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
      case AgiPictureRenderMode.unditheredVisual:
        if (pic is SciPic && pic.cachedUnditheredVisualImage == null) {
          pic.toFlatVisualUiImage(undithered: true).then((_) {
            if (mounted) setState(() {});
          });
        } else if (pic.cachedFlatVisualImage == null) {
          pic.toFlatVisualUiImage().then((_) {
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
    _session.removeListener(_onEngineNotify);
    if (_agiEngine != null) {
      _agiEngine!.atlasManager.onAtlasUpdated = null;
    } else if (_session is SciGameEngine) {
      (_session as SciGameEngine).atlasManager.onAtlasUpdated = null;
    }
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
            child: MouseRegion(
              cursor: (widget.showMouseCursor || _session.showMouseCursor)
                  ? SystemMouseCursors.none
                  : MouseCursor.defer,
              onHover: (event) {
                if (!widget.showMouseCursor && !_session.showMouseCursor) return;
                if (playfieldWidth > 0 && playfieldHeight > 0) {
                  final normX = event.localPosition.dx / playfieldWidth;
                  final normY = event.localPosition.dy / playfieldHeight;
                  final profile = widget.displayProfile ?? _session.displayProfile;
                  final next = Offset(
                    (normX * profile.width).floorToDouble(),
                    (normY * profile.height).floorToDouble(),
                  );
                  if (_mousePosition == next) return;
                  setState(() {
                    _mousePosition = next;
                  });
                }
              },
              onExit: (_) {
                if (!widget.showMouseCursor && !_session.showMouseCursor) return;
                if (_mousePosition != null) {
                  setState(() {
                    _mousePosition = null;
                  });
                }
              },
              child: GestureDetector(
              onTapUp: (details) {
                if (playfieldWidth > 0 && playfieldHeight > 0) {
                  final agi = _agiEngine;
                  // 0. If full text screen is active (e.g. Help or About screen), tap dismisses it
                  if (agi != null && agi.isTextScreen) {
                    agi.handleKeyPress(13);
                    agi.tick();
                    return;
                  }

                  final localPos = details.localPosition;
                  final normX = localPos.dx / playfieldWidth;
                  final normY = localPos.dy / playfieldHeight;
                  final profile = widget.displayProfile ?? _session.displayProfile;
                  final screenX = normX * profile.width;
                  final screenY = normY * profile.height;
                  final charCol = (screenX / 8.0).floor();
                  final charRow = (screenY / 8.0).floor();

                  if (agi != null) {
                    // 1. Top Bar Tap Handling (Row 0: Status Line / Menu Bar)
                    if (charRow == 0) {
                      if (!agi.isMenuOpen) {
                        if (agi.menuManager.isAvailable && agi.memory.getFlag(14)) {
                          int targetMenu = 0;
                          for (int i = 0; i < agi.menuManager.menus.length; i++) {
                            final m = agi.menuManager.menus[i];
                            if (charCol >= m.column - 1 && charCol < m.column + m.name.length + 1) {
                              targetMenu = i;
                              break;
                            }
                          }
                          agi.openMenu(menuIndex: targetMenu);
                        }
                      } else {
                        bool tappedHeader = false;
                        for (int i = 0; i < agi.menuManager.menus.length; i++) {
                          final m = agi.menuManager.menus[i];
                          if (charCol >= m.column - 1 && charCol < m.column + m.name.length + 1) {
                            agi.menuManager.setActiveMenu(i);
                            tappedHeader = true;
                            break;
                          }
                        }
                        if (!tappedHeader) {
                          agi.closeMenu();
                        }
                      }
                      return;
                    }

                    // 2. Dropdown Menu Tap Handling (when menu is active)
                    if (charRow > 0 && agi.isMenuOpen) {
                      final activeMenu = agi.menuManager.activeMenu;
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
                              agi.menuManager.setSelectedItemIndex(itemIndex);
                              agi.selectMenuItem();
                              return;
                            }
                          }
                        } else {
                          agi.closeMenu();
                          return;
                        }
                      } else {
                        agi.closeMenu();
                        return;
                      }
                    }
                  }

                  // 3. Playfield Canvas Tap
                  if (widget.onCanvasTap != null) {
                    final agiX = (screenX / 2.0).clamp(0.0, (AgiPic.nativeWidth - 1).toDouble());
                    final agiY = (screenY - (agi?.playfieldRow ?? 0) * 8.0).clamp(0.0, (AgiPic.nativeHeight - 1).toDouble());
                    widget.onCanvasTap!(Offset(agiX, agiY));
                  }

                  _session.handleMouseClick(Offset(screenX, screenY));
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
                          session: _session,
                          agiEngine: _agiEngine,
                          renderMode: widget.renderMode,
                          showPixelGrid: widget.showPixelGrid,
                          renderBlackTextBackgrounds: widget.renderBlackTextBackgrounds,
                          isolatedPrioritySlice: widget.isolatedPrioritySlice,
                          cursorBlink: _cursorBlink,
                          buildActors: _buildActorSprites,
                          displayProfile: widget.displayProfile ?? _session.displayProfile,
                          sciWindows: widget.sciWindows.isNotEmpty ? widget.sciWindows : _session.sciWindows,
                          mouseCursor: widget.mouseCursor ?? _session.mouseCursor,
                          mouseCursorPosition: _mousePosition ?? _session.mouseCursorPosition,
                          showMouseCursor: widget.showMouseCursor || _session.showMouseCursor,
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
                        if (!_session.isInputEnabled || _agiEngine == null) {
                          return const SizedBox.shrink();
                        }
                        final row = _agiEngine?.inputRow ?? 24;
                        return Positioned(
                          top: (row.clamp(0, 24) / 25.0) * playfieldHeight,
                          left: (1.0 / 40.0) * playfieldWidth,
                          right: (1.0 / 40.0) * playfieldWidth,
                          height: math.max(16.0, playfieldHeight / 25.0 * 1.4),
                          child: _buildIntegratedPrompt(
                            prompt: _session.promptLine.isNotEmpty
                                ? _session.promptLine
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
    final lastAi = _agiEngine?.lastAiTranslation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
        if (lastAi != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xCC0F172A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFF55FFFF).withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 10, color: Color(0xFF55FFFF)),
                const SizedBox(width: 4),
                Text(
                  'AI: "${lastAi.translatedCommand}"',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    color: const Color(0xFF55FFFF),
                    fontSize: math.max(9.0, fontSize * 0.75),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<PlayfieldActorSprite> _buildActorSprites() {
    final agi = _agiEngine;
    if (agi != null) {
      final actors = <PlayfieldActorSprite>[];
      final atlasMgr = agi.atlasManager;

      for (final obj in agi.animatedObjects) {
        if (!obj.isDrawn) continue;

        try {
          final viewRes = obj.cachedView ?? agi.getView(obj.view);
          if (obj.cachedView == null && viewRes != null) {
            obj.updateCachedView(viewRes);
          }
          final loop = viewRes?.getLoop(obj.loop);
          final safeCel = (loop != null && loop.celCount > 0 && obj.cel >= loop.celCount) ? 0 : obj.cel;
          final celHeight = obj.getCelHeight(null, safeCel, viewRes);
          final renderX = (obj.x * 2).toDouble();
          final renderY = (obj.y - celHeight + 1).toDouble();

          final cel = loop?.getCel(safeCel);
          final hit = atlasMgr.lookupCel(obj.view, obj.loop, safeCel);

          if (hit != null && hit.atlas.hasImage) {
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
                atlas: hit.atlas,
                celEntry: hit.entry,
              ),
            );
          } else {
            // If not in atlas or atlas image is decoding, trigger atlas build/side-atlas
            if (viewRes != null) {
              atlasMgr.registerView(viewRes);
              atlasMgr.prepareAtlasAsync();
            }

            final cacheKey = AtlasCelEntry.computeKey(obj.view, obj.loop, safeCel);
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

    final sci = _session is SciGameEngine ? (_session as SciGameEngine) : null;
    if (sci != null) {
      final atlasMgr = sci.atlasManager;
      final actors = <PlayfieldActorSprite>[];
      for (final sprite in _session.actors) {
        var hit = atlasMgr.lookupCel(sprite.viewNumber, sprite.loopNumber, sprite.celNumber);
        if (hit == null || !hit.atlas.hasImage) {
          final view = sci.kernel.getView(sprite.viewNumber);
          if (view != null) {
            atlasMgr.registerView(view);
            atlasMgr.prepareAtlasAsync();
            hit = atlasMgr.lookupCel(sprite.viewNumber, sprite.loopNumber, sprite.celNumber);
          }
        }
        if (hit != null && hit.atlas.hasImage) {
          actors.add(sprite.copyWith(atlas: hit.atlas, celEntry: hit.entry));
          continue;
        }
        final cacheKey = AtlasCelEntry.computeKey(sprite.viewNumber, sprite.loopNumber, sprite.celNumber);
        final cachedImage = _spriteTextureCache[cacheKey];
        actors.add(sprite.copyWith(image: cachedImage));
        if (cachedImage == null) {
          _decodeSciSpriteCel(sci, sprite.viewNumber, sprite.loopNumber, sprite.celNumber);
        }
      }
      return actors;
    }

    return _session.actors;
  }

  void _decodeSciSpriteCel(
    SciGameEngine sci,
    int viewId,
    int loopNo,
    int celNo,
  ) {
    final cacheKey = AtlasCelEntry.computeKey(viewId, loopNo, celNo);
    if (_pendingDecodes.contains(cacheKey)) return;
    _pendingDecodes.add(cacheKey);

    final view = sci.kernel.getView(viewId);
    if (view == null || view.loops.isEmpty) {
      _pendingDecodes.remove(cacheKey);
      return;
    }
    final loop = view.loops[loopNo % view.loops.length];
    if (loop.cels.isEmpty) {
      _pendingDecodes.remove(cacheKey);
      return;
    }
    final safeCel = celNo % loop.cels.length;
    final cel = loop.cels[safeCel];

    final rgbaBytes = cel.toRgba(
      parentView: view,
      celIndex: safeCel,
      scaleX: 1,
      scaleY: 1,
    );

    ui.decodeImageFromPixels(
      rgbaBytes,
      cel.width,
      cel.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) {
          setState(() {
            _spriteTextureCache[cacheKey] = image;
            sci.kernel.cacheCelImage(viewId, loopNo, celNo, image);
            _pendingDecodes.remove(cacheKey);
          });
        } else {
          image.dispose();
        }
      },
    );
  }

  void _decodeSpriteCel(
    int cacheKey,
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

/// Paints the live engine playfield. Subscribed to [repaint] (session + cursor
/// blink) so ticks call [paint] without rebuilding the surrounding widgets.
class _GamePlayfieldPainter extends CustomPainter {
  final SierraGameSession session;
  final AgiGameEngine? agiEngine;
  final AgiPictureRenderMode renderMode;
  final bool showPixelGrid;
  final bool renderBlackTextBackgrounds;
  final int? isolatedPrioritySlice;
  final ValueNotifier<bool> cursorBlink;
  final List<PlayfieldActorSprite> Function() buildActors;
  final DisplayProfile? displayProfile;
  final List<SciWindowOverlay> sciWindows;
  final SierraCursor? mouseCursor;
  final Offset? mouseCursorPosition;
  final bool showMouseCursor;

  _GamePlayfieldPainter({
    required this.session,
    this.agiEngine,
    required this.renderMode,
    required this.showPixelGrid,
    required this.renderBlackTextBackgrounds,
    required this.isolatedPrioritySlice,
    required this.cursorBlink,
    required this.buildActors,
    this.displayProfile,
    this.sciWindows = const [],
    this.mouseCursor,
    this.mouseCursorPosition,
    this.showMouseCursor = false,
    required super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pic = session.currentPic;
    final prompt = agiEngine?.activeInputPrompt;

    canvas.save();
    canvas.translate(session.shakeOffsetX, session.shakeOffsetY);
    AgiPicturePainter(
      picture: pic,
      actors: buildActors(),
      displayedTexts: agiEngine?.displayedTexts ?? const [],
      textScreenBuffer: agiEngine?.textScreenBuffer,
      isTextScreen: agiEngine?.isTextScreen ?? false,
      textFgColor: agiEngine?.textFgColor ?? 15,
      textBgColor: agiEngine?.textBgColor ?? 0,
      playfieldRow: agiEngine?.playfieldRow ?? 0,
      showCursor: cursorBlink.value && prompt?.row != null,
      cursorRow: prompt?.row,
      cursorCol: prompt?.col ?? 0,
      cursorPromptText: (prompt != null && prompt.row != null)
          ? '${prompt.prompt}${prompt.currentText}'
          : null,
      renderMode: renderMode,
      flatVisualImage: (renderMode == AgiPictureRenderMode.unditheredVisual && pic is SciPic)
          ? pic.cachedUnditheredVisualImage
          : pic?.cachedFlatVisualImage,
      priorityMapImage: pic?.cachedPriorityMapImage,
      controlMapImage: pic?.cachedControlMapImage,
      isolatedPrioritySlice: isolatedPrioritySlice,
      showPixelGrid: showPixelGrid,
      renderBlackTextBackgrounds: renderBlackTextBackgrounds,
      menuManager: agiEngine?.menuManager,
      displayProfile: displayProfile ?? session.displayProfile,
      sciWindows: sciWindows.isNotEmpty ? sciWindows : session.sciWindows,
      mouseCursor: mouseCursor ?? session.mouseCursor,
      mouseCursorPosition: mouseCursorPosition ?? session.mouseCursorPosition,
      showMouseCursor: showMouseCursor || session.showMouseCursor,
    ).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePlayfieldPainter oldDelegate) {
    return oldDelegate.session != session ||
        oldDelegate.agiEngine != agiEngine ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.showPixelGrid != showPixelGrid ||
        oldDelegate.renderBlackTextBackgrounds != renderBlackTextBackgrounds ||
        oldDelegate.isolatedPrioritySlice != isolatedPrioritySlice ||
        oldDelegate.displayProfile != displayProfile ||
        oldDelegate.showMouseCursor != showMouseCursor ||
        oldDelegate.mouseCursor != mouseCursor ||
        (showMouseCursor &&
            oldDelegate.mouseCursorPosition != mouseCursorPosition) ||
        oldDelegate.sciWindows != sciWindows;
  }
}
