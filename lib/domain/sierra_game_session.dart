import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Unified game session facade representing an active Sierra game engine (AGI or SCI).
///
/// Implemented by both [AgiGameEngine] and [SciGameEngine].
abstract class SierraGameSession implements Listenable {
  /// Display resolution, viewport geometry, and priority slicing profile.
  DisplayProfile get displayProfile;

  /// Currently loaded room/scene background picture, if any.
  SierraPicture? get currentPic;

  /// Composited depth slices for the active background picture.
  Map<int, PictureSlice>? get pictureSlices;

  /// Sprites currently rendered on the playfield.
  List<PlayfieldActorSprite> get actors;

  /// Active SCI window overlays (dialogs, menus, text boxes), if any.
  List<SciWindowOverlay> get sciWindows => const [];

  /// In-game mouse cursor, if enabled.
  SierraCursor? get mouseCursor => null;

  /// Mouse cursor position in 320x200 playfield space.
  ui.Offset? get mouseCursorPosition => null;

  /// Whether to render the in-game mouse cursor.
  bool get showMouseCursor => false;

  /// Title or status text shown in the top bar.
  String get statusLine;

  /// Input prompt label, if input prompt is active.
  String get promptLine => '';

  /// Whether the game is currently paused.
  bool get isPaused;

  /// Whether player text input is enabled.
  bool get isInputEnabled => true;

  /// Horizontal camera / shake offset.
  double get shakeOffsetX => 0.0;

  /// Vertical camera / shake offset.
  double get shakeOffsetY => 0.0;

  /// Game execution cycle speed in Hertz (e.g. 20.0).
  double get speedHz => 20.0;

  /// Changes the execution speed.
  void setSpeedHz(double speed) {}

  /// Advances the game by one tick.
  void tick();

  /// Starts the game loop.
  void start();

  /// Pauses the game loop.
  void pause();

  /// Resumes the game loop.
  void resume();

  /// Restarts the active game session to initial state.
  void restartGame({int startingRoom = 0});

  /// Dispatches 8-direction navigation input (0 = stop, 1 = up, 2 = up-right, ...).
  void handleDirection(int direction);

  /// Dispatches a key press event.
  void handleKeyPress(
    int? rawKeyCode, {
    int ascii = 0,
    bool shift = false,
    bool ctrl = false,
    bool alt = false,
  });

  /// Dispatches a mouse click on the playfield (in native coordinates).
  void handleMouseClick(ui.Offset playfieldPos);

  /// Submits a typed command string from the user.
  void submitCommand(String command);

  /// Disposes of game engine resources, timers, and audio.
  void dispose();
}
