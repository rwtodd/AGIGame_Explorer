import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/domain/sierra_view.dart';

/// Base class for UI controls rendered within an authentic SCI window overlay.
abstract class SciControlItem {
  final Rect rect;

  const SciControlItem({required this.rect});

  /// Paints the control inside [canvas] relative to [windowTopLeft].
  void paint(
    Canvas canvas, {
    required Offset windowTopLeft,
    SierraFont? defaultFont,
    int defaultColorPen = 0,
    int defaultColorBack = 15,
  });
}

/// Text label control for displaying static text or messages in an SCI window.
class SciTextControl extends SciControlItem {
  final String text;
  final int? colorPen;
  final int? colorBack;
  final SierraFont? font;
  final TextAlign align;

  const SciTextControl({
    required super.rect,
    required this.text,
    this.colorPen,
    this.colorBack,
    this.font,
    this.align = TextAlign.left,
  });

  /// Word wraps [text] against [maxWidth] using Sierra font metrics.
  static List<String> wrapText(String text, SierraFont? font, int maxWidth) {
    if (text.isEmpty) return const [''];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (maxWidth <= 0) return normalized.split('\n');

    final paragraphs = normalized.split('\n');
    final resultLines = <String>[];

    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        resultLines.add('');
        continue;
      }
      final words = paragraph.split(' ');
      var currentLine = StringBuffer();
      var currentWidth = 0;

      for (var i = 0; i < words.length; i++) {
        final word = words[i];
        if (word.isEmpty) {
          if (currentLine.isNotEmpty) {
            currentLine.write(' ');
            currentWidth += font != null ? font.measureTextWidth(' ') : 8;
          }
          continue;
        }
        final wordWidth = font != null ? font.measureTextWidth(word) : word.length * 8;
        final spaceWidth = font != null ? font.measureTextWidth(' ') : 8;

        if (currentLine.isEmpty) {
          if (wordWidth <= maxWidth) {
            currentLine.write(word);
            currentWidth = wordWidth;
          } else {
            // Giant word longer than maxWidth: break by character
            for (var c = 0; c < word.length; c++) {
              final charStr = word[c];
              final charW = font != null ? font.measureTextWidth(charStr) : 8;
              if (currentWidth + charW <= maxWidth || currentLine.isEmpty) {
                currentLine.write(charStr);
                currentWidth += charW;
              } else {
                resultLines.add(currentLine.toString());
                currentLine = StringBuffer(charStr);
                currentWidth = charW;
              }
            }
          }
        } else {
          if (currentWidth + spaceWidth + wordWidth <= maxWidth) {
            currentLine.write(' ');
            currentLine.write(word);
            currentWidth += spaceWidth + wordWidth;
          } else {
            resultLines.add(currentLine.toString());
            if (wordWidth <= maxWidth) {
              currentLine = StringBuffer(word);
              currentWidth = wordWidth;
            } else {
              currentLine = StringBuffer();
              currentWidth = 0;
              for (var c = 0; c < word.length; c++) {
                final charStr = word[c];
                final charW = font != null ? font.measureTextWidth(charStr) : 8;
                if (currentWidth + charW <= maxWidth || currentLine.isEmpty) {
                  currentLine.write(charStr);
                  currentWidth += charW;
                } else {
                  resultLines.add(currentLine.toString());
                  currentLine = StringBuffer(charStr);
                  currentWidth = charW;
                }
              }
            }
          }
        }
      }
      if (currentLine.isNotEmpty) {
        resultLines.add(currentLine.toString());
      }
    }

    return resultLines.isNotEmpty ? resultLines : const [''];
  }

  static final Map<String, ui.Picture> _pictureCache = {};

  static ui.Picture pictureFor({
    required SierraFont font,
    required List<String> lines,
    required Color color,
    required double boxWidth,
    required TextAlign align,
  }) {
    final key = '${identityHashCode(font)}|$color|${boxWidth.toInt()}|$align|${lines.join('\n')}';
    final cached = _pictureCache[key];
    if (cached != null) return cached;
    if (_pictureCache.length > 64) _pictureCache.clear();

    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final glyphPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    var yOffset = 0.0;
    for (final line in lines) {
      if (line.isNotEmpty) {
        final lineWidth = font.measureTextWidth(line);
        var xOffset = 0.0;
        if (align == TextAlign.center) {
          xOffset = (boxWidth - lineWidth) / 2.0;
        } else if (align == TextAlign.right) {
          xOffset = boxWidth - lineWidth;
        }
        var currentX = xOffset;
        for (var i = 0; i < line.length; i++) {
          final glyph = font.getGlyph(line.codeUnitAt(i));
          if (glyph == null) continue;
          for (var gy = 0; gy < glyph.height; gy++) {
            for (var gx = 0; gx < glyph.width; gx++) {
              if (glyph.isPixelSet(gx, gy)) {
                c.drawRect(
                  Rect.fromLTWH(currentX + gx, yOffset + gy, 1.0, 1.0),
                  glyphPaint,
                );
              }
            }
          }
          currentX += glyph.width;
        }
      }
      yOffset += font.fontHeight;
    }
    final picture = rec.endRecording();
    _pictureCache[key] = picture;
    return picture;
  }

  @override
  void paint(
    Canvas canvas, {
    required Offset windowTopLeft,
    SierraFont? defaultFont,
    int defaultColorPen = 0,
    int defaultColorBack = 15,
  }) {
    final effectiveFont = font ?? defaultFont;
    final fg = colorPen ?? defaultColorPen;
    final drawPos = windowTopLeft + rect.topLeft;

    if (colorBack != null) {
      final bgPaint = Paint()
        ..color = EgaColors.palette[colorBack!.clamp(0, 15)]
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect.shift(windowTopLeft), bgPaint);
    }

    if (effectiveFont != null) {
      final wrapWidth = rect.width >= 16 ? rect.width.toInt() : 192;
      final lines = wrapText(text, effectiveFont, wrapWidth);
      final picture = pictureFor(
        font: effectiveFont,
        lines: lines,
        color: EgaColors.palette[fg.clamp(0, 15)],
        boxWidth: rect.width,
        align: align,
      );
      canvas.save();
      canvas.translate(drawPos.dx, drawPos.dy);
      canvas.drawPicture(picture);
      canvas.restore();
    } else {
      // Fallback text rendering if no font resource is attached
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: EgaColors.palette[fg.clamp(0, 15)],
            fontSize: 9,
            fontFamily: 'Courier',
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width > 0 ? rect.width : 192);

      textPainter.paint(canvas, drawPos);
      textPainter.dispose();
    }
  }
}

