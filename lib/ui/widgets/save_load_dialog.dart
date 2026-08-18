import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/state/game_state_serializer.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/widgets/snapshot_thumbnail_widget.dart';

/// Operational mode for [SaveLoadDialog].
enum SaveLoadMode {
  save,
  restore,
}

/// Interactive 12-Slot Save & Restore Modal Dialog for Sierra AGI Games.
class SaveLoadDialog extends StatefulWidget {
  final AgiGameEngine engine;
  final SaveLoadMode mode;
  final Directory? directory;

  const SaveLoadDialog({
    super.key,
    required this.engine,
    required this.mode,
    this.directory,
  });

  /// Displays the Save Game modal dialog, pausing game execution while open.
  static Future<bool?> showSave(
    BuildContext context,
    AgiGameEngine engine, {
    Directory? directory,
  }) async {
    final wasPaused = engine.isPaused;
    if (!wasPaused) {
      engine.pause();
    }
    try {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => SaveLoadDialog(
          engine: engine,
          mode: SaveLoadMode.save,
          directory: directory,
        ),
      );
    } finally {
      if (!wasPaused) {
        engine.resume();
      }
    }
  }

  /// Displays the Restore Game modal dialog, pausing game execution while open.
  static Future<bool?> showRestore(
    BuildContext context,
    AgiGameEngine engine, {
    Directory? directory,
  }) async {
    final wasPaused = engine.isPaused;
    if (!wasPaused) {
      engine.pause();
    }
    try {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => SaveLoadDialog(
          engine: engine,
          mode: SaveLoadMode.restore,
          directory: directory,
        ),
      );
    } finally {
      if (!wasPaused) {
        engine.resume();
      }
    }
  }

  /// Displays the Restart Confirmation dialog per Sierra AGI Opcode 128 (`restart.game`),
  /// pausing game execution while open.
  static Future<bool?> showRestartConfirmation(
    BuildContext context,
    AgiGameEngine engine,
  ) async {
    final wasPaused = engine.isPaused;
    if (!wasPaused) {
      engine.pause();
    }
    try {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => RestartConfirmationDialog(engine: engine),
      );
    } finally {
      if (!wasPaused) {
        engine.resume();
      }
    }
  }

  @override
  State<SaveLoadDialog> createState() => _SaveLoadDialogState();
}

class _SaveLoadDialogState extends State<SaveLoadDialog> {
  static const int _totalSlots = 12;

