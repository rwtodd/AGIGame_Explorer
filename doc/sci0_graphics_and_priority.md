# SCI 16-color graphics and priority slicing

**Headline: the existing 16-layer Impeller compositor still works for SCI0 / SCI01 / SCI1-EGA, and it fits SCI better than it fits AGI.**

This document maps Sierra's 16-color SCI graphics onto the Flutter pipeline already used for AGI (`PictureSlice`, `PictureSlicer`, `AgiPicturePainter`, `ViewTextureAtlas`). Implementation comes later; this is the graphics contract.

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

### 2.1 Native 320×200, three maps

SCI0 pics are vector scripts too, but they paint **three independent 320×200 maps**:

| Map | Role in SCI | AGI analogue |
|---|---|---|
| Visual | What the player sees | Visual buffer (160, then doubled) |
| Priority | Depth 0–15 only | Priority 4–15, minus the control encoding |
| Control | Walkability + script triggers | Priority 0–3 (packed into the same buffer) |

There is **no horizontal doubling**. A SCI pic pixel is already one EGA display pixel. The picture port is 320×190 under a ~10px menu/status strip; the framebuffer is 320×200.

### 2.2 Priority is a pure Z-buffer

A character at priority P is drawn in front of background pixels whose priority is ≤ P, and behind pixels whose priority is greater. SCI Companion's pic editor and ScummVM `GfxView::draw` / `putPixel` implement that test in software. The GPU translation is exactly the AGI slicer:

> Bucket each visual pixel into `slices[priority[x, y]]`. Composite slices 0..15, inserting actors of priority P after slice P.

Because SCI priority is **not** mixed with control, we do **not** need `effectivePriorityAt` / downward column scans when slicing SCI pics. Control-line pixels in AGI were a special case so actors would still occlude correctly while walking on a trigger. SCI paints the tree trunk's depth on the priority map and the "don't walk here" color on the control map separately.

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
| FE extended | — | Palettes, priority table, embedded view |
| FF end | FF end | Then `_screen->dither()` on EGA |

Bresenham/line and flood-fill must match ScummVM `picture.cpp`, not the AGI rasterizer, even though both are "vector pics." Coordinate packing and fill abort rules differ.

## 4. EGA dither palettes

SCI0 visual "colors" are 40 slots × 4 palettes. Each slot is a pair of EGA colors. QFG1 uses two palettes of the same pic for day and night. `DrawPic`'s optional 4th argument selects the palette.

ScummVM stores the pair in the visual buffer during vector draw, then dithers to a 16-color checkerboard at `0xFF`.

**Decision for this engine:** dither to 16 EGA indices **before** slicing, then feed the existing `EgaColors` / `PictureSlice` path. Optional later: an undithered 40-color display (ScummVM `disable_dithering` / `GAMEOPTION_EGA_UNDITHER`). Do not invent a second compositor for dither pairs.

## 5. Slicing recipe (SCI)

1. Rasterize the pic into three `Uint8List` buffers, 320×200. Visual may still hold dither pairs until step 2.
2. Dither visual → 16 EGA indices (checkerboard `(x ^ y) & 1` selecting the pair, matching ScummVM).
3. For each pixel, `slices[priority[x,y]].set(x, y, egaColor)` — **no 2× X**. Empty slices stay `hasVisiblePixels: false`.
4. Upload slices as `ui.Image` (already implemented on `PictureSlice`).
5. Control buffer is kept beside the pic for `OnControl` and the Control inspector; it is not sliced.
6. Compositor: identical Painter's Algorithm loop as `AgiPicturePainter._paintCompositedSlices`, with actor `scaleX` 1.0 instead of 2.0.

`PictureSlice` is already 320×200 RGBA. The AGI-specific part is `PictureSlicer`'s 160 source + doubling. Parameterize it with a `DisplayProfile` (see the dual-engine doc) rather than forking a second slice type.

## 6. Views / atlas

SCI0 EGA views are loops of RLE cels at **native 320 pixels**, with:

- 16-bit width/height
- `displaceX` / `displaceY` (origin = bottom center)
- `clearKey` transparency
- RLE: **low nibble color, high nibble count** (AGI is the reverse)
- Per-view `mirrorBits` (same idea as AGI mirrored loops)

`ViewTextureAtlas` can pack SCI cels without change. Drawing:

- AGI: `scaleX: 2.0` (or −2.0 mirrored) because cels are 160-wide
- SCI: `scaleX: 1.0` (or −1.0 mirrored)

Do not pixel-double SCI cels. QFG2 (SCI1 EGA) may apply an 8×16 EGA mapping table; SCI0 ignores `paletteOffset`.

`add.to.pic` analogue is kernel `AddToPic`: burn the cel into the visual+priority maps, then **re-slice**. That is the same invalidate-and-reslice path AGI already uses.

## 7. Things the AGI compositor does not do yet

These are SCI graphics features, not blockers for "does slicing work?":

| Feature | Notes |
|---|---|
| Picture transitions | Iris, wipe, dissolve (`DrawPic` showStyle). AGI has almost none. Can start with instant (`showStyle = -1`). |
| Pic overlay | `DrawPic(..., clearPic: false)` composites vectors onto existing maps; re-slice after. |
| Ports / windows | Dialogs are clipped ports, not AGI `print` boxes. Status/menu live in the menu port above the picture port. |
| Embedded views in pics | `FE 07` (more common in SCI1 EGA). Rasterize into the visual/priority maps, then slice. |
| Text in the playfield | SCI uses FONT resources + ports, not AGI 8×8 cells. The "priority-matched text interleaving" in `doc/text_and_picture_compositing_architecture.md` is AGI-specific; SCI windows usually sit in the window-manager port *above* the pic. |

None of these require abandoning 16-layer slices.

## 8. Display profile (graphics-only view)

```
AGI:  native 160×168, horizontalDouble=true,  picPortTop=8,  bands=AGI table (base 48)
SCI:  native 320×200, horizontalDouble=false, picPortTop=10, bands=SCI table (top 42, 14 bands)
```

Both present a 320×200 EGA playfield to the CRT shader and 4:3 integer scaler. That is why the viewport, shader, and `PictureSlice` size can stay shared.

## 9. Workbench

Pic browser should grow a third diagnostic plane (Control) that is a real buffer for SCI and the existing masked-priority view for AGI. Step-replay of vector opcodes is still valid — SCI pics are the same kind of command stream. View browser should not assume 2× width.

## 10. First verification target

Police Quest 2 rooms: load `RESOURCE.MAP`, decompress a PIC, rasterize three maps, dither, slice, display in the pic browser with Visual / Priority / Control toggles. No VM required. If a PQ2 outdoor room occludes ego-sized test sprites at the correct Y bands, the graphics bet is confirmed.
