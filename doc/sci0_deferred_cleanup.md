# SCI0 deferred cleanup

Nits noticed while landing pictures, views, fonts, cursors, the compositor, the VM, parser, and dialogs. None of these block Stage 13 (playable first PQ2 room). Do **not** start a drive-by cleanup pass unless a bug forces it.

Roadmap: [sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md) §8 (stages 1–12 done; Stage 13 walkable room next).

## Pictures / raster

- **Redundant undithered palettes.** `SciPic._unditheredPacked` and `SciPicCanvas.unditheredPalette256` are the same 256-entry blended EGA table. Collapse to one shared constant (on `SciPic` or a tiny dither helper) so canvas/slice/flat decode cannot drift.
- **Opcode walkers are still duplicated.** Full interpret vs step-decode walk F0–FF separately in both AGI (`PicVectorInterpreter` / `PicStepInterpreter`) and SCI (`SciPicInterpreter` / `SciPicStepInterpreter`). That split is intentional — same canvas, two walkers — and should stay unless a real opcode divergence bug appears.
- **`FE 08` priority-band tables** are parsed nowhere yet. Needed when actors/Animate exist; ignore until then.
- **Pic Browser GPU lifetime.** Decoded `SierraPicture`s stay in `_ownedPics` until the screen disposes. In-place replay mutates one instance (`rasterEpoch`). Do not dispose-on-replace; that was the use-after-dispose crash.

## Views / actors

- **`PlayfieldActorSprite.scaleX` still defaults to `2.0`.** Atlas packing is native pixels; View Browser uses `SierraView.pixelScaleX`. `GamePlayfieldWidget._buildActorSprites` never passes `view.pixelScaleX`, so an SCI playfield copied from that constructor will draw 2× wide. Construct with `scaleX: view.pixelScaleX.toDouble()`. Keep `2.0` only as an AGI fallback.
- **`CelImageWidget` is AGI-only** (`scaleX: 2`, `AgiView`). Inventory/object inspection can switch to `SierraView` later.
- **SCI1 EGA `paletteOffset` 8×16 mapping** (QFG2) is ignored, matching ScummVM’s “only when `SCI_VERSION_1_EGA_ONLY`”. Honor it only after PQ2 rooms look right.
- **SCI0 early bottom-rect −1** (`_adjustForSci0Early`) is a placement quirk, not a parser issue. PQ2 is SCI0 late.

## Overlay / compositor (pre-VM polish)

- **Title and button chrome still use Courier `TextPainter`.** `SciWindowOverlay` title bar is Courier even when `font` is set. `SciButtonControl` ignores `isPressed` (no invert/inset) and vertically centers with a hardcoded `8.0` instead of `font.fontHeight` (PQ2 FONT 1 is 12px). Line advance in `SciTextControl` is `fontHeight + 2.0` while `measureTextHeight` defaults to `lineSpacing: 1`. Paint titles/buttons with the window’s `SierraFont`; leave `|c`/`|f` and `GetLongest` for the VM.
- **`sciEnableDithering` is a no-op.** Stored, serialized, and shown in `AvSettingsDialog`, but never read by `SciPic`, Pic Browser, or `PlayfieldPainter`. Architecture §7 currently marks this Done. Either wire it to SCI pic/playfield `unditheredVisual` (and have Pic Browser honor the global default) or stop calling it done. Pic Browser still has its own undithered switch.
- **Cursor gray mapping keys off `DisplayProfile.isSci`.** `_paintMouseCursor` uses `displayProfile?.isSci` as a stand-in for SCI0 vs SCI1 gray. SCI1 EGA gray should be EGA 7, matching `SierraCursor.toRgba(isSci0: false)`. Drive this from engine version, not `horizontalDouble`.
- **`DisplayProfile.isAgi` / `isSci` are `horizontalDouble` aliases.** Any future custom profile (e.g. AGI without doubling) will mis-classify. Use an explicit engine flag if these getters keep driving color and layout.
- **`SciWindowOverlay` has no value `==` / `hashCode`.** The overlay test “equality and hashCode” passes only because both windows are `const` (canonicalized identity). `PlayfieldPainter.shouldRepaint` therefore uses identity; a new equal window object always repaints. Either implement value equality or drop the test. Add one compositor assertion that painting windows does not bump `rasterEpoch` / slice GPU images, and that the cursor origin is `position - hotspot`.
- **Cache cursor/glyph `ui.Image`s** instead of 1×1 `drawRect` blits (same pattern as slices/atlas). Do **not** allocate GPU images inside `CustomPainter.paint` (that was the `SciTextControl` leak).
- **Verbose overlay comments.** Class doc retells SaveBits vs overlay; `SciTextControl` had WHAT comments above the glyph loops; window paint numbered “white inset” that is not drawn (both strokes are `penColor`). Drop WHAT / history comments; fix or delete the white-inset claim.

