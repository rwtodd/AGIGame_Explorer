# Sierra AGI Game Engine & Diagnostic Workbench

A modern, high-accuracy Sierra On-Line Adventure Game Interpreter (**AGI v2 & v3**) engine and interactive diagnostic workbench built natively in **Dart** and **Flutter** (macOS & Windows desktop).

---

## Highlights & Features

### 🎮 High-Accuracy AGI v2/v3 Game Interpreter
- **Broad Game Compatibility**: Runs classic Sierra titles including *Space Quest I & II*, *King's Quest I–IV (including AGI v3)*, *Police Quest I*, *The Black Cauldron*, and *Leisure Suit Larry I*.
- **Faithful Cycle-Based Engine**: 20 Hz AGI logic cycle timing with authentic motion models (`normal`, `wander`, `followEgo`, `moveObj`), priority depth barrier collisions, authentic water physics & baseline surface constraints (Sierra `ANIMATE.C:182` / ScummVM `view.cpp:684`), cross-room Flag 0 handoffs, and screen boundary transitions.
- **Classic Sierra Menu Bar**: Interactive dropdown menu bar (`ESC` or mouse click) supporting game options, speed controls, sound toggling, and controller shortcuts.
- **Dynamic Inventory & Dialogs**: Authentic text wrapping, single-line input prompts (`get.string`, `get.num`), `show.obj` item inspections, and TAB-based inventory selector.
- **Save State System**: JSON `.sav` save state serialization and in-memory rolling checkpoints with state diffing.

---

### 🤖 Gemini AI Natural Language Command Parser
Stuck on Sierra's strict 2-word parser ("*I don't understand 'check'*")? The engine features an optional, zero-cost **Gemini AI Command Translator**:

- **Room-Aware AST Extraction**: When you type a command, the engine decompiles the bytecode of `LOGIC 0` and the current room's logic script to extract all valid `said(...)` phrase patterns and dictionary synonyms.
- **Natural Language & Multilingual Input**: Type long sentences, conversational phrases, typos, or even other languages (e.g. "*Can you please look inside the hollow tree trunk?*", "*examine spaceship panel*", or Spanish "miro los arboles"), and Gemini translates your intent into the exact verb-noun tokens accepted by the active room script.
- **Low Latency & Fast In-Memory Caching**: Powered by `gemini-3.5-flash-lite` (with selectable models up to `gemini-3.7-flash`), cached locally per room so repeat actions execute instantly.
- **Transparent Fallback**: If AI Assist is disabled or offline, input immediately passes through the native Sierra `WORDS.TOK` tokenizer and `said(...)` pattern matcher without delay.
- **Easy Setup**: Get a free API key at [Google AI Studio](https://aistudio.google.com/) (zero cost, no credit card required) and configure it in the in-game slideout sidebar or launcher settings dialog.

---

### 🔬 Deep Diagnostic & Reverse-Engineering Workbench
Designed for reverse-engineers, modders, and curious players to inspect and modify game assets and state in real time:

- **Live Variable & Flag Inspector with Pinning**: View, filter, and edit all 256 variables and 256 flags on the fly. **Pinning** locks any variable or flag so the engine re-asserts its value each cycle (ideal for freezing timers, testing conditional branches, or granting invulnerability).
- **Interactive Checkpoints & Markdown State Diffing**: Capture instant visual checkpoints with screenshot thumbnails, roll back state, export clean JSON snapshots, and compute before/after diffs in Markdown.
- **Room Teleporter & Inventory Manager**: Teleport directly to any room (0–255) and add/drop inventory items with live cel previews.
- **Logic Script Browser & Disassembler**: Interactive AGI bytecode disassembler with syntax highlighting, jump target resolution, and plain text export.
- **Picture Vector Browser & Step Replay**: Vector drawing opcode interpreter (`0xF0`–`0xFA`) with frame-by-frame drawing replay (lines, fills, pens, splatters) and layer toggles (*Composited*, *Visual*, *Priority Buffer*, *Control Screen Buffer*).
- **View Sprite Sheet Browser**: Animated cel previewer, loop navigator, and sprite frame inspector.
- **Sound Player & Visualizer**: Multi-channel waveform and frequency visualizer with MIDI (`.mid`), CSound (`.csd`), and `.wav` export.
- **Objects & Words Browsers**: Searchable inventory table and dictionary vocabulary browser with synonym group listings.

---

### 🔊 Retro Audio Synthesis
- **Multi-Mode Synthesizer**: Native real-time PCM audio playback via macOS AudioQueue and Windows waveOut (`winmm.dll` Dart FFI).
- **Selectable Audio Modes**:
  - *PC Speaker*: Authentic 1-channel square wave tone generator.
  - *Tandy 3-Voice / PCjr*: Multi-voice tone generation with configurable periodic/white noise channel.
  - *Custom Enhanced Synthesizer*: Smooth envelopes and enhanced audio mixing.
- **Audio Export**: Export sound resources directly to standard MIDI files, CSound score files, or WAV files.

---

### 📺 Video, Aspect Ratio & Retro CRT Shaders
- **Authentic 4:3 Aspect Ratio Scaling**: Integer-scaled 320x200 playfield presentation with 4:3 display ratio correction.
- **CRT Scanline Shader**: GPU-accelerated fragment shader simulating classic cathode-ray tube phosphor bloom, curvature, and scanlines.
- **Pixel Grid & Background Toggles**: Toggle pixel boundary grids and text box background transparency.

---

## Quick Start

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x or newer)
- macOS or Windows (macOS primary desktop target)

