# SCI 16-color graphics and priority slicing

**Headline: the existing 16-layer Impeller compositor still works for SCI0 / SCI01 / SCI1-EGA, and it fits SCI better than it fits AGI.**

This document maps Sierra's 16-color SCI graphics onto the Flutter pipeline already used for AGI (`PictureSlice`, `PictureSlicer`, `AgiPicturePainter`, `ViewTextureAtlas`). Pics, views, `DisplayProfile`, and the parameterized slicer are implemented; actor `scaleX`, window overlay, and cursors are not. Roadmap: [sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md) §8.

Reference: ScummVM `graphics/picture.cpp`, `screen.h`, `ports.cpp`, `view.cpp`; SCI Companion pic/view docs; `doc/picture_rendering_strategy.md` for the AGI side.

## 1. What AGI does today

AGI pictures are 160×168 vector scripts. Two buffers:

- Visual (EGA index per native pixel)
- Priority, which is **also** control: 0–3 = barriers / water / alarm, 4–15 = depth

`PictureSlicer` walks the 160×168 visual buffer, looks up `priorityBuffer.effectivePriorityAtIndex` (scan down the column past control lines 0–2), and writes **horizontally doubled** pixels into 16 RGBA textures of 320×200. `AgiPicturePainter` then, for P = 0..15:

1. Draw slice P
2. Draw playfield text whose cell sits on band P
3. Draw actors with `priority == P`, sorted by baseline Y

Views are stored 160-wide and drawn with `scaleX: 2.0` (or −2.0 for mirrors).

That pipeline is the thing we want SCI to reuse.

## 2. What 16-color SCI actually has

### 2.1 Native 320×200, three maps, and dynamic picture ports

SCI0 pics are vector scripts too, but they paint **three independent 320×200 maps**:

| Map | Role in SCI | AGI analogue |
|---|---|---|
| Visual | What the player sees (40-color dithered or blended EGA) | Visual buffer (160, then doubled) |
| Priority | Depth 0–15 only | Priority 4–15, minus the control encoding |
| Control | Walkability + script triggers | Priority 0–3 (packed into the same buffer) |

There is **no horizontal doubling**. A SCI pic pixel is already one EGA display pixel.

**Coordinate spaces and picture ports (`GfxPort`):**
- In standard gameplay, a menu bar occupies rows 0..9, so the picture port is (0, 10) to (320, 200) with a height of 190.
- In cutscenes and title screens (e.g. PQ2 intro) where the menu bar is absent, the port is (0, 0) to (320, 200) with a height of 200.
- `SciPic` allocates three full **320×200** buffers (`Uint8List` visual, priority, control).
- During vector rasterization, coordinates are drawn relative to the active port offset: `(x, y + portTop)`.
- Consequently, all resulting `PictureSlice`s are full **320×200 RGBA textures**. The Impeller compositor requires **no special vertical translation hacks** when rendering SCI backgrounds.

### 2.2 Priority is a pure Z-buffer

A character at priority P is drawn in front of background pixels whose priority is $\le P$, and behind pixels whose priority is greater. The GPU translation is the Impeller slicer:

> Bucket each visual pixel into `slices[priority[x, y]]`. Composite slices 0..15, inserting actors of priority P after slice P.

Because SCI priority is **not** mixed with control, we do **not** use `effectivePriorityAt` or downward column scans when slicing SCI pics. Control-line pixels in AGI were a special case so actors would occlude correctly while walking on a trigger. In SCI, depth is a pure Z value ($0\text{--}15$), and control is maintained in its own dedicated buffer. `PictureSlicer` uses direct array indexing: `slices[priorityBuffer[idx] & 0x0F]` with `scanControlLines: false`.

### 2.3 Control is a collision overlay, not a layer

`OnControl` / `CanBeHere` / `CantBeHere` read the control map (and sometimes priority). Typical SCI0 convention: control 15 (`ctlWHITE`) is solid; other colors are room-defined (doors, water, trip lines). This is **not** AGI's 0/1/2/3 encoding.

