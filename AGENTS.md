# Sierra AGI Game Engine & Workbench (Flutter / Dart)

## 1. Reference Implementations & Documentation

Reference engines, specifications, and test game data are kept in the primary repository and external workspace directories on the host machine. **Even when operating in an isolated git worktree**, agents can and should directly inspect these absolute paths:

- **Reference Documentation & Engines**: `/Users/rtodd/src/flutter_agigame/reference_docs/` (gitignored)
  - `scummvm_agi-2022-12/`: ScummVM AGI engine implementation.
  - `scummvm_sci-2026-09/`: ScummVM SCI engine (`engines/sci` sparse clone; pics, views, VM, kernel, resource.map).
  - `sci_specs/`: Curated SCI0/SCI1-EGA notes (resource.map, pic opcodes, views, priority/control, kernel, parser).
  - `original_sierra_sci_src/`: Original Sierra LSL2 and LSL3 game sources (`.SC` scripts).
  - Additional AGI-era trees (NAGI, original Sierra AGI, JAGI, Agile, AGI specs PDF) also live at `/Users/rtodd/Documents/Games/Sierra_AGI_SCI/` on the host.
- **SCI architecture notes** (git-tracked): `doc/sci0_reference_index.md`, `doc/sci0_graphics_and_priority.md`, `doc/sci0_dual_engine_architecture.md`.
- **Reference Java Parser**: `/Users/rtodd/src/org.rwtodd.agi`
  - User's prior modular Java implementation for AGI v2 and v3 parsing.
- **Reference Game Assets (for testing)**: `/Users/rtodd/src/flutter_agigame/reference_games/` (gitignored)
  - AGI: `black-cauldron/`, `kings-quest-1-agi/`, `kings-quest-2/`, `kings-quest-3/`, `kings-quest-4-agi/`, `police-quest-1/`, `space-quest-1/`, `space-quest-2/`
  - SCI `police-quest-2`, `quest-for-glory-2`.

---

## 2. Architecture & Subsystems Overview

- **`lib/core/`**: EGA 16-color palette, custom exceptions, LZW 11-bit decompression, Avis Durgan decryption, nibble unpacking.
- **`lib/loader/`**: V2 & V3 `DIR` / `VOL` container parsers, `WORDS.TOK` vocabulary, `OBJECT` inventory table, LRU caching `VolumeManager`.
- **`lib/domain/`**: Data models (`Picture`, `PriorityBuffer`, `AgiView`, `AgiSound`, `AgiLogicScript`, `AgiMemory`, `AnimatedObject`, `AgiObject`).
- **`lib/picture/`**: Vector interpreter (`PicVectorInterpreter`), 16-layer depth slicer (`PictureSlicer`), and `PriorityBuffer` control/priority screen buffer.
- **`lib/audio/`**: Multi-mode PCM sound synthesizer (PC Speaker, Tandy 3-Voice, PCjr), `AgiSoundPlayer`, macOS AudioQueue sink, Windows waveOut sink, MIDI & CSound exporters.
- **`lib/logic/`**: Bytecode VM (`AgiLogicInterpreter`), opcode execution, `AgiMemory` (256 flags, 256 vars, strings, controllers), and disassembler with syntax highlighting.
- **`lib/engine/`**:
  - `AgiGameEngine`: 20 Hz tick coordinator, room lifecycle, script calls, interpreter delegate events.
  - `lib/engine/motion/`: Direction vectors (0–8), motion modes (`normal`, `wander`, `followEgo`, `moveObj`), cel animation cycling, and control line / screen border collision detection.
  - `lib/engine/parser/`: Text input tokenizer against `WORDS.TOK`, noise filtering, unknown word detection, and Sierra `said(...)` pattern matcher with `ANYWORD` (1) & `ROL` (9999) wildcards.
  - `lib/engine/state/`: JSON `.sav` save state serializer and rolling checkpoint manager.
  - `lib/engine/controllers/`: Keyboard shortcut and function key mapping (`set.key`).
- **`lib/ui/`**:
  - `lib/ui/screens/game/game_screen.dart`: Interactive playable game screen with 4:3 EGA playfield viewport, top status line, bottom command prompt, and dialog popup overlays.
  - `lib/ui/widgets/`: Playfield compositor, modal dialogs (`DialogBoxWidget`, `InputPromptDialog`, `InventoryDialog`, `ObjectInspectionDialog`, `SaveLoadDialog`), debug inspector overlay (`DebugInspectorDialog`).
  - `lib/ui/screens/browsers/`: Individual resource browsers (Logic, Picture, View, Sound, Objects, Words) for the diagnostic workbench.

---

## 3. Development & Verification Rules

- **Platform Target**: Primary focus is macOS desktop (with Windows desktop supported natively via waveOut audio sink).
- **Validation**: Every feature and fix must include tests. Always run `dart analyze` before completing tasks. Scope `flutter test` by engine (the full AGI suite is hundreds of tests and is slow):
  - **SCI-only** changes (`lib/sci/`, `test/sci/`): `flutter test test/sci/`
  - **AGI-only** changes: `flutter test` (existing tree under `test/`, excluding `test/sci/`)
  - **Shared graphics** (`DisplayProfile`, slicer, compositor, atlas, CRT, `EgaColors`): both `flutter test test/sci/` **and** the full AGI `flutter test`
  - Put all new SCI tests under `test/sci/` from the first file. Shared slicer/atlas/compositor tests that feed both 160×168 AGI and 320×200 SCI fixtures belong in `test/graphics/` (or stay in `test/picture/` and count as shared). Do not drop SCI tests into `test/engine/` or `test/loader/` next to AGI room boots.
- **Terminal Execution**: Use `BypassSandbox: true` for commands requiring host platform toolchains (like `flutter` and `git`).
