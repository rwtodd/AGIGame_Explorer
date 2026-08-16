import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/loader/object_view_resolver.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';
import 'package:flutter_agigame/ui/screens/browsers/view_browser_screen.dart';
import 'package:flutter_agigame/ui/widgets/cel_image_widget.dart';

class ObjectsBrowserScreen extends ConsumerStatefulWidget {
  final int? initialObjectIndex;

  const ObjectsBrowserScreen({super.key, this.initialObjectIndex});

  @override
  ConsumerState<ObjectsBrowserScreen> createState() => _ObjectsBrowserScreenState();
}

class _ObjectsBrowserScreenState extends ConsumerState<ObjectsBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedObjectIndex = 0;
  int? _customViewNumberOverride;
  bool _hideDummyObjects = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialObjectIndex != null) {
      _selectedObjectIndex = widget.initialObjectIndex!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final objects = loader?.initialObjects ?? [];

    final filteredIndices = <int>[];
    for (var i = 0; i < objects.length; i++) {
      final obj = objects[i];
      if (_hideDummyObjects && (obj.name.trim().startsWith('?') || obj.name.trim().isEmpty)) {
        continue;
      }
      if (_searchQuery.isEmpty ||
          obj.name.toLowerCase().contains(_searchQuery) ||
          obj.startingRoom.toString() == _searchQuery ||
          '#$i'.contains(_searchQuery)) {
        filteredIndices.add(i);
      }
    }

    final effectiveSelectedIdx = (filteredIndices.contains(_selectedObjectIndex))
        ? _selectedObjectIndex
        : (filteredIndices.isNotEmpty ? filteredIndices.first : 0);

    final selectedObj = (objects.isNotEmpty && effectiveSelectedIdx < objects.length)
        ? objects[effectiveSelectedIdx]
        : null;

    final resolvedViewNum = selectedObj != null && loader != null
        ? ObjectViewResolver.resolveViewNumber(
            objectIndex: effectiveSelectedIdx,
            object: selectedObj,
            loader: loader,
          )
        : effectiveSelectedIdx;

    final effectiveViewNum = _customViewNumberOverride ?? resolvedViewNum;
    AgiView? associatedView;
    if (loader != null && loader.presentViewNumbers.contains(effectiveViewNum)) {
      try {
        associatedView = loader.loadView(effectiveViewNum);
      } catch (_) {
        associatedView = null;
      }
    }

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
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaWhite),
              ),
              child: const Text(
                'OBJECTS BROWSER',
                style: TextStyle(
                  color: AgiTheme.egaWhite,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '${objects.length} Inventory Objects (${loader?.maxAnimated ?? 0} Max Animated)',
              style: const TextStyle(fontSize: 12, color: AgiTheme.egaMuted),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          // Left: Search and List of Objects
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AgiTheme.egaDarkSurface,
                    border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 13, color: AgiTheme.egaWhite),
                        decoration: InputDecoration(
                          hintText: 'Search items by name, index (#0), or room number...',
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('Hide Dummy Objects (?)', style: TextStyle(fontSize: 11)),
                            selected: _hideDummyObjects,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onSelected: (val) {
                              setState(() {
                                _hideDummyObjects = val;
                              });
                            },
                            avatar: Icon(
                              _hideDummyObjects ? Icons.visibility_off : Icons.visibility,
                              size: 13,
                              color: _hideDummyObjects ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Showing ${filteredIndices.length} of ${objects.length}',
                            style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredIndices.isEmpty
                      ? const Center(
                          child: Text('No objects found.', style: TextStyle(color: AgiTheme.egaMuted)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredIndices.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 6),
                          itemBuilder: (context, idx) {
                            final objIdx = filteredIndices[idx];
                            final obj = objects[objIdx];
                            final isSelected = objIdx == _selectedObjectIndex;

                            final objViewNum = loader != null
                                ? ObjectViewResolver.resolveViewNumber(
                                    objectIndex: objIdx,
                                    object: obj,
                                    loader: loader,
                                  )
                                : objIdx;

                            AgiView? objView;
                            if (loader != null && loader.presentViewNumbers.contains(objViewNum)) {
                              try {
                                objView = loader.loadView(objViewNum);
                              } catch (_) {}
                            }

                            return Material(
                              color: isSelected ? const Color(0xFF1F2937) : const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedObjectIndex = objIdx;
                                    _customViewNumberOverride = null;
                                  });
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaBorder,
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Index Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF21262D),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AgiTheme.egaBorder),
                                        ),
                                        child: Text(
                                          '#$objIdx',
                                          style: const TextStyle(
                                            color: AgiTheme.egaCyan,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Mini Cel Preview
                                      if (objView != null && objView.loops.isNotEmpty && objView.loops[0].cels.isNotEmpty) ...[
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.circular(3),
                                            border: Border.all(color: AgiTheme.egaBorder),
                                          ),
                                          child: Center(
                                            child: CelImageWidget(
                                              view: objView,
                                              loopIndex: 0,
                                              celIndex: 0,
                                              scale: 1.0,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],

                                      // Item Name & Starting Location
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              obj.name.isEmpty ? '<Nameless Item>' : obj.name,
                                              style: TextStyle(
                                                color: obj.name.isEmpty ? AgiTheme.egaMuted : AgiTheme.egaWhite,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatRoomLocation(obj.startingRoom),
                                              style: TextStyle(
                                                color: obj.startingRoom == 0 ? AgiTheme.egaGreen : AgiTheme.egaMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (objView != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AgiTheme.egaMagenta.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(3),
                                            border: Border.all(color: AgiTheme.egaMagenta.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            'VIEW $objViewNum',
                                            style: const TextStyle(fontSize: 10, color: AgiTheme.egaMagenta, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],

                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 14, color: AgiTheme.egaMuted),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: obj.name));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Copied "${obj.name}"')),
                                          );
                                        },
                                        tooltip: 'Copy Name',
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
            ),
          ),

          // Right: Detailed Object Inspector
          Container(
            width: 360,
            decoration: const BoxDecoration(
              color: AgiTheme.egaDarkSurface,
              border: Border(left: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: selectedObj == null
                ? const Center(child: Text('No object selected.', style: TextStyle(color: AgiTheme.egaMuted)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Object Header Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AgiTheme.egaBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'OBJECT #$_selectedObjectIndex',
                                    style: const TextStyle(
                                      color: AgiTheme.egaCyan,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatRoomLocation(selectedObj.startingRoom),
                                    style: TextStyle(
                                      color: selectedObj.startingRoom == 0 ? AgiTheme.egaGreen : AgiTheme.egaMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                selectedObj.name.isEmpty ? '<Nameless Item>' : selectedObj.name,
                                style: const TextStyle(
                                  color: AgiTheme.egaWhite,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Associated VIEW Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AgiTheme.egaBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.image, size: 16, color: AgiTheme.egaMagenta),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ASSOCIATED VIEW ($effectiveViewNum)',
                                    style: const TextStyle(
                                      color: AgiTheme.egaMagenta,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (loader != null)
                                    PopupMenuButton<int>(
                                      icon: const Icon(Icons.swap_horiz, size: 16, color: AgiTheme.egaCyan),
                                      tooltip: 'Switch Linked View',
                                      itemBuilder: (context) {
                                        return loader.presentViewNumbers.map((vNum) {
                                          return PopupMenuItem<int>(
                                            value: vNum,
                                            child: Text('VIEW $vNum', style: const TextStyle(fontSize: 12)),
                                          );
                                        }).toList();
                                      },
                                      onSelected: (vNum) {
                                        setState(() => _customViewNumberOverride = vNum);
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // View Preview Canvas Box
                              Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AgiTheme.egaBorder),
                                ),
                                child: associatedView == null ||
                                        associatedView.loops.isEmpty ||
                                        associatedView.loops[0].cels.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No VIEW resource found for this index',
                                          style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
                                        ),
                                      )
                                    : Center(
                                        child: CelImageWidget(
                                          view: associatedView,
                                          loopIndex: 0,
                                          celIndex: 0,
                                          scale: 3.0,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),

                              // Embedded Description String Box
                              const Text(
                                'VIEW Embedded Description:',
                                style: TextStyle(
                                  color: AgiTheme.egaMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AgiTheme.egaBorder),
                                ),
                                child: Text(
                                  (associatedView?.description != null && associatedView!.description!.isNotEmpty)
                                      ? associatedView.description!
                                      : 'No text description embedded in VIEW $effectiveViewNum header.',
                                  style: TextStyle(
                                    color: (associatedView?.description != null && associatedView!.description!.isNotEmpty)
                                        ? AgiTheme.egaWhite
                                        : AgiTheme.egaMuted,
                                    fontSize: 12,
                                    fontStyle: (associatedView?.description != null && associatedView!.description!.isNotEmpty)
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Jump to View Browser Button
                              if (associatedView != null)
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ViewBrowserScreen(
                                          initialViewNumber: effectiveViewNum,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AgiTheme.egaDarkSurface,
                                    side: const BorderSide(color: AgiTheme.egaCyan),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 14, color: AgiTheme.egaCyan),
                                  label: Text(
                                    'Inspect in View Browser (VIEW $effectiveViewNum)',
                                    style: const TextStyle(color: AgiTheme.egaCyan, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatRoomLocation(int room) {
    if (room == 0) return 'Carried by Ego (Room 0)';
    if (room == 255) return 'Room 255 (Unobtainable / Out of Play)';
    return 'Starting Room: $room';
  }
}
