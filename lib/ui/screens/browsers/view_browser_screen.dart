import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

class ViewBrowserScreen extends ConsumerStatefulWidget {
  final int? initialViewNumber;

  const ViewBrowserScreen({super.key, this.initialViewNumber});

  @override
  ConsumerState<ViewBrowserScreen> createState() => _ViewBrowserScreenState();
}

class _ViewBrowserScreenState extends ConsumerState<ViewBrowserScreen> {
  int _selectedViewNumber = 0;
  int _selectedLoopIndex = 0;
  int _selectedCelIndex = 0;

  double _zoomScale = 4.0;
  int _fps = 10;
  bool _isPlaying = false;
  Timer? _animTimer;
  Color _canvasBg = const Color(0xFF161B22);

  AgiView? _currentView;
  ui.Image? _currentCelImage;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final loader = ref.read(launcherProvider).loader;
    if (loader != null) {
      final present = loader.presentViewNumbers;
      if (widget.initialViewNumber != null && present.contains(widget.initialViewNumber)) {
        _selectedViewNumber = widget.initialViewNumber!;
      } else if (present.isNotEmpty) {
        _selectedViewNumber = present.first;
      }
      _loadView(_selectedViewNumber);
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  void _loadView(int viewNum) {
    _animTimer?.cancel();
    _isPlaying = false;

    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedViewNumber = viewNum;
      _selectedLoopIndex = 0;
      _selectedCelIndex = 0;
    });

