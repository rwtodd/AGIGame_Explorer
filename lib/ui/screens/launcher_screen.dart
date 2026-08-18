import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/logic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/objects_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/words_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/av_settings_dialog.dart';

class LauncherScreen extends ConsumerStatefulWidget {
  const LauncherScreen({super.key});

  @override
  ConsumerState<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends ConsumerState<LauncherScreen> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final launcherNotifier = ref.read(launcherProvider.notifier);

    // Keep text controller in sync if path changed externally
    if (launcherState.selectedPath != null &&
        _pathController.text != launcherState.selectedPath) {
      _pathController.text = launcherState.selectedPath!;
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(launcherState),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDirectoryCard(launcherState, launcherNotifier),
                    const SizedBox(height: 20),
                    if (launcherState.status == LauncherStatus.scanning)
                      _buildScanningCard()
                    else if (launcherState.status == LauncherStatus.error)
                      _buildErrorCard(launcherState.errorMessage ?? 'Unknown error occurred')
                    else if (launcherState.status == LauncherStatus.loaded &&
                        launcherState.gameInfo != null)
                      _buildGameDetailsCard(launcherState)
                    else
                      _buildEmptyStateCard(),
                  ],
                ),
              ),
            ),
            _buildStatusBar(launcherState),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LauncherState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF003322),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaGreen),
            ),
            child: const Text(
              'AGI v2/v3',
              style: TextStyle(
                color: AgiTheme.egaGreen,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SIERRA AGI WORKBENCH',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: AgiTheme.egaCyan,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Adventure Game Interpreter & Diagnostic Environment',
                  style: TextStyle(
                    fontSize: 12,
                    color: AgiTheme.egaMuted,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => AvSettingsDialog.show(
              context,
              resourceLoader: state.loader,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: const BorderSide(color: AgiTheme.egaCyan),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: const Icon(Icons.tune, size: 14, color: AgiTheme.egaCyan),
            label: const Text(
              'A/V Settings',
              style: TextStyle(
                color: AgiTheme.egaCyan,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AgiTheme.egaCardSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.desktop_mac, size: 14, color: AgiTheme.egaAmber),
                SizedBox(width: 6),
                Text(
                  'macOS Native',
                  style: TextStyle(
                    color: AgiTheme.egaAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryCard(LauncherState state, LauncherNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.folder_open, size: 18, color: AgiTheme.egaAmber),
                SizedBox(width: 8),
                Text(
                  'GAME DIRECTORY',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: AgiTheme.egaAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      hintText: '/path/to/sierra_agi_game (e.g. KQ3, SQ2, LSL1)',
                      suffixIcon: _pathController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _pathController.clear();
                                notifier.clear();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        notifier.scanDirectory(value.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => notifier.pickDirectory(),
                  icon: const Icon(Icons.folder_special, size: 16),
                  label: const Text('Browse...'),
                ),
                if (state.status == LauncherStatus.loaded ||
                    state.status == LauncherStatus.error) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_pathController.text.isNotEmpty) {
                        notifier.scanDirectory(_pathController.text);
                      }
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Rescan'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: AgiTheme.egaCyan),
            SizedBox(height: 16),
            Text(
              'Scanning directory and inspecting AGI resource volumes...',
              style: TextStyle(color: AgiTheme.egaWhite, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AgiTheme.egaRed, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: AgiTheme.egaRed, size: 20),
                SizedBox(width: 8),
                Text(
                  'LOAD ERROR',
                  style: TextStyle(
                    color: AgiTheme.egaRed,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              error,
              style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ensure the directory contains valid AGI files (e.g. AGIDATA.OVL, LOGDIR, PICDIR, VIEWDIR, SNDDIR, or <prefix>DIR and <prefix>VOL.0).',
              style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            Icon(Icons.sports_esports, size: 48, color: AgiTheme.egaCyan.withAlpha(150)),
            const SizedBox(height: 16),
            const Text(
              'No Game Loaded',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AgiTheme.egaWhite,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a directory containing Sierra AGI game files (King\'s Quest, Space Quest, Police Quest, Leisure Suit Larry, Gold Rush, or fan games) to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AgiTheme.egaMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameDetailsCard(LauncherState state) {
    final info = state.gameInfo!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AgiTheme.egaCyan),
                      ),
                      child: const Icon(Icons.videogame_asset, color: AgiTheme.egaCyan, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AgiTheme.egaWhite,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            info.gamePath,
                            style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: info.isV3 ? const Color(0xFF330033) : const Color(0xFF002244),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: info.isV3 ? AgiTheme.egaMagenta : AgiTheme.egaCyan,
                        ),
                      ),
                      child: Text(
                        'AGI ${info.isV3 ? "v3" : "v2"} • ${info.versionString}',
                        style: TextStyle(
                          color: info.isV3 ? AgiTheme.egaMagenta : AgiTheme.egaCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Main Gameplay Action & A/V Configuration
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GameScreen(
                                resourceLoader: state.loader,
                                initialSettings: ref.read(settingsProvider),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669), // Emerald EGA Green
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: const BorderSide(color: Color(0xFF34D399), width: 1.5),
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_filled, size: 20),
                        label: const Text(
                          'PLAY GAME',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => AvSettingsDialog.show(
                          context,
                          resourceLoader: state.loader,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AgiTheme.egaCyan, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.tune, size: 18, color: AgiTheme.egaCyan),
                        label: const Text(
                          'CONFIGURE A/V',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AgiTheme.egaCyan,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Pre-launch A/V Summary Chips
                Consumer(
                  builder: (context, ref, _) {
                    final settings = ref.watch(settingsProvider);
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildSettingSummaryChip(
                          icon: Icons.tv,
                          label: settings.display.showCrtShader
                              ? 'CRT Scanlines ON'
                              : (settings.display.correctAspectRatio ? '4:3 CRT Aspect' : '1:1 Square Pixels'),
                          onTap: () => AvSettingsDialog.show(context, resourceLoader: state.loader),
                        ),
                        _buildSettingSummaryChip(
                          icon: Icons.music_note,
                          label: _formatAudioSummary(settings.audio),
                          onTap: () => AvSettingsDialog.show(context, resourceLoader: state.loader),
                        ),
                        if (settings.display.strictIntegerScaling)
                          _buildSettingSummaryChip(
                            icon: Icons.fit_screen,
                            label: 'Integer Scaling',
                            onTap: () => AvSettingsDialog.show(context, resourceLoader: state.loader),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),
                const Divider(color: AgiTheme.egaBorder),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Icon(Icons.folder_open, size: 16, color: AgiTheme.egaAmber),
                    SizedBox(width: 8),
                    Text(
                      'GAME RESOURCES (CLICK TO EXPLORE)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AgiTheme.egaAmber,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _buildMetricTile(
                      'LOGIC Scripts',
                      info.logicCount.toString(),
                      Icons.code,
                      AgiTheme.egaGreen,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LogicBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'PICTURE Rooms',
                      info.picCount.toString(),
                      Icons.image,
                      AgiTheme.egaCyan,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PicBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'VIEW Sprites',
                      info.viewCount.toString(),
                      Icons.animation,
                      AgiTheme.egaMagenta,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ViewBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'SOUND Tracks',
                      info.soundCount.toString(),
                      Icons.music_note,
                      AgiTheme.egaAmber,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SoundBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'Inventory Objects',
                      info.objectCount.toString(),
                      Icons.inventory_2,
                      AgiTheme.egaWhite,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ObjectsBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'WORDS.TOK Vocab',
                      info.wordCount.toString(),
                      Icons.menu_book,
                      AgiTheme.egaCyan,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WordsBrowserScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMetricTile(
                      'Max Animated',
                      info.maxAnimatedObjects.toString(),
                      Icons.directions_run,
                      AgiTheme.egaGreen,
                    ),
                    _buildMetricTile(
                      'Container Format',
                      info.isV3 ? '${info.prefix}VOL.*' : 'VOL.*',
                      Icons.storage,
                      AgiTheme.egaMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final isClickable = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: color.withValues(alpha: 0.08),
        splashColor: color.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AgiTheme.egaDarkSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isClickable ? color.withValues(alpha: 0.4) : AgiTheme.egaBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        if (isClickable) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new, size: 10, color: color.withValues(alpha: 0.7)),
                        ],
                      ],
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingSummaryChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF131D31),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF27354A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AgiTheme.egaCyan),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AgiTheme.egaWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAudioSummary(AgiAudioSettings audio) {
    switch (audio.soundMode) {
      case AgiSoundMode.off:
        return 'Audio Muted';
      case AgiSoundMode.ibmPc:
        return 'IBM PC Speaker';
      case AgiSoundMode.pcJr:
        return 'Tandy 3-Voice';
      case AgiSoundMode.enhanced:
        final wave = audio.waveform.name.toUpperCase();
        if (audio.enableReverb && audio.reverbMix > 0.0) {
          final rev = (audio.reverbMix * 100).toInt();
          return 'Enhanced ($wave + $rev% Rev)';
        }
        return 'Enhanced ($wave)';
    }
  }

  Widget _buildStatusBar(LauncherState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.status == LauncherStatus.loaded
                  ? AgiTheme.egaGreen
                  : state.status == LauncherStatus.error
                      ? AgiTheme.egaRed
                      : AgiTheme.egaAmber,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.status == LauncherStatus.loaded
                ? 'Game ready: ${state.gameInfo?.displayName} (${state.gameInfo?.versionString})'
                : state.status == LauncherStatus.scanning
                    ? 'Scanning...'
                    : state.status == LauncherStatus.error
                        ? 'Error during scan'
                        : 'Ready. Choose a game folder to launch.',
            style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
          ),
          const Spacer(),
          const Text(
            'Antigravity AGI Engine',
            style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
          ),
        ],
      ),
    );
  }
}
