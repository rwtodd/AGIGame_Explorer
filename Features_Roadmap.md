# Sierra AGI Engine & Workbench — Features & Roadmap

Last updated: 2026-08 (Updated with Gemini AI parser, menu bar, and v3 engine fixes)

Reference engines: `./reference_docs`  
Reference games: `./reference_games`  
Architecture notes: `./doc/`

**Target:** Dart 3 / Flutter, macOS desktop first. AGI v2 and v3.

This document is a **status map**, not a wish list. The engine can run and complete classic Sierra titles. What comes next serves two purposes: making more games fully completable, and polishing the diagnostic workbench features that make finding and fixing remaining quirks fast and effortless.

---

## 1. Vision

Two products in one app:

1. **An accurate interpreter** that plays classic Sierra AGI games (King’s Quest, Space Quest, Police Quest, Black Cauldron, Leisure Suit Larry, etc.) natively in Dart and Flutter.
2. **A diagnostic workbench** that exposes pictures, views, logic scripts, sound channels, flags, variables, and save-states in real time.

---

## 2. Where We Actually Are

**Phase 1 (play core games) is done**, with one deliberate architectural choice: the engine runs on the main Flutter thread rather than a separate isolate. The 20 Hz tick loop, picture slicing, audio queue events, and UI share the isolate cleanly. Yielded opcodes (`print`, `get.string`, `get.num`, status menus) interact directly with UI overlays with zero serialization overhead.

**Multiple full games are playable and completable.** Space Quest II plays through to the end. There is an automated regression suite of 380+ unit and real-room integration tests for SQ1, SQ2, KQ2, KQ3, KQ4 (v3), Police Quest 1, and The Black Cauldron.

Release-mode cost on macOS (60 Hz UI, 20 Hz tick cycle): ~20% CPU, ~19% GPU, ~175 MB RAM.

### 2.1 Engine — Done

| Area | Status | Notes |
|---|---|---|
| V2 / V3 `DIR` + `VOL` loader, LZW, Avis Durgan, nibble unpack | **Done** | Handles dual-format v2 and single/split volume v3 |
| LRU cache of raw volumes, parsed LOGIC, VIEW, and picture templates | **Done** | Memory-efficient resource manager |
| Picture vector interpreter (`0xF0`–`0xFA`), scanline fill, pens, splatters | **Done** | Pixel-accurate vector rasterizer |
| Priority-sliced Impeller compositor (16 depth bands, actors Z-sorted) | **Done** | Fast GPU-accelerated depth compositing |
| VIEW atlas, mirrored loops as GPU flips, `add.to.pic` burn + reslice | **Done** | 32-bit packed integer texture atlas keys |
| Logic VM, flags/vars/strings/controllers, `call` / `new.room` / scan-start | **Done** | Full AGI bytecode interpreter |
| Motion: normal, wander, follow, move.obj, horizon, blocks, shuffle | **Done** | Authentic 8-way motion and border hit detection |
| `WORDS.TOK` parser, `said()` with ANYWORD (1) / ROL (9999) | **Done** | Noise word filtering, contraction normalization |
| Gemini AI Natural Language Command Translation | **Done** | AST `said(...)` extraction, in-memory caching, Google AI Studio integration |
| Menus, `set.key`, status line, inventory, `show.obj`, `get.string` / `get.num` | **Done** | Authentic dropdown menus & keyboard navigation |
| Save / restore / restart (`.sav` files + rolling in-memory checkpoints) | **Done** | State serialization and before/after diffing |
| Sound: PC speaker, Tandy/PCjr 3-voice+noise, custom synth; WAV/MIDI/CSound | **Done** | Real-time macOS AudioQueue PCM playback and file export |
| Display: 4:3 aspect correction, integer scale, pixel grid, EGA palette, CRT shader | **Done** | Toggleable text backgrounds, scanline shaders |
| Game loop: self-rescheduling 10/20/30/60 Hz, input queue, repaint listenable | **Done** | Cycle speed selector and sync |

Stubs that still no-op (implement when a playable game hits them):
- `overlay.pic`
- `show.pri.screen`

### 2.2 Workbench & Diagnostics — In Progress

