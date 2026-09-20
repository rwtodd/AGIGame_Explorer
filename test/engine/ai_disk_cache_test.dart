import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/engine/ai/ai_disk_cache.dart';
import 'package:flutter_agigame/engine/ai/gemini_command_translator.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:path/path.dart' as p;

class _MockHttpClient implements HttpClient {
  int postCount = 0;
  int batchEmbedCount = 0;
  int embedContentCount = 0;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postCount++;
    final isBatch = url.toString().contains('batchEmbedContents');
    if (isBatch) {
      batchEmbedCount++;
    } else {
      embedContentCount++;
    }
    return _MockHttpClientRequest(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final _MockHttpClient client;
  String? writtenBody;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _MockHttpClientRequest(this.client);

  @override
  void write(Object? obj) {
    writtenBody = obj?.toString();
  }

  @override
  Future<HttpClientResponse> close() async {
    String responseBody = jsonEncode({
      'embedding': {
        'values': [0.95, 0.31]
      }
    });

    if (writtenBody != null && writtenBody!.contains('"requests":')) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(writtenBody!);
        final reqList = parsed['requests'] as List?;
        if (reqList != null) {
          responseBody = jsonEncode({
            'embeddings': [
              for (var i = 0; i < reqList.length; i++)
                {'values': [0.95, 0.31]}
            ]
          });
        }
      } catch (_) {}
    }

    return _MockHttpClientResponse(200, responseBody);
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

class _MockResourceLoader implements AgiResourceLoader {
  final Map<int, AgiLogicScript> logics = {};
  @override
  AgiDictionary dictionary = AgiDictionary();

  @override
  List<int> get presentLogicNumbers => logics.keys.toList()..sort();

  @override
  bool hasLogic(int number) => logics.containsKey(number);

  @override
  AgiLogicScript loadLogic(int number) {
    final script = logics[number];
    if (script == null) throw Exception('Logic $number not found');
    return script;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AiDiskCache Direct Operations', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ai_disk_cache_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('sanitizeModelName strips prefix and cleans illegal characters', () {
      expect(
        AiDiskCache.sanitizeModelName('models/gemini-embedding-001'),
        equals('gemini-embedding-001'),
      );
      expect(
        AiDiskCache.sanitizeModelName('gemini-embedding-001'),
        equals('gemini-embedding-001'),
      );
      expect(
        AiDiskCache.sanitizeModelName('custom:model/v1'),
        equals('custom_model_v1'),
      );
      expect(AiDiskCache.sanitizeModelName(''), equals('default'));
    });

    test('saves and loads deduplicated vocabulary', () async {
      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('examine', 2);
      dict.setDeduplicatedWords(2, ['look']);
      dict.isDeduplicated = true;

      final file = await AiDiskCache.saveVocab(
        directory: tempDir,
        model: 'gemini-embedding-001',
        dictionary: dict,
      );

      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(
        file.path,
        equals(p.join(tempDir.path, 'ai_cache', 'gemini-embedding-001', 'vocab.json')),
      );

      final freshDict = AgiDictionary();
      freshDict.addWord('look', 2);
      freshDict.addWord('examine', 2);

      final loaded = await AiDiskCache.tryLoadVocab(
        directory: tempDir,
        model: 'gemini-embedding-001',
        dictionary: freshDict,
      );

      expect(loaded, isTrue);
      expect(freshDict.isDeduplicated, isTrue);
      expect(freshDict.idToDeduplicatedWords(2), equals(['look']));
    });

    test('loads and migrates legacy ai_vocab_cache.json', () async {
      final legacyFile = File(p.join(tempDir.path, 'ai_vocab_cache.json'));
      legacyFile.writeAsStringSync(jsonEncode({
        'version': 1,
        'groups': {
          '10': ['jump', 'leap'],
        }
      }));

      final dict = AgiDictionary();
      dict.addWord('jump', 10);
      dict.addWord('leap', 10);

      final loaded = await AiDiskCache.tryLoadVocab(
        directory: tempDir,
        model: 'gemini-embedding-001',
        dictionary: dict,
      );

      expect(loaded, isTrue);
      expect(dict.isDeduplicated, isTrue);
      expect(dict.idToDeduplicatedWords(10), equals(['jump', 'leap']));

      // Migrated file should exist
      final migratedFile = File(
        p.join(tempDir.path, 'ai_cache', 'gemini-embedding-001', 'vocab.json'),
      );
      expect(migratedFile.existsSync(), isTrue);
    });

