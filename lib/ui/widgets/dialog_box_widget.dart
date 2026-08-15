import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';

/// Modal / Positional Retro EGA Dialog Box widget with modern Unicode-ready typography.
class DialogBoxWidget extends StatelessWidget {
  final AgiDialogState dialogState;
  final VoidCallback onDismiss;

  const DialogBoxWidget({
    super.key,
    required this.dialogState,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): onDismiss,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): onDismiss,
        const SingleActivator(LogicalKeyboardKey.space): onDismiss,
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: dialogState.isModal ? onDismiss : null,
          child: Container(
            color: dialogState.isModal
                ? Colors.black.withValues(alpha: 0.65)
                : Colors.transparent,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {}, // Prevent dismissal when tapping inside the box
              child: _buildDialogCard(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogCard(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 480,
        minWidth: 260,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F6), // Clean retro-modern light background
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
                const Text(
                  'SIERRA AGI MESSAGE',
                  style: TextStyle(
                    color: Color(0xFF55FFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),

          // Message Body with Modern Unicode-Capable Typography
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(
              dialogState.message,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.45,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.left,
            ),
          ),

          // Dismiss Action Footer
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
                const Row(
                  children: [
                    Icon(
                      Icons.keyboard_return,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Press Enter or Space',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: onDismiss,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'OK',
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
