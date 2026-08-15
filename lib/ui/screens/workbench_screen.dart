import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/logic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/objects_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/words_browser_screen.dart';

enum WorkbenchTab {
  pictures,
  views,
  logics,
  sounds,
  objects,
  words,
}

class WorkbenchScreen extends ConsumerStatefulWidget {
  final WorkbenchTab initialTab;

  const WorkbenchScreen({
    super.key,
    this.initialTab = WorkbenchTab.pictures,
  });

  @override
  ConsumerState<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends ConsumerState<WorkbenchScreen> {
  late WorkbenchTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final gameInfo = launcherState.gameInfo;

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: AgiTheme.egaDarkSurface,
                border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AgiTheme.egaCyan),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back to Launcher',
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gameInfo?.displayName ?? 'SIERRA WORKBENCH',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AgiTheme.egaWhite,
                        ),
                      ),
                      Text(
                        'AGI ${gameInfo?.isV3 == true ? "v3" : "v2"} • ${gameInfo?.versionString ?? ""}',
                        style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),

                  // Tab Buttons
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabButton(
                            WorkbenchTab.pictures,
                            'PICTURES',
                            Icons.image,
                            AgiTheme.egaCyan,
                            gameInfo?.picCount ?? 0,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            WorkbenchTab.views,
                            'VIEWS',
                            Icons.animation,
                            AgiTheme.egaMagenta,
                            gameInfo?.viewCount ?? 0,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            WorkbenchTab.logics,
                            'LOGIC SCRIPTS',
                            Icons.code,
                            AgiTheme.egaGreen,
                            gameInfo?.logicCount ?? 0,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            WorkbenchTab.sounds,
                            'SOUNDS',
                            Icons.music_note,
                            AgiTheme.egaAmber,
                            gameInfo?.soundCount ?? 0,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            WorkbenchTab.objects,
                            'OBJECTS',
                            Icons.inventory_2,
                            AgiTheme.egaWhite,
                            gameInfo?.objectCount ?? 0,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            WorkbenchTab.words,
                            'VOCABULARY',
                            Icons.menu_book,
                            AgiTheme.egaCyan,
                            gameInfo?.wordCount ?? 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Active Browser Content
            Expanded(
              child: _buildActiveBrowser(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(
    WorkbenchTab tab,
    String label,
    IconData icon,
    Color color,
    int count,
  ) {
    final isSelected = _currentTab == tab;

    return InkWell(
      onTap: () => setState(() => _currentTab = tab),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF21262D) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? color : AgiTheme.egaMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AgiTheme.egaWhite : AgiTheme.egaMuted,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.2) : const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : AgiTheme.egaMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBrowser() {
    switch (_currentTab) {
      case WorkbenchTab.pictures:
        return const PicBrowserScreen();
      case WorkbenchTab.views:
        return const ViewBrowserScreen();
      case WorkbenchTab.logics:
        return const LogicBrowserScreen();
      case WorkbenchTab.sounds:
        return const SoundBrowserScreen();
      case WorkbenchTab.objects:
        return const ObjectsBrowserScreen();
      case WorkbenchTab.words:
        return const WordsBrowserScreen();
    }
  }
}
