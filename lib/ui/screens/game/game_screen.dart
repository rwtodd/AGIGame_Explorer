import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/debug_inspector_dialog.dart';
import 'package:flutter_agigame/ui/widgets/dialog_box_widget.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_agigame/ui/widgets/input_prompt_dialog.dart';
import 'package:flutter_agigame/ui/widgets/inventory_dialog.dart';
import 'package:flutter_agigame/ui/widgets/object_inspection_dialog.dart';
import 'package:flutter_agigame/ui/widgets/save_load_dialog.dart';

/// Main Playable Game Screen for Sierra AGI games.
///
/// Features:
/// - Top Status Bar (Score, Max Score, Sound Status)
/// - Composite 16-Layer Playfield Viewport
/// - Bottom Text Command Prompt with History (Up/Down arrow recall)
/// - Keyboard Arrow / WASD Directional Controller
/// - Retro Modal Dialog Popups with Unicode text support
/// - Live Speed and Diagnostics Toolbar
class GameScreen extends StatefulWidget {
  final AgiResourceLoader? resourceLoader;
  final AgiGameEngine? engine;
  final int startingRoom;

  const GameScreen({
    super.key,
    this.resourceLoader,
    this.engine,
    this.startingRoom = 0,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final AgiGameEngine _engine;
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final FocusNode _gameFocusNode = FocusNode();

  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  AgiPictureRenderMode _renderMode = AgiPictureRenderMode.compositedSlices;
  bool _showCrtShader = false;
  bool _showPixelGrid = false;

  @override
  void initState() {
    super.initState();
    if (widget.engine != null) {
      _engine = widget.engine!;
    } else {
      final soundPlayer = AgiSoundPlayer();
      _engine = AgiGameEngine(
        resourceLoader: widget.resourceLoader,
        soundPlayer: soundPlayer,
      );
      _engine.initializeGame(startingRoom: widget.startingRoom);
      _engine.start();
    }

    _engine.onSaveGameRequested = () => SaveLoadDialog.showSave(context, _engine);
    _engine.onRestoreGameRequested = () => SaveLoadDialog.showRestore(context, _engine);
    _engine.onRestartGameRequested = () => SaveLoadDialog.showRestartConfirmation(context, _engine);

    _engine.addListener(_onEngineUpdated);
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdated);
    if (widget.engine == null) {
      _engine.soundPlayer?.dispose();
      _engine.dispose();
    }
    _promptController.dispose();
    _promptFocusNode.dispose();
    _gameFocusNode.dispose();
    super.dispose();
  }

  void _onEngineUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSubmitCommand(String text) {
    final cmd = text.trim();
    if (cmd.isNotEmpty) {
      _commandHistory.remove(cmd);
      _commandHistory.add(cmd);
      _historyIndex = _commandHistory.length;
      _engine.submitCommand(cmd);
      _promptController.clear();
    }
  }

  void _navigateHistory(int delta) {
    if (_commandHistory.isEmpty) return;

    final newIndex = (_historyIndex + delta).clamp(0, _commandHistory.length);
    if (newIndex != _historyIndex) {
      _historyIndex = newIndex;
      if (_historyIndex >= 0 && _historyIndex < _commandHistory.length) {
        _promptController.text = _commandHistory[_historyIndex];
        _promptController.selection = TextSelection.fromPosition(
          TextPosition(offset: _promptController.text.length),
        );
      } else {
        _promptController.clear();
      }
    }
  }

  int _getKeyCode(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      return 13;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return 32;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return 27;
    }
    if (event.character != null && event.character!.isNotEmpty) {
      return event.character!.codeUnitAt(0);
    }
    return 13;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 1. If modal text dialog is open, Enter/Space/Escape dismisses it
    if (_engine.activeDialog != null && _engine.activeDialog!.isModal) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.dismissDialog();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 2. If object inspection modal is open, Enter/Space/Escape dismisses it
    if (_engine.inspectingObjectNumber != null) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.closeObjectInspection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 3. If inventory dialog is open, Tab or Escape dismisses it; other keys handled by dialog
    if (_engine.isInventoryOpen) {
      if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.closeInventory();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 4. Tab opens Inventory screen
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _engine.openInventory();
      return KeyEventResult.handled;
    }

    // 4. F12 or Ctrl+D / Cmd+D opens Debug Inspector
    if (event.logicalKey == LogicalKeyboardKey.f12 ||
        ((HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyD)) {
      DebugInspectorDialog.show(context, _engine);
      return KeyEventResult.handled;
    }

    // 3. Register key press on engine for `have.key()` and %v19 (LAST_CHAR)
    // (Only when prompt is not actively receiving text input)
    if (!_promptFocusNode.hasFocus) {
      _engine.handleKeyPress(_getKeyCode(event));
    }

    // 4. Trigger registered controller shortcuts via set.key mappings
    // (Only if not typing regular printable characters in the prompt)
    if (!_promptFocusNode.hasFocus ||
        event.logicalKey.keyId >= 0x1100000000 || // Function keys, modifiers, etc.
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      final controllerTriggered = _engine.controllerManager.handleKeyEvent(event, _engine.memory);
      if (controllerTriggered) {
        return KeyEventResult.handled;
      }
    }

    // If prompt is focused, allow cursor navigation and typing to reach TextField
    if (_promptFocusNode.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.space ||
          (event.character != null &&
              event.character!.isNotEmpty &&
              !HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isAltPressed &&
              !HardwareKeyboard.instance.isMetaPressed)) {
        return KeyEventResult.ignored;
      }
    }

    // 5. Direction controls ALWAYS control Ego
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.numpad8:
        _engine.setEgoDirection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.numpad9:
        _engine.setEgoDirection(2);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.numpad6:
        _engine.setEgoDirection(3);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.numpad3:
        _engine.setEgoDirection(4);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.numpad2:
        _engine.setEgoDirection(5);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.numpad1:
        _engine.setEgoDirection(6);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.numpad4:
        _engine.setEgoDirection(7);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.numpad7:
        _engine.setEgoDirection(8);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.numpad5:
        _engine.setEgoDirection(0); // Stop
        return KeyEventResult.handled;
    }

