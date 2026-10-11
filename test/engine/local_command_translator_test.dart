import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/engine/ai/local_command_translator.dart';
import 'package:flutter_agigame/engine/parser/agi_said_extractor.dart';

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String? lastWrittenBody;
  Uri? lastRequestedUri;

  /// Vector served per request input text; missing texts yield no entry.
  final Map<String, List<double>> vectorsByText = {};

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    lastRequestedUri = url;
    return _MockHttpClientRequest(this);
  }

  String buildResponseBody() {
    var inputs = <String>[];
    try {
      final sent = jsonDecode(lastWrittenBody ?? '') as Map<String, dynamic>?;
      final raw = sent?['input'] as List?;
      if (raw != null) inputs = raw.map((e) => e.toString()).toList();
    } catch (_) {}
    final data = <Map<String, dynamic>>[];
    for (var i = 0; i < inputs.length; i++) {
      final vec = vectorsByText[inputs[i]];
      if (vec != null) {
        data.add({'object': 'embedding', 'index': i, 'embedding': vec});
      }
    }
    return jsonEncode({'object': 'list', 'data': data});
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
    return _MockHttpClientResponse(client.statusCode, client.buildResponseBody());
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
  group('LocalCommandTranslator', () {
    late _MockHttpClient mockClient;
    late LocalCommandTranslator translator;

    setUp(() {
      mockClient = _MockHttpClient();
      translator = LocalCommandTranslator(httpClient: mockClient);
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
      mockClient.vectorsByText.addAll({
        'look screen': [1.0, 0.0, 0.0],
        'take card': [0.0, 1.0, 0.0],
        'push button': [0.0, 0.0, 1.0],
        // User query: examine glowing monitor display -> aligned with look screen
        'examine the glowing monitor display': [0.95, 0.05, 0.0],
      });

      final result = await translator.translate(
        rawInput: 'examine the glowing monitor display',
        commands: [
          makeCmd('look screen'),
          makeCmd('take card'),
          makeCmd('push button'),
        ],
        roomNumber: 2,
      );

      expect(result, isNotNull);
      expect(result!.translatedCommand, equals('look screen'));
      expect(result.originalInput, equals('examine the glowing monitor display'));
      expect(result.isRoomCommandMatch, isTrue);
      expect(result.similarityScore, greaterThan(0.90));
      expect(mockClient.lastRequestedUri.toString(), contains('/v1/embeddings'));
    });

    test('returns null when no candidate meets similarity threshold', () async {
      mockClient.statusCode = 200;
      mockClient.vectorsByText.addAll({
        'look screen': [1.0, 0.0, 0.0],
        'take card': [0.0, 1.0, 0.0],
        // Orthogonal input: "talk to the alien"
        'talk to the alien': [0.0, 0.0, 1.0],
      });

      final result = await translator.translate(
        rawInput: 'talk to the alien',
        commands: [
          makeCmd('look screen'),
          makeCmd('take card'),
        ],
        threshold: 0.75,
        roomNumber: 2,
      );

      expect(result, isNull);
    });

    test('caches repeated candidate embeddings in memory', () async {
      mockClient.statusCode = 200;
      mockClient.vectorsByText.addAll({
        'take card': [1.0, 0.0],
        'grab keycard': [0.99, 0.01],
      });

      final r1 = await translator.translate(
        rawInput: 'grab keycard',
        commands: [makeCmd('take card')],
        roomNumber: 5,
      );
      expect(r1, isNotNull);
      expect(r1!.translatedCommand, equals('take card'));

      // Empty out responses to ensure cache is used
      mockClient.vectorsByText.clear();

      final r2 = await translator.translate(
        rawInput: 'grab keycard',
        commands: [makeCmd('take card')],
        roomNumber: 5,
      );
      expect(r2, isNotNull);
      expect(r2!.translatedCommand, equals('take card'));
    });

    test('deduplicateDictionary embeds multi-word groups and clusters synonyms', () async {
      mockClient.statusCode = 200;
      mockClient.vectorsByText.addAll({
        'look': [1.0, 0.0],
        'see': [0.95, 0.31],
        'examine': [0.92, 0.39],
        'wizard': [0.0, 1.0],
        'ogre': [1.0, 0.0], // orthogonal to wizard
      });

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('see', 2);
      dict.addWord('examine', 2);

      dict.addWord('wizard', 45);
      dict.addWord('ogre', 45);

      dict.addWord('key', 99); // single-word group, should not require embedding

      await translator.deduplicateDictionary(dict);

      expect(dict.isDeduplicated, isTrue);
      // Group 2 preserves preferred words 'look' and 'examine', collapsing 'see'
      expect(dict.idToDeduplicatedWords(2), equals(['look', 'examine']));
      // Group 45 preserved both 'wizard' and 'ogre'
      expect(dict.idToDeduplicatedWords(45), equals(['wizard', 'ogre']));
      // Single-word group unchanged
      expect(dict.idToDeduplicatedWords(99), equals(['key']));
    });

    test('deduplicateDictionary does not freeze vocab when embeddings fail', () async {
      mockClient.statusCode = 500;

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('see', 2);

      await translator.deduplicateDictionary(dict);
      expect(dict.isDeduplicated, isFalse);
    });

    test('matches overloaded candidate phrase back to canonical target command', () async {
      mockClient.statusCode = 200;
      // Command: canonical 'look wizard', with slots: ['look'], ['wizard', 'ogre']
      // Generated phrases: 'look wizard', 'look ogre'
      mockClient.vectorsByText.addAll({
        'look wizard': [1.0, 0.0],
        'look ogre': [0.0, 1.0],
        // User types: "look at the ogre" -> aligns with 'look ogre'
        'look at the ogre': [0.05, 0.95],
      });

      final cmd = makeCmd('look wizard', [
        ['look'],
        ['wizard', 'ogre'],
      ]);

      final result = await translator.translate(
        rawInput: 'look at the ogre',
        commands: [cmd],
        threshold: 0.75,
      );

      expect(result, isNotNull);
      // User matched candidate "look ogre", so translatedCommand is "look ogre"!
      expect(result!.translatedCommand, equals('look ogre'));
      expect(result.similarityScore, greaterThan(0.90));
    });

    test('testConnection returns true for 200 OK and false for error', () async {
      mockClient.statusCode = 200;
      mockClient.vectorsByText['ping'] = [0.1, 0.2, 0.3];

      final okResult = await translator.testConnection();
      expect(okResult.success, isTrue);

      mockClient.statusCode = 500;
      final failResult = await translator.testConnection();
      expect(failResult.success, isFalse);
    });
  });
}
