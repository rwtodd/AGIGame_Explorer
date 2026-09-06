import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/sierra_font.dart';
import 'package:flutter_agigame/sci/font/sci_font.dart';
import 'package:flutter_agigame/sci/font/sci_font_parser.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

/// Diagnostic workbench browser for authentic Sierra SCI 1-bit typography resources.
class FontBrowserScreen extends ConsumerStatefulWidget {
  final int? initialFontNumber;
  final SciVolumeManager? volumeManager;

  const FontBrowserScreen({
    super.key,
    this.initialFontNumber,
    this.volumeManager,
  });

  @override
  ConsumerState<FontBrowserScreen> createState() => _FontBrowserScreenState();
}

class _FontBrowserScreenState extends ConsumerState<FontBrowserScreen> {
  static const List<String> _egaColorNames = [
    '0: Black',
    '1: Blue',
    '2: Green',
    '3: Cyan',
    '4: Red',
    '5: Magenta',
    '6: Brown',
    '7: Light Gray',
    '8: Dark Gray',
    '9: Light Blue',
    '10: Light Green',
    '11: Light Cyan',
    '12: Light Red',
    '13: Light Magenta',
    '14: Yellow',
    '15: White',
  ];

  int _selectedFontNumber = 0;
  int _selectedCharCode = 65; // 'A' by default
  SciFont? _currentFont;
  bool _isLoading = false;
  String? _errorMessage;

  // Glyph Inspector settings
  int _glyphZoom = 8;
  bool _showPixelGrid = true;

  // Text Sandbox settings
  final TextEditingController _sandboxTextController = TextEditingController(
    text: 'The quick brown fox jumps over the lazy dog.\n0123456789 !@#\$%^&*()_+-=',
  );
  int _sandboxFgColorIndex = 15; // White
  int _sandboxBgColorIndex = -1; // -1 for transparent, 0..15 for EGA
  int _sandboxScale = 2;
  bool _sandboxGreyed = false;

  // Search filter
  final TextEditingController _searchController = TextEditingController();
  String _searchFilter = '';

  SciVolumeManager? get _activeVolumeManager =>
      widget.volumeManager ?? ref.read(launcherProvider).sciVolumeManager;

  List<int> _presentFontNumbers() {
    final vm = _activeVolumeManager;
    if (vm == null) return const [];
    return vm.resourceMap.numbersForType(SciResourceType.font).toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    final present = _presentFontNumbers();
    if (widget.initialFontNumber != null && present.contains(widget.initialFontNumber)) {
      _selectedFontNumber = widget.initialFontNumber!;
    } else if (present.isNotEmpty) {
      _selectedFontNumber = present.first;
    }

    if (present.isNotEmpty) {
      _loadFont(_selectedFontNumber);
    }
  }

