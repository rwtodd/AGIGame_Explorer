import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

class WordsBrowserScreen extends ConsumerStatefulWidget {
  const WordsBrowserScreen({super.key});

  @override
  ConsumerState<WordsBrowserScreen> createState() => _WordsBrowserScreenState();
}

class _WordsBrowserScreenState extends ConsumerState<WordsBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final dict = loader?.dictionary;

    final allIds = (dict?.allIds.toList() ?? [])..sort();

    final filteredIds = _searchQuery.isEmpty
        ? allIds
        : allIds.where((id) {
            final words = dict?.idToWords(id) ?? [];
            return id.toString() == _searchQuery ||
                words.any((w) => w.toLowerCase().contains(_searchQuery));
          }).toList();

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: AppBar(
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
                color: const Color(0xFF003344),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaCyan),
              ),
              child: const Text(
                'WORDS.TOK VOCABULARY',
                style: TextStyle(
                  color: AgiTheme.egaCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '${dict?.wordCount ?? 0} Words • ${dict?.groupCount ?? 0} Synonym Groups',
              style: const TextStyle(fontSize: 12, color: AgiTheme.egaMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AgiTheme.egaDarkSurface,
              border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 13, color: AgiTheme.egaWhite),
                      decoration: InputDecoration(
                        hintText: 'Search words or group ID (e.g. look, door, 15)...',
                        prefixIcon: const Icon(Icons.search, size: 16, color: AgiTheme.egaMuted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
          ),

          Expanded(
            child: filteredIds.isEmpty
                ? const Center(
                    child: Text('No words found.', style: TextStyle(color: AgiTheme.egaMuted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredIds.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final id = filteredIds[idx];
                      final words = dict?.idToWords(id) ?? [];

                      String? specialLabel;
                      if (id == 0) specialLabel = 'anyword (matches any token)';
                      if (id == 1) specialLabel = 'rol (rest of line wildcard)';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AgiTheme.egaBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF21262D),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AgiTheme.egaBorder),
                              ),
                              child: Text(
                                '%w$id',
                                style: const TextStyle(
                                  color: AgiTheme.egaCyan,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: words.map((w) {
                                      final isMatch = _searchQuery.isNotEmpty &&
                                          w.toLowerCase().contains(_searchQuery);
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMatch
                                              ? const Color(0xFF004433)
                                              : const Color(0xFF21262D),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isMatch ? AgiTheme.egaGreen : AgiTheme.egaBorder,
                                          ),
                                        ),
                                        child: Text(
                                          w,
                                          style: TextStyle(
                                            color: isMatch ? AgiTheme.egaGreen : AgiTheme.egaWhite,
                                            fontWeight: isMatch ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  if (specialLabel != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      specialLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AgiTheme.egaAmber,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16, color: AgiTheme.egaMuted),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: words.join(', ')));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Copied synonyms for %w$id')),
                                );
                              },
                              tooltip: 'Copy Synonyms',
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
}
