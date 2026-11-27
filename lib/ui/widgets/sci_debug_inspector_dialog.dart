import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/opl/opl_debug_snapshot.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_pcm_source.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_renderer.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/screens/browsers/sci_script_browser_screen.dart';
import 'package:flutter_agigame/ui/widgets/renderer_diagnostics.dart';

/// Modal diagnostic inspector for SCI0 game execution.
///
/// Displays real-time cycle statistics, VM execution stack trace,
/// loaded scripts, playfield actor sprites, and kernel call history.
class SciDebugInspectorDialog extends StatefulWidget {
  final SciGameEngine engine;
  final RendererDiagnostics? rendererDiagnostics;

  const SciDebugInspectorDialog({super.key, required this.engine, this.rendererDiagnostics});

  static Future<void> show(BuildContext context, SciGameEngine engine,
      {RendererDiagnostics? rendererDiagnostics}) {
    engine.kernel.captureDebugLogs = true;
    engine.vm.captureDebugLogs = true;
    engine.pause();
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => SciDebugInspectorDialog(engine: engine, rendererDiagnostics: rendererDiagnostics),
    );
  }

  @override
  State<SciDebugInspectorDialog> createState() => _SciDebugInspectorDialogState();
}

/// Copied sound-slot summary for the Audio tab (captured, not live).
final class _AudioSlotSummary {
  final int resourceId;
  final int status;
  final int loop;
  final int startTick;
  final int totalTicks;
  final int cueCount;
  final int nextCue;
  final String format;

  const _AudioSlotSummary({
    required this.resourceId,
    required this.status,
    required this.loop,
    required this.startTick,
    required this.totalTicks,
    required this.cueCount,
    required this.nextCue,
    required this.format,
  });

  String get statusName => switch (status) {
        SciSoundStatus.stopped => 'stopped',
        SciSoundStatus.initialized => 'initialized',
        SciSoundStatus.paused => 'paused',
        SciSoundStatus.playing => 'playing',
        _ => 'unknown($status)',
      };
}

/// Copied per-voice driver state for the Audio tab.
final class _AudioVoiceSummary {
  final int channel;
  final int mappedChannel;
  final int note;
  final int patch;
  final int velocity;
  final bool sustained;

  const _AudioVoiceSummary({
    required this.channel,
    required this.mappedChannel,
    required this.note,
    required this.patch,
    required this.velocity,
    required this.sustained,
  });
}

/// Captured Audio-tab snapshot (Stage 7). Copied on explicit capture
/// only; the Audio tab renders from this copy while paused.
final class _AudioSnapshot {
  final SciMusicDevice device;
  final int tick;
  final List<_AudioSlotSummary> slots;
  final SciAdlibLoadResult bank;
  final bool hasActiveSource;
  final bool stereo;
  final String? sourceSummary;
  final int masterVolume;
  final SciAdLibDebugOverrides overrides;
  final List<OplWriteRecord> writeLogs;
  final bool writeLogEnabled;
  final List<OplDebugSnapshot> chipSnapshots;
  final List<_AudioVoiceSummary> voices;
  final List<int> channelPatches;
  final List<int> channelPans;
  final List<int> channelMappedVoices;

  const _AudioSnapshot({
    required this.device,
    required this.tick,
    required this.slots,
    required this.bank,
    required this.hasActiveSource,
    required this.stereo,
    required this.sourceSummary,
    required this.masterVolume,
    required this.overrides,
    required this.writeLogs,
    required this.writeLogEnabled,
    required this.chipSnapshots,
    required this.voices,
    required this.channelPatches,
    required this.channelPans,
    required this.channelMappedVoices,
  });
}

