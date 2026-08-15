import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

class LogicBrowserScreen extends ConsumerStatefulWidget {
  final int? initialLogicNumber;

  const LogicBrowserScreen({super.key, this.initialLogicNumber});

  @override
  ConsumerState<LogicBrowserScreen> createState() => _LogicBrowserScreenState();
}

class _LogicBrowserScreenState extends ConsumerState<LogicBrowserScreen>
    with SingleTickerProviderStateMixin {
  int _selectedLogicNumber = 0;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  AgiLogicScript? _currentScript;
  String _disassemblyText = '';
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

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
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadLogic(int logicNum) {
    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedLogicNumber = logicNum;
    });

    try {
      final script = loader.loadLogic(logicNum);
      final formatter = DisassemblyFormatter(
        context: DisassemblyContext(
          script: script,
          dictionary: loader.dictionary,
          objects: loader.initialObjects,
        ),
      );
      final disText = formatter.formatScript(script, version: loader.meta.version);

      setState(() {
        _currentScript = script;
        _disassemblyText = disText;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load LOGIC $logicNum: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentLogics = loader?.presentLogicNumbers ?? [];

    return Scaffold(
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
                          _buildDisassemblyTab(),
                          _buildMessagesTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentLogics) {
    final currentIndex = presentLogics.indexOf(_selectedLogicNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < presentLogics.length - 1;

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
            onPressed: hasPrev ? () => _loadLogic(presentLogics[currentIndex - 1]) : null,
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
                if (val != null) _loadLogic(val);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasNext ? () => _loadLogic(presentLogics[currentIndex + 1]) : null,
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
          icon: const Icon(Icons.copy, color: AgiTheme.egaCyan),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _disassemblyText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Disassembly copied to clipboard')),
            );
          },
          tooltip: 'Copy Disassembly',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchAndTabBar() {
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
                  hintText: 'Filter script text / messages...',
                  prefixIcon: const Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisassemblyTab() {
    final lines = _disassemblyText.split('\n');
    final filteredLines = _searchQuery.isEmpty
        ? lines
        : lines.where((l) => l.toLowerCase().contains(_searchQuery)).toList();

    return Container(
      color: const Color(0xFF0D1117),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredLines.length,
        itemBuilder: (context, idx) {
          final line = filteredLines[idx];
          return _buildCodeLine(line);
        },
      ),
    );
  }

  Widget _buildCodeLine(String line) {
    Color textColor = AgiTheme.egaWhite;
    FontWeight weight = FontWeight.normal;

    if (line.trim().startsWith('[')) {
      textColor = AgiTheme.egaMuted; // Comments
    } else if (line.contains('IF-AND') || line.contains('OR') || line.contains('UNLESS')) {
      textColor = AgiTheme.egaCyan;
      weight = FontWeight.bold;
    } else if (line.contains('said(')) {
      textColor = AgiTheme.egaGreen;
      weight = FontWeight.bold;
    } else if (line.contains('GOTO')) {
      textColor = AgiTheme.egaAmber;
      weight = FontWeight.bold;
    } else if (line.contains('print(') || line.contains('display(')) {
      textColor = AgiTheme.egaMagenta;
    }

    return SelectableText(
      line,
      style: TextStyle(
        fontFamily: 'Courier',
        fontSize: 13,
        height: 1.35,
        color: textColor,
        fontWeight: weight,
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

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: messageIndices.length,
      separatorBuilder: (context, index) => const Divider(color: AgiTheme.egaBorder, height: 1),
      itemBuilder: (context, idx) {
        final mNum = messageIndices[idx];
        final msg = script.getMessage(mNum);

        return ListTile(
          leading: Container(
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
          title: SelectableText(
            msg.isEmpty ? '<Empty Message>' : msg,
            style: TextStyle(
              color: msg.isEmpty ? AgiTheme.egaMuted : AgiTheme.egaWhite,
              fontSize: 13,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 16, color: AgiTheme.egaMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied %m$mNum')),
              );
            },
            tooltip: 'Copy Message',
          ),
        );
      },
    );
  }
}
