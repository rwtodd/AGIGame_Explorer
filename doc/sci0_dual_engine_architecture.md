# Dual-engine architecture: AGI + 16-color SCI

How this Flutter app should grow from "AGI interpreter + workbench" into "Sierra 16-color interpreter + workbench" without throwing away the graphics stack, and without pretending AGI and SCI share a VM.

Graphics details: [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md).  
References: [sci0_reference_index.md](sci0_reference_index.md).

## 1. Decision summary

| Decision | Choice | Why |
|---|---|---|
| Engine relationship | **Sibling engines** (`agi` and `sci`) behind a thin session facade | VMs are unrelated; graphics are not |
| Shared code | **Graphics kernel + audio sinks + UI chrome** | Both are 320×200 EGA with 16 depth bands |
| AGI rename | **Not in this phase** | Working AGI must stay green; extract as SCI needs it |
| First SCI title | Police Quest 2 (SCI0 late) | Game data already on disk |
| 16-color SCI scope | SCI0 + SCI01 + SCI1 EGA (QFG2) | Same pic/view model; QFG2 differs in compression/kernel |
| VGA SCI1+ | Out of scope | Bitmap pics, 256-color palettes, point-and-click UI |
| Control vs priority | SCI keeps a **third buffer**; do not pack it into priority | Matches Sierra/ScummVM; slicing stays 16 visual layers |

## 2. What is actually reusable

### Keep and share

| Piece | Today | SCI use |
|---|---|---|
| `EgaColors` | 16-color table + packed RGBA | Identical |
| `PictureSlice` | 320×200 RGBA GPU layer + `toUiImage()` | Identical |
| Impeller compositor | 16 bands, actors bucketed by priority, Y-sort inside a band | Identical algorithm; SCI skips AGI's control-line scan |
| `ViewTextureAtlas` | Pack cels, draw subrects, mirror via negative scaleX | Same; SCI scaleX is ±1 not ±2 |
| CRT shader, 4:3, integer scale, pixel grid | `CrtShaderLoader`, `AgiDisplaySettings` | Same 320×200 viewport |
| Audio sinks | macOS AudioQueue, Windows waveOut | Same PCM out; SCI needs a MIDI/AdLib synth later |
| Launcher chrome | Directory picker, game card, workbench buttons | Detect engine, then show engine-specific browsers |
| Command prompt UI | History, IME later | SCI still types text in SCI0/QFG2 |

### Share the idea, not the code

| Idea | AGI | SCI |
|---|---|---|
| Priority bands from Y | `AgiPriorityTable` (base 48, h=168) | `GfxPorts` table (top 42, 14 bands, h=200) |
| Resource cache | `VolumeManager` + LRU of LOGIC/VIEW/PIC | `RESOURCE.MAP` + LRU of SCRIPT/VIEW/PIC |
| Text parser UI | `WORDS.TOK` + `said()` | VOCAB.000 + Said-spec bytecode |
| Debug inspector | flags/vars/objects | object heap / selectors (later) |

### Do not share

| AGI | SCI | Why |
|---|---|---|
| Logic VM, 256 flags/vars | Stack VM + objects + `callk` | Different languages |
| DIR/VOL + Avis Durgan + 11-bit LZW | MAP/RESOURCE + LZW/Huffman/LZW1 | Different containers |
| `PicVectorInterpreter` 160×168, 2 buffers | SCI pic interpreter 320×200, 3 buffers, dither | Different opcodes/coords |
| VIEW RLE (color in high nibble) | VIEW RLE (color in low nibble) | Inverted nibbles, 16-bit sizes |
| Motion modes wander/follow/move.obj + control 0–3 | Script `Motion` classes + control map 0–15 | Different collision model |
| 20 Hz `LOGIC 0` cycle | Event-driven `doit` / `handleEvent` / `Animate` | Different game loop |
| AGI sound (PC speaker / PCjr 3-voice) | SCI0 MIDI / AdLib | Different resources |

