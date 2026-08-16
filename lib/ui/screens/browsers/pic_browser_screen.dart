import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/picture/pic_step_interpreter.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

class PicBrowserScreen extends ConsumerStatefulWidget {
  final int? initialPicNumber;

  const PicBrowserScreen({
    super.key,
    this.initialPicNumber,
  });

  @override
  ConsumerState<PicBrowserScreen> createState() => _PicBrowserScreenState();
}

class _PicBrowserScreenState extends ConsumerState<PicBrowserScreen> {
  int _selectedPicNumber = 0;
  AgiPictureRenderMode _renderMode = AgiPictureRenderMode.flatVisual;

  bool _enableCrtShader = false;
  bool _enableIntegerScale = false;
  bool _enableAspectRatioCorrection = true;
  bool _showPixelGrid = false;
  int? _isolatedPrioritySlice;

  // Hover Inspector State
  int? _hoverX;
  int? _hoverY;

  // Vector Replay State
  bool _replayMode = false;
  PicStepInterpreter? _stepInterpreter;
  int _currentStep = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  double _playbackSpeed = 1.0; // steps per tick multiplier

  // Active picture cache
  AgiPic? _currentPic;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final loader = ref.read(launcherProvider).loader;
    if (loader != null) {
      final present = loader.presentPicNumbers;
      if (widget.initialPicNumber != null && present.contains(widget.initialPicNumber)) {
        _selectedPicNumber = widget.initialPicNumber!;
      } else if (present.isNotEmpty) {
        _selectedPicNumber = present.first;
      }
      _loadPicture(_selectedPicNumber);
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _loadPicture(int picNum) {
    _playbackTimer?.cancel();
    _isPlaying = false;

    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedPicNumber = picNum;
      _isolatedPrioritySlice = null;
      _hoverX = null;
      _hoverY = null;
    });

