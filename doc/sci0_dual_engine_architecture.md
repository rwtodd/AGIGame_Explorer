# Dual-engine architecture: AGI + 16-color SCI

How this Flutter app should grow from "AGI interpreter + workbench" into "Sierra 16-color interpreter + workbench" without throwing away the graphics stack, and without pretending AGI and SCI share a VM.

Graphics details: [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md).  
Font & typography architecture: [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md).  
References: [sci0_reference_index.md](sci0_reference_index.md).

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
| `PlayfieldActorSprite` | Actor sprite descriptor (`AgiActorSprite`) | Generalize for `scaleX: 1.0`, `displaceX`/`displaceY`, and elevation `z` |
| `ViewTextureAtlas` | Pack cels, draw subrects, mirror via negative scaleX | Same; SCI scaleX is ±1 not ±2 |
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

## 4. Session facade (later, small)

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
  font/       sci_font_parser.dart
  cursor/     sci_cursor_parser.dart
  domain/     sci_pic.dart (visual + priority + control), sci_view.dart, sci_font.dart, sci_cursor.dart
  engine/     vm, kernel, object heap     // last
  parser/     vocab, said
  sound/      sci_sound_sequencer.dart, tandy_driver.dart, opl3_driver.dart, munt_mt32_driver.dart
```

`SciPic` holds three `Uint8List`s plus the dithered visual used for slicing. After slice, it can expose the same `Map<int, PictureSlice>` AGI already hands the painter.

## 7. Hard couplings to loosen only when SCI needs them

Documented so a later PR does not have to rediscover them:

| Coupling | File | SCI impact |
|---|---|---|
| `AgiDisplay.nativeWidth = 160` | `lib/core/constants/ega_colors.dart` | Slicer, priority buffer, pens all import this |
| `PriorityBuffer` 160×168 + control-in-band | `lib/domain/priority_buffer.dart` | SCI needs a 320×200 priority **and** a separate control buffer |
| `PictureSlicer` doubles X + column scans | `lib/picture/picture_slicer.dart` | Parameterize: `horizontalDouble: false`, `scanControlLines: false` |
| `AgiPic` owns visual + one priority + slices | `lib/domain/picture.dart` | SCI pic is three maps + slices |
| `AgiViewCel` 8-bit dims, AGI RLE | `lib/domain/agi_view.dart` | SCI 16-bit dims, inverted nibble RLE — new parser, same atlas entry |
| `AgiActorSprite` 160-wide, 2× scale | `lib/ui/widgets/agi_picture_canvas.dart` | Generalize to `PlayfieldActorSprite` with scaleX 1.0, `displaceX`/`displaceY`, and `z` elevation |
| `AgiPicturePainter` imports `AgiPic` / `PriorityBuffer` | `lib/ui/widgets/agi_picture_canvas.dart` | Decouple to `PlayfieldPainter` depending on slices + overlay pass + diagnostic images |
| Dialog boxes burn into visual buffer | `lib/ui/screens/game/game_screen.dart` | Render active windows as an overlay pass on top of slices, avoiding 16-slice reslicing |
| In-game fonts assume 8×8 monospace | `lib/ui/widgets/agi_picture_canvas.dart` | SCI scripts calculate window sizes via `TextWidth`; render native `FONT` glyphs on overlay |
| No mouse pointer support | `lib/ui/widgets/game_playfield_widget.dart` | Hide OS cursor on viewport hover; render 16×16 `CURSOR` or cel sprite on canvas overlay |
| GameScreen(AgiGameEngine) | `lib/ui/screens/game/game_screen.dart` | Session facade |
| `AgiResourceLoader.fromDirectory` | `lib/loader/resource_loader.dart` | Detection fork in launcher, not inside this class |
| Dither mode hardcoded | `lib/ui/widgets/av_settings_dialog.dart` | Add `sciEnableDithering` toggle in video settings for undithered 40-color display |

## 8. Suggested PR order after this planning phase

Each PR independently reviewable; AGI tests green throughout.

1. **`DisplayProfile` + parameterized slicer** — pure-Z direct lookup (`scanControlLines: false`), 1:1 X (`horizontalDouble: false`). AGI behavior unchanged (golden tests).
2. **SCI `RESOURCE.MAP` + decompress** — `kCompLZW` and `kCompHuffman` with unit tests against `reference_games/police-quest-2/` (read-only). No UI.
3. **SCI pic interpreter & Pic Browser** — three 320×200 buffers, dither palettes (`0xFE 0x01`), port-relative coords, authentic EGA dither + undithered (40-color) mode, Pic Browser with Visual / Priority / Control / Undithered toggles.
4. **SCI view parser + atlas (scaleX 1)** — `kViewEga` (low-nibble color, 16-bit dims, displacement), `ViewTextureAtlas` (`scaleX: 1.0`), View Browser.
5. **SCI font parser & window overlay** — `FONT` resources, window port renderer (overlay pass on top of slices, emulating `SaveBits`/`RestoreBits` without reslicing).
6. **SCI custom cursor parser & canvas pointer** — `CURSOR` (68-byte) resources, canvas mouse overlay.
7. **Launcher detection & workbench integration** — detect `RESOURCE.MAP` vs AGI, open engine-specific diagnostic browsers.
8. **Compositor decoupling & session facade** — extract `AgiPicturePainter` into `PlayfieldPainter` and `PlayfieldActorSprite`.
9. **SCI VM skeleton + `DrawPic` / `Animate` / `Parse` stubs** — PQ2 title/boot.
10. **Kernel Animate + ego motion** — first walkable PQ2 room.
11. **QFG2 compression (`kCompLZW1`) and SCI1-EGA view mapping** — only after PQ2 rooms look right.
12. **Sound synthesis: Tandy 3-Voice & OPL3 (AdLib FM)** — multi-track MIDI playback through existing audio sinks.
13. **Sound synthesis: Roland MT-32 via Munt (`libmt32emu`)** — FFI native asset binding for definitive SCI0 audio.

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
| AGI-only | `flutter test` (existing tree; `test/sci/` is empty or skipped by path) |
| Shared graphics (`DisplayProfile`, slicer, compositor, atlas, CRT, `EgaColors`) | **both** `flutter test test/sci/` and full AGI `flutter test` |

Placement:

- All new SCI tests go in `test/sci/` from the first file. Never next to `kq2_*` / `sq2_*` under `test/engine/` or `test/loader/`.
- Shared slicer/atlas/compositor tests that feed both 160×168 AGI and 320×200 SCI fixtures belong in `test/graphics/` (or remain in `test/picture/` and count as shared).
- SCI loader/pic/view fixtures come from PQ2 (and later LSL2 source-tree views). Do not check game volumes into git; tests read from `reference_games/police-quest-2/` or an env path, same pattern as AGI.
- Graphics goldens: compare sliced PNG dumps against ScummVM / pic-browser output for a handful of PQ2 rooms (day-room, interior, a pic with dither).

This is also recorded in `AGENTS.md` §3 so agents do not default to a full-suite run on every SCI PR.

## 10. What this planning phase does *not* do

- No SCI interpreter, no `lib/sci/` code, no AGI folder move.
- No `reference_docs/` in git.
- No SCI1 VGA.

The committed output of this phase is this document, the graphics note, the reference index, and the `AGENTS.md` pointer at the harvested trees.
