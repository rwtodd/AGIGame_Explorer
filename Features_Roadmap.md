# Sierra AGI Engine & Workbench — Features & Roadmap

Last updated: 2026-08 (after SQ2 became completable)

Reference engines: `./reference_docs`  
Reference games: `./reference_games`  
Architecture notes: `./doc/`

**Target:** Dart 3 / Flutter, macOS desktop first. AGI v2 and v3.

This document is a **status map**, not a wish list. The original 2022 specification mixed a working interpreter with an unbounded workbench and AI future. The engine can now finish at least one full Sierra title. What comes next should serve that: more games finishable, then the workbench features that make remaining glitches cheaper to find.

---

## 1. Vision (still true)

Two products in one app:

1. **An accurate interpreter** that can play classic Sierra AGI games (King’s Quest, Space Quest, Police Quest, Black Cauldron, …) without ScummVM.
2. **A diagnostic workbench** that exposes pictures, views, logic, sound, flags, and save-states so the first product can be made correct.

ScummVM is the better *player* if that is all you want. This project exists because the workbench and the native Dart engine are the point.

---

## 2. Where we actually are

**Phase 1 (play core games) is done**, with one deliberate exception: the engine does **not** run on a Dart isolate. The 20 Hz loop, picture slicing, and UI share the main isolate. Yielded opcodes (`print`, `get.string`, texture upload) all need the UI thread. Isolating the VM is high risk and low reward; do not pick it up.

**A full game can be finished.** Space Quest II plays through to the end. There is a large regression suite of real-room tests for SQ1, SQ2, KQ2, KQ3, Police Quest 1, and Black Cauldron.

Release-mode cost on macOS (60 Hz ticks, 2026-08): roughly 20% of one CPU core, 19% GPU, ~174 MB. Debug/hot-reload numbers are not representative.

### 2.1 Engine — done

| Area | Status |
|---|---|
| V2 / V3 `DIR` + `VOL` loader, LZW, Avis Durgan, nibble unpack | Done |
| LRU of raw volumes, parsed LOGIC, VIEW, and picture templates | Done |
| Picture vector interpreter (`0xF0`–`0xFA`), scanline fill, pens, splatters | Done |
| Priority-sliced Impeller compositor (16 depth bands, actors Z-sorted) | Done |
| VIEW atlas, mirrored loops as GPU flips, `add.to.pic` burn + incremental reslice | Done |
| Logic VM, flags/vars/strings/controllers, `call` / `new.room` / scan-start | Done |
| Motion: normal, wander, follow, move.obj, horizon, blocks, obj.pos.shuffle | Done |
| `WORDS.TOK` parser, `said()` with ANYWORD / ROL, unknown-word handling | Done |
| Menus, `set.key`, status line, inventory, `show.obj`, `get.string` / `get.num` | Done |
| Save / restore / restart (`.sav` + in-memory checkpoints with diffs) | Done |
| Sound: PC speaker, Tandy/PCjr 3-voice+noise, enhanced synth; WAV/MIDI/CSound export | Done |
| Display: 4:3, integer scale, pixel grid, EGA palette, CRT fragment shader | Done |
| Game loop: self-rescheduling 10/20/30/60 Hz, input queue, playfield `repaint:` listenable | Done |

Stubs that still no-op (implement when a playable game hits them):

- `overlay.pic`
- `show.pri.screen`

Unknown AGI v3 action opcodes 170–181 are skipped by length, not implemented.

### 2.2 Workbench — partial

| Area | Status |
|---|---|
| Launcher + resource browsers (Logic, Picture, View, Sound, Objects, Words) | Done |
| Picture layer modes (composited / visual / priority / control) and hover inspector | Done |
| Picture vector **replay** (step / play drawing opcodes) | Done |
| Logic **disassembler** with highlighting, jump targets, export as text | Done |
| Sound piano-roll / playhead, channel preview, WAV/MIDI/CSound export | Done |
| In-game debug inspector: checkpoints, flag/var **view**, object table, call stack | Partial |
| Pause / single-step cycle / speed menu | Done |
| Live flag/var **editing**, `.var` / `.flg` symbol files | Not started |
| Execution breakpoints (logic id, opcode, flag/var predicates) | Not started |
| Step-over at instruction level (vs cycle step) | Not started |
| Sprite bounding-box overlay, drag-to-teleport Ego | Not started |
| Current-room `said()` matrix, live parse tree, command autocomplete | Not started |
| VIEW/PIC PNG export from browsers | Not started |
| Dual typing modes (DOS continues vs Mac pauses) | Not started (typing currently does not pause) |
| CGA / Hercules / custom palettes | Not started |
| Dockable multi-panel IDE layout | Not started (and not needed yet) |

### 2.3 Player QoL / extras — mostly not started

| Area | Status |
|---|---|
| Click-to-walk / A* on the control map | Not started |
| God mode / no-clip / ignore hazards | Not started |
| Point-and-click context menus from VIEW hit-tests + `posn`/`said` | Not started |
| TTS for dialogs | Not started |
| Input macro record / replay | Not started |
| Time-travel frame scrub (beyond the existing 25 checkpoints) | Not started |
| Live asset hot-reload | Not started |
| Full-game JSON/PNG/CSV exporter | Pieces exist (MIDI/WAV, disassembly); no one-click pack |
| LLM fuzzy parser / live translation | Not started — **out of scope until the engine is boringly accurate** |

### 2.4 Architecture notes that the old spec got wrong

