import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';

/// Modal Inventory Screen widget (`status()` / Opcode 124).
///
/// Behavior follows authentic Sierra AGI interpreter mechanics:
/// - When Flag 13 is `false` (standard inventory viewing via Tab or "inventory" command):
///   - Displays carried items ("YOU ARE CARRYING").
///   - Clean viewing mode with keyboard navigation.
///   - Enter, Space, Escape, or "Close" button dismisses inventory and returns to the game.
/// - When Flag 13 is `true` (item selection mode e.g. "See Object", Black Cauldron "New Object", Gold Rush):
///   - Displays item selection prompt ("SELECT AN OBJECT").
///   - Enter, double-click, or "Select" button selects the item and returns its ID to Variable 25.
///   - Escape or "Cancel" button aborts selection (Variable 25 = 255).
///   - The game's logic scripts then decide what to do (e.g. calling `show.obj.v(selected + offset)`).
class InventoryDialog extends StatefulWidget {
  final AgiGameEngine? engine;
  final List<CarriedItem>? items;
  final List<AgiObject>? objects;
  final AgiMemory? memory;
  final VoidCallback? onClose;
  final ValueChanged<int>? onItemSelected;
  final ValueChanged<int>? onSelect;
  final bool? isSelectionMode;
  final int? initialSelectedObject;

  const InventoryDialog({
    super.key,
    this.engine,
    this.items,
    this.objects,
    this.memory,
    this.onClose,
    this.onItemSelected,
    this.onSelect,
    this.isSelectionMode,
    this.initialSelectedObject,
  });

  @override
  State<InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<InventoryDialog> {
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool get _isSelectionMode =>
      widget.isSelectionMode ??
      widget.engine?.memory.getFlag(13) ??
      widget.memory?.getFlag(13) ??
      false;

  @override
  void initState() {
    super.initState();
    final isSelect = _isSelectionMode;
    if (isSelect) {
      final initialObj =
          widget.initialSelectedObject ??
          widget.engine?.memory.getVar(25) ??
          widget.memory?.getVar(25);
      if (initialObj != null && initialObj != 255) {
        final carried = _resolveCarriedItems();
        final found = carried.indexWhere((c) => c.index == initialObj);
        if (found >= 0) {
          _selectedIndex = found;
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<CarriedItem> _resolveCarriedItems() {
    if (widget.items != null) {
      return widget.items!;
    }
    if (widget.engine != null) {
      return widget.engine!.getCarriedItems();
    }
    if (widget.objects != null) {
      final mem = widget.memory;
      final carried = <CarriedItem>[];
      for (int i = 0; i < widget.objects!.length; i++) {
        final obj = widget.objects![i];
        if (obj.name == '?' || obj.name.trim().isEmpty) continue;
        final room = mem?.itemRooms[i] ?? obj.startingRoom;
        if (room == 255) {
          carried.add(CarriedItem(index: i, object: obj));
        }
      }
      return carried;
    }
    return const [];
  }

  void _moveSelection(int delta, int totalItems) {
    if (totalItems <= 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, totalItems - 1);
    });
    final carried = _resolveCarriedItems();
    if (_selectedIndex >= 0 && _selectedIndex < carried.length) {
      widget.onItemSelected?.call(carried[_selectedIndex].index);
    }
  }

  void _handleSelectCurrent(List<CarriedItem> carried) {
    if (carried.isNotEmpty && _selectedIndex >= 0 && _selectedIndex < carried.length) {
      final selectedItem = carried[_selectedIndex];
      widget.onSelect?.call(selectedItem.index);
    }
    widget.onClose?.call();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final carried = _resolveCarriedItems();
    final isSelect = _isSelectionMode;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }

    if (carried.isEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        widget.onClose?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, carried.length);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, carried.length);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isSelect) {
        _handleSelectCurrent(carried);
      } else {
        widget.onClose?.call();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.space && !isSelect) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final carried = _resolveCarriedItems();
    if (_selectedIndex >= carried.length) {
      _selectedIndex = carried.isNotEmpty ? carried.length - 1 : 0;
    }
    final isSelect = _isSelectionMode;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => widget.onClose?.call(),
        child: Container(
          color: Colors.black.withValues(alpha: 0.70),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {}, // Prevent click inside dialog card from dismissing
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 480,
                minWidth: 300,
                maxHeight: 520,
              ),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F6),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF1E293B),
                  width: 3,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(6, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF334155), width: 2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.backpack,
                          color: Color(0xFF55FFFF),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isSelect ? 'SELECT AN OBJECT' : 'YOU ARE CARRYING',
                            style: const TextStyle(
                              color: Color(0xFF55FFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        if (carried.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${carried.length} item${carried.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Content Area
                  Flexible(
                    child: carried.isEmpty
                        ? _buildEmptyState()
                        : _buildItemList(carried, isSelect),
                  ),

                  // Footer Actions Bar
                  _buildFooter(carried, isSelect),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 16),
          Text(
            'You are carrying nothing.',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<CarriedItem> carried, bool isSelect) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: carried.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final item = carried[index];
          final isSelected = index == _selectedIndex;
          final displayName = item.name.trim();

          return InkWell(
            onTap: () {
              setState(() => _selectedIndex = index);
              widget.onItemSelected?.call(item.index);
            },
            onDoubleTap: () {
              setState(() => _selectedIndex = index);
              if (isSelect) {
                _handleSelectCurrent(carried);
              } else {
                widget.onClose?.call();
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE0F2FE) : Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                  width: isSelected ? 2.0 : 1.0,
                ),
                boxShadow: isSelected
                    ? const [
                        BoxShadow(
                          color: Color(0x220284C7),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // Indicator Icon
                  Icon(
                    isSelected ? Icons.arrow_right : Icons.fiber_manual_record,
                    size: isSelected ? 20 : 8,
                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),

                  // Item Index Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFBAE6FD) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '#${item.index}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Item Name
                  Expanded(
                    child: Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? const Color(0xFF0C4A6E) : const Color(0xFF0F172A),
                      ),
                    ),
                  ),

                  // Action Hint for selected item in selection mode
                  if (isSelected && isSelect)
                    const Text(
                      'Enter to select',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(List<CarriedItem> carried, bool isSelect) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        border: Border(
          top: BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.keyboard,
                  size: 14,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    carried.isEmpty
                        ? (isSelect ? 'Enter / Esc to cancel' : 'Enter / Space / Esc to close')
                        : (isSelect
                            ? '↑/↓ Navigate  •  Enter Select  •  Esc Cancel'
                            : '↑/↓ Navigate  •  Enter / Space / Esc Close'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (carried.isNotEmpty && isSelect) ...[
                ElevatedButton(
                  onPressed: () => _handleSelectCurrent(carried),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Select',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                onPressed: () => widget.onClose?.call(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFF94A3B8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text(
                  isSelect
                      ? 'Cancel'
                      : (carried.isEmpty ? 'OK' : 'Close'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
