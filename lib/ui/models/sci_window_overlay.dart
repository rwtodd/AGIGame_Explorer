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
  final SierraFont? font;
  final TextAlign align;

  const SciTextControl({
    required super.rect,
    required this.text,
    this.colorPen,
    this.font,
    this.align = TextAlign.left,
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
    final drawPos = windowTopLeft + rect.topLeft;

    if (effectiveFont != null) {
      final lines = text.split('\n');
      var yOffset = drawPos.dy;
      final glyphPaint = Paint()
        ..color = EgaColors.palette[fg.clamp(0, 15)]
        ..style = PaintingStyle.fill;

      for (final line in lines) {
        if (line.isNotEmpty) {
          final lineWidth = effectiveFont.measureTextWidth(line);
          var xOffset = drawPos.dx;
          if (align == TextAlign.center) {
            xOffset += (rect.width - lineWidth) / 2.0;
          } else if (align == TextAlign.right) {
            xOffset += rect.width - lineWidth;
          }

          var currentX = xOffset;
          for (var i = 0; i < line.length; i++) {
            final glyph = effectiveFont.getGlyph(line.codeUnitAt(i));
            if (glyph == null) {
              continue;
            }
            for (var gy = 0; gy < glyph.height; gy++) {
              for (var gx = 0; gx < glyph.width; gx++) {
                if (glyph.isPixelSet(gx, gy)) {
                  canvas.drawRect(
                    Rect.fromLTWH(currentX + gx, yOffset + gy, 1.0, 1.0),
                    glyphPaint,
                  );
                }
              }
            }
            currentX += glyph.width;
          }
        }
        yOffset += effectiveFont.fontHeight + 2.0;
      }
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
      )..layout(maxWidth: rect.width);

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
    final labelControl = SciTextControl(
      rect: Rect.fromLTWH(0, (rect.height - 8.0) / 2.0, rect.width, rect.height),
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
        final pixels = cel.getPixels(parentView: v, celIndex: celNumber);
        final paint = Paint()..filterQuality = FilterQuality.none;

        for (var y = 0; y < cel.height; y++) {
          for (var x = 0; x < cel.width; x++) {
            final colorIdx = pixels[y * cel.width + x] & 0x0F;
            if (colorIdx != cel.transparentColor) {
              paint.color = EgaColors.palette[colorIdx];
              canvas.drawRect(
                Rect.fromLTWH(drawPos.dx + x, drawPos.dy + y, 1.0, 1.0),
                paint,
              );
            }
          }
        }
      }
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
  });

  /// Paints this window frame, title bar, and all child controls to [canvas].
  void paint(Canvas canvas) {
    final penColor = EgaColors.palette[colorPen.clamp(0, 15)];
    final backColor = EgaColors.palette[colorBack.clamp(0, 15)];

    // 1. Optional 2px black drop shadow (authentic Sierra window style)
    if (hasDropShadow) {
      final shadowRect = rect.shift(const Offset(2.0, 2.0));
      final shadowPaint = Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.fill;
      canvas.drawRect(shadowRect, shadowPaint);
    }

    // 2. Window solid background fill
    final bgPaint = Paint()
      ..color = backColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    // 3. Window double border (outer pen border, 1px white inset, inner pen border)
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

    // 4. Title bar (if title provided)
    if (title != null && title!.isNotEmpty) {
      final titleHeight = 11.0;
      final titleBarRect = Rect.fromLTWH(rect.left + 3, rect.top + 3, rect.width - 6, titleHeight);

      // Title bar fill (pen color background for inverted title bar, or backColor)
      final titleBgPaint = Paint()
        ..color = penColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(titleBarRect, titleBgPaint);

      // Title text (inverted color)
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

    // 5. Child controls
    for (final control in controls) {
      control.paint(
        canvas,
        windowTopLeft: rect.topLeft,
        defaultFont: font,
        defaultColorPen: colorPen,
        defaultColorBack: colorBack,
      );
    }
  }
}
