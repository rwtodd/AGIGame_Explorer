import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';

/// Modal input prompt dialog for `get.string` (Opcode 115) and `get.num` (Opcode 118).
class InputPromptDialog extends StatefulWidget {
  final AgiInputPromptState promptState;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const InputPromptDialog({
    super.key,
    required this.promptState,
    this.onChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<InputPromptDialog> createState() => _InputPromptDialogState();
}

class _InputPromptDialogState extends State<InputPromptDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.promptState.currentText);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final isNumeric = widget.promptState.type == AgiInputPromptType.number;

    // In authentic AGI, on-screen prompts (row != null) are typed directly on the playfield
    // with 0 screen occlusion.
    if (widget.promptState.row != null) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focusNode.requestFocus(),
          child: SizedBox.expand(
            child: Opacity(
              opacity: 0.0,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLength: widget.promptState.maxLen > 0 ? widget.promptState.maxLen : null,
                keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
                inputFormatters: isNumeric ? [FilteringTextInputFormatter.digitsOnly] : null,
                textInputAction: TextInputAction.done,
                onChanged: (val) {
                  widget.onChanged?.call(val);
                },
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {}, // Prevent dismissal when tapping inside card
          child: _buildDialogCard(context, isNumeric),
        ),
      ),
    );
  }

  Widget _buildDialogCard(BuildContext context, bool isNumeric) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 460,
        minWidth: 280,
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
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AgiTheme.egaCyan,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isNumeric ? 'SIERRA AGI NUMERIC INPUT' : 'SIERRA AGI INPUT PROMPT',
                  style: const TextStyle(
                    color: Color(0xFF55FFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),

          // Message Body & Input Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.promptState.prompt.isNotEmpty) ...[
                  Text(
                    widget.promptState.prompt,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLength: widget.promptState.maxLen > 0 ? widget.promptState.maxLen : null,
                  keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
                  inputFormatters: isNumeric ? [FilteringTextInputFormatter.digitsOnly] : null,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Courier',
                  ),
                  decoration: InputDecoration(
                    hintText: isNumeric ? 'Enter number (0 - 255)...' : 'Type here...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ],
            ),
          ),

          // Action Buttons Footer
          Container(
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
                TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text(
                    'Cancel (Esc)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Submit (Enter)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
