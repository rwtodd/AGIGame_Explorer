import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/engine/ai/gemini_command_translator.dart' show ConnectionTestResult;

/// Service for generating, caching, and batching vector embeddings using the Google GenAI API.
class EmbeddingService {
  static const String defaultModel = 'gemini-embedding-001';
  static const String defaultTaskType = 'SEMANTIC_SIMILARITY';
  static const String apiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
  static const int defaultBatchSize = 50;
  static const int defaultMaxCacheSize = 5000;

  final HttpClient _httpClient;
  final Duration timeout;
  final int maxCacheSize;
  final Map<String, Float32List> _cache = {};

  /// Called with the normalized key when an entry is FIFO/LRU-evicted.
  void Function(String evictedKey)? onEvict;

  EmbeddingService({
    HttpClient? httpClient,
    this.timeout = const Duration(milliseconds: 10000),
    this.maxCacheSize = defaultMaxCacheSize,
    this.onEvict,
  }) : _httpClient = httpClient ?? HttpClient();

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

  /// Tests connectivity and API key validity with a lightweight query embedding.
  Future<ConnectionTestResult> testConnection({
    required String apiKey,
    String model = defaultModel,
    String taskType = defaultTaskType,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'API key is empty',
      );
    }

    try {
      final endpointModel = model.startsWith('models/') ? model.substring('models/'.length) : model;
      final uri = Uri.parse('$apiBaseUrl/$endpointModel:embedContent?key=$cleanKey');
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final body = jsonEncode({
        'model': 'models/$endpointModel',
        'content': {
          'parts': [
            {'text': 'ping'}
          ]
        },
        'taskType': taskType,
      });

      request.write(body);
      final response = await request.close().timeout(timeout);
      final responseStr = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(responseStr);
        final embeddingObj = json['embedding'] as Map<String, dynamic>?;
        final rawValues = embeddingObj?['values'] as List?;
        if (rawValues != null && rawValues.isNotEmpty) {
          return ConnectionTestResult(
            success: true,
            message: 'Connected successfully to $model (${rawValues.length} dims)',
            statusCode: 200,
          );
        }
        return const ConnectionTestResult(
          success: false,
          message: 'Received empty embedding response from API',
          statusCode: 200,
        );
      } else {
        String errorDetail = 'HTTP ${response.statusCode}';
        try {
          final Map<String, dynamic> json = jsonDecode(responseStr);
          if (json['error'] != null && json['error']['message'] != null) {
            errorDetail = '${json['error']['message']} (HTTP ${response.statusCode})';
          }
        } catch (_) {}
        return ConnectionTestResult(
          success: false,
          message: errorDetail,
          statusCode: response.statusCode,
        );
      }
    } catch (e, stack) {
      debugPrint('[EmbeddingService] testConnection error: $e\n$stack');
      return ConnectionTestResult(
        success: false,
        message: 'Error: $e',
      );
    }
  }

  /// Embeds a single query or text on demand using task_type [taskType] (default: [SEMANTIC_SIMILARITY]).
  Future<Float32List?> embedQuery(
    String query, {
    required String apiKey,
    String model = defaultModel,
    String taskType = defaultTaskType,
    bool useCache = true,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty || apiKey.trim().isEmpty) return null;

    final key = normalizeKey(clean);
    if (useCache && _cache.containsKey(key)) {
      return _cache[key];
    }

    final endpointModel = model.startsWith('models/') ? model.substring('models/'.length) : model;
    final uri = Uri.parse('$apiBaseUrl/$endpointModel:embedContent?key=${apiKey.trim()}');

    try {
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final body = jsonEncode({
        'model': 'models/$endpointModel',
        'content': {
          'parts': [
            {'text': clean}
          ]
        },
        'taskType': taskType,
      });

      request.write(body);
      final response = await request.close().timeout(timeout);
      final responseStr = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('[EmbeddingService] embedQuery HTTP ${response.statusCode}: $responseStr');
        return null;
      }

      final Map<String, dynamic> json = jsonDecode(responseStr);
      final embeddingObj = json['embedding'] as Map<String, dynamic>?;
      final rawValues = embeddingObj?['values'] as List?;

      if (rawValues == null || rawValues.isEmpty) {
        debugPrint('[EmbeddingService] embedQuery returned no vector values');
        return null;
      }

      final vector = normalize(rawValues.cast<num>());
      if (useCache) {
        storeInCache(clean, vector);
      }
      return vector;
    } catch (e, stack) {
      debugPrint('[EmbeddingService] embedQuery exception: $e\n$stack');
      return null;
    }
  }

  /// Batch embeds multiple texts using task_type [taskType] (default: [SEMANTIC_SIMILARITY]).
  ///
  /// Reuses cached vectors where available and only sends requests for uncached texts.
  /// Automatically chunks requests into batches of [batchSize] (default: 100).
  Future<Map<String, Float32List>> batchEmbedDocuments(
    List<String> texts, {
    required String apiKey,
    String model = defaultModel,
    String taskType = defaultTaskType,
    int batchSize = defaultBatchSize,
  }) async {
    final cleanKey = apiKey.trim();
    final results = <String, Float32List>{};
    if (texts.isEmpty || cleanKey.isEmpty) return results;

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

    final endpointModel = model.startsWith('models/') ? model.substring('models/'.length) : model;
    final uri = Uri.parse('$apiBaseUrl/$endpointModel:batchEmbedContents?key=$cleanKey');

    // 2. Chunk missing texts into batches
    for (var i = 0; i < missingTexts.length; i += batchSize) {
      final chunk = missingTexts.sublist(
        i,
        math.min(i + batchSize, missingTexts.length),
      );

      var attempt = 0;
      const maxRetries = 3;
      bool chunkSucceeded = false;

      while (attempt < maxRetries && !chunkSucceeded) {
        attempt++;
        try {
          final request = await _httpClient.postUrl(uri).timeout(timeout);
          request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

          final body = jsonEncode({
            'requests': [
              for (final text in chunk)
                {
                  'model': 'models/$endpointModel',
                  'content': {
                    'parts': [
                      {'text': text}
                    ]
                  },
                  'taskType': taskType,
                }
            ]
          });

          request.write(body);
          final response = await request.close().timeout(timeout);
          final responseStr = await response.transform(utf8.decoder).join();

          if (response.statusCode == 429) {
            int retrySeconds = math.min(60, 2 * attempt * attempt + 5);
            try {
              final Map<String, dynamic> errJson = jsonDecode(responseStr);
              final details = errJson['error']?['details'] as List?;
              if (details != null) {
                for (final d in details) {
                  final delayStr = d['retryDelay']?.toString();
                  if (delayStr != null) {
                    final numVal = double.tryParse(delayStr.replaceAll('s', ''));
                    if (numVal != null && numVal >= 0) {
                      retrySeconds = numVal.ceil();
                    }
                  }
                }
              }
            } catch (_) {}

            debugPrint(
              '[EmbeddingService] Rate limit 429 hit. Retrying chunk in ${retrySeconds}s (attempt $attempt of $maxRetries)...',
            );
            await Future.delayed(Duration(seconds: retrySeconds));
            continue;
          }

          if (response.statusCode != 200) {
            debugPrint('[EmbeddingService] batchEmbedDocuments HTTP ${response.statusCode}: $responseStr');
            break;
          }

          final Map<String, dynamic> json = jsonDecode(responseStr);
          final embeddingsList = json['embeddings'] as List?;
          if (embeddingsList == null) break;

          final count = math.min(chunk.length, embeddingsList.length);
          for (var c = 0; c < count; c++) {
            final embMap = embeddingsList[c] as Map<String, dynamic>?;
            final rawValues = embMap?['values'] as List?;
            if (rawValues != null && rawValues.isNotEmpty) {
              final vector = normalize(rawValues.cast<num>());
              final text = chunk[c];
              storeInCache(text, vector);
              results[text] = vector;
            }
          }
          chunkSucceeded = true;
        } catch (e, stack) {
          debugPrint('[EmbeddingService] batchEmbedDocuments chunk exception: $e\n$stack');
          break;
        }
      }

      // Polite inter-batch pause to prevent burst quota exhaustion
      if (i + batchSize < missingTexts.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    return results;
  }
}
