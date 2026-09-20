import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/ai/embedding_service.dart';
import 'package:flutter_agigame/engine/ai/semantic_matcher.dart';

class _FailingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    throw UnsupportedError('Unit tests must never perform real HTTP requests!');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SemanticMatcher', () {
    late EmbeddingService embeddingService;
    late SemanticMatcher matcher;

    setUp(() {
      embeddingService = EmbeddingService(httpClient: _FailingHttpClient());
      matcher = SemanticMatcher(embeddingService: embeddingService);
    });

    test('computeCosineSimilarity evaluates normalized dot products correctly', () {
      final v1 = EmbeddingService.normalize([1.0, 0.0]);
      final v2 = EmbeddingService.normalize([1.0, 0.0]);
      final v3 = EmbeddingService.normalize([0.0, 1.0]);
      final v4 = EmbeddingService.normalize([1.0, 1.0]);

      expect(SemanticMatcher.computeCosineSimilarity(v1, v2), closeTo(1.0, 1e-6));
      expect(SemanticMatcher.computeCosineSimilarity(v1, v3), closeTo(0.0, 1e-6));
      expect(SemanticMatcher.computeCosineSimilarity(v1, v4), closeTo(0.7071, 1e-3));
    });

    test('findBestMatch returns winning candidate when above threshold', () async {
      // Seed candidate vectors in cache
      final lookDeskVec = EmbeddingService.normalize([1.0, 0.1, 0.0]);
      final openDoorVec = EmbeddingService.normalize([0.0, 1.0, 0.1]);
      final takeKeyVec = EmbeddingService.normalize([0.1, 0.0, 1.0]);

      embeddingService.storeInCache('look desk (synonyms: table)', lookDeskVec);
      embeddingService.storeInCache('open door (synonyms: gate)', openDoorVec);
      embeddingService.storeInCache('take key', takeKeyVec);

      // Seed query vector for "examine table" closely aligned with "look desk"
      final queryVec = EmbeddingService.normalize([0.98, 0.15, 0.0]);
      embeddingService.storeInCache('examine table', queryVec);

      final candidates = [
        const CandidateSentence(
          id: '1',
          textToEmbed: 'look desk (synonyms: table)',
          targetCommand: 'look desk',
        ),
        const CandidateSentence(
          id: '2',
          textToEmbed: 'open door (synonyms: gate)',
          targetCommand: 'open door',
        ),
        const CandidateSentence(
          id: '3',
          textToEmbed: 'take key',
          targetCommand: 'take key',
        ),
      ];

      final result = await matcher.findBestMatch(
        userQuery: 'examine table',
        candidates: candidates,
        apiKey: 'dummy-key',
        threshold: 0.75,
      );

      expect(result.hasMatch, isTrue);
      expect(result.isNone, isFalse);
      expect(result.matchedCandidate!.targetCommand, equals('look desk'));
      expect(result.candidateIndex, equals(0));
      expect(result.score, greaterThan(0.95));
    });

    test('findBestMatch triggers none fallback when max score is below threshold', () async {
      final lookDeskVec = EmbeddingService.normalize([1.0, 0.0, 0.0, 0.0]);
      final openDoorVec = EmbeddingService.normalize([0.0, 1.0, 0.0, 0.0]);

      embeddingService.storeInCache('look desk', lookDeskVec);
      embeddingService.storeInCache('open door', openDoorVec);

      // Query vector orthogonal to all room commands
      final queryVec = EmbeddingService.normalize([0.0, 0.0, 1.0, 0.0]);
      embeddingService.storeInCache('sing a song', queryVec);

      final candidates = [
        const CandidateSentence(id: '1', textToEmbed: 'look desk', targetCommand: 'look desk'),
        const CandidateSentence(id: '2', textToEmbed: 'open door', targetCommand: 'open door'),
      ];

      final result = await matcher.findBestMatch(
        userQuery: 'sing a song',
        candidates: candidates,
        apiKey: 'dummy-key',
        threshold: 0.75,
      );

      expect(result.hasMatch, isFalse);
      expect(result.isNone, isTrue);
      expect(result.matchedCandidate, isNull);
      expect(result.score, closeTo(0.0, 1e-6));
    });

    test('threshold parameter dynamically adjusts sensitivity', () async {
      // Vectors with ~0.80 similarity
      final candVec = EmbeddingService.normalize([1.0, 0.0]);
      final queryVec = EmbeddingService.normalize([0.8, 0.6]); // dot product = 0.80

      embeddingService.storeInCache('look window', candVec);
      embeddingService.storeInCache('gaze outside', queryVec);

      final candidates = [
        const CandidateSentence(id: '1', textToEmbed: 'look window', targetCommand: 'look window'),
      ];

      // At default threshold 0.75, score 0.80 matches
      final looseMatch = await matcher.findBestMatch(
        userQuery: 'gaze outside',
        candidates: candidates,
        apiKey: 'dummy-key',
        threshold: 0.75,
      );
      expect(looseMatch.hasMatch, isTrue);

      // At strict threshold 0.85, score 0.80 triggers fallback
      final strictMatch = await matcher.findBestMatch(
        userQuery: 'gaze outside',
        candidates: candidates,
        apiKey: 'dummy-key',
        threshold: 0.85,
      );
      expect(strictMatch.hasMatch, isFalse);
      expect(strictMatch.isNone, isTrue);
    });

    test('empty query or candidates returns none with zero score', () async {
      final result1 = await matcher.findBestMatch(
        userQuery: '',
        candidates: [
          const CandidateSentence(id: '1', textToEmbed: 'look', targetCommand: 'look'),
        ],
        apiKey: 'dummy-key',
      );
      expect(result1.isNone, isTrue);
      expect(result1.score, equals(0.0));

      final result2 = await matcher.findBestMatch(
        userQuery: 'look',
        candidates: [],
        apiKey: 'dummy-key',
      );
      expect(result2.isNone, isTrue);
      expect(result2.score, equals(0.0));
    });

    group('deduplicateWordsSemantically', () {
      test('collapses true English synonyms to single representative', () {
        // Look / see / examine are aligned (>0.85 similarity)
        final vectors = {
          'look': EmbeddingService.normalize([1.0, 0.0]),
          'see': EmbeddingService.normalize([0.95, 0.31]),
          'examine': EmbeddingService.normalize([0.92, 0.39]),
          'peer': EmbeddingService.normalize([0.90, 0.43]),
        };

        final words = ['look', 'see', 'examine', 'peer'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
          threshold: 0.70,
        );

        expect(deduplicated, equals(['look']));
      });

      test('retains distinct overloaded words that are semantically unrelated', () {
        // Wizard, man, ogre, roger are virtually orthogonal in semantics
        final vectors = {
          'wizard': EmbeddingService.normalize([1.0, 0.0, 0.0, 0.0]),
          'man': EmbeddingService.normalize([0.0, 1.0, 0.0, 0.0]),
          'ogre': EmbeddingService.normalize([0.0, 0.0, 1.0, 0.0]),
          'roger': EmbeddingService.normalize([0.0, 0.0, 0.0, 1.0]),
        };

        final words = ['wizard', 'man', 'ogre', 'roger'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
          threshold: 0.70,
        );

        expect(deduplicated, equals(['wizard', 'man', 'ogre', 'roger']));
      });

      test('clusters partially overlapping groups correctly', () {
        // bush and shrub cluster together; tree and sapling cluster together
        final vectors = {
          'bush': EmbeddingService.normalize([1.0, 0.0]),
          'shrub': EmbeddingService.normalize([0.95, 0.31]),
          'tree': EmbeddingService.normalize([0.0, 1.0]),
          'sapling': EmbeddingService.normalize([0.31, 0.95]),
        };

        final words = ['bush', 'shrub', 'tree', 'sapling'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
          threshold: 0.70,
        );

        expect(deduplicated, equals(['bush', 'tree']));
      });
    });
  });
}
