import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/menu/agi_menu.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/view_texture_atlas.dart';

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
  final int objectNumber;
  final ui.Image? image;
  final Offset position;
  final int viewNumber;
  final int loopNumber;
  final int celNumber;
  final ViewTextureAtlas? atlas;

  const AgiActorSprite({
    required this.priority,
    required this.baselineY,
    this.objectNumber = 0,
    this.image,
    required this.position,
    this.viewNumber = 0,
    this.loopNumber = 0,
    this.celNumber = 0,
    this.atlas,
  });

  /// Draws this sprite cel using the texture atlas or direct ui.Image.
  void draw(Canvas canvas, Paint paint) {
    if (atlas != null && atlas!.containsCel(viewNumber, loopNumber, celNumber) && atlas!.hasImage) {
      atlas!.drawCel(
        canvas,
        viewNumber: viewNumber,
        loopNumber: loopNumber,
        celNumber: celNumber,
        position: position,
        scaleX: 2.0,
        scaleY: 1.0,
        paint: paint,
      );
    } else if (image != null) {
      canvas.drawImage(image!, position, paint);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgiActorSprite &&
        other.priority == priority &&
        other.baselineY == baselineY &&
        other.objectNumber == objectNumber &&
        other.image == image &&
        other.position == position &&
        other.viewNumber == viewNumber &&
        other.loopNumber == loopNumber &&
        other.celNumber == celNumber &&
        other.atlas == atlas;
  }

  @override
  int get hashCode => Object.hash(
        priority,
        baselineY,
        objectNumber,
        image,
        position,
        viewNumber,
        loopNumber,
        celNumber,
        atlas,
      );
}

/// Impeller-optimized CustomPainter that renders AGI backgrounds using the Painter's Algorithm across priority slices.
class AgiPicturePainter extends CustomPainter {
  final AgiPic? picture;
  final List<AgiActorSprite> actors;
  final List<AgiDisplayText> displayedTexts;
  final AgiTextScreenBuffer? textScreenBuffer;
  final bool isTextScreen;
  final int textFgColor;
  final int textBgColor;
  final bool showCursor;
  final int? cursorRow;
  final int? cursorCol;
  final String? cursorPromptText;
  final AgiPictureRenderMode renderMode;
  final ui.Image? flatVisualImage;
  final ui.Image? priorityMapImage;
  final ui.Image? controlMapImage;
  final int? isolatedPrioritySlice;
  final int playfieldRow;
  final bool showPixelGrid;
  final AgiMenuManager? menuManager;

