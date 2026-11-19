import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Manages loading, caching, and accessing the priority-sprite
/// FragmentProgram (spike prototype, see doc/review_followups.md rank 14).
class PrioritySpriteLoader {
  static ui.FragmentProgram? _program;
  static bool _hasAttemptedLoad = false;
  static bool _isLoading = false;

  /// Cached [ui.FragmentProgram] if successfully loaded, or null.
  static ui.FragmentProgram? get program => _program;

  /// True if the shader is ready to be instantiated as a [ui.FragmentShader].
  static bool get isReady => _program != null;

  /// True if an attempt has been made to load the shader asset.
  static bool get hasAttemptedLoad => _hasAttemptedLoad;

  /// Pre-warms and loads the priority-sprite fragment shader asset.
  static Future<ui.FragmentProgram?> initialize() async {
    if (_program != null) return _program;
    if (_isLoading) return null;

    _isLoading = true;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/priority_sprite.frag');
      if (kDebugMode) {
        debugPrint('Priority sprite FragmentProgram loaded successfully.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Priority sprite FragmentProgram could not be loaded: $e');
      }
      _program = null;
    } finally {
      _hasAttemptedLoad = true;
      _isLoading = false;
    }
    return _program;
  }

  /// Sets or clears the active [ui.FragmentProgram] (useful for testing).
  @visibleForTesting
  static void setProgramForTesting(ui.FragmentProgram? testProgram) {
    _program = testProgram;
    _hasAttemptedLoad = true;
  }

  /// Resets loader state.
  @visibleForTesting
  static void resetForTesting() {
    _program = null;
    _hasAttemptedLoad = false;
    _isLoading = false;
  }
}

/// Draws one sprite rect from [spriteImage] (sampled in [srcRectPx] pixel
/// coordinates) into [dstRect] (playfield coordinates), discarding fragments
/// where the priority image's priority exceeds [actorPriority].
///
/// The canvas must already be transformed so that 1 unit = 1 playfield
/// pixel (e.g. via `canvas.scale(size.width / playfieldWidth,
/// size.height / playfieldHeight)` as `PlayfieldPainter` does).
void drawPrioritySprite(
  Canvas canvas,
  ui.FragmentShader shader, {
  required ui.Image spriteImage,
  required ui.Image priorityImage,
  required Rect srcRectPx,
  required Rect dstRect,
  required Size playfieldSize,
  required int actorPriority,
  bool flipX = false,
}) {
  shader
    ..setFloat(0, dstRect.left)
    ..setFloat(1, dstRect.top)
    ..setFloat(2, dstRect.width)
    ..setFloat(3, dstRect.height)
    ..setFloat(4, srcRectPx.left)
    ..setFloat(5, srcRectPx.top)
    ..setFloat(6, srcRectPx.width)
    ..setFloat(7, srcRectPx.height)
    ..setFloat(8, spriteImage.width.toDouble())
    ..setFloat(9, spriteImage.height.toDouble())
    ..setFloat(10, playfieldSize.width)
    ..setFloat(11, playfieldSize.height)
    ..setFloat(12, actorPriority.toDouble())
    ..setFloat(13, flipX ? 1.0 : 0.0)
    ..setImageSampler(0, spriteImage, filterQuality: ui.FilterQuality.none)
    ..setImageSampler(1, priorityImage, filterQuality: ui.FilterQuality.none);

  // Rasterize a rect expanded by half a playfield pixel with AA off, and
  // let the shader's floored playfield-pixel test decide coverage. A plain
  // drawRect at fractional canvas scales gives edge device pixels partial
  // (AA on) or zero (AA off, center-on-boundary) coverage, which opens a
  // 1px seam along sprite edges; the expansion guarantees every device
  // pixel whose center falls in the sprite's playfield footprint reaches
  // the shader, and fragments in the expanded margin are discarded by the
  // shader's dstRect test. This matches drawImageRect's hard sampling.
  canvas.drawRect(
    dstRect.inflate(0.5),
    Paint()
      ..shader = shader
      ..isAntiAlias = false,
  );
}
