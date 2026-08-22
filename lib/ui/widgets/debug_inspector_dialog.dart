import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/screens/browsers/logic_browser_screen.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_agigame/ui/widgets/snapshot_thumbnail_widget.dart';

/// Full-window modal workbench for inspecting live AGI engine state, managing checkpoints (save-states),
/// generating before/after diffs, and stepping or unpausing with an embedded 1x live screen.
class DebugInspectorDialog extends StatefulWidget {
  final AgiGameEngine engine;

  const DebugInspectorDialog({
    super.key,
    required this.engine,
  });

  static Future<void> show(BuildContext context, AgiGameEngine engine) {
    engine.pause();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => DebugInspectorDialog(engine: engine),
    );
  }

  @override
  State<DebugInspectorDialog> createState() => _DebugInspectorDialogState();
}

class _DebugInspectorDialogState extends State<DebugInspectorDialog>
  with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _checkpointLabelController = TextEditingController();
  final TextEditingController _searchFilterController = TextEditingController();
  final TextEditingController _watchSpecController = TextEditingController();
  final TextEditingController _teleportRoomController = TextEditingController();

  int _checkpointFilterIndex = 0;
  int? _diffBeforeIndex;
  int? _diffAfterIndex;
  String? _computedDiffMarkdown;
  /// In-progress variable edits (typed but not yet SET/PIN'd).
  final Map<int, int> _pendingVarEdits = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    widget.engine.addListener(_onEngineUpdate);

    if (widget.engine.checkpointHistory.isNotEmpty) {
      _diffAfterIndex = 0;
      if (widget.engine.checkpointHistory.length > 1) {
        _diffBeforeIndex = 1;
      }
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineUpdate);
    _tabController.dispose();
    _checkpointLabelController.dispose();
    _searchFilterController.dispose();
    _watchSpecController.dispose();
    _teleportRoomController.dispose();
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleTakeSnapshot() {
    final label = _checkpointLabelController.text.trim();
    final snap = widget.engine.recordCheckpoint(label: label);
    _checkpointLabelController.clear();
    setState(() {
      _diffAfterIndex = 0;
      if (widget.engine.checkpointHistory.length > 1) {
        _diffBeforeIndex = 1;
      }
      _computedDiffMarkdown = null;
    });
    _showToast('📸 Snapshot captured: ${snap.label}');
  }

  void _handleCopyCurrentJson() {
    final snap = widget.engine.createSnapshot();
    final jsonStr = snap.toJsonString(pretty: true, includeThumbnail: false);
    Clipboard.setData(ClipboardData(text: jsonStr));
    _showToast('📋 Current State JSON (no thumbnail) copied to clipboard!');
  }

  void _handleCopyDiff() {
    if (_computedDiffMarkdown != null && _computedDiffMarkdown!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _computedDiffMarkdown!));
      _showToast('📋 Markdown Diff copied to clipboard!');
    }
  }

  void _handleComputeDiff() {
    final history = widget.engine.checkpointHistory;
    if (_diffBeforeIndex == null ||
        _diffAfterIndex == null ||
        _diffBeforeIndex! >= history.length ||
        _diffAfterIndex! >= history.length) {
      return;
    }

    final beforeSnap = history[_diffBeforeIndex!];
    final afterSnap = history[_diffAfterIndex!];
    final diff = AgiGameStateDiff(beforeSnap, afterSnap);
    setState(() {
      _computedDiffMarkdown = diff.toMarkdown();
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Courier', fontSize: 12)),
        duration: const Duration(seconds: 2),
        backgroundColor: AgiTheme.egaCardSurface,
      ),
    );
  }

  void _handleTeleport({int? roomNumber, bool closeInspector = false}) {
    final targetRoom = roomNumber ?? int.tryParse(_teleportRoomController.text.trim());
    if (targetRoom == null || targetRoom < 0 || targetRoom > 255) {
      _showToast('⚠️ Please enter a valid room number (0–255)');
      return;
    }

    _teleportRoomController.text = targetRoom.toString();
    widget.engine.changeRoom(targetRoom);
    // Execute a cycle to load and initialize room pictures, objects, and scripts
    widget.engine.tick();
    widget.engine.recordCheckpoint(label: 'Teleport to Room $targetRoom');

    _showToast('🚀 Teleported to Room $targetRoom');

    if (closeInspector) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  void _showTeleportDialog() {
    final allPresentLogics = widget.engine.resourceLoader?.presentLogicNumbers.toList() ?? [];
    allPresentLogics.sort();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AgiTheme.egaCyan, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.flight_takeoff, color: AgiTheme.egaCyan, size: 20),
              SizedBox(width: 8),
              Text(
                'TELEPORT TO ROOM',
                style: TextStyle(
                  color: AgiTheme.egaWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a room number to warp Ego immediately. Choose to inspect live state in the debugger or return directly to gameplay.',
                  style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _teleportRoomController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 13, color: AgiTheme.egaWhite),
                        decoration: InputDecoration(
                          hintText: 'Room # (0–255)',
                          hintStyle: const TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: AgiTheme.egaBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: AgiTheme.egaCyan),
                          ),
                        ),
                        onSubmitted: (val) {
                          final r = int.tryParse(val.trim());
                          if (r != null) {
                            Navigator.of(ctx).pop();
                            _handleTeleport(roomNumber: r);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (allPresentLogics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Available Rooms / Logics:',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: allPresentLogics.where((l) => l != 0).map((r) {
                          final isCurrent = r == widget.engine.currentRoom;
                          return ActionChip(
                            label: Text(
                              'Room $r${isCurrent ? " (Current)" : ""}',
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan,
                              ),
                            ),
                            backgroundColor: (isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan).withValues(alpha: 0.12),
                            side: BorderSide(
                              color: (isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan).withValues(alpha: 0.6),
                              width: 1,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _handleTeleport(roomNumber: r);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AgiTheme.egaMuted)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final r = int.tryParse(_teleportRoomController.text.trim());
                if (r != null) {
                  Navigator.of(ctx).pop();
                  _handleTeleport(roomNumber: r);
                }
              },
              icon: const Icon(Icons.flash_on, size: 14, color: Colors.black),
              label: const Text('Teleport (Inspect)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AgiTheme.egaCyan),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final r = int.tryParse(_teleportRoomController.text.trim());
                if (r != null) {
                  Navigator.of(ctx).pop();
                  _handleTeleport(roomNumber: r, closeInspector: true);
                }
              },
              icon: const Icon(Icons.play_arrow, size: 14, color: Colors.black),
              label: const Text('Teleport & Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AgiTheme.egaGreen),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AgiTheme.egaDarkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AgiTheme.egaBorder, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            const Divider(color: AgiTheme.egaBorder, height: 1),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLeftGameViewAndStats(),
                  const SizedBox(width: 12),
                  const VerticalDivider(color: AgiTheme.egaBorder, width: 1),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        _buildTabBar(),
                        const Divider(color: AgiTheme.egaBorder, height: 12),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildCheckpointsTab(),
                              _buildVariablesAndFlagsTab(),
                              _buildObjectsTab(),
                              _buildLogicAndSystemTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isPaused = widget.engine.isPaused;

    return Row(
      children: [
        const Icon(Icons.bug_report, color: AgiTheme.egaCyan, size: 20),
        const SizedBox(width: 6),
        const Flexible(
          child: Text(
            'AGI DEBUG WORKBENCH',
            style: TextStyle(
              color: AgiTheme.egaWhite,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),

        // Pause / Resume Engine Button
        OutlinedButton.icon(
          onPressed: () {
            if (isPaused) {
              widget.engine.resume();
            } else {
              widget.engine.pause();
            }
          },
          icon: Icon(
            isPaused ? Icons.play_arrow : Icons.pause,
            size: 15,
            color: isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
          ),
          label: Text(
            isPaused ? 'Resume' : 'Pause',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
              width: 1.2,
            ),
            backgroundColor: (isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber).withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),

        // Step Frame Button
        OutlinedButton.icon(
          onPressed: () {
            widget.engine.tick();
          },
          icon: const Icon(Icons.skip_next, size: 15, color: AgiTheme.egaCyan),
          label: const Text(
            'Step Frame',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaCyan,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AgiTheme.egaCyan, width: 1.2),
            backgroundColor: AgiTheme.egaCyan.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),

        // Capture Snapshot in Header
        OutlinedButton.icon(
          onPressed: _handleTakeSnapshot,
          icon: const Icon(Icons.camera_alt_outlined, size: 15, color: Color(0xFF22C55E)),
          label: const Text(
            'Capture Snapshot',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF22C55E),
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF22C55E), width: 1.2),
            backgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),

        // Teleport Button in Header
        OutlinedButton.icon(
          onPressed: _showTeleportDialog,
          icon: const Icon(Icons.flight_takeoff, size: 15, color: AgiTheme.egaAmber),
          label: const Text(
            'Teleport',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaAmber,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AgiTheme.egaAmber, width: 1.2),
            backgroundColor: AgiTheme.egaAmber.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            visualDensity: VisualDensity.compact,
          ),
        ),

        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.close, color: AgiTheme.egaMuted, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close Inspector & Return to Game',
        ),
      ],
    );
  }

  Widget _buildLeftGameViewAndStats() {
    final engine = widget.engine;
    final mem = engine.memory;
    final ego = engine.ego;

    return SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1x Screen Title
            Row(
              children: [
                const Icon(Icons.tv, size: 14, color: AgiTheme.egaCyan),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    'LIVE 1X VIEWPORT',
                    style: TextStyle(
                      color: AgiTheme.egaCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: engine.isPaused
                        ? AgiTheme.egaAmber.withValues(alpha: 0.2)
                        : AgiTheme.egaGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: engine.isPaused ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    engine.isPaused ? 'PAUSED' : 'RUNNING',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: engine.isPaused ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Embedded 1x Game Screen (320x240, 4:3 corrected, no CRT)
            Container(
              width: 320,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: AgiTheme.egaBorder, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GamePlayfieldWidget(
                      engine: engine,
                      renderMode: AgiPictureRenderMode.compositedSlices,
                      showCrtShader: false,
                      showPixelGrid: false,
                      correctAspectRatio: true,
                      strictIntegerScaling: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Live Engine & Ego Metrics Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AgiTheme.egaCardSurface,
                border: Border.all(color: AgiTheme.egaBorder),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ENGINE & EGO METRICS',
                    style: TextStyle(
                      color: AgiTheme.egaWhite,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Divider(color: AgiTheme.egaBorder, height: 12),
                  _buildMetricRow('Room Number:', '${engine.currentRoom} (prev: ${mem.getVar(1)})'),
                  _buildMetricRow('Cycle Count:', '${engine.cycleCount}'),
                  _buildMetricRow('Score / Max:', '${mem.getVar(3)} / ${mem.getVar(7)}'),
                  _buildMetricRow('Execution Speed:', '${engine.speedHz.toStringAsFixed(1)} Hz (v10: ${mem.getVar(10)})'),
                  _buildMetricRow('Ego Position (x, y):', '(${ego.x}, ${ego.y})'),
                  _buildMetricRow('Ego Priority:', '${ego.priority}${ego.fixedPriority ? " (fixed)" : " (auto)"}'),
                  _buildMetricRow('Ego Direction (v6):', '${ego.direction}'),
                  _buildMetricRow('Ego View/Loop/Cel:', 'v${ego.view} / l${ego.loop} / c${ego.cel}'),
                  _buildMetricRow('User Control:', engine.isUserControl ? 'YES' : 'NO (program.control)'),
                  _buildMetricRow('Sound Enabled (f9):', engine.isSoundOn ? 'ON (${engine.soundMode.name})' : 'OFF'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted, fontFamily: 'Courier'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              color: AgiTheme.egaCyan,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      labelColor: AgiTheme.egaCyan,
      unselectedLabelColor: AgiTheme.egaMuted,
      indicatorColor: AgiTheme.egaCyan,
      indicatorWeight: 2.5,
      tabs: const [
        Tab(text: 'Checkpoints & Diff'),
        Tab(text: 'Variables & Flags'),
        Tab(text: 'Animated Objects'),
        Tab(text: 'Logic & Stack'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Checkpoints & Diff
  // ---------------------------------------------------------------------------

  Widget _buildCheckpointsTab() {
    final allHistory = widget.engine.checkpointHistory;
    final manualCount = allHistory.where((s) => !s.isRoomTransition).length;
    final roomCount = widget.engine.roomCheckpoints.length;

    List<AgiGameStateSnapshot> displayedSnapshots;
    if (_checkpointFilterIndex == 1) {
      displayedSnapshots = allHistory.where((s) => !s.isRoomTransition).toList();
    } else if (_checkpointFilterIndex == 2) {
      displayedSnapshots = widget.engine.roomCheckpoints;
    } else {
      displayedSnapshots = allHistory;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Checkpoint Actions & History List
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkpointLabelController,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Snapshot label (e.g. "Before climbing tree")',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: _handleTakeSnapshot,
                    icon: const Icon(Icons.camera_alt, size: 14),
                    label: const Text('Capture', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _handleCopyCurrentJson,
                    icon: const Icon(Icons.copy, size: 13),
                    label: const Text('Copy State JSON', style: TextStyle(fontSize: 10)),
                  ),
                  if (allHistory.isNotEmpty)
                    TextButton(
                      onPressed: () => widget.engine.clearCheckpoints(),
                      child: const Text('Clear History', style: TextStyle(fontSize: 10, color: AgiTheme.egaRed)),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Filter Segment Buttons
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildFilterChip('All (${allHistory.length})', 0),
                  _buildFilterChip('📸 Manual ($manualCount)', 1),
                  _buildFilterChip('🚪 Room Entry ($roomCount)', 2),
                ],
              ),
              const SizedBox(height: 6),

              // Checkpoint Cards List
              Expanded(
                child: displayedSnapshots.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AgiTheme.egaCardSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgiTheme.egaBorder),
                        ),
                        child: Text(
                          _checkpointFilterIndex == 2
                              ? 'No room transitions recorded yet.\nWalk between rooms to automatically capture breadcrumbs.'
                              : 'No checkpoints captured yet.\nClick "Capture" to record a state snapshot.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        itemCount: displayedSnapshots.length,
                        itemBuilder: (ctx, idx) {
                          final snap = displayedSnapshots[idx];
                          final originalIndex = allHistory.indexOf(snap);
                          final isSelectedBefore = _diffBeforeIndex == originalIndex;
                          final isSelectedAfter = _diffAfterIndex == originalIndex;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: (isSelectedBefore || isSelectedAfter)
                                  ? const Color(0xFF1F2D3D)
                                  : AgiTheme.egaCardSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelectedAfter
                                    ? AgiTheme.egaCyan
                                    : (isSelectedBefore ? AgiTheme.egaAmber : AgiTheme.egaBorder),
                                width: (isSelectedBefore || isSelectedAfter) ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Thumbnail Preview (80x60, 4:3 EGA ratio)
                                SnapshotThumbnailWidget(
                                  thumbnailRgba: snap.thumbnailRgba,
                                  width: 72,
                                  height: 54,
                                  borderColor: isSelectedAfter
                                      ? AgiTheme.egaCyan
                                      : (isSelectedBefore ? AgiTheme.egaAmber : AgiTheme.egaBorder),
                                ),
                                const SizedBox(width: 8),

                                // Snapshot Metadata & Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: snap.isRoomTransition
                                                  ? AgiTheme.egaAmber.withValues(alpha: 0.2)
                                                  : AgiTheme.egaGreen.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(3),
                                              border: Border.all(
                                                color: snap.isRoomTransition ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              snap.isRoomTransition ? '🚪 ROOM ENTRY' : '📸 SNAPSHOT',
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.bold,
                                                color: snap.isRoomTransition ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              snap.label,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11.5,
                                                color: AgiTheme.egaWhite,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Room ${snap.roomNumber} | Cycle ${snap.cycleCount} | Score ${snap.score}/${snap.maxScore}',
                                        style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Actions: Restore, Copy, Delete
                                IconButton(
                                  icon: const Icon(Icons.restore, size: 18, color: AgiTheme.egaGreen),
                                  tooltip: 'Restore this state',
                                  onPressed: () {
                                    widget.engine.restoreSnapshot(snap);
                                    _showToast('State restored to: ${snap.label}');
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14, color: AgiTheme.egaCyan),
                                  tooltip: 'Copy JSON for this snapshot (no thumbnail)',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: snap.toJsonString(pretty: true, includeThumbnail: false)));
                                    _showToast('Snapshot JSON (no thumbnail) copied!');
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 14, color: AgiTheme.egaMuted),
                                  tooltip: 'Delete',
                                  onPressed: () {
                                    if (originalIndex >= 0) {
                                      widget.engine.removeCheckpoint(originalIndex);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),
        const VerticalDivider(color: AgiTheme.egaBorder, width: 1),
        const SizedBox(width: 12),

        // Right Column: State Diff Viewer
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COMPARE CHECKPOINTS (BEFORE / AFTER DIFF)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
              ),
              const SizedBox(height: 6),
              if (allHistory.length >= 2) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _diffBeforeIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Before (Checkpoint A)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        items: List.generate(allHistory.length, (i) {
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              '[#$i] ${allHistory[i].label}',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        onChanged: (val) {
                          setState(() {
                            _diffBeforeIndex = val;
                            _computedDiffMarkdown = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _diffAfterIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'After (Checkpoint B)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        items: List.generate(allHistory.length, (i) {
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              '[#$i] ${allHistory[i].label}',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        onChanged: (val) {
                          setState(() {
                            _diffAfterIndex = val;
                            _computedDiffMarkdown = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _handleComputeDiff,
                      icon: const Icon(Icons.compare_arrows, size: 14),
                      label: const Text('Compute Diff', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const Spacer(),
                    if (_computedDiffMarkdown != null)
                      ElevatedButton.icon(
                        onPressed: _handleCopyDiff,
                        icon: const Icon(Icons.copy, size: 13),
                        label: const Text('Copy Markdown Diff', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _computedDiffMarkdown ?? 'Select two checkpoints above and click "Compute Diff".',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          color: AgiTheme.egaWhite,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Center(
                    child: Text(
                      'Capture at least 2 checkpoints to compare Before & After states.',
                      style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _checkpointFilterIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _checkpointFilterIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AgiTheme.egaCyan.withValues(alpha: 0.2)
              : AgiTheme.egaCardSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaBorder,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Live Variables & Flags
  // ---------------------------------------------------------------------------

  Widget _buildVariablesAndFlagsTab() {
    final mem = widget.engine.memory;
    final query = _searchFilterController.text.trim().toLowerCase();

    bool matchesFlag(int i) {
      if (query.isEmpty) return true;
      final name = (agiFlagNames[i] ?? '').toLowerCase();
      return '$i'.contains(query) || name.contains(query) || 'f$i'.contains(query);
    }

    bool matchesVar(int i, int val) {
      if (query.isEmpty) return true;
      final name = (agiVariableNames[i] ?? '').toLowerCase();
      return '$i'.contains(query) || name.contains(query) || '$val'.contains(query) || 'v$i'.contains(query);
    }

    final flagIds = <int>[];
    for (int i = 0; i < 256; i++) {
      final show = mem.getFlag(i) || mem.isFlagPinned(i) || mem.watchedFlags.contains(i);
      if (show && matchesFlag(i)) flagIds.add(i);
    }

    final varIds = <int>[];
    for (int i = 0; i < 256; i++) {
      final val = mem.getVar(i);
      final show = val != 0 || mem.isVarPinned(i) || mem.watchedVars.contains(i);
      if (show && matchesVar(i, val)) varIds.add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchFilterController,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
            hintText: 'Filter (e.g. "ego", "score", "f3", "v6")...',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        _buildWatchBar(),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('ACTIVE FLAGS', flagIds.length, AgiTheme.egaGreen, const Color(0xFF238636)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _buildListPanel(
                        emptyLabel: 'No flags matching filter',
                        itemCount: flagIds.length,
                        itemBuilder: (ctx, idx) => _buildFlagRow(flagIds[idx]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('NON-ZERO VARIABLES', varIds.length, AgiTheme.egaAmber, const Color(0xFF9E6A03)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: _buildListPanel(
                        emptyLabel: 'No variables matching filter',
                        itemCount: varIds.length,
                        itemBuilder: (ctx, idx) => _buildVarRow(varIds[idx]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, Color titleColor, Color badgeColor) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: titleColor),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildListPanel({
    required String emptyLabel,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: itemCount == 0
          ? Center(child: Text(emptyLabel, style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(6),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const Divider(color: AgiTheme.egaBorder, height: 4),
              itemBuilder: itemBuilder,
            ),
    );
  }

  Widget _buildWatchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('debug-watch-spec'),
            controller: _watchSpecController,
            style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Add/set f36, f36=1, v3=10 …',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onSubmitted: (_) => _applyWatchSpec(pin: false),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Set once (LOGIC may change it later)',
          child: TextButton(
            key: const Key('debug-watch-set'),
            onPressed: () => _applyWatchSpec(pin: false),
            child: const Text('SET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
        Tooltip(
          message: 'Pin: restored after every tick',
          child: TextButton(
            key: const Key('debug-watch-pin'),
            onPressed: () => _applyWatchSpec(pin: true),
            child: const Text('PIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber)),
          ),
        ),
      ],
    );
  }

  void _applyWatchSpec({required bool pin}) {
    final spec = _parseWatchSpec(_watchSpecController.text);
    if (spec == null) {
      _showToast('Use f36, f36=1, v3, or v3=10');
      return;
    }
    final mem = widget.engine.memory;
    if (spec.isFlag) {
      // No explicit value → keep/watch the current bit (lets you add a zero flag).
      final value = spec.value == null ? mem.getFlag(spec.index) : spec.value != 0;
      mem.watchFlag(spec.index);
      if (pin) {
        mem.pinFlag(spec.index, value);
      } else {
        if (value) {
          mem.setFlag(spec.index);
        } else {
          mem.resetFlag(spec.index);
        }
        if (mem.isFlagPinned(spec.index)) {
          mem.pinFlag(spec.index, value);
        }
      }
    } else {
      final value = spec.value ?? mem.getVar(spec.index);
      mem.watchVar(spec.index);
      if (pin) {
        mem.pinVar(spec.index, value);
      } else {
        mem.setVar(spec.index, value);
        if (mem.isVarPinned(spec.index)) {
          mem.pinVar(spec.index, value);
        }
      }
    }
    _watchSpecController.clear();
    widget.engine.notifyListeners();
    setState(() {});
  }

  void _commitVar(int vNum, int value, {required bool pin}) {
    final mem = widget.engine.memory;
    mem.watchVar(vNum);
    mem.setVar(vNum, value);
    if (pin) {
      mem.pinVar(vNum, value);
    }
    _pendingVarEdits.remove(vNum);
    widget.engine.notifyListeners();
    setState(() {});
  }

  ({bool isFlag, int index, int? value})? _parseWatchSpec(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.startsWith('%')) s = s.substring(1);
    final parts = s.split('=');
    final token = parts[0].trim();
    int? value;
    if (parts.length > 1) {
      value = int.tryParse(parts[1].trim());
      if (value == null) return null;
    }
    if (token.startsWith('f')) {
      final n = int.tryParse(token.substring(1));
      if (n == null || n < 0 || n > 255) return null;
      return (isFlag: true, index: n, value: value);
    }
    if (token.startsWith('v')) {
      final n = int.tryParse(token.substring(1));
      if (n == null || n < 0 || n > 255) return null;
      return (isFlag: false, index: n, value: value);
    }
    return null;
  }

  Widget _buildFlagRow(int f) {
    final mem = widget.engine.memory;
    final on = mem.getFlag(f);
    final pinned = mem.isFlagPinned(f);
    final name = agiFlagNames[f] ?? 'flag_$f';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Row(
        children: [
          Text(
            '%f$f',
            style: const TextStyle(
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaCyan,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 10, color: AgiTheme.egaWhite),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: on ? const Color(0xFF238636) : AgiTheme.egaBorder,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              on ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: on ? AgiTheme.egaWhite : AgiTheme.egaMuted,
              ),
            ),
          ),
          if (pinned) ...[
            const SizedBox(width: 4),
            const Icon(Icons.push_pin, size: 12, color: AgiTheme.egaAmber),
          ],
          const SizedBox(width: 4),
          _tinyAction(
            label: on ? 'CLR' : 'SET',
            tooltip: on ? 'Clear flag (LOGIC may set it again)' : 'Set flag ON (LOGIC may clear it)',
            onPressed: () {
              mem.watchFlag(f);
              final next = !on;
              if (next) {
                mem.setFlag(f);
              } else {
                mem.resetFlag(f);
              }
              if (pinned) {
                mem.pinFlag(f, next);
              }
              widget.engine.notifyListeners();
              setState(() {});
            },
          ),
          _tinyAction(
            label: pinned ? 'UNPIN' : 'PIN',
            tooltip: pinned ? 'Stop restoring after each tick' : 'Restore this value after every tick',
            color: pinned ? AgiTheme.egaAmber : null,
            onPressed: () {
              if (pinned) {
                mem.unpinFlag(f);
              } else {
                mem.pinFlag(f, on);
              }
              widget.engine.notifyListeners();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVarRow(int vNum) {
    final mem = widget.engine.memory;
    final val = mem.getVar(vNum);
    final pinned = mem.isVarPinned(vNum);
    final name = agiVariableNames[vNum] ?? 'var_$vNum';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Row(
        children: [
          Text(
            '%v$vNum',
            style: const TextStyle(
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaAmber,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 10, color: AgiTheme.egaWhite),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 44,
            child: TextFormField(
              key: ValueKey('var-$vNum-$val'),
              initialValue: '${_pendingVarEdits[vNum] ?? val}',
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: AgiTheme.egaCyan, fontWeight: FontWeight.bold),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                final parsed = int.tryParse(text.trim());
                if (parsed != null) {
                  _pendingVarEdits[vNum] = parsed;
                }
              },
              onFieldSubmitted: (text) {
                final parsed = int.tryParse(text.trim());
                if (parsed == null) return;
                _commitVar(vNum, parsed, pin: pinned);
              },
            ),
          ),
          if (pinned) ...[
            const SizedBox(width: 4),
            const Icon(Icons.push_pin, size: 12, color: AgiTheme.egaAmber),
          ],
          const SizedBox(width: 4),
          _tinyAction(
            label: 'SET',
            tooltip: 'Set once (LOGIC may change it later)',
            onPressed: () {
              final newVal = _pendingVarEdits[vNum] ?? mem.getVar(vNum);
              _commitVar(vNum, newVal, pin: pinned);
            },
          ),
          _tinyAction(
            label: pinned ? 'UNPIN' : 'PIN',
            tooltip: pinned ? 'Stop restoring after each tick' : 'Restore this value after every tick',
            color: pinned ? AgiTheme.egaAmber : null,
            onPressed: () {
              if (pinned) {
                mem.unpinVar(vNum);
                widget.engine.notifyListeners();
                setState(() {});
              } else {
                final newVal = _pendingVarEdits[vNum] ?? val;
                _commitVar(vNum, newVal, pin: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _tinyAction({
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(36, 24),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color ?? AgiTheme.egaCyan),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Animated Objects
  // ---------------------------------------------------------------------------

  Widget _buildObjectsTab() {
    final activeObjects = widget.engine.animatedObjects
        .where((o) => o.isDrawn || o.isAnimated || o.number == 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ACTIVE ANIMATED OBJECTS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AgiTheme.egaCardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Text('${activeObjects.length} active', style: const TextStyle(fontSize: 9, color: AgiTheme.egaCyan)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: activeObjects.length,
            itemBuilder: (ctx, idx) {
              final obj = activeObjects[idx];
              final isEgo = obj.number == 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AgiTheme.egaCardSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isEgo ? AgiTheme.egaCyan : AgiTheme.egaBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isEgo ? 'Ego (Object 0)' : 'Object ${obj.number}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isEgo ? AgiTheme.egaCyan : AgiTheme.egaWhite,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Pos: (${obj.x}, ${obj.y})',
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                            color: AgiTheme.egaGreen,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Pri: ${obj.priority}${obj.fixedPriority ? " (fixed)" : " (auto)"}',
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            color: AgiTheme.egaAmber,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('View: ${obj.view} | Loop: ${obj.loop} | Cel: ${obj.cel}', style: const TextStyle(fontSize: 10, color: AgiTheme.egaWhite)),
                        const SizedBox(width: 12),
                        Text('Dir: ${obj.direction} | StepSize: ${obj.stepSize}', style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (obj.isDrawn) _buildStatusBadge('Drawn', AgiTheme.egaGreen),
                        if (obj.isAnimated) _buildStatusBadge('Animated', AgiTheme.egaCyan),
                        if (obj.isCycling) _buildStatusBadge('Cycling', AgiTheme.egaAmber),
                        if (obj.motionType == 1) _buildStatusBadge('Wander', AgiTheme.egaAmber),
                        if (obj.motionType == 2) _buildStatusBadge('FollowEgo', AgiTheme.egaGreen),
                        if (obj.motionType == 3) _buildStatusBadge('MoveObj', AgiTheme.egaCyan),
                        if (obj.cycleMode == 1) _buildStatusBadge('RevCycle', AgiTheme.egaMagenta),
                        if (obj.cycleMode == 2) _buildStatusBadge('EndOfLoop', AgiTheme.egaMagenta),
                        if (obj.cycleMode == 3) _buildStatusBadge('RevLoop', AgiTheme.egaMagenta),
                        if (obj.ignoreBlocks) _buildStatusBadge('IgnoreBlocks', AgiTheme.egaMagenta),
                        if (obj.ignoreHorizon) _buildStatusBadge('IgnoreHorizon', AgiTheme.egaBlue),
                        if (obj.ignoreObjects) _buildStatusBadge('IgnoreObjects', AgiTheme.egaMuted),
                      ],
                    ),
                    if (obj.motionType == 3) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaCyan.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.near_me, size: 12, color: AgiTheme.egaCyan),
                            const SizedBox(width: 5),
                            Text(
                              'move.obj -> Target: (${obj.targetX}, ${obj.targetY})',
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaCyan,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Result Flag: %f${obj.targetFlag ?? "?"}',
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (obj.motionType == 2) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaGreen.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_pin_circle_outlined, size: 12, color: AgiTheme.egaGreen),
                            const SizedBox(width: 5),
                            const Text(
                              'follow.ego',
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaGreen,
                              ),
                            ),
                            const Spacer(),
                            if (obj.targetFlag != null)
                              Text(
                                'Result Flag: %f${obj.targetFlag}',
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AgiTheme.egaAmber,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (obj.cycleMode == 2 || obj.cycleMode == 3) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaMagenta.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.replay, size: 12, color: AgiTheme.egaMagenta),
                            const SizedBox(width: 5),
                            Text(
                              obj.cycleMode == 2 ? 'end.of.loop' : 'reverse.loop',
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaMagenta,
                              ),
                            ),
                            const Spacer(),
                            if (obj.endOfLoopFlag != null)
                              Text(
                                'Result Flag: %f${obj.endOfLoopFlag}',
                                style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AgiTheme.egaAmber,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Logic & System
  // ---------------------------------------------------------------------------

  Widget _buildLogicAndSystemTab() {
    final stack = widget.engine.interpreter.callStack;
    final loadedLogics = {
      ...widget.engine.loadedLogicNumbers,
      widget.engine.currentRoom,
    }.toList()..sort();
    final allPresentLogics = (widget.engine.resourceLoader?.presentLogicNumbers ?? loadedLogics).toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TELEPORT / ROOM SELECTOR
          _buildTeleportSection(allPresentLogics),
          const SizedBox(height: 12),

          // 2. CURRENTLY LOADED LOGIC SCRIPTS (Interactive Workbench Links)
          _buildLoadedLogicsSection(loadedLogics, allPresentLogics),
          const SizedBox(height: 12),

          // 3. ENGINE & ROOM STATUS
          _buildEngineAndRoomStatusSection(),
          const SizedBox(height: 12),

          // 4. LOGIC CALL STACK
          _buildLogicCallStackSection(stack),
          const SizedBox(height: 12),

          // 5. INVENTORY & MEMORY ALLOCATION
          _buildInfoSection('INVENTORY & MEMORY ALLOCATION', [
            'Scan Start IP: ${widget.engine.memory.scanStartIp}',
            'Item Rooms Count: ${widget.engine.memory.itemRooms.length}',
            'String Variables Count: ${widget.engine.memory.strings.length}',
            'Max Animated Objects: ${widget.engine.animatedObjects.length}',
          ]),
        ],
      ),
    );
  }

  Widget _buildTeleportSection(List<int> allPresentLogics) {
    final currentRoom = widget.engine.currentRoom;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaCyan.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight_takeoff, size: 16, color: AgiTheme.egaCyan),
              const SizedBox(width: 6),
              const Text(
                'TELEPORT / ROOM SELECTOR',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaCyan),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AgiTheme.egaCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AgiTheme.egaCyan, width: 0.8),
                ),
                child: Text(
                  'Current: Room $currentRoom',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgiTheme.egaCyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Instantly warp Ego to any room. You can remain in the debugger to inspect variables & memory, or resume gameplay immediately.',
            style: TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 34,
                child: TextField(
                  controller: _teleportRoomController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: AgiTheme.egaWhite),
                  decoration: InputDecoration(
                    hintText: 'Room # (0–255)',
                    hintStyle: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: AgiTheme.egaBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: AgiTheme.egaCyan),
                    ),
                  ),
                  onSubmitted: (val) {
                    _handleTeleport();
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _handleTeleport(),
                icon: const Icon(Icons.flash_on, size: 14, color: AgiTheme.egaCyan),
                label: const Text('Teleport (Inspect)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaCyan)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AgiTheme.egaCyan, width: 1.2),
                  backgroundColor: AgiTheme.egaCyan.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => _handleTeleport(closeInspector: true),
                icon: const Icon(Icons.play_arrow, size: 14, color: AgiTheme.egaGreen),
                label: const Text('Teleport & Play', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaGreen)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AgiTheme.egaGreen, width: 1.2),
                  backgroundColor: AgiTheme.egaGreen.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (allPresentLogics.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Quick Room Jump:',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: allPresentLogics.where((l) => l != 0).map((roomNum) {
                final isCurrent = roomNum == currentRoom;
                return ActionChip(
                  avatar: Icon(Icons.travel_explore, size: 12, color: isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan),
                  label: Text(
                    'Room $roomNum${isCurrent ? " (Current)" : ""}',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan,
                    ),
                  ),
                  backgroundColor: (isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan).withValues(alpha: 0.12),
                  side: BorderSide(
                    color: (isCurrent ? AgiTheme.egaAmber : AgiTheme.egaCyan).withValues(alpha: 0.6),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  onPressed: () => _handleTeleport(roomNumber: roomNum),
                  tooltip: 'Teleport immediately to Room $roomNum',
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadedLogicsSection(List<int> loadedLogics, List<int> allPresentLogics) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, size: 15, color: AgiTheme.egaAmber),
              const SizedBox(width: 6),
              const Text(
                'CURRENTLY LOADED LOGIC SCRIPTS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
              ),
              const Spacer(),
              Text(
                '${loadedLogics.length} Active / ${allPresentLogics.length} Total',
                style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Click any logic chip to open its full disassembly and message tables in the Logic Workbench. Hitting "Back" returns directly to the game.',
            style: TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...loadedLogics.map((logicNum) {
                final isLogic0 = logicNum == 0;
                final isCurrentRoom = logicNum == widget.engine.currentRoom;

                String badge = 'LOGIC $logicNum';
                if (isLogic0) {
                  badge = 'LOGIC 0 (Main Loop)';
                } else if (isCurrentRoom) {
                  badge = 'LOGIC $logicNum (Room ${widget.engine.currentRoom})';
                }

                final accentColor = isLogic0
                    ? AgiTheme.egaCyan
                    : (isCurrentRoom ? AgiTheme.egaAmber : AgiTheme.egaGreen);

                return ActionChip(
                  avatar: Icon(Icons.description_outlined, size: 14, color: accentColor),
                  label: Text(
                    badge,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  backgroundColor: accentColor.withValues(alpha: 0.12),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.6), width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  onPressed: () => _openLogicWorkbench(logicNum),
                  tooltip: 'Open LOGIC $logicNum in Logic Workbench',
                );
              }),
              ActionChip(
                avatar: const Icon(Icons.open_in_new, size: 13, color: AgiTheme.egaWhite),
                label: const Text(
                  'Browse All Logics ↗',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AgiTheme.egaWhite,
                  ),
                ),
                backgroundColor: const Color(0xFF2D3748),
                side: const BorderSide(color: AgiTheme.egaBorder, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                onPressed: () => _openLogicWorkbench(0),
                tooltip: 'Open Logic Browser to view all game logic scripts',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEngineAndRoomStatusSection() {
    final currentRoom = widget.engine.currentRoom;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ENGINE & ROOM STATUS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Current Room: Room $currentRoom',
                style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _openLogicWorkbench(currentRoom),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AgiTheme.egaAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: AgiTheme.egaAmber, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open Logic Script',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
                      ),
                      SizedBox(width: 3),
                      Icon(Icons.open_in_new, size: 10, color: AgiTheme.egaAmber),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Current Cycle Count: ${widget.engine.cycleCount}',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
          ),
          const SizedBox(height: 2),
          Text(
            'Engine Speed: ${widget.engine.speedHz.toInt()} Hz (${widget.engine.isPaused ? "PAUSED" : "RUNNING"})',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
          ),
          const SizedBox(height: 2),
          Text(
            'Sound Enabled: ${widget.engine.memory.getFlag(9) ? "YES" : "NO"}',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
          ),
          const SizedBox(height: 2),
          Text(
            'Last User Command: "${widget.engine.lastSubmittedCommand ?? ""}"',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
          ),
          if (widget.engine.lastError != null) ...[
            const SizedBox(height: 2),
            Text(
              'Last Error: ${widget.engine.lastError}',
              style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaRed),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogicCallStackSection(List<dynamic> stack) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LOGIC CALL STACK',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
          ),
          const SizedBox(height: 6),
          if (stack.isEmpty)
            const Text(
              'Call stack is empty (engine is at root frame).',
              style: TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaMuted),
            )
          else
            ...stack.asMap().entries.map((e) {
              final idx = e.key;
              final frame = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AgiTheme.egaBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '[Frame #$idx] LOGIC ${frame.scriptNumber} | IP: ${frame.ip} (Length: ${frame.script.bytecodeLength} B)',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          color: AgiTheme.egaWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _openLogicWorkbench(frame.scriptNumber as int),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AgiTheme.egaCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: AgiTheme.egaCyan, width: 0.8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Script',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaCyan,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.open_in_new, size: 10, color: AgiTheme.egaCyan),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _openLogicWorkbench(int logicNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LogicBrowserScreen(
          initialLogicNumber: logicNumber,
          loader: widget.engine.resourceLoader,
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<String> lines) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber)),
          const SizedBox(height: 6),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  l,
                  style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AgiTheme.egaWhite),
                ),
              )),
        ],
      ),
    );
  }
}
