import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Manages loading, caching, and accessing the hardware CRT FragmentProgram.
class CrtShaderLoader {
  static ui.FragmentProgram? _program;
  static bool _hasAttemptedLoad = false;
  static bool _isLoading = false;

  /// Cached [ui.FragmentProgram] if successfully loaded, or null if uninitialized/unsupported.
  static ui.FragmentProgram? get program => _program;

  /// True if the shader is ready to be instantiated as a [ui.FragmentShader].
  static bool get isReady => _program != null;

  /// True if an attempt has been made to load the shader asset.
  static bool get hasAttemptedLoad => _hasAttemptedLoad;

  /// Pre-warms and loads the CRT fragment shader asset.
  static Future<ui.FragmentProgram?> initialize() async {
    if (_program != null) return _program;
    if (_isLoading) return null;

    _isLoading = true;
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/crt_effect.frag');
      if (kDebugMode) {
        debugPrint('CRT FragmentProgram loaded successfully.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CRT FragmentProgram could not be loaded (falling back to CPU painter): $e');
      }
      _program = null;
    } finally {
      _hasAttemptedLoad = true;
      _isLoading = false;
    }
    return _program;
  }

  /// Sets or clears the active [ui.FragmentProgram] (useful for testing and dependency injection).
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
