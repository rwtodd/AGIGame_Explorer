import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/engine/ai/embedding_provider.dart';

/// Service for generating, caching, and batching vector embeddings.
///
/// Transport is delegated to an [EmbeddingProvider] (local `llama-server`
/// by default); this class keeps only the in-memory LRU cache, request
/// batching, and unit-length normalization used for cosine similarity.
class EmbeddingService {
  static const String defaultModel = LocalEmbeddingProvider.defaultModel;
  static const int defaultBatchSize = 50;
  static const int defaultMaxCacheSize = 5000;

  final EmbeddingProvider _provider;
  EmbeddingProvider get provider => _provider;

  final int maxCacheSize;
  final Map<String, Float32List> _cache = {};

  /// Called with the normalized key when an entry is FIFO/LRU-evicted.
  void Function(String evictedKey)? onEvict;

  EmbeddingService({
    EmbeddingProvider? provider,
    HttpClient? httpClient,
    Uri? endpoint,
    this.maxCacheSize = defaultMaxCacheSize,
    this.onEvict,
  }) : _provider = provider ??
            LocalEmbeddingProvider(
              httpClient: httpClient,
              endpoint: endpoint,
            );

  /// Re-points the service at a (possibly restarted) local server endpoint.
  void updateEndpoint(Uri endpoint) {
    final current = _provider;
    if (current is LocalEmbeddingProvider) {
      current.endpoint = endpoint;
    }
  }

  /// Number of unique text embeddings currently stored in memory.
  int get cachedCount => _cache.length;

  /// Clears the in-memory embedding cache.
  void clearCache() => _cache.clear();

  /// Normalizes a cache lookup key.
  static String normalizeKey(String text) => text.trim().toLowerCase();

  /// Normalizes a vector to unit length ($L_2$ norm = 1.0).
  ///
  /// Storing unit vectors allows cosine similarity to be computed as a fast dot product.
  static Float32List normalize(List<num> raw) {
    final list = Float32List(raw.length);
    double sumSq = 0.0;
    for (var i = 0; i < raw.length; i++) {
      final v = raw[i].toDouble();
      list[i] = v;
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm > 1e-12) {
      for (var i = 0; i < list.length; i++) {
        list[i] = list[i] / norm;
      }
    }
    return list;
  }

  /// Retrieves an existing embedding from cache if present.
  /// Hits are moved to the most-recent end so Logic 0 is not FIFO-evicted first.
  Float32List? getCached(String text) {
    final key = normalizeKey(text);
    final vec = _cache.remove(key);
    if (vec == null) return null;
    _cache[key] = vec;
    return vec;
  }

  /// Stores an embedding vector in cache, evicting the least-recent entry if full.
  void storeInCache(String text, Float32List vector) {
    final key = normalizeKey(text);
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxCacheSize) {
      final evicted = _cache.keys.first;
      _cache.remove(evicted);
      onEvict?.call(evicted);
    }
    _cache[key] = vector;
  }

  /// Bulk stores pre-computed embedding vectors into cache.
  void storeAllInCache(Map<String, Float32List> vectors) {
    for (final entry in vectors.entries) {
      storeInCache(entry.key, entry.value);
    }
  }

  /// Tests connectivity to the embedding provider with a lightweight query.
  Future<ConnectionTestResult> testConnection() async {
    try {
      return await _provider.checkHealth();
    } catch (e, stack) {
      debugPrint('[EmbeddingService] testConnection error: $e\n$stack');
      return ConnectionTestResult(
        success: false,
        message: 'Error: $e',
      );
    }
  }

  /// Embeds a single query or text on demand.
  Future<Float32List?> embedQuery(
    String query, {
    bool useCache = true,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    final key = normalizeKey(clean);
    if (useCache && _cache.containsKey(key)) {
      return _cache[key];
    }

    final vectors = await _provider.embedTexts([clean]);
    final raw = vectors.isNotEmpty ? vectors.first : null;
    if (raw == null || raw.isEmpty) {
      debugPrint('[EmbeddingService] embedQuery returned no vector');
      return null;
    }

    final vector = normalize(raw);
    if (useCache) {
      storeInCache(clean, vector);
    }
    return vector;
  }

  /// Batch embeds multiple texts.
  ///
  /// Reuses cached vectors where available and only sends requests for uncached texts.
  /// Automatically chunks requests into batches of [batchSize].
  Future<Map<String, Float32List>> batchEmbedDocuments(
    List<String> texts, {
    int batchSize = defaultBatchSize,
  }) async {
    final results = <String, Float32List>{};
    if (texts.isEmpty) return results;

    // 1. Gather uncached texts
    final missingTexts = <String>[];
    for (final text in texts) {
      final clean = text.trim();
      if (clean.isEmpty) continue;
      final cached = _cache[normalizeKey(clean)];
      if (cached != null) {
        results[clean] = cached;
      } else if (!missingTexts.contains(clean)) {
        missingTexts.add(clean);
      }
    }

    if (missingTexts.isEmpty) {
      return results;
    }

    // 2. Chunk missing texts into batches
    for (var i = 0; i < missingTexts.length; i += batchSize) {
      final chunk = missingTexts.sublist(
        i,
        math.min(i + batchSize, missingTexts.length),
      );

      final vectors = await _provider.embedTexts(chunk);
      for (var c = 0; c < chunk.length && c < vectors.length; c++) {
        final raw = vectors[c];
        if (raw != null && raw.isNotEmpty) {
          final vector = normalize(raw);
          final text = chunk[c];
          storeInCache(text, vector);
          results[text] = vector;
        }
      }
    }

    return results;
  }
}