  List<SaveSlotInfo> _slots = [];
  bool _isLoading = true;
  int _selectedSlot = 1;
  final TextEditingController _descController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _dialogFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _descController.dispose();
    _inputFocusNode.dispose();
    _dialogFocusNode.dispose();
    super.dispose();
  }

  void _loadSlots() {
    final slots = GameStateSerializer.listSlotsSync(
      directory: widget.directory ?? widget.engine.saveDirectory,
      maxSlots: _totalSlots,
    );

    setState(() {
      _slots = slots;
      _isLoading = false;

      // In save mode, default to first empty slot or slot 1
      if (widget.mode == SaveLoadMode.save) {
        final emptyIdx = slots.indexWhere((s) => !s.exists);
        _selectedSlot = (emptyIdx != -1) ? emptyIdx + 1 : 1;
        _descController.text = _getDefaultSaveDescription();
      } else {
        // In restore mode, default to first populated slot
        final firstPopulated = slots.indexWhere((s) => s.exists);
        _selectedSlot = (firstPopulated != -1) ? firstPopulated + 1 : 1;
      }
    });
  }

  String _getDefaultSaveDescription() {
    final currentSlot = _slots.firstWhere(
      (s) => s.slot == _selectedSlot,
      orElse: () => SaveSlotInfo(
        slot: _selectedSlot,
        description: '',
        timestamp: DateTime.now(),
        roomNumber: widget.engine.currentRoom,
        score: widget.engine.memory.getVar(3),
        maxScore: widget.engine.memory.getVar(7),
        filePath: '',
        exists: false,
      ),
    );

    if (currentSlot.exists && currentSlot.description.isNotEmpty) {
      return currentSlot.description;
    }
    return 'Room ${widget.engine.currentRoom} (Score: ${widget.engine.memory.getVar(3)})';
  }

  void _onSlotSelected(int slot) {
    setState(() {
      _selectedSlot = slot;
      if (widget.mode == SaveLoadMode.save) {
        _descController.text = _getDefaultSaveDescription();
      }
    });
  }

  void _handleConfirm() {
    if (widget.mode == SaveLoadMode.save) {
      final desc = _descController.text.trim();
      final finalDesc = desc.isNotEmpty ? desc : 'Slot $_selectedSlot Save';

      GameStateSerializer.saveToSlotSync(
        widget.engine,
        _selectedSlot,
        description: finalDesc,
        directory: widget.directory ?? widget.engine.saveDirectory,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      // Restore mode
      final selectedSlotInfo = _slots.firstWhere(
        (s) => s.slot == _selectedSlot,
        orElse: () => _slots.first,
      );

      if (!selectedSlotInfo.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected slot is empty.'),
            backgroundColor: Color(0xFFAA0000),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final success = GameStateSerializer.restoreFromSlotSync(
        widget.engine,
        _selectedSlot,
        directory: widget.directory ?? widget.engine.saveDirectory,
      );

      if (mounted) {
        Navigator.of(context).pop(success);
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_selectedSlot > 1) {
        _onSlotSelected(_selectedSlot - 1);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_selectedSlot < _totalSlots) {
        _onSlotSelected(_selectedSlot + 1);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _handleConfirm();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isSave = widget.mode == SaveLoadMode.save;
    final title = isSave ? 'SAVE GAME STATE' : 'RESTORE GAME STATE';
    final headerColor = isSave ? const Color(0xFF00AA00) : AgiTheme.egaCyan;

    return Focus(
      focusNode: _dialogFocusNode,
      autofocus: !isSave,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 540,
            maxHeight: 460,
          ),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B), // Retro slate chassis
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF475569),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                offset: Offset(8, 8),
                blurRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF334155), width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: headerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: TextStyle(
                          color: headerColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                        onPressed: () => Navigator.of(context).pop(false),
                        splashRadius: 16,
                        tooltip: 'Cancel (ESC)',
                      ),
                    ],
                  ),
                ),

                // 2. Slot List
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(color: AgiTheme.egaCyan),
                    ),
                  )
                else
                  Flexible(
                    child: Container(
                      color: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _slots.length,
                        itemBuilder: (ctx, index) {
                          final slotInfo = _slots[index];
                          final isSelected = slotInfo.slot == _selectedSlot;
                          final isPopulated = slotInfo.exists;

                          return InkWell(
                            onTap: () => _onSlotSelected(slotInfo.slot),
                            onDoubleTap: _handleConfirm,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0284C7)
                                    : (index % 2 == 0
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFF172033)),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF38BDF8)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Slot Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF0369A1)
                                          : const Color(0xFF334155),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${slotInfo.slot}'.padLeft(2, '0'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Thumbnail preview for populated slots
                                  if (isPopulated && slotInfo.thumbnailRgba != null) ...[
                                    SnapshotThumbnailWidget(
                                      thumbnailRgba: slotInfo.thumbnailRgba,
                                      width: 52,
                                      height: 39,
                                      borderColor: isSelected
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF334155),
                                    ),
                                    const SizedBox(width: 10),
                                  ],

                                  // Description & Metadata
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isPopulated
                                              ? slotInfo.description
                                              : '< Empty Save Slot >',
                                          style: TextStyle(
                                            color: isPopulated
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (isPopulated)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Room ${slotInfo.roomNumber} • Score ${slotInfo.score}/${slotInfo.maxScore} • ${slotInfo.formattedDate}',
                                              style: TextStyle(
                                                color: isSelected
                                                    ? const Color(0xFFE0F2FE)
                                                    : const Color(0xFF94A3B8),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Status Indicator
                                  if (isPopulated)
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: Color(0xFF22C55E),
                                      size: 16,
                                    )
                                  else
                                    const Icon(
                                      Icons.radio_button_unchecked,
                                      color: Color(0xFF475569),
                                      size: 16,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 3. Save Description Input (Save Mode Only)
                if (isSave)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      border: Border(
                        top: BorderSide(color: Color(0xFF334155), width: 1.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SAVE DESCRIPTION:',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _descController,
                          focusNode: _inputFocusNode,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Enter save name...',
                            hintStyle: const TextStyle(color: Color(0xFF64748B)),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: Color(0xFF475569)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: AgiTheme.egaCyan, width: 1.5),
                            ),
                          ),
                          onSubmitted: (_) => _handleConfirm(),
                        ),
                      ],
                    ),
                  ),

                // 4. Action Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      top: BorderSide(color: Color(0xFF334155), width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Up/Down: Select • Enter: Confirm • Esc: Cancel',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _handleConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSave
                              ? const Color(0xFF059669)
                              : const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text(
                          isSave ? 'Save Game' : 'Restore Game',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal Confirmation Dialog for `restart.game` (Opcode 128).
class RestartConfirmationDialog extends StatelessWidget {
  final AgiGameEngine engine;

  const RestartConfirmationDialog({
    super.key,
    required this.engine,
  });

  void _confirmRestart(BuildContext context) {
    engine.restartGame();
    Navigator.of(context).pop(true);
  }

  void _cancelRestart(BuildContext context) {
    engine.cancelRestart();
    Navigator.of(context).pop(false);
  }

  KeyEventResult _handleKeyEvent(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      _confirmRestart(context);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyN ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelRestart(context);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(context, event),
      child: Center(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFDC2626), width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF991B1B),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'RESTART GAME CONFIRMATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Text(
                    'Are you sure you want to restart the game? (Y/N)\n\nAll unsaved progress will be lost.',
                    style: TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(
                      top: BorderSide(color: Color(0xFF334155), width: 1.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _cancelRestart(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                        ),
                        child: const Text('Cancel [N]'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _confirmRestart(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'Restart [Y]',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
