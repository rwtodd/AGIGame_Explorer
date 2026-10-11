/// Fetches `llama-server` binaries for bundling with the app.
///
/// The local-AI sidecar is executed from inside the app bundle (macOS) or
/// from beside the app executable (Windows); under the macOS app sandbox a
/// runtime download cannot be executed, so the binary must be bundled at
/// build time. Weights are NOT bundled here — the app downloads the GGUF
/// on first use (see [LocalSidecarManager]).
///
/// Usage:
/// ```sh
/// dart tool/fetch_llama_server.dart                 # latest release, all platforms
/// dart tool/fetch_llama_server.dart --pin bXXXX     # pinned release
/// dart tool/fetch_llama_server.dart --macos         # macOS arm64 only
/// dart tool/fetch_llama_server.dart --windows       # Windows x64 only
/// ```
///
/// Output: `third_party/llama-server/<platform>/llama-server[.exe]`
/// (gitignored). macOS packaging copies it into
/// `MyApp.app/Contents/Resources/` and re-signs it with
/// `macos/Runner/llama-server.entitlements`; Windows packaging places
/// `llama-server.exe` next to the built `.exe`. See `doc/local_ai_setup.md`.
library;

import 'dart:convert';
import 'dart:io';

const String _releasesApi =
    'https://api.github.com/ggerganov/llama.cpp/releases/latest';

String _assetFor(String tag, String target) {
  final base = target.startsWith('windows')
      ? 'llama-$tag-bin-win-cpu-x64.zip'
      : 'llama-$tag-bin-macos-arm64.zip';
  return base;
}

Future<void> main(List<String> args) async {
  String? pin;
  final filters = <String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--pin' && i + 1 < args.length) {
      pin = args[++i];
    } else if (args[i].startsWith('--')) {
      filters.add(args[i].substring(2));
    }
  }
  const targets = ['macos-arm64', 'windows-x64'];
  final selected =
      targets.where((t) => filters.isEmpty || filters.contains(t.split('-').first)).toList();
  if (selected.isEmpty) {
    stderr.writeln('Unknown platform filter: $filters (want --macos and/or --windows)');
    exitCode = 2;
    return;
  }

  final tag = pin ?? await _latestTag();
  stdout.writeln('Using llama.cpp release $tag');

  final outRoot = Directory('third_party/llama-server');
  final tmpRoot = await Directory.systemTemp.createTemp('llama_server_fetch_');
  try {
    for (final target in selected) {
      final asset = _assetFor(tag, target);
      final url = Uri.parse(
        'https://github.com/ggerganov/llama.cpp/releases/download/$tag/$asset',
      );
      final outDir = Directory('${outRoot.path}/$target')..createSync(recursive: true);
      final zipFile = File('${tmpRoot.path}/$asset');
      stdout.writeln('Downloading $url …');
      await _download(url, zipFile);
      stdout.writeln('Extracting to ${outDir.path} …');
      final unzip = await Process.run('unzip', ['-o', zipFile.path, '-d', tmpRoot.path]);
      if (unzip.exitCode != 0) {
        throw StateError('unzip failed: ${unzip.stderr}');
      }
      final binaryName = target.startsWith('windows') ? 'llama-server.exe' : 'llama-server';
      final found = tmpRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('/$binaryName'))
          .toList();
      if (found.isEmpty) throw StateError('$binaryName not found in $asset');
      await found.first.copy('${outDir.path}/$binaryName');
      if (!target.startsWith('windows')) {
        await Process.run('chmod', ['+x', '${outDir.path}/$binaryName']);
      }
      stdout.writeln('Ready: ${outDir.path}/$binaryName');
    }
  } finally {
    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<String> _latestTag() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_releasesApi));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('GitHub API failed: HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name'] as String?;
    if (tag == null || tag.isEmpty) throw StateError('No tag_name in release response');
    return tag;
  } finally {
    client.close();
  }
}

Future<void> _download(Uri url, File dest) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError('Download failed: HTTP ${response.statusCode} for $url');
    }
    final sink = dest.openWrite();
    await response.pipe(sink);
  } finally {
    client.close();
  }
}