  @override
  void dispose() {
    _sandboxTextController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadFont(int fontNum) {
    final vm = _activeVolumeManager;
    if (vm == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedFontNumber = fontNum;
    });

    try {
      final raw = vm.getResource(SciResourceType.font, fontNum);
      final font = SciFontParser.parse(raw, fontNumber: fontNum);

      // Default selection to 'A' (65) or first valid glyph
      var initialChar = 65;
      if (font.getGlyph(initialChar) == null) {
        initialChar = 0;
        for (var i = 0; i < font.numChars; i++) {
          if (font.getGlyph(i) != null) {
            initialChar = i;
            break;
          }
        }
      }

      setState(() {
        _currentFont = font;
        _selectedCharCode = initialChar;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load FONT $fontNum: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(launcherProvider);
    final presentFonts = _presentFontNumbers();

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: _buildAppBar(presentFonts),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AgiTheme.egaCyan))
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AgiTheme.egaRed, fontSize: 14),
                  ),
                )
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentFonts) {
    final fontIndex = presentFonts.indexOf(_selectedFontNumber);
    final fontName = SierraFont.standardFontName(_selectedFontNumber);

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
              'FONT $_selectedFontNumber',
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
            fontName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaWhite,
            ),
          ),
          const SizedBox(width: 12),
          if (_currentFont != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AgiTheme.egaCardSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: Text(
                '${_currentFont!.fontHeight}px Height • ${_currentFont!.validGlyphCount} / ${_currentFont!.numChars} Glyphs',
                style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AgiTheme.egaCyan),
          tooltip: 'Previous Font',
          onPressed: fontIndex > 0 ? () => _loadFont(presentFonts[fontIndex - 1]) : null,
        ),
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentFonts.contains(_selectedFontNumber) ? _selectedFontNumber : null,
              dropdownColor: AgiTheme.egaDarkSurface,
              icon: const Icon(Icons.arrow_drop_down, color: AgiTheme.egaCyan),
              style: const TextStyle(
                color: AgiTheme.egaCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              items: presentFonts
                  .map((fontNum) => DropdownMenuItem(
                        value: fontNum,
                        child: Text('Font $fontNum (${SierraFont.standardFontName(fontNum)})'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) _loadFont(val);
              },
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: AgiTheme.egaCyan),
          tooltip: 'Next Font',
          onPressed: fontIndex >= 0 && fontIndex < presentFonts.length - 1
              ? () => _loadFont(presentFonts[fontIndex + 1])
              : null,
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildBody() {
    final font = _currentFont;
    if (font == null) {
      return const Center(child: Text('No font loaded', style: TextStyle(color: AgiTheme.egaMuted)));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left pane: Glyph table palette
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: Column(
              children: [
                _buildGlyphSearchBar(),
                Expanded(child: _buildGlyphGrid(font)),
              ],
            ),
          ),
        ),

        // Right pane: Selected glyph inspector & live text sandbox
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Expanded(flex: 5, child: _buildGlyphInspector(font)),
              const Divider(color: AgiTheme.egaBorder, height: 1),
              Expanded(flex: 6, child: _buildTextSandbox(font)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlyphSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12, color: AgiTheme.egaWhite),
                decoration: InputDecoration(
                  hintText: 'Filter by character code or letter (e.g. 65, 0x41, A)...',
                  hintStyle: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  suffixIcon: _searchFilter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14, color: AgiTheme.egaMuted),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchFilter = '');
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchFilter = val.trim()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlyphGrid(SciFont font) {
    final allGlyphIndices = List.generate(font.numChars, (i) => i);

    final filteredIndices = _searchFilter.isEmpty
        ? allGlyphIndices
        : allGlyphIndices.where((code) {
            final filter = _searchFilter.toLowerCase();
            if (code.toString() == filter) return true;
            if ('0x${code.toRadixString(16).toLowerCase()}' == filter ||
                code.toRadixString(16).toLowerCase() == filter) {
              return true;
            }
            if (code >= 32 && code <= 126) {
              final ch = String.fromCharCode(code).toLowerCase();
              if (ch == filter) return true;
            }
            return false;
          }).toList();

    if (filteredIndices.isEmpty) {
      return const Center(
        child: Text('No matching glyphs found', style: TextStyle(color: AgiTheme.egaMuted)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 72,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: filteredIndices.length,
      itemBuilder: (context, idx) {
        final code = filteredIndices[idx];
        final glyph = font.getGlyph(code);
        final isSelected = code == _selectedCharCode;
        final isPrintable = code >= 32 && code <= 126;

        return InkWell(
          onTap: () => setState(() => _selectedCharCode = code),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF1E293B)
                  : (glyph != null ? AgiTheme.egaCardSurface : const Color(0xFF0F1117)),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? AgiTheme.egaCyan
                    : (glyph != null ? AgiTheme.egaBorder : Colors.transparent),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  code.toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: glyph != null && glyph.width > 0 && glyph.height > 0
                        ? CustomPaint(
                            size: Size(glyph.width.toDouble() * 1.5, glyph.height.toDouble() * 1.5),
                            painter: _GlyphThumbnailPainter(
                              glyph: glyph,
                              fgColor: isSelected ? AgiTheme.egaCyan : AgiTheme.egaWhite,
                              scale: 1.5,
                            ),
                          )
                        : Text(
                            isPrintable ? String.fromCharCode(code) : '·',
                            style: const TextStyle(fontSize: 11, color: Colors.white24),
                          ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  glyph != null ? '${glyph.width}x${glyph.height}' : 'empty',
                  style: const TextStyle(fontSize: 8, color: AgiTheme.egaMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlyphInspector(SciFont font) {
    final glyph = font.getGlyph(_selectedCharCode);
    final isPrintable = _selectedCharCode >= 32 && _selectedCharCode <= 126;
    final charDesc = isPrintable ? "'${String.fromCharCode(_selectedCharCode)}'" : 'Special / Control';

    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.zoom_in, size: 16, color: AgiTheme.egaAmber),
              const SizedBox(width: 8),
              Text(
                'GLYPH INSPECTION #$_selectedCharCode (0x${_selectedCharCode.toRadixString(16).padLeft(2, '0').toUpperCase()}) $charDesc',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AgiTheme.egaAmber,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Zoom controls
              const Text('Zoom: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
              for (final z in [4, 8, 12, 16]) ...[
                InkWell(
                  onTap: () => setState(() => _glyphZoom = z),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: _glyphZoom == z ? AgiTheme.egaCyan : AgiTheme.egaDarkSurface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${z}x',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _glyphZoom == z ? AgiTheme.egaBlack : AgiTheme.egaWhite,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              // Grid toggle
              InkWell(
                onTap: () => setState(() => _showPixelGrid = !_showPixelGrid),
                child: Row(
                  children: [
                    Icon(
                      _showPixelGrid ? Icons.grid_on : Icons.grid_off,
                      size: 14,
                      color: _showPixelGrid ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Grid',
                      style: TextStyle(
                        fontSize: 11,
                        color: _showPixelGrid ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Inspector main display
          Expanded(
            child: Row(
              children: [
                // Canvas preview
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF030712),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: Center(
                      child: glyph != null && glyph.width > 0 && glyph.height > 0
                          ? InteractiveViewer(
                              child: CustomPaint(
                                size: Size(
                                  glyph.width.toDouble() * _glyphZoom,
                                  glyph.height.toDouble() * _glyphZoom,
                                ),
                                painter: _GlyphPixelPainter(
                                  glyph: glyph,
                                  scale: _glyphZoom,
                                  showGrid: _showPixelGrid,
                                  fgColor: AgiTheme.egaWhite,
                                  bgColor: const Color(0xFF111827),
                                ),
                              ),
                            )
                          : Text(
                              'Glyph #$_selectedCharCode is unmapped or 0-width',
                              style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                            ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Metrics sidebar
                SizedBox(
                  width: 160,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AgiTheme.egaCardSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AgiTheme.egaBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'METRICS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AgiTheme.egaCyan,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _metricRow('Width', glyph != null ? '${glyph.width} px' : '-'),
                        _metricRow('Height', glyph != null ? '${glyph.height} px' : '-'),
                        _metricRow('Bytes/Row', glyph != null ? '${glyph.bytesPerRow} B' : '-'),
                        _metricRow(
                          'Data Size',
                          glyph != null ? '${glyph.rawBitmap.length} B' : '-',
                        ),
                        _metricRow(
                          'Offset',
                          glyph != null ? '0x${glyph.charOffset.toRadixString(16)}' : '-',
                        ),
                        const Divider(color: AgiTheme.egaBorder, height: 16),
                        _metricRow('Font Height', '${font.fontHeight} px'),
                        _metricRow('Slots', '${font.numChars}'),
                        _metricRow('Active', '${font.validGlyphCount}'),
                      ],
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

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AgiTheme.egaWhite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSandbox(SciFont font) {
    final text = _sandboxTextController.text;
    final measuredWidth = font.measureTextWidth(text.split('\n').first);
    final measuredHeight = font.measureTextHeight(text);

    return Container(
      color: const Color(0xFF0B0F17),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 18, color: AgiTheme.egaGreen),
              const SizedBox(width: 8),
              const Text(
                'INTERACTIVE TEXT SANDBOX',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AgiTheme.egaGreen,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Presets menu
              PopupMenuButton<String>(
                color: AgiTheme.egaDarkSurface,
                icon: const Icon(Icons.playlist_play, size: 18, color: AgiTheme.egaCyan),
                tooltip: 'Sample Presets',
                onSelected: (val) => setState(() => _sandboxTextController.text = val),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'The quick brown fox jumps over the lazy dog.',
                    child: Text('Pangram', style: TextStyle(color: AgiTheme.egaWhite, fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'Police Quest 2: The Vengeance\nSierra On-Line, Inc.',
                    child: Text('Police Quest 2 Title', style: TextStyle(color: AgiTheme.egaWhite, fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'Officer Sonny Bonds, report to Captain Dooley immediately!',
                    child: Text('PQ2 Dialog Line', style: TextStyle(color: AgiTheme.egaWhite, fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'Score: 125 of 250   Sound: ON',
                    child: Text('Status Bar Line', style: TextStyle(color: AgiTheme.egaWhite, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Options row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // FG Color
                const Text('FG: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
                DropdownButton<int>(
                  value: _sandboxFgColorIndex,
                  dropdownColor: AgiTheme.egaDarkSurface,
                  style: const TextStyle(fontSize: 11, color: AgiTheme.egaWhite),
                  items: List.generate(
                    16,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, color: EgaColors.palette[i]),
                          const SizedBox(width: 6),
                          Text(_egaColorNames[i]),
                        ],
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    if (val != null) setState(() => _sandboxFgColorIndex = val);
                  },
                ),
                const SizedBox(width: 14),

                // BG Color
                const Text('BG: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
                DropdownButton<int>(
                  value: _sandboxBgColorIndex,
                  dropdownColor: AgiTheme.egaDarkSurface,
                  style: const TextStyle(fontSize: 11, color: AgiTheme.egaWhite),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('Transparent')),
                    ...List.generate(
                      16,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, color: EgaColors.palette[i]),
                            const SizedBox(width: 6),
                            Text(_egaColorNames[i]),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sandboxBgColorIndex = val);
                  },
                ),
                const SizedBox(width: 14),

                // Scale
                const Text('Scale: ', style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted)),
                for (final s in [1, 2, 3, 4]) ...[
                  InkWell(
                    onTap: () => setState(() => _sandboxScale = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: _sandboxScale == s ? AgiTheme.egaGreen : AgiTheme.egaDarkSurface,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _sandboxScale == s ? Colors.black : AgiTheme.egaWhite,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 14),

                // Greyed stipple toggle
                InkWell(
                  onTap: () => setState(() => _sandboxGreyed = !_sandboxGreyed),
                  child: Row(
                    children: [
                      Icon(
                        _sandboxGreyed ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 14,
                        color: _sandboxGreyed ? AgiTheme.egaGreen : AgiTheme.egaMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Greyed',
                        style: TextStyle(
                          fontSize: 11,
                          color: _sandboxGreyed ? AgiTheme.egaGreen : AgiTheme.egaMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Dims: $measuredWidth x $measuredHeight px',
                  style: const TextStyle(fontSize: 10, color: AgiTheme.egaMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Text Field
          SizedBox(
            height: 48,
            child: TextField(
              controller: _sandboxTextController,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: AgiTheme.egaWhite),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                hintText: 'Type text to render with authentic Sierra bitmap font...',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),

          // Live authentic bitmap rendering viewport
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF050810),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: CustomPaint(
                    size: Size(
                      math.max(1, measuredWidth * _sandboxScale).toDouble(),
                      math.max(1, measuredHeight * _sandboxScale).toDouble(),
                    ),
                    painter: _FontTextPainter(
                      font: font,
                      text: text,
                      scale: _sandboxScale,
                      fgColor: EgaColors.palette[_sandboxFgColorIndex],
                      bgColor: _sandboxBgColorIndex >= 0
                          ? EgaColors.palette[_sandboxBgColorIndex]
                          : null,
                      greyed: _sandboxGreyed,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for rendering a single glyph thumbnail in the grid palette.
class _GlyphThumbnailPainter extends CustomPainter {
  final SierraFontGlyph glyph;
  final Color fgColor;
  final double scale;

  const _GlyphThumbnailPainter({
    required this.glyph,
    required this.fgColor,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    for (var y = 0; y < glyph.height; y++) {
      for (var x = 0; x < glyph.width; x++) {
        if (glyph.isPixelSet(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(x * scale, y * scale, scale, scale),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphThumbnailPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.fgColor != fgColor ||
      oldDelegate.scale != scale;
}

/// Custom painter for rendering a magnified glyph in the Glyph Inspector.
class _GlyphPixelPainter extends CustomPainter {
  final SierraFontGlyph glyph;
  final int scale;
  final bool showGrid;
  final Color fgColor;
  final Color bgColor;

  const _GlyphPixelPainter({
    required this.glyph,
    required this.scale,
    required this.showGrid,
    required this.fgColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pSize = scale.toDouble();
    final totalWidth = glyph.width * pSize;
    final totalHeight = glyph.height * pSize;

    // Fill background
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, totalHeight), bgPaint);

    // Draw active ink pixels
    final inkPaint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    for (var y = 0; y < glyph.height; y++) {
      for (var x = 0; x < glyph.width; x++) {
        if (glyph.isPixelSet(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(x * pSize, y * pSize, pSize, pSize),
            inkPaint,
          );
        }
      }
    }

    // Draw pixel grid lines
    if (showGrid && scale >= 4) {
      final gridPaint = Paint()
        ..color = const Color(0x22FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (var x = 0; x <= glyph.width; x++) {
        canvas.drawLine(Offset(x * pSize, 0), Offset(x * pSize, totalHeight), gridPaint);
      }
      for (var y = 0; y <= glyph.height; y++) {
        canvas.drawLine(Offset(0, y * pSize), Offset(totalWidth, y * pSize), gridPaint);
      }
    }

    // Draw outer boundary border
    final borderPaint = Paint()
      ..color = AgiTheme.egaCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, totalHeight), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GlyphPixelPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.scale != scale ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.fgColor != fgColor ||
      oldDelegate.bgColor != bgColor;
}

/// Custom painter for rendering authentic bitmap text in the Interactive Sandbox.
class _FontTextPainter extends CustomPainter {
  final SierraFont font;
  final String text;
  final int scale;
  final Color fgColor;
  final Color? bgColor;
  final bool greyed;
  static const int lineSpacing = 1;

  const _FontTextPainter({
    required this.font,
    required this.text,
    required this.scale,
    required this.fgColor,
    this.bgColor,
    this.greyed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;

    final pSize = scale.toDouble();
    final lines = text.split('\n');

    // Fill background if specified
    if (bgColor != null) {
      final bgPaint = Paint()
        ..color = bgColor!
        ..style = PaintingStyle.fill;
      canvas.drawRect(Offset.zero & size, bgPaint);
    }

    final inkPaint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    var cursorY = 0;
    for (final line in lines) {
      var cursorX = 0;
      for (var i = 0; i < line.length; i++) {
        final code = line.codeUnitAt(i);
        final glyph = font.getGlyph(code);
        if (glyph == null || glyph.width == 0) {
          continue;
        }

        for (var gy = 0; gy < glyph.height; gy++) {
          final targetY = cursorY + gy;
          final mask = greyed ? ((targetY % 2 == 1) ? 0xAA : 0x55) : 0xFF;

          for (var gx = 0; gx < glyph.width; gx++) {
            final targetX = cursorX + gx;

            if (glyph.isPixelSet(gx, gy)) {
              if (greyed && ((mask & (0x80 >> (gx & 7))) == 0)) {
                continue;
              }

              canvas.drawRect(
                Rect.fromLTWH(targetX * pSize, targetY * pSize, pSize, pSize),
                inkPaint,
              );
            }
          }
        }
        cursorX += glyph.width;
      }
      cursorY += font.fontHeight + lineSpacing;
    }
  }

  @override
  bool shouldRepaint(covariant _FontTextPainter oldDelegate) =>
      oldDelegate.font != font ||
      oldDelegate.text != text ||
      oldDelegate.scale != scale ||
      oldDelegate.fgColor != fgColor ||
      oldDelegate.bgColor != bgColor ||
      oldDelegate.greyed != greyed;
}
