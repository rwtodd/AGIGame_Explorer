import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Defaults for the app-managed local embedding sidecar (`llama-server`).
class LocalSidecarDefaults {
  /// Hugging Face repo hosting the EmbeddingGemma 2 GGUF weights.
  static const String weightsRepo = 'ggml-org/embeddinggemma-2-GGUF';

  /// Text-only quantized encoder (~270M params); vision `mmproj` files are skipped.
  static const String weightsFile = 'embeddinggemma-2-Q8_0.gguf';

  /// Preferred loopback port for the sidecar.
  static const int defaultPort = 8080;

  /// Expected EmbeddingGemma 2 vector width; used to recognize a compatible server.
  static const int expectedDimensions = 768;

  static Uri weightsDownloadUri(String repo, String file) =>
      Uri.parse('https://huggingface.co/$repo/resolve/main/$file');
}

/// Thrown when the local embedding sidecar cannot be provided.
class SidecarUnavailable implements Exception {
  final String message;
  SidecarUnavailable(this.message);
  @override
  String toString() => 'SidecarUnavailable: $message';
}

/// Minimal process handle abstraction so the manager is unit-testable.
abstract class SidecarProcess {
  int get pid;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Spawns sidecar processes; production implementation wraps `dart:io Process`.
abstract class SidecarProcessRunner {
  Future<SidecarProcess> start(String executable, List<String> arguments);
}

class IoSidecarProcess extends SidecarProcess {
  final Process _process;
  IoSidecarProcess(this._process);
  @override
  int get pid => _process.pid;
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}

class IoSidecarProcessRunner implements SidecarProcessRunner {
  @override
  Future<SidecarProcess> start(String executable, List<String> arguments) async {
    final process = await Process.start(executable, arguments);
    // Drain output so the child never blocks on a full pipe.
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
    return IoSidecarProcess(process);
  }
}

/// Owns the lifecycle of the local `llama-server` embedding sidecar.
///
/// User-friendliness contract:
/// - The user never starts, stops, or configures a server by hand.
/// - An already-running compatible server (e.g. the user's own llama-server
///   serving 768-dim embeddings on our port) is **adopted**, never killed.
/// - Only a server this manager spawned is shut down, on [shutdown].
/// - A stale `local_ai_server.json` pidfile from a crash is adopted when
///   healthy, discarded when not; nothing is ever killed by PID.
class LocalSidecarManager {
  final HttpClient _httpClient;
  final SidecarProcessRunner _processRunner;
  final Directory supportDir;

  String? binaryPathOverride;
  String? weightsPathOverride;
  int port;

  /// PATH lookup for the server binary; injectable for hermetic tests.
  final Future<String?> Function(String name) locateOnPath;

  SidecarProcess? _ownedProcess;
  bool _ownsServer = false;

  LocalSidecarManager({
    HttpClient? httpClient,
    SidecarProcessRunner? processRunner,
    Directory? supportDir,
    this.binaryPathOverride,
    this.weightsPathOverride,
    this.port = LocalSidecarDefaults.defaultPort,
    Future<String?> Function(String name)? locateOnPath,
  })  : _httpClient = httpClient ?? HttpClient(),
        _processRunner = processRunner ?? IoSidecarProcessRunner(),
        supportDir = supportDir ?? defaultSupportDir(),
        locateOnPath = locateOnPath ?? _defaultLocateOnPath;

