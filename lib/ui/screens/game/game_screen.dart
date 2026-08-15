import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/dialog_box_widget.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';

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
      _engine = AgiGameEngine(resourceLoader: widget.resourceLoader);
      _engine.initializeGame(startingRoom: widget.startingRoom);
      _engine.start();
    }

    _engine.addListener(_onEngineUpdated);
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdated);
    if (widget.engine == null) {
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
    _promptFocusNode.requestFocus();
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // If modal dialog is open, Enter/Space/Escape dismisses it
    if (_engine.activeDialog != null) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        _engine.dismissDialog();
        return KeyEventResult.handled;
      }
    }

    // Direction controls when prompt is not exclusively capturing text
    final isPromptFocused = _promptFocusNode.hasFocus;

    if (!isPromptFocused) {
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
        case LogicalKeyboardKey.space:
          _engine.setEgoDirection(0); // Stop
          return KeyEventResult.handled;
      }
    } else {
      // History recall when prompt is focused
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _navigateHistory(-1);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _navigateHistory(1);
        return KeyEventResult.handled;
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
              _buildStatusBar(),
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
                      if (_engine.activeDialog != null)
                        Positioned.fill(
                          child: DialogBoxWidget(
                            dialogState: _engine.activeDialog!,
                            onDismiss: _engine.dismissDialog,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18, color: AgiTheme.egaCyan),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Exit Game',
          ),
          const SizedBox(width: 6),
          const Text(
            'AGI ENGINE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaWhite,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 16),

          // Pause / Play toggle
          IconButton(
            icon: Icon(
              _engine.isPaused ? Icons.play_arrow : Icons.pause,
              size: 18,
              color: _engine.isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
            ),
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
            onPressed: _engine.isPaused ? () => _engine.tick() : null,
            tooltip: 'Step Single Cycle',
          ),

          // Restart
          IconButton(
            icon: const Icon(Icons.replay, size: 18, color: AgiTheme.egaRed),
            onPressed: () => _engine.initializeGame(startingRoom: widget.startingRoom),
            tooltip: 'Restart Game',
          ),

          const Spacer(),

          // Speed Selection
          PopupMenuButton<double>(
            initialValue: _engine.speedHz,
            tooltip: 'Cycle Speed',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 14, color: AgiTheme.egaAmber),
                  const SizedBox(width: 4),
                  Text(
                    '${_engine.speedHz.toInt()} Hz',
                    style: const TextStyle(fontSize: 11, color: AgiTheme.egaAmber),
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
          const SizedBox(width: 8),

          // CRT Toggle
          IconButton(
            icon: Icon(
              Icons.tv,
              size: 18,
              color: _showCrtShader ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
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
            onPressed: () {
              setState(() {
                _showPixelGrid = !_showPixelGrid;
              });
            },
            tooltip: 'Toggle Pixel Grid',
          ),

          // Render Mode View Toggle
          PopupMenuButton<AgiPictureRenderMode>(
            initialValue: _renderMode,
            tooltip: 'View Layer Mode',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, size: 14, color: AgiTheme.egaCyan),
                  const SizedBox(width: 4),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          const Text(
            '> ',
            style: TextStyle(
              color: AgiTheme.egaWhite,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
          Expanded(
            child: TextField(
              controller: _promptController,
              focusNode: _promptFocusNode,
              style: const TextStyle(
                color: AgiTheme.egaWhite,
                fontSize: 14,
                fontFamily: 'Courier',
              ),
              cursorColor: AgiTheme.egaCyan,
              cursorWidth: 8,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Type a command (e.g. look around)...',
                hintStyle: TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 13,
                  fontFamily: 'Courier',
                ),
              ),
              onSubmitted: _handleSubmitCommand,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, size: 16, color: AgiTheme.egaCyan),
            onPressed: () => _handleSubmitCommand(_promptController.text),
            tooltip: 'Send Command (Enter)',
          ),
        ],
      ),
    );
  }
}
