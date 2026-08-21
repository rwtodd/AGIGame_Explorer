# Sierra AGI Game Engine & Diagnostic Workbench

A modern Sierra On-Line Adventure Game Interpreter (AGI v2/v3) player and interactive reverse-engineering workbench built natively in Dart and Flutter.

## Documentation & Architecture
- [**Features Roadmap**](Features_Roadmap.md): Current status, what is actually implemented, and what to build next.
- [**Picture rendering**](doc/picture_rendering_strategy.md): Vector opcodes, priority buffer, Impeller slice compositor.
- [**Graphics & animation pipeline**](doc/graphics_and_animation_pipeline.md): View atlas, cel cycling, input buffering.
- [**Text compositing**](doc/text_and_picture_compositing_architecture.md): Status line, dialogs, and picture layers.
- [**Sound system**](doc/sound_system_design.md): PC speaker / Tandy / enhanced synth, MIDI and CSound export.

## Implemented Subsystems
- **Container & Resource Loader**: Real-time parsing of V2 and V3 AGI volumes (`VOL.0..n`, `DIR` files, or `<prefix>DIR` / `<prefix>VOL.0`).
- **Decompression & Crypto**: 11-bit LZW decompression, 4-bit nibble expansion, and Avis Durgan XOR decryption.
- **Data Parsers**: `WORDS.TOK` vocabulary dictionaries and `OBJECT` inventory tables.
- **Picture Vector Renderer**: Full opcode interpreter (`0xF0`–`0xFA`), Bresenham line drawing, 4-way flood fill, circle/rectangle pens, and LFSR splatter textures.
- **Impeller Priority Canvas**: 320x200 priority slice decomposition, nearest-neighbor boundary compositing, and layer diagnostics (Composited, Visual, Priority Map, Control Map).