Workbench consequence: keep the existing Visual / Priority / Control inspector modes. For SCI, Control shows the third buffer instead of masking priority values `< 4`.

### 2.4 Actor priority from Y

Walking actors do not carry a painted priority. The kernel maps feet-Y through a 200-entry band table (`GfxPorts::_priorityBands`).

Default init (`kernelInitPriorityBands`):

- Early SCI0 (`_usesOldGfxFunctions`): 15 bands, Y=42..200, then Sierra collapses band 15 into 14
- SCI0 late / SCI01 / SCI1 EGA: **14 bands, Y=42..190**

Integer math only (Sierra used int32; floats change LSL2 airplane, etc.):

```
bandSize = ((bottom - top) * 2000) / bandCount
bands[y] = 1 + ((y - top) * 2000) / bandSize   // y in [top, bottom)
```

Pics may replace the table (`FE 08`, 14 bytes). Scripts may call `GraphAdjustPriority(top, bottom)`.

AGI analogue: `AgiPriorityTable` (base 48, 12-pixel bands, height 168). Same interface, different numbers.

## 3. Picture opcodes vs AGI

Same 0xF0 family, extra control + palettes, native 320 coordinates.

| SCI0 | AGI | Notes |
|---|---|---|
| F0 / F1 set/disable visual | F0 / F1 | SCI F0 indexes a 40-entry dither palette, not a raw EGA color |
| F2 / F3 set/disable priority | F2 / F3 | Same idea |
| F4 short patterns | F9/FA pens | SCI splits pen plot into short/medium/absolute |
| F5 medium lines, F6 long, F7 short | F4–F7 lines | Different coord packing (320×200 abs/rel) |
| F8 fill | F8 fill | Sierra-exact, visual fill is white-only |
| F9 set pattern | F9 set pen | Circle/rect + texture bit |
| FA / FD pattern plots | FA plot pen | |
| **FB / FC set/disable control** | — | Third buffer |
| **FE extended** | — | Sub-op 0/1: 40-byte palette sets; sub-op 8: priority table; sub-op 7: embedded view |
| FF end | FF end | End of vector stream |

Bresenham/line and flood-fill must match ScummVM `picture.cpp`, not the AGI rasterizer, even though both are "vector pics." Coordinate packing and fill abort rules differ.

## 4. EGA dither palettes & non-dithered display mode

SCI0 visual "colors" are 40 slots × 4 palettes. Each slot is a pair of EGA colors $(c_1, c_2)$. Palettes are configured by picture opcode `FE 01` (40 bytes per palette table). QFG1 uses two palettes of the same pic for day and night. `DrawPic`'s optional 4th argument selects the palette.

ScummVM stores the pair in the visual buffer during vector draw, then resolves them to display pixels at `0xFF`.

### 4.1 Two visual presentation modes

Our engine supports both authentic rendering and modern enhanced viewing:

1. **Authentic EGA Dither Mode (Default)**:
   - Visual buffer stores the 40-entry palette indices during drawing.
   - At end of pic, checkerboard dither `(x ^ y) & 1` selects color $c_1$ or $c_2$.
   - Yields authentic 16-color EGA pixel patterns.

2. **Non-Dithered / Undithered Blended Mode (ScummVM `disable_dithering` / `GAMEOPTION_EGA_UNDITHER`)**:
   - Instead of alternating pixels, each of the 40 color slots maps to the intermediate 24-bit RGB blend of the two EGA colors:
     ```dart
     final r = (col1.red + col2.red) ~/ 2;
     final g = (col1.green + col2.green) ~/ 2;
     final b = (col1.blue + col2.blue) ~/ 2;
     ```
   - Produces a smooth, true 40-color visual presentation without dither artifacts.

### 4.2 Clean GPU integration

