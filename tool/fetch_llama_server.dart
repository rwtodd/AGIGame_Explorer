/// Provides a releasable `llama-server` binary for bundling with the app.
///
/// Strategy:
/// - Default: download a pinned upstream release asset with `--pin bNNNN`.
///   Release archives are self-contained (dylibs/DLLs included with working
///   relative rpaths), which is what makes them safe to bundle — unlike a
///   Homebrew install, whose absolute `/opt/homebrew/opt/...` dylib links
///   would break on machines without Homebrew.
/// - `--local`: reuse a Homebrew `llama-server` whose build is new enough to
///   know the `gemma-embedding2` architecture (>= [_minBuild]). For local
///   smoke-testing only, never for release bundling.
///
/// Usage:
/// ```sh
/// dart tool/fetch_llama_server.dart --pin b11712        # all platforms
/// dart tool/fetch_llama_server.dart --pin b11712 --macos
/// dart tool/fetch_llama_server.dart --local             # dev shortcut
/// ```
///
/// Download integrity: the archive's SHA-256 must match [pinnedArchiveSha256]
/// before extraction. A pin/build with no entry is refused, unless
/// `--allow-unpinned` is passed (then the computed hash is printed so it can
/// be pasted into the pin table).
///
/// Output: `third_party/llama-server/<platform>/llama-server[.exe]`
/// (gitignored). See `tool/bundle_llama_server.dart` and
/// `doc/local_ai_setup.md`.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// First llama.cpp build containing `gemma-embedding2` support (PR #30054).
const int _minBuild = 11454;

/// Pinned SHA-256 digests of upstream release archives, keyed by release
/// tag, then by asset filename.
///
/// To add a pin for a new build: download the asset from the GitHub release
/// (or read the release-asset `digest` via the GitHub API), compute
/// `shasum -a 256 <asset>`, and add one line per asset below.
const Map<String, Map<String, String>> pinnedArchiveSha256 = {
  'b11712': {
    'llama-b11712-bin-macos-arm64.tar.gz':
        'fc2bdadcefee39c6b652707667d22ec8c959eaf7bf143e97a6d30226824852c1',
    'llama-b11712-bin-win-cpu-x64.zip':
        'cc8454164d885e6826a06abd6100aa040b5b5139d527ae49058ec7c449011b68',
  },
};

/// Returns the pinned SHA-256 digest for ([tag], [asset]), or `null` when
/// no pin is recorded for it.
String? expectedArchiveSha256(String tag, String asset) =>
    pinnedArchiveSha256[tag]?[asset];

/// Streams [file] through SHA-256 and returns the lowercase hex digest.
/// The file is never loaded into memory whole: [Hash.bind] chunks the
/// byte stream through the converter.
Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).single;
  return digest.toString();
}

const List<String> _homebrewCandidates = [
  '/opt/homebrew/bin/llama-server',
  '/usr/local/bin/llama-server',
];

Future<void> main(List<String> args) async {
  String? pin;
  var local = false;
  var allowUnpinned = false;
  final filters = <String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--pin' && i + 1 < args.length) {
      pin = args[++i];
    } else if (args[i] == '--local') {
      local = true;
    } else if (args[i] == '--allow-unpinned') {
      allowUnpinned = true;
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

  final outRoot = Directory('third_party/llama-server');
  for (final target in selected) {
    final binaryName = target.startsWith('windows') ? 'llama-server.exe' : 'llama-server';
    // Keep the archive's full layout (bin/ + lib/*.dylib): the server binary
    // is useless without its sibling dynamic libraries.
    final outDir = Directory('${outRoot.path}/$target')..createSync(recursive: true);
    final dest = '${outDir.path}/$binaryName';

    if (local) {
      if (target.startsWith('windows')) {
        stderr.writeln('--local is macOS/Homebrew only; pass --pin bNNNN for Windows.');
        exitCode = 2;
        return;
      }
      final found = await _localBinaryAtLeast(_minBuild);
      if (found == null) {
        stderr.writeln('No Homebrew llama-server >= b$_minBuild; pass --pin bNNNN.');
        exitCode = 2;
        return;
      }
      // Dev shortcut only: copies the binary without its /opt/homebrew
      // dylibs, so the result runs on THIS machine, not in a release bundle.
      await File(found).copy(dest);
      await Process.run('chmod', ['+x', dest]);
      stdout.writeln('Reused local $found -> $dest (dev only, not for release)');
      continue;
    }

    if (pin == null) {
      stderr.writeln('Pass --pin bNNNN (or --local for a dev shortcut on macOS).');
      exitCode = 2;
      return;
    }
    await _downloadReleaseAsset(pin, target, binaryName, outDir.path, dest,
        allowUnpinned: allowUnpinned);
  }
}

