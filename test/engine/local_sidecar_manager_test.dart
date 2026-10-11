import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/ai/local_sidecar_manager.dart';

class _FakeProcess extends SidecarProcess {
  final Completer<int> _exitCompleter = Completer<int>();
  final List<ProcessSignal> killSignals = [];

  @override
  final int pid = 4242;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    return true;
  }
}

class _FakeRunner implements SidecarProcessRunner {
  final List<String> startedArgs = [];
  String? startedExe;
  _FakeProcess? process;

  @override
  Future<SidecarProcess> start(String executable, List<String> arguments) async {
    startedExe = executable;
    startedArgs.addAll(arguments);
    process = _FakeProcess();
    return process!;
  }
}

class _ProbeHttpClient implements HttpClient {
  /// Dims served per probe call; exhausted entries repeat the last value.
  final List<int?> dimsSequence;
  int probeCount = 0;

  _ProbeHttpClient(this.dimsSequence);

  int? get _currentDims => dimsSequence[
      probeCount < dimsSequence.length ? probeCount : dimsSequence.length - 1];

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final dims = _currentDims;
    probeCount++;
    return _ProbeRequest(dims);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeRequest implements HttpClientRequest {
  final int? dims;

  _ProbeRequest(this.dims);

  @override
  HttpHeaders get headers => _ProbeHeaders();

  @override
  void write(Object? obj) {}

  @override
  Future<HttpClientResponse> close() async {
    if (dims == null) return _ProbeResponse(500, '{}');
    return _ProbeResponse(
      200,
      jsonEncode({
        'object': 'list',
        'data': [
          {
            'object': 'embedding',
            'index': 0,
            'embedding': List.filled(dims!, 0.1),
          }
        ],
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProbeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  _ProbeResponse(this.statusCode, this.body);

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
  group('LocalSidecarManager', () {
    late Directory tempDir;
    late File fakeBinary;
    late File fakeWeights;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sidecar_test_');
      fakeBinary = File('${tempDir.path}/llama-server')..createSync();
      fakeWeights = File('${tempDir.path}/model.gguf')..createSync();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    LocalSidecarManager makeManager({
      required _ProbeHttpClient http,
      required _FakeRunner runner,
    }) {
      return LocalSidecarManager(
        httpClient: http,
        processRunner: runner,
        supportDir: Directory('${tempDir.path}/support'),
        binaryPathOverride: fakeBinary.path,
        weightsPathOverride: fakeWeights.path,
      );
    }

    test('adopts an already-running compatible server without spawning', () async {
      final http = _ProbeHttpClient([768]);
      final runner = _FakeRunner();
      final manager = makeManager(http: http, runner: runner);

      final uri = await manager.ensureRunning();

      expect(uri.port, equals(LocalSidecarDefaults.defaultPort));
      expect(manager.ownsServer, isFalse);
      expect(runner.startedExe, isNull);

      // Shutdown must not touch the adopted (user-owned) server.
      await manager.shutdown();
      expect(runner.process, isNull);
    });

    test('spawns the sidecar with --embeddings when nothing is running', () async {
      final http = _ProbeHttpClient([null, 768]);
      final runner = _FakeRunner();
      final manager = makeManager(http: http, runner: runner);

      final uri = await manager.ensureRunning();

      expect(runner.startedExe, equals(fakeBinary.path));
      expect(
        runner.startedArgs,
        containsAll(['--model', fakeWeights.path, '--embeddings']),
      );
      expect(manager.ownsServer, isTrue);
      expect(manager.ownedPid, equals(4242));
      expect(uri.port, equals(LocalSidecarDefaults.defaultPort));
      // Crash-recovery pidfile is recorded.
      expect(File('${tempDir.path}/support/local_ai_server.json').existsSync(), isTrue);
    });

    test('shutdown kills only a spawned server', () async {
      final http = _ProbeHttpClient([null, 768]);
      final runner = _FakeRunner();
      final manager = makeManager(http: http, runner: runner);

      await manager.ensureRunning();
      await manager.shutdown();

      expect(runner.process!.killSignals, contains(ProcessSignal.sigterm));
      expect(manager.ownsServer, isFalse);
      expect(
        File('${tempDir.path}/support/local_ai_server.json').existsSync(),
        isFalse,
      );
    });

    test('moves to a free port when the preferred port serves wrong dims', () async {
      final http = _ProbeHttpClient([128, 128, 768]);
      final runner = _FakeRunner();
      final manager = makeManager(http: http, runner: runner);

      final uri = await manager.ensureRunning();

      expect(uri.port, isNot(equals(LocalSidecarDefaults.defaultPort)));
      expect(runner.startedArgs, contains('${uri.port}'));
      expect(manager.ownsServer, isTrue);
    });

    test('throws SidecarUnavailable when no binary can be resolved', () async {
      final http = _ProbeHttpClient([null]);
      final runner = _FakeRunner();
      final manager = LocalSidecarManager(
        httpClient: http,
        processRunner: runner,
        supportDir: Directory('${tempDir.path}/support'),
        binaryPathOverride: '${tempDir.path}/does-not-exist',
        weightsPathOverride: fakeWeights.path,
        locateOnPath: (_) async => null,
      );

      await expectLater(
        manager.ensureRunning(),
        throwsA(isA<SidecarUnavailable>()),
      );
      expect(runner.startedExe, isNull);
    });
  });
}