Forcing a common "Sierra VM" would be a lie and would slow both engines down.

## 3. Target tree (incremental, not a big-bang move)

```
lib/
  core/            EGA palette, DisplayProfile, errors, shared helpers
  graphics/        NEW home for PictureSlice, slicer, compositor, atlas, CRT
  audio/           shared sinks; agi_sound_player stays AGI-specific
  ui/              launcher, playfield, dialogs; browsers keyed by engine
  agi/             (later) today's loader / logic / picture / engine / motion
  sci/             NEW, future PRs
```

**This planning phase does not move files.** AGI stays where it is (`lib/loader`, `lib/logic`, `lib/engine`, `lib/picture`, …) until a SCI feature actually needs the extracted type. When that happens, move the type and leave a thin export or updated import — do not rename every `Agi*` class in the same PR.

### DisplayProfile (the one extraction worth doing first)

`AgiDisplay` is hardcoded 160 native + 2× (`lib/core/constants/ega_colors.dart`). Introduce a small immutable profile:

```dart
class DisplayProfile {
  final int nativeWidth;       // AGI 160, SCI 320
  final int nativeHeight;      // AGI 168 playfield, SCI 200
  final int renderedWidth;     // always 320
  final int renderedHeight;    // always 200
  final bool horizontalDouble; // AGI true, SCI false
  final int picPortTop;        // AGI 8 (status), SCI ~10 (menu)
  final int priorityBandCount; // AGI 16 slots 0..15, SCI same slot count
}
```

`PictureSlicer.slice` takes native dimensions and `horizontalDouble` instead of reading `AgiDisplay` constants. AGI tests must stay pixel-identical.

## 4. Session facade (later, small)

Today `GameScreen` / `LauncherScreen` take `AgiGameEngine` and `AgiResourceLoader` concretely. When SCI can boot a room, introduce a narrow interface the UI already almost uses:

```dart
abstract class SierraGameSession {
  DisplayProfile get display;
  Listenable get frameListenable;
  Map<int, PictureSlice>? get pictureSlices;
  List<AgiActorSprite> get actors;          // rename later if needed
  String get statusLine;
  String get promptLine;
  Future<void> tick();
  void handleDirection(int dir);
  void submitCommand(String text);
}
```

AGI implements it with the existing engine. SCI implements it with kernel `Animate` output. The compositor stays engine-agnostic: slices + actor sprites + CRT.

Do **not** put kernel/VM types on this interface.

## 5. Launcher detection

`OnDiskMetaData.fromDirectory` currently throws if it cannot find AGI files. Extend detection:

1. If `RESOURCE.MAP` exists (case-insensitive) → SCI. Read map enough to count views/pics/scripts; show "SCI0" / "SCI1 EGA" once version heuristics exist.
2. Else existing AGI path (`AGIDATA.OVL`, `LOGDIR`, or `*DIR`).
3. Else error: "Not an AGI or SCI game directory."

Workbench buttons:

| AGI | SCI0 |
|---|---|
| Logic, Picture, View, Sound, Objects, Words | Script, Picture, View, Sound, Text, Vocab, Font, Cursor |

Picture and View browsers should be the first SCI UI: they prove the shared compositor. Script disassembly can wait for the VM.

## 6. SCI module sketch (future, not this phase)

```
lib/sci/
  loader/     resource_map.dart, volume.dart, decompressor_lzw.dart, decompressor_huffman.dart
  picture/    sci_pic_interpreter.dart, dither.dart
  view/       sci_view_parser.dart
  domain/     sci_pic.dart (visual + priority + control), sci_view.dart
  engine/     vm, kernel, object heap     // last
  parser/     vocab, said
  sound/      midi                        // after boot
```

`SciPic` holds three `Uint8List`s plus the dithered visual used for slicing. After slice, it can expose the same `Map<int, PictureSlice>` AGI already hands the painter.

## 7. Hard couplings to loosen only when SCI needs them

