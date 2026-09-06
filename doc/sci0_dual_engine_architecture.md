# Dual-engine architecture: AGI + 16-color SCI

How this Flutter app should grow from "AGI interpreter + workbench" into "Sierra 16-color interpreter + workbench" without throwing away the graphics stack, and without pretending AGI and SCI share a VM.

Graphics details: [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md).  
Font & typography architecture: [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md).  
References: [sci0_reference_index.md](sci0_reference_index.md).  
Leftover nits (do not block the next resource type): [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md).

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
| `PlayfieldActorSprite` | Still `AgiActorSprite` with hardcoded `scaleX: 2.0` | Stage 8: `SierraView.pixelScaleX` (AGI 2 / SCI 1), `displaceX`/`displaceY`, elevation `z` |
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
  cursor/     NEXT  sci_cursor_parser + Cursor Browser
  engine/     LATER vm, kernel, object heap
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
| `AgiActorSprite` 160-wide, 2× scale | `lib/ui/widgets/agi_picture_canvas.dart` | **Still coupled.** Stage 8: `PlayfieldActorSprite` + `pixelScaleX`. |
| `AgiPicturePainter` name / AGI types | `lib/ui/widgets/agi_picture_canvas.dart` | **Partial.** Already paints `SierraPicture`. Rename + overlay pass in stage 8. |
| Dialog boxes burn into visual buffer | `lib/ui/screens/game/game_screen.dart` | **Still coupled.** Overlay pass in stage 8; needs FONT metrics (stage 5 parser, kernel later). |
| In-game fonts assume 8×8 monospace | `lib/ui/widgets/agi_picture_canvas.dart` | **Still coupled.** Stage 5 parses `FONT`; overlay draw is stage 8; `TextWidth` is VM. |
| No mouse pointer support | `lib/ui/widgets/game_playfield_widget.dart` | **Still coupled.** Stage 6 parses `CURSOR`; canvas pointer is playfield / stage 8. |
| GameScreen(AgiGameEngine) | `lib/ui/screens/game/game_screen.dart` | **Still coupled.** Session facade when SCI can tick a room (stage 9+). |
| `AgiResourceLoader.fromDirectory` | `lib/loader/resource_loader.dart` | **Done.** Detection fork is in the launcher, not this class. |
| Dither mode hardcoded | `lib/ui/widgets/av_settings_dialog.dart` | **Partial.** Pic Browser has undithered toggle. Global `sciEnableDithering` waits for SCI playfield. |

## 8. Roadmap status (branch `sci0`)

Pattern that has worked and should continue: **parse the resource, put it behind a shared interface, open a diagnostic browser.** Do not wait for the VM. Do not rename every `Agi*` class. Extract (`DisplayProfile`, `SierraPicture`, `SierraView`) when the SCI feature needs it.

Each remaining stage independently reviewable; AGI tests green throughout. SCI-only work is `flutter test test/sci/`. Shared graphics (atlas, compositor, slicer) runs both suites.

| # | Stage | Status |
|---|---|---|
| 1 | `DisplayProfile` + parameterized slicer | **Done.** Pure-Z / 1:1 X via profile; AGI goldens unchanged. |
| 2 | SCI `RESOURCE.MAP` + LZW / Huffman | **Done.** PQ2 volumes in `lib/sci/loader/`. |
| 3 | SCI pic interpreter + Pic Browser | **Done.** Three 320×200 maps, dither / undithered, vector replay. |
| 4 | SCI view parser + atlas + View Browser | **Done.** `kViewEga`, `SierraView`, atlas packs native pixels, `pixelScaleX` 1. |
| 5 | FONT parser + Font Browser | **Done.** Authentic 1-bit glyphs, PQ2 SYSFONT/USERFONT in workbench. |
| 6 | CURSOR parser + Cursor Browser | **Next.** 68-byte `CURSOR`; not the playfield pointer yet. |
| 7 | Launcher detection + workbench | **Done.** Remaining tiles (`onTap`) ship with stages 5, 6, sound, VM. |
| 8 | Compositor: `PlayfieldPainter`, `PlayfieldActorSprite`, window overlay | After 5–6. Actor `scaleX` / displacement; overlay pass (no visual burn-in). |
| 9 | SCI VM skeleton + `DrawPic` / `Animate` / `Parse` stubs | After 8. PQ2 title / boot. Session facade lands here, not earlier. |
| 10 | Kernel Animate + ego motion | After 9. First walkable PQ2 room. |
| 11 | QFG2 `kCompLZW1` + SCI1-EGA view mapping | After PQ2 rooms look right. |
| 12 | Tandy 3-Voice & OPL3 (AdLib FM) | After a walkable room. Existing PCM sinks. |
| 13 | Roland MT-32 via Munt (`libmt32emu`) | Last. FFI + user-provided ROMs. |

