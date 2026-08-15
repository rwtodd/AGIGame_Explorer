# Sierra AGI Game Engine & Diagnostic Workbench

A modern Sierra On-Line Adventure Game Interpreter (AGI v2/v3) player and interactive reverse-engineering workbench built natively in Dart and Flutter.

## Documentation & Architecture
- [**Features Roadmap**](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/Features_Roadmap.md): Engine specification, workbench tooling, and phase breakdown.
- [**Picture Vector Renderer & Impeller Canvas Strategy**](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/doc/picture_rendering_strategy.md): Architectural specification of vector opcode interpretation, 8-bit priority buffer memory layout, Impeller 320x200 priority-sliced layering, and Z-sorting compositing.

## Implemented Subsystems
- **Container & Resource Loader**: Real-time parsing of V2 and V3 AGI volumes (`VOL.0..n`, `DIR` files, or `<prefix>DIR` / `<prefix>VOL.0`).
- **Decompression & Crypto**: 11-bit LZW decompression, 4-bit nibble expansion, and Avis Durgan XOR decryption.
- **Data Parsers**: `WORDS.TOK` vocabulary dictionaries and `OBJECT` inventory tables.
- **Picture Vector Renderer**: Full opcode interpreter (`0xF0`–`0xFA`), Bresenham line drawing, 4-way flood fill, circle/rectangle pens, and LFSR splatter textures.
- **Impeller Priority Canvas**: 320x200 priority slice decomposition, nearest-neighbor boundary compositing, and layer diagnostics (Composited, Visual, Priority Map, Control Map).
