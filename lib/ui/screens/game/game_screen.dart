import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/debug_inspector_dialog.dart';
import 'package:flutter_agigame/ui/widgets/dialog_box_widget.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_agigame/ui/widgets/input_prompt_dialog.dart';
import 'package:flutter_agigame/ui/widgets/inventory_dialog.dart';
import 'package:flutter_agigame/ui/widgets/object_inspection_dialog.dart';
import 'package:flutter_agigame/ui/widgets/save_load_dialog.dart';
import 'package:flutter_agigame/ui/widgets/sidebar_slideout_panel.dart';

/// Main Playable Game Screen for Sierra AGI games.
///
/// Features:
/// - Top Status Bar (Score, Max Score, Sound Status)
/// - Composite 16-Layer Playfield Viewport
/// - Bottom Text Command Prompt with History (Up/Down arrow recall)
/// - Keyboard Arrow / WASD Directional Controller
/// - Retro Modal Dialog Popups with Unicode text support
/// - Live Speed and Diagnostics Toolbar
class GameScreen extends ConsumerStatefulWidget {
  final AgiResourceLoader? resourceLoader;
  final AgiGameEngine? engine;
  final int startingRoom;
  final AgiUserSettings? initialSettings;

  const GameScreen({
    super.key,
    this.resourceLoader,
    this.engine,
    this.startingRoom = 0,
    this.initialSettings,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final AgiGameEngine _engine;
  final FocusNode _gameFocusNode = FocusNode();
  String _currentInputText = '';

  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  AgiPictureRenderMode _renderMode = AgiPictureRenderMode.compositedSlices;
  bool _showCrtShader = false;
  bool _showPixelGrid = false;
  bool _renderBlackTextBackgrounds = false;
  bool _correctAspectRatio = true;
  bool _strictIntegerScaling = false;
  SidebarPanelTab? _openPanelTab;
  DateTime? _lastDialogDismissTime;

  @override
  void initState() {
    super.initState();

    final initSettings = widget.initialSettings;
    if (initSettings != null) {
      _showCrtShader = initSettings.display.showCrtShader;
      _showPixelGrid = initSettings.display.showPixelGrid;
      _renderBlackTextBackgrounds = initSettings.display.renderBlackTextBackgrounds;
      _correctAspectRatio = initSettings.display.correctAspectRatio;
      _strictIntegerScaling = initSettings.display.strictIntegerScaling;
      _renderMode = initSettings.display.renderMode;
    }

    if (widget.engine != null) {
      _engine = widget.engine!;
      if (initSettings != null) {
        _engine.setSoundMode(initSettings.audio.soundMode);
        _engine.setSynthesizerConfig(initSettings.audio.toSynthesizerConfig());
      }
    } else {
      final soundPlayer = AgiSoundPlayer();
      _engine = AgiGameEngine(
        resourceLoader: widget.resourceLoader,
        soundPlayer: soundPlayer,
      );

      if (initSettings != null) {
        _engine.setSoundMode(initSettings.audio.soundMode);
        _engine.setSynthesizerConfig(initSettings.audio.toSynthesizerConfig());
      }

      _engine.initializeGame(startingRoom: widget.startingRoom);
      _engine.start();
    }

    _engine.onSaveGameRequested = () => SaveLoadDialog.showSave(context, _engine);
    _engine.onRestoreGameRequested = () => SaveLoadDialog.showRestore(context, _engine);
    _engine.onRestartGameRequested = () => SaveLoadDialog.showRestartConfirmation(context, _engine);
  }

  @override
  void dispose() {
    if (widget.engine == null) {
      _engine.dispose();
      _engine.soundPlayer.dispose();
    }
    _gameFocusNode.dispose();
    super.dispose();
  }

  void _handleSubmitCommand([String? text]) {
    final cmd = (text ?? _currentInputText).trim();
    if (cmd.isNotEmpty) {
      _commandHistory.remove(cmd);
      _commandHistory.add(cmd);
      _historyIndex = _commandHistory.length;

      // Debug warp: intercepted here, before WORDS.TOK / said().
      // Bang-prefix so it can never collide with a real vocabulary word.
      final lower = cmd.toLowerCase();
      if (lower.startsWith('!tp')) {
        final rest = cmd.substring(3).trim();
        final targetRoom = int.tryParse(rest.split(RegExp(r'\s+')).first);
        if (targetRoom != null && targetRoom >= 0 && targetRoom <= 255) {
          _engine.changeRoom(targetRoom);
          _engine.tick();
          _engine.recordCheckpoint(label: 'Teleport to Room $targetRoom');
          setState(() {
            _currentInputText = '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🚀 Teleported to Room $targetRoom',
                  style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
              backgroundColor: const Color(0xFF0284C7),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      }

      _engine.submitCommand(cmd);
      setState(() {
        _currentInputText = '';
      });
    }
  }

  void _navigateHistory(int delta) {
    if (_commandHistory.isEmpty) return;

    final newIndex = (_historyIndex + delta).clamp(0, _commandHistory.length);
    if (newIndex != _historyIndex) {
      _historyIndex = newIndex;
      setState(() {
        if (_historyIndex >= 0 && _historyIndex < _commandHistory.length) {
          _currentInputText = _commandHistory[_historyIndex];
        } else {
          _currentInputText = '';
        }
      });
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
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    // 0. If interactive input prompt is open (e.g. get.string / get.num), handle typing and submission regardless of focus
    if (_engine.activeInputPrompt != null) {
      final prompt = _engine.activeInputPrompt!;
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _engine.submitInputPrompt(prompt.currentText);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.cancelInputPrompt();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (prompt.currentText.isNotEmpty) {
          final newText = prompt.currentText.substring(0, prompt.currentText.length - 1);
          _engine.updateInputPrompt(newText);
        }
        return KeyEventResult.handled;
      }
      if (event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        final char = event.character!;
        final code = char.codeUnitAt(0);
        if (code >= 32 && code <= 126) {
          if (prompt.type == AgiInputPromptType.number && (code < 48 || code > 57)) {
            return KeyEventResult.handled; // ignore non-digit for numeric prompts
          }
          if (prompt.maxLen > 0 && prompt.currentText.length >= prompt.maxLen) {
            return KeyEventResult.handled; // ignore when at max length
          }
          _engine.updateInputPrompt(prompt.currentText + char);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    }

    // 1. If modal text dialog is open, Enter/Space/Escape dismisses it
    if (_engine.activeDialog != null && _engine.activeDialog!.isModal) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        final now = DateTime.now();
        if (_lastDialogDismissTime == null || now.difference(_lastDialogDismissTime!).inMilliseconds > 150) {
          _lastDialogDismissTime = now;
          _engine.dismissDialog();
        }
      }
      return KeyEventResult.handled;
    }

    // 2. If object inspection modal is open, Enter/Space/Escape dismisses it
    if (_engine.inspectingObjectNumber != null) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.closeObjectInspection();
      }
      return KeyEventResult.handled;
    }

    // 3. If inventory dialog is open, Tab or Escape dismisses it; other keys handled by dialog
    if (_engine.isInventoryOpen) {
      if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.closeInventory();
      }
      return KeyEventResult.handled;
    }

    // 4. If full text screen is active (e.g. Help or About screen), any key sends keypress and ticks engine
    if (_engine.isTextScreen) {
      _engine.handleKeyPress(_getKeyCode(event));
      _engine.tick();
      return KeyEventResult.handled;
    }

    // 4. If Menu system is open, route navigation and item selection
    if (_engine.isMenuOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.closeMenu();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _engine.navigateMenuLeft();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _engine.navigateMenuRight();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _engine.navigateMenuUp();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _engine.navigateMenuDown();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.home) {
        _engine.menuManager.navigateHome();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.end) {
        _engine.menuManager.navigateEnd();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.pageUp) {
        _engine.menuManager.navigatePageUp();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.pageDown) {
        _engine.menuManager.navigatePageDown();
        setState(() {});
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _engine.selectMenuItem();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // 5. ESC opens Menu Bar (if menu is available and enabled)
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_currentInputText.isNotEmpty) {
        setState(() {
          _currentInputText = '';
        });
        return KeyEventResult.handled;
      } else if (_engine.menuManager.isAvailable && _engine.memory.getFlag(14)) {
        _engine.openMenu();
        return KeyEventResult.handled;
      }
    }

    // 6. Tab opens Inventory screen
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
    _engine.handleKeyPress(_getKeyCode(event));

    // 4. Trigger registered controller shortcuts via set.key mappings
    final controllerTriggered = _engine.controllerManager.handleKeyEvent(event, _engine.memory);
    if (controllerTriggered) {
      return KeyEventResult.handled;
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

    // 7. Command prompt input (when input is enabled)
    if (_engine.isInputEnabled) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _handleSubmitCommand();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_currentInputText.isNotEmpty) {
          setState(() {
            _currentInputText = _currentInputText.substring(0, _currentInputText.length - 1);
          });
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_currentInputText.isNotEmpty) {
          setState(() {
            _currentInputText = '';
          });
        }
        return KeyEventResult.handled;
      } else if ((event.logicalKey == LogicalKeyboardKey.space || event.character == ' ') &&
          _currentInputText.isEmpty &&
          _commandHistory.isNotEmpty) {
        // Spacebar on empty input recalls the last entered command (SCI-style QoL)
        setState(() {
          _currentInputText = _commandHistory.last;
          _historyIndex = _commandHistory.length - 1;
        });
        return KeyEventResult.handled;
      } else if (event.character != null &&
          event.character!.isNotEmpty &&
          !HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isAltPressed) {
        final char = event.character!;
        final code = char.codeUnitAt(0);
        if (code >= 32 && code <= 126) {
          setState(() {
            _currentInputText = _currentInputText + char;
          });
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.handled;
  }

  void _safeUpdateDisplay({
    bool? showCrtShader,
    bool? showPixelGrid,
    bool? renderBlackTextBackgrounds,
    bool? correctAspectRatio,
    bool? strictIntegerScaling,
    AgiPictureRenderMode? renderMode,
  }) {
    try {
      ref.read(settingsProvider.notifier).updateDisplay(
            showCrtShader: showCrtShader,
            showPixelGrid: showPixelGrid,
            renderBlackTextBackgrounds: renderBlackTextBackgrounds,
            correctAspectRatio: correctAspectRatio,
            strictIntegerScaling: strictIntegerScaling,
            renderMode: renderMode,
          );
    } catch (_) {
      // Safe fallback if mounted without ProviderScope in unit tests
    }
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
          child: Row(
            children: [
              _buildLeftSidebar(),
              _openPanelTab != null
                  ? ListenableBuilder(
                      listenable: _engine,
                      builder: (context, _) => _buildSlideoutPanel(),
                    )
                  : _buildSlideoutPanel(),
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Playfield paints from the engine listenable; it is not
                      // rebuilt on every AGI tick (see GamePlayfieldWidget).
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: GamePlayfieldWidget(
                            engine: _engine,
                            renderMode: _renderMode,
                            showCrtShader: _showCrtShader,
                            showPixelGrid: _showPixelGrid,
                            renderBlackTextBackgrounds: _renderBlackTextBackgrounds,
                            correctAspectRatio: _correctAspectRatio,
                            strictIntegerScaling: _strictIntegerScaling,
                            currentInputText: _currentInputText,
                          ),
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _engine,
                        builder: (context, _) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_engine.activeDialog != null)
                                Positioned.fill(
                                  child: DialogBoxWidget(
                                    dialogState: _engine.activeDialog!,
                                    onDismiss: _engine.dismissDialog,
                                    correctAspectRatio: _correctAspectRatio,
                                    strictIntegerScaling: _strictIntegerScaling,
                                  ),
                                ),
                              if (_engine.activeInputPrompt != null)
                                Positioned.fill(
                                  child: InputPromptDialog(
                                    promptState: _engine.activeInputPrompt!,
                                    onChanged: _engine.updateInputPrompt,
                                    onSubmit: _engine.submitInputPrompt,
                                    onCancel: _engine.cancelInputPrompt,
                                  ),
                                ),
                              if (_engine.isInventoryOpen &&
                                  _engine.inspectingObjectNumber == null)
                                Positioned.fill(
                                  child: InventoryDialog(
                                    engine: _engine,
                                    onClose: () => _engine.closeInventory(),
                                    onSelect: (selectedObj) =>
                                        _engine.closeInventory(selectedObj),
                                    correctAspectRatio: _correctAspectRatio,
                                    strictIntegerScaling: _strictIntegerScaling,
                                  ),
                                ),
                              if (_engine.inspectingObjectNumber != null)
                                Positioned.fill(
                                  child: ObjectInspectionDialog(
                                    engine: _engine,
                                    objectNumber: _engine.inspectingObjectNumber!,
                                    onClose: _engine.closeObjectInspection,
                                    correctAspectRatio: _correctAspectRatio,
                                    strictIntegerScaling: _strictIntegerScaling,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlideoutPanel() {
    return SidebarSlideoutPanel(
      isOpen: _openPanelTab != null,
      activeTab: _openPanelTab ?? SidebarPanelTab.audio,
      engine: _engine,
      onTabChanged: (tab) => setState(() => _openPanelTab = tab),
      onClose: () => setState(() => _openPanelTab = null),
      showCrtShader: _showCrtShader,
      onCrtShaderChanged: (val) {
        setState(() => _showCrtShader = val);
        _safeUpdateDisplay(showCrtShader: val);
      },
      showPixelGrid: _showPixelGrid,
      onPixelGridChanged: (val) {
        setState(() => _showPixelGrid = val);
        _safeUpdateDisplay(showPixelGrid: val);
      },
      renderBlackTextBackgrounds: _renderBlackTextBackgrounds,
      onRenderBlackTextBackgroundsChanged: (val) {
        setState(() => _renderBlackTextBackgrounds = val);
        _safeUpdateDisplay(renderBlackTextBackgrounds: val);
      },
      correctAspectRatio: _correctAspectRatio,
      onAspectRatioChanged: (val) {
        setState(() => _correctAspectRatio = val);
        _safeUpdateDisplay(correctAspectRatio: val);
      },
      strictIntegerScaling: _strictIntegerScaling,
      onStrictIntegerScalingChanged: (val) {
        setState(() => _strictIntegerScaling = val);
        _safeUpdateDisplay(strictIntegerScaling: val);
      },
      renderMode: _renderMode,
      onRenderModeChanged: (mode) {
        setState(() => _renderMode = mode);
        _safeUpdateDisplay(renderMode: mode);
      },
    );
  }

  Widget _buildLeftSidebar() {
    return Container(
      width: 42,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(right: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),

          // Exit Game
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18, color: AgiTheme.egaCyan),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Exit Game',
          ),

          const Divider(height: 10, thickness: 1, color: AgiTheme.egaBorder),

          // Pause / Play toggle & Single Step (scoped to engine state)
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 18, color: AgiTheme.egaCyan),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: _engine.isPaused ? () => _engine.tick() : null,
                    tooltip: 'Step Single Cycle',
                  ),
                ],
              );
            },
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

          const Divider(height: 10, thickness: 1, color: AgiTheme.egaBorder),

          // Speed Selection
          PopupMenuButton<double>(
            initialValue: _engine.speedHz,
            tooltip: 'Cycle Speed (${_engine.speedHz.toStringAsFixed(1)} Hz)',
            icon: const Icon(Icons.speed, size: 18, color: AgiTheme.egaAmber),
            padding: EdgeInsets.zero,
            onSelected: (hz) => _engine.setSpeedHz(hz),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 10.0, child: Text('Slow (10 Hz / delay 3)')),
              PopupMenuItem(value: 20.0, child: Text('Normal (20 Hz / delay 2)')),
              PopupMenuItem(value: 30.0, child: Text('Fast (30 Hz / delay 1)')),
              PopupMenuItem(value: 60.0, child: Text('Fastest (60 Hz / delay 0)')),
            ],
          ),

          // Sound Options Slideout Button
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) {
              final isAudioOpen = _openPanelTab == SidebarPanelTab.audio;
              IconData soundIcon;
              Color soundColor;
              String soundLabel;

              if (!_engine.isSoundOn || _engine.soundMode == AgiSoundMode.off) {
                soundIcon = Icons.volume_off;
                soundColor = AgiTheme.egaMuted;
                soundLabel = 'Sound: OFF';
              } else {
                switch (_engine.soundMode) {
                  case AgiSoundMode.off:
                    soundIcon = Icons.volume_off;
                    soundColor = AgiTheme.egaMuted;
                    soundLabel = 'Sound: OFF';
                    break;
                  case AgiSoundMode.ibmPc:
                    soundIcon = Icons.speaker;
                    soundColor = AgiTheme.egaAmber;
                    soundLabel = 'Sound: IBM PC Speaker';
                    break;
                  case AgiSoundMode.pcJr:
                    soundIcon = Icons.volume_down;
                    soundColor = AgiTheme.egaCyan;
                    soundLabel = 'Sound: PCjr / Tandy 3-Voice';
                    break;
                  case AgiSoundMode.enhanced:
                    soundIcon = Icons.auto_awesome;
                    soundColor = AgiTheme.egaMagenta;
                    soundLabel = 'Sound: Enhanced Mode';
                    break;
                }
              }

              return Container(
                decoration: BoxDecoration(
                  color: isAudioOpen ? const Color(0xFF1E3A5F) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: Icon(soundIcon, size: 18, color: soundColor),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _openPanelTab = isAudioOpen ? null : SidebarPanelTab.audio;
                    });
                  },
                  tooltip: '$soundLabel (Click for Audio Panel / F2 toggle)',
                ),
              );
            },
          ),

          // Display / Video Options Slideout Button
          Builder(
            builder: (context) {
              final isVideoOpen = _openPanelTab == SidebarPanelTab.video;
              return Container(
                decoration: BoxDecoration(
                  color: isVideoOpen ? const Color(0xFF1E3A5F) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.tv,
                    size: 18,
                    color: isVideoOpen
                        ? AgiTheme.egaWhite
                        : (_showCrtShader || _showPixelGrid ? AgiTheme.egaCyan : AgiTheme.egaMuted),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _openPanelTab = isVideoOpen ? null : SidebarPanelTab.video;
                    });
                  },
                  tooltip: 'Display & Video Options',
                ),
              );
            },
          ),

          const Spacer(),

          // Restore last manual checkpoint, or last room-entry if none exist.
          ListenableBuilder(
            listenable: _engine,
            builder: (context, _) {
              final snap = _engine.lastRetryCheckpoint;
              return IconButton(
                icon: Icon(
                  Icons.restore,
                  size: 18,
                  color: snap == null ? AgiTheme.egaMuted : AgiTheme.egaAmber,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: snap == null
                    ? null
                    : () {
                        final label = snap.label;
                        _engine.restoreLastRetryCheckpoint();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Restored: $label',
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
                            ),
                            duration: const Duration(seconds: 2),
                            backgroundColor: AgiTheme.egaCardSurface,
                          ),
                        );
                      },
                tooltip: snap == null
                    ? 'Restore last checkpoint (none yet)'
                    : 'Restore: ${snap.label}',
              );
            },
          ),

          // Quick-Capture Checkpoint Snapshot (Instant save-state)
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, size: 18, color: AgiTheme.egaCyan),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {
              final snap = _engine.recordCheckpoint();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📸 Captured: ${snap.label}',
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
                  duration: const Duration(seconds: 2),
                  backgroundColor: AgiTheme.egaCardSurface,
                ),
              );
            },
            tooltip: 'Quick-Capture Checkpoint Snapshot',
          ),

          // Debug Inspector & Checkpoint button (F12)
          IconButton(
            icon: const Icon(Icons.bug_report, size: 18, color: AgiTheme.egaGreen),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () => DebugInspectorDialog.show(context, _engine),
            tooltip: 'Debug Inspector & Checkpoints (F12)',
          ),

          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
