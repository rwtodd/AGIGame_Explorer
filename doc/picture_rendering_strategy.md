# **Sierra AGI Picture Vector Renderer & Impeller Canvas Architecture**

## **1. Overview & Vision**

In classic Sierra AGI (v2 and v3) engines, graphics were stored as compact vector command scripts (**PICTURE** resources) rather than pre-rendered bitmaps. When a room loaded, the interpreter executed line drawing, pen plotting, and flood fill opcodes onto two distinct low-resolution software buffers:

1. **The Visual Screen (160×168)**: 16-color EGA raster background.
2. **The Priority Screen (160×168)**: 4-bit buffer where values $0\text{–}3$ represented collision/barrier control lines, $4\text{–}14$ represented horizontal depth sorting bands sloping toward the camera, and $15$ represented the base background (sky/horizon).

During classic software rendering, the engine performed a CPU-driven per-pixel test when blitting sprites: a sprite pixel at $(x, y)$ with priority $P$ was only blitted if $\text{PriorityMap}(x, y) \le P$.

### **The Impeller Multi-Layer Slicing Strategy**

Rather than emulating a flat, CPU-driven software framebuffer, this engine decomposes the background into **priority-tagged 320×200 transparent image slices** and leverages Flutter’s **Impeller** GPU rasterizer to composite background slices and dynamic actor sprites using the **Painter's Algorithm**.

```text
┌───────────────────────────────────────────────────────────┐
│              SCENE GRAPH / IMPELLER CANVAS               │
│                                                           │
│  [Layer 15] Background Base Layer (Sky / Horizon)        │
│  [Layer 0]  Background Priority 0 pixels                  │
│  [Layer 1]  Background Priority 1 pixels                  │
│     ...                                                   │
│  [Layer 4]  Background Priority 4 pixels (Ground band 4)  │
│  [Actor]    Ego (Walking at Priority 4, Y=120)            │
│  [Layer 5]  Background Priority 5 pixels                  │
│  [Actor]    Town Guard (Standing at Priority 5, Y=140)    │
│  [Layer 6]  Tree Trunk & Foliage (Priority 6)             │
│     ...                                                   │
│  [Layer 14] Foreground overlay (Archway / Tree Branch)    │
│  [UI Layer] Sierra Status Bar / Dialogue Box / Prompt     │
└─────────────────────────────┬─────────────────────────────┘
                              │
                              ▼  320x200 4:3 Aspect Display
┌───────────────────────────────────────────────────────────┐
│               IMPELLER CRT FRAGMENT SHADER                │
│  - Takes composited scene texture                         │
│  - Integer scaling + Scanlines + Phosphor bloom           │
└───────────────────────────────────────────────────────────┘
```

---

## **2. Core Components & Data Structures**

### **A. Priority Buffer ([`PriorityBuffer`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/domain/priority_buffer.dart))**
- **Memory Representation**: 8-bit `Uint8List` buffer ($160 \times 168 = 26,880\text{ bytes}$).
- **Default State**: Initialized to priority `4` everywhere across the buffer.
- **Values**:
  - `0`: Unconditional barrier (solid obstacle: walls, trees, cliff edges, impassable terrain; always blocks).
  - `1`: Conditional barrier (blocks Ego / certain actors unless allowed by `ignore.blocks`).
  - `2`: Trigger / Alarm line (used by LOGIC scripts to detect room boundaries or events, sets flag 3).
  - `3`: Water barrier (swimming / drowning hazard boundary, sets flag 0).
  - `4..14`: Z-depth bands.
  - `15`: Unconditional background (sky / horizon).
- **Downward Column Scanning (`effectivePriorityAt`)**:
  When an actor sits on a control line ($< 4$), its visual depth is determined by scanning downwards along the same column until finding the first underlying depth band ($\ge 4$). If none is found before reaching the bottom, $15$ is returned.

### **B. Picture Slice ([`PictureSlice`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/domain/picture.dart))**
- Standardized at **320×200** resolution (pixel-doubled horizontally: $x \times 2$ and $x \times 2 + 1$).
- Playfield occupies rows $0\text{–}167$; bottom rows $168\text{–}199$ remain transparent.
- Empty pixels are encoded as RGBA $(0, 0, 0, 0)$.
- `hasVisiblePixels`: Boolean flag allowing the Impeller compositor to skip empty draw calls.
- `toUiImage()`: Asynchronously prepares and caches a Flutter `ui.Image` GPU texture.

### **C. Unified Picture Domain ([`AgiPic`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/domain/picture.dart))**
Encapsulates:
1. `visualPixels`: Flat 160×168 EGA color index buffer.
2. `priorityBuffer`: The `PriorityBuffer` depth & collision map.
3. `slices`: `Map<int, PictureSlice>` containing all 16 priority layers.
4. Diagnostic renderers: `renderFlatVisualRgba()`, `renderPriorityMapRgba()`, `renderControlMapRgba()`.

---

## **3. Vector Opcode Interpretation**

The vector interpreter ([`PicVectorInterpreter`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/picture/pic_vector_interpreter.dart)) processes Sierra PICTURE bytecode streams:

