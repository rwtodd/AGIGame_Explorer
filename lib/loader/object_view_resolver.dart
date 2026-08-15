import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

/// Helper utility that resolves the authentic [AgiView] resource corresponding to an [AgiObject].
///
/// In Sierra AGI adventure games:
/// 1. Inventory object views are the only VIEW resources with an embedded ASCII description string
///    in their VIEW header (`view.description`), while characters and animations have no description.
/// 2. Sierra games organize inventory views in contiguous blocks starting from a base index:
///    - Early AGI (KQ1, KQ2, SQ1, SQ2, PQ1, Larry): Base offset 0 (Views 1..N for Objects 1..N)
///    - Mid AGI (KQ3): Base offset 100 (Views 101..153 for Objects 1..N)
///    - Late AGI (KQ4): Base offset 213 (Views 214..255 for Objects 1..N)
/// 3. Object #0 in AGI games is typically a dummy placeholder named '?'.
class ObjectViewResolver {
  const ObjectViewResolver._();

  /// Attempts to determine the inventory object view base offset from LOGIC 0 bytecode.
  ///
  /// In Sierra AGI games:
  /// - The inventory viewer routine executes `status()` (opcode 124).
  /// - It calculates the corresponding VIEW number using `addn(%v, baseOffset)` (opcode 5).
  /// - It then displays the inventory view using `show.obj.v(%v)` (opcode 162).
  /// - In games without a base offset (KQ1, KQ2, SQ1, etc.), `show.obj.v` is called directly without `addn` (offset = 0).
  static int? findBaseOffsetFromBytecode(AgiResourceLoader loader) {
    final candidateLogics = [0, 1, 2, 3, 4, 5];
    for (final logicNum in candidateLogics) {
      if (!loader.presentLogicNumbers.contains(logicNum)) continue;
      try {
        final logic = loader.loadLogic(logicNum);
        final code = logic.bytecodes;
        int? zeroCandidate;

        // Scan for show.obj.v (opcode 162 / 0xA2)
        for (int i = 0; i < code.length - 1; i++) {
          if (code[i] == 162) {
            final targetVar = code[i + 1];

            // Scan backwards up to 60 bytes for `addn(%v, N)` (opcode 5) operating on targetVar
            final scanBackStart = (i - 60 >= 0) ? i - 60 : 0;
            for (int j = i - 1; j >= scanBackStart; j--) {
              if (code[j] == 5 && j + 2 < code.length && code[j + 1] == targetVar) {
                final offset = code[j + 2];
                return offset;
              }
            }

            // Also check if status() [124] was called before show.obj.v without addn on targetVar -> base offset is 0
            for (int j = i - 1; j >= scanBackStart; j--) {
              if (code[j] == 124) {
                zeroCandidate = 0;
                break;
              }
            }
          }
        }

        if (zeroCandidate != null) {
          return zeroCandidate;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolves the most accurate VIEW resource number for the given [object] at [objectIndex].
  static int resolveViewNumber({
    required int objectIndex,
    required AgiObject object,
    required AgiResourceLoader loader,
  }) {
    final presentViews = loader.presentViewNumbers;
    if (presentViews.isEmpty) return 0;

    // 1. Primary Heuristic: Scan LOGIC 0 bytecode for status -> addn -> show.obj.v
    final logicBaseOffset = findBaseOffsetFromBytecode(loader);
    if (logicBaseOffset != null) {
      final expectedView = logicBaseOffset + objectIndex;
      if (presentViews.contains(expectedView)) {
        return expectedView;
      }
    }

    // 2. Secondary Heuristic: Scan and collect all views that have an embedded text description
    final viewsWithDesc = <int, String>{};
    for (final vNum in presentViews) {
      try {
        final view = loader.loadView(vNum);
        if (view.description != null && view.description!.trim().isNotEmpty) {
          viewsWithDesc[vNum] = view.description!.trim();
        }
      } catch (_) {}
    }

    // 3. If there are views with descriptions, determine the base view offset.
    if (viewsWithDesc.isNotEmpty) {
      final sortedDescViews = viewsWithDesc.keys.toList()..sort();
      final minDescView = sortedDescViews.first;

      // In Sierra AGI games, Object 1 corresponds to minDescView, so baseOffset = minDescView - 1.
      final baseOffset = minDescView > 0 ? minDescView - 1 : 0;
      final expectedView = baseOffset + objectIndex;

      // If the expected view is present (or in views with descriptions), it is the primary match.
      if (viewsWithDesc.containsKey(expectedView) || presentViews.contains(expectedView)) {
        return expectedView;
      }

      // If the expected view is not present (e.g. an item that reuses another view like KQ3 Empty Lard Jar -> Empty Jar),
      // search for a match among views with descriptions.
      final cleanedName = object.name.replaceAll('*', '').trim().toLowerCase();
      if (cleanedName.isNotEmpty) {
        for (final entry in viewsWithDesc.entries) {
          final descLower = entry.value.toLowerCase();
          if (descLower.contains(cleanedName) || cleanedName.contains(descLower)) {
            return entry.key;
          }
        }
      }
    }

    // 4. Fallback to 1-based index (e.g. Object #1 -> VIEW 1)
    final oneBasedIndex = objectIndex + 1;
    if (presentViews.contains(oneBasedIndex)) {
      return oneBasedIndex;
    }

    // 5. Fallback to 0-based index
    if (presentViews.contains(objectIndex)) {
      return objectIndex;
    }

    return presentViews.first;
  }
}