    // 6. Command history navigation via PageUp/PageDown or F3
    if (event.logicalKey == LogicalKeyboardKey.pageUp ||
        event.logicalKey == LogicalKeyboardKey.f3) {
      _navigateHistory(-1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _navigateHistory(1);
      return KeyEventResult.handled;
    }

    // 7. Command prompt input (when prompt is NOT focused, allow typing directly to prompt)
    if (_engine.isInputEnabled && !_promptFocusNode.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _handleSubmitCommand(_promptController.text);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        final text = _promptController.text;
        if (text.isNotEmpty) {
          _promptController.text = text.substring(0, text.length - 1);
          _promptController.selection = TextSelection.fromPosition(
            TextPosition(offset: _promptController.text.length),
          );
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _promptController.clear();
        return KeyEventResult.handled;
      } else if (event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        final char = event.character!;
        final code = char.codeUnitAt(0);
        if (code >= 32 && code <= 126) {
          _promptController.text = _promptController.text + char;
          _promptController.selection = TextSelection.fromPosition(
            TextPosition(offset: _promptController.text.length),
          );
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _gameFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopToolbar(),
              if (_engine.isStatusLineEnabled) _buildStatusBar(),
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GamePlayfieldWidget(
                        engine: _engine,
                        renderMode: _renderMode,
                        showCrtShader: _showCrtShader,
                        showPixelGrid: _showPixelGrid,
                      ),

                      // Modal Dialog Popup Overlay
                      if (_engine.activeDialog != null && _engine.activeDialog!.isModal)
                        Positioned.fill(
                          child: DialogBoxWidget(
                            dialogState: _engine.activeDialog!,
                            onDismiss: _engine.dismissDialog,
                          ),
                        ),

                      // Modal Input Prompt Popup Overlay
                      if (_engine.activeInputPrompt != null)
                        Positioned.fill(
                          child: InputPromptDialog(
                            promptState: _engine.activeInputPrompt!,
                            onSubmit: _engine.submitInputPrompt,
                            onCancel: _engine.cancelInputPrompt,
                          ),
                        ),

                      // Inventory Dialog Overlay
                      if (_engine.isInventoryOpen && _engine.inspectingObjectNumber == null)
                        Positioned.fill(
                          child: InventoryDialog(
                            engine: _engine,
                            onClose: _engine.closeInventory,
                            onInspect: (itemIdx) => _engine.inspectObject(itemIdx),
                          ),
                        ),

                      // Object Inspection Dialog Overlay
                      if (_engine.inspectingObjectNumber != null)
                        Positioned.fill(
                          child: ObjectInspectionDialog(
                            engine: _engine,
                            objectNumber: _engine.inspectingObjectNumber!,
                            onClose: _engine.closeObjectInspection,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _buildCommandPromptBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18, color: AgiTheme.egaCyan),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Exit Game',
          ),
          const SizedBox(width: 4),
          const Text(
            'AGI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaWhite,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 6),

          // Pause / Play toggle
          IconButton(
            icon: Icon(
              _engine.isPaused ? Icons.play_arrow : Icons.pause,
              size: 18,
              color: _engine.isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {
              if (_engine.isPaused) {
                _engine.resume();
              } else {
                _engine.pause();
              }
            },
            tooltip: _engine.isPaused ? 'Resume Engine' : 'Pause Engine',
          ),

          // Single Step
          IconButton(
            icon: const Icon(Icons.skip_next, size: 18, color: AgiTheme.egaCyan),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: _engine.isPaused ? () => _engine.tick() : null,
            tooltip: 'Step Single Cycle',
          ),

          // Save Game (F5)
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 18, color: Color(0xFF22C55E)),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => SaveLoadDialog.showSave(context, _engine),
            tooltip: 'Save Game (F5)',
          ),

          // Restore Game (F7)
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 18, color: AgiTheme.egaCyan),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => SaveLoadDialog.showRestore(context, _engine),
            tooltip: 'Restore Game (F7)',
          ),

          // Restart Game (F9)
          IconButton(
            icon: const Icon(Icons.replay, size: 18, color: AgiTheme.egaRed),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => SaveLoadDialog.showRestartConfirmation(context, _engine),
            tooltip: 'Restart Game (F9)',
          ),

          const Spacer(),

          // Speed Selection
          PopupMenuButton<double>(
            initialValue: _engine.speedHz,
            tooltip: 'Cycle Speed',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 13, color: AgiTheme.egaAmber),
                  const SizedBox(width: 3),
                  Text(
                    '${_engine.speedHz.toInt()} Hz',
                    style: const TextStyle(fontSize: 10, color: AgiTheme.egaAmber),
                  ),
                ],
              ),
            ),
            onSelected: (hz) => _engine.setSpeedHz(hz),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 10.0, child: Text('Slow (10 Hz)')),
              PopupMenuItem(value: 20.0, child: Text('Normal (20 Hz)')),
              PopupMenuItem(value: 40.0, child: Text('Fast (40 Hz)')),
              PopupMenuItem(value: 60.0, child: Text('Fastest (60 Hz)')),
            ],
          ),
          const SizedBox(width: 4),

          // CRT Toggle
          IconButton(
            icon: Icon(
              Icons.tv,
              size: 18,
              color: _showCrtShader ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _showCrtShader = !_showCrtShader;
              });
            },
            tooltip: 'Toggle CRT Scanline Shader',
          ),

          // Pixel Grid Toggle
          IconButton(
            icon: Icon(
              Icons.grid_4x4,
              size: 18,
              color: _showPixelGrid ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _showPixelGrid = !_showPixelGrid;
              });
            },
            tooltip: 'Toggle Pixel Grid',
          ),
          const SizedBox(width: 2),

          // Render Mode View Toggle
          PopupMenuButton<AgiPictureRenderMode>(
            initialValue: _renderMode,
            tooltip: 'View Layer Mode',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, size: 13, color: AgiTheme.egaCyan),
                  const SizedBox(width: 3),
                  Text(
                    _renderMode.name.toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: AgiTheme.egaCyan),
                  ),
                ],
              ),
            ),
            onSelected: (mode) {
              setState(() {
                _renderMode = mode;
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: AgiPictureRenderMode.compositedSlices,
                child: Text('Priority Slices (Game View)'),
              ),
              PopupMenuItem(
                value: AgiPictureRenderMode.flatVisual,
                child: Text('Flat Visual Background'),
              ),
              PopupMenuItem(
                value: AgiPictureRenderMode.priorityMap,
                child: Text('Priority Depth Map'),
              ),
              PopupMenuItem(
                value: AgiPictureRenderMode.controlMap,
                child: Text('Control Barrier Map'),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Debug Inspector & Checkpoint button
          IconButton(
            icon: const Icon(Icons.bug_report, size: 18, color: AgiTheme.egaGreen),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => DebugInspectorDialog.show(context, _engine),
            tooltip: 'Debug Inspector & Checkpoints (F12)',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final score = _engine.memory.getVar(3);
    final maxScore = _engine.memory.getVar(7);
    final soundOn = _engine.memory.getFlag(9);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0), // Classic light gray EGA status bar
        border: Border(
          bottom: BorderSide(color: Color(0xFF94A3B8), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Score: $score of $maxScore',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontFamily: 'Courier',
            ),
          ),
          InkWell(
            onTap: () => _engine.toggleSound(),
            child: Row(
              children: [
                Icon(
                  soundOn ? Icons.volume_up : Icons.volume_off,
                  size: 14,
                  color: soundOn ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  'Sound: ${soundOn ? "ON" : "OFF"}',
                  style: TextStyle(
                    color: soundOn ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandPromptBar() {
    final isEnabled = _engine.isInputEnabled;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isEnabled ? const Color(0xFF0D1117) : const Color(0xFF070A0E),
        border: Border(
          top: BorderSide(
            color: isEnabled ? AgiTheme.egaBorder : const Color(0xFF1E293B),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '> ',
            style: TextStyle(
              color: isEnabled ? AgiTheme.egaWhite : const Color(0xFF475569),
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
          Expanded(
            child: TextField(
              controller: _promptController,
              focusNode: _promptFocusNode,
              enabled: isEnabled,
              style: TextStyle(
                color: isEnabled ? AgiTheme.egaWhite : const Color(0xFF475569),
                fontSize: 14,
                fontFamily: 'Courier',
              ),
              cursorColor: isEnabled ? AgiTheme.egaCyan : Colors.transparent,
              cursorWidth: 8,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                hintText: isEnabled ? 'Type a command (e.g. look around)...' : '[INPUT DISABLED]',
                hintStyle: TextStyle(
                  color: isEnabled ? const Color(0xFF4B5563) : const Color(0xFF334155),
                  fontSize: 13,
                  fontFamily: 'Courier',
                ),
              ),
              onSubmitted: isEnabled ? _handleSubmitCommand : null,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.send,
              size: 16,
              color: isEnabled ? AgiTheme.egaCyan : const Color(0xFF334155),
            ),
            onPressed: isEnabled ? () => _handleSubmitCommand(_promptController.text) : null,
            tooltip: isEnabled ? 'Send Command (Enter)' : 'Input Disabled',
          ),
        ],
      ),
    );
  }
}