/// Returns a local binary path whose build is >= [minBuild], or `null`.
Future<String?> _localBinaryAtLeast(int minBuild) async {
  for (final path in _homebrewCandidates) {
    if (!File(path).existsSync()) continue;
    final build = await _binaryBuild(path);
    if (build != null && build >= minBuild) return path;
    stdout.writeln('Skipping $path (build ${build ?? 'unknown'} < b$minBuild).');
  }
  return null;
}

/// Parses `build NNNNN` from `llama-server --version`.
Future<int?> _binaryBuild(String path) async {
  try {
    final result = await Process.run(path, ['--version']);
    final out = '${result.stdout}${result.stderr}';
    final match = RegExp(r'build (\d+)').firstMatch(out);
    return match == null ? null : int.tryParse(match.group(1)!);
  } catch (_) {
    return null;
  }
}

Future<void> _downloadReleaseAsset(
  String tag,
  String target,
  String binaryName,
  String outDirPath,
  String dest, {
  bool allowUnpinned = false,
}) async {
  final asset = target.startsWith('windows')
      ? 'llama-$tag-bin-win-cpu-x64.zip'
      : 'llama-$tag-bin-macos-arm64.tar.gz';
  final url = Uri.parse(
    'https://github.com/ggml-org/llama.cpp/releases/download/$tag/$asset',
  );
  final tmpRoot = await Directory.systemTemp.createTemp('llama_server_fetch_');
  try {
    final archive = File('${tmpRoot.path}/$asset');
    stdout.writeln('Downloading $url …');
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Download failed: HTTP ${response.statusCode} for $url');
      }
      await response.pipe(archive.openWrite());
    } finally {
      client.close();
    }
    // Integrity check before extraction: refuse an unpinned build unless
    // the maintainer explicitly opted in with --allow-unpinned.
    final expected = expectedArchiveSha256(tag, asset);
    if (expected != null) {
      final actual = await sha256OfFile(archive);
      if (actual != expected) {
        throw StateError(
            'SHA-256 mismatch for $asset: expected $expected, got $actual. '
            'Refusing to extract.');
      }
      stdout.writeln('Verified SHA-256 for $asset.');
    } else if (allowUnpinned) {
      final actual = await sha256OfFile(archive);
      stdout.writeln(
          'WARNING: no pinned SHA-256 for $asset (tag $tag); '
          'proceeding because --allow-unpinned was passed.');
      stdout.writeln('sha256: $actual  $asset');
      stdout.writeln(
          'Paste this digest into pinnedArchiveSha256 in tool/fetch_llama_server.dart.');
    } else {
      throw StateError('No pinned SHA-256 for $asset (tag $tag). '
          'Add its digest to pinnedArchiveSha256 in '
          'tool/fetch_llama_server.dart, or pass --allow-unpinned to '
          'proceed without verification.');
    }
    stdout.writeln('Extracting $asset …');
    final extract = target.startsWith('windows')
        ? await Process.run('unzip', ['-o', archive.path, '-d', tmpRoot.path])
        : await Process.run('tar', ['-xzf', archive.path, '-C', tmpRoot.path]);
    if (extract.exitCode != 0) throw StateError('extract failed: ${extract.stderr}');
    final found = tmpRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('/$binaryName'))
        .toList();
    if (found.isEmpty) throw StateError('$binaryName not found in $asset');
    // Copy the binary plus every sibling dylib/DLL next to it, preserving
    // the archive's relative layout so @rpath / DLL search keeps working.
    final binDir = found.first.parent;
    for (final file in binDir.listSync(recursive: true).whereType<File>()) {
      final relative = file.path.substring(binDir.path.length + 1);
      final target_ = File('$outDirPath/$relative');
      await target_.parent.create(recursive: true);
      await file.copy(target_.path);
    }
    if (!target.startsWith('windows')) {
      await Process.run('chmod', ['+x', dest]);
    }
    stdout.writeln('Ready: $outDirPath/ ($binaryName + sibling libs)');
  } finally {
    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  }
}
