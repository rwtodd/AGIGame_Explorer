import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/ai/gemini_command_translator.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

class _MockResourceLoader implements AgiResourceLoader {
  final Map<int, AgiLogicScript> logics = {};
  @override
  late AgiDictionary dictionary;

  @override
  AgiLogicScript loadLogic(int number) {
    final s = logics[number];
    if (s == null) {
      throw ResourceNotPresentException('Logic $number not found');
    }
    return s;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClient implements HttpClient {
  int statusCode = 200;
  String responseBody = '';

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _MockHttpClientRequest(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final _MockHttpClient client;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _MockHttpClientRequest(this.client);

  @override
  void write(Object? obj) {}

  @override
  Future<HttpClientResponse> close() async =>
      _MockHttpClientResponse(client.statusCode, client.responseBody);

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
  group('AgiGameEngine AI Translation Integration', () {
    late AgiDictionary dictionary;
    late _MockResourceLoader mockLoader;
    late _MockHttpClient mockClient;
    late AgiGameEngine engine;

    setUp(() {
      dictionary = AgiDictionary();
      dictionary.addWord('look', 10);
      dictionary.addWord('screen', 100);
      dictionary.addWord('terminal', 100);
      dictionary.addWord('card', 101);
      dictionary.addWord('take', 20);

      mockLoader = _MockResourceLoader();
      mockLoader.dictionary = dictionary;

      // Room 2 logic:
      // if (said(look, screen)) { print("The computer display shows reactor status."); }
      mockLoader.logics[2] = AgiLogicScript(
        logicNumber: 2,
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0x64, 0x00, // said(10, 100) -> look screen
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0x00,
        ]),
        messages: ['The computer display shows reactor status.'],
      );

      mockClient = _MockHttpClient();
      mockClient.statusCode = 200;
      mockClient.responseBody = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'look screen'}
              ]
            }
          }
        ]
      });

      engine = AgiGameEngine(
        dictionary: dictionary,
        resourceLoader: mockLoader,
      );

      engine.geminiTranslator = GeminiCommandTranslator(httpClient: mockClient);
      engine.memory.setVar(0, 2); // %v0: current_room = 2
    });

    test('natural input is translated via AI and matches said() test in AGI script', () async {
      // Configure AI assist
      engine.isAiEnabled = true;
      engine.aiApiKey = 'mock-api-key';

      // Submit natural language input
      await engine.submitCommand('can you please examine the terminal monitor');

      // Verify AI translation metadata was set
      expect(engine.lastAiTranslation, isNotNull);
      expect(engine.lastAiTranslation!.originalInput, equals('can you please examine the terminal monitor'));
      expect(engine.lastAiTranslation!.translatedCommand, equals('look screen'));

      // Verify engine word group IDs are set for [look, screen] -> [10, 100]
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1

      // Verify checkSaid matches
      expect(engine.checkSaid([10, 100]), isTrue);
      expect(engine.memory.getFlag(4), isTrue); // said.accepted = 1
    });

    test('when AI is disabled, raw input is tokenized directly without translation', () async {
      engine.isAiEnabled = false;

      engine.submitCommand('look screen');

      expect(engine.lastAiTranslation, isNull);
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.checkSaid([10, 100]), isTrue);
    });
  });
}
