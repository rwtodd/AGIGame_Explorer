# Testing: Reference Game Data Setup

## Overview

The game files used by data-dependent tests are **copyrighted and are never committed**
to this repository. The `reference_games/` and `reference_docs/` directories are
**gitignored**. Copy them verbatim from your own original media (install discs /
floppy image extractions); this document does not list download sources.

Without the game data, data-dependent tests report **SKIPPED** (never silently
passing, never failing) via the helper at `test/support/reference_games.dart`.
Synthetic tests that need no game data always run.

## Game directories referenced by the test suite

Derived from `grep -rhoE "reference_games/[A-Za-z0-9._-]+" test/ | sort -u`.
Engine classification follows `AGENTS.md` §1 (for AGI, the v2/v3 split follows
`lib/loader/game_metadata.dart`: v2 = separate DIR files, v3 = unified `<prefix>DIR`).

| Directory | Game (engine) | Used by (test areas) |
|---|---|---|
| `black-cauldron` | The Black Cauldron (AGI v2) | Engine startup, inventory |
| `codename-iceman` | Codename: ICEMAN (SCI0 late) | SCI set-jump |
| `conquests-of-camelot` | Conquests of Camelot (SCI0 late) | SCI camelot room/dialog |
| `kings-quest-1-agi` | King's Quest 1 (AGI v2) | Engine swimming, room transition |
| `kings-quest-2` | King's Quest 2 (AGI v2) | Engine, loader, picture, UI startup |
| `kings-quest-3` | King's Quest 3 (AGI v2) | Engine rooms/inventory, loader, UI startup |
| `kings-quest-4-agi` | King's Quest 4, AGI release (AGI v3) | Engine rooms/rides, loader, audio, UI startup |
| `kings-quest-4-sci` | King's Quest 4, SCI release (SCI0 early) | SCI KQ4 boot |
| `lsl-2` | Leisure Suit Larry 2 (SCI0 late) | SCI new-room cleanup |
| `police-quest-1` | Police Quest 1 (AGI v2) | Engine ego/room, said extractor |
| `police-quest-2` | Police Quest 2 (SCI0 late) | SCI boot, PIC/VIEW/FONT/CURSOR/script browsers, parser, said, sound, save/load, dialogs, volume |
| `space-quest-1` | Space Quest 1 (AGI v2) | Engine rooms/story, UI keypad/input |
| `space-quest-2` | Space Quest 2 (AGI v2) | Engine rooms/story, UI text compositing |
| `space-quest-3` | Space Quest 3 (SCI0 late) | SCI menu/inventory |

## Expected contents per directory

- **AGI games** (v2 layout): the Sierra DIR/VOL set — `LOGDIR`, `PICDIR`,
  `VIEWDIR`, `SNDDIR`, `VOL.0`–`VOL.n`, plus `WORDS.TOK` and `OBJECT`.
  The AGI v3 install instead uses a combined directory (`KQ4DIR`) with
  `KQ4VOL.0`–`KQ4VOL.n` (and `WORDS.TOK`/`OBJECT`).
- **SCI games**: `RESOURCE.MAP` plus the `RESOURCE.000`–`RESOURCE.n` volume
  files from the original install, plus any patch files the install provides.

Copy files **verbatim** from your original install / floppy image extraction,
keeping the directory names exactly as in the table above.

## Setup steps

1. Create `reference_games/` at the repo root (it is gitignored).
2. Copy each game into `reference_games/<dir-name>/` using the exact directory
   names from the table.
3. Verify the setup with a quick smoke run (with `flutter`/`dart` on your
   PATH, or invoke them from your Flutter SDK's `bin/`):
   - `flutter test test/support/reference_games_test.dart`
   - plus one PQ2 data test, e.g.
     `flutter test test/sci/sci_pic_pq2_test.dart`
4. Scoped / full test commands (from `AGENTS.md` §3):
   - SCI-only: `flutter test test/sci/`
   - AGI-only: `flutter test` (tree under `test/`, excluding `test/sci/`)
   - The full suite needs **all 14 directories**; `test/sci/` needs mainly
     `police-quest-2` plus the other SCI directories in the table.
   - `dart analyze` must stay clean.

## Writing a new data-dependent test

Use the helpers from `test/support/reference_games.dart`:

- At the top of a test / testWidgets body that opens game data:
  `if (skipIfReferenceGameMissing('dir')) return;`
- As a group/test `skip:` argument when the group's `setUp`/`setUpAll` loads
  data for the whole group: `skip: referenceGameSkip('dir')`.
- To let a `setUp` pass through when the data is absent:
  `if (!referenceGameExists('dir')) return;`

Do **not** write a bare `if (!existsSync()) return;` — it silently passes
instead of skipping. Prefer synthetic fixtures (`test/fixtures/`) when the
behaviour under test does not need real game data.