### Approach notes on what remains

**Still agree**

- Sibling engines, shared graphics, no shared VM.
- Leave AGI files in place. No `lib/graphics/` or `lib/agi/` move-everything PR.
- Workbench-first for each resource type (pics, views, then fonts, then cursors).
- SCI windows stay an **overlay pass**, never burned into the visual buffer (that would reslice all 16 layers on every keystroke).
- High-res Font 0/1 substitution needs kernel `TextWidth` / `GetLongest`. The Font Browser renders authentic bitmaps. Vector substitution is a video setting once scripts query metrics — see [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md).
- Session facade (`SierraGameSession`) waits until SCI can tick a room. Browsers already fork on `launcherState.isSci`.
- QFG2 compression / EGA mapping after PQ2. VGA remains out of scope.
- Sound after a walkable room; Tandy reuses `PcmSynthesizer`, then OPL3, then Munt.

**Adjusted (learned from pics/views)**

- Old stage 7 (launcher) landed during pics, not after cursors. Keep that: each new parser wires its launcher tile.
- Original stage 5 bundled `FONT` parsing with `SaveBits`/`RestoreBits` overlay. That would stall fonts behind a painter rename. **Split:** stage 5 is parser + Font Browser; overlay is stage 8 (it needs `PlayfieldPainter`, not the FONT file format).
- Same split for cursors: parser + Cursor Browser now; hide-OS-cursor + canvas pointer with the playfield / stage 8.
- `AgiActorSprite.scaleX: 2.0` and the `AgiPicturePainter` rename wait for stage 8. Atlas already packs SCI cels.
- Global `sciEnableDithering` in `AvSettingsDialog` waits for an SCI playfield. Pic Browser already has the undithered toggle.
- Leftover pic nits (duplicate undithered palettes, duplicated opcode walkers, `FE 08`) stay in [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md). Do not insert a cleanup PR before fonts.

## 8.1 Sound architecture & synthesizer roadmap

Unlike AGI's fixed 4-channel PSG chip, SCI0 audio resources (`SOUND`, type 4) are multi-track MIDI sequences with device-specific track mappings and proprietary control loops. The sound subsystem will implement a multi-tiered architecture that renders Linear PCM into the shared `AudioQueueSink` (macOS) and `WaveOutSink` (Windows):

### Tier 1: Tandy 1000 / PCjr 3-Voice (Immediate / Low Effort)
- SCI0 sound resources contain tracks tagged specifically for Tandy/PCjr sound hardware.
- Can be driven directly by reusing the engine's existing `PcmSynthesizer` 3-voice square-wave generator.

### Tier 2: OPL3 / AdLib FM Synthesis (Authentic PC Sound)
- Emulates the Yamaha YMF262 (OPL3) / YM3812 (OPL2) sound chips (e.g. Nuked OPL3 or Woody's OPL).
- Reads Sierra's AdLib instrument patch banks (`PATCH.001` or embedded patch tables in sound resources) to program the 2-operator FM synthesis registers.
- Synthesizes 44.1kHz stereo PCM directly into the shared audio sinks.

### Tier 3: Roland MT-32 Synthesis via Munt / `libmt32emu` (The Definitive Experience)
- The gold standard for Sierra SCI0 adventures: Sierra composers composed the original soundtracks specifically on Roland MT-32 hardware.
- **Implementation**:
  - Bind the open-source `libmt32emu` C++ library via Dart FFI and Native Assets (`dart-setup-ffi-assets`).
  - Minimal C ABI: initialize synth, send MIDI events from the SCI sequencer, render 32kHz (or resampled 44.1kHz/48kHz) stereo 16-bit PCM chunks into `AudioQueueSink`/`WaveOutSink`.
  - Requires user-provided Roland MT-32 ROMs (`MT32_CONTROL.ROM` and `MT32_PCM.ROM`).

### Tier 4: General MIDI & SoundFonts (Optional Modern Alternative)
- Optional playback via platform CoreAudio DLS on macOS or fluidsynth via FFI for SoundFont (.sf2) support.

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
