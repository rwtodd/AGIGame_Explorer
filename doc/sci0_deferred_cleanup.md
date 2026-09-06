# SCI0 deferred cleanup

Nits noticed while landing pictures, then views. None of these block the next resource type. Do **not** start another pic-cleanup pass before fonts/cursors unless a bug forces it.

## Pictures / raster

- **Redundant undithered palettes.** `SciPic._unditheredPacked` and `SciPicCanvas.unditheredPalette256` are the same 256-entry blended EGA table. Collapse to one shared constant (on `SciPic` or a tiny dither helper) so canvas/slice/flat decode cannot drift.
- **Opcode walkers are still duplicated.** Full interpret vs step-decode walk F0–FF separately in both AGI (`PicVectorInterpreter` / `PicStepInterpreter`) and SCI (`SciPicInterpreter` / `SciPicStepInterpreter`). That split is intentional — same canvas, two walkers — and should stay unless a real opcode divergence bug appears.
- **`FE 08` priority-band tables** are parsed nowhere yet. Needed when actors/Animate exist; ignore until then.
- **`AgiPicturePainter` name.** Already paints `SierraPicture`. Rename to `PlayfieldPainter` in the compositor-decoupling PR, not as a drive-by.
- **Pic Browser GPU lifetime.** Decoded `SierraPicture`s stay in `_ownedPics` until the screen disposes. In-place replay mutates one instance (`rasterEpoch`). Do not dispose-on-replace; that was the use-after-dispose crash.

## Views / compositor (after this PR)

- **`AgiActorSprite` still hardcodes `scaleX: 2.0`.** Atlas packing is engine-agnostic native pixels; the playfield draw path is not. Generalize to `PlayfieldActorSprite` using `SierraView.pixelScaleX` (AGI 2, SCI 1) plus `displaceX` / `displaceY` / `z` when rooms actually animate.
- **`CelImageWidget` is AGI-only** (`scaleX: 2`, `AgiView`). Inventory/object inspection can switch to `SierraView` later.
- **SCI1 EGA `paletteOffset` 8×16 mapping** (QFG2) is ignored, matching ScummVM’s “only when `SCI_VERSION_1_EGA_ONLY`”. Honor it only after PQ2 rooms look right.
- **SCI0 early bottom-rect −1** (`_adjustForSci0Early`) is a placement quirk, not a parser issue. PQ2 is SCI0 late.

## Loader / UI leftovers

- **Launcher `copyWith` sentinel** for `sciVolumeManager` is already fixed; keep using `_unset`, never `??`.
- **VGA-in-EGA views** (`flags == 0x80`) and **SCI1.1 views** (`version == 1`) should keep failing closed in the EGA parser.