  AgiPicturePainter({
    this.picture,
    this.actors = const [],
    this.displayedTexts = const [],
    this.textScreenBuffer,
    this.isTextScreen = false,
    this.textFgColor = 15,
    this.textBgColor = 0,
    this.playfieldRow = 1,
    this.showCursor = false,
    this.cursorRow,
    this.cursorCol,
    this.cursorPromptText,
    this.renderMode = AgiPictureRenderMode.compositedSlices,
    this.flatVisualImage,
    this.priorityMapImage,
    this.controlMapImage,
    this.isolatedPrioritySlice,
    this.showPixelGrid = false,
    this.menuManager,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;

    final scaleX = size.width / AgiDisplay.renderedWidth;
    final scaleY = size.height / AgiDisplay.renderedHeight;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (isTextScreen) {
      _paintTextScreen(canvas);
      if (showCursor) {
        _paintCursor(canvas);
      }
    } else {
      final pic = picture;
      final effectiveFlat = flatVisualImage ?? pic?.cachedFlatVisualImage;
      final effectivePri = priorityMapImage ?? pic?.cachedPriorityMapImage;
      final effectiveCtrl = controlMapImage ?? pic?.cachedControlMapImage;

      if (isolatedPrioritySlice != null && pic != null) {
        canvas.save();
        canvas.translate(0.0, playfieldRow * 8.0);
        final slice = pic.getSlice(isolatedPrioritySlice!);
        if (slice != null && slice.hasVisiblePixels && slice.cachedUiImage != null) {
          canvas.drawImage(slice.cachedUiImage!, Offset.zero, paint);
        }
        canvas.restore();
      } else if (pic != null) {
        canvas.save();
        canvas.translate(0.0, playfieldRow * 8.0);
        switch (renderMode) {
          case AgiPictureRenderMode.compositedSlices:
            _paintCompositedSlices(canvas, paint, effectiveFlat, pic);
            break;

          case AgiPictureRenderMode.flatVisual:
            if (effectiveFlat != null) {
              canvas.drawImage(effectiveFlat, Offset.zero, paint);
            }
            if (textScreenBuffer != null && textScreenBuffer!.hasContent) {
              canvas.save();
              canvas.translate(0.0, -playfieldRow * 8.0);
              _paintTextBackgroundFills(canvas);
              canvas.restore();
            }
            if (actors.isNotEmpty) {
              for (final actor in actors) {
                actor.draw(canvas, paint);
              }
            }
            if (textScreenBuffer != null && textScreenBuffer!.hasContent) {
              canvas.save();
              canvas.translate(0.0, -playfieldRow * 8.0);
              _paintTextGlyphs(canvas);
              canvas.restore();
            }
            break;

          case AgiPictureRenderMode.priorityMap:
            if (effectivePri != null) {
              canvas.drawImage(effectivePri, Offset.zero, paint);
            }
            break;

          case AgiPictureRenderMode.controlMap:
            if (effectiveFlat != null) {
              final dimPaint = Paint()
                ..filterQuality = FilterQuality.none
                ..color = Colors.white.withValues(alpha: 0.25);
              canvas.drawImage(effectiveFlat, Offset.zero, dimPaint);
            }
            if (effectiveCtrl != null) {
              canvas.drawImage(effectiveCtrl, Offset.zero, paint);
            }
            break;
        }
        canvas.restore();
      }

      if (pic == null && textScreenBuffer != null && textScreenBuffer!.hasContent) {
        _paintTextOverlay(canvas);
      }

      if (showCursor) {
        _paintCursor(canvas);
      }
    }

    if (menuManager != null && menuManager!.isOpen) {
      _paintMenu(canvas, menuManager!);
    }

    if (showPixelGrid) {
      _paintGrid(canvas);
    }

    canvas.restore();
  }

  static final List<TextStyle> _egaStyles = List.generate(
    16,
    (fg) => TextStyle(
      color: EgaColors.palette[fg],
      fontSize: 7.5,
      fontWeight: FontWeight.w600,
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New', 'monospace'],
      height: 1.0,
      letterSpacing: 0.1,
    ),
  );

  static final Map<int, double> _scaleCache = {};
  static final Map<String, TextPainter> _textPainterCache = {};
  static const int _maxCachedPainters = 256;

  static TextStyle _monospaceStyle(int fg, {double fontSize = 7.5}) {
    if (fontSize == 7.5 && fg >= 0 && fg < 16) {
      return _egaStyles[fg];
    }
    return TextStyle(
      color: EgaColors.palette[fg.clamp(0, 15)],
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New', 'monospace'],
      height: 1.0,
      letterSpacing: 0.1,
    );
  }

  static double _measureMonospaceWidth(String text, int fg, {double fontSize = 7.5}) {
    if (text.isEmpty) return 0.0;
    final tp = _getTextPainter(text, fg, fontSize: fontSize);
    return tp.width;
  }

  static double _getHorizontalScale(int fg, {double fontSize = 7.5}) {
    final key = (fg.clamp(0, 15) << 8) | (fontSize * 10).toInt();
    final cached = _scaleCache[key];
    if (cached != null) return cached;

    final sampleWidth = _measureMonospaceWidth('0123456789ABCDEF', fg, fontSize: fontSize);
    final scale = sampleWidth <= 0 ? 1.75 : (8.0 / (sampleWidth / 16.0));
    _scaleCache[key] = scale;
    return scale;
  }

  static TextPainter _getTextPainter(String text, int fg, {double fontSize = 7.5}) {
    final key = '$fg:$fontSize:$text';
    final cached = _textPainterCache[key];
    if (cached != null) return cached;

    if (_textPainterCache.length >= _maxCachedPainters) {
      _textPainterCache.clear();
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: _monospaceStyle(fg, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _textPainterCache[key] = tp;
    return tp;
  }

  void _paintTextRun(Canvas canvas, String text, int startCol, int r, int fg, {double fontSize = 7.5}) {
    if (text.isEmpty) return;
    final textPainter = _getTextPainter(text, fg, fontSize: fontSize);
    final sx = _getHorizontalScale(fg, fontSize: fontSize);
    final yOffset = r * 8.0 + ((8.0 - textPainter.height) / 2.0).clamp(0.0, 4.0);

    canvas.save();
    canvas.translate(startCol * 8.0, yOffset);
    canvas.scale(sx, 1.0);
    textPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _paintCursor(Canvas canvas) {
    if (!showCursor || cursorRow == null) return;
    if (cursorRow! < 0 || cursorRow! >= AgiTextScreenBuffer.rows) return;

    double cursorX;
    if (cursorPromptText != null) {
      final promptOffset = (cursorCol ?? 0) * 8.0;
      cursorX = promptOffset + (cursorPromptText!.length * 8.0);
    } else if (cursorCol != null) {
      cursorX = cursorCol! * 8.0;
    } else {
      return;
    }

    final cursorPaint = Paint()
      ..color = EgaColors.palette[textFgColor.clamp(0, 15)]
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(cursorX, cursorRow! * 8.0 + 6.5, 8.0, 1.5),
      cursorPaint,
    );
  }

  void _paintTextScreen(Canvas canvas) {
    // Fill text screen background with EGA color
    final bgPaint = Paint()
      ..color = EgaColors.palette[textBgColor.clamp(0, 15)]
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(0.0, 0.0, 320.0, 200.0),
      bgPaint,
    );

    if (textScreenBuffer == null) return;

    for (int r = 0; r < AgiTextScreenBuffer.rows; r++) {
      int c = 0;
      while (c < AgiTextScreenBuffer.columns) {
        final cell = textScreenBuffer!.getCell(r, c);
        if (cell.isBlank && cell.bg == textBgColor) {
          c++;
          continue;
        }

        final startCol = c;
        final fg = cell.fg;
        final bg = cell.bg;
        final sb = StringBuffer();

        while (c < AgiTextScreenBuffer.columns) {
          final nextCell = textScreenBuffer!.getCell(r, c);
          if (nextCell.fg != fg || nextCell.bg != bg) {
            break;
          }
          sb.write(nextCell.char);
          c++;
        }

        final runText = sb.toString();
        final textTrimmed = runText.trimRight();

        if (bg != textBgColor) {
          final cellBgPaint = Paint()
            ..color = EgaColors.palette[bg.clamp(0, 15)]
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromLTWH(startCol * 8.0, r * 8.0, (c - startCol) * 8.0, 8.0),
            cellBgPaint,
          );
        }

        if (textTrimmed.isNotEmpty) {
          _paintTextRun(canvas, textTrimmed, startCol, r, fg);
        }
      }
    }
  }

  void _paintTextOverlay(Canvas canvas) {
    _paintTextBackgroundFills(canvas);
    _paintTextGlyphs(canvas);
  }

  void _paintTextBackgroundFills(Canvas canvas) {
    if (textScreenBuffer == null) return;

    for (int r = 0; r < AgiTextScreenBuffer.rows; r++) {
      int c = 0;
      while (c < AgiTextScreenBuffer.columns) {
        final cell = textScreenBuffer!.getCell(r, c);
        if (cell.bg == 0) {
          c++;
          continue;
        }

        final startCol = c;
        final bg = cell.bg;

        while (c < AgiTextScreenBuffer.columns) {
          final nextCell = textScreenBuffer!.getCell(r, c);
          if (nextCell.bg != bg) {
            break;
          }
          c++;
        }

        final cellBgPaint = Paint()
          ..color = EgaColors.palette[bg.clamp(0, 15)]
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(startCol * 8.0, r * 8.0, (c - startCol) * 8.0, 8.0),
          cellBgPaint,
        );
      }
    }
  }