| Opcode | Mnemonic | Description |
| :--- | :--- | :--- |
| `0xF0` | `SET_VISUAL_COLOR` | Sets visual color (`0..15`) and enables visual drawing. |
| `0xF1` | `DISABLE_VISUAL` | Disables visual buffer updates. |
| `0xF2` | `SET_PRIORITY_COLOR` | Sets priority color (`0..15`) and enables priority drawing. |
| `0xF3` | `DISABLE_PRIORITY` | Disables priority buffer updates. |
| `0xF4` | `DRAW_Y_CORNER` | Alternating vertical then horizontal line segments starting from $(x, y)$. |
| `0xF5` | `DRAW_X_CORNER` | Alternating horizontal then vertical line segments starting from $(x, y)$. |
| `0xF6` | `ABSOLUTE_LINES` | Sequence of coordinate pairs $(x_1, y_1), (x_2, y_2)\dots$ drawing lines. |
| `0xF7` | `RELATIVE_LINES` | Initial $(x, y)$ followed by displacement bytes with signed 4-bit nibbles. |
| `0xF8` | `FLOOD_FILL` | 4-way queue-based flood fill bounded to the 160×168 playfield. |
| `0xF9` | `SET_PEN` | Configures pen shape (circle/rectangle), style (solid/splatter), and size ($0\text{–}7$). |
| `0xFA` | `PLOT_PEN` | Plots points using the active pen and pattern. |
| `0xFF` | `END_OF_PICTURE` | Signals picture completion. |

### **A. Bresenham Line Drawing**
Exact integer arithmetic line algorithm matching Sierra AGI and reference interpreters:
```dart
int height = (y2 - y1).abs(), width = (x2 - x1).abs();
int addY = y2 >= y1 ? 1 : -1, addX = x2 >= x1 ? 1 : -1;
int i = width, threshold = width, errX = 0, errY = width ~/ 2;
if (height > width) {
  i = height; threshold = height; errX = height ~/ 2; errY = 0;
}
int x = x1, y = y1;
plotPoint(x, y);
while (i-- > 0) {
  errY += height; if (errY >= threshold) { errY -= threshold; y += addY; }
  errX += width;  if (errX >= threshold) { errX -= threshold; x += addX; }
  plotPoint(x, y);
}
```

### **B. Pens & Splatter Patterns**
- **Rectangles**: Width $= \text{size} + 1$, Height $= \text{size} \times 2 + 1$.
- **Circles**: Uses classic Sierra 8-tier skip/plot matrices ([`CirclePen`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/picture/pic_pen.dart)), with AGI V3 variation ([`V3CirclePen`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/picture/pic_pen.dart)) for size 1 circles.
- **Splatter LFSR**: Pseudo-random texture generator using polynomial $0\text{xB8}$:
  $$\text{patternData} = (\text{patternData} \gg 1) \oplus ((\text{patternData} \ \& \ 1) \neq 0 \ ?\ 0\text{xB8} : 0)$$
  Plotted if $(\text{patternData} \ \& \ 3) == 2$.

---

## **4. Slicing & Impeller Compositing Rules**

### **A. Priority Mapping for Control Lines**
Control lines ($0\text{–}3$) define walkable areas and triggers on the priority map, but represent visible scenery. During slicing in [`PictureSlicer`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/picture/picture_slicer.dart):
- Each pixel's visual color is assigned to the slice corresponding to `effectivePriorityAt(x, y)`.
- This ensures that when an actor walks across a barrier or trigger at depth band $8$, background pixels in that band render beneath foreground scenery at depth band $9$.

### **B. Preventing Bilinear Seam Bleeding**
When rendering adjacent sliced textures, bilinear filtering would interpolate opaque edge pixels with transparent neighbors, causing dark outlines.
- **Resolution**: All layer draw calls configure `Paint()..filterQuality = FilterQuality.none` (Nearest Neighbor).

### **C. Sprite Z-Ordering & Interleaving**
Within [`AgiPicturePainter`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/ui/widgets/agi_picture_canvas.dart):
1. Draw **Priority 15 Background Base** (Sky/Horizon).
2. For priority $P \in [0, 14]$:
   - Draw `PictureSlice[P]` (if `hasVisiblePixels`).
   - Draw active actor sprites with priority $P$, sorted by baseline $Y$ ascending (smaller $Y =$ further back).
3. Draw any sprites assigned to priority $15$.

---

## **5. Diagnostic Workbench Integration**

[`AgiPictureWidget`](file:///Users/rtodd/.gemini/antigravity/worktrees/flutter_agigame/implement_picture_vector_renderer/lib/ui/widgets/agi_picture_canvas.dart) provides instant layer switching:
- **Composited**: Full Impeller Z-order multi-layer rendering.
- **Visual**: Flat 16-color EGA background backdrop.
- **Priority**: Color-coded depth priority map ($0\text{–}14 + 15$).
- **Control**: Isolated view of trigger lines, conditional/unconditional barriers, and water surfaces.
