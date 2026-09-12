# Dual-engine architecture: AGI + 16-color SCI

How this Flutter app should grow from "AGI interpreter + workbench" into "Sierra 16-color interpreter + workbench" without throwing away the graphics stack, and without pretending AGI and SCI share a VM.

Graphics details: [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md).  
Font & typography architecture: [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md).  
References: [sci0_reference_index.md](sci0_reference_index.md).  
Leftover nits (do not block the VM): [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md).

**Progress (branch `sci0`):** stages 1–12 are in. PQ2 boots, plays the intro, parses commands, and draws modal Print/GetInput windows. Next is a **walkable first room** (menu bar, cursor, Graph, ego motion in a real room) — not save/audio/QFG2. See [§8](#8-roadmap-status-branch-sci0).

## 1. Decision summary

| Decision | Choice | Why |
|---|---|---|
| Engine relationship | **Sibling engines** (`agi` and `sci`) behind a thin session facade | VMs are unrelated; graphics are not |
| Shared code | **Graphics kernel + audio sinks + UI chrome** | Both are 320×200 EGA with 16 depth bands |
| AGI rename | **Not in this phase** | Working AGI must stay green; extract as SCI needs it |
| First SCI title | Police Quest 2 (SCI0 late) | `reference_games/police-quest-2/`. Also linked: LSL2/3, SQ3, ICEMAN, Colonel's Bequest, Camelot, KQ4 SCI, QFG1/2. See [sci0_reference_index.md](sci0_reference_index.md). |
| 16-color SCI scope | SCI0 + SCI01 + SCI1 EGA (QFG2) | Same pic/view model; QFG2 differs in compression/kernel |
| VGA SCI1+ | Out of scope | Bitmap pics, 256-color palettes, point-and-click UI |
| Control vs priority | SCI keeps a **third buffer**; do not pack it into priority | Matches Sierra/ScummVM; slicing stays 16 visual layers |
| Window & text rendering | **Overlay pass**, not visual buffer burn-in | Prevents re-slicing all 16 layers on every dialog popup |
| Non-dithered display | **Supported as video setting toggle** | `PictureSlice` stores 32-bit RGBA; undithered 40-color maps directly |

## 2. What is actually reusable

### Keep and share

| Piece | Today | SCI use |
|---|---|---|
| `EgaColors` | 16-color table + packed RGBA | Identical |
| `PictureSlice` | 320×200 RGBA GPU layer + `toUiImage()` | Identical |
| `PictureSlicer` | Slices visual + priority into 16 RGBA maps | Parameterized: `scanControlLines: false`, `horizontalDouble: false` |
| Impeller compositor | 16 bands, actors bucketed by priority, Y-sort inside a band | Identical algorithm; SCI skips AGI's control-line scan |
| `PlayfieldActorSprite` | Parameterized `PlayfieldActorSprite` | **Done in Stage 8:** `SierraView.pixelScaleX` (AGI 2 / SCI 1), `displaceX`/`displaceY`, elevation `z` |
| `ViewTextureAtlas` | Packs `SierraView` cels, shared rects for mirrors | Done; playfield draw still passes AGI `scaleX: 2.0` |
| Custom mouse cursor | Not in AGI (keyboard only) | Hide OS cursor; render 16×16 `CURSOR` or cel sprite on canvas overlay |
| CRT shader, 4:3, integer scale, pixel grid | `CrtShaderLoader`, `AgiDisplaySettings` | Same 320×200 viewport; add `sciEnableDithering` toggle |
| Audio sinks | macOS AudioQueue, Windows waveOut | Same PCM out; shared by Tandy, OPL3, and Munt synthesizers |
| Launcher chrome | Directory picker, game card, workbench buttons | Detect engine, then show engine-specific browsers |
| Command prompt UI | History, IME later | SCI still types text in SCI0/QFG2 |

### Share the idea, not the code

| Idea | AGI | SCI |
|---|---|---|
| Priority bands from Y | `AgiPriorityTable` (base 48, h=168) | `GfxPorts` table (top 42, 14 bands, h=200) |
| Resource cache | `VolumeManager` + LRU of LOGIC/VIEW/PIC | `RESOURCE.MAP` + LRU of SCRIPT/VIEW/PIC |
| Font & Windowing | 8×8 cell text screen buffer (SF Mono) | `FONT` resources + Window ports (rendered as overlay pass; scripts require exact font metrics) |
| Sound synthesizer | SN76489 4-channel PSG (PC Speaker, Tandy) | Multi-tier MIDI synth: Tandy 3-Voice -> OPL3 (AdLib) -> Munt (MT-32) |
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
| AGI sound (fixed 4-channel PSG) | SCI multi-track MIDI sequences | Different resources and synthesis hardware |

Forcing a common "Sierra VM" would be a lie and would slow both engines down.

## 3. Target tree (incremental, not a big-bang move)

```
lib/
  core/            EGA palette, DisplayProfile, errors, shared helpers
  graphics/        NOT CREATED — extract in place; no big-bang move
  audio/           shared sinks; agi_sound_player stays AGI-specific
  ui/              launcher, playfield, dialogs; browsers keyed by engine
  agi/             NOT CREATED — AGI stays in lib/loader, lib/logic, lib/engine, lib/picture
  sci/             loader/, picture/, view/  (font/, cursor/, engine/ still to come)
  domain/          SierraPicture, SierraView  (shared interfaces; Agi* / Sci* implement)
```

AGI stays where it is until a SCI feature actually needs the extracted type. When that happens, introduce an interface in place (`SierraPicture`, `SierraView`, `DisplayProfile`) — do not rename every `Agi*` class in the same PR, and do not invent `lib/graphics/` as a move-everything PR. That approach is what landed pics and views.

### DisplayProfile (done — the one extraction that had to go first)

`AgiDisplay` is hardcoded 160 native + 2× (`lib/core/constants/ega_colors.dart`). Introduce a small immutable profile:

```dart
class DisplayProfile {
  final int nativeWidth;       // AGI 160, SCI 320
  final int nativeHeight;      // AGI 168 playfield, SCI 200
  final int renderedWidth;     // always 320
  final int renderedHeight;    // always 200
  final bool horizontalDouble; // AGI true, SCI false
  final int picPortTop;        // AGI 8 (status), SCI ~10 (standard menu bar)
  final int priorityBandCount; // AGI 16 slots 0..15, SCI same slot count
  final bool scanControlLines; // AGI true (downward scan for < 4), SCI false (pure Z)
}
```

**Port coordinates and framebuffer:**
- In SCI, the full screen buffer is 320×200.
- Normal gameplay rooms sit under a 10px menu bar (rows 0..9), so the picture port (`GfxPort`) is (0, 10) to (320, 200) with a height of 190.
- Title screens and cutscenes (e.g. PQ2 intro) use full-screen ports: (0, 0) to (320, 200).
- `SciPic` buffers are always full 320×200. Vector opcodes draw with port offset `y + portTop`.
- Therefore, all `PictureSlice` textures are 320×200 RGBA, and the Impeller compositor requires no special vertical translation hacks for SCI.

`PictureSlicer.slice` takes `DisplayProfile` (or `horizontalDouble` and `scanControlLines`) instead of hardcoding `AgiDisplay` constants and downward column scans. AGI tests must stay pixel-identical.

## 4. Session facade — done

`SierraGameSession` is implemented by `AgiGameEngine` and `SciGameEngine`. `GameScreen` / `GamePlayfieldWidget` take the session. Do **not** put kernel/VM types on this interface.

The compositor stays engine-agnostic: slices + actor sprites + window overlay + CRT.

**Dialog boxes and windows:**
SCI dialogs, message boxes, and text controls (`kNewWindow`, `kDrawControl`) are drawn using bitmap `FONT` resources (resource type 7). They are rendered as a **top-level overlay pass** on top of the 16 composited slices rather than burning into the visual buffer (which would force an expensive full 16-slice reslice on every keystroke or cursor blink).

## 5. Launcher detection — done

`LauncherNotifier.scanDirectory` forks on `RESOURCE.MAP` (case-insensitive) vs AGI (`AGIDATA.OVL` / `*DIR`). SCI shows resource counts and opens Pic, View, Font, Cursor, and Script browsers.

| AGI | SCI0 |
|---|---|
| Logic, Picture, View, Sound, Objects, Words | Script, Picture, View, Sound, Text, Vocab, Font, Cursor |

## 6. SCI module sketch

Domain types live next to their parser (same as pictures/views), not in a separate `lib/sci/domain/`. Shared interfaces live in `lib/domain/`.

```
lib/sci/
  loader/     DONE  resource_map, volume, decompressor_lzw, decompressor_huffman
  picture/    DONE  sci_pic, sci_pic_canvas, interpreter, step interpreter
  view/       DONE  sci_view, sci_view_parser (kViewEga)
  font/       DONE  sci_font, sci_font_parser + Font Browser
  cursor/     DONE  sci_cursor, sci_cursor_parser + Cursor Browser
  engine/     DONE  vm, kernel, window manager, game session
  parser/     DONE  vocab.000, said heuristic (GNF still later)
  sound/      PARTIAL  kDoSound cues; no PCM sequencer yet
```

`SciPic` holds three `Uint8List`s plus the dithered visual used for slicing, and exposes the same `Map<int, PictureSlice>` the painter already consumes.

## 7. Hard couplings to loosen only when SCI needs them

| Coupling | File | Status |
|---|---|---|
| `AgiDisplay.nativeWidth = 160` | `lib/core/constants/ega_colors.dart` | **Loosened.** `DisplayProfile` parameterizes slicer/pics. AGI pens still import `AgiDisplay`. |
| `PriorityBuffer` 160×168 + control-in-band | `lib/domain/priority_buffer.dart` | **SCI side done.** `SciPic` has separate visual / priority / control. AGI still packs control into priority. |
| `PictureSlicer` doubles X + column scans | `lib/picture/picture_slicer.dart` | **Done.** `horizontalDouble` / `scanControlLines` via `DisplayProfile`. |
| `AgiPic` owns visual + one priority + slices | `lib/domain/picture.dart` | **Loosened.** `SierraPicture`; `SciPic` is three maps + slices. |
| `AgiViewCel` 8-bit dims, AGI RLE | `lib/domain/agi_view.dart` | **Loosened.** `SierraView`; SCI parser is inverted-nibble / 16-bit. Atlas packs both. |
| `AgiActorSprite` 160-wide, 2× scale | `lib/ui/widgets/agi_picture_canvas.dart` | **Done.** `PlayfieldActorSprite` supports `scaleX`, `scaleY`, `displaceX`, `displaceY`, elevation `z`. Backward-compatible typedef. |
| `AgiPicturePainter` name / AGI types | `lib/ui/widgets/agi_picture_canvas.dart` | **Done.** `PlayfieldPainter` with backward-compatible typedef, `sciWindows` overlay pass, and `mouseCursor` overlay pass. |
| Dialog boxes burn into visual buffer | `lib/ui/screens/game/game_screen.dart` | **Done.** `SciWindowOverlay` pass renders on top of composited slices without GPU slice invalidation. |
| In-game fonts assume 8×8 monospace | `lib/ui/widgets/agi_picture_canvas.dart` | **Done.** `SciWindowOverlay` uses `SierraFont` bitmap text rendering. |
| No mouse pointer support | `lib/ui/widgets/game_playfield_widget.dart` | **Done.** Custom in-game Sierra cursor rendering and mouse tracking in `PlayfieldPainter` and `GamePlayfieldWidget`. |
| GameScreen(AgiGameEngine) | `lib/ui/screens/game/game_screen.dart` | **Done.** `GameScreen(SierraGameSession)`. AGI-only menu/inventory paths remain behind `_agiEngine`. |
| `AgiResourceLoader.fromDirectory` | `lib/loader/resource_loader.dart` | **Done.** Detection fork is in the launcher, not this class. |
| Dither mode hardcoded | `lib/ui/widgets/av_settings_dialog.dart` | **Partial.** Toggle exists in settings; nothing reads it yet. See [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md). |

## 8. Roadmap status (branch `sci0`)

Pattern that has worked and should continue: **parse the resource, put it behind a shared interface, open a diagnostic browser.** Do not rename every `Agi*` class. Extract (`DisplayProfile`, `SierraPicture`, `SierraView`) when the SCI feature needs it.

Each remaining stage independently reviewable; AGI tests green throughout. SCI-only work is `flutter test test/sci/`. Shared graphics (atlas, compositor, slicer) runs both suites.

**Why the remaining order changed.** Stages 10–12 landed as a playable *intro* plus parser/dialogs, not as a walkable game. Save, AdLib, QFG2, and MT-32 do not unblock “Sonny walks around the station and types `look locker`.” The next stage is that room. Parser GNF is its own stage because it is large and you need a room to test it. A second SCI0 title (LSL2) sits after PQ2 is a game, so we catch PQ2-shaped assumptions (room-99 speed test, kernel IDs) before QFG2.

| # | Stage | Status | Deliverables / Milestone |
|---|---|---|---|
| 1 | `DisplayProfile` + parameterized slicer | **Done.** | Pure-Z / 1:1 X via profile; AGI goldens unchanged. |
| 2 | SCI `RESOURCE.MAP` + LZW / Huffman | **Done.** | PQ2 volumes in `lib/sci/loader/`. |
| 3 | SCI pic interpreter + Pic Browser | **Done.** | Three 320×200 maps, dither / undithered, vector replay. |
| 4 | SCI view parser + atlas + View Browser | **Done.** | `kViewEga`, `SierraView`, atlas packs native pixels, `pixelScaleX` 1. |
| 5 | FONT parser + Font Browser | **Done.** | Authentic 1-bit glyphs, PQ2 SYSFONT/USERFONT in workbench. |
| 6 | CURSOR parser + Cursor Browser | **Done.** | 68-byte `CURSOR` (type 8), `SierraCursor`, Cursor Browser sandbox. |
| 7 | Launcher detection + workbench | **Done.** | Engine fork; Pic/View/Font/Cursor/Script tiles. |
| 8 | Compositor: painter, sprites, window overlay | **Done.** | Displacement / `z`; overlay windows; cursor overlay. |
| 9 | SCI VM skeleton + PMachine pipeline | **Done.** | 128 opcodes, SegManager, VOCAB.996/997, kernel table, PQ2 boot. |
| 10 | `Animate`, ego motion, `SierraGameSession` | **Done.** | Cast sprites, DrawPic/SetNowSeen/CanBeHere/OnControl, Wait, Bresen, session facade, PQ2 intro. Leftovers: FE 08 bands, portable Wait(0) pump. |
| 11 | Text parser, Said, command prompt | **Done.** | VOCAB.000, kParse/kSaid/kSetSynonyms/kDrawStatus, GetInput loop. Leftovers: menu bar, VOCAB.900 GNF (→ 13 / 14). |
| 12 | Dialog windows, controls, wrapping | **Done.** | NewWindow/DrawControl/EditControl/Display/TextSize, inner port, GlobalToLocal. Leftovers: `|c`/`|f`, GetLongest, Graph, hi-res Font 0/1. |
| 13 | Playable first PQ2 room | **Next.** | Menu bar + status strip, SetCursor, Graph, mouse events, window hit-test, walk a real room, type `look`. |
| 14 | VOCAB.900 GNF Said matcher | Planned. | Port ScummVM `parser/grammar.cpp` + `parser/said.cpp`. Heuristic matcher stays until this lands. |
| 15 | FileIO, save/load, inventory | Planned. | FOpen/FGets, kSaveGame/kRestoreGame, `gInventory showSelf:`. |
| 16 | SCI0 audio (Tandy + OPL3) | Planned. | Hearable `kDoSound`: sequencer into existing PCM sinks. |
| 17 | QFG2 SCI1-EGA | Planned. | LZW1 volumes, `paletteOffset` 8×16, QFG2 boot. After PQ2 is a game. |
| 18 | Roland MT-32 via Munt | Planned. | Native asset + user ROMs. Last audio tier. |
| 19 | Second SCI0 title (LSL2) | Planned. | Portability check: not room 99, not PQ2 script numbers. |
| 20 | Workbench & debug depth | Planned. | Overlay cache/`==`, script send from inspector, Graph debug, `|c`/`|f` if still open. |

---

### 8.1 Detailed roadmap for upcoming stages

#### Stages 10–12 (landed — do not reopen as “next”)

- **10:** `SciGameEngine` ticks `(Game play:)`, `kAnimate` emits sprites, BaseSetter/CanBeHere/OnControl, InitBresen/DoBresen, pic port origin, PQ2 intro. Session facade is live.
- **11:** VOCAB.000, Parse/Said/synonyms, DrawStatus, User.said / GetInput. Menu bar kernels are still stubs.
- **12:** Window manager + overlay controls, wrap, Display on pic port, inner-port chrome. `kGraph` is still a stub.

Nits that are not a stage: [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md).

#### Stage 13: Playable first PQ2 room (**next**)

- **Goal:** Skip or finish the intro, stand in a gameplay room (car / station), walk with arrows, type `look`, see a 10px status/menu strip and a mouse cursor.
- **Why this is next:** Everything else (save, AdLib, QFG2) assumes a room you can occupy. The intro does not prove ego motion, control maps, or menus.
- **Key deliverables:**
  1. **Menu bar + status strip.** `kAddMenu` / `kDrawMenuBar` / `kMenuSelect` / `kGetMenu` / `kSetMenu`. Paint rows 0..9. Gameplay pic port stays `(0, 10)–(320, 200)`.
  2. **Cursor.** `kSetCursor`; `SciGameEngine.showMouseCursor` true; mouse press/release into `kGetEvent`.
  3. **`kGraph`.** Enough of SaveBits/RestoreBits/Fill/Update for Print and in-room redraws (overlay stack, not a 16-slice reslice).
  4. **Hit-testing.** Click DButton / DEdit; `GlobalToLocal` already exists.
  5. **Pic `FE 08` priority bands** if the first room embeds a custom table.
  6. **Portable Wait(0) extra-pump** (not hardcoded room 99) so other SCI0 titles can boot.
  7. **Walk.** DirLoop + DoBresen + CanBeHere on a real control map; ego cycles while moving.
- **Verification:** `test/sci/sci_walkable_room_test.dart` plus a live PQ2 room: Sonny walks, `look` prints the room text, Esc/click opens the menu.

#### Stage 14: VOCAB.900 GNF Said matcher

- **Goal:** `look locker`, `open door<steel`, `look>` then `/key` match Sierra, not the clause heuristic.
- **Deliverables:** Port ScummVM `parseGNF` + `said()`; keep the heuristic only as a fallback behind a flag. Wire `syntaxFail` to real tree failure.
- **Verification:** PQ2 Said goldens from script 33 / station rooms; `look>` no longer steals more specific patterns incorrectly.

#### Stage 15: FileIO, save/load, inventory

- **Goal:** Persistence and `gInventory`.
- **Deliverables:** `FOpen`/`FPuts`/`FGets`/`FClose` on a save directory; `kSaveGame` / `kRestoreGame` / `kGetSaveFiles` / `kCheckSaveGame`; inventory window via existing DIcon/DButton (Tab or menu).
- **Verification:** Save in a room, restore, inventory showSelf.

#### Stage 16: SCI0 audio (Tandy + OPL3)

- **Goal:** Hear PQ2. `kDoSound` already pumps SCI0 cues; this stage is PCM.
- **Deliverables:** SOUND sequencer; Tandy 3-voice via existing `PcmSynthesizer`; AdLib/OPL3 2-op with `PATCH.001`; shared AudioQueue / waveOut sinks.
- **Verification:** Title music and a room sting. MT-32 stays Stage 18.

#### Stage 17: QFG2 SCI1-EGA

- After PQ2 is a game. LZW1 volumes, view `paletteOffset`, QFG2 boot/room.

#### Stage 18: Roland MT-32 (Munt)

- Native asset + user ROMs. Last audio tier.

#### Stage 19: Second SCI0 title (LSL2)

- **Goal:** Prove the engine is not a PQ2 special case.
- **Deliverables:** Boot LSL2, leave its speed-test room (99, same number, different scripts), walk one room, one Said. Note LSL3 uses room 290.
- **Verification:** `test/sci/` LSL2 boot + one walkable room. Do this before spending a stage on QFG2 if PQ2 still has PQ2-only gates.

#### Stage 20: Workbench & debug depth

- Overlay `==` / cache (`toOverlays` every tick).
- Inspector: send selector, dump parse tree, Graph bits.
- `|c` / `|f` / GetLongest if Stage 13 did not need them.
- Hi-res Font 0/1 as a **video setting**, not a blocker. Bitmap metrics stay the script-facing truth unless we close the loop.

---

### Approach notes on what remains

**Still agree**

- Sibling engines, shared graphics, no shared VM.
- Leave AGI files in place. No `lib/graphics/` or `lib/agi/` move-everything PR.
- SCI windows stay an **overlay pass**, never burned into the visual buffer.
- QFG2 compression / EGA mapping follows PQ2 being a game (Stage 17, after 13–16).
- Sound: hearable Tandy/OPL3 (16) before Munt (18).

**Changed**

- Do **not** treat save/load or QFG2 as the next stage. A walkable PQ2 room is the gate.
- Menu bar moved out of Stage 11 leftovers into Stage 13 (it is the 10px gameplay port).
- VOCAB.900 GNF is Stage 14, not a drive-by inside Parse.
- Hi-res Font 0/1 is polish (Stage 20), not a closed-loop blocker for dialogs.
- Add LSL2 (19) as a portability check before SCI1-EGA.

## 9. Testing policy

Segregate suites by directory so SCI work does not wait on hundreds of AGI room boots. `dart analyze` always. `flutter test` is scoped:

| Change | Command |
|---|---|
| SCI-only (`lib/sci/`, `test/sci/`) | `flutter test test/sci/` |
| AGI-only | `flutter test` excluding `test/sci/` (path-scoped, not a tag) |
| Shared graphics (`DisplayProfile`, slicer, compositor, atlas, CRT, `EgaColors`) | **both** `flutter test test/sci/` and full AGI `flutter test` |

Placement:

- All new SCI tests go in `test/sci/` from the first file. Never next to `kq2_*` / `sq2_*` under `test/engine/` or `test/loader/`.
- Shared slicer/atlas/compositor tests that feed both 160×168 AGI and 320×200 SCI fixtures belong in `test/graphics/` (or remain in `test/picture/` and count as shared).
- SCI loader/pic/view/font fixtures come from PQ2 (and later LSL2 source-tree views). Do not check game volumes into git; tests read from `reference_games/police-quest-2/` or an env path, same pattern as AGI.
- Graphics goldens: compare sliced PNG dumps against ScummVM / pic-browser output for a handful of PQ2 rooms (day-room, interior, a pic with dither).

This is also recorded in `AGENTS.md` §3 so agents do not default to a full-suite run on every SCI PR.

## 10. Still out of scope

- No `reference_docs/` in git (harvest stays gitignored).
- No SCI1 VGA (bitmap pics, 256-color palettes, point-and-click).
- No `lib/agi/` or `lib/graphics/` folder shuffle.
- No shared "Sierra VM."
- No QFG2 / SCI1-EGA mapping until PQ2 rooms look right.
