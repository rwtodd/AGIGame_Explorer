import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

/// Modal / Positional Retro EGA Dialog Box widget modeled after authentic Sierra AGI dialogs.
///
/// Features:
/// - Refined playfield-proportional font sizing (~45-50 characters per screen width, ~30-35 chars per dialog line).
/// - Pure solid white block with classic Sierra EGA dark red inner border (Color 4: #AA0000).
/// - Subtle modern drop shadow behind the dialog card.
/// - Positioning in 40x25 text-grid coordinates when `row` / `col` are specified (`print.at`).
/// - Centered horizontally & vertically when coordinates are omitted (`print`).
/// - Simple dismissal via Enter, Space, Escape, or tapping anywhere on screen.
/// - Fully transparent backdrop preserving complete visibility of the game scene underneath.
class DialogBoxWidget extends StatelessWidget {
  final AgiDialogState dialogState;
  final VoidCallback onDismiss;
  final bool correctAspectRatio;
  final bool strictIntegerScaling;

  const DialogBoxWidget({
    super.key,
    required this.dialogState,
    required this.onDismiss,
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): onDismiss,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): onDismiss,
        const SingleActivator(LogicalKeyboardKey.space): onDismiss,
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dialogState.isModal ? onDismiss : null,
          child: Container(
            color: Colors.transparent, // Authentic Sierra: no screen-wide dark tint
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final availableHeight = constraints.maxHeight;
                if (availableWidth <= 0 || availableHeight <= 0) {
                  return const SizedBox.shrink();
                }

                final targetAspect = correctAspectRatio ? (4.0 / 3.0) : (320.0 / 200.0);
                double playfieldWidth;
                double playfieldHeight;

                if (strictIntegerScaling) {
                  final int baseWidth = 320;
                  final int baseHeight = correctAspectRatio ? 240 : 200;
                  final maxScaleX = availableWidth ~/ baseWidth;
                  final maxScaleY = availableHeight ~/ baseHeight;
                  final scale = math.max(1, math.min(maxScaleX, maxScaleY));
                  playfieldWidth = (baseWidth * scale).toDouble();
                  playfieldHeight = (baseHeight * scale).toDouble();
                } else {
                  final containerAspect = availableWidth / availableHeight;
                  if (containerAspect > targetAspect) {
                    playfieldHeight = availableHeight;
                    playfieldWidth = availableHeight * targetAspect;
                  } else {
                    playfieldWidth = availableWidth;
                    playfieldHeight = availableWidth / targetAspect;
                  }
                }

                final playfieldLeft = (availableWidth - playfieldWidth) / 2.0;
                final playfieldTop = (availableHeight - playfieldHeight) / 2.0;

                // Refined proportional font sizing:
                // Targeting ~48 characters across full playfield width (~18-20px at 960x720)
                // Closely matches the visual height of standard AGI character cells while maintaining crisp modern typography.
                final fontSize = math.max(11.0, playfieldWidth / 48.0);

                final horizontalPadding = math.max(12.0, playfieldWidth * 0.015);
                final verticalPadding = math.max(10.0, playfieldHeight * 0.014);

                // In proportional fonts, average character width is ~0.52 * fontSize.
                // Size the box width to comfortably fit the requested column width (~30-35 characters per line).
                final targetCols = (dialogState.width != null && dialogState.width! > 0)
                    ? dialogState.width!
                    : 32;
                final expectedTextWidth = targetCols * (fontSize * 0.54);
                final maxCardWidth = math.max(
                  60.0,
                  math.min(
                    playfieldWidth * 0.85,
                    expectedTextWidth + (horizontalPadding * 2) + 16.0,
                  ),
                );

                final card = _buildDialogCard(
                  context,
                  maxWidth: maxCardWidth,
                  fontSize: fontSize,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                  playfieldWidth: playfieldWidth,
                  playfieldHeight: playfieldHeight,
                );

                // Position calculation:
                // row: 0..24 on the 40x25 text grid
                // col: 0..39 on the 40x25 text grid
                final row = dialogState.row;
                final col = dialogState.col;

                if (row == null && col == null) {
                  // Standard centered modal dialog (from print / print.v)
                  return Center(child: card);
                }

                // Positional dialog (from print.at / print.at.v)
                // Row mapping: row / 25.0 * playfieldHeight
                // Col mapping: col / 40.0 * playfieldWidth
                final topFraction = (row ?? 6).clamp(0, 23) / 25.0;
                final topPos = playfieldTop + (topFraction * playfieldHeight);

                if (col != null) {
                  final leftFraction = col.clamp(0, 38) / 40.0;
                  final leftPos = playfieldLeft + (leftFraction * playfieldWidth);

                  return Stack(
                    children: [
                      Positioned(
                        top: topPos,
                        left: leftPos,
                        child: card,
                      ),
                    ],
                  );
                } else {
                  // Col is null, so center horizontally at the prescribed row
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: topPos,
                        child: card,
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogCard(
    BuildContext context, {
    required double maxWidth,
    required double fontSize,
    required double horizontalPadding,
    required double verticalPadding,
    required double playfieldWidth,
    required double playfieldHeight,
  }) {
    final borderWidth = math.max(2.0, (playfieldWidth / 400.0).roundToDouble());
    final shadowOffset = math.max(3.0, playfieldWidth * 0.004);
    final shadowBlur = math.max(4.0, playfieldWidth * 0.007);

    final effectiveMinWidth = math.min(math.max(40.0, playfieldWidth * 0.10), maxWidth);

    return Container(
      constraints: BoxConstraints(
        minWidth: effectiveMinWidth,
        maxWidth: maxWidth,
      ),
      margin: EdgeInsets.all(math.max(4.0, playfieldWidth * 0.008)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: Colors.white,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x44000000), // Subtle modern drop-shadow behind the box
            offset: Offset(shadowOffset, shadowOffset),
            blurRadius: shadowBlur,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFAA0000), // Classic Sierra EGA Red (Color 4)
            width: borderWidth,
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Text(
          dialogState.message,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1.35,
            letterSpacing: 0.1,
          ),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }
}