    test('quantizeToInt8Base64 and dequantizeFromInt8Base64 preserve cosine similarity', () {
      final rand = math.Random(42);
      final vec = Float32List(768);
      double sumSq = 0;
      for (var i = 0; i < 768; i++) {
        vec[i] = rand.nextDouble() * 2 - 1;
        sumSq += vec[i] * vec[i];
      }
      final norm = math.sqrt(sumSq);
      for (var i = 0; i < 768; i++) {
        vec[i] /= norm;
      }

      final b64 = AiDiskCache.quantizeToInt8Base64(vec);
      expect(b64.length, equals(1024)); // 768 bytes * 4 / 3 = 1024 base64 chars

      final reconstructed = AiDiskCache.dequantizeFromInt8Base64(b64);
      expect(reconstructed.length, equals(768));

      // Reconstructed vector must be unit-length
      double reconSumSq = 0;
      for (var i = 0; i < 768; i++) {
        reconSumSq += reconstructed[i] * reconstructed[i];
      }
      expect(math.sqrt(reconSumSq), closeTo(1.0, 1e-4));

      // Cosine similarity error must be under 0.005 (similarity > 0.995)
      double dot = 0;
      for (var i = 0; i < 768; i++) {
        dot += vec[i] * reconstructed[i];
      }
      expect(dot, greaterThan(0.995));
    });

    test('saves, loads, and merges per-logic candidate embeddings in gzipped format', () async {
      final vec1 = Float32List.fromList([0.6, 0.8, 0.0]);
      final vec2 = Float32List.fromList([0.0, 1.0, 0.0]);

      // Save initial logic 0 candidates
      final file1 = await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
        embeddings: {'look screen': vec1},
      );

      expect(file1, isNotNull);
      expect(file1!.existsSync(), isTrue);
      expect(file1.path.endsWith('logic_0.json.gz'), isTrue);

      // Verify Gzip header (0x1F, 0x8B)
      final rawBytes = file1.readAsBytesSync();
      expect(rawBytes.length, greaterThan(2));
      expect(rawBytes[0], equals(0x1F));
      expect(rawBytes[1], equals(0x8B));

      // Save additional logic 0 candidates (should merge)
      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
        embeddings: {'take key': vec2},
      );

