# **Sierra AGI Engine & Interactive Debug Workbench Specification**

Note: reference AGI engines are in ./reference\_docs

Note: reference AGI games are in ./reference\_games

**Target Technology:** Dart / Flutter (Cross-platform: Desktop, Web, Mobile)  
**Target Architecture:** Sierra On-Line Adventure Game Interpreter (AGI) v2/v3

## **1\. Executive Summary & Vision**

While standard emulators like ScummVM focus primarily on accurate, unobtrusive gameplay, this project aims to build a modern **Sierra AGI Game Engine & Diagnostic Workbench** written natively in Dart and Flutter.  
The goal is a dual-purpose application:

> 1. **An accurate interpreter** capable of running classic Sierra games (King's Quest I–III, Space Quest I–II, Police Quest I, Leisure Suit Larry I, Gold Rush\!, etc.).  
> 2. **A deep diagnostic, reverse-engineering, and modding workbench** that exposes internal state, script logic, visual layers, sound registers, and memory in real time.

## **2\. Core Architecture & Tech Stack**

> * **Framework:** Flutter (Desktop-first UI with responsive adaptations for Mobile/Web).  
> * **Language:** Dart 3.x (Leveraging strong typing, patterns, isolates for timing-critical threads, and FFI if needed).  
> * **Rendering Engine:** Flutter  
  * Decompose backgrounds into priority bands so Impeller can paint them along with active sprites in Z-Order.  
  * Nearest-neighbor scaling to best integer multiple scale, adjusted for 4:3 aspect ratio, and add an optional CRT Shader.  
  * Present text and dialogs in modern, non-pixelated text.  
> * **State Management:** Riverpod / Bloc for reactive UI updates across debug panels without sacrificing main render thread performance. To maintain frame-rate precision (e.g., 20 ticks/sec AGI cycles and 60/120 FPS UI updates), isolate the engine's execution loop and sound synthesizer into a dedicated Dart Isolate, communicating with Flutter's main thread via thread-safe state ports.

## **3\. Core Engine Components**

### **A. Resource Loader & Unpacker**

> * Parse AGI container formats (VOL.0–VOL.n, DIR files, or v3 embedded directory structures).  
> * Decrypt and decompress game assets in real time:  
  * LOGIC (Bytecode scripts)  
  * PICTURE (Vector drawing commands)  
  * VIEW (Animated bitmap sprite sheets)  
  * SOUND (3-channel tone \+ 1-channel noise data)  
  * OBJECT (Inventory item records)  
  * WORDS.TOK (Vocabulary dictionary and synonym tables)  
> * Cache LRU-style the n-most recently-used resources so that we don’t have to keep re-parsing the same assets over and over when a user retraces nearby screens.

## **4\. Diagnostic & Debugging Suite (The Workbench)**

### **A. Visual & Graphics Debugger**

> * **Layer Toggles:** Independently switch visibility on/off for:  
  * Visual Background Canvas  
  * Priority Buffer Map (Depth sorting visualization with color-coded priority bands 0–14)  
  * Control Screen Buffer Map (Walkable areas, conditional triggers, water barriers, line-triggers)  
  * Sprite Bounding Boxes & Hitboxes (VIEW collision bounds)  
> * **Vector Picture Drawing Replay:**  
  * Step-by-step playback of PICTURE drawing opcodes (Watch line draws, flood fills, and control line painting in slow motion or frame-by-frame).  
  * Interactive Vector Editor preview: Highlight individual drawing commands and see which lines they generate on screen.  
> * **Palette & CRT Customization:**  
  * Toggle classic palettes: standard EGA (16 colors), CGA (Mode 4 palettes), Hercules Mono, or modern customized hex palettes.  
  * Configurable retro CRT shaders: Scanlines, phosphor bloom, curvature, pixel slot-masks.

### **B. Logic & Script Bytecode Debugger**

> * **Real-time Disassembler / Decompiler:**  
  * Disassembled view with opcode names and arguments.  
  * Decompile active LOGIC scripts on the fly into human-readable pseudo-code or AGI Studio syntax.  
  * **AST Decompilation & Spatial Extraction:** Decompile LOGIC blocks into an Abstract Syntax Tree (AST) that scans for paired posn(v, x1, y1, x2, y2) and said(...) checks to automatically detect interactive spatial triggers in the room logic.  
> * **Live Execution Control:**  
  * Pause, Single-Step frame, Step-Over logic execution, or set Speed Overrides (1 FPS to Uncapped).  
  * Breakpoints: Set execution breakpoints based on:  
    * Logic ID execution (e.g., break when LOGIC 15 runs).  
    * Variable mutation (e.g., break when current room changes, or when a variable is equal/not-equal/greater/less than a target value).  
    * Flag state toggles (e.g., break when ![][image3] turns TRUE).  
    * Specific command execution (e.g., break on new.room(), get(), or print()).  
    * Logical conjunctions of rules (e.g., Variable AND Flag rules).  
> * **Flag & Variable Inspector:**  
  * Live monitoring grid for all 256 Flags and 256 Variables.  
  * Symbol Naming System: Load community .var / .flg symbol mappings or define custom label aliases.  
  * Direct State Editing: Freeze, force toggle, or edit variable values live during gameplay.  
> * **Call Stack Viewer:**  
  * View current active LOGIC call tree (call(), call.v(), return()).

### **C. Sprite (VIEW) Inspector & Manipulator**

> * **Active Object Table Viewer:**  
  * View table of all active objects on screen: position, current VIEW ID, loop index, cel index, animation status, priority level, step size, and cycle time.  
> * **Interactive Object Teleportation:**  
  * Click and drag Ego or any active NPC sprite directly on the canvas to move them instantly (toggleable dev mode).  
> * **Sprite Viewer & Frame Exporter:**  
  * Browse all VIEW resources, animate loops, and export frames as PNG/GIF.

### **D. Parser & Vocabulary Diagnostics**

> * **WORDS.TOK Explorer:**  
  * Searchable dictionary of all recognized words and assigned word group IDs.  
  * Allow user to add new synonyms to words.  
  * Active Room Command Matrix that scans currently loaded LOGIC files for active said() matches, letting developers see every valid phrase reachable in the current room state.  
> * **Live Input Parse Tree:**  
  * Display real-time token breakdown when a user types a command (e.g., "look at tree" ==> Word 15 look, Word 0 ignore, Word 120 tree).  
> * **Autocomplete & Command Helper:**  
  * Dynamic overlay showing valid recognized verbs/nouns based on WORDS.TOK and local room script said() handlers.  
> * **Dual Input Modes:**  
  * Typing pauses game execution (MacOS style).  
  * Typing while the game continues running (DOS style).

### **E. Audio & Sound Channel Inspector**

> * **Multi-Track Mixer:**  
  * Solo, mute, or adjust volume for Channels 1, 2, 3 (Tones), and Channel 4 (Noise generator).  
> * **Audio Visualizer:**  
  * Real-time piano roll or frequency visualizer for sound bytecode execution.  
> * **Synthesizer Engine Switcher:**  
  * Standard PC Speaker (Square wave tone generation).  
  * Tandy 3-Voice / IBM PCjr (Enhanced with stereo separation, configurable reverb, and selectable waveforms: square, sawtooth, sine).  
  * SoundFont / MIDI conversion pipeline.

## **5\. Quality-of-Life & Modern Enhancements**

> * **Point-and-Click & Context Menu Overlay:**  
  * **Dynamic Object Hit-Testing:** Click on active dynamic VIEW sprites to trigger context menus (Look, Talk, Touch, Inventory interactions).  
  * **AST & Positional Logic Mapping:** Combine AST decompilation of posn() bounds with control buffer pixel values to expose background hotspots without manual re-authoring.  
  * **Optional Hotspot Overlays:** Support external JSON mapping files for community-contributed room interaction maps.  
> * **Save State Branching Timeline & Time-Travel Rewind:**  
  * Visual save-state manager with screenshot previews and a tree view showing timeline branches with text annotations.  
  * **Deterministic Time-Travel Rewind:** Store ring-buffered delta snapshots (variables, object positions, dynamic logic stacks) for frame-by-frame scrubbing back and forth through gameplay.  
> * **Pathfinding & Click-to-Walk:**  
  * Auto-pathfinding around priority obstacle buffers using A-star pathfinding on the control map buffer.  
> * **Accessibility / Text-to-Speech:**  
  * Integrated Flutter TTS to read on-screen text boxes aloud for visually impaired players.  
> * **No-Clip / God Mode:**  
  * Toggle flags to bypass control buffer collisions, prevent Ego death sequences, or make Ego invisible to hazard checks.

## **6\. AI & Smart Assistant Integration**

> * **Natural Language Command Parser:**  
  * Bridge fuzzy user typing to Sierra parser commands when deemed close enough (e.g., converting "check out the hollow log" ==> "look in log").  
  * Bridge Japanese natural language input to English Sierra parser commands.  
> * **Live Translation & Localization:**  
  * Real-time translation overlay to auto-localize on-screen dialogs and printed messages into Japanese or other target languages using LLM APIs or offline local models.

## **7\. Modding & Developer Workflows**

> * **Live Asset Hot-Reloading:**  
  * Edit a VIEW image or modify a decompiled LOGIC file in an external editor and watch the game update instantly in the running engine without restarting.  
> * **Full Game Decompile / Export:**  
  * Single-click project exporter: Convert an entire Sierra AGI game into a modern, structured JSON/PNG asset directory for modding or re-implementation:  
    * CSV files for WORDS.TOK and inventory objects.  
    * MIDI and WAV files for sound resources.  
    * PNG images for VIEW and PICTURE resources (scaled 2x horizontally for width correction, with optional 4:3 EGA aspect ratio correction.  
    * Decompiled text of LOGIC resources and associated message strings.  
> * **Macro & Input Scripting:**  
  * Record input play-through macros for rapid automated testing, speedrun validation, or bug reproduction.

## **8\. Implementation Roadmap**

### **Phase 1: Engine Foundation & Playability First (Play Core Games)**

> * **Resource Loader & Unpacker:** Parse VOL / DIR containers, decrypt assets, and extract LOGIC, PICTURE, VIEW, SOUND, OBJECT, and WORDS.TOK. Implement LRU caching.  
> * **Vector & Sprite Renderers:** Build PICTURE vector renderer and VIEW sprite compositor with priority depth buffer sorting in Flutter.  
> * **Isolate Execution Loop:** Build Dart Isolate execution thread running at 20 ticks/sec AGI cycle timing.  
> * **Bytecode Interpreter Engine:** Implement core AGI v2/v3 logic opcodes, flags, variables,  and object movement vectors.  
> * **Parser & Input System:** Implement WORDS.TOK dictionary lookup, said() check handler, and text input field (DOS and MacOS typing modes).  
> * **Basic Audio & Storage:** Implement basic PC Speaker audio channel synthesizer and standard file-based Save/Load game mechanisms.

### **Phase 2: Player Enhancements & Quality-of-Life**

> * **Audio Synthesizer Suite:** Add Tandy 3-Voice engine (with waveform customization and stereo separation) and SoundFont/MIDI playback.  
> * **Video & Display Customization:** 4:3 aspect ratio scaling, pixel-doubling, custom color palettes (EGA/CGA/Mono), and retro CRT shader options.  
> * **Navigation & Accessibility:** A-star pathfinding on the control buffer for click-to-walk navigation; integrated Flutter Text-to-Speech (TTS) engine.  
> * **AI Live Localization:** LLM-assisted live translation overlay to localise printed game text into Japanese or other languages.  
> * **God Mode Controls:** Basic collision bypass and invulnerability toggles.

### **Phase 3: Diagnostic & Debugging Workbench**

> * **Workbench UI Layout:** Multi-panel dockable Flutter layout with reactive Riverpod state updates.  
> * **Visual Diagnostics:** Overlays for Priority Buffer map, Control Buffer map, and Sprite Bounding/Hitboxes.  
> * **Flag & Variable Inspector:** Interactive live monitoring grid, symbol alias loader (.var/.flg), and real-time state overrides.  
> * **Logic Execution Debugger:** Disassembler view, execution breakpoints (Logic ID, variable/flag triggers, opcodes), step-frame controls, and call stack viewer.  
> * **Vector & Asset Inspection:** PICTURE vector opcode drawing step replay; VIEW sprite sheet browser and frame exporter; Active Object Table monitor.  
> * **Audio & Vocabulary Diagnostics:** Multi-track channel mixer, piano roll visualizer, WORDS.TOK dictionary browser, live parse tree viewer, and active room said() handler matrix.

### **Phase 4: Advanced Workbench & Time-Travel Debugging**

> * **Time-Travel Rewind System:** Ring-buffered state snapshotting with deterministic frame-by-frame scrubbing and interactive timeline branch manager.  
> * **Canvas Manipulator:** Interactive drag-and-drop object/Ego teleportation on the game canvas.  
> * **Point-and-Click Integration:** Context menus powered by dynamic VIEW hit-testing and decompiled LOGIC AST spatial triggers (posn() \+ said()).  
> * **Macro Automation:** Input macro recorder and automated playback runner for bug reproduction and speedrunning.

### **Phase 5: Future & Ambitious Engine Features (Modding & AI)**

> * **Live Asset Hot-Reloading:** Watch external file modifications (LOGIC / VIEW) and hot-reload running game assets live without restarting the game loop.  
> * **Full Game Decompiler & Exporter:** Single-click exporter producing modern JSON, PNG 4:3 aspect-corrected, CSV, MIDI, and decompiled source text.  
> * **Natural Language AI Parser:** LLM fuzzy natural language parser translating user queries into Sierra verb/noun tokens (including cross-language Japanese ![][image11] Sierra parser bridging).

