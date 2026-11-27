import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/sci/loader/decompressor_huffman.dart';
import 'package:flutter_agigame/sci/loader/decompressor_lzw.dart';
import 'package:flutter_agigame/sci/loader/resource_map.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';
import 'package:flutter_agigame/sci/script/sci_script_header.dart';

/// LRU Memory Cache for decompressed resource buffers.
class _SciLruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  _SciLruCache(this.capacity);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  void clear() => _map.clear();
  int get length => _map.length;
}

/// 8-byte header present at each resource entry in a SCI0 volume file (`RESOURCE.001`, etc.).
class SciVolumeRecordHeader {
  final int id;
  final int compSize;
  final int decompSize;
  final int method;

  const SciVolumeRecordHeader({
    required this.id,
    required this.compSize,
    required this.decompSize,
    required this.method,
  });

  /// Length in bytes of the compressed payload following the 8-byte header.
  int get payloadSize => compSize >= 4 ? compSize - 4 : 0;

  SciResourceType? get resourceType => SciResourceType.fromInt(id >> 11);
  int get resourceNumber => id & 0x7FF;

  factory SciVolumeRecordHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const SciCorruptResourceException('Volume record header too short (< 8 bytes)');
    }
    final bd = ByteData.sublistView(bytes);
    return SciVolumeRecordHeader(
      id: bd.getUint16(0, Endian.little),
      compSize: bd.getUint16(2, Endian.little),
      decompSize: bd.getUint16(4, Endian.little),
      method: bd.getUint16(6, Endian.little),
    );
  }

  @override
  String toString() =>
      'SciVolumeRecordHeader(${resourceType?.typeName ?? '?'}.$resourceNumber, '
      'compSize: $compSize, decompSize: $decompSize, method: $method)';
}

/// Disk-backed volume manager for SCI0/SCI1 games.
///
/// Loads `RESOURCE.MAP`, accesses `RESOURCE.000`–`RESOURCE.003`, detects loose
/// patch files, and decompresses resources. SCI0 volumes map raw method 1 to
/// LSB LZW and raw method 2 to Huffman. Post-SCI01 volumes (detected via
/// [usesPostSci01Compression]) invert the flavor: raw method 1 is Huffman and
/// raw method 2 is MSB early-change LZW1.
class SciVolumeManager {
  final String gameDirectory;
  final SciResourceMap resourceMap;
  final Map<int, RandomAccessFile> _openVolumes = {};
  final _SciLruCache<SciResourceId, Uint8List> _cache;
  bool? _isEarlySci0;
  bool? _usesPostSci01Compression;

  /// True if this volume uses the early SCI0 script format (e.g. King's Quest IV SCI).
  bool get isEarlySci0 {
    if (_isEarlySci0 != null) return _isEarlySci0!;
    try {
      final script0Bytes = getResource(SciResourceType.script, 0);
      _isEarlySci0 = hasOldSci0ScriptHeader(script0Bytes);
    } catch (_) {
      _isEarlySci0 = false;
    }
    return _isEarlySci0!;
  }

  /// Whether volume resources use the post-SCI01 compression flavor.
  ///
  /// This mirrors the preliminary view-compression detection concept (the
  /// first compressed view not interpreted as old LZW means post-SCI01) and
  /// is only a compression-format signal, not full game-version detection:
  /// scan the volume-backed (non-patch) view entries in resource-number
  /// order (up to 10), read each raw header, and let the first entry with a
  /// nonzero raw method decide (1 => old/SCI0 mapping, any other nonzero
  /// => post-SCI01 mapping). When no examined view is compressed, or no
  /// volumes/headers can be read, this defaults to false, which preserves
  /// every existing SCI0 and synthetic behavior.
  bool get usesPostSci01Compression {
    if (_usesPostSci01Compression != null) {
      return _usesPostSci01Compression!;
    }
    var result = false;
    try {
      final views = resourceMap
          .entriesForType(SciResourceType.view)
          .where((entry) => !entry.isPatch);
      var examined = 0;
      for (final entry in views) {
        if (examined >= 10) break;
        examined++;
        try {
          final header = readHeader(entry);
          if (header.method != 0) {
            result = header.method != 1;
            break;
          }
        } catch (_) {
          // Skip an unreadable view header; the post-SCI01 decision needs
          // one readable compressed view.
        }
      }
    } catch (_) {
      result = false;
    }
    _usesPostSci01Compression = result;
    return result;
  }

  SciVolumeManager._({
    required this.gameDirectory,
    required this.resourceMap,
    int cacheCapacity = 128,
  }) : _cache = _SciLruCache<SciResourceId, Uint8List>(cacheCapacity);

  /// Creates an empty [SciVolumeManager] with no resources (useful for UI tests and isolated harnesses).
  SciVolumeManager.empty()
      : gameDirectory = '',
        resourceMap = SciResourceMap(const {}),
        _cache = _SciLruCache<SciResourceId, Uint8List>(1);

