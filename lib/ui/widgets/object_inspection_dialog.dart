import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/object_view_resolver.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/agi_message_formatter.dart';
import 'package:flutter_agigame/ui/widgets/cel_image_widget.dart';

/// Modal dialog for inspecting an individual inventory object (`show.obj` / `show.obj.v`).
///
/// Features:
/// - Pure solid white block with classic Sierra EGA dark red inner border (Color 4: #AA0000).
/// - Subtle modern drop shadow behind the dialog card.
/// - Renders item sprite preview with authentic 2:1 EGA pixel aspect and transparency.
/// - Displays embedded VIEW text description or item name using authentic dialog font scaling.
/// - Formats Sierra AGI message placeholders (%v variables, %s strings, %o object names, escapes).
/// - Dismissible via Enter, Space, Escape, or tapping/clicking anywhere on screen.
/// - Fully transparent backdrop preserving complete visibility of the game screen underneath.
class ObjectInspectionDialog extends StatelessWidget {
  final AgiGameEngine? engine;
  final int objectNumber;
  final AgiObject? object;
  final AgiView? view;
  final String? description;
  final AgiMemory? memory;
  final AgiResourceLoader? loader;
  final VoidCallback? onClose;
  final bool correctAspectRatio;
  final bool strictIntegerScaling;

  const ObjectInspectionDialog({
    super.key,
    this.engine,
    required this.objectNumber,
    this.object,
    this.view,
    this.description,
    this.memory,
    this.loader,
    this.onClose,
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
  });

  /// Formats Sierra AGI message placeholders using standalone [AgiMemory].
  static String formatWithMemory(
    String text,
    AgiMemory memory, {
    AgiResourceLoader? loader,
    List<String> inputWords = const [],
  }) {
    return AgiMessageFormatter.format(
      text,
      memory: memory,
      loader: loader,
      inputWords: inputWords,
    );
  }

  String _formatText(String text) {
    if (engine != null) {
      return engine!.formatMessage(text);
    }
    final effectiveMemory = memory;
    if (effectiveMemory != null) {
      return formatWithMemory(text, effectiveMemory, loader: loader);
    }
    return text;
  }

  AgiObject? _resolveObject() {
    if (object != null) return object;
    if (engine != null) {
      final objects = engine!.objects;
      if (objectNumber >= 0 && objectNumber < objects.length) {
        return objects[objectNumber];
      }
    }
    return null;
  }

  AgiView? _resolveView(AgiObject? resolvedObject) {
    if (view != null) return view;
    final effectiveLoader = loader ?? engine?.resourceLoader;
    if (effectiveLoader == null) return null;

    final viewNum = objectNumber;
    try {
      if (effectiveLoader.presentViewNumbers.contains(viewNum)) {
        return effectiveLoader.loadView(viewNum);
      }
    } catch (_) {}

    // Fallback: If viewNum is an object index, attempt ObjectViewResolver
    final targetObj = resolvedObject ?? const AgiObject(name: '', startingRoom: 0);
    try {
      final fallbackNum = ObjectViewResolver.resolveViewNumber(
        objectIndex: objectNumber,
        object: targetObj,
        loader: effectiveLoader,
      );
      if (effectiveLoader.presentViewNumbers.contains(fallbackNum)) {
        return effectiveLoader.loadView(fallbackNum);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedObj = _resolveObject();
    final resolvedView = _resolveView(resolvedObj);

    final rawName = resolvedObj?.name ??
        (resolvedView?.description != null ? 'OBJECT VIEW' : 'View #$objectNumber');
    final displayName = _formatText(rawName.trim());
    final rawDescription = description ??
        ((resolvedView?.description != null && resolvedView!.description!.trim().isNotEmpty)
            ? resolvedView.description!.trim()
            : null);
    final effectiveDescription = rawDescription != null ? _formatText(rawDescription) : null;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): () => onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.space): () => onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () => onClose?.call(),
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: Container(
            color: Colors.transparent, // Authentic Sierra: no dark screen tint
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

                final fontSize = math.max(11.0, playfieldWidth / 48.0);
                final spriteScale = math.max(1.0, playfieldWidth / 320.0);

                final horizontalPadding = math.max(12.0, playfieldWidth * 0.015);
                final verticalPadding = math.max(10.0, playfieldHeight * 0.014);

                final targetCols = 32;
                final expectedTextWidth = targetCols * (fontSize * 0.54);
                final maxCardWidth = math.max(
                  140.0,
                  math.min(
                    playfieldWidth * 0.85,
                    expectedTextWidth + (horizontalPadding * 2) + 16.0,
                  ),
                );

                final borderWidth = math.max(2.0, (playfieldWidth / 400.0).roundToDouble());
                final shadowOffset = math.max(3.0, playfieldWidth * 0.004);
                final shadowBlur = math.max(4.0, playfieldWidth * 0.007);
                final effectiveMinWidth = math.min(math.max(60.0, playfieldWidth * 0.15), maxCardWidth);

                return Center(
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: effectiveMinWidth,
                      maxWidth: maxCardWidth,
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
                          color: const Color(0x44000000), // Subtle modern drop shadow
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 1. Sprite Preview
                          if (resolvedView != null &&
                              resolvedView.loops.isNotEmpty &&
                              resolvedView.loops[0].cels.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(bottom: verticalPadding),
                              child: CelImageWidget(
                                view: resolvedView,
                                loopIndex: 0,
                                celIndex: 0,
                                scale: spriteScale,
                              ),
                            )
                          else
                            Padding(
                              padding: EdgeInsets.only(bottom: verticalPadding),
                              child: Icon(
                                Icons.inventory_2_outlined,
                                size: fontSize * 2.5,
                                color: const Color(0xFF888888),
                              ),
                            ),

                          // 2. Description or Object Name
                          Text(
                            (effectiveDescription != null && effectiveDescription.isNotEmpty)
                                ? effectiveDescription
                                : displayName,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              letterSpacing: 0.1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
