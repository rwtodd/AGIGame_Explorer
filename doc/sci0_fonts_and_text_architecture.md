# Sierra SCI0 Font & Text Architecture

How text, fonts, and dialogs work in Sierra 16-color SCI (SCI0 / SCI01 / SCI1-EGA), and how this Flutter engine supports both authentic bitmap font rendering and modern high-resolution anti-aliased typography.

Companion architecture docs:
- [sci0_graphics_and_priority.md](sci0_graphics_and_priority.md) — 16-layer slicing, window overlay pass, custom cursors
- [sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md) — dual-engine structure and roadmap (§8 status)
- [text_and_picture_compositing_architecture.md](text_and_picture_compositing_architecture.md) — AGI fixed-cell text interleaving

**Implementation order (do not collapse these):**

1. **FONT parser + Font Browser** — authentic 1-bit glyphs, PQ2 `SYSFONT` / `USERFONT` in the workbench. Same pattern as pics/views. No overlay, no vector substitution.
2. **Window overlay pass** — compositor stage (`PlayfieldPainter`). Emulate `SaveBits`/`RestoreBits` as overlay state, never burn into the visual buffer.
3. **Kernel `TextWidth` / `GetLongest`** — VM stage. Scripts size windows from font metrics.
4. **High-res Font 0/1 substitution** — video setting, only after (3). Fonts ≥ 2 stay bitmap forever.

---

## 1. Contrast with AGI Text Handling & Architectural Boundary

### 1.1 Structural Comparison

| Dimension | AGI Text Subsystem | SCI Text Subsystem (`SierraFont`) |
|---|---|---|
| **Underlying Layout** | Rigid **40-column × 25-row grid** composed of fixed $8 \times 8$ pixel character cells in $320 \times 200$ screen space. | Fully proportional typography placed at arbitrary $(x, y)$ pixel coordinates. |
| **Script Interaction** | Scripts have zero font awareness; opcodes position strings exclusively by cell row ($0\text{--}24$) and column ($0\text{--}39$). | Scripts dynamically calculate dialog boxes, input prompt coordinates, word-wrapping breakpoints, and button sizes by querying font metrics (`kTextWidth`, `kTextSize`, `GetLongest`). |
| **Compositing Model** | **Priority Depth Interleaving**: Each character cell queries the underlying `PriorityBuffer` at `(col * 4, row * 8)` so that text layers *between* 16 Impeller GPU priority slices (e.g. behind foreground rock slices in SQ2 Room 22, behind actor sprites in SQ1 Room 65, or under actor photographs in PQ1 Room 116). | **Window Overlay Pass**: Windows and dialog boxes float on an overlay pass (`SaveBits` / `RestoreBits`, Stage 8) that sits on top of the playfield without burning into or reslicing the 16 layers. |
| **Resource Packaging** | No font resources exist in game volumes. Character shapes were hardcoded into the interpreter executable or machine BIOS ROM. | Bundled as standalone `FONT` resources (type 7) containing 1-bit monochrome bitmaps and per-character advance tables. |

### 1.2 Why the AGI Engine Does Not Need Adaptation to `SierraFont`

A natural architectural question arises: *Should AGI be adapted to use `SierraFont` and `SierraFontGlyph` so that both engines share a single unified typography pipeline?*

The answer is **no**, and keeping their rendering paths distinct is the superior design for several reasons:

1. **Fundamental Impedance Mismatch**:
   AGI's `AgiTextScreenBuffer` is not a list of positioned strings; it is a discrete 2D matrix of 1,000 cells (`AgiTextCell`). Adapting AGI to a proportional font pipeline like `SierraFont` would fundamentally violate AGI's cell-grid contract without providing any functional benefit.
2. **Preserving Critical GPU Priority Interleaving**:
   AGI's unique text rendering algorithm (detailed in [text_and_picture_compositing_architecture.md](text_and_picture_compositing_architecture.md)) requires rasterizing cells in lockstep with the 16 GPU priority bands to achieve authentic occlusion with scenery and actor sprites. Forcing AGI through SCI's proportional overlay pass would break this priority-band interleaving.
3. **Zero Regression Risk**:
   The AGI text pipeline is battle-tested against hundreds of room boot and gameplay tests across eight reference AGI titles (KQ1–KQ4, SQ1–SQ2, PQ1, Black Cauldron). Decoupling SCI's font system ensures AGI remains 100% stable.

### 1.3 How High-Resolution Font Substitution Differs Between Engines

Both engines support modern, anti-aliased high-resolution typography, but the mechanisms reflect their architectural differences:

