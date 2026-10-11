import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Result of testing connectivity to an embedding provider.
class ConnectionTestResult {
  final bool success;
  final String message;
  final int? statusCode;

  /// Embedding vector width reported by the provider, when known.
  final int? dimensions;

  const ConnectionTestResult({
    required this.success,
    required this.message,
    this.statusCode,
    this.dimensions,
  });
}

/// Abstract transport for producing embedding vectors.
///
/// Implementations hide where vectors come from (local sidecar server,
/// remote API, or a fake in tests) so [EmbeddingService] keeps only
/// caching, batching, and normalization logic.
abstract class EmbeddingProvider {
  /// Human-readable provider name used in status messages.
  String get name;

  /// Model identifier sent to the provider (e.g. GGUF file or model slug).
  String get model;

  /// Returns one vector per input text, in order, with `null` for failures.
  Future<List<Float32List?>> embedTexts(List<String> texts);

  /// Lightweight health check; embeds a ping to also report vector width.
  Future<ConnectionTestResult> checkHealth();
}

/// Embedding provider for a local `llama-server` (llama.cpp) instance.
///
/// Speaks the OpenAI-compatible `POST {endpoint}/v1/embeddings` API enabled
/// by starting the server with `--embeddings`. No API key is involved.
class LocalEmbeddingProvider implements EmbeddingProvider {
  /// Default model slug for the text-only EmbeddingGemma 2 encoder.
  static const String defaultModel = 'embeddinggemma-2-text';

  /// Expected vector width of EmbeddingGemma 2 (unified 768-dim space).
  static const int expectedDimensions = 768;

  static const int defaultBatchSize = 100;

  @override
  String name = 'local';

  @override
  String model;

  Uri endpoint;
  final HttpClient _httpClient;
  final Duration timeout;
  final int batchSize;

  LocalEmbeddingProvider({
    HttpClient? httpClient,
    Uri? endpoint,
    this.model = defaultModel,
    this.timeout = const Duration(milliseconds: 30000),
    this.batchSize = defaultBatchSize,
  })  : _httpClient = httpClient ?? HttpClient(),
        endpoint = endpoint ?? Uri.parse('http://127.0.0.1:8080');

  Uri get _embeddingsUri => endpoint.resolve('/v1/embeddings');

  @override
  Future<List<Float32List?>> embedTexts(List<String> texts) async {
    final results = List<Float32List?>.filled(texts.length, null);
    for (var i = 0; i < texts.length; i += batchSize) {
      final end = (i + batchSize < texts.length) ? i + batchSize : texts.length;
      final chunk = texts.sublist(i, end);
      final vectors = await _embedChunk(chunk);
      for (var c = 0; c < chunk.length; c++) {
        results[i + c] = vectors[c];
      }
    }
    return results;
  }

  /// Embeds one chunk, preserving order; failures yield `null` entries.
  Future<List<Float32List?>> _embedChunk(List<String> chunk) async {
    final results = List<Float32List?>.filled(chunk.length, null);
    try {
      final request = await _httpClient.postUrl(_embeddingsUri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode({
        'model': model,
        'input': chunk,
      }));
      final response = await request.close().timeout(timeout);
      final responseStr = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('[LocalEmbeddingProvider] HTTP ${response.statusCode}: $responseStr');
        return results;
      }

      final Map<String, dynamic> json = jsonDecode(responseStr);
      final data = json['data'] as List?;
      if (data == null) {
        debugPrint('[LocalEmbeddingProvider] response missing data array');
        return results;
      }

      for (final item in data) {
        final map = item as Map<String, dynamic>?;
        final index = map?['index'] as int?;
        final values = map?['embedding'] as List?;
        if (index != null && index >= 0 && index < results.length && values != null && values.isNotEmpty) {
          final vec = Float32List(values.length);
          for (var v = 0; v < values.length; v++) {
            vec[v] = (values[v] as num).toDouble();
          }
          results[index] = vec;
        }
      }
    } catch (e, stack) {
      debugPrint('[LocalEmbeddingProvider] embed chunk exception: $e\n$stack');
    }
    return results;
  }

  @override
  Future<ConnectionTestResult> checkHealth() async {
    try {
      final vectors = await embedTexts(const ['ping']).timeout(timeout);
      final vec = vectors.isNotEmpty ? vectors.first : null;
      if (vec != null && vec.isNotEmpty) {
        return ConnectionTestResult(
          success: true,
          message: 'Connected to $name $model (${vec.length} dims)',
          statusCode: 200,
          dimensions: vec.length,
        );
      }
      return const ConnectionTestResult(
        success: false,
        message: 'Local embedding server returned no vector',
        statusCode: 200,
      );
    } catch (e) {
      return ConnectionTestResult(
        success: false,
        message: 'Local embedding server unreachable at $endpoint ($e)',
      );
    }
  }
}
