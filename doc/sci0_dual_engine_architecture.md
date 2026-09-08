# Dual-engine architecture: AGI + 16-color SCI

How this Flutter app should grow from "AGI interpreter + workbench" into "Sierra 16-color interpreter + workbench" without throwing away the graphics stack, and without pretending AGI and SCI share a VM.

Graphics details: [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md).  
Font & typography architecture: [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md).  
References: [sci0_reference_index.md](sci0_reference_index.md).  
Leftover nits (do not block the VM): [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md).

**Progress (branch `sci0`):** stages 1–4 and launcher detection are done. Next is FONT (parser + Font Browser), then CURSOR, then compositor decoupling. See [§8](#8-roadmap-status-branch-sci0).

## 1. Decision summary

| Decision | Choice | Why |
|---|---|---|
| Engine relationship | **Sibling engines** (`agi` and `sci`) behind a thin session facade | VMs are unrelated; graphics are not |
| Shared code | **Graphics kernel + audio sinks + UI chrome** | Both are 320×200 EGA with 16 depth bands |
| AGI rename | **Not in this phase** | Working AGI must stay green; extract as SCI needs it |
| First SCI title | Police Quest 2 (SCI0 late) | Game data linked under `reference_games/police-quest-2/` |
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

## 4. Session facade (still later — when SCI can tick a room)

Today `GameScreen` / `LauncherScreen` take `AgiGameEngine` and `AgiResourceLoader` concretely. When SCI can boot a room, introduce a narrow interface the UI already almost uses:

```dart
abstract class SierraGameSession {
  DisplayProfile get display;
  Listenable get frameListenable;
  Map<int, PictureSlice>? get pictureSlices;
  List<PlayfieldActorSprite> get actors;
  String get statusLine;
  String get promptLine;
  Future<void> tick();
  void handleDirection(int dir);
  void submitCommand(String text);
}
```

AGI implements it with the existing engine. SCI implements it with kernel `Animate` output. The compositor stays engine-agnostic: slices + actor sprites + window overlay + CRT.

**Dialog boxes and windows:**
SCI dialogs, message boxes, and text controls (`kNewWindow`, `kDrawControl`) are drawn using bitmap `FONT` resources (resource type 7). They are rendered as a **top-level overlay pass** on top of the 16 composited slices rather than burning into the visual buffer (which would force an expensive full 16-slice reslice on every keystroke or cursor blink).

Do **not** put kernel/VM types on this interface.

## 5. Launcher detection — done

`LauncherNotifier.scanDirectory` forks on `RESOURCE.MAP` (case-insensitive) vs AGI (`AGIDATA.OVL` / `*DIR`). SCI shows resource counts and opens Pic / View browsers. Remaining tiles (Font, Cursor, Sound, Text, Vocab, Script) get `onTap` when that parser exists — not a separate launcher PR.

| AGI | SCI0 |
|---|---|
| Logic, Picture, View, Sound, Objects, Words | Script, Picture, View, Sound, Text, Vocab, Font, Cursor |

Script disassembly still waits for the VM.

## 6. SCI module sketch

Domain types live next to their parser (same as pictures/views), not in a separate `lib/sci/domain/`. Shared interfaces live in `lib/domain/`.

```
lib/sci/
  loader/     DONE  resource_map, volume, decompressor_lzw, decompressor_huffman
  picture/    DONE  sci_pic, sci_pic_canvas, interpreter, step interpreter
  view/       DONE  sci_view, sci_view_parser (kViewEga)
  font/       DONE  sci_font, sci_font_parser + Font Browser
  cursor/     DONE  sci_cursor, sci_cursor_parser + Cursor Browser
  engine/     NEXT  vm, kernel, object heap
  parser/     LATER vocab, said
  sound/      LATER sequencer, tandy, opl3, munt
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
| GameScreen(AgiGameEngine) | `lib/ui/screens/game/game_screen.dart` | **Still coupled.** Session facade when SCI can tick a room (Stage 10). |
| `AgiResourceLoader.fromDirectory` | `lib/loader/resource_loader.dart` | **Done.** Detection fork is in the launcher, not this class. |
| Dither mode hardcoded | `lib/ui/widgets/av_settings_dialog.dart` | **Partial.** Toggle exists in settings; nothing reads it yet. See [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md). |

## 8. Roadmap status (branch `sci0`)

Pattern that has worked and should continue: **parse the resource, put it behind a shared interface, open a diagnostic browser.** Do not wait for the VM. Do not rename every `Agi*` class. Extract (`DisplayProfile`, `SierraPicture`, `SierraView`) when the SCI feature needs it.

Each remaining stage independently reviewable; AGI tests green throughout. SCI-only work is `flutter test test/sci/`. Shared graphics (atlas, compositor, slicer) runs both suites.

| # | Stage | Status | Deliverables / Milestone |
|---|---|---|---|
| 1 | `DisplayProfile` + parameterized slicer | **Done.** | Pure-Z / 1:1 X via profile; AGI goldens unchanged. |
| 2 | SCI `RESOURCE.MAP` + LZW / Huffman | **Done.** | PQ2 volumes in `lib/sci/loader/`. |
| 3 | SCI pic interpreter + Pic Browser | **Done.** | Three 320×200 maps, dither / undithered, vector replay. |
| 4 | SCI view parser + atlas + View Browser | **Done.** | `kViewEga`, `SierraView`, atlas packs native pixels, `pixelScaleX` 1. |
| 5 | FONT parser + Font Browser | **Done.** | Authentic 1-bit glyphs, PQ2 SYSFONT/USERFONT in workbench. |
| 6 | CURSOR parser + Cursor Browser | **Done.** | 68-byte `CURSOR` (type 8), `SierraCursor` domain interface, workbench Cursor Browser with live sandbox. |
| 7 | Launcher detection + workbench | **Done.** | Remaining tiles (`onTap`) ship with stages 5, 6, sound, VM. |
| 8 | Compositor: `PlayfieldPainter`, `PlayfieldActorSprite`, window overlay | **Done.** | Actor `scaleX` / displacement / elevation `z`; `SciWindowOverlay` pass; in-game cursor overlay; `sciEnableDithering` setting. |
| 9 | SCI VM skeleton + PMachine pipeline | **Done.** | PMachine VM (128 opcodes), SegManager, VOCAB.996/997, 0x00..0x71 kernel table, SciVmObserver hooks, PQ2 boot test. |
| 10 | Kernel `Animate`, Ego Motion & Game Session Facade | **Next.** | First walkable PQ2 room! Real-time cast drawing, room lifecycle, input events, barrier collision, `SierraGameSession`. |
| 11 | Text Parser, `Said` Matcher, Command Prompt & Menu Bar | Planned. | `VOCAB.000` tokenizer, `kParse`, `kSaid` bytecode matcher, `kDrawStatus`, interactive text prompt, top menu bar. |
| 12 | Dialog Windows, Text Layout, Controls & Hi-Res Typography | Planned. | `kNewWindow`, `kDisposeWindow`, `kDrawControl`, `kTextWidth`, modal dialog overlays, closed-loop vector Font 0/1. |
| 13 | Save/Load State & Inventory System | Planned. | SCI heap serialization, `kSaveGame`/`kRestoreGame`, item inspection dialogs, Tab inventory browser. |
| 14 | SCI0 Audio Tier 1 & 2 (Tandy 3-Voice & OPL3 FM Synthesis) | Planned. | SCI0 MIDI sequencer, `PcmSynthesizer` Tandy playback, AdLib/OPL3 2-op FM synth, shared PCM sinks. |
| 15 | QFG2 Support (`kCompLZW1` Decompression & SCI1-EGA Views) | Planned. | 1.5-pass LZW1 decompression, `paletteOffset` 8×16 EGA color mapping, QFG2 room exploration. |
| 16 | Roland MT-32 Synthesis via Munt (`libmt32emu`) | Planned. | Native C/C++ asset via Dart Native Assets, user ROM loader, 32kHz studio orchestral playback. |

---

### 8.1 Detailed Roadmap for Upcoming Stages

#### Stage 10: Kernel `Animate`, Ego Motion & Game Session Facade (Active Next Step)
- **Goal**: Render the first walkable room in Police Quest 2 directly in `GameScreen` using `SierraGameSession`.
- **Key Deliverables**:
  1. **Kernel `Animate(cast, cycle)` (`0x0B`)**:
     - Iterates through the `cast` list from `SciSegManager` (`SciList`).
     - Inspects actor properties: `view`, `loop`, `cel`, `x`, `y`, `z`, `priority`, `signal`, `nsTop`, `nsLeft`, `nsBottom`, `nsRight`.
     - Processes Sierra `signal` bitfield flags: `kSignalStopUpdate (0x0001)`, `kSignalViewHidden (0x0008)`, `kSignalFixedPriority (0x0010)`, `kSignalNoUpdate (0x0002)`, `kSignalIgnoreActor (0x4000)`.
     - Maps baseline Y to priority band using the 14-band table (`bands[y]` for Y in 42..190).
     - Updates bounding box extents (`nsTop`, `nsLeft`, `nsBottom`, `nsRight`) on the object (`SetNowSeen`).
     - Emits sorted `PlayfieldActorSprite` instances (`scaleX: 1.0`, `scaleY: 1.0`, `displaceX`, `displaceY`, `z`, priority).
     - Forwards sprite list to `PlayfieldPainter`.
  2. **Room & Picture Lifecycle**:
     - `kDrawPic(picNum, style, clearPic, palette)` (`0x08`): Loads and rasterizes `PICTURE` resources via `SciPicInterpreter`, setting visual, priority, and control buffers.
     - `kPicNotValid` (`0x0A`) and `kShow` (`0x09`): Controls deferral and presentation of newly drawn rooms.
  3. **Collision & Space Testing**:
     - `kOnControl(screen, x, y, x2, y2)` (`0x3E`): Samples control buffer values under points or rectangles.
     - `kCanBeHere(actor, cast)` (`0x3F`) / `kCantBeHere`: Validates actor position against control map barrier lines (`ctlWHITE` / 15) and other non-ignored actors.
  4. **Input Event Translation**:
     - `kGetEvent(mask, eventObj)` (`0x48`): Translates Flutter keyboard inputs (arrow keys, Enter, Esc) and mouse movement/clicks into SCI event object properties (`type`, `message`, `modifiers`).
  5. **Session Facade (`SierraGameSession`)**:
     - Abstract interface uniting `AgiGameEngine` and `SciGameEngine` behind `GameScreen`.
     - `SciGameEngine`: Drives the 60 Hz tick / 20 Hz script cycle:
       1. Polls user events into `kGetEvent`.
       2. Executes `(gGame doit:)` in the VM.
       3. `kAnimate` builds and updates the actor sprite list.
       4. Passes the active `SciPic` and `PlayfieldActorSprite` list to `GamePlayfieldWidget`.
- **Verification**: `test/sci/sci_walkable_room_test.dart` and booting PQ2 into a room where Sonny Bonds walks and animates.

#### Stage 11: Text Parser, `Said` Matcher, Command Prompt & Menu Bar
- **Goal**: Full command-line text input ("look around", "open locker", "talk to marie") and top menu bar navigation.
- **Key Deliverables**:
  1. **`VOCAB.000` Vocabulary Subsystem**:
     - Binary parser for vocabulary word groups, word classes, synonyms, and group IDs.
  2. **Kernel `Parse(inputString, eventObj)` (`0x49`)**:
     - Strips punctuation and noise words.
     - Tokenizes text into word group IDs matching `VOCAB.000`.
     - Identifies unknown words and flags them for the game script's response.
  3. **Kernel `Said(saidSpecPointer)` (`0x4A`)**:
     - Evaluates compiled Sierra `Said` specs (sequence of word group IDs, `ANYWORD` wildcard 1, `ROL` wildcard 9999, operators like `,`, `/`, `&`, `[]`).
     - Matches parsed event tokens against script `Said` expressions.
  4. **Status & Menu Bar**:
     - `kDrawStatus(text)` (`0x1F`): Draws or updates the top status bar (score, sound status, room title).
     - `kAddMenu(title, text)` (`0x24`), `kSetMenu(item, ...)` (`0x25`), `kGetMenu(item, ...)` (`0x26`): Populates and updates standard Sierra pull-down menus.
  5. **UI Integration**:
     - Connects bottom command line in `GameScreen` to `kParse`, providing history and auto-focus.
- **Verification**: `test/sci/sci_parser_test.dart` verifying `VOCAB.000` tokenization and `Said` expression evaluation.

#### Stage 12: Dialog Windows, Text Layout, Controls & Hi-Res Typography
- **Goal**: Authentic modal dialogs, item inspection boxes, input prompt dialogs, and high-resolution typography.
- **Key Deliverables**:
  1. **Window Stack Management**:
     - `kNewWindow(rect, title, type, pri, bg, fg)` (`0x13`): Creates a window record, pushing it to the overlay window stack.
     - `kDisposeWindow(windowHandle)` (`0x16`): Pops and disposes the window.
     - `kDrawControl(controlObj)` (`0x17`), `kHiliteControl(controlObj)` (`0x18`), `kEditControl(controlObj)` (`0x19`): Renders dialog buttons, text controls, and editable fields.
  2. **Text Metrics & Word Wrapping**:
     - `kTextSize(rect, text, font, maxWidth)` (`0x28`): Measures multiline text dimensions for window sizing.
     - `kTextWidth(text, font)`: Character advance width metrics.
  3. **Overlay & Typography Integration**:
     - Connects active windows to `SciWindowOverlay` on `PlayfieldPainter`.
     - Tokenizes embedded format codes: `|c` (color changes) and `|f` (font switching).
     - High-res vector typography substitution for Font 0 and Font 1: closed feedback loop supplying vector metrics to `kTextWidth`/`kTextSize` so scripts construct perfectly proportioned windows without text clipping. Authentic bitmap fallback available via video settings.
- **Verification**: `test/sci/sci_dialog_overlay_test.dart` asserting modal dialog rendering, button bevels, and typography metrics.

#### Stage 13: Save/Load State & Inventory System
- **Goal**: Full game persistence, checkpoint restoration, and inventory management.
- **Key Deliverables**:
  1. **SCI0 Heap State Serialization**:
     - `kSaveGame(desc, slot, version)` (`0x43`): Serializes dynamic SCI0 heap (modified object properties, global variables, script instances, node lists).
     - `kRestoreGame(slot, version)` (`0x44`): Deserializes and restores game state.
     - `kCheckFreeSpace(path)` (`0x45`), `kRestartGame()` (`0x46`).
  2. **Inventory Subsystem**:
     - Standard inventory browser dialog triggered by `(gInventory showSelf:)` or Tab key.
     - Item view cel rendering in `SciIconControl`.
- **Verification**: `test/sci/sci_save_load_test.dart` validating state serialization round-trip.

#### Stage 14: SCI0 Audio Tier 1 & 2 (Tandy 3-Voice & OPL3 FM Synthesis)
- **Goal**: Authentic soundtrack and sound effects playback on macOS and Windows.
- **Key Deliverables**:
  1. **Sound Resource Format & Sequencer**:
     - `SOUND` (type 4) multi-track MIDI format parser.
     - Loop points, priority channels, track markers.
     - `kDoSound` (`0x40`): Sub-ops for `MasterVol`, `SoundOn`, `Restore`, `Init`, `Play`, `Stop`, `Pause`, `Resume`, `Fade`, `CheckDriver`.
  2. **Synthesizers**:
     - **Tier 1 (Tandy 1000 / PCjr 3-Voice)**: Reuses existing `PcmSynthesizer` square wave generator.
     - **Tier 2 (OPL3 / AdLib FM)**: 2-operator Yamaha FM synthesis emulation using Sierra `PATCH.001` instrument banks.
     - Directly streams synthesized 44.1kHz stereo PCM into `AudioQueueSink` (macOS) and `WaveOutSink` (Windows).
- **Verification**: `test/sci/sci_sound_sequencer_test.dart` and live audio playback in PQ2.

#### Stage 15: QFG2 Support (`kCompLZW1` Decompression & SCI1-EGA Views)
- **Goal**: Full support for Quest for Glory 2: Trial by Fire.
- **Key Deliverables**:
  1. **Decompression Algorithm**:
     - 1.5-pass `kCompLZW1` dictionary decompressor for SCI1-EGA volumes.
  2. **Graphics Translation**:
     - SCI1-EGA view decoding with `paletteOffset` 8×16 color translation.
- **Verification**: `test/sci/sci_qfg2_boot_test.dart` verifying QFG2 resource loading, room exploration, and character portraits.

#### Stage 16: Roland MT-32 Synthesis via Munt (`libmt32emu`)
- **Goal**: Studio-quality Roland MT-32 orchestral synthesis.
- **Key Deliverables**:
  1. **Native Integration**:
     - C ABI dynamic library integration using Dart Native Assets (`hook/build.dart`).
     - User-supplied MT-32 ROM loader (`MT32_CONTROL.ROM`, `MT32_PCM.ROM`).
     - Real-time 32kHz stereo PCM rendering into platform audio sinks.
- **Verification**: `test/sci/sci_mt32_synth_test.dart` validating Munt initialization and MIDI stream synthesis.

---

### Approach notes on what remains

**Still agree**

- Sibling engines, shared graphics, no shared VM.
- Leave AGI files in place. No `lib/graphics/` or `lib/agi/` move-everything PR.
- Workbench-first for each resource type (pics, views, fonts, cursors).
- SCI windows stay an **overlay pass**, never burned into the visual buffer.
- High-res Font 0/1 substitution requires the closed-loop metrics feedback in Stage 12.
- Session facade (`SierraGameSession`) connects in Stage 10 when SCI can tick a room.
- QFG2 compression / EGA mapping follows PQ2 completion.
- Sound progression: Tandy 3-Voice & OPL3 first (Stage 14), Munt MT-32 last (Stage 16).

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