  /// Initializes a [SciVolumeManager] for the specified [gameDirectory].
  ///
  /// Loads `RESOURCE.MAP` and registers any loose patch files (e.g. `script.701`, `patch.000`).
  factory SciVolumeManager.fromDirectory(
    String gameDirectory, {
    int cacheCapacity = 128,
  }) {
    final dir = Directory(gameDirectory);
    if (!dir.existsSync()) {
      throw SciResourceNotFoundException('Game directory not found: $gameDirectory');
    }

    // Locate RESOURCE.MAP case-insensitively
    final mapFile = _findFileCaseInsensitive(gameDirectory, 'RESOURCE.MAP');
    if (!mapFile.existsSync()) {
      throw SciResourceNotFoundException('RESOURCE.MAP not found in $gameDirectory');
    }

    final baseMap = SciResourceMap.fromFile(mapFile);
    final patches = _scanLoosePatches(gameDirectory);
    final effectiveMap = patches.isNotEmpty ? baseMap.withPatches(patches) : baseMap;

    return SciVolumeManager._(
      gameDirectory: gameDirectory,
      resourceMap: effectiveMap,
      cacheCapacity: cacheCapacity,
    );
  }

  /// Looks up and retrieves the uncompressed byte content of the given resource.
  Uint8List getResource(SciResourceType type, int number) =>
      getResourceById(SciResourceId(type, number));

  /// Looks up and retrieves the uncompressed byte content of the given [id].
  Uint8List getResourceById(SciResourceId id) {
    final cached = _cache.get(id);
    if (cached != null) {
      return cached;
    }

    final entry = resourceMap.findById(id);
    if (entry == null) {
      throw SciResourceNotFoundException('Resource $id not found in map or patches');
    }

    Uint8List decompressed;
    if (entry.isPatch) {
      decompressed = _readPatch(entry);
    } else {
      decompressed = _readVolumeResource(entry);
    }

    _cache.put(id, decompressed);
    return decompressed;
  }

  /// Asynchronously retrieves the uncompressed byte content of the given resource.
  Future<Uint8List> getResourceAsync(SciResourceType type, int number) async =>
      getResource(type, number);

  /// Returns true if the resource exists in either the volume map or loose patches.
  bool hasResource(SciResourceType type, int number) =>
      resourceMap.contains(type, number);

  /// Finds the resource entry for [type] and [number], or null if not present.
  SciResourceEntry? findResource(SciResourceType type, int number) =>
      resourceMap.find(type, number);

  /// Reads the 8-byte volume header for the given [entry] without decompressing the payload.
  SciVolumeRecordHeader readHeader(SciResourceEntry entry) {
    if (entry.isPatch) {
      throw ArgumentError('Cannot read volume header for a loose patch entry: $entry');
    }
    final raf = _getVolumeFile(entry.volumeNumber);
    raf.setPositionSync(entry.fileOffset);
    final headerBytes = raf.readSync(8);
    return SciVolumeRecordHeader.fromBytes(headerBytes);
  }

  /// Reads the raw, uncompressed payload of the patch file for [entry].
  Uint8List _readPatch(SciResourceEntry entry) {
    final file = entry.patchFile!;
    if (!file.existsSync()) {
      throw SciResourceNotFoundException('Loose patch file missing: ${file.path}');
    }

    final bytes = file.readAsBytesSync();
    if (bytes.length < 2) {
      throw SciCorruptResourceException('Loose patch file too small: ${file.path}');
    }

    final extraHeaderLen = bytes[1] & 0xFF;
    final payloadOffset = 2 + extraHeaderLen;
    if (payloadOffset > bytes.length) {
      throw SciCorruptResourceException(
        'Patch file header offset ($payloadOffset) exceeds file length (${bytes.length}): ${file.path}',
      );
    }

    return Uint8List.sublistView(bytes, payloadOffset);
  }

