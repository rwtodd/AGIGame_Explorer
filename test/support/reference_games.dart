import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Helpers for guarding tests against missing reference game data.
///
/// Reference game files under `reference_games/` are never committed to the
/// repository. Tests that need them must report SKIPPED (not silent PASS)
/// when the data is not present. Use [skipIfPathMissing] / [skipIfReferenceGameMissing]
/// at the top of a test body, or [referenceGameSkip] as a `skip:` argument on
/// a group/test.
///
/// NOTE: `markTestSkipped` does NOT abort execution. Callers of `skipIf*`
/// must `return` when the helper returns `true`, e.g.:
///
/// ```dart
/// if (skipIfReferenceGameMissing('kings-quest-2')) return;
/// ```
String referenceGamePath(String gameDirName) => 'reference_games/$gameDirName';

/// Returns true if [gameDirName] exists under `reference_games/`.
bool referenceGameExists(String gameDirName) =>
    Directory(referenceGamePath(gameDirName)).existsSync();

/// If [path] (a directory or file) does not exist, calls [markTestSkipped]
/// with a message pointing to `doc/testing.md` and returns `true`.
/// Otherwise returns `false`.
///
/// The caller must `return` when this returns `true` — [markTestSkipped]
/// only marks the test as skipped; it does not stop the test body from running.
bool skipIfPathMissing(String path) {
  if (Directory(path).existsSync() || File(path).existsSync()) {
    return false;
  }
  markTestSkipped(
    'Required reference game data not found: $path (see doc/testing.md)',
  );
  return true;
}

/// Convenience for [skipIfPathMissing] with a `reference_games/` subdirectory.
bool skipIfReferenceGameMissing(String gameDirName) =>
    skipIfPathMissing(referenceGamePath(gameDirName));

/// Returns `false` if the game exists, otherwise the skip-reason string,
/// for use as a group/test `skip:` argument:
///
/// ```dart
/// group('thing', skip: referenceGameSkip('kings-quest-2'), () { ... });
/// ```
///
/// When the value is a [String], the test framework reports the test as
/// skipped with that reason without running the body. When it is `false`,
/// the body runs normally.
Object referenceGameSkip(String gameDirName) {
  if (referenceGameExists(gameDirName)) {
    return false;
  }
  return 'Required reference game data not found: '
      '${referenceGamePath(gameDirName)} (see doc/testing.md)';
}