- **In AGI (Fixed-Box Monospace Centering)**:
  Because every character slot is guaranteed to occupy an $8 \times 8$ cell on a 40-column grid, substituting a modern vector font (like SF Mono or Courier) is trivial: the renderer simply centers the anti-aliased vector glyph inside each $8 \times 8$ cell rectangle. The scripts cannot break because grid coordinates never shift.
- **In SCI (Metric Feedback Loop)**:
  Because SCI scripts measure character widths dynamically to size windows, buttons, and word wrapping, substituting a modern vector font requires a closed feedback loop:
  1. Vector font glyphs (Chicago / New York) are measured at nominal size.
  2. Those exact advance widths are supplied to the script engine via `SierraFont.getCharWidth()`.
  3. Game scripts construct window bounding boxes that precisely accommodate the vector metrics.
  4. Flutter's `TextPainter` draws the vector font into the calculated box at Retina resolution with zero clipping.

### 1.4 Single Point of Convergence: Optional Authentic 1984 PC Bitmap Mode

The only place where `SierraFont` could conceptually intersect with AGI is if we ever implement an authentic 1984 IBM PC / CGA ROM display toggle for AGI:
- A built-in 1-bit $8 \times 8$ ROM font (`AgiRomFont implements SierraFont`) could provide original pixel-art glyph bitmaps.
- Even in that case, `AgiTextScreenBuffer` and its 16-band Impeller depth interleaving would remain the execution engine.

---

## 2. Sierra SCI Font Resources (`FONT`, Type 7)

SCI games bundle their fonts in `FONT` resources.

### 2.1 Binary Layout (1-Bit Monochrome Bitmap)

From ScummVM `graphics/scifont.cpp`:

```
Offset  Size     Field
0x00    uint16   Low byte: unused / format flag
0x02    uint16   numChars (typically 128 or 256)
0x04    uint16   fontHeight (vertical advance in pixels, e.g. 12, 9, 18)
0x06    uint16[] charOffsets[numChars] (offset from resource start to glyph data)
```

At each `charOffset`:
```
Offset  Size     Field
+0x00   uint8    charWidth (horizontal pixel width of glyph)
+0x01   uint8    charHeight (pixel height of glyph)
+0x02   bytes    1-bit bitmap data: ((charWidth + 7) / 8) * charHeight bytes
```

Bitmaps are packed MSB-first: `bit 7` of the first byte is the leftmost pixel of the row.

### 2.2 Standard Core Fonts vs Game-Specific Custom Fonts

