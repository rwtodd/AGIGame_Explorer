import 'dart:async';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/animated_object.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';

/// Delegate interface allowing the AGI logic interpreter to interact with
/// the surrounding engine subsystems (rendering, sound synthesizer, text console, resource manager).
abstract class AgiInterpreterDelegate {
  /// Called when an animated object is drawn on screen (for boundary and horizon clamping).
  FutureOr<void> onDraw(AnimatedObject obj) {}

  /// Called when an animated object transitions to updating (`start.update`).
  void onStartUpdate(AnimatedObject obj) {}

  /// Called when an animated object is erased from the screen (`erase`).
  void onErase(AnimatedObject obj) {}

  /// Called when an animated object is repositioned (`reposition`, `reposition.to`).
  void onReposition(AnimatedObject obj, int newX, int newY) {}

  /// Called when an animated object is assigned a move path (`move.obj`, `move.obj.v`).
  void onMoveObj(AnimatedObject obj, int targetX, int targetY) {}

  /// Called when the script requests a room change via `new.room` or `new.room.v`.
  FutureOr<void> onNewRoom(int roomNumber) {}

  /// Loads a referenced logic script for `call` / `call.v`.
  AgiLogicScript? loadLogic(int logicNumber) => null;

  /// Retrieves an active or cached VIEW resource by [viewNumber].
  AgiView? getView(int viewNumber) => null;

  /// The vocabulary dictionary (WORDS.TOK) associated with the current game.
  AgiDictionary? get dictionary => null;

  /// Converts a vocabulary word group ID [wordId] into its primary text string.
  String? wordToString(int wordId) {
    final dict = dictionary;
    if (dict != null) {
      final words = dict.idToWords(wordId);
      if (words.isNotEmpty) return words.first;
    }
    return null;
  }

  /// Parses user command string [input] through vocabulary tokenizer and feeds into said matcher.
  void onParse(String input) {}

  /// Prompts the player for a text string input with message [prompt] (e.g. `get.string`).
  Future<String?> onGetString(String prompt, int row, int col, int maxLen) async => null;

  /// Prompts the player for a numeric input with message [prompt] (e.g. `get.num`).
  Future<int?> onGetNum(String prompt) async => null;

  /// Called when `print` or `print.v` is executed.
  FutureOr<void> onPrint(String message, {bool isModal = true, int timeoutHalfSeconds = 0}) {}

  /// Called when `display` or `display.v` is executed.
  void onDisplay(int row, int col, String message) {}

  /// Called when `print.at` or `print.at.v` is executed.
  FutureOr<void> onPrintAt(String message, int row, int col, int width, {bool isModal = true, int timeoutHalfSeconds = 0}) {}

  /// Called when `close.window` is executed.
  void onCloseWindow() {}

  /// Called when `clear.lines` is executed.
  void onClearLines(int top, int bottom, int color) {}

  /// Called when `clear.text.rect` is executed.
  void onClearTextRect(int top, int left, int bottom, int right, int color) {}

  /// Called when `set.text.attribute` is executed.
  void onSetTextAttribute(int fg, int bg) {}

  /// Called when `text.screen` is executed.
  void onTextScreen() {}

  /// Called when `graphics` is executed.
  void onGraphics() {}

  /// Called when `shake.screen` is executed.
  FutureOr<void> onShakeScreen(int count) {}

  /// Called when `configure.screen` is executed.
  void onConfigureScreen(int playTop, int inputLine, int statusLine) {}

  /// Called when `sound` action begins playing a sound resource.
  void onSound(int soundNumber, int completionFlag) {}

  /// Called when `stop.sound` is executed.
  void onStopSound() {}

  /// Called when `load.pic` is executed.
  FutureOr<void> onLoadPic(int picNumber) {}

  /// Called when `draw.pic` is executed.
  FutureOr<void> onDrawPic(int picNumber) {}

  /// Called when `show.pic` is executed.
  FutureOr<void> onShowPic() {}

  /// Called when `overlay.pic` is executed.
  void onOverlayPic(int picNumber) {}

  /// Called when `show.pri.screen` is executed.
  void onShowPriScreen() {}

  /// Called when `discard.pic` is executed.
  void onDiscardPic(int picNumber) {}

  /// Called when `load.view` is executed.
  FutureOr<void> onLoadView(int viewNumber) {}

  /// Called when `discard.view` is executed.
  void onDiscardView(int viewNumber) {}

  /// Called when `add.to.pic` or `add.to.pic.v` is executed.
  FutureOr<void> onAddToPic(int view, int loop, int cel, int x, int y, int pri, int boxPri) {}

  /// Called when `status` is executed.
  FutureOr<void> onStatus() {}

  /// Called when `show.obj` or `show.obj.v` is executed.
  FutureOr<void> onShowObj(int objNumber) {}

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

  /// Called when `set.menu` is executed.
  void onSetMenu(String menuName) {}

  /// Called when `set.menu.item` is executed.
  void onSetMenuItem(String itemName, int controllerSlot) {}

  /// Called when `submit.menu` is executed.
  void onSubmitMenu() {}

  /// Called when `enable.item` is executed.
  void onEnableItem(int controllerSlot) {}

  /// Called when `disable.item` is executed.
  void onDisableItem(int controllerSlot) {}

  /// Called when `menu.input` is executed.
  void onMenuInput() {}

  /// Evaluates whether a key was pressed (for test opcode 0x0D `have.key()`).
  bool haveKey() => false;

  /// Evaluates whether the current parsed user input matches [wordGroupIds] for `said(...)`.
  bool checkSaid(List<int> wordGroupIds) => false;

  /// Current room horizon Y. Used by Sierra `SetCel` border clipping.
  int get horizon => 36;
}

/// Default no-op delegate implementation (useful for tests and headless execution).
class DefaultAgiInterpreterDelegate extends AgiInterpreterDelegate {}

