# SCI0 deferred cleanup

Nits noticed while landing pictures, views, fonts, cursors, the compositor, and the VM skeleton. None of these block Stage 10 (Kernel Animate & Ego Motion). Do **not** start a drive-by cleanup pass unless a bug forces it.

Roadmap: [sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md) §8 (stages 1–9 done; Stage 10 Animate & Ego Motion next).

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

- **`Wait(0)` extra-pump is hardcoded to room 99.** `SciGameEngine._pumpVm` runs extra `doit` cycles only while `g11` (currentRoom) is 99, so PQ2's speed test can count a real `machineSpeed` instead of ~20. LSL2 also uses room 99 (`RM099.SC`); **LSL3 uses room 290**. QFG2 and other SCI0 titles may differ or skip the test. Do not treat 99 as universal. A portable version would extra-pump `Wait(0)` for ~1s of `GetTime` after boot, independent of room number, then cap at one cycle per tick even if scripts leave speed at 0.

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

## Roadmap mapping for remaining items (Stages 10–15)

- **Stage 10 (Kernel Animate & Ego Motion)**:
  - `SierraGameSession` / `GameScreen(SierraGameSession)` session facade.
  - `FE 08` priority-band table parsing and dynamic priority mapping.
  - Actor `nsTop`/`nsLeft`/`nsBottom`/`nsRight` coordinate bounding boxes.
- **Stage 11 (Text Parser & Menu Bar)**:
  - Status bar and menu bar item hit-testing.
- **Stage 12 (Dialog Windows & Typography)**:
  - SaveBits/RestoreBits as an overlay *stack* (`kNewWindow` / `kDisposeWindow`).
  - Kernel `TextWidth` / `GetLongest` and `|c` / `|f` tokenization.
  - High-res Font 0/1 substitution (video setting; fonts ≥ 2 stay bitmap).
  - Hit-testing on overlay controls.
- **Stage 15 (QFG2 & SCI1-EGA)**:
  - QFG2 SCI1-EGA gray cursors and view `paletteOffset` 8×16 translation.