Documented so a later PR does not have to rediscover them:

| Coupling | File | SCI impact |
|---|---|---|
| `AgiDisplay.nativeWidth = 160` | `lib/core/constants/ega_colors.dart` | Slicer, priority buffer, pens all import this |
| `PriorityBuffer` 160×168 + control-in-band | `lib/domain/priority_buffer.dart` | SCI needs a 320×200 priority **and** a separate control buffer |
| `PictureSlicer` doubles X | `lib/picture/picture_slicer.dart` | Parameterize |
| `AgiPic` owns visual + one priority + slices | `lib/domain/picture.dart` | SCI pic is three maps + slices |
| `AgiViewCel` 8-bit dims, AGI RLE | `lib/domain/agi_view.dart` | SCI 16-bit dims, inverted nibble RLE — new parser, same atlas entry |
| `AgiPicturePainter` imports `AgiPic` / `PriorityBuffer` | `lib/ui/widgets/agi_picture_canvas.dart` | Depend on slices + optional control overlay, not `AgiPic` |
| `GameScreen(AgiGameEngine)` | `lib/ui/screens/game/game_screen.dart` | Session facade |
| `AgiResourceLoader.fromDirectory` | `lib/loader/resource_loader.dart` | Detection fork in launcher, not inside this class |

## 8. Suggested PR order after this planning phase

Each PR independently reviewable; AGI tests green throughout.

1. **`DisplayProfile` + parameterized slicer** — AGI behavior unchanged (golden tests).
2. **SCI `RESOURCE.MAP` + decompress** — unit tests against PQ2 (read-only). No UI.
3. **SCI pic interpreter** — three buffers, dither, slice; pic browser opens PQ2 rooms. Visual / Priority / Control toggles.
4. **SCI view parser + atlas (scaleX 1)** — view browser.
5. **Compositor consumed by both browsers** — extract painter from `AgiPic` if PR 3 still pokes AGI types.
6. **SCI VM skeleton + `DrawPic` / `Animate` / `Parse` stubs** — PQ2 title/boot.
7. **Kernel Animate + ego** — first walkable PQ2 room.
8. **QFG2 compression (`kCompLZW1`) and SCI1-EGA view mapping** — only after PQ2 rooms look right.

Sound, save/load, and a full kernel table are after ego walks.

## 9. Testing policy

Segregate suites by directory so SCI work does not wait on hundreds of AGI room boots. `dart analyze` always. `flutter test` is scoped:

| Change | Command |
|---|---|
| SCI-only (`lib/sci/`, `test/sci/`) | `flutter test test/sci/` |
| AGI-only | `flutter test` (existing tree; `test/sci/` is empty or skipped by path) |
| Shared graphics (`DisplayProfile`, slicer, compositor, atlas, CRT, `EgaColors`) | **both** `flutter test test/sci/` and full AGI `flutter test` |

Placement:

- All new SCI tests go in `test/sci/` from the first file. Never next to `kq2_*` / `sq2_*` under `test/engine/` or `test/loader/`.
- Shared slicer/atlas/compositor tests that feed both 160×168 AGI and 320×200 SCI fixtures belong in `test/graphics/` (or remain in `test/picture/` and count as shared).
- SCI loader/pic/view fixtures come from PQ2 (and later LSL2 source-tree views). Do not check game volumes into git; tests read from `reference_games/` or an env path, same pattern as AGI.
- Graphics goldens: compare sliced PNG dumps against ScummVM / pic-browser output for a handful of PQ2 rooms (day-room, interior, a pic with dither).

This is also recorded in `AGENTS.md` §3 so agents do not default to a full-suite run on every SCI PR.

## 10. What this planning phase does *not* do

- No SCI interpreter, no `lib/sci/` code, no AGI folder move.
- No `reference_docs/` in git.
- No SCI1 VGA.

The committed output of this phase is this document, the graphics note, the reference index, and the `AGENTS.md` pointer at the harvested trees.
