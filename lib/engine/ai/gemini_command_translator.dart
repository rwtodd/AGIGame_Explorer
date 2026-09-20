import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/engine/ai/embedding_service.dart';
import 'package:flutter_agigame/engine/ai/semantic_matcher.dart';
import 'package:flutter_agigame/engine/parser/agi_said_extractor.dart';

/// Result of testing connectivity to the Gemini / Google GenAI Embedding API.
class ConnectionTestResult {
  final bool success;
  final String message;
  final int? statusCode;

  const ConnectionTestResult({
    required this.success,
    required this.message,
    this.statusCode,
  });
}

/// Result of an AI command translation or semantic match attempt.
class AiTranslationResult {
  /// The player's original input string.
  final String originalInput;

  /// The translated or matched AGI command (e.g. "look screen", "take card").
  final String translatedCommand;

  /// Whether the translation was matched to a specific room command from logic scripts.
  final bool isRoomCommandMatch;

  /// Whether this result was resolved using in-memory cached vectors.
  final bool fromCache;

  /// Cosine similarity score between the input and the matched command (0.0 to 1.0).
  final double? similarityScore;

  const AiTranslationResult({
    required this.originalInput,
    required this.translatedCommand,
    this.isRoomCommandMatch = false,
    this.fromCache = false,
    this.similarityScore,
  });

  @override
  String toString() =>
      'AiTranslationResult("$originalInput" -> "$translatedCommand", score: ${similarityScore?.toStringAsFixed(3) ?? "N/A"})';
}

/// Service that translates natural language player inputs into Sierra AGI commands
/// using Google's embedding models (`text-embedding-004` / `gemini-embedding-001`)
/// and local vector cosine similarity matching.
class GeminiCommandTranslator {
  static const String defaultModel = 'gemini-embedding-001';

  final HttpClient _httpClient;
  final Duration timeout;
  late final EmbeddingService embeddingService;
  late final SemanticMatcher semanticMatcher;

  GeminiCommandTranslator({
    HttpClient? httpClient,
    this.timeout = const Duration(milliseconds: 10000),
    EmbeddingService? embeddingService,
    SemanticMatcher? semanticMatcher,
  }) : _httpClient = httpClient ?? HttpClient() {
    this.embeddingService = embeddingService ??
        EmbeddingService(
          httpClient: _httpClient,
          timeout: timeout,
        );
    this.semanticMatcher = semanticMatcher ??
        SemanticMatcher(embeddingService: this.embeddingService);
  }

  /// Tests connectivity and API key validity with a lightweight embedding request.
  Future<ConnectionTestResult> testConnection({
    required String apiKey,
    String model = defaultModel,
  }) async {
    return embeddingService.testConnection(
      apiKey: apiKey,
      model: model,
    );
  }

  /// One-time semantic deduplication of multi-word synonym groups in [dictionary].
  ///
  /// Extracts all words from word groups having > 1 word, batch-embeds them,
  /// clusters them via [SemanticMatcher.deduplicateWordsSemantically],
  /// and saves the deduplicated lists into [dictionary.setDeduplicatedWords].
  Future<void> deduplicateDictionary(
    AgiDictionary dictionary, {
    required String apiKey,
    String model = defaultModel,
    double clusterThreshold = 0.70,
    Set<int>? relevantWordIds,
  }) async {
    if (dictionary.isDeduplicated) return;

    final multiWordGroups = <int, List<String>>{};
    final wordsToEmbed = <String>{};

    final candidateIds = relevantWordIds ?? dictionary.allIds;
    for (final id in candidateIds) {
      final words = dictionary.idToWords(id);
      final validWords = words.where((w) {
        final clean = w.trim();
        return clean.length > 1 &&
            !clean.startsWith('word_') &&
            clean != '<any>' &&
            clean != '<rol>';
      }).toList();

      if (validWords.length > 1) {
        multiWordGroups[id] = validWords;
        wordsToEmbed.addAll(validWords);
      }
    }

    if (wordsToEmbed.isNotEmpty && apiKey.trim().isNotEmpty) {
      final vectors = await embeddingService.batchEmbedDocuments(
        wordsToEmbed.toList(),
        apiKey: apiKey,
        model: model,
        taskType: EmbeddingService.defaultTaskType,
      );

      for (final entry in multiWordGroups.entries) {
        final id = entry.key;
        final words = entry.value;
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
          threshold: clusterThreshold,
        );
        dictionary.setDeduplicatedWords(id, deduplicated);
      }
    }

    dictionary.isDeduplicated = true;
  }

  /// Translates [rawInput] against [commands] using the embedding semantic matcher.
  ///
  /// Generates candidate sentences from each command's deduplicated synonyms,
  /// embeds them with [EmbeddingService], and computes cosine similarity locally.
  /// Returns [AiTranslationResult] if a candidate exceeds [threshold] (default: 0.75),
  /// or `null` if no candidate was semantically close enough (triggering native fallback).
  Future<AiTranslationResult?> translate({
    required String rawInput,
    required List<ExtractedSaidCommand> commands,
    required String apiKey,
    String model = defaultModel,
    double threshold = SemanticMatcher.defaultThreshold,
    int? roomNumber,
  }) async {
    final clean = rawInput.trim();
    if (clean.isEmpty || apiKey.trim().isEmpty || commands.isEmpty) return null;

    final candidates = <CandidateSentence>[];
    for (var cmdIndex = 0; cmdIndex < commands.length; cmdIndex++) {
      final cmd = commands[cmdIndex];
      final phrases = cmd.generateCandidatePhrases();
      for (var pIndex = 0; pIndex < phrases.length; pIndex++) {
        final phrase = phrases[pIndex];
        candidates.add(
          CandidateSentence(
            id: '${cmd.scriptNumber}:$cmdIndex:$pIndex:$phrase',
            textToEmbed: phrase,
            targetCommand: cmd.canonicalPhrase,
            metadata: cmd,
          ),
        );
      }
    }

    final matchResult = await semanticMatcher.findBestMatch(
      userQuery: clean,
      candidates: candidates,
      apiKey: apiKey,
      threshold: threshold,
      model: model,
    );

    if (matchResult.hasMatch) {
      final winner = matchResult.matchedCandidate!;
      debugPrint(
        '[Embedding AI] Matched "$clean" -> "${winner.targetCommand}" '
        '(score: ${matchResult.score.toStringAsFixed(3)})',
      );
      return AiTranslationResult(
        originalInput: clean,
        translatedCommand: winner.targetCommand,
        isRoomCommandMatch: true,
        fromCache: matchResult.fromCache,
        similarityScore: matchResult.score,
      );
    }

    debugPrint(
      '[Embedding AI] No candidate met threshold $threshold for "$clean" '
      '(max score: ${matchResult.score.toStringAsFixed(3)})',
    );
    return null;
  }

  /// Clears the embedding vector cache.
  void clearCache() {
    embeddingService.clearCache();
  }
}
