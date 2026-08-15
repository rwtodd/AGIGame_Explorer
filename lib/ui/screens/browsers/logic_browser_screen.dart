import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_highlighter.dart';
import 'package:flutter_agigame/logic/disassembler/instruction_decoder.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/objects_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/pic_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/sound_browser_screen.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';

class LogicBrowserScreen extends ConsumerStatefulWidget {
  final int? initialLogicNumber;

  const LogicBrowserScreen({super.key, this.initialLogicNumber});

  @override
  ConsumerState<LogicBrowserScreen> createState() => _LogicBrowserScreenState();
}

class _LogicHistoryEntry {
  final int logicNumber;
  final int tabIndex;
  final double disassemblyScrollOffset;
  final double messagesScrollOffset;
  final int? highlightedLineIndex;

  const _LogicHistoryEntry({
    required this.logicNumber,
    required this.tabIndex,
    required this.disassemblyScrollOffset,
    required this.messagesScrollOffset,
    this.highlightedLineIndex,
  });
}

class _LogicBrowserScreenState extends ConsumerState<LogicBrowserScreen>
    with SingleTickerProviderStateMixin {
  int _selectedLogicNumber = 0;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _disassemblyScrollController = ScrollController();
  final ScrollController _messagesScrollController = ScrollController();

  final List<_LogicHistoryEntry> _historyStack = [];

  AgiLogicScript? _currentScript;
  List<DisassemblyLine> _disassemblyLines = [];
  String _exportDisassemblyText = '';
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  // Active line / message highlight for jump-to orientation
  int? _highlightedLineIndex;
  int? _highlightedMessageNum;
  Timer? _highlightTimer;

  // Search match navigation state
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final loader = ref.read(launcherProvider).loader;
    if (loader != null) {
      final present = loader.presentLogicNumbers;
      if (widget.initialLogicNumber != null && present.contains(widget.initialLogicNumber)) {
        _selectedLogicNumber = widget.initialLogicNumber!;
      } else if (present.isNotEmpty) {
        _selectedLogicNumber = present.first;
      }
      _loadLogic(_selectedLogicNumber);
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _disassemblyScrollController.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  /// Navigates to a script manually (via dropdown or chevrons), resetting the jump history.
  void _selectLogic(int targetLogicNum) {
    if (targetLogicNum == _selectedLogicNumber) return;
    _historyStack.clear();
    _loadLogic(targetLogicNum);
  }

  /// Hyper-links to a logic script from a code chip, saving the current location to the history stack.
  void _jumpToLogic(int targetLogicNum) {
    if (targetLogicNum == _selectedLogicNumber) return;

    final currentEntry = _LogicHistoryEntry(
      logicNumber: _selectedLogicNumber,
      tabIndex: _tabController.index,
      disassemblyScrollOffset: _disassemblyScrollController.hasClients
          ? _disassemblyScrollController.offset
          : 0.0,
      messagesScrollOffset:
          _messagesScrollController.hasClients ? _messagesScrollController.offset : 0.0,
      highlightedLineIndex: _highlightedLineIndex,
    );
    _historyStack.add(currentEntry);

    _loadLogic(targetLogicNum);
  }

  /// Handles the back action: pops from history stack if available, otherwise pops screen.
  void _handleBack() {
    if (_historyStack.isNotEmpty) {
      final prev = _historyStack.removeLast();
      _loadLogic(prev.logicNumber, restoreHistory: prev);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _loadLogic(int logicNum, {_LogicHistoryEntry? restoreHistory}) {
    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

    _highlightTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedLogicNumber = logicNum;
      _highlightedLineIndex = restoreHistory?.highlightedLineIndex;
      _highlightedMessageNum = null;
      _currentMatchIndex = 0;
    });

    if (restoreHistory == null) {
      // Reset scroll positions when loading a new script without history
      if (_disassemblyScrollController.hasClients) {
        _disassemblyScrollController.jumpTo(0);
      }
      if (_messagesScrollController.hasClients) {
        _messagesScrollController.jumpTo(0);
      }
    }

    try {
      final script = loader.loadLogic(logicNum);
      final disContext = DisassemblyContext(
        script: script,
        dictionary: loader.dictionary,
        objects: loader.initialObjects,
      );

      final formatter = DisassemblyFormatter(context: disContext);
      // Full export text includes the message header table wholesale
      final fullExportText = formatter.formatScript(
        script,
        version: loader.meta.version,
        includeMessages: true,
      );

      // UI disassembly lines tokenized directly from the AST (no message header dump)
      final decoder = InstructionDecoder(version: loader.meta.version);
      final ast = decoder.decode(script.bytecodes);
      final lines = DisassemblyHighlighter.tokenizeToLines(ast, context: disContext);

      setState(() {
        _currentScript = script;
        _disassemblyLines = lines;
        _exportDisassemblyText = fullExportText;
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
          if (_messagesScrollController.hasClients) {
            _messagesScrollController.jumpTo(
              math.min(
                restoreHistory.messagesScrollOffset,
                _messagesScrollController.position.maxScrollExtent,
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
        _errorMessage = 'Failed to load LOGIC $logicNum: $e';
        _isLoading = false;
      });
    }
  }

  /// Jumps to a line in the Disassembly view with surrounding context above & below.
  void _jumpToLine(int lineIndex, {bool clearFilter = false}) {
    if (lineIndex < 0 || lineIndex >= _disassemblyLines.length) return;

    if (clearFilter && (_searchQuery.isNotEmpty || _searchController.text.isNotEmpty)) {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
        _currentMatchIndex = 0;
      });
    }

    if (_tabController.index != 0) {
      _tabController.index = 0;
    }

    // Always trigger highlight timer unconditionally so it never stays stuck
    _triggerLineHighlight(lineIndex);

    // Scroll when layout / controller is ready
    _scrollToDisassemblyLine(lineIndex);
  }

  void _scrollToDisassemblyLine(int lineIndex, {int attempts = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_disassemblyScrollController.hasClients &&
          _disassemblyScrollController.position.hasContentDimensions) {
        const double lineHeight = 24.0;
        const double topPadding = 12.0;
        final viewportHeight = _disassemblyScrollController.position.viewportDimension;
        final lineCenter = topPadding + (lineIndex * lineHeight) + (lineHeight / 2);
        final targetOffset = math.max(0.0, lineCenter - (viewportHeight / 2));

        _disassemblyScrollController.animateTo(
          math.min(targetOffset, _disassemblyScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else if (attempts < 10) {
        Future.delayed(const Duration(milliseconds: 30), () {
          if (mounted) {
            _scrollToDisassemblyLine(lineIndex, attempts: attempts + 1);
          }
        });
      }
    });
  }

  /// Jumps to a specific address in the bytecode disassembly.
  void _jumpToAddress(int targetAddress) {
    final lineIndex = _disassemblyLines.indexWhere((line) => line.address == targetAddress);
    if (lineIndex != -1) {
      _jumpToLine(lineIndex);
    } else {
      // Find the closest instruction line at or before targetAddress
      var closestIdx = -1;
      var minDiff = 999999;
      for (var i = 0; i < _disassemblyLines.length; i++) {
        final addr = _disassemblyLines[i].address;
        if (addr != null) {
          final diff = (addr - targetAddress).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestIdx = i;
          }
        }
      }
      if (closestIdx != -1) {
        _jumpToLine(closestIdx);
      }
    }
  }

  /// Jumps to a message in the Messages tab with surrounding context.
  void _jumpToMessage(int messageNum, {bool clearFilter = false}) {
    final script = _currentScript;
    if (script == null || messageNum < 1 || messageNum > script.messageCount) return;

    if (clearFilter && (_searchQuery.isNotEmpty || _searchController.text.isNotEmpty)) {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
        _currentMatchIndex = 0;
      });
    }

    if (_tabController.index != 1) {
      _tabController.index = 1;
    }

    _triggerMessageHighlight(messageNum);

    _scrollToMessage(messageNum);
  }

  void _scrollToMessage(int messageNum, {int attempts = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_messagesScrollController.hasClients &&
          _messagesScrollController.position.hasContentDimensions) {
        const double cardHeight = 58.0;
        const double topPadding = 16.0;
        final viewportHeight = _messagesScrollController.position.viewportDimension;
        final index = messageNum - 1;
        final cardCenter = topPadding + (index * cardHeight) + (cardHeight / 2);
        final targetOffset = math.max(0.0, cardCenter - (viewportHeight / 2));

        _messagesScrollController.animateTo(
          math.min(targetOffset, _messagesScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else if (attempts < 10) {
        Future.delayed(const Duration(milliseconds: 30), () {
          if (mounted) {
            _scrollToMessage(messageNum, attempts: attempts + 1);
          }
        });
      }
    });
  }

  /// Finds where a message is used in the disassembly and jumps to that line.
  void _findMessageInDisassembly(int messageNum) {
    final pattern = RegExp('\\%m$messageNum\\b');
    var lineIndex = _disassemblyLines.indexWhere(
      (line) => line.targetMessageNum == messageNum || pattern.hasMatch(line.rawText),
    );

    if (lineIndex == -1) {
      // Check if any line comment contains the message text
      final msgText = _currentScript?.getMessage(messageNum);
      if (msgText != null && msgText.trim().isNotEmpty && msgText.trim().length >= 3) {
        final cleanMsg = msgText.trim();
        lineIndex = _disassemblyLines.indexWhere(
          (line) => line.rawText.contains(cleanMsg),
        );
      }
    }

    if (lineIndex != -1) {
      _jumpToLine(lineIndex, clearFilter: true);
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: AgiTheme.egaAmber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Message %m$messageNum is in the messages table, but not directly referenced in LOGIC $_selectedLogicNumber bytecode.',
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _triggerLineHighlight(int lineIndex) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedLineIndex = lineIndex;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _highlightedLineIndex = null);
      }
    });
  }

  void _triggerMessageHighlight(int messageNum) {
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageNum = messageNum;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _highlightedMessageNum = null);
      }
    });
  }

  /// Prompt for "Go to Address" jump.
  void _showGoToAddressDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgiTheme.egaDarkSurface,
        title: const Text('Go to Bytecode Address', style: TextStyle(color: AgiTheme.egaCyan, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter hex address (e.g. 00A0 or 0x01A0):', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
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
            child: const Text('Go', style: TextStyle(color: Color(0xFF002233), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _processAddressJump(String input) {
    final clean = input.trim().replaceAll('0x', '').replaceAll('0X', '');
    final addr = int.tryParse(clean, radix: 16);
    if (addr != null) {
      _jumpToAddress(addr);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid hex address')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentLogics = loader?.presentLogicNumbers ?? [];
    final presentViews = loader?.presentViewNumbers ?? [];
    final presentPics = loader?.presentPicNumbers ?? [];
    final presentSounds = loader?.presentSoundNumbers ?? [];
    final objectCount = loader?.initialObjects.length ?? 0;

    return PopScope(
      canPop: _historyStack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AgiTheme.egaBlack,
        appBar: _buildAppBar(presentLogics),
        body: Column(
          children: [
            _buildSearchAndTabBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AgiTheme.egaGreen))
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!, style: const TextStyle(color: AgiTheme.egaRed)))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildDisassemblyTab(
                              presentLogics: presentLogics,
                              presentViews: presentViews,
                              presentPics: presentPics,
                              presentSounds: presentSounds,
                              objectCount: objectCount,
                            ),
                            _buildMessagesTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentLogics) {
    final currentIndex = presentLogics.indexOf(_selectedLogicNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < presentLogics.length - 1;

    final hasHistory = _historyStack.isNotEmpty;
    final backTooltip = hasHistory
        ? 'Back to LOGIC ${_historyStack.last.logicNumber}'
        : 'Back to Overview';

    return AppBar(
      backgroundColor: AgiTheme.egaDarkSurface,
      elevation: 0,
      leadingWidth: hasHistory ? 96 : null,
      leading: hasHistory
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.arrow_back, color: AgiTheme.egaAmber),
                  onPressed: _handleBack,
                  tooltip: backTooltip,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.home, size: 20, color: AgiTheme.egaCyan),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Exit to Overview',
                ),
              ],
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back, color: AgiTheme.egaCyan),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back to Overview',
            ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF003311),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaGreen),
            ),
            child: const Text(
              'LOGIC BROWSER',
              style: TextStyle(
                color: AgiTheme.egaGreen,
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
            onPressed: hasPrev ? () => _selectLogic(presentLogics[currentIndex - 1]) : null,
            tooltip: 'Previous Script',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentLogics.contains(_selectedLogicNumber) ? _selectedLogicNumber : null,
              dropdownColor: AgiTheme.egaCardSurface,
              style: const TextStyle(
                color: AgiTheme.egaWhite,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: presentLogics.map((logicNum) {
                return DropdownMenuItem<int>(
                  value: logicNum,
                  child: Text('LOGIC $logicNum'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _selectLogic(val);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasNext ? () => _selectLogic(presentLogics[currentIndex + 1]) : null,
            tooltip: 'Next Script',
          ),

          if (_currentScript != null) ...[
            const SizedBox(width: 12),
            Text(
              '${_currentScript!.bytecodeLength} Bytes • ${_currentScript!.messageCount} Messages',
              style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tag, color: AgiTheme.egaCyan),
          onPressed: _showGoToAddressDialog,
          tooltip: 'Go to Address (0xADDR)',
        ),
        IconButton(
          icon: const Icon(Icons.copy, color: AgiTheme.egaCyan),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _exportDisassemblyText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Disassembly & message table copied to clipboard'),
              ),
            );
          },
          tooltip: 'Copy Wholesale Disassembly (with Messages)',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchAndTabBar() {
    final matches = _computeMatches();
    final hasMatches = matches.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AgiTheme.egaGreen,
            labelColor: AgiTheme.egaGreen,
            unselectedLabelColor: AgiTheme.egaMuted,
            tabs: const [
              Tab(text: 'Disassembly Code'),
              Tab(text: 'Message Strings'),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12, color: AgiTheme.egaWhite),
                decoration: InputDecoration(
                  hintText: 'Filter script text / messages (double-click match to focus in context)...',
                  prefixIcon: const Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchQuery.isNotEmpty && hasMatches) ...[
                        Text(
                          '${_currentMatchIndex + 1}/${matches.length}',
                          style: const TextStyle(fontSize: 10, color: AgiTheme.egaAmber),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_drop_up, size: 18, color: AgiTheme.egaCyan),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Previous Match',
                          onPressed: () => _navigateMatch(-1, matches),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_drop_down, size: 18, color: AgiTheme.egaCyan),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Next Match',
                          onPressed: () => _navigateMatch(1, matches),
                        ),
                      ],
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _currentMatchIndex = 0;
                            });
                          },
                        ),
                    ],
                  ),
                ),
                onChanged: (v) {
                  setState(() {
                    _searchQuery = v.trim().toLowerCase();
                    _currentMatchIndex = 0;
                  });
                },
                onSubmitted: (_) {
                  if (hasMatches) {
                    _navigateMatch(1, matches);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _computeMatches() {
    if (_searchQuery.isEmpty) return const [];
    if (_tabController.index == 0) {
      final matches = <int>[];
      for (var i = 0; i < _disassemblyLines.length; i++) {
        if (_disassemblyLines[i].rawText.toLowerCase().contains(_searchQuery)) {
          matches.add(i);
        }
      }
      return matches;
    } else {
      final script = _currentScript;
      if (script == null) return const [];
      final matches = <int>[];
      for (var i = 1; i <= script.messageCount; i++) {
        final msg = script.getMessage(i);
        if (msg.toLowerCase().contains(_searchQuery) || '%m$i'.contains(_searchQuery)) {
          matches.add(i);
        }
      }
      return matches;
    }
  }

  void _navigateMatch(int delta, List<int> matches) {
    if (matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + delta) % matches.length;
      if (_currentMatchIndex < 0) _currentMatchIndex += matches.length;
    });

    final target = matches[_currentMatchIndex];
    if (_tabController.index == 0) {
      _jumpToLine(target);
    } else {
      _jumpToMessage(target);
    }
  }

  Widget _buildDisassemblyTab({
    required List<int> presentLogics,
    required List<int> presentViews,
    required List<int> presentPics,
    required List<int> presentSounds,
    required int objectCount,
  }) {
    final filtered = _searchQuery.isEmpty
        ? _disassemblyLines
        : _disassemblyLines.where((l) => l.rawText.toLowerCase().contains(_searchQuery)).toList();

    return SelectionArea(
      child: Container(
        color: const Color(0xFF0D1117),
        child: ListView.builder(
          key: const PageStorageKey('disassembly_list'),
          controller: _disassemblyScrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemExtent: 24.0,
          itemCount: filtered.length,
          itemBuilder: (context, idx) {
            final line = filtered[idx];
            final originalIndex = line.lineNumber - 1;
            final isHighlighted = _highlightedLineIndex == originalIndex;

            return _buildInteractiveCodeLine(
              line: line,
              originalIndex: originalIndex,
              isHighlighted: isHighlighted,
              presentLogics: presentLogics,
              presentViews: presentViews,
              presentPics: presentPics,
              presentSounds: presentSounds,
              objectCount: objectCount,
            );
          },
        ),
      ),
    );
  }

  Widget _buildInteractiveCodeLine({
    required DisassemblyLine line,
    required int originalIndex,
    required bool isHighlighted,
    required List<int> presentLogics,
    required List<int> presentViews,
    required List<int> presentPics,
    required List<int> presentSounds,
    required int objectCount,
  }) {
    final textSpans = DisassemblyHighlighter.toTextSpans(line.tokens);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 24.0,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AgiTheme.egaCyan.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isHighlighted
            ? Border.all(color: AgiTheme.egaCyan, width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {},
              onDoubleTap: () {
                // Double clicking a filtered line returns to unfiltered view, centered on clicked line
                _jumpToLine(originalIndex, clearFilter: true);
              },
              child: Text.rich(
                TextSpan(children: textSpans),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
          ),
          // Quick action chips for interactive cross-references
          if (line.targetMessageNum != null) ...[
            const SizedBox(width: 8),
            _buildReferenceChip(
              label: 'Msg %m${line.targetMessageNum}',
              color: AgiTheme.egaCyan,
              tooltip: 'Jump to message in Messages tab',
              onTap: () => _jumpToMessage(line.targetMessageNum!),
            ),
          ],
          if (line.targetAddress != null) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: '0x${line.targetAddress!.toRadixString(16).padLeft(4, '0').toUpperCase()}',
              color: AgiTheme.egaAmber,
              tooltip: 'Jump to target address',
              onTap: () => _jumpToAddress(line.targetAddress!),
            ),
          ],
          if (line.targetLogicNum != null && presentLogics.contains(line.targetLogicNum)) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: 'LOGIC ${line.targetLogicNum}',
              color: AgiTheme.egaGreen,
              tooltip: 'Navigate to LOGIC ${line.targetLogicNum}',
              onTap: () => _jumpToLogic(line.targetLogicNum!),
            ),
          ],
          if (line.targetViewNum != null && presentViews.contains(line.targetViewNum)) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: 'VIEW ${line.targetViewNum}',
              color: AgiTheme.egaMagenta,
              tooltip: 'Open VIEW ${line.targetViewNum} in View Browser',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ViewBrowserScreen(initialViewNumber: line.targetViewNum),
                  ),
                );
              },
            ),
          ],
          if (line.targetPicNum != null && presentPics.contains(line.targetPicNum)) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: 'PIC ${line.targetPicNum}',
              color: AgiTheme.egaRed,
              tooltip: 'Open PIC ${line.targetPicNum} in Picture Browser',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PicBrowserScreen(initialPicNumber: line.targetPicNum),
                  ),
                );
              },
            ),
          ],
          if (line.targetSoundNum != null && presentSounds.contains(line.targetSoundNum)) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: 'SOUND ${line.targetSoundNum}',
              color: AgiTheme.egaBlue,
              tooltip: 'Open SOUND ${line.targetSoundNum} in Sound Browser',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SoundBrowserScreen(initialSoundNumber: line.targetSoundNum),
                  ),
                );
              },
            ),
          ],
          if (line.targetInventoryNum != null && line.targetInventoryNum! < objectCount) ...[
            const SizedBox(width: 6),
            _buildReferenceChip(
              label: 'OBJ %i${line.targetInventoryNum}',
              color: AgiTheme.egaAmber,
              tooltip: 'Open item %i${line.targetInventoryNum} in Inventory/Objects Browser',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ObjectsBrowserScreen(initialObjectIndex: line.targetInventoryNum),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReferenceChip({
    required String label,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Courier',
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesTab() {
    final script = _currentScript;
    if (script == null || script.messageCount == 0) {
      return const Center(
        child: Text('No messages in this script.', style: TextStyle(color: AgiTheme.egaMuted)),
      );
    }

    final messageIndices = <int>[];
    for (var i = 1; i <= script.messageCount; i++) {
      final msg = script.getMessage(i);
      if (_searchQuery.isEmpty || msg.toLowerCase().contains(_searchQuery) || '%m$i'.contains(_searchQuery)) {
        messageIndices.add(i);
      }
    }

    return SelectionArea(
      child: ListView.separated(
        key: const PageStorageKey('messages_list'),
        controller: _messagesScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: messageIndices.length,
        separatorBuilder: (context, index) => const Divider(color: AgiTheme.egaBorder, height: 1),
        itemBuilder: (context, idx) {
          final mNum = messageIndices[idx];
          final msg = script.getMessage(mNum);
          final isHighlighted = _highlightedMessageNum == mNum;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? AgiTheme.egaCyan.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isHighlighted
                  ? Border.all(color: AgiTheme.egaCyan, width: 1.5)
                  : null,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: InkWell(
                onTap: () {},
                onDoubleTap: () => _jumpToMessage(mNum, clearFilter: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AgiTheme.egaBorder),
                  ),
                  child: Text(
                    '%m$mNum',
                    style: const TextStyle(color: AgiTheme.egaGreen, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
              title: InkWell(
                onTap: () {},
                onDoubleTap: () => _jumpToMessage(mNum, clearFilter: true),
                child: Text(
                  msg.isEmpty ? '<Empty Message>' : msg,
                  style: TextStyle(
                    color: msg.isEmpty ? AgiTheme.egaMuted : AgiTheme.egaWhite,
                    fontSize: 13,
                  ),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.code, size: 18, color: AgiTheme.egaCyan),
                    onPressed: () => _findMessageInDisassembly(mNum),
                    tooltip: 'Find in Disassembly Code',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: AgiTheme.egaMuted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: msg));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied %m$mNum')),
                      );
                    },
                    tooltip: 'Copy Message',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
