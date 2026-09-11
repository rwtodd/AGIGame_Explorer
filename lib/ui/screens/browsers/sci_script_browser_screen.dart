import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_decompiler.dart';
import 'package:flutter_agigame/sci/script/sci_disassembler.dart';
import 'package:flutter_agigame/sci/script/sci_script.dart';
import 'package:flutter_agigame/sci/script/sci_script_highlighter.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';

class SciScriptBrowserScreen extends ConsumerStatefulWidget {
  final int? initialScriptNumber;
  final SciVolumeManager? volumeManager;

  const SciScriptBrowserScreen({
    super.key,
    this.initialScriptNumber,
    this.volumeManager,
  });

  @override
  ConsumerState<SciScriptBrowserScreen> createState() =>
      _SciScriptBrowserScreenState();
}

class _ScriptHistoryEntry {
  final int scriptNumber;
  final int tabIndex;
  final double disassemblyScrollOffset;
  final double decompiledScrollOffset;
  final int? highlightedLineIndex;

  const _ScriptHistoryEntry({
    required this.scriptNumber,
    required this.tabIndex,
    required this.disassemblyScrollOffset,
    required this.decompiledScrollOffset,
    this.highlightedLineIndex,
  });
}

/// Outline symbol for quick jumping.
class _CachedScriptListing {
  final SciScript script;
  final List<SciDisassemblyLine> disassemblyLines;
  final String decompiledText;
  final List<String> decompiledLines;
  final List<_OutlineSymbol> symbols;

  const _CachedScriptListing({
    required this.script,
    required this.disassemblyLines,
    required this.decompiledText,
    required this.decompiledLines,
    required this.symbols,
  });
}

class _OutlineSymbol {
  final String label;
  final int offset;
  final bool isMethod;
  final bool isProcedure;
  final bool isObject;

  const _OutlineSymbol({
    required this.label,
    required this.offset,
    this.isMethod = false,
    this.isProcedure = false,
    this.isObject = false,
  });
}

