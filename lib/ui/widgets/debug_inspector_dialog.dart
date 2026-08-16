import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/domain/game_state_snapshot.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';

/// Modal dialog for inspecting live AGI engine state, managing checkpoints (save-states),
/// generating before/after diffs, and exporting/importing state JSON.
class DebugInspectorDialog extends StatefulWidget {
  final AgiGameEngine engine;

  const DebugInspectorDialog({
    super.key,
    required this.engine,
  });

  static Future<void> show(BuildContext context, AgiGameEngine engine) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
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

  int? _diffBeforeIndex;
  int? _diffAfterIndex;
  String? _computedDiffMarkdown;

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
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleTakeSnapshot() {
    final label = _checkpointLabelController.text.trim();
    widget.engine.recordCheckpoint(label: label);
    _checkpointLabelController.clear();
    setState(() {
      _diffAfterIndex = 0;
      if (widget.engine.checkpointHistory.length > 1) {
        _diffBeforeIndex = 1;
      }
      _computedDiffMarkdown = null;
    });
    _showToast('📸 Snapshot captured!');
  }

  void _handleCopyCurrentJson() {
    final snap = widget.engine.createSnapshot();
    final jsonStr = snap.toJsonString(pretty: true);
    Clipboard.setData(ClipboardData(text: jsonStr));
    _showToast('📋 Current State JSON copied to clipboard!');
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

  void _handlePasteJsonDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgiTheme.egaDarkSurface,
        title: const Text(
          'Load State from JSON',
          style: TextStyle(color: AgiTheme.egaCyan, fontSize: 16),
        ),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: textController,
            maxLines: 12,
            style: const TextStyle(fontSize: 11, fontFamily: 'Courier'),
            decoration: const InputDecoration(
              hintText: 'Paste AGI State Snapshot JSON here...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isNotEmpty) {
                try {
                  final snap = AgiGameStateSnapshot.fromJsonString(raw);
                  widget.engine.restoreSnapshot(snap);
                  Navigator.of(ctx).pop();
                  _showToast('✅ State restored successfully!');
                } catch (e) {
                  _showToast('❌ Invalid JSON: $e');
                }
              }
            },
            child: const Text('Restore State'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Courier')),
        duration: const Duration(seconds: 2),
        backgroundColor: AgiTheme.egaCardSurface,
      ),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 860,
        height: 620,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildTabBar(),
            const Divider(color: AgiTheme.egaBorder, height: 16),
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
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.bug_report, color: AgiTheme.egaCyan, size: 20),
        const SizedBox(width: 8),
        const Text(
          'AGI DEBUG INSPECTOR & STATE CHECKPOINTS',
          style: TextStyle(
            color: AgiTheme.egaWhite,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, color: AgiTheme.egaMuted, size: 18),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close Inspector',
        ),
      ],
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
    final history = widget.engine.checkpointHistory;

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
                        hintText: 'Snapshot label (e.g. "Before stepping on line")',
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
              const SizedBox(height: 8),
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
                  OutlinedButton.icon(
                    onPressed: _handlePasteJsonDialog,
                    icon: const Icon(Icons.file_upload, size: 13),
                    label: const Text('Load JSON', style: TextStyle(fontSize: 10)),
                  ),
                  if (history.isNotEmpty)
                    TextButton(
                      onPressed: () => widget.engine.clearCheckpoints(),
                      child: const Text('Clear History', style: TextStyle(fontSize: 10, color: AgiTheme.egaRed)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'CHECKPOINT HISTORY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: history.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AgiTheme.egaCardSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgiTheme.egaBorder),
                        ),
                        child: const Text(
                          'No checkpoints captured yet.\nClick "Capture" to record a state snapshot.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        itemCount: history.length,
                        itemBuilder: (ctx, idx) {
                          final snap = history[idx];
                          final isSelectedBefore = _diffBeforeIndex == idx;
                          final isSelectedAfter = _diffAfterIndex == idx;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isSelectedBefore || isSelectedAfter)
                                  ? const Color(0xFF1F2D3D)
                                  : AgiTheme.egaCardSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelectedAfter
                                    ? AgiTheme.egaCyan
                                    : (isSelectedBefore ? AgiTheme.egaAmber : AgiTheme.egaBorder),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        snap.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AgiTheme.egaWhite,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Room ${snap.roomNumber} | Cycle ${snap.cycleCount} | Score ${snap.score}/${snap.maxScore}',
                                        style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.restore, size: 16, color: AgiTheme.egaGreen),
                                  tooltip: 'Restore this state',
                                  onPressed: () {
                                    widget.engine.restoreSnapshot(snap);
                                    _showToast('State restored to: ${snap.label}');
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14, color: AgiTheme.egaCyan),
                                  tooltip: 'Copy JSON for this snapshot',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: snap.toJsonString(pretty: true)));
                                    _showToast('Snapshot JSON copied!');
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 14, color: AgiTheme.egaMuted),
                                  tooltip: 'Delete',
                                  onPressed: () => widget.engine.removeCheckpoint(idx),
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
              if (history.length >= 2) ...[
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
                        items: List.generate(history.length, (i) {
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              '[#$i] ${history[i].label}',
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
                        items: List.generate(history.length, (i) {
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              '[#$i] ${history[i].label}',
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
                          backgroundColor: const Color(0xFF238636),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
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

  // ---------------------------------------------------------------------------
  // Tab 2: Live Variables & Flags
  // ---------------------------------------------------------------------------

  Widget _buildVariablesAndFlagsTab() {
    final mem = widget.engine.memory;
    final query = _searchFilterController.text.trim().toLowerCase();

    // Active Flags
    final activeFlags = <int>[];
    for (int i = 0; i < mem.flags.length; i++) {
      if (mem.flags[i]) {
        final name = agiFlagNames[i] ?? '';
        if (query.isEmpty || '$i'.contains(query) || name.toLowerCase().contains(query)) {
          activeFlags.add(i);
        }
      }
    }

    // Non-zero Variables
    final nonZeroVars = <int, int>{};
    for (int i = 0; i < mem.variables.length; i++) {
      final val = mem.variables[i];
      if (val != 0) {
        final name = agiVariableNames[i] ?? '';
        if (query.isEmpty || '$i'.contains(query) || name.toLowerCase().contains(query) || '$val'.contains(query)) {
          nonZeroVars[i] = val;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchFilterController,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
            hintText: 'Filter variables or flags (e.g. "ego", "room", "score", "f3", "v6")...',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Flags Column
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'ACTIVE FLAGS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaGreen),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF238636),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${activeFlags.length}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AgiTheme.egaCardSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgiTheme.egaBorder),
                        ),
                        child: activeFlags.isEmpty
                            ? const Center(
                                child: Text('No active flags matching filter', style: TextStyle(fontSize: 10, color: AgiTheme.egaMuted)),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(6),
                                itemCount: activeFlags.length,
                                separatorBuilder: (_, _) => const Divider(color: AgiTheme.egaBorder, height: 4),
                                itemBuilder: (ctx, idx) {
                                  final f = activeFlags[idx];
                                  final name = agiFlagNames[f] ?? 'flag_$f';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
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
                                        const SizedBox(width: 8),
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
                                            color: const Color(0xFF238636),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: const Text('ON', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Non-Zero Variables Column
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'NON-ZERO VARIABLES',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgiTheme.egaAmber),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9E6A03),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${nonZeroVars.length}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AgiTheme.egaCardSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgiTheme.egaBorder),
                        ),
                        child: nonZeroVars.isEmpty
                            ? const Center(
                                child: Text('No non-zero variables matching filter', style: TextStyle(fontSize: 10, color: AgiTheme.egaMuted)),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(6),
                                itemCount: nonZeroVars.length,
                                separatorBuilder: (_, _) => const Divider(color: AgiTheme.egaBorder, height: 4),
                                itemBuilder: (ctx, idx) {
                                  final vNum = nonZeroVars.keys.elementAt(idx);
                                  final val = nonZeroVars[vNum]!;
                                  final name = agiVariableNames[vNum] ?? 'var_$vNum';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
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
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontSize: 10, color: AgiTheme.egaWhite),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '$val',
                                          style: const TextStyle(
                                            fontFamily: 'Courier',
                                            fontWeight: FontWeight.bold,
                                            color: AgiTheme.egaCyan,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
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
                      children: [
                        if (obj.isDrawn) _buildStatusBadge('Drawn', AgiTheme.egaGreen),
                        if (obj.isAnimated) _buildStatusBadge('Animated', AgiTheme.egaCyan),
                        if (obj.isCycling) _buildStatusBadge('Cycling', AgiTheme.egaAmber),
                        if (obj.ignoreBlocks) _buildStatusBadge('IgnoreBlocks', AgiTheme.egaMagenta),
                        if (obj.ignoreHorizon) _buildStatusBadge('IgnoreHorizon', AgiTheme.egaBlue),
                        if (obj.ignoreObjects) _buildStatusBadge('IgnoreObjects', AgiTheme.egaMuted),
                      ],
                    ),
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection('ENGINE & ROOM STATUS', [
            'Current Room: Room ${widget.engine.currentRoom}',
            'Current Cycle Count: ${widget.engine.cycleCount}',
            'Engine Speed: ${widget.engine.speedHz.toInt()} Hz (${widget.engine.isPaused ? "PAUSED" : "RUNNING"})',
            'Sound Enabled: ${widget.engine.memory.getFlag(9) ? "YES" : "NO"}',
            'Last User Command: "${widget.engine.lastSubmittedCommand ?? ""}"',
            if (widget.engine.lastError != null) 'Last Error: ${widget.engine.lastError}',
          ]),
          const SizedBox(height: 12),
          _buildInfoSection('LOGIC CALL STACK', [
            if (stack.isEmpty)
              'Call stack is empty.'
            else
              ...stack.asMap().entries.map((e) {
                final idx = e.key;
                final frame = e.value;
                return '[Frame #$idx] Logic ${frame.scriptNumber} | IP: ${frame.ip} (Total bytecode length: ${frame.script.bytecodeLength} bytes)';
              }),
          ]),
          const SizedBox(height: 12),
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