  /// Reads and decompresses a resource stored in a volume container file.
  Uint8List _readVolumeResource(SciResourceEntry entry) {
    final raf = _getVolumeFile(entry.volumeNumber);
    raf.setPositionSync(entry.fileOffset);

    final headerBytes = raf.readSync(8);
    final header = SciVolumeRecordHeader.fromBytes(headerBytes);

    final expectedId = (entry.id.type.typeCode << 11) | entry.id.number;
    if (header.id != expectedId) {
      throw SciCorruptResourceException(
        'Volume header id mismatch for resource ${entry.id}: '
        'map entry id 0x${expectedId.toRadixString(16)}, '
        'volume record header id 0x${header.id.toRadixString(16)} '
        '(compSize: ${header.compSize}, decompSize: ${header.decompSize}, '
        'method: ${header.method})',
      );
    }
    if (header.compSize < 4) {
      throw SciCorruptResourceException(
        'Volume record for resource ${entry.id} has invalid compSize '
        '${header.compSize} (< 4): id 0x${header.id.toRadixString(16)}, '
        'decompSize: ${header.decompSize}, method: ${header.method}',
      );
    }
    if (header.method == 0 && header.payloadSize != header.decompSize) {
      throw SciCorruptResourceException(
        'Uncompressed volume record for resource ${entry.id} has '
        'payloadSize ${header.payloadSize} != decompSize ${header.decompSize}: '
        'id 0x${header.id.toRadixString(16)}, compSize: ${header.compSize}, '
        'method: ${header.method}',
      );
    }

    final payload = raf.readSync(header.payloadSize);
    if (payload.length < header.payloadSize) {
      throw SciCorruptResourceException(
        'Premature end of volume reading resource ${entry.id}: '
        'read ${payload.length} bytes, expected ${header.payloadSize}',
      );
    }

    if (usesPostSci01Compression) {
      switch (header.method) {
        case 0: // Uncompressed
          return payload;
        case 1: // Post-SCI01 Huffman
          return SciDecompressorHuffman.decompress(payload, header.decompSize);
        case 2: // Post-SCI01 LZW1 (MSB-first, early-change)
          return SciDecompressorLZW.decompress(
            payload,
            header.decompSize,
            msb: true,
            earlyChange: true,
          );
        case 3:
        case 4:
          throw SciDecompressionException(
            'SCI1 view/pic compressed resource ${entry.id} uses compression '
            'method ${header.method}, which needs view/pic post-processing '
            'decompression that is not supported yet',
          );
        default:
          throw SciDecompressionException(
            'Unsupported compression method ${header.method} for resource ${entry.id}',
          );
      }
    }

    switch (header.method) {
      case 0: // Uncompressed
        return payload;
      case 1: // SCI0 LZW
        return SciDecompressorLZW.decompress(payload, header.decompSize);
      case 2: // SCI0 Huffman
        return SciDecompressorHuffman.decompress(payload, header.decompSize);
      default:
        throw SciDecompressionException(
          'Unsupported compression method ${header.method} for resource ${entry.id}',
        );
    }
  }

  RandomAccessFile _getVolumeFile(int volumeNumber) {
    var raf = _openVolumes[volumeNumber];
    if (raf == null) {
      final volPadded = volumeNumber.toString().padLeft(3, '0');
      final fileName = 'RESOURCE.$volPadded';
      final file = _findFileCaseInsensitive(gameDirectory, fileName);
      if (!file.existsSync()) {
        throw SciResourceNotFoundException(
          'Volume file $fileName not found in $gameDirectory',
        );
      }
      raf = file.openSync(mode: FileMode.read);
      _openVolumes[volumeNumber] = raf;
    }
    return raf;
  }

  /// Closes all open volume files and clears the cache.
  void close() {
    for (final raf in _openVolumes.values) {
      try {
        raf.closeSync();
      } catch (_) {}
    }
    _openVolumes.clear();
    _cache.clear();
  }

  /// Helper to locate a file in a directory case-insensitively.
  static File _findFileCaseInsensitive(String dirPath, String fileName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return File(p.join(dirPath, fileName));
    }
    final targetUpper = fileName.toUpperCase();
    for (final entity in dir.listSync()) {
      if (entity is File && p.basename(entity.path).toUpperCase() == targetUpper) {
        return entity;
      }
    }
    return File(p.join(dirPath, fileName));
  }

  /// Scans [gameDirectory] for loose patch files (e.g. `script.701`, `patch.000`, `patch.101`).
  static List<SciResourceEntry> _scanLoosePatches(String gameDirectory) {
    final dir = Directory(gameDirectory);
    if (!dir.existsSync()) {
      return const [];
    }

    final patches = <SciResourceEntry>[];

    for (final entity in dir.listSync()) {
      if (entity is! File) continue;

      final baseName = p.basename(entity.path);
      final parts = baseName.split('.');
      if (parts.length != 2) continue;

      final part1 = parts[0];
      final part2 = parts[1];

      // Scheme 1: type.number (e.g. script.701, patch.000, patch.101, view.001)
      final typeFromPart1 = SciResourceType.fromString(part1);
      final numFromPart2 = int.tryParse(part2);
      if (typeFromPart1 != null && numFromPart2 != null) {
        patches.add(SciResourceEntry(
          id: SciResourceId(typeFromPart1, numFromPart2),
          patchFile: entity,
        ));
        continue;
      }

      // Scheme 2: number.ext (e.g. 701.scr, 000.pat)
      final numFromPart1 = int.tryParse(part1);
      final typeFromPart2 = SciResourceType.fromString(part2);
      if (numFromPart1 != null && typeFromPart2 != null) {
        patches.add(SciResourceEntry(
          id: SciResourceId(typeFromPart2, numFromPart1),
          patchFile: entity,
        ));
      }
    }

    return patches;
  }
}
