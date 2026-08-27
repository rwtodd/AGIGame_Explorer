import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/ai/gemini_command_translator.dart';

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String responseBody = '';
  String? lastWrittenBody;
  Uri? lastRequestedUri;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
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
  Future<E> drain<E>([E? futureValue]) async {
    return futureValue as E;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('GeminiCommandTranslator', () {
    late _MockHttpClient mockClient;
    late GeminiCommandTranslator translator;

    setUp(() {
      mockClient = _MockHttpClient();
      translator = GeminiCommandTranslator(httpClient: mockClient);
    });

    test('translates natural language matching valid room command', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'look screen\n'}
              ]
            }
          }
        ]
      });

      final result = await translator.translate(
        rawInput: 'examine the glowing monitor display',
        roomCommands: ['look screen', 'take card', 'push button'],
        apiKey: 'test-api-key',
        roomNumber: 2,
      );

      expect(result, isNotNull);
      expect(result!.translatedCommand, equals('look screen'));
      expect(result.originalInput, equals('examine the glowing monitor display'));
      expect(result.isRoomCommandMatch, isTrue);
      expect(result.fromCache, isFalse);

      // Verify request URI contained key
      expect(mockClient.lastRequestedUri.toString(), contains('key=test-api-key'));
      // Verify body contained room commands
      expect(mockClient.lastWrittenBody, contains('look screen'));
    });

    test('translates natural language into AGI-speak when no room command matches', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '"look tapestry"'}
              ]
            }
          }
        ]
      });

      final result = await translator.translate(
        rawInput: 'is that a tapestry? take a look',
        roomCommands: ['look screen', 'take card'],
        apiKey: 'test-api-key',
        roomNumber: 2,
      );

      expect(result, isNotNull);
      expect(result!.translatedCommand, equals('look tapestry'));
      expect(result.isRoomCommandMatch, isFalse);
    });

    test('caches repeated translations for the same room and input', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'take card'}
              ]
            }
          }
        ]
      });

      final r1 = await translator.translate(
        rawInput: 'grab keycard',
        roomCommands: ['take card'],
        apiKey: 'test-api-key',
        roomNumber: 5,
      );
      expect(r1!.fromCache, isFalse);

      // Change mock response to verify second call uses cache rather than network
      mockClient.responseBody = jsonEncode({'candidates': []});

      final r2 = await translator.translate(
        rawInput: 'grab keycard',
        roomCommands: ['take card'],
        apiKey: 'test-api-key',
        roomNumber: 5,
      );
      expect(r2!.fromCache, isTrue);
      expect(r2.translatedCommand, equals('take card'));
    });

    test('testConnection returns true for 200 OK and false for error', () async {
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'PONG'}
              ]
            }
          }
        ]
      });

      final okResult = await translator.testConnection(apiKey: 'good-key');
      expect(okResult.success, isTrue);

      mockClient.statusCode = 403;
      final failResult = await translator.testConnection(apiKey: 'bad-key');
      expect(failResult.success, isFalse);
    });
  });
}
