import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/screens/browsers/sci_script_browser_screen.dart';

/// Modal diagnostic inspector for SCI0 game execution.
///
/// Displays real-time cycle statistics, VM execution stack trace,
/// loaded scripts, playfield actor sprites, and kernel call history.
class SciDebugInspectorDialog extends StatefulWidget {
  final SciGameEngine engine;

  const SciDebugInspectorDialog({super.key, required this.engine});

  static Future<void> show(BuildContext context, SciGameEngine engine) {
    engine.kernel.captureDebugLogs = true;
    engine.vm.captureDebugLogs = true;
    engine.pause();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => SciDebugInspectorDialog(engine: engine),
    );
  }

  @override
  State<SciDebugInspectorDialog> createState() => _SciDebugInspectorDialogState();
}

class _SciDebugInspectorDialogState extends State<SciDebugInspectorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _logFilterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.engine.addListener(_onEngineUpdate);
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineUpdate);
    widget.engine.kernel.captureDebugLogs = false;
    widget.engine.vm.captureDebugLogs = false;
    _tabController.dispose();
    _logFilterController.dispose();
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final picNum = engine.currentPic?.picNumber;

    return Dialog(
      backgroundColor: AgiTheme.egaCardSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AgiTheme.egaBorder, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Column(
          children: [
            // Header
            _buildHeader(engine, picNum),

            // Tab Bar
            Container(
              color: const Color(0xFF1E2638),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AgiTheme.egaCyan,
                labelColor: AgiTheme.egaWhite,
                unselectedLabelColor: AgiTheme.egaMuted,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.memory, size: 16),
                    text: 'VM & Stack (${engine.vm.executionStack.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.animation, size: 16),
                    text: 'Actors (${engine.actors.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.list_alt, size: 16),
                    text: 'Kernel Logs (${engine.recentKernelLogs.length})',
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVmStackTab(engine),
                  _buildActorsTab(engine),
                  _buildKernelLogsTab(engine),
                ],
              ),
            ),

            // Footer / Toolbar
            _buildFooter(engine),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SciGameEngine engine, int? picNum) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131926),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: AgiTheme.egaGreen, size: 20),
          const SizedBox(width: 8),
          const Text(
            'SCI0 Diagnostic Inspector',
            style: TextStyle(
              color: AgiTheme.egaWhite,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              picNum != null ? 'Pic $picNum' : 'No Pic',
              style: const TextStyle(
                color: AgiTheme.egaCyan,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: AgiTheme.egaMuted, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildVmStackTab(SciGameEngine engine) {
    final frames = engine.vm.executionStack.reversed.toList();
    final loadedScripts = engine.segManager.loadedScripts.values.toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Execution Stack
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Execution Call Stack',
                      style: TextStyle(
                        color: AgiTheme.egaAmber,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${frames.length} frame(s)',
                      style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131926),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: frames.isEmpty
                        ? const Center(
                            child: Text(
                              'VM idle (stack empty)',
                              style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier'),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: frames.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 8, color: Color(0xFF222D42)),
                            itemBuilder: (context, i) {
                              final f = frames[i];
                              final depth = frames.length - 1 - i;
                              final selName = f.selector >= 0
                                  ? engine.selectors.getSelectorName(f.selector)
                                  : '-';
                              final scr = engine.segManager.loadedScripts[f.pc.segment];
                              final scrNum = scr?.scriptNumber ?? f.pc.segment;

                              return Row(
                                children: [
                                  Text(
                                    '#$depth ',
                                    style: const TextStyle(
                                      color: AgiTheme.egaMuted,
                                      fontFamily: 'Courier',
                                      fontSize: 11,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E2C44),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      f.type.name,
                                      style: const TextStyle(
                                        color: AgiTheme.egaCyan,
                                        fontFamily: 'Courier',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Script $scrNum',
                                    style: const TextStyle(
                                      color: AgiTheme.egaWhite,
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '::$selName',
                                    style: const TextStyle(
                                      color: AgiTheme.egaAmber,
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'pc: 0x${f.pc.offset.toRadixString(16).padLeft(4, '0')}',
                                    style: const TextStyle(
                                      color: AgiTheme.egaMuted,
                                      fontFamily: 'Courier',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right: Engine info & loaded scripts
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Engine Statistics',
                  style: TextStyle(
                    color: AgiTheme.egaAmber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131926),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AgiTheme.egaBorder),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('Status', engine.isPaused ? 'PAUSED' : 'RUNNING'),
                      _buildStatRow('Cycle Count', '${engine.cycleCount}'),
                      _buildStatRow('Cycle Speed', '${engine.speedHz.toStringAsFixed(1)} Hz'),
                      _buildStatRow('Current Pic', '${engine.currentPic?.picNumber ?? "None"}'),
                      _buildStatRow('Pic Slices', '${engine.pictureSlices?.length ?? 0} layers'),
                      _buildStatRow('Active Sprites', '${engine.actors.length}'),
                      _buildStatRow('Stack Items', '${engine.vm.stack.length}'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Loaded Scripts',
                      style: TextStyle(
                        color: AgiTheme.egaAmber,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${loadedScripts.length}',
                      style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131926),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(6),
                      itemCount: loadedScripts.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 4, color: Color(0xFF222D42)),
                      itemBuilder: (context, i) {
                        final s = loadedScripts[i];
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SciScriptBrowserScreen(
                                  initialScriptNumber: s.scriptNumber,
                                  volumeManager: widget.engine.volumeManager,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  'Script ${s.scriptNumber}',
                                  style: const TextStyle(
                                    color: AgiTheme.egaCyan,
                                    fontFamily: 'Courier',
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'seg: ${s.segmentId}',
                                  style: const TextStyle(
                                    color: AgiTheme.egaMuted,
                                    fontFamily: 'Courier',
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11)),
          const Spacer(),
          Text(
            val,
            style: const TextStyle(
              color: AgiTheme.egaWhite,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActorsTab(SciGameEngine engine) {
    final actors = engine.actors;

    if (actors.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, color: AgiTheme.egaMuted, size: 36),
            SizedBox(height: 8),
            Text(
              'No active playfield actor sprites in this room cycle.',
              style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: actors.length,
      separatorBuilder: (_, _) => const Divider(height: 8, color: Color(0xFF222D42)),
      itemBuilder: (context, i) {
        final a = actors[i];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF131926),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AgiTheme.egaBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2C44),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'V${a.viewNumber}:L${a.loopNumber}:C${a.celNumber}',
                  style: const TextStyle(
                    color: AgiTheme.egaCyan,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pos: (${a.position.dx.toInt()}, ${a.position.dy.toInt()})  Baseline Y: ${a.baselineY}  Z: ${a.z}',
                    style: const TextStyle(
                      color: AgiTheme.egaWhite,
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Priority: ${a.priority}  Updating: ${a.isUpdating}  Displace: (${a.displaceX}, ${a.displaceY})',
                    style: const TextStyle(
                      color: AgiTheme.egaMuted,
                      fontFamily: 'Courier',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKernelLogsTab(SciGameEngine engine) {
    final filter = _logFilterController.text.trim().toLowerCase();
    final logs = engine.recentKernelLogs.reversed.where((l) {
      if (filter.isEmpty) return true;
      return l.toLowerCase().contains(filter);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _logFilterController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: AgiTheme.egaWhite,
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Filter kernel calls (e.g. DrawPic, Animate, GetEvent)...',
                      hintStyle: const TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: AgiTheme.egaMuted, size: 16),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFF131926),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AgiTheme.egaBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: AgiTheme.egaBorder),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, color: AgiTheme.egaCyan, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Copy all logs to clipboard',
                onPressed: () {
                  final text = engine.recentKernelLogs.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kernel logs copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF131926),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching kernel logs.',
                        style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier'),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            logs[i],
                            style: const TextStyle(
                              color: AgiTheme.egaWhite,
                              fontFamily: 'Courier',
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(SciGameEngine engine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF131926),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          // Play / Pause
          OutlinedButton.icon(
            icon: Icon(
              engine.isPaused ? Icons.play_arrow : Icons.pause,
              size: 16,
              color: engine.isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
            ),
            label: Text(
              engine.isPaused ? 'Resume' : 'Pause',
              style: TextStyle(
                color: engine.isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
                fontSize: 12,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: engine.isPaused ? AgiTheme.egaGreen : AgiTheme.egaAmber,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () {
              if (engine.isPaused) {
                engine.resume();
              } else {
                engine.pause();
              }
              setState(() {});
            },
          ),
          const SizedBox(width: 8),

          // Single Step
          OutlinedButton.icon(
            icon: const Icon(Icons.skip_next, size: 16, color: AgiTheme.egaCyan),
            label: const Text('Step 1 Tick', style: TextStyle(color: AgiTheme.egaCyan, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AgiTheme.egaCyan),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () {
              engine.tick();
              setState(() {});
            },
          ),
          const SizedBox(width: 8),

          // Copy State JSON
          OutlinedButton.icon(
            icon: const Icon(Icons.data_object, size: 16, color: Color(0xFF22C55E)),
            label: const Text('Copy State JSON', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF22C55E)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: () {
              final jsonStr = engine.exportStateJson(pretty: true);
              Clipboard.setData(ClipboardData(text: jsonStr));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 SCI Engine State JSON copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          const Spacer(),

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: AgiTheme.egaWhite)),
          ),
        ],
      ),
    );
  }
}
