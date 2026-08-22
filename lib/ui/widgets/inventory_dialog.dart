import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/object_inspection_dialog.dart';

/// Modal Inventory Screen widget (`status()` / Opcode 124).
///
/// Behavior follows authentic Sierra AGI interpreter mechanics:
/// - When Flag 13 is `false` (standard inventory viewing via Tab or "inventory" command):
///   - Displays carried items ("You are carrying:").
///   - 2-column responsive layout matching Sierra AGI screen organization.
///   - Clean viewing mode with keyboard (arrows, Enter, Space, Escape) and mouse navigation.
///   - Enter, Space, Escape, or tapping anywhere dismisses inventory and returns to the game.
/// - When Flag 13 is `true` (item selection mode e.g. "See Object", Black Cauldron "New Object", Gold Rush):
///   - Displays item selection prompt ("Select an object:").
///   - Full 2D grid navigation (Up/Down/Left/Right), auto-scrolling to keep active item in view.
///   - Enter or double-tap confirms selection (returning item ID to Variable 25).
///   - Escape or tapping outside aborts selection (Variable 25 = 255).
///
/// Visual Aesthetic:
/// - Solid white block with classic Sierra EGA dark red inner border (Color 4: #AA0000).
/// - Subtle modern drop shadow behind the dialog card.
/// - Proportional font scaling matching standard AGI dialog boxes.
/// - 2-column item grid with smooth auto-scrolling.
/// - No bulky OS window titles, badges, or buttons.
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
  final bool correctAspectRatio;
  final bool strictIntegerScaling;

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
    this.correctAspectRatio = true,
    this.strictIntegerScaling = false,
  });

  @override
  State<InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<InventoryDialog> {
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<GlobalKey> _itemKeys = [];

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
        _scrollToSelected();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureItemKeys(int count) {
    while (_itemKeys.length < count) {
      _itemKeys.add(GlobalKey());
    }
    while (_itemKeys.length > count) {
      _itemKeys.removeLast();
    }
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedIndex >= 0 && _selectedIndex < _itemKeys.length) {
        final keyContext = _itemKeys[_selectedIndex].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            alignment: 0.5,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
          );
        }
      }
    });
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
    _scrollToSelected();
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
      if (_selectedIndex >= 2) {
        _moveSelection(-2, carried.length);
      } else {
        _moveSelection(-_selectedIndex, carried.length);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_selectedIndex + 2 < carried.length) {
        _moveSelection(2, carried.length);
      } else if (_selectedIndex < carried.length - 1) {
        _moveSelection(carried.length - 1 - _selectedIndex, carried.length);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_selectedIndex > 0) {
        _moveSelection(-1, carried.length);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_selectedIndex < carried.length - 1) {
        _moveSelection(1, carried.length);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _moveSelection(-6, carried.length);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _moveSelection(6, carried.length);
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
    _ensureItemKeys(carried.length);

    if (_selectedIndex >= carried.length) {
      _selectedIndex = carried.isNotEmpty ? carried.length - 1 : 0;
    }
    final isSelect = _isSelectionMode;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => widget.onClose?.call(),
        if (carried.isEmpty || !isSelect) ...{
          const SingleActivator(LogicalKeyboardKey.enter): () => widget.onClose?.call(),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () => widget.onClose?.call(),
          const SingleActivator(LogicalKeyboardKey.space): () => widget.onClose?.call(),
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onClose?.call(),
          child: Container(
            color: Colors.transparent, // Authentic Sierra: no dark screen tint
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final availableHeight = constraints.maxHeight;
                if (availableWidth <= 0 || availableHeight <= 0) {
                  return const SizedBox.shrink();
                }

                final targetAspect = widget.correctAspectRatio ? (4.0 / 3.0) : (320.0 / 200.0);
                double playfieldWidth;
                double playfieldHeight;

                if (widget.strictIntegerScaling) {
                  final int baseWidth = 320;
                  final int baseHeight = widget.correctAspectRatio ? 240 : 200;
                  final maxScaleX = availableWidth ~/ baseWidth;
                  final maxScaleY = availableHeight ~/ baseHeight;
                  final scale = math.max(1, math.min(maxScaleX, maxScaleY));
                  playfieldWidth = (baseWidth * scale).toDouble();
                  playfieldHeight = (baseHeight * scale).toDouble();
                } else {
                  final containerAspect = availableWidth / availableHeight;
                  if (containerAspect > targetAspect) {
                    playfieldHeight = availableHeight;
                    playfieldWidth = availableHeight * targetAspect;
                  } else {
                    playfieldWidth = availableWidth;
                    playfieldHeight = availableWidth / targetAspect;
                  }
                }

                final fontSize = math.max(11.0, playfieldWidth / 48.0);
                final horizontalPadding = math.max(12.0, playfieldWidth * 0.018);
                final verticalPadding = math.max(10.0, playfieldHeight * 0.016);

                // 2-column wide card
                final maxCardWidth = math.max(
                  260.0,
                  math.min(playfieldWidth * 0.90, playfieldWidth * 0.72),
                );
                final maxCardHeight = playfieldHeight * 0.85;

                final borderWidth = math.max(2.0, (playfieldWidth / 400.0).roundToDouble());
                final shadowOffset = math.max(3.0, playfieldWidth * 0.004);
                final shadowBlur = math.max(4.0, playfieldWidth * 0.007);
                final effectiveMinWidth = math.min(math.max(160.0, playfieldWidth * 0.35), maxCardWidth);

                final int rowCount = (carried.length + 1) ~/ 2;

                return Center(
                  child: GestureDetector(
                    onTap: isSelect ? () {} : () => widget.onClose?.call(),
                    child: Container(
                      constraints: BoxConstraints(
                        minWidth: effectiveMinWidth,
                        maxWidth: maxCardWidth,
                        maxHeight: maxCardHeight,
                      ),
                      margin: EdgeInsets.all(math.max(4.0, playfieldWidth * 0.008)),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.white,
                          width: borderWidth,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x44000000), // Subtle modern drop shadow
                            offset: Offset(shadowOffset, shadowOffset),
                            blurRadius: shadowBlur,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFAA0000), // Classic Sierra EGA Red (Color 4)
                            width: borderWidth,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: verticalPadding,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Header / Title
                            if (carried.isNotEmpty || isSelect)
                              Padding(
                                padding: EdgeInsets.only(bottom: verticalPadding * 0.7),
                                child: Text(
                                  isSelect ? 'Select an object:' : 'You are carrying:',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                    height: 1.25,
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                              ),

                            // 2. Items Grid (2 Columns) or Empty State
                            if (carried.isEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: verticalPadding * 0.5),
                                child: Text(
                                  'You are carrying nothing.',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                  textAlign: isSelect ? TextAlign.left : TextAlign.center,
                                ),
                              )
                            else
                              Flexible(
                                child: Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: rowCount > 8,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    shrinkWrap: true,
                                    itemCount: rowCount,
                                    itemBuilder: (context, rowIndex) {
                                      final leftIndex = rowIndex * 2;
                                      final rightIndex = leftIndex + 1;

                                      final leftItem = carried[leftIndex];
                                      final rightItem = rightIndex < carried.length
                                          ? carried[rightIndex]
                                          : null;

                                      return Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: math.max(1.0, fontSize * 0.08),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            // Left Column Cell
                                            _buildItemCell(
                                              item: leftItem,
                                              index: leftIndex,
                                              isSelected: leftIndex == _selectedIndex,
                                              isSelect: isSelect,
                                              fontSize: fontSize,
                                              carried: carried,
                                            ),

                                            const SizedBox(width: 8),

                                            // Right Column Cell
                                            if (rightItem != null)
                                              _buildItemCell(
                                                item: rightItem,
                                                index: rightIndex,
                                                isSelected: rightIndex == _selectedIndex,
                                                isSelect: isSelect,
                                                fontSize: fontSize,
                                                carried: carried,
                                              )
                                            else
                                              const Expanded(child: SizedBox()),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                            // 3. Optional Instructions / Shortcut Hint
                            if (isSelect && carried.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: verticalPadding * 0.7),
                                child: Text(
                                  'Enter to select, Esc to cancel',
                                  style: TextStyle(
                                    color: const Color(0xFF666666),
                                    fontSize: math.max(10.0, fontSize * 0.80),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _formatItemName(String name) {
    if (widget.engine != null) {
      return widget.engine!.formatMessage(name);
    }
    final mem = widget.memory;
    if (mem != null) {
      return ObjectInspectionDialog.formatWithMemory(
        name,
        mem,
        loader: widget.engine?.resourceLoader,
      );
    }
    return name;
  }

  Widget _buildItemCell({
    required CarriedItem item,
    required int index,
    required bool isSelected,
    required bool isSelect,
    required double fontSize,
    required List<CarriedItem> carried,
  }) {
    return Expanded(
      child: InkWell(
        key: _itemKeys[index],
        onTap: () {
          setState(() => _selectedIndex = index);
          widget.onItemSelected?.call(item.index);
          _scrollToSelected();
          if (!isSelect) {
            widget.onClose?.call();
          }
        },
        onDoubleTap: () {
          setState(() => _selectedIndex = index);
          if (isSelect) {
            _handleSelectCurrent(carried);
          } else {
            widget.onClose?.call();
          }
        },
        child: Container(
          color: (isSelect && isSelected) ? const Color(0xFFE0F2FE) : Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: 4.0,
            vertical: math.max(2.0, fontSize * 0.14),
          ),
          child: Row(
            children: [
              if (isSelect)
                Text(
                  isSelected ? '> ' : '  ',
                  style: TextStyle(
                    color: const Color(0xFFAA0000),
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
              Expanded(
                child: Text(
                  _formatItemName(item.name.trim()),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: fontSize,
                    fontWeight: (isSelect && isSelected) ? FontWeight.bold : FontWeight.w500,
                    height: 1.25,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
