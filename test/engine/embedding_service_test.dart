import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/ai/embedding_service.dart';

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String responseBody = '';
  String? lastWrittenBody;
  Uri? lastRequestedUri;
  int postCount = 0;
  HttpClientResponse Function(int callIndex)? responseGenerator;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postCount++;
    lastRequestedUri = url;
    return _MockHttpClientRequest(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final _MockHttpClient client;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _MockHttpClientRequest(this.client);

  @override
  void write(Object? obj) {
    client.lastWrittenBody = obj?.toString();
  }

  @override
  Future<HttpClientResponse> close() async {
    if (client.responseGenerator != null) {
      return client.responseGenerator!(client.postCount);
    }
    return _MockHttpClientResponse(client.statusCode, client.responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, dynamic> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  _MockHttpClientResponse(this.statusCode, this.body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = Stream.value(utf8.encode(body));
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('EmbeddingService', () {
    late _MockHttpClient mockClient;
    late EmbeddingService service;

    setUp(() {
      mockClient = _MockHttpClient();
      service = EmbeddingService(httpClient: mockClient);
    });

    test('normalize produces unit-length vectors', () {
      final normalized = EmbeddingService.normalize([3.0, 4.0]);
      expect(normalized.length, equals(2));
      expect(normalized[0], closeTo(0.6, 1e-6));
      expect(normalized[1], closeTo(0.8, 1e-6));

      // L2 norm must be 1.0
      final norm = math.sqrt(normalized[0] * normalized[0] + normalized[1] * normalized[1]);
      expect(norm, closeTo(1.0, 1e-6));
    });

    test('normalize handles zero vector without division by zero', () {
      final normalized = EmbeddingService.normalize([0.0, 0.0, 0.0]);
      expect(normalized.every((v) => v == 0.0), isTrue);
    });

    test('embedQuery sends SEMANTIC_SIMILARITY and caches result', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'embedding': {
          'values': [0.1, 0.2, 0.3, 0.4]
        }
      });

      final vector = await service.embedQuery(
        'search the computer desk',
        apiKey: 'test-api-key',
      );

      expect(vector, isNotNull);
      expect(vector!.length, equals(4));
      expect(mockClient.postCount, equals(1));
      expect(mockClient.lastRequestedUri.toString(), contains('gemini-embedding-001:embedContent'));
      expect(mockClient.lastRequestedUri.toString(), contains('key=test-api-key'));

      final sentJson = jsonDecode(mockClient.lastWrittenBody!);
      expect(sentJson['taskType'], equals('SEMANTIC_SIMILARITY'));
      expect(sentJson['content']['parts'][0]['text'], equals('search the computer desk'));

      // Second call should return cached vector without an extra HTTP post
      final vector2 = await service.embedQuery(
        'search the computer desk',
        apiKey: 'test-api-key',
      );

      expect(vector2, equals(vector));
      expect(mockClient.postCount, equals(1)); // No additional network request
    });

    test('batchEmbedDocuments sends SEMANTIC_SIMILARITY and caches candidate vectors', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'embeddings': [
          {
            'values': [1.0, 0.0, 0.0]
          },
          {
            'values': [0.0, 1.0, 0.0]
          }
        ]
      });

      final results = await service.batchEmbedDocuments(
        ['look screen', 'take key'],
        apiKey: 'test-api-key',
      );

      expect(results.length, equals(2));
      expect(results['look screen'], isNotNull);
      expect(results['take key'], isNotNull);
      expect(mockClient.postCount, equals(1));
      expect(mockClient.lastRequestedUri.toString(), contains('gemini-embedding-001:batchEmbedContents'));

      final sentJson = jsonDecode(mockClient.lastWrittenBody!);
      expect(sentJson['requests'], hasLength(2));
      expect(sentJson['requests'][0]['taskType'], equals('SEMANTIC_SIMILARITY'));
      expect(sentJson['requests'][0]['content']['parts'][0]['text'], equals('look screen'));

      // Re-running with existing plus one new candidate should only request the missing one
      mockClient.responseBody = jsonEncode({
        'embeddings': [
          {
            'values': [0.0, 0.0, 1.0]
          }
        ]
      });

      final results2 = await service.batchEmbedDocuments(
        ['look screen', 'take key', 'open door'],
        apiKey: 'test-api-key',
      );

      expect(results2.length, equals(3));
      expect(mockClient.postCount, equals(2));

      final secondSentJson = jsonDecode(mockClient.lastWrittenBody!);
      expect(secondSentJson['requests'], hasLength(1));
      expect(secondSentJson['requests'][0]['content']['parts'][0]['text'], equals('open door'));
    });

    test('testConnection returns success on valid response', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'embedding': {
          'values': [0.1, 0.2, 0.3]
        }
      });

      final result = await service.testConnection(apiKey: 'valid-key');
      expect(result.success, isTrue);
      expect(result.statusCode, equals(200));
      expect(result.message, contains('Connected successfully'));

      final sentJson = jsonDecode(mockClient.lastWrittenBody!);
      expect(sentJson['taskType'], equals('SEMANTIC_SIMILARITY'));
    });

    test('testConnection fails when API returns error', () async {
      mockClient.statusCode = 403;
      mockClient.responseBody = jsonEncode({
        'error': {'message': 'API key not valid'}
      });

      final result = await service.testConnection(apiKey: 'invalid-key');
      expect(result.success, isFalse);
    });

    test('batchEmbedDocuments retries upon receiving HTTP 429 with retryDelay', () async {
      mockClient.responseGenerator = (callIndex) {
        if (callIndex == 1) {
          return _MockHttpClientResponse(
            429,
            jsonEncode({
              'error': {
                'code': 429,
                'message': 'Quota exceeded',
                'details': [
                  {
                    '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                    'retryDelay': '0s',
                  }
                ]
              }
            }),
          );
        } else {
          return _MockHttpClientResponse(
            200,
            jsonEncode({
              'embeddings': [
                {
                  'values': [0.5, 0.5]
                }
              ]
            }),
          );
        }
      };

      final results = await service.batchEmbedDocuments(
        ['retry test phrase'],
        apiKey: 'test-api-key',
      );

      expect(results, contains('retry test phrase'));
      expect(mockClient.postCount, equals(2));
    });

    test('storeInCache LRU-evicts the least recently used key and notifies onEvict', () {
      final evicted = <String>[];
      final service = EmbeddingService(
        httpClient: mockClient,
        maxCacheSize: 2,
        onEvict: evicted.add,
      );
      final a = EmbeddingService.normalize([1.0]);
      final b = EmbeddingService.normalize([0.0, 1.0]);
      final c = EmbeddingService.normalize([0.5, 0.5]);
      service.storeInCache('logic0', a);
      service.storeInCache('room1', b);
      expect(service.getCached('logic0'), isNotNull);
      service.storeInCache('room2', c);
      expect(evicted, equals(['room1']));
      expect(service.getCached('logic0'), isNotNull);
      expect(service.getCached('room1'), isNull);
      expect(service.getCached('room2'), isNotNull);
    });
  });
}
