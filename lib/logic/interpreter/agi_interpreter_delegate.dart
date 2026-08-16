import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';

/// Delegate interface allowing the AGI logic interpreter to interact with
/// the surrounding engine subsystems (rendering, sound synthesizer, text console, resource manager).
abstract class AgiInterpreterDelegate {
  /// Called when an animated object is drawn on screen (for boundary and horizon clamping).
  void onDraw(AnimatedObject obj) {}
  /// Called when the script requests a room change via `new.room` or `new.room.v`.
  void onNewRoom(int roomNumber) {}

  /// Loads a referenced logic script for `call` / `call.v`.
  AgiLogicScript? loadLogic(int logicNumber) => null;

  /// Called when `print` or `print.v` is executed.
  void onPrint(String message) {}

  /// Called when `display` or `display.v` is executed.
  void onDisplay(int row, int col, String message) {}

  /// Called when `print.at` or `print.at.v` is executed.
  void onPrintAt(String message, int x, int y, int width) {}

  /// Called when `clear.lines` is executed.
  void onClearLines(int top, int bottom, int color) {}

  /// Called when `clear.text.rect` is executed.
  void onClearTextRect(int top, int left, int bottom, int right, int color) {}

  /// Called when `text.screen` is executed.
  void onTextScreen() {}

  /// Called when `graphics` is executed.
  void onGraphics() {}

  /// Called when `shake.screen` is executed.
  void onShakeScreen(int count) {}

  /// Called when `sound` action begins playing a sound resource.
  void onSound(int soundNumber, int completionFlag) {}

  /// Called when `stop.sound` is executed.
  void onStopSound() {}

  /// Called when `load.pic` is executed.
  void onLoadPic(int picNumber) {}

  /// Called when `draw.pic` is executed.
  void onDrawPic(int picNumber) {}

  /// Called when `show.pic` is executed.
  void onShowPic() {}

  /// Called when `overlay.pic` is executed.
  void onOverlayPic(int picNumber) {}

  /// Called when `show.pri.screen` is executed.
  void onShowPriScreen() {}

  /// Called when `discard.pic` is executed.
  void onDiscardPic(int picNumber) {}

  /// Called when `load.view` is executed.
  void onLoadView(int viewNumber) {}

  /// Called when `discard.view` is executed.
  void onDiscardView(int viewNumber) {}

  /// Called when `add.to.pic` or `add.to.pic.v` is executed.
  void onAddToPic(int view, int loop, int cel, int x, int y, int pri, int boxPri) {}

  /// Called when `show.obj` or `show.obj.v` is executed.
  void onShowObj(int objNumber) {}

  /// Called when `quit` is executed.
  void onQuit() {}

  /// Called when `pause` is executed.
  void onPause() {}

  /// Called when `status.line.on` / `status.line.off` is executed.
  void onStatusLine(bool enabled) {}

  /// Called when `prevent.input` / `accept.input` is executed.
  void onInputMode(bool enabled) {}

  /// Called when `program.control` or `player.control` is executed.
  void onUserControl(bool enabled) {}

  /// Called when `set.horizon` changes the room horizon line.
  void onSetHorizon(int horizon) {}

  /// Called when `block` defines an active barrier rectangle.
  void onBlock(int x1, int y1, int x2, int y2) {}

  /// Called when `unblock` removes the active barrier rectangle.
  void onUnblock() {}

  /// Called when `log` is executed.
  void onLog(String message) {}

  /// Called when `set.key` is executed to register a key-to-controller mapping.
  void onSetKey(int scancode, int ascii, int controllerCode) {}

  /// Called when `save.game` is executed.
  void onSaveGame() {}

  /// Called when `restore.game` is executed.
  void onRestoreGame() {}

  /// Called when `restart.game` is executed.
  void onRestartGame() {}

  /// Evaluates whether a key was pressed (for test opcode 0x0D `have.key()`).
  bool haveKey() => false;

  /// Evaluates whether the current parsed user input matches [wordGroupIds] for `said(...)`.
  bool checkSaid(List<int> wordGroupIds) => false;
}

/// Default no-op delegate implementation (useful for tests and headless execution).
class DefaultAgiInterpreterDelegate extends AgiInterpreterDelegate {}

