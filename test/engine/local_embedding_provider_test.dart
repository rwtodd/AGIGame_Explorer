import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/ai/embedding_provider.dart';

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String responseBody = '';
  String? lastWrittenBody;
  Uri? lastRequestedUri;
  int postCount = 0;

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
    return _MockHttpClientResponse(client.statusCode, client.responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

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

class _FailingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    throw const SocketException('connection refused');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LocalEmbeddingProvider', () {
    late _MockHttpClient mockClient;
    late LocalEmbeddingProvider provider;

    setUp(() {
      mockClient = _MockHttpClient();
      provider = LocalEmbeddingProvider(httpClient: mockClient);
    });

    test('posts OpenAI-compatible input to /v1/embeddings', () async {
      mockClient.responseBody = jsonEncode({
        'object': 'list',
        'data': [
          {'object': 'embedding', 'index': 0, 'embedding': [0.1, 0.2]},
          {'object': 'embedding', 'index': 1, 'embedding': [0.3, 0.4]},
        ],
      });

      final vectors = await provider.embedTexts(['look screen', 'take key']);

      expect(vectors, hasLength(2));
      expect(vectors[0]![0], closeTo(0.1, 1e-6));
      expect(vectors[0]![1], closeTo(0.2, 1e-6));
      expect(vectors[1]![0], closeTo(0.3, 1e-6));
      expect(vectors[1]![1], closeTo(0.4, 1e-6));
      expect(mockClient.lastRequestedUri.toString(), contains('/v1/embeddings'));

      final sent = jsonDecode(mockClient.lastWrittenBody!);
      expect(sent['input'], equals(['look screen', 'take key']));
      expect(sent['model'], equals(LocalEmbeddingProvider.defaultModel));
    });

    test('maps out-of-order indices back to input order', () async {
      mockClient.responseBody = jsonEncode({
        'object': 'list',
        'data': [
          {'object': 'embedding', 'index': 1, 'embedding': [9.0]},
          {'object': 'embedding', 'index': 0, 'embedding': [1.0]},
        ],
      });

      final vectors = await provider.embedTexts(['a', 'b']);

      expect(vectors[0]!.toList(), equals([1.0]));
      expect(vectors[1]!.toList(), equals([9.0]));
    });

    test('HTTP errors yield nulls', () async {
      mockClient.statusCode = 500;
      mockClient.responseBody = jsonEncode({'error': 'loading'});

      final vectors = await provider.embedTexts(['a', 'b']);

      expect(vectors, equals([null, null]));
    });

    test('connection failures yield nulls', () async {
      final failing = LocalEmbeddingProvider(httpClient: _FailingHttpClient());

      final vectors = await failing.embedTexts(['a']);

      expect(vectors, equals([null]));
    });

    test('checkHealth reports dimensions on success', () async {
      mockClient.responseBody = jsonEncode({
        'object': 'list',
        'data': [
          {'object': 'embedding', 'index': 0, 'embedding': [0.1, 0.2, 0.3]},
        ],
      });

      final health = await provider.checkHealth();

      expect(health.success, isTrue);
      expect(health.dimensions, equals(3));
    });

    test('checkHealth fails when unreachable', () async {
      final failing = LocalEmbeddingProvider(httpClient: _FailingHttpClient());

      final health = await failing.checkHealth();

      expect(health.success, isFalse);
    });
  });
}
