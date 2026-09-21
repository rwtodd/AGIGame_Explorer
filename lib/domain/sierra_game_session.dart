import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/core/display_profile.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/save_slot_info.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/domain/sound.dart';
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

  /// Current room or scene number (e.g. 0..255 in AGI, global 11 in SCI0).
  int get currentRoom;

  /// Current player score.
  int get score => 0;

  /// Maximum possible player score.
  int get maxScore => 0;

  /// Directory where save state files are stored.
  Directory? get saveDirectory => null;
  set saveDirectory(Directory? dir) {}

  /// Callback when the game requests the Save Game modal dialog.
  VoidCallback? get onSaveGameRequested => null;
  set onSaveGameRequested(VoidCallback? cb) {}

  /// Callback when the game requests the Restore Game modal dialog.
  VoidCallback? get onRestoreGameRequested => null;
  set onRestoreGameRequested(VoidCallback? cb) {}

  /// Callback when the game requests the Restart Game confirmation dialog.
  VoidCallback? get onRestartGameRequested => null;
  set onRestartGameRequested(VoidCallback? cb) {}

  /// Title or status text shown in the top bar.
  String get statusLine;

  /// Input prompt label, if input prompt is active.
  String get promptLine => '';

  /// Whether the game is currently paused.
  bool get isPaused;

  /// Whether this session has been disposed and should no longer be interacted with.
  bool get isDisposed => false;

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

  /// Sound player managing active audio synthesis and playback.
  AgiSoundPlayer? get soundPlayer => null;

  /// Active audio mode (PC Speaker, Tandy/PCjr, Enhanced, or Off).
  AgiSoundMode get soundMode => AgiSoundMode.off;

  /// Whether sound playback is currently enabled and unmuted.
  bool get isSoundOn => false;

  /// Configuration for enhanced FM/DSP synthesizer parameters.
  SynthesizerConfig get synthesizerConfig => const SynthesizerConfig();

  /// Changes the audio playback mode.
  void setSoundMode(AgiSoundMode mode) {}

  /// Updates the synthesizer configuration parameters.
  void setSynthesizerConfig(SynthesizerConfig config) {}

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

  /// Cancels an interactive restart request.
  void cancelRestart() {}

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

  /// Updates the playfield mouse position (native coordinates). Default no-op.
  void handleMouseMove(ui.Offset playfieldPos) {}

  /// Submits a typed command string from the user.
  void submitCommand(String command);

  /// Saves the active game state to save slot [slot].
  Future<File> saveGameState({
    int slot = 1,
    String description = '',
    Directory? directory,
  }) =>
      throw UnsupportedError('saveGameState is not supported by this session');

  /// Restores the game state from save slot [slot].
  Future<bool> restoreGameState({
    int slot = 1,
    Directory? directory,
  }) =>
      throw UnsupportedError('restoreGameState is not supported by this session');

  /// Lists save slot metadata.
  List<SaveSlotInfo> listSaveSlots({
    Directory? directory,
    int maxSlots = 12,
  }) =>
      const [];

  /// Captures an RGBA thumbnail of the current screen.
  Uint8List? captureScreenThumbnailRgba({
    int targetWidth = 80,
    int targetHeight = 84,
  }) =>
      null;

  /// Disposes of game engine resources, timers, and audio.
  void dispose();
}