  static Future<String?> _defaultLocateOnPath(String name) async {
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(locator, [name]);
      if (result.exitCode == 0) {
        final first = (result.stdout as String).split('\n').first.trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    return null;
  }

  /// Whether this manager spawned the current server (and may shut it down).
  bool get ownsServer => _ownsServer;

  /// PID of the spawned server, when owned.
  int? get ownedPid => _ownedProcess?.pid;

  /// Active endpoint (owned or adopted).
  Uri get endpoint => Uri.parse('http://127.0.0.1:$port');

  /// Platform config directory, mirroring settings storage.
  static Directory defaultSupportDir() {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.config/flutter_agigame');
      }
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData/flutter_agigame');
      }
    }
    return Directory('.flutter_agigame');
  }

  File get _pidFile => File('${supportDir.path}/local_ai_server.json');

  /// Ensures a compatible embedding server is reachable, spawning our own
  /// sidecar when needed. Returns the live endpoint.
  ///
  /// [onDownloadProgress] receives 0.0–1.0 while fetching weights (`null`
  /// when the size is unknown); [onStatus] receives human-readable steps
  /// for settings UI.
  Future<Uri> ensureRunning({
    void Function(double? progress)? onDownloadProgress,
    void Function(String status)? onStatus,
  }) async {
    if (_ownedProcess != null) {
      return endpoint;
    }

    // 1. Adopt anything already serving compatible embeddings here.
    final existingDims = await _probeEmbeddingDims(endpoint);
    if (existingDims == LocalSidecarDefaults.expectedDimensions) {
      _ownsServer = false;
      debugPrint('[LocalSidecar] Adopted existing server at $endpoint');
      return endpoint;
    }

    // 2. Resolve the server binary.
    onStatus?.call('Locating local AI server…');
    final binary = await _resolveBinary();
    if (binary == null) {
      throw SidecarUnavailable(
        'llama-server not found. Install llama.cpp (https://github.com/ggerganov/llama.cpp/releases) '
        'or place llama-server next to the app.',
      );
    }

    // 3. Ensure weights are on disk.
    onStatus?.call('Checking embedding model…');
    final weights = await _ensureWeights(onDownloadProgress, onStatus);

    // 4. If the preferred port is taken by something incompatible, move aside.
    if (existingDims != null) {
      port = await _findFreePort();
      debugPrint('[LocalSidecar] Port in use by incompatible server; using $port');
    }

    // 5. Spawn and wait for readiness.
    onStatus?.call('Starting local AI server…');
    final args = ['--model', weights, '--port', '$port', '--embeddings'];
    try {
      _ownedProcess = await _processRunner.start(binary, args);
    } catch (e) {
      throw SidecarUnavailable('Failed to launch $binary: $e');
    }
    _ownsServer = true;

    final ready = await _waitForReady(
      onStatus: onStatus,
      timeout: const Duration(seconds: 120),
    );
    if (!ready) {
      await shutdown();
      throw SidecarUnavailable('Local AI server did not become ready in time.');
    }

    _writePidFile();
    debugPrint('[LocalSidecar] Spawned server pid=${_ownedProcess?.pid} at $endpoint');
    return endpoint;
  }

  /// Shuts down the sidecar **only if this manager spawned it**.
  /// Adopted (user-owned) servers are left running.
  Future<void> shutdown() async {
    final owned = _ownedProcess;
    _ownedProcess = null;
    _ownsServer = false;
    try {
      if (_pidFile.existsSync()) _pidFile.deleteSync();
    } catch (_) {}
    if (owned == null) return;
    try {
      owned.kill();
      await owned.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        owned.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  /// Returns embedding dims when [base] serves OpenAI-compatible embeddings,
  /// `null` when unreachable or incompatible.
  Future<int?> _probeEmbeddingDims(Uri base) async {
    try {
      final request = await _httpClient
          .postUrl(base.resolve('/v1/embeddings'))
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode({
        'model': 'probe',
        'input': ['ping'],
      }));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>?;
      final data = json?['data'] as List?;
      if (data == null || data.isEmpty) return null;
      final values = (data.first as Map<String, dynamic>?)?['embedding'] as List?;
      return values?.length;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForReady({
    void Function(String status)? onStatus,
    required Duration timeout,
  }) async {
    // Liveness latch: set when our child exits (bind failure or crash).
    var exited = false;
    final owned = _ownedProcess;
    if (owned != null) {
      unawaited(owned.exitCode.then((_) => exited = true));
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (owned != null && exited) {
        debugPrint('[LocalSidecar] server process exited during startup');
        _ownedProcess = null;
        _ownsServer = false;
        return false;
      }
      final dims = await _probeEmbeddingDims(endpoint);
      if (dims == LocalSidecarDefaults.expectedDimensions) return true;
      onStatus?.call('Loading embedding model…');
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<String?> _resolveBinary() async {
    if (binaryPathOverride != null && File(binaryPathOverride!).existsSync()) {
      return binaryPathOverride;
    }
    for (final candidate in _bundledCandidates()) {
      if (File(candidate).existsSync()) return candidate;
    }
    return _findOnPath(Platform.isWindows ? 'llama-server.exe' : 'llama-server');
  }

  /// Bundled-server locations: beside/inside the app bundle per platform.
  List<String> _bundledCandidates() {
    final candidates = <String>[];
    try {
      final exe = Platform.resolvedExecutable;
      final dir = File(exe).parent.path;
      if (Platform.isMacOS) {
        // .../MyApp.app/Contents/MacOS/MyApp -> .../Contents/Resources/
        final resources = '$dir/../Resources';
        candidates.add('$resources/llama-server');
        candidates.add('$dir/llama-server');
      } else if (Platform.isWindows) {
        candidates.add('$dir\\llama-server.exe');
      } else {
        candidates.add('$dir/llama-server');
      }
    } catch (_) {}
    return candidates;
  }

  Future<String?> _findOnPath(String name) => locateOnPath(name);

  Future<String> _ensureWeights(
    void Function(double? progress)? onDownloadProgress,
    void Function(String status)? onStatus,
  ) async {
    if (weightsPathOverride != null) return weightsPathOverride!;
    final file = File(
      '${supportDir.path}/models/${LocalSidecarDefaults.weightsFile}',
    );
    if (file.existsSync()) return file.path;

    onStatus?.call('Downloading embedding model (one-time)…');
    final uri = LocalSidecarDefaults.weightsDownloadUri(
      LocalSidecarDefaults.weightsRepo,
      LocalSidecarDefaults.weightsFile,
    );
    try {
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw SidecarUnavailable(
          'Model download failed: HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength;
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.part');
      var received = 0;
      final sink = tmp.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onDownloadProgress?.call(total > 0 ? received / total : null);
      }
      await sink.close();
      await tmp.rename(file.path);
      onDownloadProgress?.call(1.0);
      return file.path;
    } catch (e) {
      if (e is SidecarUnavailable) rethrow;
      throw SidecarUnavailable('Model download failed: $e');
    }
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = socket.port;
    await socket.close();
    return freePort;
  }

  void _writePidFile() {
    try {
      if (!supportDir.existsSync()) supportDir.createSync(recursive: true);
      _pidFile.writeAsStringSync(jsonEncode({
        'pid': _ownedProcess?.pid,
        'port': port,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('[LocalSidecar] Failed to write pidfile: $e');
    }
  }
}