  void _paintTextGlyphs(Canvas canvas) {
    if (textScreenBuffer == null) return;

    for (int r = 0; r < AgiTextScreenBuffer.rows; r++) {
      int c = 0;
      while (c < AgiTextScreenBuffer.columns) {
        final cell = textScreenBuffer!.getCell(r, c);
        if (cell.isBlank) {
          c++;
          continue;
        }

        final startCol = c;
        final fg = cell.fg;
        final sb = StringBuffer();

        while (c < AgiTextScreenBuffer.columns) {
          final nextCell = textScreenBuffer!.getCell(r, c);
          if (nextCell.fg != fg || nextCell.isBlank) {
            break;
          }
          sb.write(nextCell.char);
          c++;
        }

        final runText = sb.toString();
        final textTrimmed = runText.trimRight();

        if (textTrimmed.isNotEmpty) {
          _paintTextRun(canvas, textTrimmed, startCol, r, fg);
        }
      }
    }
  }

  void _paintCompositedSlices(Canvas canvas, Paint paint, ui.Image? fallbackFlat, AgiPic pic) {
    // Check if we have valid slices ready
    final hasSlices = pic.slices.values.any((s) => s.hasVisiblePixels && s.cachedUiImage != null);

    if (!hasSlices && fallbackFlat != null) {
      canvas.drawImage(fallbackFlat, Offset.zero, paint);
      if (textScreenBuffer != null && textScreenBuffer!.hasContent) {
        canvas.save();
        canvas.translate(0.0, -playfieldRow * 8.0);
        _paintTextBackgroundFills(canvas);
        canvas.restore();
      }
      if (actors.isNotEmpty) {
        final sortedActors = List<AgiActorSprite>.from(actors)
          ..sort((a, b) {
            final cmp = a.priority.compareTo(b.priority);
            if (cmp != 0) return cmp;
            final cmpY = a.baselineY.compareTo(b.baselineY);
            if (cmpY != 0) return cmpY;
            return a.objectNumber.compareTo(b.objectNumber);
          });
        for (final actor in sortedActors) {
          actor.draw(canvas, paint);
        }
      }
      if (textScreenBuffer != null && textScreenBuffer!.hasContent) {
        canvas.save();
        canvas.translate(0.0, -playfieldRow * 8.0);
        _paintTextGlyphs(canvas);
        canvas.restore();
      }
      return;
    }

    // Pre-bucket actors by priority (0..15) once to eliminate 16 allocations/sorts per frame
    final priorityBuckets = List<List<AgiActorSprite>>.generate(16, (_) => <AgiActorSprite>[]);
    for (final actor in actors) {
      final pri = actor.priority.clamp(0, 15);
      priorityBuckets[pri].add(actor);
    }
    for (int p = 0; p <= 15; p++) {
      final bucket = priorityBuckets[p];
      if (bucket.length > 1) {
        bucket.sort((a, b) {
          final cmp = a.baselineY.compareTo(b.baselineY);
          if (cmp != 0) return cmp;
          return a.objectNumber.compareTo(b.objectNumber);
        });
      }
    }

    // Interleave priority slices (0..15) with actor sprites in authentic Painter's Algorithm order.
    // In AGI, priority 4 is furthest background (horizon) and 15 is closest foreground overlay.
    for (int p = 0; p <= 15; p++) {
      final slice = pic.getSlice(p);
      if (slice != null && slice.hasVisiblePixels && slice.cachedUiImage != null) {
        canvas.drawImage(slice.cachedUiImage!, Offset.zero, paint);
      }

      // Draw background text fills (e.g. solid white newspaper backdrop from clear.text.rect)
      // on the base playfield layer (priority 4) before actors are composited.
      if (p == 4 && textScreenBuffer != null && textScreenBuffer!.hasContent) {
        canvas.save();
        canvas.translate(0.0, -playfieldRow * 8.0);
        _paintTextBackgroundFills(canvas);
        canvas.restore();
      }

      final bandActors = priorityBuckets[p];
      for (final actor in bandActors) {
        actor.draw(canvas, paint);
      }
    }

    // Text glyphs (status line, input prompt, and display() text) float on top of all picture slices and actors
    if (textScreenBuffer != null && textScreenBuffer!.hasContent) {
      canvas.save();
      canvas.translate(0.0, -playfieldRow * 8.0);
      _paintTextGlyphs(canvas);
      canvas.restore();
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

  void _paintMenu(Canvas canvas, AgiMenuManager menuMgr) {
    // 1. Menu Bar Header across top line (Row 0: 320x8 pixels)
    final barBgPaint = Paint()
      ..color = EgaColors.palette[15] // White background
      ..style = PaintingStyle.fill;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 320.0, 8.0), barBgPaint);

    for (int i = 0; i < menuMgr.menus.length; i++) {
      final m = menuMgr.menus[i];
      final isSelected = i == menuMgr.activeMenuIndex;

      if (isSelected) {
        // Highlighted active menu category (Inverted black bar)
        final selBgPaint = Paint()
          ..color = EgaColors.palette[0]
          ..style = PaintingStyle.fill;
        final startX = (m.column - 0.5) * 8.0;
        final width = (m.name.length + 1) * 8.0;
        canvas.drawRect(Rect.fromLTWH(startX, 0, width, 8.0), selBgPaint);
        _paintTextRun(canvas, m.name, m.column, 0, 15);
      } else {
        _paintTextRun(canvas, m.name, m.column, 0, 0);
      }
    }

    // 2. Dropdown popup box for the currently active menu category
    final activeMenu = menuMgr.activeMenu;
    if (activeMenu != null && activeMenu.items.isNotEmpty) {
      final maxLen = max(activeMenu.maxItemTextLength, 10);
      final col = activeMenu.items.first.column;
      final boxWidth = (maxLen + 2) * 8.0;
      final boxHeight = (activeMenu.items.length + 1) * 8.0;
      final left = ((col - 1) * 8.0).clamp(0.0, 320.0 - boxWidth);
      const top = 8.0;

      // Dropdown Box Background
      final boxBgPaint = Paint()
        ..color = EgaColors.palette[15]
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(left, top, boxWidth, boxHeight), boxBgPaint);

      // Dropdown Box Outer Frame
      final borderPaint = Paint()
        ..color = EgaColors.palette[0]
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(Rect.fromLTWH(left, top, boxWidth, boxHeight), borderPaint);

      // Draw Menu Items
      for (int idx = 0; idx < activeMenu.items.length; idx++) {
        final item = activeMenu.items[idx];
        final itemY = top + (idx + 0.5) * 8.0;

        if (item.isSeparator) {
          final sepPaint = Paint()
            ..color = EgaColors.palette[8]
            ..strokeWidth = 1.0;
          canvas.drawLine(
            Offset(left + 4.0, itemY + 3.5),
            Offset(left + boxWidth - 4.0, itemY + 3.5),
            sepPaint,
          );
        } else if (idx == activeMenu.selectedItemIndex) {
          // Highlight selected item
          final selItemBgPaint = Paint()
            ..color = EgaColors.palette[0]
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromLTWH(left + 2.0, top + idx * 8.0 + 2.0, boxWidth - 4.0, 8.0),
            selItemBgPaint,
          );

          // Draw item text in white
          final itemTextPainter = _getTextPainter(item.text, 15);
          final sx = _getHorizontalScale(15);
          canvas.save();
          canvas.translate(left + 8.0, top + idx * 8.0 + 2.0);
          canvas.scale(sx, 1.0);
          itemTextPainter.paint(canvas, Offset.zero);
          canvas.restore();
        } else {
          final fgColor = item.isEnabled ? 0 : 8;
          final itemTextPainter = _getTextPainter(item.text, fgColor);
          final sx = _getHorizontalScale(fgColor);
          canvas.save();
          canvas.translate(left + 8.0, top + idx * 8.0 + 2.0);
          canvas.scale(sx, 1.0);
          itemTextPainter.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AgiPicturePainter oldDelegate) {
    if (oldDelegate.picture != picture ||
        oldDelegate.renderMode != renderMode ||
        oldDelegate.isTextScreen != isTextScreen ||
        oldDelegate.textBgColor != textBgColor ||
        oldDelegate.textScreenBuffer != textScreenBuffer ||
        oldDelegate.displayedTexts != displayedTexts ||
        oldDelegate.flatVisualImage != flatVisualImage ||
        oldDelegate.priorityMapImage != priorityMapImage ||
        oldDelegate.controlMapImage != controlMapImage ||
        oldDelegate.picture?.cachedFlatVisualImage != picture?.cachedFlatVisualImage ||
        oldDelegate.picture?.cachedPriorityMapImage != picture?.cachedPriorityMapImage ||
        oldDelegate.picture?.cachedControlMapImage != picture?.cachedControlMapImage ||
        oldDelegate.showCursor != showCursor ||
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.cursorPromptText != cursorPromptText ||
        oldDelegate.playfieldRow != playfieldRow ||
        oldDelegate.isolatedPrioritySlice != isolatedPrioritySlice ||
        oldDelegate.showPixelGrid != showPixelGrid ||
        oldDelegate.menuManager?.isOpen != menuManager?.isOpen ||
        oldDelegate.menuManager?.activeMenuIndex != menuManager?.activeMenuIndex ||
        oldDelegate.menuManager?.activeMenu?.selectedItemIndex != menuManager?.activeMenu?.selectedItemIndex) {
      return true;
    }

    if (oldDelegate.actors.length != actors.length) return true;
    for (int i = 0; i < actors.length; i++) {
      if (oldDelegate.actors[i] != actors[i]) return true;
    }

    return false;
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
    final priFuture = pic.toPriorityMapUiImage();
    final ctrlFuture = pic.toControlMapUiImage();
    final slicesFuture = pic.preloadGpuTextures();

    if (slicesFuture is Future) {
      await slicesFuture;
    }
    final results = await Future.wait([flatFuture, priFuture, ctrlFuture]);

    if (!mounted || token != _loadToken) return;

    setState(() {
      _displayedPic = pic;
      _flatImage = results[0];
      _priImage = results[1];
      _ctrlImage = results[2];
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
        _priImage ??= await targetPic.toPriorityMapUiImage();
        break;
      case AgiPictureRenderMode.controlMap:
        _ctrlImage ??= await targetPic.toControlMapUiImage();
        break;
    }
    if (mounted) {
      setState(() {});
    }
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