      // Load back
      final loaded = await AiDiskCache.loadLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
      );

      expect(loaded, isNotNull);
      expect(loaded!.length, equals(2));
      expect(loaded['look screen']![0], closeTo(0.6, 0.01));
      expect(loaded['take key']![1], closeTo(1.0, 0.01));
    });

    test('enforces model directory isolation', () async {
      final vec = Float32List.fromList([1.0, 0.0]);

      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 5,
        embeddings: {'test action': vec},
      );

      // Model A has it
      final loadedA = await AiDiskCache.loadLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 5,
      );
      expect(loadedA, isNotNull);

      // Model B does not have it
      final loadedB = await AiDiskCache.loadLogicCandidates(
        directory: tempDir,
        model: 'other-model-xyz',
        scriptNumber: 5,
      );
      expect(loadedB, isNull);
    });

    test('clearCache removes targeted model or all models', () async {
      final vec = Float32List.fromList([1.0, 0.0]);

      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'model-a',
        scriptNumber: 1,
        embeddings: {'cmd': vec},
      );
      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'model-b',
        scriptNumber: 1,
        embeddings: {'cmd': vec},
      );

      // Clear only model-a
      await AiDiskCache.clearCache(directory: tempDir, model: 'model-a');
      expect(
        await AiDiskCache.loadLogicCandidates(
          directory: tempDir,
          model: 'model-a',
          scriptNumber: 1,
        ),
        isNull,
      );
      expect(
        await AiDiskCache.loadLogicCandidates(
          directory: tempDir,
          model: 'model-b',
          scriptNumber: 1,
        ),
        isNotNull,
      );

      // Clear all
      await AiDiskCache.clearCache(directory: tempDir);
      expect(
        await AiDiskCache.loadLogicCandidates(
          directory: tempDir,
          model: 'model-b',
          scriptNumber: 1,
        ),
        isNull,
      );
    });
  });

  group('AgiGameEngine Disk Cache Integration', () {
    late Directory tempDir;
    late _MockHttpClient mockClient;
    late _MockResourceLoader mockLoader;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ai_engine_cache_test_');
      mockClient = _MockHttpClient();
      mockLoader = _MockResourceLoader();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('prewarmCurrentRoomCandidates loads cached candidates from disk with 0 HTTP calls', () async {
      // 1. Pre-seed disk cache for Logic 0 and Logic 2
      final vec = Float32List.fromList([0.95, 0.31]);
      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
        embeddings: {'look screen': vec},
      );
      await AiDiskCache.saveLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 2,
        embeddings: {'open door': vec},
      );

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('screen', 3);
      dict.addWord('open', 4);
      dict.addWord('door', 5);
      dict.isDeduplicated = true;
      mockLoader.dictionary = dict;

      final translator = GeminiCommandTranslator(httpClient: mockClient);
      final engine = AgiGameEngine(
        dictionary: dict,
        resourceLoader: mockLoader,
      );
      engine.geminiTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.aiApiKey = 'test-key';
      engine.isAiEnabled = true;
      engine.memory.setVar(0, 2); // Current room = 2

      // Prewarm active room candidates
      await engine.prewarmCurrentRoomCandidates();

      // Zero HTTP requests should have been made!
      expect(mockClient.postCount, equals(0));

      // EmbeddingService should now have candidates in memory
      expect(translator.embeddingService.getCached('look screen'), isNotNull);
      expect(translator.embeddingService.getCached('open door'), isNotNull);
    });