/// Push button control for interactive buttons (e.g. "OK", "Cancel", "Restart").
class SciButtonControl extends SciControlItem {
  final String text;
  final bool isPressed;
  final bool isFocused;
  final int? colorPen;
  final int? colorBack;
  final SierraFont? font;

  const SciButtonControl({
    required super.rect,
    required this.text,
    this.isPressed = false,
    this.isFocused = false,
    this.colorPen,
    this.colorBack,
    this.font,
  });

  @override
  void paint(
    Canvas canvas, {
    required Offset windowTopLeft,
    SierraFont? defaultFont,
    int defaultColorPen = 0,
    int defaultColorBack = 15,
  }) {
    final effectivePen = colorPen ?? defaultColorPen;
    final effectiveBack = colorBack ?? defaultColorBack;
    final btnRect = rect.shift(windowTopLeft);

    // Button background
    final bgPaint = Paint()
      ..color = EgaColors.palette[effectiveBack.clamp(0, 15)]
      ..style = PaintingStyle.fill;
    canvas.drawRect(btnRect, bgPaint);

    // Button bevel borders (Sierra 3D look)
    final borderPaint = Paint()
      ..color = EgaColors.palette[effectivePen.clamp(0, 15)]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(btnRect, borderPaint);

    if (isFocused) {
      final focusPaint = Paint()
        ..color = EgaColors.palette[0] // Black inner dashed focus
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(btnRect.deflate(2.0), focusPaint);
    }

    // Centered label text
    final btnFontH = (font ?? defaultFont)?.fontHeight.toDouble() ?? 8.0;
    final labelControl = SciTextControl(
      rect: Rect.fromLTWH(0, (rect.height - btnFontH) / 2.0, rect.width, rect.height),
      text: text,
      colorPen: effectivePen,
      font: font ?? defaultFont,
      align: TextAlign.center,
    );
    labelControl.paint(
      canvas,
      windowTopLeft: btnRect.topLeft,
      defaultFont: defaultFont,
      defaultColorPen: defaultColorPen,
    );
  }
}

/// Icon / View cel control (e.g. inventory item preview, warning badge).
class SciIconControl extends SciControlItem {
  final SierraView? view;
  final int loopNumber;
  final int celNumber;
  final ui.Image? directImage;

  const SciIconControl({
    required super.rect,
    this.view,
    this.loopNumber = 0,
    this.celNumber = 0,
    this.directImage,
  });

  static final Map<String, ui.Picture> _iconCache = {};

