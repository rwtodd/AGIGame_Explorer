import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/ai/ai_vocab_cache.dart';
import 'package:flutter_agigame/engine/ai/local_command_translator.dart';
import 'fake_local_sidecar.dart';
import 'package:path/path.dart' as p;

class _MockHttpClient implements HttpClient {
  int postCount = 0;

  /// Posts carrying real texts (excludes the `ping` health check).
  int embedPostCount = 0;

  String? lastWrittenBody;

  /// Vector served per request input text.
  final Map<String, List<double>> vectorsByText = {
    'look': [1.0, 0.0],
    'examine': [0.95, 0.31],
    'ping': [0.5, 0.5],
  };

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postCount++;
    return _MockRequest(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockRequest implements HttpClientRequest {
  final _MockHttpClient client;

  _MockRequest(this.client);

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  void write(Object? obj) {
    client.lastWrittenBody = obj?.toString();
  }

  @override
  Future<HttpClientResponse> close() async {
    var inputs = <String>[];
    try {
      final sent = jsonDecode(client.lastWrittenBody ?? '') as Map<String, dynamic>?;
      final raw = sent?['input'] as List?;
      if (raw != null) inputs = raw.map((e) => e.toString()).toList();
    } catch (_) {}
    if (inputs.length != 1 || inputs.first != 'ping') {
      client.embedPostCount++;
    }
    return _MockResponse(inputs.map((t) => client.vectorsByText[t] ?? [0.0, 1.0]).toList());
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

class _MockResponse extends Stream<List<int>> implements HttpClientResponse {
  final List<List<double>> vectors;

  _MockResponse(this.vectors);

  @override
  final int statusCode = 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = Stream.value(
      utf8.encode(
        jsonEncode({
          'object': 'list',
          'data': [
            for (var i = 0; i < vectors.length; i++)
              {'object': 'embedding', 'index': i, 'embedding': vectors[i]}
          ]
        }),
      ),
    );
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
  group('AiVocabCache', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ai_vocab_cache_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('saves and loads deduplicated vocabulary to/from disk', () async {
      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('examine', 2);
      dict.addWord('wizard', 45);

      dict.setDeduplicatedWords(2, ['look']);
      dict.setDeduplicatedWords(45, ['wizard']);
      dict.isDeduplicated = true;

      // 1. Save to directory
      final savedFile = await AiVocabCache.saveToDirectory(
        directory: tempDir,
        dictionary: dict,
      );

      expect(savedFile, isNotNull);
      expect(savedFile!.existsSync(), isTrue);
      expect(p.basename(savedFile.path), equals('vocab.json'));

      // 2. Load into a fresh dictionary
      final freshDict = AgiDictionary();
      freshDict.addWord('look', 2);
      freshDict.addWord('examine', 2);
      freshDict.addWord('wizard', 45);
      expect(freshDict.isDeduplicated, isFalse);

      final loaded = await AiVocabCache.tryLoadFromDirectory(
        directory: tempDir,
        dictionary: freshDict,
      );

      expect(loaded, isTrue);
      expect(freshDict.isDeduplicated, isTrue);
      expect(freshDict.idToDeduplicatedWords(2), equals(['look']));
      expect(freshDict.idToDeduplicatedWords(45), equals(['wizard']));
    });

    test('loads and migrates legacy ai_vocab_cache.json from game root', () async {
      // Write a legacy ai_vocab_cache.json at root of tempDir
      final legacyFile = File(p.join(tempDir.path, 'ai_vocab_cache.json'));
      final legacyPayload = jsonEncode({
        'version': 1,
        'groups': {
          '2': ['look'],
          '45': ['wizard'],
        }
      });
      legacyFile.writeAsStringSync(legacyPayload);

      final freshDict = AgiDictionary();
      freshDict.addWord('look', 2);
      freshDict.addWord('examine', 2);
      freshDict.addWord('wizard', 45);

      final loaded = await AiVocabCache.tryLoadFromDirectory(
        directory: tempDir,
        dictionary: freshDict,
      );

      expect(loaded, isTrue);
      expect(freshDict.isDeduplicated, isTrue);
      expect(freshDict.idToDeduplicatedWords(2), equals(['look']));

      // Must have migrated to ai_cache/embeddinggemma-2-text/vocab.json
      final migratedFile = File(
        p.join(tempDir.path, 'ai_cache', 'embeddinggemma-2-text', 'vocab.json'),
      );
      expect(migratedFile.existsSync(), isTrue);
    });

    test('tryLoadFromDirectory returns false when cache file does not exist', () async {
      final dict = AgiDictionary();
      final loaded = await AiVocabCache.tryLoadFromDirectory(
        directory: tempDir,
        dictionary: dict,
      );

      expect(loaded, isFalse);
      expect(dict.isDeduplicated, isFalse);
    });

    test('AgiGameEngine prewarmAi uses existing cache file with zero HTTP requests', () async {
      final mockClient = _MockHttpClient();
      final translator = LocalCommandTranslator(httpClient: mockClient);

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('examine', 2);
      dict.setDeduplicatedWords(2, ['look']);
      dict.isDeduplicated = true;

      // Pre-create cache file in tempDir
      await AiVocabCache.saveToDirectory(
        directory: tempDir,
        dictionary: dict,
      );

      // Now create a new engine instance pointing to tempDir
      final newDict = AgiDictionary();
      newDict.addWord('look', 2);
      newDict.addWord('examine', 2);

      final engine = AgiGameEngine(dictionary: newDict);
      engine.commandTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.sidecarManager = FakeSidecarManager();
      engine.isAiEnabled = true;

      // Wait for prewarm
      await engine.prewarmAi();

      expect(newDict.isDeduplicated, isTrue);
      expect(newDict.idToDeduplicatedWords(2), equals(['look']));
      // No embedding requests should have been made because the cache was on
      // disk (only the sidecar health ping is expected).
      expect(mockClient.embedPostCount, equals(0));
    });

    test('AgiGameEngine prewarmAi deduplicates and saves cache when no cache exists', () async {
      final mockClient = _MockHttpClient();
      final translator = LocalCommandTranslator(httpClient: mockClient);

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('examine', 2);

      final engine = AgiGameEngine(dictionary: dict);
      engine.commandTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.sidecarManager = FakeSidecarManager();
      engine.isAiEnabled = true;

      // Verify no cache file before prewarm
      final cacheFile = File(
        p.join(tempDir.path, 'ai_cache', 'embeddinggemma-2-text', 'vocab.json'),
      );
      expect(cacheFile.existsSync(), isFalse);

      await engine.prewarmAi();

      expect(dict.isDeduplicated, isTrue);
      // HTTP request was made to deduplicate
      expect(mockClient.postCount, greaterThan(0));
      // Cache file must now exist on disk
      expect(cacheFile.existsSync(), isTrue);

      final content = cacheFile.readAsStringSync();
      expect(content, contains('"2"'));
    });
  });
}