### Running the App
```bash
# Clone the repository
git clone https://github.com/rwtodd/AGIGame_Explorer.git
cd AGIGame_Explorer

# Install Flutter dependencies
flutter pub get

# Run on macOS desktop
flutter run -d macos

# Or run on Windows desktop
flutter run -d windows
```

### Running Tests
```bash
# Run the full test suite (570+ unit and game integration tests)
flutter test

# Run static analysis
dart analyze
```

---

## Game Controls & Shortcuts

| Key / Input | Action |
|---|---|
| **Arrow Keys / Numpad** | Move Ego in 8 directions (Up, Down, Left, Right, Diagonals) |
| **Spacebar** | Re-type the last input command (if the input is empty) |
| **Typing** | Enter parser commands directly at the command prompt |
| **ESC** | Open / Close Sierra Top Menu Bar |
| **TAB** | Open Inventory Dialog |
| **Enter / Return** | Advance dialogue boxes, submit text input, confirm menus |
| **F1** | Help Screen |
| **F2** | Sound On / Off Toggle |
| **F4** | Use Active Object (The Black Cauldron) |
| **F5** | Save Game Dialog |
| **F7** | Restore Game Dialog |
| **F9** | Restart Game |

---

## Architecture & Project Structure

```
lib/
├── audio/          # PCM synthesizer, AudioQueue sink, MIDI/CSound/WAV builders
├── core/           # EGA palette, LZW decompression, Avis Durgan crypto, exceptions
├── domain/         # Models (Picture, View, Sound, Logic, Menu, GameStateSnapshot)
├── engine/         # 20 Hz tick loop, motion, collisions, parser, said extractor
│   └── ai/         # Gemini AI natural language command translator
├── loader/         # V2/V3 DIR & VOL container parser, resource caching
├── logic/          # Bytecode VM, instruction decoder, logic disassembler
├── picture/        # Vector picture interpreter and priority depth slicer
└── ui/             # Game playfield, diagnostic browsers, dialogs, shaders
    ├── screens/    # LauncherScreen, GameScreen, and 6 Resource Browsers
    └── widgets/    # Sidebar slideout panel, AV settings, inspector dialog
```

For detailed architectural notes, see:
- [Features Roadmap](Features_Roadmap.md)
- [Picture Rendering Strategy](doc/picture_rendering_strategy.md)
- [Graphics & Animation Pipeline](doc/graphics_and_animation_pipeline.md)
- [Text & Picture Compositing Architecture](doc/text_and_picture_compositing_architecture.md)
- [Sound System Design](doc/sound_system_design.md)