## VM / game loop

- **Host throttles like DOSBox, not ScummVM script patches.** Each `tick()` steps the 60 Hz PIT by `60/speedHz` (3 at 20 Hz) and allows that many Wait(0) `doit`s. PQ2’s room-99 test still runs and should land g110 around 40–80. ScummVM instead patches rm99:doit to `g110=$7fff` / `gSpeed=6`. Do not add that patch unless a title’s test still overflows. GetTime spin loops yield after two identical reads (Dialog.doit).

## Parser / Said leftovers

- **`SciSaidMatcher.aiHook` is process-global.** A static mutable hook plus swallowed exceptions will leak across tests and engines. Prefer an instance/engine callback.
- **`kSetSynonyms` never `clearSynonyms()`.** ScummVM clears then walks collection elements only. Old room synonyms persist, and `_applyScriptSynonyms` on the collection object itself may treat `Game.number` as a script id.
- **`isInputEnabled` walks script 996 for `'User'` on every rebuild.** Cache the User object pointer (or `canInput`) after instantiate.
- **VOCAB.900 GNF parse tree is not ported.** `kParse` now sets `parserIsValid` and calls `wordFail`/`syntaxFail` with Sierra acc/claimed, but Said still matches a flat word-group heuristic. Port `parser/grammar.cpp` + `parser/said.cpp` when optional/`<`/`>` forms keep drifting.

## Overlay / compositor leftovers

- **`toOverlays()` allocates new `SciWindowOverlay` objects every tick.** No value `==` on overlays, so `shouldRepaint` always sees a new list. Cache until `onWindowsChanged`, or implement overlay/control value equality.
- **Title bars still use Courier `TextPainter` when no Sierra font is attached.** Prefer `SierraFont` (now used when `font` is set); Courier is the no-font fallback.

## Loader / UI leftovers

- **Launcher `copyWith` sentinel** for `sciVolumeManager` is already fixed; keep using `_unset`, never `??`.
- **VGA-in-EGA views** (`flags == 0x80`) and **SCI1.1 views** (`version == 1`) should keep failing closed in the EGA parser.

## Roadmap mapping for remaining items (Stages 13–20)

- **Stage 13 (Playable first PQ2 room)**:
  - Menu bar + 10px status strip; `kGraph`; SetCursor; mouse events; window hit-test.
  - `FE 08` priority-band tables (parsed on DrawPic). PIT is stepped from the host; no script speed-test patch.
- **Stage 14 (VOCAB.900 GNF)**:
  - Real Said tree; `syntaxFail` on GNF failure.
- **Stage 15 (FileIO / save / inventory)**:
  - FOpen family; kSaveGame/kRestoreGame; `gInventory showSelf:`.
- **Stage 16 (SCI0 audio)**:
  - Sequencer + Tandy/OPL3 into existing PCM sinks.
- **Stage 17 (QFG2)**:
  - LZW1; view `paletteOffset` 8×16; SCI1-EGA gray cursors.
- **Stage 20 (Workbench)**:
  - Overlay `==` / `toOverlays` cache; `|c`/`|f` / GetLongest; hi-res Font 0/1 as a setting.
