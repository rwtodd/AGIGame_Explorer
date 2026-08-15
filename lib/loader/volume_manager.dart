import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/lzw_decompression.dart';
import 'package:flutter_agigame/core/utils/pic_compression.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';

/// LRU Memory Cache for byte arrays or decoded resources.
class LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  LruCache(this.capacity);

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

/// Abstract contract for reading raw resource bytes from AGI volume containers.
abstract class VolumeManager {
  Uint8List getResource(DirEntry de);
  Future<Uint8List> getResourceAsync(DirEntry de);
  Uint8List getWordsData();
  Uint8List getObjectsData();
  void close();

  static VolumeManager create(GameMetaData meta) {
    if (meta.isV3) {
      return V3VolumeManager(meta.gamePath, meta.prefix ?? '');
    } else {
      return V2VolumeManager(meta.gamePath);
    }
  }
}

/// Helper to find a file case-insensitively.
File _findFileCaseInsensitive(String dirPath, String fileName) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    throw AgiException('Directory does not exist: $dirPath');
  }

  final files = dir.listSync().whereType<File>();
  return files.firstWhere(
    (f) => p.basename(f.path).toUpperCase() == fileName.toUpperCase(),
    orElse: () => File(p.join(dirPath, fileName)),
  );
}

/// Disk-backed volume manager for AGI v1 and v2 games (`VOL.0`, `VOL.1`, ...).
class V2VolumeManager implements VolumeManager {
  final String gamePath;
  final Map<int, RandomAccessFile> _openFiles = {};
  final LruCache<DirEntry, Uint8List> _resourceCache;

  V2VolumeManager(this.gamePath, {int cacheCapacity = 64})
      : _resourceCache = LruCache<DirEntry, Uint8List>(cacheCapacity);

  RandomAccessFile _getFile(int volume) {
    var raf = _openFiles[volume];
    if (raf == null) {
      final file = _findFileCaseInsensitive(gamePath, 'VOL.$volume');
      if (!file.existsSync()) {
        throw AgiException('Volume file VOL.$volume does not exist in $gamePath');
      }
      raf = file.openSync(mode: FileMode.read);
      _openFiles[volume] = raf;
    }
    return raf;
  }

  @override
  Uint8List getResource(DirEntry de) {
    if (!de.isPresent) {
      throw const ResourceNotPresentException('Requested resource does not exist.');
    }

    final cached = _resourceCache.get(de);
    if (cached != null) {
      return cached;
    }

    final raf = _getFile(de.volume);
    try {
      raf.setPositionSync(de.offset);
      final header = raf.readSync(5);
      if (header.length < 5) {
        throw AgiException('Unexpected EOF reading header for $de');
      }

      if (header[0] != 0x12 || header[1] != 0x34 || header[2] != de.volume) {
        throw AgiException('Bad resource header signature for $de (${header.sublist(0, 3)})');
      }

      final reslen = header[3] | (header[4] << 8);
      final resource = raf.readSync(reslen);
      if (resource.length < reslen) {
        throw AgiException('Unexpected EOF reading $reslen bytes for $de');
      }

      _resourceCache.put(de, resource);
      return resource;
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Failed to read resource $de: $e', e);
    }
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry de) async {
    return getResource(de);
  }

  @override
  Uint8List getWordsData() {
    final file = _findFileCaseInsensitive(gamePath, 'WORDS.TOK');
    if (!file.existsSync()) {
      throw AgiException('WORDS.TOK file not found in $gamePath');
    }
    return file.readAsBytesSync();
  }

  @override
  Uint8List getObjectsData() {
    final file = _findFileCaseInsensitive(gamePath, 'OBJECT');
    if (!file.existsSync()) {
      throw AgiException('OBJECT file not found in $gamePath');
    }
    return file.readAsBytesSync();
  }

  @override
  void close() {
    for (final raf in _openFiles.values) {
      try {
        raf.closeSync();
      } catch (_) {}
    }
    _openFiles.clear();
    _resourceCache.clear();
  }
}

/// Disk-backed volume manager for AGI v3 games (`<prefix>VOL.0`, `<prefix>VOL.1`, ...).
class V3VolumeManager implements VolumeManager {
  final String gamePath;
  final String prefix;
  final Map<int, RandomAccessFile> _openFiles = {};
  final LruCache<DirEntry, Uint8List> _resourceCache;

  V3VolumeManager(this.gamePath, this.prefix, {int cacheCapacity = 64})
      : _resourceCache = LruCache<DirEntry, Uint8List>(cacheCapacity);

  RandomAccessFile _getFile(int volume) {
    var raf = _openFiles[volume];
    if (raf == null) {
      final fileName = '${prefix}VOL.$volume';
      final file = _findFileCaseInsensitive(gamePath, fileName);
      if (!file.existsSync()) {
        throw AgiException('Volume file $fileName does not exist in $gamePath');
      }
      raf = file.openSync(mode: FileMode.read);
      _openFiles[volume] = raf;
    }
    return raf;
  }

  @override
  Uint8List getResource(DirEntry de) {
    if (!de.isPresent) {
      throw const ResourceNotPresentException('Requested resource does not exist.');
    }

    final cached = _resourceCache.get(de);
    if (cached != null) {
      return cached;
    }

    final raf = _getFile(de.volume);
    try {
      raf.setPositionSync(de.offset);
      final header = raf.readSync(7);
      if (header.length < 7) {
        throw AgiException('Unexpected EOF reading header for $de');
      }

      if (header[0] != 0x12 || header[1] != 0x34 || (header[2] & 0x7F) != de.volume) {
        throw AgiException('Bad resource header signature for $de (${header.sublist(0, 3)})');
      }

      final picCompressed = (header[2] & 0x80) != 0;
      final reslen = header[3] | (header[4] << 8);
      final lzwlen = header[5] | (header[6] << 8);

      final packed = raf.readSync(lzwlen);
      if (packed.length < lzwlen) {
        throw AgiException('Unexpected EOF reading $lzwlen packed bytes for $de');
      }

      Uint8List resource;
      if (reslen != packed.length) {
        if (picCompressed) {
          resource = PicDecompressor.expand(packed, reslen);
        } else {
          resource = LzwDecompressor.expand(packed, reslen);
        }
      } else {
        resource = packed;
      }

      _resourceCache.put(de, resource);
      return resource;
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Failed to read resource $de: $e', e);
    }
  }

  @override
  Future<Uint8List> getResourceAsync(DirEntry de) async {
    return getResource(de);
  }

  @override
  Uint8List getWordsData() {
    final file = _findFileCaseInsensitive(gamePath, 'WORDS.TOK');
    if (!file.existsSync()) {
      throw AgiException('WORDS.TOK file not found in $gamePath');
    }
    return file.readAsBytesSync();
  }

  @override
  Uint8List getObjectsData() {
    final file = _findFileCaseInsensitive(gamePath, 'OBJECT');
    if (!file.existsSync()) {
      throw AgiException('OBJECT file not found in $gamePath');
    }
    return file.readAsBytesSync();
  }

  @override
  void close() {
    for (final raf in _openFiles.values) {
      try {
        raf.closeSync();
      } catch (_) {}
    }
    _openFiles.clear();
    _resourceCache.clear();
  }
}