  static ui.Picture _iconPicture(
    SierraView v,
    SierraViewCel cel,
    int loopNumber,
    int celNumber,
  ) {
    final key = '${identityHashCode(v)}|$loopNumber|$celNumber';
    final cached = _iconCache[key];
    if (cached != null) return cached;
    if (_iconCache.length > 64) _iconCache.clear();

    final pixels = cel.getPixels(parentView: v, celIndex: celNumber);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final paint = Paint()..filterQuality = FilterQuality.none;
    for (var y = 0; y < cel.height; y++) {
      for (var x = 0; x < cel.width; x++) {
        final colorIdx = pixels[y * cel.width + x] & 0x0F;
        if (colorIdx == cel.transparentColor) continue;
        paint.color = EgaColors.palette[colorIdx];
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0), paint);
      }
    }
    final picture = rec.endRecording();
    _iconCache[key] = picture;
    return picture;
  }

  @override
  void paint(
    Canvas canvas, {
    required Offset windowTopLeft,
    SierraFont? defaultFont,
    int defaultColorPen = 0,
    int defaultColorBack = 15,
  }) {
    final drawPos = windowTopLeft + rect.topLeft;
    if (directImage != null) {
      canvas.drawImage(directImage!, drawPos, Paint()..filterQuality = FilterQuality.none);
      return;
    }

    final v = view;
    if (v != null) {
      final cel = v.getCel(loopNumber, celNumber);
      if (cel != null) {
        final picture = _iconPicture(v, cel, loopNumber, celNumber);
        canvas.save();
        canvas.translate(drawPos.dx, drawPos.dy);
        canvas.drawPicture(picture);
        canvas.restore();
      }
    }
  }
}

/// Single-line editable text control (e.g. filename prompt, save game description).
class SciEditControl extends SciControlItem {
  final String text;
  final int cursorPosition;
  final int maxChars;
  final int? colorPen;
  final int? colorBack;
  final SierraFont? font;
  final bool isFocused;

  const SciEditControl({
    required super.rect,
    required this.text,
    this.cursorPosition = 0,
    this.maxChars = 40,
    this.colorPen,
    this.colorBack,
    this.font,
    this.isFocused = true,
  });

  @override
  void paint(
    Canvas canvas, {
    required Offset windowTopLeft,
    SierraFont? defaultFont,
    int defaultColorPen = 0,
    int defaultColorBack = 15,
  }) {
    final effectiveFont = font ?? defaultFont;
    final fg = colorPen ?? defaultColorPen;
    final bg = colorBack ?? defaultColorBack;
    final editRect = rect.shift(windowTopLeft);
    final frameRect = editRect.inflate(1.0);

    // Box background
    final bgPaint = Paint()
      ..color = EgaColors.palette[bg.clamp(0, 15)]
      ..style = PaintingStyle.fill;
    canvas.drawRect(frameRect, bgPaint);

    // Box border (1px outer frame around text area)
    final borderPaint = Paint()
      ..color = EgaColors.palette[fg.clamp(0, 15)]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(frameRect, borderPaint);

    final textPos = editRect.topLeft + const Offset(1.0, 0.0);

    if (effectiveFont != null) {
      final picture = SciTextControl.pictureFor(
        font: effectiveFont,
        lines: [text],
        color: EgaColors.palette[fg.clamp(0, 15)],
        boxWidth: rect.width,
        align: TextAlign.left,
      );
      canvas.save();
      canvas.translate(textPos.dx, textPos.dy);
      canvas.drawPicture(picture);
      canvas.restore();

      var cursorX = textPos.dx;
      final prefix = cursorPosition <= text.length
          ? text.substring(0, cursorPosition.clamp(0, text.length))
          : text;
      cursorX += effectiveFont.measureTextWidth(prefix).toDouble();

      if (isFocused) {
        final cursorPaint = Paint()
          ..color = EgaColors.palette[fg.clamp(0, 15)]
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(cursorX, editRect.top + effectiveFont.fontHeight - 1.0, 6.0, 1.0),
          cursorPaint,
        );
      }
    } else {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: EgaColors.palette[fg.clamp(0, 15)],
            fontSize: 9,
            fontFamily: 'Courier',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: editRect.width - 4.0);
      textPainter.paint(canvas, textPos);
      textPainter.dispose();
    }
  }
}

/// Active modal or modeless SCI Window Overlay (`kNewWindow`, `kDrawControl`).
///
/// In authentic Sierra SCI, dialog windows were drawn into the visual buffer and
/// restored with `kSaveBits`/`kRestoreBits`. In our engine, windows and dialogs
/// are rendered as an independent **top-level overlay pass** on top of the 16
/// composited priority depth slices, eliminating expensive GPU slice invalidation
/// and re-slicing on every dialog interaction.
class SciWindowOverlay {
  /// Window / port identifier.
  final int id;

  /// Bounding rectangle in 320x200 screen coordinate space.
  final Rect rect;

  /// Optional window title rendered at the top of the window frame.
  final String? title;