- **No engine isolate.** Single-threaded loop on the UI isolate. Keep it.
- **Riverpod is only for launcher/settings.** The running engine is a `ChangeNotifier`. Do not rewrite it onto Bloc/Riverpod.
- **Cross-platform is a someday.** macOS desktop is the target. `dart:io` volume I/O is fine.
- **Worktrees / `file://` links in README were stale.** Docs live in this repo: `Features_Roadmap.md`, `doc/`.

---

## 3. Game coverage

Assets in `reference_games/`: Black Cauldron, KQ2, KQ3, KQ4 (AGI v3), Police Quest 1, SQ1, SQ2.

| Game | Evidence | Completeness |
|---|---|---|
| Space Quest II | Endgame test + playthrough | **Finishable** |
| Space Quest I | Intro, restore, room 2 | Playable; not signed off as complete |
| King’s Quest II | Many room/glitch tests (swim, castle, Dracula, magic door, …) | Playable; not signed off as complete |
| King’s Quest III | Inventory, restore, wizard death, room freezes | Playable; not signed off as complete |
| Police Quest 1 | Ego + room 116 tests | Unknown beyond those scenes |
| Black Cauldron | Inventory test | Unknown beyond that |
| King’s Quest IV (AGI) | V3 volumes present | Untested as a playthrough |

“Finishable” means a human can complete the game, not that every opcode path is proven. Remaining titles should be treated as **accuracy work**, not new features.

---

## 4. What should actually come next

Order is the point. Do not start Phase 5 AI, isolates, or a dockable IDE.

### Next 1 — Finish more games (highest value)

The interpreter is the product. Pick one title (KQ2 or SQ1 are the best-tested) and play it to the ending, filing engine bugs as you go. Same process that made SQ2 finishable.

Concrete engine gaps to keep on the radar:

- Implement `overlay.pic` and `show.pri.screen` when a game actually calls them (log in debug until then).
- Treat unknown opcode 170–181 as a bug if a v3 title (KQ4) dies on them.
- Keep adding *narrow* room tests next to each fix. Do not replace the real-game suite with mocks.

God mode / no-clip / “ignore blocks” belongs **here**, not in a QoL phase. It is a testing tool: walk through walls, skip death scripts, reach the rooms that still glitch.

### Next 2 — Workbench that makes Next 1 cheaper

Only the pieces that shorten a playthrough-and-fix loop:

1. **Live edit** flags and variables in the inspector (toggle f0–f15, set v0/v3/v6, etc.).
2. **Breakpoints:** break on logic number, on `new.room`, on flag set, on `said` match. Cycle-step already exists.
3. **Current-room `said()` list** scanned from loaded LOGIC (the “what can I type here?” matrix).
4. **Sprite bounding boxes** on the playfield (toggle). Drag-teleport Ego is nice; boxes first.

Do **not** build an AST decompiler, spatial hotspot extractor, or dockable panel framework in this pass. Disassembly + inspector + checkpoints already cover 80% of debugging.

### Next 3 — Click-to-walk

A* on the control buffer (priorities 0/1 blocked, 2/3 walkable as today) and a click on the playfield that issues a `move.obj` for Ego. This is the single best player-facing upgrade once two or three games finish. It reuses collision code you already have. Context menus and JSON hotspot maps wait until click-to-walk exists.

### Next 4 — Macro record / replay

Record direction, typed commands, and controller keys; play them back as the input queue. That turns a successful human playthrough into a regression test. You already have the input queue and a mountain of hand-written room tests; macros fill the gap between “this room works” and “this game still finishes.”

### After that (only if the above is boring)

- CGA / Hercules palette swaps and a less-overlay CRT (sample the playfield). Cosmetic.
- PNG export from View/Pic browsers. Small, useful for the workbench.
- Dual typing modes (pause-while-typing). Small.
- Full-game export pack (CSV words/objects, PNG, MIDI, disassembly). Most of the pieces exist.
- Frame-by-frame rewind. Checkpoints already exist; a ring buffer is a new persistence problem.
- Live hot-reload of LOGIC/VIEW. Cool for modding; not needed to finish Sierra games.

### Explicitly later / maybe never

- Engine isolate
- Riverpod/Bloc rewrite of the VM
- Web and mobile ports
- LLM command paraphrasing and live translation
- TTS
- Point-and-click adventure overlay with community JSON maps (after click-to-walk, if anyone asks)

---

## 5. Suggested working sequence

Each item is a vertical slice with tests. Stop and play a game after each.

| Order | Slice | Why |
|---|---|---|
| A | God mode + ignore-blocks + “don’t die” toggles in the inspector | Unlocks remaining playthroughs |
| B | Play KQ2 (or SQ1) to completion; fix glitches; add room tests | Second finishable title |
| C | Live var/flag edit + break on `new.room` / flag | Faster C-style debugging |
| D | Room `said()` matrix in the inspector | Stops guessing verbs |
| E | `overlay.pic` / `show.pri.screen` when a title needs them | Accuracy |
| F | Click-to-walk | Player QoL |
| G | Input macros feeding the existing test runner | Protect A–F |

---

## 6. Old phase labels (for archaeology)

The 2022 spec’s phases, mapped onto today:

| Old phase | Reality |
|---|---|
| Phase 1 Engine foundation | **Done** (no isolate, by choice) |
| Phase 2 Audio/video QoL | **Mostly done** (no A*, TTS, AI, god mode) |
| Phase 3 Workbench | **Started**: browsers + inspector + picture replay. Missing breakpoints, live edit, said matrix, bbox overlay |
| Phase 4 Time-travel / P&C / macros | Checkpoints exist. The rest is later |
| Phase 5 Modding & AI | Out of scope |

Use section 5, not these phase numbers, when picking work.
