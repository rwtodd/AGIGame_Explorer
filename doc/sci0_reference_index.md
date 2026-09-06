# SCI 16-color reference index

Local, gitignored material for implementing Sierra SCI0 / SCI01 / SCI1-EGA support in this Flutter engine. Harvested 2026-09 on branch `sci0`. **Do not commit `reference_docs/`.**

Companion architecture docs:

- [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md) — does 16-layer slicing still work?
- [sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md) — how AGI and SCI share graphics without sharing a VM (roadmap status in §8)
- [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md) — font resources, selective hi-res typography, and layout metrics
- [sci0_deferred_cleanup.md](sci0_deferred_cleanup.md) — leftover pic/view nits; do not block fonts

## What was pulled

| Location | Contents |
|---|---|
| `reference_docs/scummvm_sci-2026-09/` | Full ScummVM `engines/sci` tree (217 files). Origin commit `df31503e8da88af91e9d41b36ede91fab0f6db74`. |
| `reference_docs/sci_specs/` | Curated notes: versions, resource.map, pics, views, screens, VM/kernel, parser. |
| `reference_docs/original_sierra_sci_src/leisure-suit-larry-2-main/` | Original Sierra LSL2 scripts (`SRC/*.SC`), headers, views. |
| `reference_docs/original_sierra_sci_src/leisure-suit-larry-3-main/` | Original Sierra LSL3 sources. |
| `reference_docs/scummvm_agi-2022-12/` | Existing AGI ScummVM tree (unchanged). |
| `reference_docs/README.md` | Folder-level readme (also gitignored). |

AGI-era copies of NAGI / original Sierra AGI still live under `/Users/rtodd/Documents/Games/Sierra_AGI_SCI/` if needed; they were not re-copied.

## ScummVM SCI map (questions → files)

Paths relative to `reference_docs/scummvm_sci-2026-09/`.

| Question | File |
|---|---|
| SCI0 vs SCI1 EGA vs VGA version enum | `detection.h` (`SciVersion`) |
| `RESOURCE.MAP` SCI0 packing | `resource/resource.cpp` `readResourceMapSCI0` |
| LZW / Huffman / LZW1 | `resource/decompressor.h` |
| Pic opcodes F0–FF, dither palettes, flood fill | `graphics/picture.cpp` `drawVectorData` |
| Three framebuffers | `graphics/screen.h` (`_visualScreen`, `_priorityScreen`, `_controlScreen`) |
| Y → priority band table | `graphics/ports.cpp` `priorityBandsInit` |
| SCI0 EGA view header + RLE | `graphics/view.cpp` `initData` `kViewEga` |
| Cast drawing / kernel Animate | `graphics/animate.cpp` |
| DrawPic / Show / AddToPic / OnControl | `engine/kgraphics.cpp`, `engine/kernel_tables.h` |
| Stack VM + objects | `engine/vm.cpp`, `engine/object.cpp`, `engine/script.cpp` |
| Parse / Said | `engine/kparse.cpp`, `parser/` |
| SCI0 MIDI | `sound/` |

## Local game data (not in this repo)

| Game | Path | Notes |
|---|---|---|
| Police Quest 2 | `reference_games/police-quest-2/` | **First playable target.** SCI0 late. `RESOURCE.MAP` + `RESOURCE.001`–`003`. |
| Quest for Glory 2 | `reference_games/quest-for-glory-2/` | SCI1 EGA (`SCI_VERSION_1_EGA_ONLY`). Same 16-color vector pics, different compression. |
| LSL2 / LSL3 / QFG1 EGA volumes | — | Not linked at harvest. LSL2/3 *source* is in `reference_docs/original_sierra_sci_src/`. |

## Web sources that fetched cleanly

SCI Wiki (`sciwiki.sierrahelp.com`) and the ScummVM wiki are behind bot checks. Prefer:

- https://scicompanion.com/Documentation/intro.html
- https://scicompanion.com/Documentation/_sources/pics.txt
- https://scicompanion.com/Documentation/_sources/views.txt
- https://scicompanion.com/Documentation/_sources/vocabs.txt
- https://github.com/scummvm/scummvm/tree/master/engines/sci

Notes distilled from those (and from ScummVM source) are in `reference_docs/sci_specs/`.
