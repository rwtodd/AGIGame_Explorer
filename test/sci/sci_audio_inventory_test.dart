import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

import '../support/reference_games.dart';

/// Stage 0 audio corpus inventory (see doc/sci_adlib_mt32_audio_plan.md).
///
/// Scans every local reference SCI title and prints a one-line summary of the
/// audio-relevant resource layout: patch entries, patch 3 (AdLib bank) size,
/// sound count, loose driver files, and early-SCI0 classification.
///
/// This is an inventory, not a behavior test: assertions stay structural
/// (map loads, >0 sounds, patch-3 size in the documented set where readable)
/// and game-specific copyrighted bytes are never asserted. Titles absent
/// from `reference_games/` are skipped.
///
/// Patch 3 size note: volume entries report the decompressed length from
/// the volume record header without decompressing (a game's compression
/// method may be unsupported by this loader); loose patch files yield the
/// payload after header strip via `getResource`. A path that throws is
/// reported as `unreadable:<error type>` instead of failing the inventory.
void main() {
  const games = <String>[
    'police-quest-2',
    'kings-quest-4-sci',
    'space-quest-3',
    'lsl-2',
    'lsl-3',
    'codename-iceman',
    'colonels-bequest',
    'conquests-of-camelot',
    'quest-for-glory-1',
    'quest-for-glory-2',
  ];

  /// AdLib bank sizes accepted by ScummVM (plan doc, "Short answer").
  const documentedPatch3Sizes = {1344, 2690, 5382};

  /// One-line inventory summary for a present [gameDirName].
  String inventoryLine(String gameDirName) {
    final vm = SciVolumeManager.fromDirectory(referenceGamePath(gameDirName));
    try {
      final patchEntries = vm.resourceMap.entriesForType(SciResourceType.patch);
      final patchNumbers = patchEntries.map((e) => e.id.number).toList();

      String patch3;
      final entry3 = vm.findResource(SciResourceType.patch, 3);
      if (entry3 == null) {
        patch3 = 'none';
      } else {
        try {
          final int size;
          if (entry3.isPatch) {
            // Loose patch: getResource strips the wrapper header and
            // returns the raw (uncompressed) bank payload.
            size = vm.getResource(SciResourceType.patch, 3).length;
          } else {
            size = vm.readHeader(entry3).decompSize;
          }
          patch3 = size.toString();
          expect(
            documentedPatch3Sizes.contains(size),
            isTrue,
            reason: '$gameDirName patch 3 size $size not in $documentedPatch3Sizes',
          );
        } catch (e) {
          patch3 = 'unreadable:${e.runtimeType}';
        }
      }

      final soundCount = vm.resourceMap.entriesForType(SciResourceType.sound).length;

      // Loose driver files present on disk (uppercase names on disk;
      // match case-insensitively so lowercase variants still list).
      final dir = Directory(referenceGamePath(gameDirName));
      final drivers = <String>[];
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final base = entity.uri.pathSegments.last.toUpperCase();
        if (base == 'ADL.DRV' || base == 'SNDBLAST.DRV' || base == 'MT32.DRV') {
          drivers.add('${entity.uri.pathSegments.last}=${entity.lengthSync()}B');
        }
      }
      drivers.sort();

      return '$gameDirName | map=${vm.resourceMap.length} patches=$patchNumbers '
          'patch3=$patch3 sounds=$soundCount '
          'drivers=[${drivers.isEmpty ? 'none' : drivers.join(', ')}] '
          'earlySci0=${vm.isEarlySci0}';
    } finally {
      vm.close();
    }
  }

  group('SCI audio corpus inventory (Stage 0)', () {
    for (final game in games) {
      test(game, () {
        if (skipIfReferenceGameMissing(game)) return;

        final vm = SciVolumeManager.fromDirectory(referenceGamePath(game));
        try {
          // Structural: the volume manager loads and the map is populated.
          expect(vm.resourceMap.length, greaterThan(0),
              reason: '$game RESOURCE.MAP loaded but empty');
          expect(
            vm.resourceMap.entriesForType(SciResourceType.sound),
            isNotEmpty,
            reason: '$game has no sound resources',
          );
        } finally {
          vm.close();
        }

        // ignore: avoid_print
        print(inventoryLine(game));
      });
    }

    test('corpus table', () {
      final lines = <String>[];
      for (final game in games) {
        if (!referenceGameExists(game)) continue;
        lines.add(inventoryLine(game));
      }
      // ignore: avoid_print
      print('SCI audio inventory (${lines.length}/${games.length} titles present):');
      for (final line in lines) {
        // ignore: avoid_print
        print(line);
      }
      expect(lines.length, greaterThan(0),
          reason: 'no reference SCI titles present at all');
    });
  });
}
