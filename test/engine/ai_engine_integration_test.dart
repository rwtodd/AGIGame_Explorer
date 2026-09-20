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
  bool hasLogic(int number) => logics.containsKey(number);

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
  String? batchEmbedResponse;
  String? embedContentResponse;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final body = url.toString().contains('batchEmbedContents')
        ? (batchEmbedResponse ??
            jsonEncode({
              'embeddings': [
                {
                  'values': [1.0, 0.0]
                }
              ]
            }))
        : (embedContentResponse ??
            jsonEncode({
              'embedding': {
                'values': [0.98, 0.02]
              }
            }));
    return _MockHttpClientRequest(this, body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final _MockHttpClient client;
  final String bodyToSend;
  String? writtenBody;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _MockHttpClientRequest(this.client, this.bodyToSend);

  @override
  void write(Object? obj) {
    writtenBody = obj?.toString();
  }

  @override
  Future<HttpClientResponse> close() async {
    String responseBody = bodyToSend;
    if (writtenBody != null && writtenBody!.contains('"requests":')) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(writtenBody!);
        final reqList = parsed['requests'] as List?;
        if (reqList != null && client.batchEmbedResponse == null) {
          final embs = <Map<String, dynamic>>[];
          for (final req in reqList) {
            final text = req['content']?['parts']?[0]?['text']?.toString().toLowerCase() ?? '';
            if (text.contains('cat')) {
              embs.add({'values': [0.0, 1.0]});
            } else {
              embs.add({'values': [1.0, 0.0]});
            }
          }
          responseBody = jsonEncode({'embeddings': embs});
        }
      } catch (_) {}
    } else if (writtenBody != null && client.embedContentResponse == null) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(writtenBody!);
        final text = parsed['content']?['parts']?[0]?['text']?.toString().toLowerCase() ?? '';
        if (text.contains('cat')) {
          responseBody = jsonEncode({
            'embedding': {'values': [0.0, 1.0]}
          });
        } else {
          responseBody = jsonEncode({
            'embedding': {'values': [1.0, 0.0]}
          });
        }
      } catch (_) {}
    }
    return _MockHttpClientResponse(client.statusCode, responseBody);
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
      expect(engine.lastAiTranslation!.similarityScore, greaterThan(0.9));

      // Verify engine word group IDs are set for [look, screen] -> [10, 100]
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1

      // Verify checkSaid matches
      expect(engine.checkSaid([10, 100]), isTrue);
      expect(engine.memory.getFlag(4), isTrue); // said.accepted = 1
    });

    test('unrelated input below threshold triggers fallback to raw tokenization', () async {
      engine.isAiEnabled = true;
      engine.aiApiKey = 'mock-api-key';
      engine.aiSimilarityThreshold = 0.75;

      // Query vector orthogonal to room commands
      mockClient.embedContentResponse = jsonEncode({
        'embedding': {
          'values': [0.0, 1.0]
        }
      });

      // Submit input that won't match room commands above threshold
      await engine.submitCommand('sing song');

      // AI translation should be null because threshold was not met
      expect(engine.lastAiTranslation, isNull);
      // Engine tokenizes raw input 'sing song'
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1
    });

    test('when AI is disabled, raw input is tokenized directly without translation', () async {
      engine.isAiEnabled = false;

      await engine.submitCommand('look screen');

      expect(engine.lastAiTranslation, isNull);
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.checkSaid([10, 100]), isTrue);
    });

    test('dynamically loaded secondary logic (e.g. NPC overlay) commands are included and matched', () async {
      dictionary.addWord('cat', 200);

      // Overlay logic 104 (cat):
      // if (said(look, cat)) { print("A scruffy black cat looks back at you."); }
      mockLoader.logics[104] = AgiLogicScript(
        logicNumber: 104,
        bytecodes: Uint8List.fromList([
          0xFF,
          0x0E, 0x02, 0x0A, 0x00, 0xC8, 0x00, // said(10, 200) -> look cat
          0xFF, 0x02, 0x00, 0x65, 0x01,
          0x00,
        ]),
        messages: ['A scruffy black cat looks back at you.'],
      );

      // Simulate loading logic 104 into active engine
      engine.loadLogic(104);
      expect(engine.loadedLogicNumbers, contains(104));

      engine.isAiEnabled = true;
      engine.aiApiKey = 'mock-api-key';

      // Submit command targeted at overlay script
      await engine.submitCommand('look cat');

      expect(engine.lastAiTranslation, isNotNull);
      expect(engine.lastAiTranslation!.translatedCommand, equals('look cat'));
      expect(engine.parsedWordIds, equals([10, 200]));
      expect(engine.checkSaid([10, 200]), isTrue);
    });

    test('command starting with colon passes directly to Sierra parser, bypassing AI', () async {
      engine.isAiEnabled = true;
      engine.aiApiKey = 'mock-api-key';

      // Submit input with leading colon (e.g. ":look screen" or ": get clam")
      await engine.submitCommand(':look screen');

      // AI translation should be null because it was completely bypassed
      expect(engine.lastAiTranslation, isNull);
      // Engine tokenized the raw stripped command directly
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.lastSubmittedCommand, equals('look screen'));
      expect(engine.memory.getFlag(2), isTrue); // have.input = 1
      expect(engine.checkSaid([10, 100]), isTrue); // said.accepted = 1
    });

    test('command starting with colon and space strips whitespace before raw parsing', () async {
      engine.isAiEnabled = true;
      engine.aiApiKey = 'mock-api-key';

      await engine.submitCommand(':   look screen  ');

      expect(engine.lastAiTranslation, isNull);
      expect(engine.parsedWordIds, equals([10, 100]));
      expect(engine.lastSubmittedCommand, equals('look screen'));
    });
  });
}