class _SciDebugInspectorDialogState extends State<SciDebugInspectorDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _logFilterController = TextEditingController();

  _AudioSnapshot? _audioSnapshot;
  int _audioSideIndex = 0;
  int _audioChannel = 0;
  int? _audioPatch;
  AgiSoundPlayer? _auditionPlayer;
  bool _auditionPlaying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    widget.engine.addListener(_onEngineUpdate);
    _audioSnapshot = _captureAudioSnapshot();
  }

  @override
  void dispose() {
    widget.engine.removeListener(_onEngineUpdate);
    widget.engine.kernel.captureDebugLogs = false;
    widget.engine.vm.captureDebugLogs = false;
    _auditionPlayer?.dispose();
    _auditionPlayer = null;
    _tabController.dispose();
    _logFilterController.dispose();
    super.dispose();
  }

  /// Explicit Audio capture (initState + Refresh button only; never from
  /// build, so no snapshot work happens during ordinary rebuilds).
  _AudioSnapshot _captureAudioSnapshot() {
    final engine = widget.engine;
    final kernel = engine.kernel;
    final bank = kernel.ensureAdLibBankLoaded();
    final source = kernel.activeAdLibSource;
    final driver = source?.debugDriver;
    final track = source?.track;
    return _AudioSnapshot(
      device: engine.sciMusicDevice,
      tick: kernel.currentSciTicks,
      slots: <_AudioSlotSummary>[
        for (final slot in kernel.soundSlots.values)
          _AudioSlotSummary(
            resourceId: slot.resourceId,
            status: slot.status,
            loop: slot.loop,
            startTick: slot.startTick,
            totalTicks: slot.parsedSound?.track?.totalTicks ?? 0,
            cueCount: slot.cues.length,
            nextCue: slot.nextCue,
            format: slot.parsedSound?.track == null
                ? 'none'
                : '${slot.parsedSound!.track!.variant.name}/'
                    '${slot.parsedSound!.track!.soundFormat.name}',
          ),
      ],
      bank: bank,
      hasActiveSource: source != null,
      stereo: source?.stereoDualOpl2 ?? false,
      sourceSummary: source == null
          ? null
          : '${source.bank.debugSummary()} track=${track?.totalTicks ?? 0} ticks '
              'variant=${track?.variant.name ?? '?'} profile=${driver?.profile.name ?? '?'}',
      masterVolume: driver?.masterVolume ?? 15,
      overrides: engine.sciAdLibDebugOverrides,
      writeLogs: source == null ? const [] : List<OplWriteRecord>.of(source.writeLogs),
      writeLogEnabled: source?.writeLogEnabled ?? false,
      chipSnapshots: source == null ? const [] : source.debugSnapshots(),
      voices: <_AudioVoiceSummary>[
        if (driver != null)
          for (var v = 0; v < 9; v++)
            _AudioVoiceSummary(
              channel: driver.voiceChannel(v),
              mappedChannel: driver.voiceMappedChannel(v),
              note: driver.voiceNote(v),
              patch: driver.voicePatch(v),
              velocity: driver.voiceVelocity(v),
              sustained: driver.voiceSustained(v),
            ),
      ],
      channelPatches: <int>[
        if (driver != null)
          for (var c = 0; c < 16; c++) driver.channelPatch(c),
      ],
      channelPans: <int>[
        if (driver != null)
          for (var c = 0; c < 16; c++) driver.channelPan(c),
      ],
      channelMappedVoices: <int>[
        if (driver != null)
          for (var c = 0; c < 16; c++) driver.channelMappedVoices(c),
      ],
    );
  }

  void _recaptureAudio() {
    setState(() => _audioSnapshot = _captureAudioSnapshot());
  }

  void _updateOverrides(SciAdLibDebugOverrides overrides) {
    widget.engine.setSciAdLibDebugOverrides(overrides);
    _recaptureAudio();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
  }

  void _showToast(String message, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
        ),
        duration: duration,
        backgroundColor: AgiTheme.egaCardSurface,
      ),
    );
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

            if (widget.rendererDiagnostics != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: SelectableText(
                  widget.rendererDiagnostics!.describe(),
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: AgiTheme.egaMuted,
                  ),
                ),
              ),

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
                  const Tab(
                    icon: Icon(Icons.graphic_eq, size: 16),
                    text: 'Audio',
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
                  _buildAudioTab(),
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
                      _buildStatRow('Menu Visible', '${engine.kernel.menuBar.visible}'),
                      _buildStatRow('Menu Open', '${engine.kernel.menuBar.openMenuId ?? "-"}'),
                      _buildStatRow('Mouse At', '${engine.kernel.mouseX},${engine.kernel.mouseY}'),
                      _buildStatRow('Title Hit', '${engine.kernel.menuBar.menuIdAt(engine.kernel.mouseX, engine.kernel.mouseY, engine.kernel.getFont(0))}'),
                      _buildStatRow('Menu Titles', engine.kernel.menuBar.menus.map((m) => m.title.trim()).where((t) => t.isNotEmpty).join(' | ')),
                      _buildStatRow('Status Active', '${engine.kernel.menuBar.statusActive}'),
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
          _buildStubHitsSection(engine),
          const SizedBox(height: 8),
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
                  _showToast('Kernel logs copied to clipboard', duration: const Duration(seconds: 1));
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

  /// Unimplemented kernel ops ranked by hit count. Play the game with this
  /// open and the hottest rows are the next stubs worth implementing.
  Widget _buildStubHitsSection(SciGameEngine engine) {
    final total = engine.kernel.stubHitTotal;
    final top = engine.kernel.topStubHits(10);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: AgiTheme.egaAmber, size: 14),
              const SizedBox(width: 6),
              Text(
                'UNIMPLEMENTED KERNEL OPS ($total calls)',
                style: const TextStyle(
                  color: AgiTheme.egaAmber,
                  fontFamily: 'Courier',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  engine.kernel.clearStubStats();
                  setState(() {});
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(color: AgiTheme.egaCyan, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (top.isEmpty)
            const Text(
              'No stubbed kernel calls this session.',
              style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11),
            )
          else
            for (final row in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '0x${row.id.toRadixString(16).padLeft(2, "0")} ${row.name} × ${row.hits}',
                  style: const TextStyle(
                    color: AgiTheme.egaWhite,
                    fontFamily: 'Courier',
                    fontSize: 11,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // ==========================================
  // AUDIO TAB (Stage 7: captured snapshot only)
  // ==========================================

  String _segName(int seg) => switch (seg) {
        0 => 'silent',
        1 => 'attack',
        2 => 'decay',
        3 => 'sustain',
        4 => 'release',
        _ => 'seg$seg',
      };

  Widget _buildAudioTab() {
    final snap = _audioSnapshot;
    if (snap == null) {
      return const Center(
        child: Text(
          'No audio snapshot captured.',
          style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier'),
        ),
      );
    }
    final bankText = snap.bank.bank == null
        ? 'no bank: ${snap.bank.reason ?? 'unavailable'}'
        : '${snap.bank.bank!.debugSummary()} (${snap.bank.provenance.name})';
    final fallback = widget.engine.kernel.adLibFallbackReason;
    final sourceText = !snap.hasActiveSource
        ? 'no active source${fallback != null ? ' (fallback: $fallback)' : ''}'
        : '${snap.sourceSummary} master=${snap.masterVolume}/15';
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            const Text(
              'Captured snapshot (explicit capture only)',
              style: TextStyle(
                color: AgiTheme.egaAmber,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              'tick ${snap.tick}',
              style: const TextStyle(
                color: AgiTheme.egaMuted,
                fontFamily: 'Courier',
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 14, color: AgiTheme.egaCyan),
              label: const Text(
                'Capture',
                style: TextStyle(color: AgiTheme.egaCyan, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AgiTheme.egaCyan),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              onPressed: _recaptureAudio,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Summary strip.
        _audioBox(
          'SUMMARY',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEVICE  ${snap.device.name}',
                  style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              Text('BANK  $bankText',
                  style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              Text('SOURCE  $sourceText',
                  style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _audioBox(
          'SOUND SLOTS (${snap.slots.length})',
          snap.slots.isEmpty
              ? const Text('No sound slots.',
                  style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in snap.slots)
                      Text(
                        'res=${s.resourceId} status=${s.statusName} loop=${s.loop} '
                        'start=${s.startTick} total=${s.totalTicks} cues=${s.cueCount}/${s.nextCue} format=${s.format}',
                        style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        _buildOplSnapshotSection(snap),
        const SizedBox(height: 8),
        _buildPatchBrowserSection(snap),
        const SizedBox(height: 8),
        _buildLiveControlsSection(snap),
        const SizedBox(height: 8),
        _buildWriteTraceSection(snap),
      ],
    );
  }

  Widget _audioBox(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AgiTheme.egaCyan,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildOplSnapshotSection(_AudioSnapshot snap) {
    if (snap.chipSnapshots.isEmpty) {
      return _audioBox(
        'OPL SNAPSHOT',
        const Text('No active source: no chip snapshot captured.',
            style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11)),
      );
    }
    final side = _audioSideIndex.clamp(0, snap.chipSnapshots.length - 1);
    final shot = snap.chipSnapshots[side];
    final sideLabel = snap.chipSnapshots.length == 1 ? 'Left' : (side == 0 ? 'Left' : 'Right');
    final cell = TextStyle(fontFamily: 'Courier', fontSize: 9, color: AgiTheme.egaWhite);
    final head = TextStyle(fontFamily: 'Courier', fontSize: 9, fontWeight: FontWeight.bold, color: AgiTheme.egaCyan);
    return _audioBox(
      'OPL SNAPSHOT ($sideLabel)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (snap.chipSnapshots.length > 1)
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Left'),
                  selected: side == 0,
                  onSelected: (_) => setState(() => _audioSideIndex = 0),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Right'),
                  selected: side == 1,
                  onSelected: (_) => setState(() => _audioSideIndex = 1),
                ),
              ],
            ),
          Text(
            'globals noteSel=${shot.noteSel} csm=${shot.csm} amDepth=${shot.amDepth} vibDepth=${shot.vibDepth} rhythm=0x${shot.rhythmBits.toRadixString(16)}',
            style: cell,
          ),
          const SizedBox(height: 4),
          // Register/channel grid: 9 voices across columns.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(children: [
                  Text('ch', style: head),
                  for (var v = 0; v < 9; v++) Text(' V$v', style: head),
                ]),
                TableRow(children: [
                  Text('fnum', style: cell),
                  for (final c in shot.channels) Text(' ${c.fnum}', style: cell),
                ]),
                TableRow(children: [
                  Text('block', style: cell),
                  for (final c in shot.channels) Text(' ${c.block}', style: cell),
                ]),
                TableRow(children: [
                  Text('key', style: cell),
                  for (final c in shot.channels) Text(' ${c.keyOn ? 1 : 0}', style: cell),
                ]),
                TableRow(children: [
                  Text('fb', style: cell),
                  for (final c in shot.channels) Text(' ${c.feedback}', style: cell),
                ]),
                TableRow(children: [
                  Text('conn', style: cell),
                  for (final c in shot.channels) Text(' ${c.connection}', style: cell),
                ]),
                TableRow(children: [
                  Text('modOff', style: cell),
                  for (final c in shot.channels) Text(' ${c.modulatorOffset}', style: cell),
                ]),
                TableRow(children: [
                  Text('carOff', style: cell),
                  for (final c in shot.channels) Text(' ${c.carrierOffset}', style: cell),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 9x2 operator grid.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(children: [
                  Text('op', style: head),
                  for (var v = 0; v < 9; v++) Text(' V$v', style: head),
                ]),
                TableRow(children: [
                  Text('mod seg', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${_segName(shot.operators[v * 2].envelopeSegment)}', style: cell),
                ]),
                TableRow(children: [
                  Text('car seg', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${_segName(shot.operators[v * 2 + 1].envelopeSegment)}', style: cell),
                ]),
                TableRow(children: [
                  Text('mod lvl', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2].envelopeDb.toStringAsFixed(1)}', style: cell),
                ]),
                TableRow(children: [
                  Text('car lvl', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2 + 1].envelopeDb.toStringAsFixed(1)}', style: cell),
                ]),
                TableRow(children: [
                  Text('mod TL', style: cell),
                  for (var v = 0; v < 9; v++) Text(' ${shot.operators[v * 2].tl}', style: cell),
                ]),
                TableRow(children: [
                  Text('car TL', style: cell),
                  for (var v = 0; v < 9; v++) Text(' ${shot.operators[v * 2 + 1].tl}', style: cell),
                ]),
                TableRow(children: [
                  Text('mult', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2].mult}/${shot.operators[v * 2 + 1].mult}', style: cell),
                ]),
                TableRow(children: [
                  Text('AR/DR', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(
                      ' ${shot.operators[v * 2].ar}/${shot.operators[v * 2].dr} '
                      '${shot.operators[v * 2 + 1].ar}/${shot.operators[v * 2 + 1].dr}',
                      style: cell,
                    ),
                ]),
                TableRow(children: [
                  Text('SL/RR', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(
                      ' ${shot.operators[v * 2].sl}/${shot.operators[v * 2].rr} '
                      '${shot.operators[v * 2 + 1].sl}/${shot.operators[v * 2 + 1].rr}',
                      style: cell,
                    ),
                ]),
                TableRow(children: [
                  Text('KSL', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2].ksl}/${shot.operators[v * 2 + 1].ksl}', style: cell),
                ]),
                TableRow(children: [
                  Text('KSR', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2].ksr}/${shot.operators[v * 2 + 1].ksr}', style: cell),
                ]),
                TableRow(children: [
                  Text('AM/VIB', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(
                      ' ${shot.operators[v * 2].am ? 1 : 0}${shot.operators[v * 2].vib ? 1 : 0}/'
                      '${shot.operators[v * 2 + 1].am ? 1 : 0}${shot.operators[v * 2 + 1].vib ? 1 : 0}',
                      style: cell,
                    ),
                ]),
                TableRow(children: [
                  Text('wave', style: cell),
                  for (var v = 0; v < 9; v++)
                    Text(' ${shot.operators[v * 2].waveform}/${shot.operators[v * 2 + 1].waveform}', style: cell),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatchBrowserSection(_AudioSnapshot snap) {
    final bank = snap.bank.bank;
    final patchCount = bank?.instrumentCount ?? 0;
    final selected = (_audioPatch ?? 0).clamp(0, patchCount > 0 ? patchCount - 1 : 0);
    final instrument = bank != null && patchCount > 0 ? bank.instruments[selected] : null;
    return _audioBox(
      'PATCH BROWSER',
      bank == null
          ? Text('No bank available: ${snap.bank.reason ?? 'unavailable'}',
              style: const TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DropdownButton<int>(
                      value: selected,
                      items: [
                        for (var i = 0; i < patchCount; i++)
                          DropdownMenuItem(value: i, child: Text('Patch $i')),
                      ],
                      onChanged: (v) => setState(() => _audioPatch = v ?? 0),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _auditionPlaying ? _stopAudition : _startAudition,
                      icon: Icon(_auditionPlaying ? Icons.stop : Icons.play_arrow, size: 14),
                      label: Text(_auditionPlaying ? 'Stop' : 'Play'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (instrument != null) ...[
                  SelectableText('op0 [${instrument.operator0.debugString()}]',
                      style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 10)),
                  SelectableText('op1 [${instrument.operator1.debugString()}]',
                      style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 10)),
                  SelectableText('mod [${instrument.modulator.debugString()}]',
                      style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 10)),
                  SelectableText(instrument.debugString(),
                      style: const TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 9)),
                ],
              ],
            ),
    );
  }

  /// Patch audition through a dedicated, dialog-owned player. Never
  /// borrows the game engine's player/source. Lazily initialized on the
  /// first audition; the engine stays paused regardless.
  Future<void> _startAudition() async {
    final bank = _audioSnapshot?.bank.bank;
    final patch = _audioPatch ?? 0;
    if (bank == null || patch < 0 || patch >= bank.instrumentCount) return;
    var player = _auditionPlayer;
    if (player == null) {
      player = AgiSoundPlayer();
      player.onFinished = () {
        if (mounted) setState(() => _auditionPlaying = false);
      };
      _auditionPlayer = player;
      await player.initialize(sampleRate: widget.engine.kernel.synthesizerConfig.sampleRate);
      if (!mounted) return;
    }
    final overrides = widget.engine.sciAdLibDebugOverrides
        .copyWith(patchOverrides: const {});
    final track = sciAdLibPatchAuditionTrack(patch);
    final source = SciAdLibPcmSource(
      track,
      bank,
      outputSampleRate: widget.engine.kernel.synthesizerConfig.sampleRate,
      masterVolume: 15,
      stereoDualOpl2: true,
      debugOverrides: overrides,
    );
    setState(() => _auditionPlaying = true);
    await player.playPcmSource(source, totalTicks: track.totalTicks);
    if (mounted && player.isStopped) {
      setState(() => _auditionPlaying = false);
    }
  }

  void _stopAudition() {
    _auditionPlayer?.stop();
    setState(() => _auditionPlaying = false);
  }

  Widget _buildLiveControlsSection(_AudioSnapshot snap) {
    final ch = _audioChannel.clamp(0, 14);
    final overrides = snap.overrides;
    final gain = overrides.gainSteps[ch] ?? 0;
    final pan = overrides.panOverrides[ch];
    final trackPan = snap.channelPans.length > ch ? snap.channelPans[ch] : 64;
    final patchOverride = overrides.patchOverrides[ch];
    final patchCount = snap.bank.bank?.instrumentCount ?? 0;
    return _audioBox(
      'LIVE CONTROLS (session debug overrides, applied next note, not persisted)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Channel',
                  style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: ch,
                items: [
                  for (var i = 0; i <= 14; i++)
                    DropdownMenuItem(value: i, child: Text('ch$i')),
                ],
                onChanged: (v) => setState(() => _audioChannel = v ?? 0),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _updateOverrides(const SciAdLibDebugOverrides.empty()),
                child: const Text('Reset overrides'),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text('Gain steps',
                    style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              ),
              Expanded(
                child: Slider(
                  value: gain.toDouble(),
                  min: -32,
                  max: 16,
                  divisions: 48,
                  onChanged: (v) {
                    final next = Map<int, int>.of(overrides.gainSteps)..[ch] = v.round();
                    _updateOverrides(overrides.copyWith(gainSteps: next));
                  },
                ),
              ),
              Text('$gain',
                  style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text('Pan',
                    style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              ),
              Expanded(
                child: Slider(
                  value: (pan ?? trackPan).toDouble(),
                  min: 0,
                  max: 127,
                  divisions: 127,
                  onChanged: (v) {
                    final next = Map<int, int>.of(overrides.panOverrides)..[ch] = v.round();
                    _updateOverrides(overrides.copyWith(panOverrides: next));
                  },
                ),
              ),
              Text('${pan ?? trackPan}',
                  style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              TextButton(
                onPressed: pan == null
                    ? null
                    : () {
                        final next = Map<int, int>.of(overrides.panOverrides)..remove(ch);
                        _updateOverrides(overrides.copyWith(panOverrides: next));
                      },
                child: const Text('Track Pan'),
              ),
            ],
          ),
          Row(
            children: [
              const Text('Muted',
                  style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 12)),
              const Spacer(),
              Switch(
                value: overrides.mutedChannels.contains(ch),
                onChanged: (v) {
                  final next = Set<int>.of(overrides.mutedChannels);
                  if (v) {
                    next.add(ch);
                  } else {
                    next.remove(ch);
                  }
                  _updateOverrides(overrides.copyWith(mutedChannels: next));
                },
              ),
            ],
          ),
          Row(
            children: [
              const Text('Solo',
                  style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 12)),
              const Spacer(),
              Switch(
                value: overrides.soloChannels.contains(ch),
                onChanged: (v) {
                  final next = Set<int>.of(overrides.soloChannels);
                  if (v) {
                    next.add(ch);
                  } else {
                    next.remove(ch);
                  }
                  _updateOverrides(overrides.copyWith(soloChannels: next));
                },
              ),
            ],
          ),
          Row(
            children: [
              const Text('Patch override',
                  style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
              const SizedBox(width: 8),
              DropdownButton<int?>(
                value: patchOverride,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Track patch')),
                  for (var i = 0; i < patchCount; i++)
                    DropdownMenuItem<int?>(value: i, child: Text('Patch $i')),
                ],
                onChanged: (v) {
                  final next = Map<int, int>.of(overrides.patchOverrides);
                  if (v == null) {
                    next.remove(ch);
                  } else {
                    next[ch] = v;
                  }
                  _updateOverrides(overrides.copyWith(patchOverrides: next));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWriteTraceSection(_AudioSnapshot snap) {
    final enabled = snap.writeLogEnabled;
    final recent = snap.writeLogs.length > 40
        ? snap.writeLogs.sublist(snap.writeLogs.length - 40)
        : snap.writeLogs;
    return _audioBox(
      'WRITE TRACE',
      snap.hasActiveSource
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Capture register writes',
                        style: TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: enabled,
                      onChanged: (v) {
                        final source = widget.engine.kernel.activeAdLibSource;
                        if (source == null) return;
                        if (v) source.clearWriteLogs();
                        source.writeLogEnabled = v;
                        _recaptureAudio();
                      },
                    ),
                  ],
                ),
                Text('Count: ${snap.writeLogs.length}',
                    style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 11)),
                if (recent.isEmpty)
                  const Text('No writes captured yet.',
                      style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11))
                else
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      itemCount: recent.length,
                      itemBuilder: (_, i) {
                        final r = recent[i];
                        return Text(
                          'frame=${r.frameIndex} 0x${r.address.toRadixString(16).padLeft(2, '0')}=0x${r.value.toRadixString(16).padLeft(2, '0')}',
                          style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier', fontSize: 10),
                        );
                      },
                    ),
                  ),
                OutlinedButton(
                  onPressed: () {
                    widget.engine.kernel.activeAdLibSource?.clearWriteLogs();
                    _recaptureAudio();
                  },
                  child: const Text('Clear'),
                ),
              ],
            )
          : const Text('No active source: write trace is unavailable.',
              style: TextStyle(color: AgiTheme.egaMuted, fontFamily: 'Courier', fontSize: 11)),
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
              final d = widget.rendererDiagnostics;
              final jsonStr = d == null
                  ? engine.exportStateJson(pretty: true)
                  : const JsonEncoder.withIndent('  ')
                      .convert(injectRendererDiagnostics(engine.exportState(), d));
              Clipboard.setData(ClipboardData(text: jsonStr));
              _showToast('📋 SCI Engine State JSON copied to clipboard!');
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
