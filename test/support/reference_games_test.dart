import 'package:flutter_test/flutter_test.dart';

import 'reference_games.dart';

void main() {
  test('path helper and existing-path check pass', () {
    expect(
      referenceGamePath('police-quest-2'),
      equals('reference_games/police-quest-2'),
    );
    expect(skipIfPathMissing('test'), isFalse);
  });

  test('guard with missing game reports as skipped (skipIf* returns true)', () {
    if (skipIfReferenceGameMissing('__definitely_missing_game__')) return;
    fail('unreachable');
  });

  group(
    'group with skip: argument reports as skipped',
    skip: referenceGameSkip('__definitely_missing_game__'),
    () {
      test('body never runs', () {
        fail('unreachable');
      });
    },
  );
}
