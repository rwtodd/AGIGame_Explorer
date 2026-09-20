import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/engine/ai/gemini_command_translator.dart';
import 'package:flutter_agigame/engine/parser/agi_said_extractor.dart';

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String responseBody = '';
  String? lastWrittenBody;
  Uri? lastRequestedUri;

  String? batchEmbedResponse;
  String? embedContentResponse;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    lastRequestedUri = url;
    final body = url.toString().contains('batchEmbedContents')
        ? (batchEmbedResponse ?? responseBody)
        : (embedContentResponse ?? responseBody);
    return _MockHttpClientRequest(this, body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final _MockHttpClient client;
  final String bodyToSend;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _MockHttpClientRequest(this.client, this.bodyToSend);

  @override
  void write(Object? obj) {
    client.lastWrittenBody = obj?.toString();
  }

  @override
  Future<HttpClientResponse> close() async {
    return _MockHttpClientResponse(client.statusCode, bodyToSend);
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

    ExtractedSaidCommand makeCmd(String phrase, [List<List<String>>? synonyms]) {
      return ExtractedSaidCommand(
        scriptNumber: 2,
        wordGroupIds: const [1, 2],
        canonicalPhrase: phrase,
        wordSynonyms: synonyms ??
            phrase.split(' ').map((w) => [w]).toList(),
      );
    }

    test('translates natural language matching valid room command', () async {
      mockClient.statusCode = 200;
      // Candidates: 'look screen', 'take card', 'push button'
      mockClient.batchEmbedResponse = jsonEncode({
        'embeddings': [
          {'values': [1.0, 0.0, 0.0]}, // look screen
          {'values': [0.0, 1.0, 0.0]}, // take card
          {'values': [0.0, 0.0, 1.0]}, // push button
        ]
      });

      // User query: examine glowing monitor display -> aligned with look screen
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.95, 0.05, 0.0]
        }
      });

      final result = await translator.translate(
        rawInput: 'examine the glowing monitor display',
        commands: [
          makeCmd('look screen'),
          makeCmd('take card'),
          makeCmd('push button'),
        ],
        apiKey: 'test-api-key',
        roomNumber: 2,
      );

      expect(result, isNotNull);
      expect(result!.translatedCommand, equals('look screen'));
      expect(result.originalInput, equals('examine the glowing monitor display'));
      expect(result.isRoomCommandMatch, isTrue);
      expect(result.similarityScore, greaterThan(0.90));
      expect(mockClient.lastRequestedUri.toString(), contains('key=test-api-key'));
    });

    test('returns null when no candidate meets similarity threshold', () async {
      mockClient.statusCode = 200;
      mockClient.batchEmbedResponse = jsonEncode({
        'embeddings': [
          {'values': [1.0, 0.0, 0.0]},
          {'values': [0.0, 1.0, 0.0]},
        ]
      });

      // Orthogonal input: "talk to the alien"
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.0, 0.0, 1.0]
        }
      });

      final result = await translator.translate(
        rawInput: 'talk to the alien',
        commands: [
          makeCmd('look screen'),
          makeCmd('take card'),
        ],
        apiKey: 'test-api-key',
        threshold: 0.75,
        roomNumber: 2,
      );

      expect(result, isNull);
    });

    test('caches repeated candidate embeddings in memory', () async {
      mockClient.statusCode = 200;
      mockClient.batchEmbedResponse = jsonEncode({
        'embeddings': [
          {'values': [1.0, 0.0]}
        ]
      });
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.99, 0.01]
        }
      });

      final r1 = await translator.translate(
        rawInput: 'grab keycard',
        commands: [makeCmd('take card')],
        apiKey: 'test-api-key',
        roomNumber: 5,
      );
      expect(r1, isNotNull);
      expect(r1!.translatedCommand, equals('take card'));

      // Empty out responses to ensure cache is used
      mockClient.batchEmbedResponse = jsonEncode({'embeddings': []});
      mockClient.embedContentResponse = jsonEncode({'embedding': {'values': []}});

      final r2 = await translator.translate(
        rawInput: 'grab keycard',
        commands: [makeCmd('take card')],
        apiKey: 'test-api-key',
        roomNumber: 5,
      );
      expect(r2, isNotNull);
      expect(r2!.translatedCommand, equals('take card'));
    });

    test('deduplicateDictionary embeds multi-word groups and clusters synonyms', () async {
      mockClient.statusCode = 200;
      mockClient.batchEmbedResponse = jsonEncode({
        'embeddings': [
          {'values': [1.0, 0.0]}, // look
          {'values': [0.95, 0.31]}, // see (sim >= 0.70 to look)
          {'values': [0.92, 0.39]}, // examine (sim >= 0.70 to look)
          {'values': [0.0, 1.0]}, // wizard
          {'values': [1.0, 0.0]}, // ogre (orthogonal to wizard)
        ]
      });

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('see', 2);
      dict.addWord('examine', 2);

      dict.addWord('wizard', 45);
      dict.addWord('ogre', 45);

      dict.addWord('key', 99); // single-word group, should not require embedding

      await translator.deduplicateDictionary(
        dict,
        apiKey: 'test-key',
      );

      expect(dict.isDeduplicated, isTrue);
      // Group 2 collapsed to 'look'
      expect(dict.idToDeduplicatedWords(2), equals(['look']));
      // Group 45 preserved both 'wizard' and 'ogre'
      expect(dict.idToDeduplicatedWords(45), equals(['wizard', 'ogre']));
      // Single-word group unchanged
      expect(dict.idToDeduplicatedWords(99), equals(['key']));
    });

    test('deduplicateDictionary does not freeze vocab when embeddings fail', () async {
      mockClient.statusCode = 500;
      mockClient.batchEmbedResponse = jsonEncode({
        'error': {'message': 'unavailable'},
      });

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('see', 2);

      await translator.deduplicateDictionary(dict, apiKey: 'test-key');
      expect(dict.isDeduplicated, isFalse);
    });

    test('matches overloaded candidate phrase back to canonical target command', () async {
      mockClient.statusCode = 200;
      // Command: canonical 'look wizard', with slots: ['look'], ['wizard', 'ogre']
      // Generated phrases: 'look wizard', 'look ogre'
      mockClient.batchEmbedResponse = jsonEncode({
        'embeddings': [
          {'values': [1.0, 0.0]}, // look wizard
          {'values': [0.0, 1.0]}, // look ogre
        ]
      });

      // User types: "look at the ogre" -> aligns with 'look ogre'
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.05, 0.95] // close to look ogre
        }
      });

      final cmd = makeCmd('look wizard', [
        ['look'],
        ['wizard', 'ogre'],
      ]);

      final result = await translator.translate(
        rawInput: 'look at the ogre',
        commands: [cmd],
        apiKey: 'test-key',
        threshold: 0.75,
      );

      expect(result, isNotNull);
      // Even though user matched "look ogre", canonical target is "look wizard"!
      expect(result!.translatedCommand, equals('look wizard'));
      expect(result.similarityScore, greaterThan(0.90));
    });

    test('testConnection returns true for 200 OK and false for error', () async {
      mockClient.statusCode = 200;
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.1, 0.2, 0.3]
        }
      });

      final okResult = await translator.testConnection(apiKey: 'good-key');
      expect(okResult.success, isTrue);

      mockClient.statusCode = 403;
      mockClient.embedContentResponse = jsonEncode({
        'error': {'message': 'Invalid API Key'}
      });
      final failResult = await translator.testConnection(apiKey: 'bad-key');
      expect(failResult.success, isFalse);
    });
  });
}
