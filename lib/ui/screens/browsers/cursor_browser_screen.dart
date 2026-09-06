import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor.dart';
import 'package:flutter_agigame/sci/cursor/sci_cursor_parser.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

/// Background color mode for cursor inspection.
enum CursorInspectorBg {
  darkCheckerboard,
  lightCheckerboard,
  black,
  egaBlue,
  egaGreen,
  white,
}

/// Diagnostic workbench browser for authentic Sierra SCI 16x16 masked cursor resources.
class CursorBrowserScreen extends ConsumerStatefulWidget {
  final int? initialCursorNumber;
  final SciVolumeManager? volumeManager;

  const CursorBrowserScreen({
    super.key,
    this.initialCursorNumber,
    this.volumeManager,
  });

  @override
  ConsumerState<CursorBrowserScreen> createState() => _CursorBrowserScreenState();
}

class _CursorBrowserScreenState extends ConsumerState<CursorBrowserScreen> {
  int _selectedCursorNumber = 999;
  SciCursor? _currentCursor;
  bool _isLoading = false;
  String? _errorMessage;

  // Inspector settings
  int _zoomScale = 16;
  bool _showPixelGrid = true;
  bool _showHotspotMarker = true;
  CursorInspectorBg _inspectorBg = CursorInspectorBg.darkCheckerboard;
  math.Point<int>? _hoveredPixel;

  // Sandbox settings
  int _sandboxScale = 2;
  Offset? _sandboxMousePosition;
  bool _isMouseInSandbox = false;
  final List<Offset> _sandboxClickHistory = [];
  int _sandboxTargetClicks = 0;
  bool _sandboxItemCollected = false;
  bool _sandboxDoorOpened = false;

  SciVolumeManager? get _activeVolumeManager =>
      widget.volumeManager ?? ref.read(launcherProvider).sciVolumeManager;

  List<int> _presentCursorNumbers() {
    final vm = _activeVolumeManager;
    if (vm == null) return const [];
    return vm.resourceMap.numbersForType(SciResourceType.cursor).toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    final present = _presentCursorNumbers();
    if (widget.initialCursorNumber != null && present.contains(widget.initialCursorNumber)) {
      _selectedCursorNumber = widget.initialCursorNumber!;
    } else if (present.isNotEmpty) {
      // Default to 999 (standard arrow) if available, otherwise first cursor
      _selectedCursorNumber = present.contains(999) ? 999 : present.first;
    }

    if (present.isNotEmpty) {
      _loadCursor(_selectedCursorNumber);
    }
  }

  void _loadCursor(int cursorNum) {
    final vm = _activeVolumeManager;
    if (vm == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedCursorNumber = cursorNum;
      _hoveredPixel = null;
    });

