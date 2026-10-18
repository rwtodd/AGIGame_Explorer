/// Bundles `llama-server` into a built Flutter macOS app (or next to a
/// Windows build) so the sandboxed release app can execute its sidecar.
///
/// Prerequisites: `dart tool/fetch_llama_server.dart --pin bNNNN` (populates
/// `third_party/llama-server/<platform>/` with the server plus sibling libs).
///
/// Usage:
/// ```sh
/// flutter build macos --release
/// dart tool/bundle_llama_server.dart \
///   --app build/macos/Build/Products/Release/flutter_agigame.app
/// ```
///
/// macOS: copies `llama-server` and its sibling `.dylib` files into
/// `<app>/Contents/Resources/` (the binary resolves them via its
/// `@loader_path` rpath, so the flat layout keeps working) and signs every
/// copied file with `macos/Runner/llama-server.entitlements`
/// (`app-sandbox` + `inherit`, which is what allows the sandboxed app to
/// execute its own helper). This is the first location
/// [LocalSidecarManager] checks.
/// Signing identity defaults to ad-hoc (`-`); pass `--sign "<identity>"`
/// for a Developer ID / distribution identity.
///
/// Windows: copies `llama-server.exe` and sibling `.dll` files next to the
/// built app `.exe`:
/// ```sh
/// dart tool/bundle_llama_server.dart --windows \
///   --app build/windows/x64/runner/Release/flutter_agigame.exe
/// ```
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  String? appPath;
  String? sign;
  var windows = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--app' && i + 1 < args.length) {
      appPath = args[++i];
    } else if (args[i] == '--sign' && i + 1 < args.length) {
      sign = args[++i];
    } else if (args[i] == '--windows') {
      windows = true;
    }
  }
  if (appPath == null || appPath.isEmpty) {
    stderr.writeln(
      'Usage: dart tool/bundle_llama_server.dart --app <path> [--sign <id>] [--windows]',
    );
    exitCode = 2;
    return;
  }

  final platformDir = windows ? 'windows-x64' : 'macos-arm64';
  final binaryName = windows ? 'llama-server.exe' : 'llama-server';
  final libPattern = windows ? '.dll' : '.dylib';
  final sourceDir = Directory('third_party/llama-server/$platformDir');
  final source = File('${sourceDir.path}/$binaryName');
  if (!source.existsSync()) {
    stderr.writeln(
      'Missing ${source.path}. Run `dart tool/fetch_llama_server.dart --pin bNNNN` first.',
    );
    exitCode = 2;
    return;
  }
  final libs = sourceDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith(libPattern))
      .toList();

  final String destDirPath;
  if (windows) {
    destDirPath = File(appPath).parent.path;
  } else {
    final resources = Directory('$appPath/Contents/Resources');
    if (!resources.existsSync()) {
      stderr.writeln('Not a macOS app bundle (no Contents/Resources): $appPath');
      exitCode = 2;
      return;
    }
    destDirPath = resources.path;
  }

  final copied = <File>[source, ...libs];
  for (final file in copied) {
    final name = file.path.split('/').last;
    await file.copy('$destDirPath/$name');
  }
  if (!windows) {
    await Process.run('chmod', ['+x', '$destDirPath/$binaryName']);

    final identity = sign ?? '-';
    for (final file in copied) {
      final name = file.path.split('/').last;
      final signResult = await Process.run('codesign', [
        '--force',
        '--sign',
        identity,
        '--entitlements',
        'macos/Runner/llama-server.entitlements',
        '$destDirPath/$name',
      ]);
      if (signResult.exitCode != 0) {
        stderr.writeln('codesign failed for $name: ${signResult.stderr}');
        exitCode = 1;
        return;
      }
    }
    stdout.writeln(
      'Bundled + signed (${identity == '-' ? 'ad-hoc' : identity}): '
      '$binaryName + ${libs.length} libs -> $destDirPath',
    );

    // Adding files invalidates the app seal: re-seal the bundle itself.
    // No --deep, so the helper keeps its own inherit-entitled signature.
    final reseal = await Process.run('codesign', [
      '--force',
      '--sign',
      identity,
      appPath,
    ]);
    if (reseal.exitCode != 0) {
      stderr.writeln('app re-seal failed: ${reseal.stderr}');
      exitCode = 1;
      return;
    }
    stdout.writeln('Re-sealed app bundle: $appPath');

    final verify =
        await Process.run('codesign', ['-d', '--entitlements', '-', '$destDirPath/$binaryName']);
    stdout.writeln(verify.stdout.toString().trim());
  } else {
    stdout.writeln('Copied: $binaryName + ${libs.length} DLLs -> $destDirPath');
  }
}
