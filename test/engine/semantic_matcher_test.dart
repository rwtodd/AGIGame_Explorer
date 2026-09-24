import 'dart:async';
import 'dart:convert';
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

/// Minimal mock that serves one embedding vector per request and counts calls.
class _CountingHttpClient implements HttpClient {
  int postCount = 0;
  final List<double> queryVector;

  _CountingHttpClient(this.queryVector);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postCount++;
    return _CountingRequest(url, queryVector);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingRequest implements HttpClientRequest {
  final Uri url;
  final List<double> queryVector;

  _CountingRequest(this.url, this.queryVector);

  @override
  HttpHeaders get headers => _DummyHeaders();

  @override
  void write(Object? obj) {}

  @override
  Future<HttpClientResponse> close() async {
    final body = url.path.contains('batchEmbedContents')
        ? jsonEncode({
            'embeddings': [
              {'values': queryVector},
            ],
          })
        : jsonEncode({
            'embedding': {'values': queryVector},
          });
    return _CountingResponse(body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingResponse extends Stream<List<int>> implements HttpClientResponse {
  final String body;

  _CountingResponse(this.body);

  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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
      expect(
        SemanticMatcher.computeCosineSimilarity(
          EmbeddingService.normalize([1.0, 0.0]),
          EmbeddingService.normalize([1.0, 0.0, 0.0]),
        ),
        0.0,
      );
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
      expect(result.fromCache, isTrue);
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

    test('uncached query embeds once while cached candidates are not refetched', () async {
      final countingClient = _CountingHttpClient([0.98, 0.15, 0.0]);
      final cachedService = EmbeddingService(httpClient: countingClient);
      final cachedMatcher = SemanticMatcher(embeddingService: cachedService);

      cachedService.storeInCache(
        'look desk',
        EmbeddingService.normalize([1.0, 0.1, 0.0]),
      );
      cachedService.storeInCache(
        'open door',
        EmbeddingService.normalize([0.0, 1.0, 0.1]),
      );

      final result = await cachedMatcher.findBestMatch(
        userQuery: 'examine table',
        candidates: const [
          CandidateSentence(id: '1', textToEmbed: 'look desk', targetCommand: 'look desk'),
          CandidateSentence(id: '2', textToEmbed: 'open door', targetCommand: 'open door'),
        ],
        apiKey: 'dummy-key',
      );

      expect(result.hasMatch, isTrue);
      expect(result.matchedCandidate!.targetCommand, equals('look desk'));
      expect(result.fromCache, isFalse);
      // Exactly one network call (the uncached query); cached candidates
      // must not trigger a batch refetch.
      expect(countingClient.postCount, equals(1));
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
      test('collapses true English synonyms to single representative using default threshold', () {
        // Look / see / peer / gaze are aligned (>0.88 similarity)
        final vectors = {
          'look': EmbeddingService.normalize([1.0, 0.0]),
          'see': EmbeddingService.normalize([0.95, 0.31]),
          'peer': EmbeddingService.normalize([0.90, 0.43]),
          'gaze': EmbeddingService.normalize([0.91, 0.41]),
        };

        final words = ['look', 'see', 'peer', 'gaze'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
        );

        expect(deduplicated, equals(['look']));
      });

      test('preserves both preferred words when multiple preferred words exist in the same group', () {
        // 'take', 'get', 'catch' are all preferred verbs
        final vectors = {
          'take': EmbeddingService.normalize([1.0, 0.0]),
          'get': EmbeddingService.normalize([0.96, 0.28]), // > 0.88 to take
          'catch': EmbeddingService.normalize([0.90, 0.43]), // > 0.88 to take
          'grab': EmbeddingService.normalize([0.95, 0.31]), // collapses into take/get
          'pick up': EmbeddingService.normalize([0.94, 0.34]), // collapses into take/get
        };

        final words = ['catch', 'get', 'grab', 'pick up', 'take'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
        );

        expect(deduplicated, contains('take'));
        expect(deduplicated, contains('get'));
        expect(deduplicated, contains('catch'));
        expect(deduplicated, isNot(contains('grab')));
        expect(deduplicated, isNot(contains('pick up')));
      });

      test('prioritizes natural canonical words over alphabetical order or profanity', () {
        // 'bitch' comes first alphabetically, but 'look' is preferred
        final vectors = {
          'bitch': EmbeddingService.normalize([0.80, 0.60]),
          'check out': EmbeddingService.normalize([0.95, 0.31]),
          'look': EmbeddingService.normalize([1.0, 0.0]),
          'examine': EmbeddingService.normalize([0.92, 0.39]),
        };

        // Input passed with alphabetical order
        final words = ['bitch', 'check out', 'examine', 'look'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
        );

        // 'look' must be the first prototype, not 'bitch' or 'check out'
        expect(deduplicated.first, equals('look'));
      });

      test('preserves distinct entities in overloaded word groups', () {
        // Distinct entities: girl, woman, witch, fairy
        final vectors = {
          'girl': EmbeddingService.normalize([1.0, 0.0, 0.0, 0.0]),
          'damsel': EmbeddingService.normalize([0.95, 0.31, 0.0, 0.0]), // sim 0.95 to girl -> collapses
          'woman': EmbeddingService.normalize([0.80, 0.60, 0.0, 0.0]), // sim 0.80 < 0.88 -> preserved!
          'witch': EmbeddingService.normalize([0.0, 0.0, 1.0, 0.0]), // orthogonal -> preserved!
          'hag': EmbeddingService.normalize([0.0, 0.0, 0.95, 0.31]), // sim 0.95 to witch -> collapses
          'fairy': EmbeddingService.normalize([0.0, 0.0, 0.0, 1.0]), // orthogonal -> preserved!
          'bitch': EmbeddingService.normalize([0.90, 0.43, 0.0, 0.0]), // sim 0.90 to girl -> collapses into girl
        };

        final words = ['bitch', 'damsel', 'fairy', 'girl', 'hag', 'witch', 'woman'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
        );

        // Preserves girl, woman, witch, fairy; collapses damsel, hag, bitch
        expect(deduplicated, contains('girl'));
        expect(deduplicated, contains('woman'));
        expect(deduplicated, contains('witch'));
        expect(deduplicated, contains('fairy'));
        expect(deduplicated, isNot(contains('bitch')));
        expect(deduplicated, isNot(contains('damsel')));
        expect(deduplicated, isNot(contains('hag')));
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
        );

        expect(deduplicated, equals(['tree', 'bush']));
      });

      test('preserves distinct core adventure objects (clam, shell, clamshell) and purges obscenities', () {
        final vectors = {
          'clam': EmbeddingService.normalize([1.0, 0.0]),
          'shell': EmbeddingService.normalize([0.92, 0.39]), // highly aligned
          'clamshell': EmbeddingService.normalize([0.94, 0.34]), // highly aligned
          'clam shell': EmbeddingService.normalize([0.96, 0.28]), // compound
          'cunt': EmbeddingService.normalize([0.1, 0.9]), // unrelated obscenity
        };

        final words = ['clam', 'clam shell', 'clamshell', 'cunt', 'shell'];
        final deduplicated = SemanticMatcher.deduplicateWordsSemantically(
          words,
          vectors,
        );

        expect(deduplicated, contains('clam'));
        expect(deduplicated, contains('shell'));
        expect(deduplicated, contains('clamshell'));
        expect(deduplicated, isNot(contains('cunt')));
      });
    });
  });
}
