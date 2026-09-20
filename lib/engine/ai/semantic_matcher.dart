import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_agigame/engine/ai/embedding_service.dart';

/// Represents a candidate game action to be evaluated for semantic similarity.
class CandidateSentence {
  /// Unique identifier for this candidate (e.g. script:command or text hash).
  final String id;

  /// The enriched descriptive text used for vector embedding.
  /// Example: "look desk (synonyms: table, drawer)"
  final String textToEmbed;

  /// The canonical command to execute if matched.
  /// Example: "look desk"
  final String targetCommand;

  /// Optional metadata attached to this candidate (e.g. [ExtractedSaidCommand]).
  final dynamic metadata;

  const CandidateSentence({
    required this.id,
    required this.textToEmbed,
    required this.targetCommand,
    this.metadata,
  });

  @override
  String toString() => '$targetCommand [$id]';
}

/// Result of evaluating a user input against a set of candidate sentences.
class SemanticMatchResult {
  /// Whether no candidate was semantically close enough to exceed the similarity threshold.
  final bool isNone;

  /// The highest-scoring candidate, or `null` if none exceeded the threshold.
  final CandidateSentence? matchedCandidate;

  /// The index of the matched candidate in the original candidates list.
  final int? candidateIndex;

  /// The highest cosine similarity score computed (0.0 to 1.0).
  final double score;

  /// Whether the result was resolved using cached vectors without new API generation calls.
  final bool fromCache;

  /// Whether a valid candidate was successfully matched above threshold.
  bool get hasMatch => !isNone && matchedCandidate != null;

  const SemanticMatchResult.match({
    required this.matchedCandidate,
    required this.candidateIndex,
    required this.score,
    this.fromCache = false,
  }) : isNone = false;

  const SemanticMatchResult.none({
    required this.score,
    this.fromCache = false,
  })  : isNone = true,
        matchedCandidate = null,
        candidateIndex = null;

  @override
  String toString() {
    if (hasMatch) {
      return 'SemanticMatch(candidate: "${matchedCandidate!.targetCommand}", score: ${score.toStringAsFixed(3)}, index: $candidateIndex)';
    }
    return 'SemanticMatch(none, maxScore: ${score.toStringAsFixed(3)})';
  }
}

/// Matches user natural language input against candidate game actions using local vector cosine similarity.
class SemanticMatcher {
  static const double defaultThreshold = 0.75;

  final EmbeddingService embeddingService;

  SemanticMatcher({EmbeddingService? embeddingService})
      : embeddingService = embeddingService ?? EmbeddingService();

  /// Computes cosine similarity between two normalized vectors.
  ///
  /// Since [EmbeddingService] produces unit-length vectors ($\|a\| = \|b\| = 1$),
  /// cosine similarity simplifies to the Euclidean dot product:
  /// $\cos(\theta) = a \cdot b$.
  static double computeCosineSimilarity(Float32List a, Float32List b) {
    final len = math.min(a.length, b.length);
    double dot = 0.0;
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    // Clamp to [0.0, 1.0] for similarity comparison
    return dot.clamp(0.0, 1.0);
  }

  /// Reduces a list of [words] down to minimal semantic representatives
  /// using greedy centroid clustering on their embedding vectors in [wordVectors].
  ///
  /// Any word that has cosine similarity >= [threshold] (default: 0.70)
  /// with an already-accepted representative is considered covered and discarded.
  static List<String> deduplicateWordsSemantically(
    List<String> words,
    Map<String, Float32List> wordVectors, {
    double threshold = 0.70,
  }) {
    if (words.length <= 1) return words;

    final representatives = <String>[];
    for (final word in words) {
      final clean = word.trim().toLowerCase();
      if (clean.isEmpty) continue;

      final vec = wordVectors[clean] ?? wordVectors[word];
      if (vec == null) {
        if (!representatives.contains(word)) {
          representatives.add(word);
        }
        continue;
      }

      bool covered = false;
      for (final rep in representatives) {
        final repVec = wordVectors[rep.toLowerCase()] ?? wordVectors[rep];
        if (repVec != null) {
          final sim = computeCosineSimilarity(vec, repVec);
          if (sim >= threshold) {
            covered = true;
            break;
          }
        }
      }

      if (!covered) {
        representatives.add(word);
      }
    }

    return representatives.isEmpty ? words : representatives;
  }

  /// Finds the candidate sentence that best matches [userQuery].
  ///
  /// 1. Ensures candidate embeddings are pre-computed / cached via [EmbeddingService].
  /// 2. Embeds the [userQuery] with `taskType: RETRIEVAL_QUERY`.
  /// 3. Computes local dot product against each candidate vector in memory.
  /// 4. If `maxScore < threshold`, returns a fallback result [SemanticMatchResult.none].
  /// 5. Otherwise, returns the winning candidate with [SemanticMatchResult.match].
  Future<SemanticMatchResult> findBestMatch({
    required String userQuery,
    required List<CandidateSentence> candidates,
    required String apiKey,
    double threshold = defaultThreshold,
    String model = EmbeddingService.defaultModel,
  }) async {
    final cleanQuery = userQuery.trim();
    if (cleanQuery.isEmpty || candidates.isEmpty || apiKey.trim().isEmpty) {
      return const SemanticMatchResult.none(score: 0.0);
    }

    // Step 1: Ensure candidate embeddings are batch-computed/cached
    final candidateTexts = candidates.map((c) => c.textToEmbed).toList();
    final docVectors = await embeddingService.batchEmbedDocuments(
      candidateTexts,
      apiKey: apiKey,
      model: model,
    );

    // Step 2: Embed the incoming user search query
    final queryVector = await embeddingService.embedQuery(
      cleanQuery,
      apiKey: apiKey,
      model: model,
    );

    if (queryVector == null) {
      return const SemanticMatchResult.none(score: 0.0);
    }

    // Step 3: Compute cosine similarity locally in memory
    double maxScore = -1.0;
    CandidateSentence? bestCandidate;
    int? bestIndex;

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final candVector = docVectors[candidate.textToEmbed] ??
          embeddingService.getCached(candidate.textToEmbed);

      if (candVector == null) continue;

      final similarity = computeCosineSimilarity(queryVector, candVector);
      if (similarity > maxScore) {
        maxScore = similarity;
        bestCandidate = candidate;
        bestIndex = i;
      }
    }

    final finalScore = math.max(0.0, maxScore);

    // Step 4: Apply threshold / fallback logic
    if (bestCandidate == null || finalScore < threshold) {
      return SemanticMatchResult.none(score: finalScore);
    }

    return SemanticMatchResult.match(
      matchedCandidate: bestCandidate,
      candidateIndex: bestIndex,
      score: finalScore,
    );
  }
}
