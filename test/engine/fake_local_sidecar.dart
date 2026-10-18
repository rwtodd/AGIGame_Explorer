import 'package:flutter_agigame/engine/ai/local_sidecar_manager.dart';

/// Test double for [LocalSidecarManager]: pretends a compatible local
/// embedding server is already reachable, so engine AI flows can be tested
/// against a mocked HTTP provider without spawning a real `llama-server`.
class FakeSidecarManager extends LocalSidecarManager {
  FakeSidecarManager() : super();

  @override
  Future<Uri> ensureRunning({
    void Function(double? progress)? onDownloadProgress,
    void Function(String status)? onStatus,
  }) async =>
      endpoint;
}

/// Test double for [LocalSidecarManager]: always fails, simulating a
/// missing or broken server binary. Engine AI flows must degrade to
/// zero HTTP traffic (native-parser fallback) instead of throwing.
class FailingSidecarManager extends LocalSidecarManager {
  FailingSidecarManager() : super();

  @override
  Future<Uri> ensureRunning({
    void Function(double? progress)? onDownloadProgress,
    void Function(String status)? onStatus,
  }) async {
    throw SidecarUnavailable('no server (test double)');
  }
}