| Area | Status | Notes |
|---|---|---|
| Launcher + resource browsers (Logic, Picture, View, Sound, Objects, Words) | **Done** | Full browser suite with search and playback |
| Picture layer modes (composited / visual / priority / control) and hover inspector | **Done** | Available in Picture Browser |
| Picture vector **replay** (step / play drawing opcodes frame-by-frame) | **Done** | Step forward/back through picture vector draws |
| Logic **disassembler** with highlighting, jump targets, export as text | **Done** | Full instruction decoder and decompiler |
| Sound piano-roll / playhead, channel preview, WAV/MIDI/CSound export | **Done** | Interactive tone playback and channel solo/mute |
| In-game sidebar slideout panel (Audio, Video, AI tabs) | **Done** | Quick-access settings and API key config |
| In-game debug inspector: checkpoints, flag/var **view**, object table, call stack | **Done** | Inspect live state and checkpoint diffs |
| Live flag/var **editing & pinning** in inspector | **Done** | Inline edits, +/- steppers, watch expressions, push-pin locks per tick |
| Room teleporter & inventory add/drop manager | **Done** | Teleport to rooms 0–255 and give/drop items in inspector |
| Pause / single-step cycle / speed menu | **Done** | Step 1 frame at a time |
| In-game visual debug overlays (Priority, Control buffer, Actor bounding boxes) | Next | Toggle depth/control maps directly in `GameScreen` |
| God mode / no-clip / ignore hazards | Next | Bypasses control barriers for rapid testing |
| Execution breakpoints (logic id, opcode, flag/var predicates) | Planned | Break on room change, flag toggle, or opcode |
| Step-over at instruction level (vs cycle step) | Planned | Instruction-level debugger |
| Current-room `said()` matrix inspector | Planned | Browse reachable verbs/nouns in current room |
| PNG export from View / Picture browsers | Planned | One-click sprite/background export |

### 2.3 Player QoL & AI Enhancements

| Area | Status | Notes |
|---|---|---|
| Gemini AI natural language command parser | **Done** | Integrated with AST said extractor, in-memory cache, and fallback |
| Multilingual translation support (e.g. Spanish/Japanese to Sierra tokens) | **Done** | Handled natively by Gemini command translator |
| IME & Unicode prompt input (Japanese/CJK/accented text entry) | Planned | Wire `TextInputClient` for OS composition & candidate popups |
| God mode / no-clip / ignore hazards | Next | Bypasses control barriers for rapid testing |
| Click-to-walk / A* pathfinding on control map | Planned | A* navigation around priority 0/1 obstacles |
| Point-and-click context menus from VIEW hit-tests + `posn`/`said` | Planned | Contextual actions (Look, Talk, Take) on click |
| TTS for dialogs | Planned | Optional accessibility screen reader |
| Input macro record / replay | Planned | Record input playthroughs for regression testing |

---

## 3. Game Compatibility

Assets in `reference_games/`: Black Cauldron, KQ2, KQ3, KQ4 (AGI v3), Police Quest 1, SQ1, SQ2.

| Game | Engine Version | Status | Notes |
|---|---|---|---|
| **Space Quest II** | AGI v2.917 | **Finishable** | Full playthrough verified, endgame sequences pass |
| **Space Quest I** | AGI v2.272 | **Finishable** | Intro, Arcada departure, keypad input, droid hazards tested |
| **King’s Quest II** | AGI v2.411 | **Finishable** | Swim, castle, Dracula, magic door, tower stairs verified |
| **King’s Quest III** | AGI v2.917 | Playable | Wizard timer clock sync, inventory, spells, and room transitions tested |
| **King’s Quest IV** | AGI v3.002.149 | **Finishable** | AGI v3 logic decryption, object priorities, and doorway motion tested |
| **Police Quest I** | AGI v2.425 | Playable | Ego driving, room 116, booking room verified |
| **The Black Cauldron** | AGI v2.007 | Playable | F3/F4 item selection, food usage, room 8 survival tested |

---

## 4. Prioritized Next Steps

### Next 1 — In-Game Visual Debug Overlays & God Mode (Highest Value for Playtesting)
1. **In-Game Visual Overlays**: Toggle translucent Control Buffer (walkable/water/triggers), Priority Buffer (depth bands), and Actor Bounding Boxes directly inside `GameScreen`.
2. **God Mode / No-Clip Toggle**: Bypass collision barriers to accelerate bug diagnosis and test rooms without dying.
3. **Current-Room `said()` Matrix & Autocomplete**: In-game list of valid recognized actions for the active room logic.

### Next 2 — Full Playthrough Verifications
- Continue playing games through to completion, capturing edge-case opcodes or quirks and adding regression tests.

### Next 3 — A* Click-to-Walk
- Implement A* pathfinding on the 320x200 control buffer to let players click on the playfield to move Ego around obstacles.

### Next 4 — Macro Record & Playback
- Record keyboard/mouse inputs and replay them as automated regression tests.

---

## 5. Working Sequence

| Order | Slice | Goal |
|---|---|---|
| **A** | In-game collision/priority visual overlays & God mode | Effortless in-game visual diagnosis |
| **B** | Full playthrough verification | Expand library of 100% completed games |
| **C** | Current-room `said()` matrix inspector | Real-time command discovery |
| **D** | Breakpoints (break on `new.room`, flag set, or `said` match) | Advanced bytecode debugging |
| **E** | A* Click-to-walk on control buffer | Modern point-and-click player enhancement |
| **F** | Input macro recording & playback | Automated speedrun and regression validation |
