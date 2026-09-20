import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/engine/ai/embedding_service.dart';
import 'package:path/path.dart' as p;

/// Manages persistent on-disk caching for AI assets (deduplicated vocabulary and
/// per-LOGIC candidate phrase embeddings) organized by embedding model.
///
/// Directory layout:
/// ```
/// <gameDirectory>/
///   ai_cache/
///     <model_slug>/
///       vocab.json
///       logic_0.json
///       logic_1.json
///       ...
/// ```
class AiDiskCache {
  static const String cacheDirName = 'ai_cache';
  static const String vocabFileName = 'vocab.json';
  static const String legacyVocabFileName = 'ai_vocab_cache.json';

  /// Sanitizes a model identifier into a clean filesystem folder name.
  ///
  /// Examples:
  /// - `'gemini-embedding-001'` -> `'gemini-embedding-001'`
  /// - `'models/gemini-embedding-001'` -> `'gemini-embedding-001'`
  static String sanitizeModelName(String model) {
    var name = model.trim();
    if (name.startsWith('models/')) {
      name = name.substring('models/'.length);
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return name.isEmpty ? 'default' : name;
  }

  /// Returns the target cache directory for [model] under [gameDirectory].
  static Directory getCacheDirectory(Directory gameDirectory, String model) {
    final slug = sanitizeModelName(model);
    return Directory(p.join(gameDirectory.path, cacheDirName, slug));
  }

  /// Attempts to load deduplicated word groups from [directory] for [model] into [dictionary].
  ///
  /// Checks `<gameDirectory>/ai_cache/<model>/vocab.json` first.
  /// If not found, checks legacy `<gameDirectory>/ai_vocab_cache.json` for backwards compatibility.
  /// If loaded from the legacy location, automatically migrates it to the new location.
  /// Returns `true` if valid deduplicated vocabulary was loaded.
  static Future<bool> tryLoadVocab({
    required Directory directory,
    required String model,
    required AgiDictionary dictionary,
  }) async {
    try {
      final cacheDir = getCacheDirectory(directory, model);
      final modelVocabFile = File(p.join(cacheDir.path, vocabFileName));
      final legacyFile = File(p.join(directory.path, legacyVocabFileName));

      File fileToRead;
      bool isLegacy = false;

      if (modelVocabFile.existsSync()) {
        fileToRead = modelVocabFile;
      } else if (legacyFile.existsSync()) {
        fileToRead = legacyFile;
        isLegacy = true;
      } else {
        return false;
      }

      final content = await fileToRead.readAsString();
      final Map<String, dynamic> json = jsonDecode(content);
      final groupsJson = json['groups'] as Map<String, dynamic>?;
      if (groupsJson == null || groupsJson.isEmpty) {
        return false;
      }

      final groups = <int, List<String>>{};
      for (final entry in groupsJson.entries) {
        final id = int.tryParse(entry.key);
        if (id != null && entry.value is List) {
          final words = (entry.value as List).map((e) => e.toString()).toList();
          groups[id] = words;
        }
      }

      dictionary.loadDeduplicatedWords(groups);
      debugPrint(
        '[AiDiskCache] Loaded ${groups.length} deduplicated word groups from ${fileToRead.path}',
      );

      // Auto-migrate legacy cache file to model-isolated folder
      if (isLegacy) {
        await saveVocab(
          directory: directory,
          model: model,
          dictionary: dictionary,
        );
      }

      return true;
    } catch (e, stack) {
      debugPrint('[AiDiskCache] Failed to load vocab cache from $directory: $e\n$stack');
      return false;
    }
  }

  /// Saves the deduplicated word groups from [dictionary] to `<gameDirectory>/ai_cache/<model>/vocab.json`.
  static Future<File?> saveVocab({
    required Directory directory,
    required String model,
    required AgiDictionary dictionary,
  }) async {
    try {
      if (!directory.existsSync()) {
        return null;
      }

      final groups = dictionary.deduplicatedWords;
      if (groups.isEmpty) {
        return null;
      }

      final cacheDir = getCacheDirectory(directory, model);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      final groupsJson = <String, List<String>>{};
      for (final entry in groups.entries) {
        groupsJson[entry.key.toString()] = entry.value;
      }

      final payload = jsonEncode({
        'version': 1,
        'model': sanitizeModelName(model),
        'wordCount': dictionary.wordCount,
        'groupCount': dictionary.groupCount,
        'groups': groupsJson,
      });

      final file = File(p.join(cacheDir.path, vocabFileName));
      await file.writeAsString(payload, flush: true);
      debugPrint(
        '[AiDiskCache] Saved ${groups.length} deduplicated word groups to ${file.path}',
      );
      return file;
    } catch (e, stack) {
      debugPrint('[AiDiskCache] Failed to save vocab cache to $directory: $e\n$stack');
      return null;
    }
  }

  /// Quantizes a unit-normalized Float32 vector to signed 8-bit integers and Base64 encodes it.
  static String quantizeToInt8Base64(Float32List vector) {
    final bytes = Int8List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      bytes[i] = (vector[i] * 127.0).round().clamp(-128, 127);
    }
    return base64.encode(
      Uint8List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  /// Decodes a Base64 signed 8-bit integer vector and reconstructs a unit-normalized Float32 vector.
  static Float32List dequantizeFromInt8Base64(String b64) {
    final raw = base64.decode(b64);
    final int8View = Int8List.view(
      raw.buffer,
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final floats = Float32List(int8View.length);
    double sumSq = 0.0;
    for (var i = 0; i < int8View.length; i++) {
      final val = int8View[i] / 127.0;
      floats[i] = val;
      sumSq += val * val;
    }
    if (sumSq > 0) {
      final norm = sqrt(sumSq);
      for (var i = 0; i < floats.length; i++) {
        floats[i] /= norm;
      }
    }
    return floats;
  }

  /// Reads and decodes JSON from [file], automatically decompressing if Gzipped.
  static Future<Map<String, dynamic>?> readCompressedOrPlainJson(File file) async {
    if (!file.existsSync()) return null;
    List<int> bytes = await file.readAsBytes();
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      bytes = gzip.decode(bytes);
    }
    final content = utf8.decode(bytes);
    return jsonDecode(content) as Map<String, dynamic>?;
  }

  /// Loads candidate phrase embeddings for [scriptNumber] from disk if cached.
  ///
  /// Path: `<gameDirectory>/ai_cache/<model>/logic_<scriptNumber>.json.gz`.
  /// Also checks uncompressed `logic_<scriptNumber>.json` if present.
  /// Returns a map from candidate phrase to normalized [Float32List] vector, or `null` if not found.
  static Future<Map<String, Float32List>?> loadLogicCandidates({
    required Directory directory,
    required String model,
    required int scriptNumber,
  }) async {
    try {
      final cacheDir = getCacheDirectory(directory, model);
      final gzFile = File(p.join(cacheDir.path, 'logic_$scriptNumber.json.gz'));
      final plainFile = File(p.join(cacheDir.path, 'logic_$scriptNumber.json'));

      File fileToRead;
      if (gzFile.existsSync()) {
        fileToRead = gzFile;
      } else if (plainFile.existsSync()) {
        fileToRead = plainFile;
      } else {
        return null;
      }

      final json = await readCompressedOrPlainJson(fileToRead);
      final embeddingsJson = json?['embeddings'] as Map<String, dynamic>?;
      if (embeddingsJson == null || embeddingsJson.isEmpty) {
        return null;
      }

      final results = <String, Float32List>{};
      for (final entry in embeddingsJson.entries) {
        if (entry.value is String) {
          results[entry.key] = dequantizeFromInt8Base64(entry.value as String);
        } else if (entry.value is List) {
          final rawList = entry.value as List;
          final vec = Float32List(rawList.length);
          for (var i = 0; i < rawList.length; i++) {
            vec[i] = (rawList[i] as num).toDouble();
          }
          results[entry.key] = vec;
        }
      }

      debugPrint(
        '[AiDiskCache] Loaded ${results.length} candidate embeddings for Logic $scriptNumber from ${fileToRead.path}',
      );
      return results;
    } catch (e, stack) {
      debugPrint(
        '[AiDiskCache] Failed to load logic candidate cache for Logic $scriptNumber: $e\n$stack',
      );
      return null;
    }
  }

  /// Saves candidate phrase embeddings for [scriptNumber] to `<gameDirectory>/ai_cache/<model>/logic_<scriptNumber>.json.gz`.
  ///
  /// Merges with existing cached candidates if a cache file for this logic already exists.
  static Future<File?> saveLogicCandidates({
    required Directory directory,
    required String model,
    required int scriptNumber,
    required Map<String, Float32List> embeddings,
  }) async {
    try {
      if (!directory.existsSync() || embeddings.isEmpty) {
        return null;
      }

      final cacheDir = getCacheDirectory(directory, model);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      // If file already exists, merge with existing embeddings
      final merged = <String, Float32List>{};
      final existing = await loadLogicCandidates(
        directory: directory,
        model: model,
        scriptNumber: scriptNumber,
      );
      if (existing != null) {
        merged.addAll(existing);
      }
      merged.addAll(embeddings);

      final encodedMap = <String, String>{};
      for (final entry in merged.entries) {
        encodedMap[entry.key] = quantizeToInt8Base64(entry.value);
      }

      final payload = jsonEncode({
        'version': 2,
        'model': sanitizeModelName(model),
        'logicId': scriptNumber,
        'candidateCount': merged.length,
        'encoding': 'int8_base64',
        'compression': 'gzip',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'embeddings': encodedMap,
      });

      final gzBytes = gzip.encode(utf8.encode(payload));
      final file = File(p.join(cacheDir.path, 'logic_$scriptNumber.json.gz'));
      await file.writeAsBytes(gzBytes, flush: true);

      // Clean up legacy uncompressed file if it exists
      final plainFile = File(p.join(cacheDir.path, 'logic_$scriptNumber.json'));
      if (plainFile.existsSync()) {
        try {
          plainFile.deleteSync();
        } catch (_) {}
      }

      debugPrint(
        '[AiDiskCache] Saved ${merged.length} candidate embeddings for Logic $scriptNumber to ${file.path} (${gzBytes.length} bytes)',
      );
      return file;
    } catch (e, stack) {
      debugPrint(
        '[AiDiskCache] Failed to save logic candidate cache for Logic $scriptNumber: $e\n$stack',
      );
      return null;
    }
  }

  /// Clears the on-disk cache for [model] (or all models if [model] is null).
  static Future<void> clearCache({
    required Directory directory,
    String? model,
  }) async {
    try {
      if (model != null) {
        final cacheDir = getCacheDirectory(directory, model);
        if (cacheDir.existsSync()) {
          await cacheDir.delete(recursive: true);
        }
      } else {
        final allCacheDir = Directory(p.join(directory.path, cacheDirName));
        if (allCacheDir.existsSync()) {
          await allCacheDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[AiDiskCache] Failed to clear cache in $directory: $e');
    }
  }
}

/// Backwards-compatible wrapper for [AiVocabCache].
class AiVocabCache {
  static const String fileName = AiDiskCache.legacyVocabFileName;

  static Future<bool> tryLoadFromDirectory({
    required Directory directory,
    required AgiDictionary dictionary,
    String model = EmbeddingService.defaultModel,
  }) =>
      AiDiskCache.tryLoadVocab(
        directory: directory,
        model: model,
        dictionary: dictionary,
      );

  static Future<File?> saveToDirectory({
    required Directory directory,
    required AgiDictionary dictionary,
    String model = EmbeddingService.defaultModel,
  }) =>
      AiDiskCache.saveVocab(
        directory: directory,
        model: model,
        dictionary: dictionary,
      );
}