Because `PictureSlice` stores standard 32-bit packed RGBA texels, **undithered mode requires zero shader modifications and zero compositor changes**. The selection between authentic dithered and undithered colors is simply a palette translation lookup during slice generation (`PictureSlicer`).

This will be exposed in the video settings dialog (`AvSettingsDialog` / `AgiUserSettings`) as an optional toggle (`sciEnableDithering`, defaulting to true).

## 5. Slicing recipe (SCI)

1. Rasterize the pic into three `Uint8List` buffers, 320×200. Visual holds 40-color palette indices.
2. Translate visual pixels to 32-bit RGBA:
   - If dithering is enabled: resolve `(x ^ y) & 1 ? col2 : col1` -> `EgaColors.rgbaPacked[c]`.
   - If dithering is disabled: resolve directly to the blended 40-color packed RGBA value.
3. For each pixel, `slices[priority[x, y] & 0x0F].set(x, y, packedRgba)` — **no 2× X, no downward column scan**. Empty slices stay `hasVisiblePixels: false`.
4. Upload slices as `ui.Image` (already implemented on `PictureSlice`).
5. Control buffer is kept beside the pic for `OnControl` and the Control inspector; it is not sliced.
6. Compositor: identical Painter's Algorithm loop as `AgiPicturePainter._paintCompositedSlices`, with actor `scaleX` 1.0 instead of 2.0.

`PictureSlice` is already 320×200 RGBA. Parameterize `PictureSlicer.slice` with `DisplayProfile` and `scanControlLines: false` rather than forking a second slice type.

## 6. Views, atlas, and actor sprites

SCI0 EGA views are loops of RLE cels at **native 320 pixels**, with:

- 16-bit width/height
- `displaceX` / `displaceY` (origin = bottom center)
- `clearKey` transparency
- RLE: **low nibble color, high nibble count** (AGI is the reverse)
- Per-view `mirrorBits` (same idea as AGI mirrored loops)

`ViewTextureAtlas` can pack SCI cels without change. Drawing:

- AGI: `scaleX: 2.0` (or −2.0 mirrored) because cels are 160-wide
- SCI: `scaleX: 1.0` (or −1.0 mirrored)

### Actor sprite generalization (`PlayfieldActorSprite`)

`AgiActorSprite` in `lib/ui/widgets/agi_picture_canvas.dart` should be generalized to `PlayfieldActorSprite`:
- **Scale**: `scaleX: 1.0` for SCI vs `2.0` for AGI.
- **Origin offset**: signed `(displaceX, displaceY)` offsets.
- **Actor elevation `z`**: In SCI, actors have a `z` property (vertical offset off the floor). Depth sorting baseline is `sortY = y - z`, while visual canvas position is `(x, y)`.

`add.to.pic` analogue is kernel `AddToPic`: burn the cel into the visual+priority maps, then **re-slice**. That is the same invalidate-and-reslice path AGI already uses.

## 7. Windows, text, and custom mouse cursors

### 7.1 Window overlay pass (avoiding slice invalidation)

In Sierra's original interpreter, dialog windows were drawn directly into the visual buffer, using `kSaveBits` / `kRestoreBits` to save and restore the underlying pixel rectangles.

**Do not burn dialog boxes into the visual buffer and re-slice.** Re-slicing all 16 priority layers on every dialog popup, cursor blink, or input character would destroy performance.

Instead:
- The 16-layer Impeller compositor renders the room background and actor sprites.
- Active SCI windows and dialogs are rendered as an **overlay port pass** on top of the 16 composited slices.
- `kSaveBits` and `kRestoreBits` are emulated by saving/restoring window overlay state, completely avoiding background slice invalidation.

### 7.2 Text & Font Handling: Native Bitmap Fonts vs Hi-Res Overlays

In AGI, text was placed on a rigid 40×25 monospace grid (8×8 pixel cells), which allowed substituting modern hi-res fonts (like SF Mono) by simply centering glyphs within the cells.