class _SciScriptBrowserScreenState
    extends ConsumerState<SciScriptBrowserScreen>
    with SingleTickerProviderStateMixin {
  int _selectedScriptNumber = 0;
  late TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _disassemblyScrollController = ScrollController();
  final ScrollController _decompiledScrollController = ScrollController();
  final ScrollController _objectsScrollController = ScrollController();
  final ScrollController _stringsScrollController = ScrollController();
  final ScrollController _exportsScrollController = ScrollController();

  final List<_ScriptHistoryEntry> _historyStack = [];

  SciScript? _currentScript;
  List<SciDisassemblyLine> _disassemblyLines = [];
  String _decompiledText = '';
  List<String> _decompiledLines = [];
  List<_OutlineSymbol> _symbols = [];
  final Map<int, _CachedScriptListing> _listingCache = {};

  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  int? _highlightedLineIndex;
  Timer? _highlightTimer;

  // Cached shared environments for symbol decoding
  SciSegManager? _segManager;
  SciKernel? _kernel;
  SciSelectors? _selectors;

  SciVolumeManager? get _activeVolumeManager =>
      widget.volumeManager ?? ref.read(launcherProvider).sciVolumeManager;

  List<int> _presentScriptNumbers() {
    final vm = _activeVolumeManager;
    if (vm == null) return const [];
    return vm.resourceMap.numbersForType(SciResourceType.script).toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    final present = _presentScriptNumbers();
    if (widget.initialScriptNumber != null &&
        present.contains(widget.initialScriptNumber)) {
      _selectedScriptNumber = widget.initialScriptNumber!;
    } else if (present.isNotEmpty) {
      _selectedScriptNumber = present.first;
    }

    if (present.isNotEmpty) {
      _loadScript(_selectedScriptNumber);
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _disassemblyScrollController.dispose();
    _decompiledScrollController.dispose();
    _objectsScrollController.dispose();
    _stringsScrollController.dispose();
    _exportsScrollController.dispose();
    super.dispose();
  }

  void _initEnvironment(SciVolumeManager vm) {
    if (_selectors == null) {
      _selectors = SciSelectors();
      try {
        final v997 = vm.getResource(SciResourceType.vocab, 997);
        _selectors!.loadVocab997(v997);
      } catch (_) {}
    }

    if (_segManager == null) {
      _segManager = SciSegManager(volumeManager: vm);
      try {
        final v996 = vm.getResource(SciResourceType.vocab, 996);
        _segManager!.loadClassTable(v996);
      } catch (_) {}
    }

    if (_kernel == null) {
      _kernel = SciKernel();
      _kernel!.selectors = _selectors!;
    }
  }

  void _selectScript(int targetScriptNum) {
    if (targetScriptNum == _selectedScriptNumber) return;
    _historyStack.clear();
    _loadScript(targetScriptNum);
  }

  void _jumpToScript(int targetScriptNum) {
    if (targetScriptNum == _selectedScriptNumber) return;

    final currentEntry = _ScriptHistoryEntry(
      scriptNumber: _selectedScriptNumber,
      tabIndex: _tabController.index,
      disassemblyScrollOffset: _disassemblyScrollController.hasClients
          ? _disassemblyScrollController.offset
          : 0.0,
      decompiledScrollOffset: _decompiledScrollController.hasClients
          ? _decompiledScrollController.offset
          : 0.0,
      highlightedLineIndex: _highlightedLineIndex,
    );
    _historyStack.add(currentEntry);

    _loadScript(targetScriptNum);
  }

  void _handleBack() {
    if (_historyStack.isNotEmpty) {
      final prev = _historyStack.removeLast();
      _loadScript(prev.scriptNumber, restoreHistory: prev);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _loadScript(int scriptNum, {_ScriptHistoryEntry? restoreHistory}) {
    final vm = _activeVolumeManager;
    if (vm == null) return;

    _highlightTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedScriptNumber = scriptNum;
      _highlightedLineIndex = restoreHistory?.highlightedLineIndex;
    });

    if (restoreHistory == null) {
      if (_disassemblyScrollController.hasClients) {
        _disassemblyScrollController.jumpTo(0);
      }
      if (_decompiledScrollController.hasClients) {
        _decompiledScrollController.jumpTo(0);
      }
    }

    try {
      _initEnvironment(vm);

      var cached = _listingCache[scriptNum];
      if (cached == null) {
        final script = _segManager!.instantiateScript(scriptNum, vm);

        final disContext = SciDisassemblyContext(
          script: script,
          selectors: _selectors,
          segManager: _segManager,
          kernel: _kernel,
        );

        final disasm = SciDisassembler(disContext);
        final disLines = disasm.disassembleScript();
        final decompiler = SciDecompiler(disContext);
        final decompText = decompiler.decompileScript();
        cached = _CachedScriptListing(
          script: script,
          disassemblyLines: disLines,
          decompiledText: decompText,
          decompiledLines: decompText.split('\n'),
          symbols: _buildOutlineSymbols(script, _selectors),
        );
        _listingCache[scriptNum] = cached;
      }

      setState(() {
        _currentScript = cached!.script;
        _disassemblyLines = cached.disassemblyLines;
        _decompiledText = cached.decompiledText;
        _decompiledLines = cached.decompiledLines;
        _symbols = cached.symbols;
        _isLoading = false;
      });

      if (restoreHistory != null) {
        _tabController.animateTo(restoreHistory.tabIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_disassemblyScrollController.hasClients) {
            _disassemblyScrollController.jumpTo(
              math.min(
                restoreHistory.disassemblyScrollOffset,
                _disassemblyScrollController.position.maxScrollExtent,
              ),
            );
          }
          if (_decompiledScrollController.hasClients) {
            _decompiledScrollController.jumpTo(
              math.min(
                restoreHistory.decompiledScrollOffset,
                _decompiledScrollController.position.maxScrollExtent,
              ),
            );
          }
          if (restoreHistory.highlightedLineIndex != null) {
            _triggerLineHighlight(restoreHistory.highlightedLineIndex!);
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load SCRIPT $scriptNum: $e';
        _isLoading = false;
      });
    }
  }

  List<_OutlineSymbol> _buildOutlineSymbols(
    SciScript script,
    SciSelectors? selectors,
  ) {
    final list = <_OutlineSymbol>[];

    // Objects and Classes
    final sortedObjects = script.objects.values.toList()
      ..sort((a, b) => a.pos.offset.compareTo(b.pos.offset));

    for (final obj in sortedObjects) {
      final name = obj.nameString ?? 'obj_0x${obj.pos.offset.toRadixString(16)}';
      list.add(
        _OutlineSymbol(
          label: '${obj.isClass ? "class" : "instance"} $name',
          offset: obj.pos.offset,
          isObject: true,
        ),
      );

      for (final m in obj.methods.entries) {
        final selName = selectors?.getSelectorName(m.key) ?? 'sel_${m.key}';
        list.add(
          _OutlineSymbol(
            label: '  $name::$selName()',
            offset: m.value,
            isMethod: true,
          ),
        );
      }
    }

    // Standalone procedures
    for (var i = 0; i < script.exports.length; i++) {
      final off = script.exports[i];
      if (!script.isObject(off)) {
        list.add(
          _OutlineSymbol(
            label: 'procedure export_$i',
            offset: off,
            isProcedure: true,
          ),
        );
      }
    }

    return list;
  }

  void _triggerLineHighlight(int lineIndex) {
    _highlightTimer?.cancel();
    setState(() => _highlightedLineIndex = lineIndex);
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _highlightedLineIndex = null);
    });
  }

  void _jumpToAddress(int address) {
    final idx = _disassemblyLines.indexWhere((l) => l.address == address);
    if (idx != -1) {
      _tabController.animateTo(1); // Disassembly tab
      _triggerLineHighlight(idx);
      _scrollToDisassemblyLine(idx);
    } else {
      _showAddressNotFoundMessage(address);
    }
  }

  void _scrollToDisassemblyLine(int lineIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_disassemblyScrollController.hasClients) {
        const lineHeight = 24.0;
        final targetOffset = math.max(0.0, lineIndex * lineHeight - 100);
        _disassemblyScrollController.animateTo(
          math.min(targetOffset, _disassemblyScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _showAddressNotFoundMessage(int address) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Address 0x${address.toRadixString(16)} not found in script.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showGoToAddressDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgiTheme.egaDarkSurface,
        title: const Text(
          'Go to Script Offset',
          style: TextStyle(color: AgiTheme.egaCyan, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter hex address (e.g. 01A4 or 0x01A4):',
              style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              style: const TextStyle(color: AgiTheme.egaWhite, fontFamily: 'Courier'),
              decoration: const InputDecoration(
                hintText: '0000',
                prefixText: '0x ',
                prefixStyle: TextStyle(color: AgiTheme.egaCyan),
              ),
              onSubmitted: (val) {
                Navigator.of(ctx).pop();
                _processAddressJump(val);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AgiTheme.egaMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AgiTheme.egaCyan),
            onPressed: () {
              Navigator.of(ctx).pop();
              _processAddressJump(textController.text);
            },
            child: const Text(
              'Go',
              style: TextStyle(color: Color(0xFF002233), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _processAddressJump(String input) {
    final clean = input.trim().replaceAll('0x', '');
    final addr = int.tryParse(clean, radix: 16);
    if (addr != null) {
      _jumpToAddress(addr);
    }
  }

  void _copyScriptToClipboard() {
    final isDecompiled = _tabController.index == 0;
    final text = isDecompiled
        ? _decompiledText
        : _disassemblyLines.map((l) => l.rawText).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${isDecompiled ? "Decompiled script" : "Disassembly"} copied to clipboard.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentScripts = _presentScriptNumbers();
    final currentIndex = presentScripts.indexOf(_selectedScriptNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex != -1 && currentIndex < presentScripts.length - 1;

    return Scaffold(
      backgroundColor: AgiTheme.egaDarkSurface,
      appBar: AppBar(
        backgroundColor: AgiTheme.egaCardSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _historyStack.isNotEmpty ? Icons.arrow_back : Icons.close,
            color: AgiTheme.egaCyan,
          ),
          tooltip: _historyStack.isNotEmpty ? 'Back to previous location' : 'Close',
          onPressed: _handleBack,
        ),
        title: Row(
          children: [
            const Icon(Icons.code, color: AgiTheme.egaGreen, size: 20),
            const SizedBox(width: 8),
            const Text(
              'SCI Script Browser',
              style: TextStyle(
                color: AgiTheme.egaWhite,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),

            // Previous Chevron
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 22),
              color: hasPrev ? AgiTheme.egaCyan : AgiTheme.egaMuted,
              tooltip: 'Previous Script',
              onPressed: hasPrev
                  ? () => _selectScript(presentScripts[currentIndex - 1])
                  : null,
            ),

            // Dropdown Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AgiTheme.egaDarkSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: presentScripts.contains(_selectedScriptNumber)
                      ? _selectedScriptNumber
                      : null,
                  dropdownColor: AgiTheme.egaCardSurface,
                  style: const TextStyle(
                    color: AgiTheme.egaCyan,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                  ),
                  items: presentScripts.map((sNum) {
                    return DropdownMenuItem<int>(
                      value: sNum,
                      child: Text('Script $sNum'),
                    );
                  }).toList(),
                  onChanged: (sNum) {
                    if (sNum != null) _selectScript(sNum);
                  },
                ),
              ),
            ),

            // Next Chevron
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 22),
              color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
              tooltip: 'Next Script',
              onPressed: hasNext
                  ? () => _selectScript(presentScripts[currentIndex + 1])
                  : null,
            ),

            const SizedBox(width: 16),

            // Outline / Quick Symbol Jump Dropdown
            if (_symbols.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AgiTheme.egaDarkSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AgiTheme.egaBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_OutlineSymbol>(
                    isExpanded: true,
                    hint: const Text(
                      'Jump to Symbol...',
                      style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                    ),
                    dropdownColor: AgiTheme.egaCardSurface,
                    style: const TextStyle(
                      color: AgiTheme.egaAmber,
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                    items: _symbols.map((sym) {
                      return DropdownMenuItem<_OutlineSymbol>(
                        value: sym,
                        child: Text(
                          sym.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (sym) {
                      if (sym != null) _jumpToAddress(sym.offset);
                    },
                  ),
                ),
              ),
          ],
        ),
        actions: [
          // Go to Address Button
          IconButton(
            icon: const Icon(Icons.navigation, color: AgiTheme.egaAmber, size: 20),
            tooltip: 'Go to Address (0x...)',
            onPressed: _showGoToAddressDialog,
          ),
          // Copy Script
          IconButton(
            icon: const Icon(Icons.copy, color: AgiTheme.egaCyan, size: 20),
            tooltip: 'Copy Script to Clipboard',
            onPressed: _copyScriptToClipboard,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AgiTheme.egaCyan,
          indicatorWeight: 3,
          labelColor: AgiTheme.egaCyan,
          unselectedLabelColor: AgiTheme.egaMuted,
          tabs: [
            const Tab(text: 'Decompiled'),
            const Tab(text: 'Disassembly'),
            Tab(text: 'Objects (${_currentScript?.objects.length ?? 0})'),
            Tab(text: 'Strings (${_currentScript?.strings.length ?? 0})'),
            Tab(text: 'Exports & Locals'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AgiTheme.egaCyan),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AgiTheme.egaRed, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AgiTheme.egaRed, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search bar for filtering
        _buildSearchBar(),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDecompiledTab(),
              _buildDisassemblyTab(),
              _buildObjectsTab(),
              _buildStringsTab(),
              _buildExportsLocalsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF131B2A),
      child: Row(
        children: [
          const Icon(Icons.search, color: AgiTheme.egaMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search script code, selectors, strings...',
                hintStyle: TextStyle(color: AgiTheme.egaMuted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
            ),
          ),
          if (_searchQuery.isNotEmpty) ...[
            Text(
              '${_getMatchCount()} matches',
              style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: AgiTheme.egaMuted, size: 16),
              tooltip: 'Clear search',
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ],
        ],
      ),
    );
  }

  int _getMatchCount() {
    if (_searchQuery.isEmpty) return 0;
    final q = _searchQuery.toLowerCase();
    if (_tabController.index == 0) {
      return _decompiledLines.where((l) => l.toLowerCase().contains(q)).length;
    } else if (_tabController.index == 1) {
      return _disassemblyLines.where((l) => l.rawText.toLowerCase().contains(q)).length;
    }
    return 0;
  }

  // --- TAB 0: Decompiled Sierra Script Language ---
  Widget _buildDecompiledTab() {
    return Container(
      color: const Color(0xFF0C101A),
      child: ListView.builder(
        controller: _decompiledScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _decompiledLines.length,
        itemBuilder: (ctx, index) {
          final line = _decompiledLines[index];
          final isHighlighted = _highlightedLineIndex == index;

          return Container(
            color: isHighlighted ? const Color(0xFF332200) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: SelectableText.rich(
              SciScriptHighlighter.highlightLine(
                line,
                searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
              ),
              style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
            ),
          );
        },
      ),
    );
  }

  // --- TAB 1: Bytecode Disassembly ---
  Widget _buildDisassemblyTab() {
    return Container(
      color: const Color(0xFF0C101A),
      child: ListView.builder(
        controller: _disassemblyScrollController,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: _disassemblyLines.length,
        itemBuilder: (ctx, index) {
          final line = _disassemblyLines[index];
          final isHighlighted = _highlightedLineIndex == index;

          if (line.isLabel) {
            return Container(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                line.label ?? '',
                style: const TextStyle(
                  color: AgiTheme.egaAmber,
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          return Container(
            color: isHighlighted ? const Color(0xFF332200) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address
                SizedBox(
                  width: 50,
                  child: Text(
                    '[${line.hexAddress}]',
                    style: const TextStyle(
                      color: Color(0xFF6B82A8),
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                  ),
                ),

                // Hex Bytes
                SizedBox(
                  width: 90,
                  child: Text(
                    line.hexBytes,
                    style: const TextStyle(
                      color: Color(0xFF8899AA),
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                  ),
                ),

                // Mnemonic & Operands
                Expanded(
                  child: SelectableText.rich(
                    SciScriptHighlighter.highlightLine(
                      '${"  " * line.indent}${line.mnemonic.padRight(8)} ${line.operands.join(", ")}'
                      '${line.comment != null ? "   ; ${line.comment}" : ""}',
                      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
                    ),
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                  ),
                ),

                // Interactive Jump Chips
                if (line.targetAddress != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => _jumpToAddress(line.targetAddress!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2D4A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaCyan),
                        ),
                        child: Text(
                          '-> 0x${line.targetAddress!.toRadixString(16).padLeft(4, "0")}',
                          style: const TextStyle(
                            color: AgiTheme.egaCyan,
                            fontSize: 11,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    ),
                  ),

                // Interactive Script Jump Chip
                if (line.targetScriptNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => _jumpToScript(line.targetScriptNumber!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E1E3A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaMagenta),
                        ),
                        child: Text(
                          'Scr ${line.targetScriptNumber}',
                          style: const TextStyle(
                            color: AgiTheme.egaMagenta,
                            fontSize: 11,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    ),
                  ),

                // View link chip
                if (line.targetViewNum != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ViewBrowserScreen(
                              initialViewNumber: line.targetViewNum,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E1E3A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaMagenta),
                        ),
                        child: Text(
                          'View ${line.targetViewNum}',
                          style: const TextStyle(
                            color: AgiTheme.egaMagenta,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Pic link chip
                if (line.targetPicNum != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PicBrowserScreen(
                              initialPicNumber: line.targetPicNum,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A2E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaGreen),
                        ),
                        child: Text(
                          'Pic ${line.targetPicNum}',
                          style: const TextStyle(
                            color: AgiTheme.egaGreen,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Sound link chip
                if (line.targetSoundNum != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SoundBrowserScreen(
                              initialSoundNumber: line.targetSoundNum,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A2E1E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AgiTheme.egaAmber),
                        ),
                        child: Text(
                          'Snd ${line.targetSoundNum}',
                          style: const TextStyle(
                            color: AgiTheme.egaAmber,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- TAB 2: Objects & Classes Inspector ---
  Widget _buildObjectsTab() {
    final script = _currentScript;
    if (script == null || script.objects.isEmpty) {
      return const Center(
        child: Text(
          'No objects or classes defined in this script.',
          style: TextStyle(color: AgiTheme.egaMuted),
        ),
      );
    }

    final sortedObjects = script.objects.values.toList()
      ..sort((a, b) => a.pos.offset.compareTo(b.pos.offset));

    return ListView.builder(
      controller: _objectsScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedObjects.length,
      itemBuilder: (ctx, index) {
        final obj = sortedObjects[index];
        final name = obj.nameString ?? 'obj_0x${obj.pos.offset.toRadixString(16)}';
        final superName = _contextClassNameFromReg(obj.superClass);

        return Card(
          color: AgiTheme.egaCardSurface,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AgiTheme.egaBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: obj.isClass ? AgiTheme.egaMagenta : AgiTheme.egaCyan,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        obj.isClass ? 'CLASS' : 'INSTANCE',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      name,
                      style: const TextStyle(
                        color: AgiTheme.egaWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'of $superName',
                      style: const TextStyle(
                        color: AgiTheme.egaAmber,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Offset: 0x${obj.pos.offset.toRadixString(16)}',
                      style: const TextStyle(
                        color: AgiTheme.egaMuted,
                        fontFamily: 'Courier',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Properties count & Methods count
                Row(
                  children: [
                    Text(
                      'Properties: ${obj.variables.length}',
                      style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Methods: ${obj.methods.length}',
                      style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 12),
                    ),
                  ],
                ),
                const Divider(color: AgiTheme.egaBorder, height: 20),

                // Methods list with click-to-jump
                if (obj.methods.isNotEmpty) ...[
                  const Text(
                    'Methods:',
                    style: TextStyle(
                      color: AgiTheme.egaCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: obj.methods.entries.map((m) {
                      final selName = _selectors?.getSelectorName(m.key) ?? 'sel_${m.key}';
                      return ActionChip(
                        backgroundColor: const Color(0xFF16253D),
                        side: const BorderSide(color: AgiTheme.egaBorder),
                        label: Text(
                          '$selName() [0x${m.value.toRadixString(16)}]',
                          style: const TextStyle(
                            color: AgiTheme.egaAmber,
                            fontFamily: 'Courier',
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () => _jumpToAddress(m.value),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _contextClassNameFromReg(SciReg superClass) {
    if (_segManager == null) return 'Class_${superClass.toUint16()}';
    if (superClass.isPointer) {
      final obj = _segManager!.getObject(superClass);
      if (obj?.nameString != null) return obj!.nameString!;
    }
    final addr = _segManager!.getClassAddress(superClass.toUint16());
    if (!addr.isNull) {
      final clObj = _segManager!.getObject(addr);
      if (clObj?.nameString != null) return clObj!.nameString!;
    }
    return 'Class_${superClass.toUint16()}';
  }

  // --- TAB 3: Strings Table ---
  Widget _buildStringsTab() {
    final script = _currentScript;
    if (script == null || script.strings.isEmpty) {
      return const Center(
        child: Text(
          'No strings extracted in this script.',
          style: TextStyle(color: AgiTheme.egaMuted),
        ),
      );
    }

    final entries = script.strings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final filtered = _searchQuery.isEmpty
        ? entries
        : entries
            .where((e) => e.value.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return ListView.builder(
      controller: _stringsScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (ctx, index) {
        final e = filtered[index];
        return Card(
          color: AgiTheme.egaCardSurface,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: AgiTheme.egaBorder),
          ),
          child: ListTile(
            dense: true,
            leading: Text(
              '0x${e.key.toRadixString(16).padLeft(4, "0")}',
              style: const TextStyle(
                color: AgiTheme.egaCyan,
                fontFamily: 'Courier',
                fontSize: 12,
              ),
            ),
            title: SelectableText(
              '"${e.value}"',
              style: const TextStyle(
                color: AgiTheme.egaGreen,
                fontFamily: 'Courier',
                fontSize: 13,
              ),
            ),
            trailing: Text(
              '${e.value.length} chars',
              style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  // --- TAB 4: Exports & Locals Table ---
  Widget _buildExportsLocalsTab() {
    final script = _currentScript;
    if (script == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      controller: _exportsScrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exports Section
          const Text(
            'Exports Table',
            style: TextStyle(
              color: AgiTheme.egaCyan,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AgiTheme.egaCardSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Index', style: TextStyle(color: AgiTheme.egaMuted))),
                DataColumn(label: Text('Offset', style: TextStyle(color: AgiTheme.egaMuted))),
                DataColumn(label: Text('Symbol', style: TextStyle(color: AgiTheme.egaMuted))),
                DataColumn(label: Text('Action', style: TextStyle(color: AgiTheme.egaMuted))),
              ],
              rows: List.generate(script.exports.length, (i) {
                final offset = script.exports[i];
                final obj = script.objects[offset];
                final isObj = obj != null;
                final name = isObj
                    ? '${obj.isClass ? "class" : "instance"} ${obj.nameString ?? ""}'
                    : 'procedure';

                return DataRow(
                  cells: [
                    DataCell(Text('$i', style: const TextStyle(color: AgiTheme.egaWhite))),
                    DataCell(
                      Text(
                        '0x${offset.toRadixString(16).padLeft(4, "0")}',
                        style: const TextStyle(
                          color: AgiTheme.egaCyan,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        name,
                        style: TextStyle(
                          color: isObj ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(
                      TextButton(
                        onPressed: () => _jumpToAddress(offset),
                        child: const Text('Jump'),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Locals Section
          const Text(
            'Local Variables',
            style: TextStyle(
              color: AgiTheme.egaCyan,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AgiTheme.egaCardSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Index', style: TextStyle(color: AgiTheme.egaMuted))),
                DataColumn(label: Text('Initial Value', style: TextStyle(color: AgiTheme.egaMuted))),
                DataColumn(label: Text('Type', style: TextStyle(color: AgiTheme.egaMuted))),
              ],
              rows: List.generate(script.locals.length, (i) {
                final reg = script.locals[i];
                return DataRow(
                  cells: [
                    DataCell(Text('local$i', style: const TextStyle(color: AgiTheme.egaWhite))),
                    DataCell(
                      Text(
                        reg.isPointer
                            ? 'ptr [${reg.segment}:${reg.offset.toRadixString(16)}]'
                            : '${reg.toUint16()} (0x${reg.toUint16().toRadixString(16)})',
                        style: const TextStyle(
                          color: AgiTheme.egaAmber,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        reg.isPointer ? 'Pointer' : 'Integer',
                        style: TextStyle(
                          color: reg.isPointer ? AgiTheme.egaMagenta : AgiTheme.egaWhite,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