    try {
      final raw = vm.getResource(SciResourceType.cursor, cursorNum);
      final cursor = SciCursorParser.parse(raw, cursorNumber: cursorNum);

      setState(() {
        _currentCursor = cursor;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load CURSOR $cursorNum: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(launcherProvider);
    final presentCursors = _presentCursorNumbers();

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: _buildAppBar(presentCursors),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AgiTheme.egaCyan))
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AgiTheme.egaRed, fontSize: 14),
                  ),
                )
              : presentCursors.isEmpty
                  ? const Center(
                      child: Text(
                        'No CURSOR resources found in this volume.',
                        style: TextStyle(color: AgiTheme.egaMuted, fontSize: 14),
                      ),
                    )
                  : _buildBody(presentCursors),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentCursors) {
    final cursorIndex = presentCursors.indexOf(_selectedCursorNumber);
    final cursorName = SierraCursor.standardCursorName(_selectedCursorNumber);

    return AppBar(
      backgroundColor: AgiTheme.egaDarkSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AgiTheme.egaCyan),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back to Launcher',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF220033),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaMagenta),
            ),
            child: Text(
              'CURSOR $_selectedCursorNumber',
              style: const TextStyle(
                color: AgiTheme.egaMagenta,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            cursorName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaWhite,
            ),
          ),
          const SizedBox(width: 12),
          if (_currentCursor != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AgiTheme.egaCardSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Text(
                '16×16 • Hotspot: (${_currentCursor!.hotspotX}, ${_currentCursor!.hotspotY})',
                style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AgiTheme.egaCyan),
          tooltip: 'Previous Cursor',
          onPressed: cursorIndex > 0 ? () => _loadCursor(presentCursors[cursorIndex - 1]) : null,
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentCursors.contains(_selectedCursorNumber) ? _selectedCursorNumber : null,
              dropdownColor: AgiTheme.egaDarkSurface,
              icon: const Icon(Icons.arrow_drop_down, color: AgiTheme.egaCyan),
              style: const TextStyle(
                color: AgiTheme.egaCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              items: presentCursors
                  .map((cNum) => DropdownMenuItem(
                        value: cNum,
                        child: Text('Cursor $cNum (${SierraCursor.standardCursorName(cNum)})'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) _loadCursor(val);
              },
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: AgiTheme.egaCyan),
          tooltip: 'Next Cursor',
          onPressed: cursorIndex >= 0 && cursorIndex < presentCursors.length - 1
              ? () => _loadCursor(presentCursors[cursorIndex + 1])
              : null,
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildBody(List<int> presentCursors) {
    final cursor = _currentCursor;
    if (cursor == null) {
      return const Center(
        child: Text('No cursor loaded', style: TextStyle(color: AgiTheme.egaMuted)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left pane: Cursor gallery / list
        Expanded(
          flex: 3,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: _buildCursorGallery(presentCursors),
          ),
        ),

        // Middle pane: High-zoom pixel inspector
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: _buildPixelInspector(cursor),
          ),
        ),

        // Right pane: Interactive live mouse testing sandbox
        Expanded(
          flex: 5,
          child: _buildInteractiveSandbox(cursor),
        ),
      ],
    );
  }

  // ===========================================================================
  // Cursor Gallery (Left Pane)
  // ===========================================================================

  Widget _buildCursorGallery(List<int> presentCursors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AgiTheme.egaDarkSurface,
            border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.grid_view, size: 16, color: AgiTheme.egaCyan),
              const SizedBox(width: 8),
              Text(
                'AVAILABLE CURSORS (${presentCursors.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AgiTheme.egaCyan,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: presentCursors.length,
            itemBuilder: (context, index) {
              final cNum = presentCursors[index];
              final isSelected = cNum == _selectedCursorNumber;
              final name = SierraCursor.standardCursorName(cNum);
              final desc = SierraCursor.standardCursorDescription(cNum);

              return Card(
                color: isSelected ? const Color(0xFF1E2838) : AgiTheme.egaCardSurface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaBorder,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _loadCursor(cNum),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Cursor thumbnail preview
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF101418),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaBorder,
                            ),
                          ),
                          child: Center(
                            child: _buildCursorThumbnail(cNum),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Label and metadata
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Cursor $cNum',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaWhite,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (cNum == 999)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF003344),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(color: AgiTheme.egaCyan, width: 0.8),
                                      ),
                                      child: const Text(
                                        'DEFAULT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AgiTheme.egaCyan,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AgiTheme.egaAmber,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                desc,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCursorThumbnail(int cursorNum) {
    final vm = _activeVolumeManager;
    if (vm == null) return const SizedBox.shrink();
    try {
      final raw = vm.getResource(SciResourceType.cursor, cursorNum);
      final cursor = SciCursorParser.parse(raw, cursorNumber: cursorNum);
      return CustomPaint(
        size: const Size(32, 32),
        painter: _CursorPainter(
          cursor: cursor,
          scale: 2,
          showHotspot: false,
          showGrid: false,
          bgColor: Colors.transparent,
        ),
      );
    } catch (_) {
      return const Icon(Icons.broken_image, size: 20, color: AgiTheme.egaRed);
    }
  }

  // ===========================================================================
  // Pixel Inspector (Middle Pane)
  // ===========================================================================

  Widget _buildPixelInspector(SciCursor cursor) {
    return Column(
      children: [
        // Inspector toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: AgiTheme.egaDarkSurface,
            border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.zoom_in, size: 16, color: AgiTheme.egaCyan),
              const SizedBox(width: 8),
              const Text(
                'PIXEL INSPECTOR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AgiTheme.egaCyan,
                ),
              ),
              const Spacer(),
              // Zoom selector
              const Text('Zoom: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _zoomScale,
                  dropdownColor: AgiTheme.egaDarkSurface,
                  style: const TextStyle(fontSize: 11, color: AgiTheme.egaCyan, fontWeight: FontWeight.bold),
                  items: const [8, 12, 16, 20, 24]
                      .map((z) => DropdownMenuItem(value: z, child: Text('${z}x')))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _zoomScale = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Grid toggle
              IconButton(
                icon: Icon(
                  _showPixelGrid ? Icons.grid_on : Icons.grid_off,
                  size: 18,
                  color: _showPixelGrid ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                ),
                tooltip: 'Toggle Pixel Grid',
                onPressed: () => setState(() => _showPixelGrid = !_showPixelGrid),
              ),
              // Hotspot toggle
              IconButton(
                icon: Icon(
                  _showHotspotMarker ? Icons.adjust : Icons.panorama_fish_eye,
                  size: 18,
                  color: _showHotspotMarker ? AgiTheme.egaRed : AgiTheme.egaMuted,
                ),
                tooltip: 'Toggle Hotspot Crosshair',
                onPressed: () => setState(() => _showHotspotMarker = !_showHotspotMarker),
              ),
            ],
          ),
        ),

        // Background selector row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF14181E),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Background: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
                const SizedBox(width: 8),
                _buildBgChip('Dark Check', CursorInspectorBg.darkCheckerboard),
                _buildBgChip('Light Check', CursorInspectorBg.lightCheckerboard),
                _buildBgChip('Black', CursorInspectorBg.black),
                _buildBgChip('Blue', CursorInspectorBg.egaBlue),
                _buildBgChip('Green', CursorInspectorBg.egaGreen),
                _buildBgChip('White', CursorInspectorBg.white),
              ],
            ),
          ),
        ),

        // Centered magnified cursor canvas
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MouseRegion(
                    onHover: (event) {
                      final local = event.localPosition;
                      final px = (local.dx / _zoomScale).floor();
                      final py = (local.dy / _zoomScale).floor();
                      if (px >= 0 && px < 16 && py >= 0 && py < 16) {
                        setState(() => _hoveredPixel = math.Point(px, py));
                      }
                    },
                    onExit: (_) => setState(() => _hoveredPixel = null),
                    child: Container(
                      width: 16.0 * _zoomScale,
                      height: 16.0 * _zoomScale,
                      decoration: BoxDecoration(
                        border: Border.all(color: AgiTheme.egaBorder, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        size: Size(16.0 * _zoomScale, 16.0 * _zoomScale),
                        painter: _CursorPainter(
                          cursor: cursor,
                          scale: _zoomScale,
                          showHotspot: _showHotspotMarker,
                          showGrid: _showPixelGrid,
                          bgMode: _inspectorBg,
                          hoveredPixel: _hoveredPixel,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Hover status line
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AgiTheme.egaCardSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: Text(
                      _hoveredPixel != null
                          ? 'Pixel (${_hoveredPixel!.x}, ${_hoveredPixel!.y}): ${_pixelDescription(cursor.getPixel(_hoveredPixel!.x, _hoveredPixel!.y))}'
                          : 'Hover over grid to inspect pixels',
                      style: TextStyle(
                        fontSize: 11,
                        color: _hoveredPixel != null ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const Divider(color: AgiTheme.egaBorder, height: 1),

        // Cursor statistics and mask breakdown
        Container(
          padding: const EdgeInsets.all(12),
          color: AgiTheme.egaDarkSurface,
          child: _buildCursorMetrics(cursor),
        ),
      ],
    );
  }

  Widget _buildBgChip(String label, CursorInspectorBg bgMode) {
    final isSelected = _inspectorBg == bgMode;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() => _inspectorBg = bgMode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF003344) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaBorder,
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
      ),
    );
  }

  String _pixelDescription(SierraCursorPixel p) {
    switch (p) {
      case SierraCursorPixel.black:
        return 'BLACK (EGA 0 / Outline)';
      case SierraCursorPixel.white:
        return 'WHITE (EGA 15 / Interior)';
      case SierraCursorPixel.transparent:
        return 'TRANSPARENT (Alpha = 0)';
      case SierraCursorPixel.gray:
        return 'GRAY / WHITE (EGA 7/15)';
    }
  }

  Widget _buildCursorMetrics(SciCursor cursor) {
    var blackCount = 0;
    var whiteCount = 0;
    var transparentCount = 0;
    var grayCount = 0;

    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        switch (cursor.getPixel(x, y)) {
          case SierraCursorPixel.black:
            blackCount++;
            break;
          case SierraCursorPixel.white:
            whiteCount++;
            break;
          case SierraCursorPixel.transparent:
            transparentCount++;
            break;
          case SierraCursorPixel.gray:
            grayCount++;
            break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RESOURCE METRICS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AgiTheme.egaAmber,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              'Size: 68 bytes',
              style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildMetricPill('Hotspot', '(${cursor.hotspotX}, ${cursor.hotspotY})', AgiTheme.egaRed),
            _buildMetricPill('Black', '$blackCount px', AgiTheme.egaWhite),
            _buildMetricPill('White', '$whiteCount px', AgiTheme.egaWhite),
            _buildMetricPill('Transparent', '$transparentCount px', AgiTheme.egaCyan),
            if (grayCount > 0)
              _buildMetricPill('Gray', '$grayCount px', AgiTheme.egaMuted),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AgiTheme.egaCardSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted)),
          Text(
            value,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Interactive Live Testing Sandbox (Right Pane)
  // ===========================================================================

  Widget _buildInteractiveSandbox(SciCursor cursor) {
    return Column(
      children: [
        // Sandbox header & controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: AgiTheme.egaDarkSurface,
            border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.mouse, size: 16, color: AgiTheme.egaGreen),
              const SizedBox(width: 8),
              const Text(
                'LIVE MOUSE TESTING SANDBOX',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AgiTheme.egaGreen,
                ),
              ),
              const Spacer(),
              // Scale selector
              const Text('Scale: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _sandboxScale,
                  dropdownColor: AgiTheme.egaDarkSurface,
                  style: const TextStyle(fontSize: 11, color: AgiTheme.egaGreen, fontWeight: FontWeight.bold),
                  items: const [1, 2, 3, 4]
                      .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _sandboxScale = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: AgiTheme.egaMuted),
                tooltip: 'Reset Sandbox State',
                onPressed: () {
                  setState(() {
                    _sandboxClickHistory.clear();
                    _sandboxTargetClicks = 0;
                    _sandboxItemCollected = false;
                    _sandboxDoorOpened = false;
                  });
                },
              ),
            ],
          ),
        ),

        // Subtitle instructions
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF101418),
          child: const Text(
            'Move mouse into simulated screen below. System pointer is hidden; authentic Sierra cursor tracks with exact hotspot.',
            style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
          ),
        ),

        // Interactive simulated game viewport
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MouseRegion(
              cursor: SystemMouseCursors.none,
              onEnter: (event) {
                setState(() {
                  _isMouseInSandbox = true;
                  _sandboxMousePosition = event.localPosition;
                });
              },
              onHover: (event) {
                setState(() {
                  _sandboxMousePosition = event.localPosition;
                });
              },
              onExit: (_) {
                setState(() {
                  _isMouseInSandbox = false;
                  _sandboxMousePosition = null;
                });
              },
              child: GestureDetector(
                onTapDown: (details) {
                  final pos = details.localPosition;
                  setState(() {
                    _sandboxClickHistory.add(pos);
                    if (_sandboxClickHistory.length > 20) {
                      _sandboxClickHistory.removeAt(0);
                    }
                  });
                },
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F141C),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AgiTheme.egaBorder, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Simulated retro adventure backdrop
                      _buildSimulatedBackdrop(),

                      // Interactive game targets
                      _buildInteractiveTargets(),

                      // Visual markers for click history
                      ..._sandboxClickHistory.map((pos) => Positioned(
                            left: pos.dx - 4,
                            top: pos.dy - 4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                                border: Border.all(color: AgiTheme.egaCyan.withAlpha(200), width: 1.5),
                              ),
                            ),
                          )),

                      // Authentic Sierra Cursor rendered over viewport at mouse position
                      if (_isMouseInSandbox && _sandboxMousePosition != null)
                        Positioned(
                          left: _sandboxMousePosition!.dx - (cursor.hotspotX * _sandboxScale),
                          top: _sandboxMousePosition!.dy - (cursor.hotspotY * _sandboxScale),
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: Size(16.0 * _sandboxScale, 16.0 * _sandboxScale),
                              painter: _CursorPainter(
                                cursor: cursor,
                                scale: _sandboxScale,
                                showHotspot: false,
                                showGrid: false,
                                bgMode: null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Sandbox status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AgiTheme.egaDarkSurface,
            border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
          ),
          child: Row(
            children: [
              Text(
                _sandboxMousePosition != null
                    ? 'Pointer: (${_sandboxMousePosition!.dx.toInt()}, ${_sandboxMousePosition!.dy.toInt()}) [Hotspot aligned]'
                    : 'Pointer outside sandbox canvas',
                style: const TextStyle(fontSize: 11, color: AgiTheme.egaGreen, fontFamily: 'Courier'),
              ),
              const Spacer(),
              Text(
                'Clicks: ${_sandboxClickHistory.length}',
                style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimulatedBackdrop() {
    return Column(
      children: [
        // Sky / ceiling
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF000033), Color(0xFF000055)],
              ),
            ),
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Lytton Police Department - Target Range / Desk',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF8888AA),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        // Floor / ground
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF003300), Color(0xFF002200)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractiveTargets() {
    return Stack(
      children: [
        // Target 1: Click Counter Button
        Positioned(
          left: 30,
          top: 70,
          child: InkWell(
            onTap: () {
              setState(() => _sandboxTargetClicks++);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2838),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgiTheme.egaCyan, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 20, color: AgiTheme.egaCyan),
                  const SizedBox(height: 4),
                  const Text('Click Target', style: TextStyle(fontSize: 11, color: AgiTheme.egaWhite, fontWeight: FontWeight.bold)),
                  Text('Score: $_sandboxTargetClicks', style: const TextStyle(fontSize: 10, color: AgiTheme.egaAmber)),
                ],
              ),
            ),
          ),
        ),

        // Target 2: Inventory Item (Keys)
        Positioned(
          left: 180,
          top: 100,
          child: InkWell(
            onTap: () {
              setState(() => _sandboxItemCollected = !_sandboxItemCollected);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _sandboxItemCollected ? const Color(0xFF222822) : const Color(0xFF332211),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _sandboxItemCollected ? AgiTheme.egaGreen : AgiTheme.egaAmber,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _sandboxItemCollected ? Icons.check_circle : Icons.vpn_key,
                    size: 20,
                    color: _sandboxItemCollected ? AgiTheme.egaGreen : AgiTheme.egaAmber,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sandboxItemCollected ? 'Keys Collected' : 'Locker Keys',
                    style: TextStyle(
                      fontSize: 11,
                      color: _sandboxItemCollected ? AgiTheme.egaGreen : AgiTheme.egaWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _sandboxItemCollected ? 'Click to drop' : 'Click to take',
                    style: const TextStyle(fontSize: 9, color: AgiTheme.egaMuted),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Target 3: Station Door (Toggle Open/Close)
        Positioned(
          right: 30,
          top: 60,
          child: InkWell(
            onTap: () {
              setState(() => _sandboxDoorOpened = !_sandboxDoorOpened);
            },
            child: Container(
              width: 70,
              height: 110,
              decoration: BoxDecoration(
                color: _sandboxDoorOpened ? const Color(0xFF001122) : const Color(0xFF2B1F14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaWhite, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _sandboxDoorOpened ? Icons.door_front_door : Icons.meeting_room,
                    size: 28,
                    color: _sandboxDoorOpened ? AgiTheme.egaCyan : AgiTheme.egaAmber,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _sandboxDoorOpened ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _sandboxDoorOpened ? AgiTheme.egaCyan : AgiTheme.egaAmber,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// CustomPainter for Sierra Cursor (High-precision pixel renderer)
// =============================================================================

class _CursorPainter extends CustomPainter {
  final SciCursor cursor;
  final int scale;
  final bool showHotspot;
  final bool showGrid;
  final CursorInspectorBg? bgMode;
  final Color? bgColor;
  final math.Point<int>? hoveredPixel;

  _CursorPainter({
    required this.cursor,
    required this.scale,
    this.showHotspot = true,
    this.showGrid = false,
    this.bgMode,
    this.bgColor,
    this.hoveredPixel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveScale = math.max(1, scale).toDouble();

    // 1. Draw Background
    if (bgMode != null) {
      _paintBackground(canvas, size, effectiveScale);
    } else if (bgColor != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = bgColor!);
    }

    // 2. Draw Cursor Pixels
    final paintBlack = Paint()..color = Colors.black;
    final paintWhite = Paint()..color = Colors.white;

    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final pixel = cursor.getPixel(x, y);
        if (pixel == SierraCursorPixel.transparent) continue;

        final rect = Rect.fromLTWH(
          x * effectiveScale,
          y * effectiveScale,
          effectiveScale,
          effectiveScale,
        );

        switch (pixel) {
          case SierraCursorPixel.black:
            canvas.drawRect(rect, paintBlack);
            break;
          case SierraCursorPixel.white:
          case SierraCursorPixel.gray:
            canvas.drawRect(rect, paintWhite);
            break;
          case SierraCursorPixel.transparent:
            break;
        }
      }
    }

    // 3. Draw Pixel Grid (if enabled and scale >= 4)
    if (showGrid && scale >= 4) {
      final gridPaint = Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1.0;

      for (var i = 0; i <= 16; i++) {
        final pos = i * effectiveScale;
        // Vertical line
        canvas.drawLine(Offset(pos, 0), Offset(pos, 16 * effectiveScale), gridPaint);
        // Horizontal line
        canvas.drawLine(Offset(0, pos), Offset(16 * effectiveScale, pos), gridPaint);
      }
    }

    // 4. Highlight hovered pixel
    if (hoveredPixel != null &&
        hoveredPixel!.x >= 0 &&
        hoveredPixel!.x < 16 &&
        hoveredPixel!.y >= 0 &&
        hoveredPixel!.y < 16) {
      final hx = hoveredPixel!.x * effectiveScale;
      final hy = hoveredPixel!.y * effectiveScale;
      final hoverRect = Rect.fromLTWH(hx, hy, effectiveScale, effectiveScale);
      canvas.drawRect(
        hoverRect,
        Paint()
          ..color = AgiTheme.egaCyan.withAlpha(120)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        hoverRect,
        Paint()
          ..color = AgiTheme.egaCyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 5. Draw Hotspot Marker (if enabled)
    if (showHotspot) {
      final hsX = cursor.hotspotX * effectiveScale + (effectiveScale / 2);
      final hsY = cursor.hotspotY * effectiveScale + (effectiveScale / 2);

      final hsCrosshairPaint = Paint()
        ..color = const Color(0xFFFF2222)
        ..strokeWidth = 1.5;

      final hsCenterPaint = Paint()
        ..color = const Color(0xFFFF2222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      // Crosshair lines
      canvas.drawLine(Offset(hsX - (effectiveScale * 0.8), hsY), Offset(hsX + (effectiveScale * 0.8), hsY), hsCrosshairPaint);
      canvas.drawLine(Offset(hsX, hsY - (effectiveScale * 0.8)), Offset(hsX, hsY + (effectiveScale * 0.8)), hsCrosshairPaint);

      // Target circle
      canvas.drawCircle(Offset(hsX, hsY), effectiveScale * 0.5, hsCenterPaint);
    }
  }

  void _paintBackground(Canvas canvas, Size size, double effectiveScale) {
    switch (bgMode!) {
      case CursorInspectorBg.darkCheckerboard:
        _drawCheckerboard(canvas, size, const Color(0xFF1B2129), const Color(0xFF141920), effectiveScale);
        break;
      case CursorInspectorBg.lightCheckerboard:
        _drawCheckerboard(canvas, size, const Color(0xFFE0E0E0), const Color(0xFFB0B0B0), effectiveScale);
        break;
      case CursorInspectorBg.black:
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
        break;
      case CursorInspectorBg.egaBlue:
        canvas.drawRect(Offset.zero & size, Paint()..color = EgaColors.palette[1]);
        break;
      case CursorInspectorBg.egaGreen:
        canvas.drawRect(Offset.zero & size, Paint()..color = EgaColors.palette[2]);
        break;
      case CursorInspectorBg.white:
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
        break;
    }
  }

  void _drawCheckerboard(Canvas canvas, Size size, Color color1, Color color2, double scale) {
    final paint1 = Paint()..color = color1;
    final paint2 = Paint()..color = color2;
    final checkSize = math.max(4.0, scale / 2);

    final cols = (size.width / checkSize).ceil();
    final rows = (size.height / checkSize).ceil();

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final paint = (r + c) % 2 == 0 ? paint1 : paint2;
        canvas.drawRect(
          Rect.fromLTWH(c * checkSize, r * checkSize, checkSize, checkSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) {
    return oldDelegate.cursor != cursor ||
        oldDelegate.scale != scale ||
        oldDelegate.showHotspot != showHotspot ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.bgMode != bgMode ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.hoveredPixel != hoveredPixel;
  }
}