    try {
      final pic = loader.loadPic(picNum);
      final rawData = loader.loadRawPic(picNum);
      final stepInterpreter = PicStepInterpreter(rawData, isV3: loader.meta.isV3);

      setState(() {
        _currentPic = pic;
        _stepInterpreter = stepInterpreter;
        _currentStep = stepInterpreter.totalSteps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load PICTURE $picNum: $e';
        _isLoading = false;
      });
    }
  }

  void _setStep(int step) {
    if (_stepInterpreter == null) return;
    final clamped = step.clamp(0, _stepInterpreter!.totalSteps);
    setState(() {
      _currentStep = clamped;
      _currentPic = _stepInterpreter!.renderUpToStep(clamped, computeSlices: true);
    });
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      if (_stepInterpreter == null) return;
      if (_currentStep >= _stepInterpreter!.totalSteps) {
        _setStep(0);
      }
      setState(() => _isPlaying = true);
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (!mounted || _stepInterpreter == null) {
          timer.cancel();
          return;
        }
        final next = _currentStep + (_playbackSpeed * 2).ceil();
        if (next >= _stepInterpreter!.totalSteps) {
          _setStep(_stepInterpreter!.totalSteps);
          timer.cancel();
          setState(() => _isPlaying = false);
        } else {
          _setStep(next);
        }
      });
    }
  }

  Future<void> _exportPng() async {
    if (_currentPic == null) return;

    try {
      Uint8List rgba;
      String suffix;
      switch (_renderMode) {
        case AgiPictureRenderMode.priorityMap:
          rgba = _currentPic!.renderPriorityMapRgba();
          suffix = 'priority';
          break;
        case AgiPictureRenderMode.controlMap:
          rgba = _currentPic!.renderControlMapRgba();
          suffix = 'control';
          break;
        default:
          rgba = _currentPic!.renderFlatVisualRgba();
          suffix = 'visual';
          break;
      }

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Picture #$_selectedPicNumber PNG',
        fileName: 'pic_${_selectedPicNumber.toString().padLeft(3, '0')}_$suffix.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (path != null) {
        // Convert RGBA to standard uncompressed PNG or write raw buffer
        // (A quick BMP or direct file write)
        final bmp = _encodeBmp(rgba, AgiPic.renderedWidth, AgiPic.renderedHeight);
        final file = File(path.endsWith('.bmp') || path.endsWith('.png') ? path : '$path.bmp');
        await file.writeAsBytes(bmp);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported picture to ${file.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AgiTheme.egaRed),
        );
      }
    }
  }

  Uint8List _encodeBmp(Uint8List rgba, int width, int height) {
    // Standard 32-bit BMP header
    final headerSize = 54;
    final imageSize = width * height * 4;
    final fileSize = headerSize + imageSize;
    final bytes = Uint8List(fileSize);
    final bd = ByteData.sublistView(bytes);

    // BM header
    bytes[0] = 0x42; // 'B'
    bytes[1] = 0x4D; // 'M'
    bd.setUint32(2, fileSize, Endian.little);
    bd.setUint32(10, headerSize, Endian.little);

    // DIB header
    bd.setUint32(14, 40, Endian.little);
    bd.setInt32(18, width, Endian.little);
    bd.setInt32(22, -height, Endian.little); // top-down
    bd.setUint16(26, 1, Endian.little);
    bd.setUint16(28, 32, Endian.little); // 32 bpp
    bd.setUint32(34, imageSize, Endian.little);

    // Convert RGBA to BGRA
    var dstIdx = headerSize;
    for (var i = 0; i < rgba.length; i += 4) {
      bytes[dstIdx + 0] = rgba[i + 2]; // B
      bytes[dstIdx + 1] = rgba[i + 1]; // G
      bytes[dstIdx + 2] = rgba[i + 0]; // R
      bytes[dstIdx + 3] = rgba[i + 3]; // A
      dstIdx += 4;
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentPics = loader?.presentPicNumbers ?? [];

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: _buildAppBar(presentPics),
      body: Row(
        children: [
          // Left & Center Main Viewport Area
          Expanded(
            child: Column(
              children: [
                _buildDisplayControlsBar(),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        color: const Color(0xFF080B0F),
                        child: _buildCanvasArea(),
                      ),
                      if (_hoverX != null && _hoverY != null && _currentPic != null)
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: _buildInspectorHud(),
                        ),
                    ],
                  ),
                ),
                if (_replayMode && _stepInterpreter != null)
                  _buildReplayBar(),
              ],
            ),
          ),

          // Right Sidebar: Priority Slice & Layer Inspector (only shown in Composited mode)
          if (_renderMode == AgiPictureRenderMode.compositedSlices)
            _buildSliceInspectorSidebar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentPics) {
    final currentIndex = presentPics.indexOf(_selectedPicNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < presentPics.length - 1;

    return AppBar(
      backgroundColor: AgiTheme.egaDarkSurface,
      elevation: 0,
      titleSpacing: 0,
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
              color: const Color(0xFF003344),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaCyan),
            ),
            child: const Text(
              'PIC BROWSER',
              style: TextStyle(
                color: AgiTheme.egaCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Picture Selector Navigation
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: hasPrev ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasPrev ? () => _loadPicture(presentPics[currentIndex - 1]) : null,
            tooltip: 'Previous Picture',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentPics.contains(_selectedPicNumber) ? _selectedPicNumber : null,
              dropdownColor: AgiTheme.egaCardSurface,
              style: const TextStyle(
                color: AgiTheme.egaWhite,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: presentPics.map((picNum) {
                return DropdownMenuItem<int>(
                  value: picNum,
                  child: Text('PICTURE $picNum'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _loadPicture(val);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasNext ? () => _loadPicture(presentPics[currentIndex + 1]) : null,
            tooltip: 'Next Picture',
          ),

          if (_currentPic != null) ...[
            const SizedBox(width: 12),
            Text(
              '${_currentPic!.activeSlices.length} Active Slices • ${_stepInterpreter?.totalSteps ?? 0} Vector Ops',
              style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.file_download, color: AgiTheme.egaAmber),
          onPressed: _exportPng,
          tooltip: 'Export Image (PNG/BMP)',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDisplayControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // View Mode Selector
            SegmentedButton<AgiPictureRenderMode>(
              segments: const [
                ButtonSegment(
                  value: AgiPictureRenderMode.flatVisual,
                  label: Text('Visual'),
                  icon: Icon(Icons.image, size: 14),
                ),
                ButtonSegment(
                  value: AgiPictureRenderMode.priorityMap,
                  label: Text('Priority'),
                  icon: Icon(Icons.layers, size: 14),
                ),
                ButtonSegment(
                  value: AgiPictureRenderMode.controlMap,
                  label: Text('Control'),
                  icon: Icon(Icons.security, size: 14),
                ),
                ButtonSegment(
                  value: AgiPictureRenderMode.compositedSlices,
                  label: Text('Composited'),
                  icon: Icon(Icons.auto_awesome_motion, size: 14),
                ),
              ],
              selected: {_renderMode},
              onSelectionChanged: (set) {
                setState(() {
                  _renderMode = set.first;
                  _isolatedPrioritySlice = null;
                });
              },
            ),
            const SizedBox(width: 16),

            // Display Toggles (CRT Shader, Integer Scale, 4:3 Ratio, Vector Replay, Grid)
            FilterChip(
              label: const Text('CRT Shader'),
              selected: _enableCrtShader,
              onSelected: (val) => setState(() => _enableCrtShader = val),
              avatar: Icon(
                Icons.tv,
                size: 14,
                color: _enableCrtShader ? AgiTheme.egaGreen : AgiTheme.egaMuted,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Integer Scale'),
              selected: _enableIntegerScale,
              onSelected: (val) => setState(() => _enableIntegerScale = val),
              avatar: Icon(
                Icons.crop_free,
                size: 14,
                color: _enableIntegerScale ? AgiTheme.egaCyan : AgiTheme.egaMuted,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('4:3 Ratio'),
              selected: _enableAspectRatioCorrection,
              onSelected: (val) => setState(() => _enableAspectRatioCorrection = val),
              avatar: Icon(
                Icons.aspect_ratio,
                size: 14,
                color: _enableAspectRatioCorrection ? AgiTheme.egaAmber : AgiTheme.egaMuted,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Grid'),
              selected: _showPixelGrid,
              onSelected: (val) => setState(() => _showPixelGrid = val),
              avatar: Icon(
                Icons.grid_4x4,
                size: 14,
                color: _showPixelGrid ? AgiTheme.egaMagenta : AgiTheme.egaMuted,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Vector Replay'),
              selected: _replayMode,
              onSelected: (val) {
                setState(() {
                  _replayMode = val;
                  if (!val) {
                    _playbackTimer?.cancel();
                    _isPlaying = false;
                    _loadPicture(_selectedPicNumber);
                  }
                });
              },
              avatar: Icon(
                Icons.draw,
                size: 14,
                color: _replayMode ? AgiTheme.egaGreen : AgiTheme.egaMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AgiTheme.egaCyan));
    }
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: AgiTheme.egaRed)),
      );
    }
    if (_currentPic == null) {
      return const Center(
        child: Text('No picture selected.', style: TextStyle(color: AgiTheme.egaMuted)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: AgiPictureWidget(
        picture: _currentPic!,
        renderMode: _renderMode,
        enableCrtShader: _enableCrtShader,
        enableIntegerScaling: _enableIntegerScale,
        enableAspectRatioCorrection: _enableAspectRatioCorrection,
        showPixelGrid: _showPixelGrid,
        isolatedPrioritySlice: _isolatedPrioritySlice,
        onHoverPixel: (x, y) {
          setState(() {
            _hoverX = x;
            _hoverY = y;
          });
        },
        onExitHover: () {
          setState(() {
            _hoverX = null;
            _hoverY = null;
          });
        },
      ),
    );
  }

  Widget _buildInspectorHud() {
    final x = _hoverX!;
    final y = _hoverY!;
    final pic = _currentPic!;

    final isInsidePicture = y < AgiPic.nativeHeight && x < AgiPic.nativeWidth;

    final colorIdx = isInsidePicture
        ? pic.visualPixels[y * AgiPic.nativeWidth + x]
        : 0;
    final color = colorIdx < EgaColors.palette.length ? EgaColors.palette[colorIdx] : Colors.black;
    final colorName = isInsidePicture
        ? (colorIdx < EgaColors.colorNames.length ? EgaColors.colorNames[colorIdx] : '$colorIdx')
        : 'Border';

    final rawPri = isInsidePicture ? pic.priorityAtPixel(x, y) : 0;
    final effPri = isInsidePicture ? pic.effectivePriorityAtPixel(x, y) : 0;

    String controlDesc;
    if (!isInsidePicture) {
      controlDesc = 'Text Area / Border';
    } else if (rawPri == 0) {
      controlDesc = 'Unconditional Barrier (0)';
    } else if (rawPri == 1) {
      controlDesc = 'Conditional Barrier (1)';
    } else if (rawPri == 2) {
      controlDesc = 'Trigger / Alarm (2)';
    } else if (rawPri == 3) {
      controlDesc = 'Water (3)';
    } else {
      controlDesc = 'None (Depth Band $rawPri)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgiTheme.egaBorder),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Coordinate badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'X: $x  Y: $y',
              style: const TextStyle(
                color: AgiTheme.egaCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Visual Color
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Color $colorIdx ($colorName)',
            style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 12),
          ),
          const SizedBox(width: 14),

          // Priority Band
          Text(
            'Priority: $rawPri (Effective: $effPri)',
            style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
          ),
          const SizedBox(width: 14),

          // Control Attributes
          Text(
            'Control: $controlDesc',
            style: TextStyle(
              color: rawPri < 4 ? AgiTheme.egaGreen : AgiTheme.egaMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplayBar() {
    final stepInterp = _stepInterpreter!;
    final total = stepInterp.totalSteps;
    final currentOp = (_currentStep > 0 && _currentStep <= total)
        ? stepInterp.steps[_currentStep - 1]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Replay playback controls
              IconButton(
                icon: const Icon(Icons.first_page),
                color: AgiTheme.egaCyan,
                onPressed: () => _setStep(0),
                tooltip: 'Reset to Beginning',
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                color: AgiTheme.egaCyan,
                onPressed: _currentStep > 0 ? () => _setStep(_currentStep - 1) : null,
                tooltip: 'Step Backward',
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                color: AgiTheme.egaGreen,
                onPressed: _togglePlayback,
                tooltip: _isPlaying ? 'Pause' : 'Play Drawing',
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                color: AgiTheme.egaCyan,
                onPressed: _currentStep < total ? () => _setStep(_currentStep + 1) : null,
                tooltip: 'Step Forward',
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                color: AgiTheme.egaCyan,
                onPressed: () => _setStep(total),
                tooltip: 'Jump to End',
              ),

              const SizedBox(width: 8),
              // Step counter
              Text(
                'Step $_currentStep / $total',
                style: const TextStyle(
                  color: AgiTheme.egaWhite,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),

              // Slider
              Expanded(
                child: Slider(
                  value: _currentStep.toDouble(),
                  min: 0,
                  max: total.toDouble(),
                  activeColor: AgiTheme.egaCyan,
                  inactiveColor: AgiTheme.egaBorder,
                  onChanged: (val) => _setStep(val.round()),
                ),
              ),

              // Speed selector
              DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: _playbackSpeed,
                  dropdownColor: AgiTheme.egaCardSurface,
                  style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: 0.5, child: Text('0.5x Speed')),
                    DropdownMenuItem(value: 1.0, child: Text('1x Speed')),
                    DropdownMenuItem(value: 2.0, child: Text('2x Speed')),
                    DropdownMenuItem(value: 5.0, child: Text('5x Speed')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _playbackSpeed = v);
                  },
                ),
              ),
            ],
          ),

          if (currentOp != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Opcode 0x${currentOp.opcode.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: AgiTheme.egaCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${currentOp.commandName}: ${currentOp.description}',
                  style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSliceInspectorSidebar() {
    final pic = _currentPic;

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(left: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.layers, size: 16, color: AgiTheme.egaAmber),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'PRIORITY SLICES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: AgiTheme.egaAmber,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isolatedPrioritySlice != null)
                  InkWell(
                    onTap: () => setState(() => _isolatedPrioritySlice = null),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, size: 12, color: AgiTheme.egaCyan),
                        SizedBox(width: 4),
                        Text(
                          'Show All',
                          style: TextStyle(fontSize: 11, color: AgiTheme.egaCyan),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: pic == null
                ? const Center(
                    child: Text('No slices', style: TextStyle(color: AgiTheme.egaMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: 16, // Slices 15 down to 0
                    itemBuilder: (context, index) {
                      final p = 15 - index;
                      final slice = pic.getSlice(p);
                      final hasPixels = slice != null && slice.hasVisiblePixels;
                      final isIsolated = _isolatedPrioritySlice == p;
                      final isVisible = hasPixels && (_isolatedPrioritySlice == null || isIsolated);

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: isIsolated,
                          selectedTileColor: const Color(0xFF1F6FEB).withValues(alpha: 0.2),
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: EgaColors.palette[p],
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                          title: Text(
                            p == 15 ? 'Base 15 (Sky)' : 'Depth Band $p',
                            style: TextStyle(
                              fontSize: 12,
                              color: hasPixels ? AgiTheme.egaWhite : AgiTheme.egaMuted,
                              fontWeight: isIsolated ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: !hasPixels
                              ? const Text('Empty', style: TextStyle(fontSize: 10, color: AgiTheme.egaMuted))
                              : isVisible
                                  ? Icon(
                                      Icons.visibility,
                                      size: 14,
                                      color: isIsolated ? AgiTheme.egaCyan : AgiTheme.egaGreen,
                                    )
                                  : const Icon(
                                      Icons.visibility_off,
                                      size: 14,
                                      color: AgiTheme.egaMuted,
                                    ),
                          onTap: hasPixels
                              ? () {
                                  setState(() {
                                    if (isIsolated) {
                                      _isolatedPrioritySlice = null;
                                    } else {
                                      _isolatedPrioritySlice = p;
                                      _renderMode = AgiPictureRenderMode.compositedSlices;
                                    }
                                  });
                                }
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
