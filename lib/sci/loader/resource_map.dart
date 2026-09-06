import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

/// An entry describing the location of a resource in a volume or patch file.
class SciResourceEntry {
  final SciResourceId id;
  final int volumeNumber;
  final int fileOffset;
  final File? patchFile;
  final int patchOffset;
  final int? patchLength;

  const SciResourceEntry({
    required this.id,
    this.volumeNumber = 0,
    this.fileOffset = 0,
    this.patchFile,
    this.patchOffset = 0,
    this.patchLength,
  });

  /// True if this entry points to a loose patch file on disk rather than a packed volume.
  bool get isPatch => patchFile != null;

  @override
  String toString() {
    if (isPatch) {
      return 'SciResourceEntry($id, patch: ${patchFile?.path}, offset: $patchOffset)';
    }
    return 'SciResourceEntry($id, vol: $volumeNumber, offset: 0x${fileOffset.toRadixString(16)})';
  }
}

/// Parsed in-memory index of SCI0 `RESOURCE.MAP`.
///
/// Maps each unique [SciResourceId] to its [SciResourceEntry].
/// Follows Sierra / ScummVM semantics where the first occurrence in `RESOURCE.MAP` wins,
/// and external patch files override volume entries.
class SciResourceMap {
  final Map<SciResourceId, SciResourceEntry> _entries;
  final int rawRecordCount;
  final int duplicateCount;

  SciResourceMap(
    Map<SciResourceId, SciResourceEntry> entries, {
    this.rawRecordCount = 0,
    this.duplicateCount = 0,
  }) : _entries = Map.unmodifiable(entries);

  /// Parses a SCI0 `RESOURCE.MAP` binary byte buffer.
  ///
  /// Entries are 6 bytes each:
  /// - `uint16 id` (high 5 bits = resource type, low 11 bits = resource number)
  /// - `uint32 offset` (high 6 bits = volume number, low 26 bits = file offset)
  /// The table is terminated by `offset == 0xFFFFFFFF`.
  factory SciResourceMap.fromBytes(Uint8List bytes) {
    if (bytes.length < 6) {
      throw const SciCorruptResourceException('RESOURCE.MAP is too small to contain any entries');
    }

    final bd = ByteData.sublistView(bytes);
    final entries = <SciResourceId, SciResourceEntry>{};
    var rawCount = 0;
    var dupCount = 0;

    for (var i = 0; i + 6 <= bytes.length; i += 6) {
      final id = bd.getUint16(i, Endian.little);
      final offset = bd.getUint32(i + 2, Endian.little);

      if (offset == 0xFFFFFFFF) {
        // Sierra end-of-map sentinel
        break;
      }

      rawCount++;

      final typeCode = id >> 11;
      final type = SciResourceType.fromInt(typeCode);
      if (type == null) {
        // Unknown or invalid type code in map
        continue;
      }

      final number = id & 0x7FF;
      final resId = SciResourceId(type, number);

      // First entry in map wins; later entries are superseded historical versions
      if (!entries.containsKey(resId)) {
        final volumeNumber = (offset >> 26) & 0x3F;
        final fileOffset = offset & 0x03FFFFFF;

        entries[resId] = SciResourceEntry(
          id: resId,
          volumeNumber: volumeNumber,
          fileOffset: fileOffset,
        );
      } else {
        dupCount++;
      }
    }

    return SciResourceMap(
      entries,
      rawRecordCount: rawCount,
      duplicateCount: dupCount,
    );
  }

  /// Parses a SCI0 `RESOURCE.MAP` from a file on disk.
  factory SciResourceMap.fromFile(File file) {
    if (!file.existsSync()) {
      throw SciResourceNotFoundException('RESOURCE.MAP file not found at ${file.path}');
    }
    return SciResourceMap.fromBytes(file.readAsBytesSync());
  }

  /// Looks up a resource entry by type and number.
  SciResourceEntry? find(SciResourceType type, int number) =>
      _entries[SciResourceId(type, number)];

  /// Looks up a resource entry by its [SciResourceId].
  SciResourceEntry? findById(SciResourceId id) => _entries[id];

  /// Returns whether this map contains the given resource.
  bool contains(SciResourceType type, int number) =>
      _entries.containsKey(SciResourceId(type, number));

  /// Returns whether this map contains the given [SciResourceId].
  bool containsId(SciResourceId id) => _entries.containsKey(id);

  /// All unique resource entries in the map.
  List<SciResourceEntry> get allEntries => _entries.values.toList(growable: false);

  /// Total count of unique resources in this map.
  int get length => _entries.length;

  /// Returns all resource entries matching the specified [type], sorted by resource number.
  List<SciResourceEntry> entriesForType(SciResourceType type) {
    final list = _entries.values.where((e) => e.id.type == type).toList();
    list.sort((a, b) => a.id.number.compareTo(b.id.number));
    return list;
  }

  /// Returns all available resource numbers for a given [type], sorted numerically.
  List<int> numbersForType(SciResourceType type) {
    final nums = _entries.keys
        .where((k) => k.type == type)
        .map((k) => k.number)
        .toList();
    nums.sort();
    return nums;
  }

  /// Creates a new [SciResourceMap] with the specified loose patch entries overriding
  /// any existing volume entries.
  SciResourceMap withPatches(Iterable<SciResourceEntry> patches) {
    final merged = Map<SciResourceId, SciResourceEntry>.from(_entries);
    for (final patch in patches) {
      merged[patch.id] = patch;
    }
    return SciResourceMap(
      merged,
      rawRecordCount: rawRecordCount,
      duplicateCount: duplicateCount,
    );
  }
}
