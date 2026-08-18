# **Text & Picture Compositing Architecture in GPU-Sliced AGI**

## **1. Background & The Vector Text vs. Pixel Slices Tension**

In original Sierra AGI interpreters (1984–1989), the display was driven by a single 320×200 software video framebuffer:
1. **Background Picture**: `draw.pic(n)` drew vector lines and flood fills directly into the framebuffer and priority buffer.
2. **Text / Character Output**: Opcodes like `display(row, col, msg)`, `clear.text.rect(...)`, and `set.text.attribute(...)` wrote character glyphs directly into the video framebuffer.
3. **Actor Sprites**: Animated objects were blitted onto the framebuffer, testing against the priority buffer pixel-by-pixel.

In our modern Flutter engine, picture graphics are decomposed into **16 GPU-accelerated priority slices** (layers $0\text{–}15$) to leverage Flutter Impeller for hardware compositing, while the text layer is maintained as a high-resolution text screen buffer (`AgiTextScreenBuffer`).

This creates a subtle architectural challenge: **where does on-screen text fit into the multi-layer GPU depth stack?**

---

## **2. Two Conflicting Case Studies**

### **Case 1: Space Quest 2 – Room 22 (Rope Swing Chasm)**
- **Scenario**: In Room 22, Roger Wilco swings on a rope across a sheer gorge. LOGIC 22 calls:
  ```text
  display(21, 5, "F6 to release grip on rope")
  ```
- **The Issue**: Room 22's picture contains foreground cliff and rock formations categorized at **Priority 10 and 12** on the left side of the playfield ($x \in [20, 36], y \in [160, 168]$).
- **Failure Mode**: If the text buffer is composited on the base background layer (Priority 4), the subsequent Priority 10/12 foreground rock slices are painted over columns 5–8, clipping out `"F6 to "` and leaving only `"release grip on rope"` visible.

### **Case 2: Police Quest 1 – Room 116 (The Lytton Tribune Newspaper)**
- **Scenario**: In Room 116, the player reads a full-screen newspaper. LOGIC 116 calls:
  ```text
  clear.text.rect(2, 1, 21, 38, 15) // Fills newspaper with white background (bg = 15)
  display(5, 1, "The city of Lytton, |")
  ...
  position(o1, 93, 91)
  draw(o1) // Photo of President Hickle (View 96, cel 0)
  ```
- **The Issue**: The photo of President Hickle is an **actor sprite** (`%o1`), positioned inside the white newspaper area where the right text column has empty space.
- **Failure Mode**: If the entire text overlay (background fills + character glyphs) is composited after all actors, the solid white background fill (`bg = 15`) of the text buffer paints directly over Actor `%o1`, leaving a blank white box instead of the photograph.

---

## **3. The Architectural Decision: Split Background Fills and Text Glyphs (Option A)**

To resolve this conflict without sacrificing either scene element, the text rendering pipeline is split into two distinct passes:

```text
┌───────────────────────────────────────────────────────────┐
│            GPU SCENE COMPOSITING ORDER (IMPELLER)         │
│                                                           │
│  [Layer 0..3] Picture Slices 0..3                         │
│  [Layer 4]    Picture Slice 4 (Base Background Horizon)   │
│  [Text BG]    _paintTextBackgroundFills()                 │
│               - Draws solid rects for cells with bg != 0  │
│               - e.g. White newspaper page (bg=15)         │
│  [Actor o1]   Photo Sprite / Actors at Priority 4..15     │
│  [Layer 5..15] Foreground Picture Slices (Cliffs/Trees)   │
│  [Text FG]    _paintTextGlyphs()                          │
│               - Floats character glyphs & status/prompt   │
│               - e.g. "F6 to release grip on rope"         │
└───────────────────────────────────────────────────────────┘
```

### **How It Operates**
1. **Pass 1: Text Background Fills (`_paintTextBackgroundFills`)**:
   - Executes at **Priority 4** (base playfield layer).
   - Scans `AgiTextScreenBuffer` for cells where `bg != 0` (e.g. white background from `clear.text.rect`).
   - Fills these background rectangles *before* actor sprites (like the newspaper photo) and foreground scenery are composited.
2. **Pass 2: Actor & Scenery Composition**:
   - Priority slices $4\text{–}15$ and actor sprites $0\text{–}15$ are interleaved in authentic Painter's Algorithm order.
   - Actor sprites (e.g., photo `%o1`) cleanly composite on top of the white newspaper background.
3. **Pass 3: Text Glyphs Floating Layer (`_paintTextGlyphs`)**:
   - Executes at the **very top** of the playfield stack (after all picture slices and actor sprites).
   - Draws character glyphs and status/command prompt text.
   - Transparent text cells (`bg == 0`) do not paint background bounding boxes, allowing foreground cliff/rock slices to sit cleanly behind text glyphs without clipping them.

---

## **4. Results & Verification**

- **Space Quest 2 Room 22**: `"F6 to release grip on rope"` floats on top of the Priority 12 cliff slice, fully legible.
- **Police Quest 1 Room 116**: The photo of President Hickle sits cleanly on top of the white newspaper background, with no blank white masking boxes.
- **King's Quest & General Gameplay**: Status line (row 0), command prompt (row 22/23), and all in-game `display()` messages remain crystal clear and unobstructed by background vectors.
