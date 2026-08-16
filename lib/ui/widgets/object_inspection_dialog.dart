import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/object_view_resolver.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/widgets/cel_image_widget.dart';

/// Modal dialog for inspecting an individual inventory object (`show.obj` / `show.obj.v`).
///
/// Features:
/// - Displays object name and index
/// - Renders item sprite preview with authentic 2:1 EGA pixel aspect and transparency
/// - Displays embedded VIEW text description
/// - Keyboard shortcuts (Enter, Space, Escape) and mouse click dismissal
class ObjectInspectionDialog extends StatefulWidget {
  final AgiGameEngine? engine;
  final int objectNumber;
  final AgiObject? object;
  final AgiView? view;
  final String? description;
  final AgiResourceLoader? loader;
  final VoidCallback? onClose;

  const ObjectInspectionDialog({
    super.key,
    this.engine,
    required this.objectNumber,
    this.object,
    this.view,
    this.description,
    this.loader,
    this.onClose,
  });

  @override
  State<ObjectInspectionDialog> createState() => _ObjectInspectionDialogState();
}

class _ObjectInspectionDialogState extends State<ObjectInspectionDialog> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  AgiObject? _resolveObject() {
    if (widget.object != null) return widget.object;
    if (widget.engine != null &&
        widget.objectNumber >= 0 &&
        widget.objectNumber < widget.engine!.objects.length) {
      return widget.engine!.objects[widget.objectNumber];
    }
    return null;
  }

  AgiView? _resolveView(AgiObject? resolvedObject) {
    if (widget.view != null) return widget.view;
    final effectiveLoader = widget.loader ?? widget.engine?.resourceLoader;
    if (effectiveLoader == null) return null;

    final targetObj = resolvedObject ?? const AgiObject(name: '', startingRoom: 0);
    try {
      final viewNum = ObjectViewResolver.resolveViewNumber(
        objectIndex: widget.objectNumber,
        object: targetObj,
        loader: effectiveLoader,
      );
      if (effectiveLoader.presentViewNumbers.contains(viewNum)) {
        return effectiveLoader.loadView(viewNum);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedObj = _resolveObject();
    final resolvedView = _resolveView(resolvedObj);

    final rawName = resolvedObj?.name ?? 'Object #${widget.objectNumber}';
    final displayName = rawName.replaceAll('*', '').trim();
    final effectiveDescription = widget.description ??
        ((resolvedView?.description != null && resolvedView!.description!.trim().isNotEmpty)
            ? resolvedView.description!.trim()
            : null);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): () => widget.onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => widget.onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.space): () => widget.onClose?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () => widget.onClose?.call(),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            color: Colors.black.withValues(alpha: 0.70),
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {}, // Prevent tap inside dialog from closing
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 420,
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          Expanded(
                            child: Text(
                              displayName.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF55FFFF),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '#${widget.objectNumber}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Sprite Canvas Frame
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: (resolvedView != null &&
                                resolvedView.loops.isNotEmpty &&
                                resolvedView.loops[0].cels.isNotEmpty)
                            ? CelImageWidget(
                                view: resolvedView,
                                loopIndex: 0,
                                celIndex: 0,
                                scale: 3.5,
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 40,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                      ),
                    ),

                    // Description text if present
                    if (effectiveDescription != null && effectiveDescription.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFFCBD5E1),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            effectiveDescription,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                    // Footer Action Bar
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
                          const Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.keyboard_return,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Enter / Space / Esc to close',
                                    style: TextStyle(
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
                          ElevatedButton(
                            onPressed: widget.onClose,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