    try {
      final view = loader.loadView(viewNum);
      setState(() {
        _currentView = view;
        _isLoading = false;
      });
      _renderCurrentCel();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load VIEW $viewNum: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _renderCurrentCel() async {
    final view = _currentView;
    if (view == null) return;
    final cel = view.getCel(_selectedLoopIndex, _selectedCelIndex);
    if (cel == null) return;

    try {
      final rgba = cel.toRgba(
        parentView: view,
        celIndex: _selectedCelIndex,
        scaleX: 2, // 2x horizontal scaling for 160->320 aspect
        scaleY: 1,
      );

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        cel.width * 2,
        cel.height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final img = await completer.future;

      if (mounted) {
        setState(() {
          _currentCelImage = img;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  void _toggleAnimation() {
    if (_isPlaying) {
      _animTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      final view = _currentView;
      if (view == null) return;
      final loop = view.getLoop(_selectedLoopIndex);
      if (loop == null || loop.cels.isEmpty) return;

      setState(() => _isPlaying = true);
      final interval = Duration(milliseconds: (1000 / _fps).round());
      _animTimer = Timer.periodic(interval, (_) {
        if (!mounted || _currentView == null) return;
        final l = _currentView!.getLoop(_selectedLoopIndex);
        if (l == null || l.cels.isEmpty) return;

        setState(() {
          _selectedCelIndex = (_selectedCelIndex + 1) % l.cels.length;
        });
        _renderCurrentCel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentViews = loader?.presentViewNumbers ?? [];

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: _buildAppBar(presentViews),
      body: Row(
        children: [
          // Main Preview and Animation Viewport
          Expanded(
            child: Column(
              children: [
                _buildToolbar(),
                Expanded(
                  child: Container(
                    color: const Color(0xFF080B0F),
                    child: _buildViewport(),
                  ),
                ),
                _buildAnimationControls(),
              ],
            ),
          ),

          // Right Sidebar: Cel Metadata & Sprite Sheet Gallery
          _buildSidebar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentViews) {
    final currentIndex = presentViews.indexOf(_selectedViewNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < presentViews.length - 1;

    return AppBar(
      backgroundColor: AgiTheme.egaDarkSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AgiTheme.egaCyan),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back to Overview',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF440044),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaMagenta),
            ),
            child: const Text(
              'VIEW BROWSER',
              style: TextStyle(
                color: AgiTheme.egaMagenta,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),

          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: hasPrev ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasPrev ? () => _loadView(presentViews[currentIndex - 1]) : null,
            tooltip: 'Previous View',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentViews.contains(_selectedViewNumber) ? _selectedViewNumber : null,
              dropdownColor: AgiTheme.egaCardSurface,
              style: const TextStyle(
                color: AgiTheme.egaWhite,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: presentViews.map((viewNum) {
                return DropdownMenuItem<int>(
                  value: viewNum,
                  child: Text('VIEW $viewNum'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _loadView(val);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasNext ? () => _loadView(presentViews[currentIndex + 1]) : null,
            tooltip: 'Next View',
          ),

          if (_currentView != null) ...[
            const SizedBox(width: 12),
            Text(
              '${_currentView!.loopCount} Loops • ${_currentView!.totalCelsCount} Cels',
              style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          // Zoom Scale Buttons
          const Text('Zoom: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
          for (final z in [1.0, 2.0, 4.0, 6.0, 8.0]) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text('${z.toInt()}x'),
                selected: _zoomScale == z,
                onSelected: (sel) {
                  if (sel) setState(() => _zoomScale = z);
                },
              ),
            ),
          ],
          const Spacer(),

          // Canvas Background options
          const Text('Background: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
          for (final bg in [
            const Color(0xFF161B22),
            const Color(0xFF000000),
            const Color(0xFF2E3440),
            const Color(0xFFFFFFFF),
          ]) ...[
            InkWell(
              onTap: () => setState(() => _canvasBg = bg),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _canvasBg == bg ? AgiTheme.egaCyan : AgiTheme.egaBorder,
                    width: _canvasBg == bg ? 2 : 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewport() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AgiTheme.egaMagenta));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: AgiTheme.egaRed)));
    }
    if (_currentCelImage == null) {
      return const Center(child: Text('No cel selected', style: TextStyle(color: AgiTheme.egaMuted)));
    }

    final celW = _currentCelImage!.width.toDouble();
    final celH = _currentCelImage!.height.toDouble();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _canvasBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AgiTheme.egaBorder),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: CustomPaint(
          size: Size(celW * _zoomScale, celH * _zoomScale),
          painter: _RawImagePainter(image: _currentCelImage!),
        ),
      ),
    );
  }

  Widget _buildAnimationControls() {
    final view = _currentView;
    final loop = view?.getLoop(_selectedLoopIndex);
    final totalCels = loop?.celCount ?? 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          // Loop Selector
          if (view != null && view.loopCount > 0) ...[
            const Text('Loop: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedLoopIndex < view.loopCount ? _selectedLoopIndex : 0,
                dropdownColor: AgiTheme.egaCardSurface,
                style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 12, fontWeight: FontWeight.bold),
                items: List.generate(view.loopCount, (i) {
                  return DropdownMenuItem(value: i, child: Text('Loop $i (${view.loops[i].celCount} cels)'));
                }),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedLoopIndex = val;
                      _selectedCelIndex = 0;
                    });
                    _renderCurrentCel();
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Play / Pause
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            color: AgiTheme.egaGreen,
            onPressed: _toggleAnimation,
            tooltip: _isPlaying ? 'Pause Loop' : 'Play Loop',
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            color: AgiTheme.egaCyan,
            onPressed: _selectedCelIndex > 0
                ? () {
                    setState(() => _selectedCelIndex--);
                    _renderCurrentCel();
                  }
                : null,
            tooltip: 'Previous Cel',
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            color: AgiTheme.egaCyan,
            onPressed: _selectedCelIndex < totalCels - 1
                ? () {
                    setState(() => _selectedCelIndex++);
                    _renderCurrentCel();
                  }
                : null,
            tooltip: 'Next Cel',
          ),

          const SizedBox(width: 8),
          Text(
            'Cel $_selectedCelIndex / ${totalCels - 1}',
            style: const TextStyle(color: AgiTheme.egaWhite, fontWeight: FontWeight.bold, fontSize: 12),
          ),

          Expanded(
            child: Slider(
              value: _selectedCelIndex.toDouble().clamp(0, (totalCels - 1).toDouble()),
              min: 0,
              max: (totalCels - 1).toDouble() > 0 ? (totalCels - 1).toDouble() : 1,
              activeColor: AgiTheme.egaMagenta,
              inactiveColor: AgiTheme.egaBorder,
              onChanged: (val) {
                setState(() => _selectedCelIndex = val.round());
                _renderCurrentCel();
              },
            ),
          ),

          // FPS selector
          const Text('Speed: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _fps,
              dropdownColor: AgiTheme.egaCardSurface,
              style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 FPS')),
                DropdownMenuItem(value: 10, child: Text('10 FPS')),
                DropdownMenuItem(value: 20, child: Text('20 FPS')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _fps = v);
                  if (_isPlaying) {
                    _toggleAnimation();
                    _toggleAnimation();
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final view = _currentView;
    final cel = view?.getCel(_selectedLoopIndex, _selectedCelIndex);

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(left: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AgiTheme.egaMagenta),
                SizedBox(width: 8),
                Text(
                  'CEL PROPERTIES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AgiTheme.egaMagenta,
                  ),
                ),
              ],
            ),
          ),

          if (cel != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _buildPropertyRow('Resolution', '${cel.width} × ${cel.height} (scaled to ${cel.width * 2} × ${cel.height})'),
                  _buildPropertyRow('Transparent Color', 'Color ${cel.transparentColor} (${EgaColors.colorNames[cel.transparentColor]})'),
                  _buildPropertyRow('Mirrored', cel.isMirrored ? 'Yes (from Loop ${cel.mirrorLoop})' : 'No (Forward)'),
                  if (view?.description != null)
                    _buildPropertyRow('Description', view!.description!),
                ],
              ),
            ),

          const Divider(color: AgiTheme.egaBorder, height: 1),

          // Sprite Sheet Gallery
          Container(
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Icon(Icons.grid_view, size: 16, color: AgiTheme.egaCyan),
                SizedBox(width: 8),
                Text(
                  'SPRITE GALLERY',
                  style: TextStyle(
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
            child: view == null
                ? const SizedBox.shrink()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: view.loopCount,
                    itemBuilder: (context, lIdx) {
                      final loop = view.loops[lIdx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: lIdx == _selectedLoopIndex ? const Color(0xFF21262D) : const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: lIdx == _selectedLoopIndex ? AgiTheme.egaMagenta : AgiTheme.egaBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Loop $lIdx (${loop.celCount} cels)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AgiTheme.egaWhite,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(loop.celCount, (cIdx) {
                                final isSel = lIdx == _selectedLoopIndex && cIdx == _selectedCelIndex;
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedLoopIndex = lIdx;
                                      _selectedCelIndex = cIdx;
                                    });
                                    _renderCurrentCel();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSel ? AgiTheme.egaMagenta : const Color(0xFF0D1117),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSel ? Colors.white : AgiTheme.egaBorder,
                                      ),
                                    ),
                                    child: Text(
                                      'Cel $cIdx',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isSel ? Colors.white : AgiTheme.egaMuted,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RawImagePainter extends CustomPainter {
  final ui.Image image;

  const _RawImagePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _RawImagePainter oldDelegate) => oldDelegate.image != image;
}
