import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/sci/loader/decompressor_huffman.dart';
import 'package:flutter_agigame/sci/loader/decompressor_lzw.dart';
import 'package:flutter_agigame/sci/loader/resource_map.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/sci_exceptions.dart';

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

/// Disk-backed volume manager for SCI0 games.
///
/// Loads `RESOURCE.MAP`, accesses `RESOURCE.000`–`RESOURCE.003`, detects loose
/// patch files, and decompresses resources via LZW (method 1) or Huffman (method 2).
class SciVolumeManager {
  final String gameDirectory;
  final SciResourceMap resourceMap;
  final Map<int, RandomAccessFile> _openVolumes = {};
  final _SciLruCache<SciResourceId, Uint8List> _cache;

  SciVolumeManager._({
    required this.gameDirectory,
    required this.resourceMap,
    int cacheCapacity = 128,
  }) : _cache = _SciLruCache<SciResourceId, Uint8List>(cacheCapacity);

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

    final payload = raf.readSync(header.payloadSize);
    if (payload.length < header.payloadSize) {
      throw SciCorruptResourceException(
        'Premature end of volume reading resource ${entry.id}: '
        'read ${payload.length} bytes, expected ${header.payloadSize}',
      );
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