Uint8List makeSaidScript(List<int> words) {
  final bytes = <int>[
    0xFF, // IF
    0x0E, // SAID
    words.length,
  ];
  for (final w in words) {
    bytes.add(w & 0xFF);
    bytes.add((w >> 8) & 0xFF);
  }
  bytes.add(0xFF); // End tests
  bytes.add(0); // Then len low
  bytes.add(0); // Then len high
  return Uint8List.fromList(bytes);
}

    test('cold room prewarm fetches embeddings via API and persists them to disk', () async {
      mockLoader.logics[0] = AgiLogicScript(
        logicNumber: 0,
        bytecodes: makeSaidScript([2, 3]), // said("look", "screen")
        messages: const [],
      );
      mockLoader.logics[2] = AgiLogicScript(
        logicNumber: 2,
        bytecodes: makeSaidScript([4, 5]), // said("open", "door")
        messages: const [],
      );

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('screen', 3);
      dict.addWord('open', 4);
      dict.addWord('door', 5);
      dict.isDeduplicated = true;
      mockLoader.dictionary = dict;

      final translator = GeminiCommandTranslator(httpClient: mockClient);
      final engine = AgiGameEngine(
        dictionary: dict,
        resourceLoader: mockLoader,
      );
      engine.geminiTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.aiApiKey = 'test-key';
      engine.memory.setVar(0, 2);
      engine.isAiEnabled = true;

      // Verify no cache on disk before prewarm
      final logic0File = File(
        p.join(tempDir.path, 'ai_cache', 'gemini-embedding-001', 'logic_0.json.gz'),
      );
      final logic2File = File(
        p.join(tempDir.path, 'ai_cache', 'gemini-embedding-001', 'logic_2.json.gz'),
      );
      expect(logic0File.existsSync(), isFalse);
      expect(logic2File.existsSync(), isFalse);

      await engine.prewarmAi();

      // Batch embed was called
      expect(mockClient.batchEmbedCount, greaterThan(0));

      // Files now exist on disk
      expect(logic0File.existsSync(), isTrue);
      expect(logic2File.existsSync(), isTrue);

      final logic0Loaded = await AiDiskCache.loadLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
      );
      expect(logic0Loaded, isNotNull);
      expect(logic0Loaded!.containsKey('look screen'), isTrue);
    });

    test('precomputeAllRoomCaches precomputes all scripts in resourceLoader', () async {
      mockLoader.logics[0] = AgiLogicScript(
        logicNumber: 0,
        bytecodes: makeSaidScript([2, 3]),
        messages: const [],
      );
      mockLoader.logics[1] = AgiLogicScript(
        logicNumber: 1,
        bytecodes: makeSaidScript([4, 5]),
        messages: const [],
      );
      mockLoader.logics[2] = AgiLogicScript(
        logicNumber: 2,
        bytecodes: makeSaidScript([6, 7]),
        messages: const [],
      );

      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('screen', 3);
      dict.addWord('open', 4);
      dict.addWord('door', 5);
      dict.addWord('take', 6);
      dict.addWord('key', 7);
      dict.isDeduplicated = true;
      mockLoader.dictionary = dict;

      final translator = GeminiCommandTranslator(httpClient: mockClient);
      final engine = AgiGameEngine(
        dictionary: dict,
        resourceLoader: mockLoader,
      );
      engine.geminiTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.aiApiKey = 'test-key';
      engine.isAiEnabled = true;

      await engine.prewarmAi();

      final progressed = <int>[];
      await engine.precomputeAllRoomCaches(
        onProgress: (cur, tot, scriptNum) => progressed.add(scriptNum),
      );

      expect(progressed, equals([0, 1, 2]));

      // Verify all 3 cache files exist
      for (final id in [0, 1, 2]) {
        final f = File(
          p.join(tempDir.path, 'ai_cache', 'gemini-embedding-001', 'logic_$id.json.gz'),
        );
        expect(f.existsSync(), isTrue);
      }

      // Calling precompute again makes 0 HTTP calls because files are already cached!
      final priorPosts = mockClient.postCount;
      await engine.precomputeAllRoomCaches();
      expect(mockClient.postCount, equals(priorPosts));
    });

    test('prewarmCurrentRoomCandidates ensures vocab is loaded before candidates are saved', () async {
      // 1. Create vocab.json on disk with deduplicated word
      final dict = AgiDictionary();
      dict.addWord('look', 2);
      dict.addWord('examine', 2);
      dict.addWord('peer', 2);
      dict.setDeduplicatedWords(2, ['look']); // pruned 'examine' and 'peer'
      dict.isDeduplicated = true;
      await AiDiskCache.saveVocab(
        directory: tempDir,
        model: 'gemini-embedding-001',
        dictionary: dict,
      );

      // 2. Set up fresh engine where dict is NOT deduplicated yet
      final freshDict = AgiDictionary();
      freshDict.addWord('look', 2);
      freshDict.addWord('examine', 2);
      freshDict.addWord('peer', 2);
      freshDict.addWord('screen', 3);
      expect(freshDict.isDeduplicated, isFalse);

      mockLoader.dictionary = freshDict;
      mockLoader.logics[0] = AgiLogicScript(
        logicNumber: 0,
        bytecodes: makeSaidScript([2, 3]), // said("look", "screen")
        messages: const [],
      );

      final translator = GeminiCommandTranslator(httpClient: mockClient);
      final engine = AgiGameEngine(
        dictionary: freshDict,
        resourceLoader: mockLoader,
      );
      engine.geminiTranslator = translator;
      engine.gameDirectory = tempDir;
      engine.aiApiKey = 'test-key';
      engine.isAiEnabled = true;
      engine.memory.setVar(0, 0); // room 0

      // Call prewarmCurrentRoomCandidates directly while dict is not deduplicated
      await engine.prewarmCurrentRoomCandidates();

      // Dictionary must now be deduplicated
      expect(freshDict.isDeduplicated, isTrue);

      // Verify logic_0 candidates were loaded into memory
      final cached0 = await AiDiskCache.loadLogicCandidates(
        directory: tempDir,
        model: 'gemini-embedding-001',
        scriptNumber: 0,
      );
      expect(cached0, isNotNull);
      // Because vocab was deduplicated first, only 'look screen' was embedded, NOT 'examine screen' or 'peer screen'
      expect(cached0!.keys.contains('look screen'), isTrue);
      expect(cached0.keys.contains('examine screen'), isFalse);
      expect(cached0.keys.contains('peer screen'), isFalse);
    });
  });
}