SCI text works fundamentally differently:
1. **Proportional Typography**: Text in SCI is proportionally spaced, not monospace. Games ship bitmap **`FONT` resources** (type 7).
2. **Game Script Layout Calculations**: Sierra scripts calculate window dimensions, button sizes, word wrapping, and text input positions by querying character metrics from the active font (`TextWidth`, `CelWide`, etc.).
3. **The Risk of Arbitrary Hi-Res Substitution**: If an arbitrary modern TrueType font (like Arial or SF Pro) were substituted in game dialogs, its character widths would not match the script's calculations. Text would overflow calculated window boundaries, wrap onto unexpected lines, or clip off button borders.

**The Strategy for SCI (see [sci0_fonts_and_text_architecture.md](sci0_fonts_and_text_architecture.md)):**
- **Selective High-Res Substitution**: Feed scaled vector metrics into `SciFont` for **Font 0 (System)** and **Font 1 (Serif)** so game scripts compute exact window sizes and line breaks using the vector font's advance widths. Render these fonts with anti-aliasing directly at Retina resolution on the overlay pass.
- **Authentic Bitmaps for Font $\ge$ 2**: Keep authentic 1-bit bitmap rendering for exotic and decorative fonts (Font $\ge$ 2), ensuring game-specific symbols (e.g. SQ3 alien hieroglyphs, QFG2 Arabic calligraphy) are never corrupted or missing.
- **Outer Engine Chrome**: Modern hi-res vector fonts (SF Pro / SF Mono) continue to be used for the top status bar, menu headers, command prompt history, settings dialogs, and debug inspectors.
- **Authentic Mode Toggle**: Allow players to toggle 100% authentic bitmap rendering for all fonts via video settings.

### 7.3 Custom Mouse Cursors (`CURSOR` resources)

Unlike keyboard-only AGI, SCI0/SCI1 games incorporate mouse interaction.
- **Resource Format**: SCI0 `CURSOR` resources (type 8) are 68 bytes, storing 16×16 pixels with two bitmasks (Mask A and Mask B) that map to black, white, and transparent pixels, plus a hotspot coordinate or center flag.
- **Dynamic Cursors**: Scripts can switch cursors via `kSetCursor` (`SetCursor`) or even use View cels as cursors (e.g. magnifying glasses, crosshairs, icons).
- **Flutter Implementation**:
  - In `GamePlayfieldWidget`, when the mouse is within the playfield, set `MouseRegion(cursor: SystemMouseCursors.none)` to hide the host OS pointer.
  - Draw the active 16×16 cursor texture directly on the canvas overlay at the translated `(x, y)` coordinate.
  - **Benefits**: The cursor inherits integer pixel scaling and CRT scanline/phosphor shaders naturally, behaves identically across macOS, Windows, Linux, and Web, and updates instantaneously without OS cursor lag.

## 8. Display profile (graphics-only view)

```
AGI:  native 160×168, horizontalDouble=true,  picPortTop=8,  bands=AGI table (base 48)
SCI:  native 320×200, horizontalDouble=false, picPortTop=10, bands=SCI table (top 42, 14 bands)
```

Both present a 320×200 EGA playfield to the CRT shader and 4:3 integer scaler. That is why the viewport, shader, and `PictureSlice` size stay shared.

## 9. Workbench

Pic browser should grow a third diagnostic plane (Control) that is a real buffer for SCI and the existing masked-priority view for AGI. Step-replay of vector opcodes is still valid — SCI pics are the same kind of command stream. The browser will also offer an **Undithered (40-color)** preview toggle. View browser should not assume 2× width.

## 10. First verification target

Police Quest 2 rooms: load `RESOURCE.MAP` from `reference_games/police-quest-2/`, decompress a PIC, rasterize three maps, dither, slice, display in the pic browser with Visual / Priority / Control / Undithered toggles. No VM required. If a PQ2 outdoor room occludes ego-sized test sprites at the correct Y bands, the graphics bet is confirmed.