  /// Foreground EGA color (borders, title, default text: 0..15, default 0 black).
  final int colorPen;

  /// Background EGA fill color (0..15, default 15 white).
  final int colorBack;

  /// Z-depth priority of this window overlay (higher sorts in front, default 15).
  final int priority;

  /// Active bitmap font for text controls within this window.
  final SierraFont? font;

  /// Whether this window has an authentic drop shadow (bottom-right 2px).
  final bool hasDropShadow;

  /// Child controls (labels, buttons, icons) inside the window.
  final List<SciControlItem> controls;

  /// When false, only child controls are painted (kDisplay on the pic port).
  final bool showChrome;

  /// When false, skip the double border and drop shadow (`NOFRAME`).
  final bool showFrame;

  /// Inner-port origin relative to [rect] (title/frame inset).
  final Offset contentOffset;

  const SciWindowOverlay({
    required this.id,
    required this.rect,
    this.title,
    this.colorPen = 0,
    this.colorBack = 15,
    this.priority = 15,
    this.font,
    this.hasDropShadow = true,
    this.controls = const [],
    this.showChrome = true,
    this.showFrame = true,
    this.contentOffset = Offset.zero,
  });

  SciWindowOverlay copyWith({
    int? id,
    Rect? rect,
    String? title,
    int? colorPen,
    int? colorBack,
    int? priority,
    SierraFont? font,
    bool? hasDropShadow,
    List<SciControlItem>? controls,
    bool? showChrome,
    bool? showFrame,
    Offset? contentOffset,
  }) {
    return SciWindowOverlay(
      id: id ?? this.id,
      rect: rect ?? this.rect,
      title: title ?? this.title,
      colorPen: colorPen ?? this.colorPen,
      colorBack: colorBack ?? this.colorBack,
      priority: priority ?? this.priority,
      font: font ?? this.font,
      hasDropShadow: hasDropShadow ?? this.hasDropShadow,
      controls: controls ?? this.controls,
      showChrome: showChrome ?? this.showChrome,
      showFrame: showFrame ?? this.showFrame,
      contentOffset: contentOffset ?? this.contentOffset,
    );
  }

  /// Paints this window frame, title bar, and all child controls to [canvas].
  void paint(Canvas canvas) {
    final penColor = EgaColors.palette[colorPen.clamp(0, 15)];
    final backColor = EgaColors.palette[colorBack.clamp(0, 15)];

    if (!showChrome) {
      final origin = rect.topLeft + contentOffset;
      for (final control in controls) {
        control.paint(
          canvas,
          windowTopLeft: origin,
          defaultFont: font,
          defaultColorPen: colorPen,
          defaultColorBack: colorBack,
        );
      }
      return;
    }

    if (hasDropShadow && showFrame) {
      final shadowRect = rect.shift(const Offset(2.0, 2.0));
      final shadowPaint = Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.fill;
      canvas.drawRect(shadowRect, shadowPaint);
    }

    final bgPaint = Paint()
      ..color = backColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    if (showFrame) {
      final outerBorderPaint = Paint()
        ..color = penColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(rect, outerBorderPaint);

      if (rect.width > 6 && rect.height > 6) {
        final innerBorderPaint = Paint()
          ..color = penColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRect(rect.deflate(2.0), innerBorderPaint);
      }
    }

    if (title != null && title!.isNotEmpty) {
      final titleHeight = 10.0;
      final titleBarRect = Rect.fromLTWH(rect.left + 3, rect.top + 3, rect.width - 6, titleHeight);
      final titleBgPaint = Paint()
        ..color = penColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(titleBarRect, titleBgPaint);

      if (font != null) {
        final picture = SciTextControl.pictureFor(
          font: font!,
          lines: [title!],
          color: backColor,
          boxWidth: titleBarRect.width,
          align: TextAlign.center,
        );
        canvas.save();
        canvas.translate(titleBarRect.left, titleBarRect.top);
        canvas.drawPicture(picture);
        canvas.restore();
      } else {
        final titleTextPainter = TextPainter(
          text: TextSpan(
            text: title,
            style: TextStyle(
              color: backColor,
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: titleBarRect.width);
        final titleX = titleBarRect.left + (titleBarRect.width - titleTextPainter.width) / 2.0;
        final titleY = titleBarRect.top + (titleBarRect.height - titleTextPainter.height) / 2.0;
        titleTextPainter.paint(canvas, Offset(titleX, titleY));
        titleTextPainter.dispose();
      }
    }

    final origin = rect.topLeft + contentOffset;
    for (final control in controls) {
      control.paint(
        canvas,
        windowTopLeft: origin,
        defaultFont: font,
        defaultColorPen: colorPen,
        defaultColorBack: colorBack,
      );
    }
  }
}