Original Sierra source headers (`GAME.SH` from *Leisure Suit Larry 2 & 3*, *Space Quest 3*, *King's Quest 4*) reveal a standard system font numbering convention:

| Font ID | Constant Name | Description & Origin |
|---|---|---|
| **0** | `SYSFONT` / `CHICAGO12` | 12px bold sans/slab serif. Based on Susan Kare's Mac OS Chicago font. Used for menu headers, system dialogs, buttons, and standard story text. |
| **1** | `USERFONT` / `NEWYORK12` | 12px proportional serif. Based on Mac OS New York / Times. Used for narrative passages, descriptions, and books. |
| **2** | `GENEVA12` / `SANS_SERIF_12` | 12px clean sans-serif. |
| **3** | `SMALL9` / `SANS_SERIF_10` | 9px–10px condensed sans-serif for compact prompts. |
| **4** | `SERIF9` | 9px small serif. |
| **7** | `HELVETICA18` / `BIG_FAT_18` | 18px large headline / title font. |
| **999** | `GENEVA7` / `SANS_SERIF_8` | 7px–8px tiny font used for notices and status lines. |

#### Game-Specific Customizations
Beyond the core fonts, individual titles introduced specialized thematic fonts:
- **Police Quest 2**: Typewriter / teletype fonts for dispatch logs, police reports, and booking screens.
- **Space Quest 3**: Monospace sci-fi terminal fonts, *Astro Chicken* arcade fonts, and alien hieroglyphs.
- **Quest for Glory 1 & 2**: Arabic calligraphy, medieval blackletter, and fantasy parchment lettering.

### 2.3 Inline Formatting Codes (`|c` and `|f`)

Sierra text strings frequently embed formatting control codes bounded by pipe characters (`|`):
- `|c1|` — Set text color to EGA color 1 (Blue)
- `|c|` — Restore previous / default text color
- `|f1|` — Switch font to Font 1 (Serif)
- `|f0|` — Switch font back to Font 0 (System)

The text renderer must parse these codes on the fly and adjust formatting mid-sentence.

---

## 3. The Selective High-Resolution Substitution Strategy

To achieve crystal-clear, anti-aliased typography without breaking game puzzles or visual motifs, the engine implements a **selective substitution policy**:

> **Substitute high-resolution modern vector fonts for Font 0 and Font 1 only.**  
> **Always use the authentic bitmap font for Font $\ge 2$.**

### 3.1 Why This Boundary is Optimal

1. **Safety**: Font 0 and Font 1 represent >90% of reading text across all SCI games. They use standard Latin/ASCII characters and follow predictable proportional proportions.
2. **Immunity to Broken Puzzles**: Fonts $\ge 2$ frequently contain alien glyphs (SQ3), ornate calligraphy (QFG2), or custom iconography where substituting an off-the-shelf vector font would either fail (missing glyphs) or ruin a visual puzzle.
3. **Best of Both Worlds**: The player enjoys razor-sharp, readable dialogs and menus, while all game-specific artistic fonts retain their authentic Sierra look.

---

## 4. How High-Res Metric Substitution Works

Because the SCI VM queries font metrics dynamically, we can feed the substituted font's metrics directly into the engine calculations:

```
┌────────────────────────────────────────────────────────────┐
│                  Modern Vector Font (e.g. TTF)             │
│  - Nominal 12pt TrueType font scaled to ~12px in 320×200   │
└─────────────────────────────┬──────────────────────────────┘
                              │ Scaled character advance widths
                              ▼
┌────────────────────────────────────────────────────────────┐
│                    SciFont Implementation                  │
│  - getCharWidth(c) returns round(vectorAdvanceWidth)       │
│  - getHeight() returns round(vectorLineHeight)             │
└─────────────────────────────┬──────────────────────────────┘
                              │
                              ▼ Feeds 320×200 coordinates
┌────────────────────────────────────────────────────────────┐
│                SCI Kernel / Script Engine                  │
│  - Calculates box rects & line breaks with vector metrics  │
└─────────────────────────────┬──────────────────────────────┘
                              │ Window & string bounds
                              ▼
┌────────────────────────────────────────────────────────────┐
│                Flutter High-Res Overlay Pass               │
│  - TextPainter renders the vector font at Retina resolution│
│  - Translates |c and |f into a Flutter TextSpan tree       │
│  - Fits 100% pixel-perfect inside the calculated box!      │
└─────────────────────────────┴──────────────────────────────┘
```

### 4.1 Step-by-Step Mechanism

1. **Metric Extraction in 320×200 Terms**:
   - For Font 0 (System): A modern Chicago revival (e.g. Chicago FLF) or clean bold sans-serif (e.g. SF Pro / Inter) is measured at nominal size.
   - For Font 1 (Serif): A modern New York / Times-style font is measured at nominal size.
   - For every character $c \in [0, 255]$, `SciFont.getCharWidth(c)` returns the integer pixel advance in $320 \times 200$ screen space.
2. **Script Execution**:
   - When a room script calls `(Print "Roger Wilco...")`, the kernel's `GetLongest` and `kTextWidth` functions measure words using `SciFont.getCharWidth(c)`.
   - The kernel wraps lines and calculates the window rectangle $(x, y, w, h)$ based on these exact metrics.
3. **High-Res Rendering**:
   - The overlay pass renders the text using Flutter's `TextPainter` with anti-aliasing directly at native device/Retina resolution.
   - Because the window boundary was computed from the vector font's own metrics, the text fits the box with mathematical precision: **no clipped buttons, no text spilling outside borders, and no unintended line breaks**.

### 4.2 Formatting Code Tokenization (`TextSpan` Tree)

When drawing text containing `|c` or `|f` codes, the renderer parses the string into a Flutter `TextSpan` tree:

```dart
TextSpan parseSciFormattedText(String rawText, int defaultColor, int defaultFontId) {
  // Tokenize by '|' codes
  // |c<n>| -> Color(EgaColors.palette[n])
  // |c|   -> restore defaultColor
  // |f0|  -> Font 0 family
  // |f1|  -> Font 1 family
  // Returns structured TextSpan with mixed styles
}
```

---

## 5. Authentic Bitmap Fallback Mode

For players who prefer 100% original pixel-art aesthetics, the engine provides an authentic bitmap rendering path:
- Glyphs from the `FONT` resource are drawn directly as 1-bit monochrome masks into a 320×200 overlay buffer.
- Displayed through the 4:3 integer scaler and CRT scanline shader, giving the exact visual look of a 1988 Tandy / EGA monitor.

---

## 6. User Configuration (`AvSettingsDialog`)

The video/display settings panel will provide a clean selector:

| Setting | Value | Behavior |
|---|---|---|
| **Text Rendering Mode** | `Authentic Bitmap` | All fonts (0..999) rendered using original 1-bit Sierra bitmap glyphs through the CRT shader. |
| | `Modern High-Res (Recommended)` | Fonts 0 & 1 rendered with anti-aliased vector typography matched to script metrics; Fonts $\ge 2$ use authentic bitmaps. |
